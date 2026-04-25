import Foundation
import FirebaseFirestore

// MARK: - FirestoreService
//
// Admin-side Firestore write/read service.
//
// Firestore schema (flat):
//   /collections/{collectionId}      ← name, icon, type  (метаданные коллекции)
//   /cardSets/{setId}                ← collectionId, name, cefrLevel, accessTier, description
//       /cards/{cardId}              ← setId, en, translations, sampleEN, sampleTranslations, …
//   /pairsSets/{setId}               ← collectionId, title, cefrLevel, accessTier, items[] (embedded)
//
// Плоская схема выбрана намеренно: главный запрос iOS-приложения —
//   "все сеты до уровня пользователя" — работает в одно обращение:
//   db.collection("cardSets").whereField("cefrLevel", in: levels)
//
// Admin-only поля (isSynced, deployStatus) намеренно НЕ пишутся в Firestore.
//
// ⚠️  Требует GoogleService-Info.plist в таргете и FirebaseApp.configure().

struct FirestoreService {

    private var db: Firestore { Firestore.firestore() }

    // MARK: - Deploy CardSet

    /// Записывает метаданные коллекции, сет и все карточки в Firestore.
    /// Использует один WriteBatch (лимит Firestore: 500 операций).
    /// Для сетов с > 498 карточками выбрасывает FirestoreServiceError.tooManyCards.
    func deployCardSet(
        collection: FSCollection,
        set: FSCardSet,
        cards: [FSCard]
    ) async throws {
        guard cards.count <= 498 else {
            throw FirestoreServiceError.tooManyCards(cards.count)
        }

        let batch   = db.batch()
        let collRef = db.collection("collections").document(collection.id)
        let setRef  = db.collection("cardSets").document(set.id)

        // Удаляем из Firestore карточки, которых больше нет в локальном сете.
        // Это необходимо, т.к. batch.setData записывает только текущие карточки,
        // а удалённые из Admin остаются в Firestore subcollection.
        let existingSnap = try await setRef.collection("cards").getDocuments()
        let localCardIds = Set(cards.map { $0.id })
        for doc in existingSnap.documents where !localCardIds.contains(doc.documentID) {
            batch.deleteDocument(doc.reference)
        }
        let deletedCount = existingSnap.documents.filter { !localCardIds.contains($0.documentID) }.count

        batch.setData(collectionDoc(collection), forDocument: collRef, merge: true)
        batch.setData(cardSetDoc(set), forDocument: setRef)
        for card in cards {
            let cardRef = setRef.collection("cards").document(card.id)
            batch.setData(cardDoc(card), forDocument: cardRef)
        }

        try await batch.commit()
        log("[Firestore] Deployed CardSet '\(set.name)' (\(cards.count) cards, \(deletedCount) deleted)", level: .info)
    }

    // MARK: - Deploy PairsSet

    /// Записывает метаданные коллекции и сет (items встроены) в Firestore.
    func deployPairsSet(
        collection: FSCollection,
        set: FSPairsSet
    ) async throws {
        let batch   = db.batch()
        let collRef = db.collection("collections").document(collection.id)
        let setRef  = db.collection("pairsSets").document(set.id)

        batch.setData(collectionDoc(collection), forDocument: collRef, merge: true)
        batch.setData(pairsSetDoc(set), forDocument: setRef)

        try await batch.commit()
        log("[Firestore] Deployed PairsSet '\(set.title ?? set.id)' (\(set.items.count) pairs)", level: .info)
    }

    // MARK: - Fetch (для iOS sync)

    func fetchCollections() async throws -> [[String: Any]] {
        let snap = try await db.collection("collections").getDocuments()
        return snap.documents.map { $0.data() }
    }

    /// Загружает все CardSet с cefrLevel из переданного списка.
    func fetchCardSets(levels: [String]) async throws -> [[String: Any]] {
        guard !levels.isEmpty else { return [] }
        let snap = try await db.collection("cardSets")
            .whereField("cefrLevel", in: levels)
            .getDocuments()
        return snap.documents.map { $0.data() }
    }

    func fetchCards(setId: String) async throws -> [[String: Any]] {
        let snap = try await db
            .collection("cardSets").document(setId)
            .collection("cards").getDocuments()
        return snap.documents.map { $0.data() }
    }

    /// Загружает все PairsSet с cefrLevel из переданного списка.
    func fetchPairsSets(levels: [String]) async throws -> [[String: Any]] {
        guard !levels.isEmpty else { return [] }
        let snap = try await db.collection("pairsSets")
            .whereField("cefrLevel", in: levels)
            .getDocuments()
        return snap.documents.map { $0.data() }
    }

    // MARK: - Document builders
    // Admin-only поля (isSynced, deployStatus) намеренно исключены.

    private func collectionDoc(_ c: FSCollection) -> [String: Any] {
        var d: [String: Any] = [
            "id":        c.id,
            "name":      c.name,
            "type":      c.type.rawValue,
            "updatedAt": Timestamp(date: c.updatedAt),
            "createdAt": Timestamp(date: c.createdAt)
        ]
        if let icon = c.icon { d["icon"] = icon }
        return d
    }

    private func cardSetDoc(_ s: FSCardSet) -> [String: Any] {
        var d: [String: Any] = [
            "id":           s.id,
            "collectionId": s.collectionId,
            "name":         s.name,
            "cefrLevel":    s.cefrLevel.rawValue,
            "accessTier":   s.accessTier.rawValue,
            "updatedAt":    Timestamp(date: s.updatedAt),
            "createdAt":    Timestamp(date: s.createdAt)
        ]
        if let desc = s.description { d["description"] = desc }
        return d
    }

    private func cardDoc(_ card: FSCard) -> [String: Any] {
        [
            "id":                 card.id,
            "setId":              card.setId,
            "en":                 card.en,
            "transcription":      card.transcription,
            "translations":       card.translations,
            "sampleEN":           card.sampleEN,
            "sampleTranslations": card.sampleTranslations,
            "tag":                card.tag,
            "updatedAt":          Timestamp(date: card.updatedAt),
            "createdAt":          Timestamp(date: card.createdAt)
        ]
    }

    private func pairsSetDoc(_ s: FSPairsSet) -> [String: Any] {
        var d: [String: Any] = [
            "id":           s.id,
            "collectionId": s.collectionId,
            "cefrLevel":    s.cefrLevel.rawValue,
            "accessTier":   s.accessTier.rawValue,
            "items":        s.items.map { pairDoc($0) },
            "updatedAt":    Timestamp(date: s.updatedAt),
            "createdAt":    Timestamp(date: s.createdAt)
        ]
        if let title = s.title       { d["title"]       = title }
        if let desc  = s.description { d["description"] = desc  }
        return d
    }

    private func pairDoc(_ p: FSPair) -> [String: Any] {
        var d: [String: Any] = [
            "id":          p.id,
            "tag":         p.tag,
            "displayMode": p.displayMode.rawValue
        ]
        if let v = p.left        { d["left"]        = v }
        if let v = p.right       { d["right"]       = v }
        if let v = p.description { d["description"] = v }
        if let v = p.sample      { d["sample"]      = v }
        if let v = p.leftTitle   { d["leftTitle"]   = v }
        if let v = p.rightTitle  { d["rightTitle"]  = v }
        return d
    }
}

// MARK: - FirestoreServiceError

enum FirestoreServiceError: LocalizedError {
    case tooManyCards(Int)

    var errorDescription: String? {
        switch self {
        case .tooManyCards(let count):
            return "Too many cards (\(count)) for a single deploy batch. Max 498 per set."
        }
    }
}
