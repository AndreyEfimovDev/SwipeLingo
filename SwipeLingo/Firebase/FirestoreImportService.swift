import Foundation
import SwiftData
import Network
import FirebaseCore
import FirebaseFirestore

// MARK: - FirestoreImportService
//
// Syncs developer-curated content from Firestore into SwiftData.
//
// syncFromFirestore(into:language:upToLevel:forceFullSync:) — async, fetches content from Firestore.
//   • Idempotent: uses firestoreId for upsert matching.
//   • Preserves user SRS state on card updates.
//   • Filters by CEFR level — only loads sets ≤ upToLevel.
//   • Cleans up local sets above the user's level and empty collections.
//   • Delta sync: queries only sets with updatedAt > lastSyncAt (stored in UserDefaults).
//     Pass forceFullSync: true (e.g., on level change) to ignore lastSyncAt and re-download everything.
//   • Requires composite Firestore indexes on (cefrLevel, updatedAt) for cardSets & pairsSets collections.
//
// ⚠️  Requires FirebaseApp.configure() and GoogleService-Info.plist. Skips gracefully if absent.

struct FirestoreImportService {

    // MARK: - Sync from Firestore (real content)
    //
    // Плоская схема Firestore:
    //   /collections/{id}       ← метаданные (name, icon, type)
    //   /cardSets/{id}          ← collectionId, cefrLevel, …
    //       /cards/{id}         ← карточки (вложены в сет)
    //   /pairsSets/{id}         ← collectionId, cefrLevel, items[]
    //
    // Загружаются только сеты уровня ≤ upToLevel (уровень пользователя из UserProfile).
    // Upsert: сопоставление SwiftData ↔ Firestore по полю firestoreId.
    // SRS-состояние карточек не перезаписывается при обновлении.

    // UserDefaults key where the last successful sync timestamp is stored.
    private static let lastSyncAtKey = "firestoreLastSyncAt"

    // MARK: - Network check

    /// Быстрая проверка наличия сетевого соединения через NWPathMonitor.
    /// Firestore offline-режим молча возвращает пустые результаты из кеша —
    /// без этой проверки sync выглядит успешным даже без интернета.
    private func isNetworkReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: .global(qos: .utility))
        }
    }

    func syncFromFirestore(
        into context: ModelContext,
        language: NativeLanguage,
        upToLevel: CEFRLevel = .c2,
        forceFullSync: Bool = false
    ) async {
        guard FirebaseApp.app() != nil else {
            log("[Firestore] Firebase not configured — skipping content sync", level: .warning)
            return
        }

        guard await isNetworkReachable() else {
            log("[Firestore] No network — skipping sync", level: .warning)
            await MainActor.run { ErrorManager.shared.showBanner(AppNetworkError.noConnection.message) }
            return
        }

        let db     = Firestore.firestore()
        let levels = upToLevel.andBelow.map { $0.rawValue }   // ["a1", "a2", …, upToLevel]

        // Delta sync: only fetch sets updated after the last successful sync.
        // forceFullSync = true resets the baseline (used when CEFR level changes — need all content).
        let lastSyncAt: Date = forceFullSync
            ? .distantPast
            : (UserDefaults.standard.object(forKey: Self.lastSyncAtKey) as? Date ?? .distantPast)
        let isDelta = lastSyncAt > .distantPast

        log("[Firestore] Sync started (up to \(upToLevel.displayCode), \(levels.count) levels, \(isDelta ? "delta since \(lastSyncAt)" : "full"))", level: .info)

        do {
            // ── 1. Pre-load SwiftData caches ──────────────────────────────
            let allCollections = context.fetchWithErrorHandling(
                FetchDescriptor<Collection>(predicate: #Predicate { !$0.isUserCreated })
            )
            let allSets = context.fetchWithErrorHandling(
                FetchDescriptor<CardSet>(predicate: #Predicate { !$0.isUserCreated })
            )
            let allPairsSets = context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())

            var collectionsByFsId: [String: Collection] = Dictionary(
                uniqueKeysWithValues: allCollections.compactMap { c in c.firestoreId.map { ($0, c) } }
            )
            var cardSetsByFsId: [String: CardSet] = Dictionary(
                uniqueKeysWithValues: allSets.compactMap { s in s.firestoreId.map { ($0, s) } }
            )
            var pairsSetsByFsId: [String: PairsSet] = Dictionary(
                uniqueKeysWithValues: allPairsSets.compactMap { s in s.firestoreId.map { ($0, s) } }
            )

            // ── 2. Collections (метаданные — все, без фильтра по уровню) ──
            let collSnap = try await db.collection("collections").getDocuments()
            for doc in collSnap.documents {
                let d = doc.data()
                guard let fsId    = d["id"]   as? String,
                      let name    = d["name"] as? String,
                      let typeRaw = d["type"] as? String,
                      let type    = CollectionType(rawValue: typeRaw)
                else { continue }

                if let existing = collectionsByFsId[fsId] {
                    existing.name      = name
                    existing.icon      = d["icon"] as? String
                    existing.updatedAt = (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                } else {
                    let c = Collection(
                        name: name,
                        icon: d["icon"] as? String,
                        isOwned: true, isUserCreated: false,
                        type: type,
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? .now
                    )
                    c.firestoreId = fsId
                    context.insert(c)
                    collectionsByFsId[fsId] = c
                }
            }

            // UUID коллекций, у которых есть хотя бы один загруженный сет
            var loadedCollectionIds = Set<UUID>()

            // ── 3. CardSets — фильтр по уровню пользователя + delta по updatedAt ─
            // Delta: whereField("updatedAt", isGreaterThan:) + whereField("cefrLevel", in:)
            // требует composite index в Firestore Console:
            //   Collection: cardSets  Fields: cefrLevel ASC, updatedAt ASC
            // try? — если delta query падает (индекс не создан), возвращает nil → full fallback.
            // try в catch пробрасывается во внешний do-catch, поэтому используем try? здесь.
            let cardSetsBaseQuery = db.collection("cardSets").whereField("cefrLevel", in: levels)
            let setSnap: QuerySnapshot
            if isDelta,
               let deltaSnap = try? await cardSetsBaseQuery
                   .whereField("updatedAt", isGreaterThan: Timestamp(date: lastSyncAt))
                   .getDocuments() {
                setSnap = deltaSnap
                log("[Firestore] CardSets fetched: \(setSnap.documents.count) (delta)", level: .info)
            } else {
                if isDelta { log("[Firestore] CardSets delta failed (index missing?), using full", level: .warning) }
                setSnap = try await cardSetsBaseQuery.getDocuments()
                log("[Firestore] CardSets fetched: \(setSnap.documents.count) (full\(isDelta ? " fallback" : ""))", level: .info)
            }

            // ── 4. Cards — параллельная загрузка всех subcollections ───────
            // Раньше каждый сет загружался последовательно: N сетов = N сетевых вызовов.
            // Теперь все /cardSets/{id}/cards запросы выполняются параллельно → O(1) по времени.
            let setFsIds = setSnap.documents.compactMap { $0.data()["id"] as? String }
            let cardSnapsBySetId: [String: QuerySnapshot] = try await withThrowingTaskGroup(
                of: (String, QuerySnapshot).self
            ) { group in
                for setFsId in setFsIds {
                    group.addTask {
                        let snap = try await db
                            .collection("cardSets").document(setFsId)
                            .collection("cards").getDocuments()
                        return (setFsId, snap)
                    }
                }
                var result: [String: QuerySnapshot] = [:]
                for try await (id, snap) in group { result[id] = snap }
                return result
            }
            log("[Firestore] Card subcollections fetched: \(cardSnapsBySetId.count)", level: .info)

            // Upsert CardSets + Cards в SwiftData (последовательно — ModelContext не thread-safe)
            for setDoc in setSnap.documents {
                let sd = setDoc.data()
                guard let setFsId      = sd["id"]           as? String,
                      let setName      = sd["name"]         as? String,
                      let collFsId     = sd["collectionId"] as? String,
                      let sdCollection = collectionsByFsId[collFsId]
                else { continue }

                let cefrLevel  = (sd["cefrLevel"]  as? String).flatMap { CEFRLevel(rawValue: $0)  } ?? .b2
                let accessTier = (sd["accessTier"] as? String).flatMap { AccessTier(rawValue: $0) } ?? .free

                let sdSet: CardSet
                if let existing = cardSetsByFsId[setFsId] {
                    existing.name           = setName
                    existing.cefrLevel      = cefrLevel
                    existing.accessTier     = accessTier
                    existing.setDescription = sd["description"] as? String
                    existing.updatedAt      = (sd["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                    sdSet = existing
                } else {
                    let s = CardSet(
                        name: setName,
                        collectionId: sdCollection.id,
                        level: cefrLevel,
                        isUserCreated: false,
                        accessTier: accessTier,
                        setDescription: sd["description"] as? String,
                        updatedAt: (sd["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                        createdAt: (sd["createdAt"] as? Timestamp)?.dateValue() ?? .now
                    )
                    s.firestoreId = setFsId
                    context.insert(s)
                    cardSetsByFsId[setFsId] = s
                    sdSet = s
                }
                loadedCollectionIds.insert(sdCollection.id)

                // Cards — используем уже загруженный snapshot
                guard let cardSnap = cardSnapsBySetId[setFsId] else { continue }

                let sdSetId = sdSet.id
                let existingCards = context.fetchWithErrorHandling(
                    FetchDescriptor<Card>(predicate: #Predicate { $0.setId == sdSetId })
                )
                var cardsByFsId: [String: Card] = Dictionary(
                    uniqueKeysWithValues: existingCards.compactMap { c in c.firestoreId.map { ($0, c) } }
                )

                for cardDoc in cardSnap.documents {
                    let cd = cardDoc.data()
                    guard let cardFsId = cd["id"] as? String,
                          let en       = cd["en"] as? String
                    else { continue }

                    let translations       = cd["translations"]       as? [String: String]   ?? [:]
                    let sampleEN           = cd["sampleEN"]           as? [String]           ?? []
                    let sampleTranslations = cd["sampleTranslations"] as? [String: [String]] ?? [:]
                    let transcription      = cd["transcription"]      as? String             ?? ""
                    let item               = translations[language.langId] ?? ""
                    let sampleItem         = sampleTranslations[language.langId] ?? []

                    if let existing = cardsByFsId[cardFsId] {
                        // Обновляем контент, SRS-состояние не трогаем
                        existing.en                = en
                        existing.item              = item
                        existing.sampleEN          = sampleEN
                        existing.sampleItem        = sampleItem
                        existing.dictTranscription = transcription
                        existing.updatedAt         = (cd["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                    } else {
                        let c = Card(
                            en: en, item: item,
                            sampleEN: sampleEN, sampleItem: sampleItem,
                            dictTranscription: transcription,
                            createdAt: (cd["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                            updatedAt: (cd["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                            setId: sdSet.id
                        )
                        c.firestoreId = cardFsId
                        context.insert(c)
                        cardsByFsId[cardFsId] = c
                    }
                }
            }

            // ── 5. PairsSets — фильтр по уровню пользователя + delta по updatedAt ─
            // Delta: composite index в Firestore Console:
            //   Collection: pairsSets  Fields: cefrLevel ASC, updatedAt ASC
            let pairsSetsBaseQuery = db.collection("pairsSets").whereField("cefrLevel", in: levels)
            let pairsSnap: QuerySnapshot
            if isDelta,
               let deltaSnap = try? await pairsSetsBaseQuery
                   .whereField("updatedAt", isGreaterThan: Timestamp(date: lastSyncAt))
                   .getDocuments() {
                pairsSnap = deltaSnap
                log("[Firestore] PairsSets fetched: \(pairsSnap.documents.count) (delta)", level: .info)
            } else {
                if isDelta { log("[Firestore] PairsSets delta failed (index missing?), using full", level: .warning) }
                pairsSnap = try await pairsSetsBaseQuery.getDocuments()
                log("[Firestore] PairsSets fetched: \(pairsSnap.documents.count) (full\(isDelta ? " fallback" : ""))", level: .info)
            }

            for pairsDoc in pairsSnap.documents {
                let pd = pairsDoc.data()
                guard let pairsFsId  = pd["id"]           as? String,
                      let collFsId   = pd["collectionId"] as? String,
                      let sdColl     = collectionsByFsId[collFsId]
                else { continue }

                let cefrLevel  = (pd["cefrLevel"]  as? String).flatMap { CEFRLevel(rawValue: $0)  } ?? .b2
                let accessTier = (pd["accessTier"] as? String).flatMap { AccessTier(rawValue: $0) } ?? .free
                let pairs      = (pd["items"] as? [[String: Any]] ?? []).compactMap { parsePair(from: $0) }

                if let existing = pairsSetsByFsId[pairsFsId] {
                    existing.title          = pd["title"]       as? String
                    existing.setDescription = pd["description"] as? String
                    existing.cefrLevel      = cefrLevel
                    existing.accessTier     = accessTier
                    existing.items          = pairs
                    existing.updatedAt      = (pd["updatedAt"] as? Timestamp)?.dateValue() ?? .now
                    existing.collectionId   = sdColl.id
                } else {
                    let ps = PairsSet(
                        title:          pd["title"]       as? String,
                        setDescription: pd["description"] as? String,
                        cefrLevel: cefrLevel, accessTier: accessTier,
                        deployStatus: .live,
                        items: pairs,
                        collectionId: sdColl.id,
                        updatedAt: (pd["updatedAt"] as? Timestamp)?.dateValue() ?? .now,
                        createdAt: (pd["createdAt"] as? Timestamp)?.dateValue() ?? .now
                    )
                    ps.firestoreId = pairsFsId
                    context.insert(ps)
                    pairsSetsByFsId[pairsFsId] = ps
                }
                loadedCollectionIds.insert(sdColl.id)
            }

            // ── 6. (удалено) Раньше здесь удалялись Firestore-сеты выше уровня пользователя.
            // Теперь используется фильтрация на стороне UI: сеты хранятся локально для всех
            // загруженных уровней, показываются только те что ≤ userLevel.
            // Плюсы: смена уровня мгновенная (без sync), при повышении уровня данные уже есть.

            // ── 7. Cleanup: удаляем коллекции без единого сета в SwiftData ──────
            // loadedCollectionIds содержит только коллекции из текущего sync-запроса.
            // Дополняем коллекциями у которых в SwiftData уже есть сеты любого уровня
            // (сеты теперь не удаляются при смене уровня — хранятся и фильтруются в UI).
            let freshSets  = context.fetchWithErrorHandling(FetchDescriptor<CardSet>(predicate: #Predicate { !$0.isUserCreated }))
            let freshPairs = context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())
            freshSets.forEach  { loadedCollectionIds.insert($0.collectionId) }
            freshPairs.forEach { if let id = $0.collectionId { loadedCollectionIds.insert(id) } }

            // Используем СВЕЖИЙ fetch (не allCollections — снапшот до синка):
            // шаг 2 мог добавить новые коллекции в этом же цикле синка,
            // которых нет в allCollections.
            let currentCollections = context.fetchWithErrorHandling(
                FetchDescriptor<Collection>(predicate: #Predicate { !$0.isUserCreated })
            )
            for c in currentCollections {
                guard c.firestoreId != nil else { continue }
                if !loadedCollectionIds.contains(c.id) {
                    context.delete(c)
                    log("[Firestore] Removed empty Collection '\(c.name)'", level: .info)
                }
            }

            context.saveWithErrorHandling()

            // Сохраняем метку времени успешного синка — следующий запрос будет delta.
            UserDefaults.standard.set(Date.now, forKey: Self.lastSyncAtKey)
            log("[Firestore] Sync complete", level: .info)

        } catch {
            log("[Firestore] Sync failed: \(error)", level: .error)
            let nsError = error as NSError
            let isOffline = nsError.domain == NSURLErrorDomain
                         && nsError.code   == NSURLErrorNotConnectedToInternet
            let message = isOffline
                ? AppNetworkError.noConnection.message
                : AppNetworkError.serverError.message
            await MainActor.run { ErrorManager.shared.showBanner(message) }
        }
    }

    // MARK: - Parse Pair from Firestore dict

    private func parsePair(from d: [String: Any]) -> Pair? {
        guard let idStr = d["id"] as? String,
              let id = UUID(uuidString: idStr) ?? Optional(UUID())
        else { return nil }

        let displayModeRaw = d["displayMode"] as? String ?? ""
        let displayMode = DisplayMode(rawValue: displayModeRaw) ?? .parallel

        return Pair(
            id:          id,
            left:        d["left"]        as? String,
            right:       d["right"]       as? String,
            description: d["description"] as? String,
            sample:      d["sample"]      as? String,
            tag:         d["tag"]         as? String ?? "",
            leftTitle:   d["leftTitle"]   as? String,
            rightTitle:  d["rightTitle"]  as? String,
            displayMode: displayMode
        )
    }

    // MARK: - FSCard → Card conversion

    /// Converts an FSCard (Firestore model) into a SwiftData Card.
    func card(from fsCard: FSCard, swiftDataSetId: UUID, language: NativeLanguage) -> Card {
        Card(
            en:                fsCard.en,
            item:              fsCard.translation(for: language),
            sampleEN:          fsCard.sampleEN,
            sampleItem:        fsCard.sampleTranslation(for: language),
            dictTranscription: fsCard.transcription,
            setId:             swiftDataSetId
        )
    }
}
