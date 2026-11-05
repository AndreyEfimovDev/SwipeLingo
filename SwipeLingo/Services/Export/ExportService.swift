import Foundation
import SwiftData

// MARK: - ExportService
// Обрабатывает JSON-экспорт и импорт пользовательских карточек и SRS-состояния pairs.
// Cards: полный контент (только пользовательские сеты).
// Pairs: только SRS-состояние — контент приходит из Firestore и синхронизируется автоматически.

final class ExportService {

    // MARK: - Export

    /// Экспортирует карточки своего аккаунта и SRS-состояние pairs во временный JSON-файл.
    /// - Parameter firebaseUID: аккаунт, чьи сеты попадают в бэкап (см. `buildCardSetsExport`).
    func exportAll(from context: ModelContext, firebaseUID: String) -> Result<URL, Error> {
        let cardSets = buildCardSetsExport(from: context, firebaseUID: firebaseUID)
        let pairsSRS = buildPairsSRSExport(from: context)
        let backup   = SwipeLingoBackup(cardSets: cardSets, pairsSRS: pairsSRS)
        return writeToTemp(backup)
    }

    /// Сеты пользователя только из СВОИХ коллекций (см. `Collection.isMine(firebaseUID:)`) — «бэкап =
    /// то, что видно на экране». Сеты другого Firebase-аккаунта на том же iCloud в UI скрыты; попади они
    /// в бэкап, восстановление на чистом устройстве присвоило бы их текущему аккаунту — слияние
    /// аккаунтов через файл, которого приложение избегает и в дедупе.
    private func buildCardSetsExport(from context: ModelContext, firebaseUID: String) -> [BackupCardSet] {
        let collections = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
        let ownCollectionIds = Set(
            collections.filter { $0.isUserCreated && $0.isMine(firebaseUID: firebaseUID) }.map(\.id)
        )
        let sets = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
            .filter { $0.isUserCreated && !$0.isSoftDeleted && ownCollectionIds.contains($0.collectionId) }

        return sets.map { set in
            let collection = collections.first { $0.id == set.collectionId }
            let setId = set.id
            let cards = context.fetchWithErrorHandling(
                FetchDescriptor<Card>(predicate: #Predicate { $0.setId == setId })
            )
            .filter { $0.status != .deleted }
            .map { c in
                BackupCard(
                    id:            c.id,
                    en:            c.en,
                    item:          c.item,
                    sampleEN:      c.sampleEN,
                    sampleItem:    c.sampleItem,
                    userSampleEN:  c.userSampleEN,
                    userSampleItem: c.userSampleItem,
                    status:        c.status.rawValue,
                    isFavorite:    c.isFavorite,
                    tags:          c.tags,
                    synonyms:      c.synonyms,
                    level:         c.level,
                    easeFactor:    c.easeFactor,
                    interval:      c.interval,
                    repetitions:   c.repetitions,
                    dueDate:       c.dueDate,
                    lastReviewed:  c.lastReviewed,
                    createdAt:     c.createdAt
                )
            }

            return BackupCardSet(
                id:             set.id,
                name:           set.name,
                isInbox:        collection?.isInbox ?? false,
                collectionName: collection?.name ?? "",
                collectionIcon: collection?.icon,
                level:          set.level,
                setDescription: set.setDescription,
                createdAt:      set.createdAt,
                cards:          cards
            )
        }
    }

    private func buildPairsSRSExport(from context: ModelContext) -> [BackupPairsSRS] {
        context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())
            .filter { !$0.isSoftDeleted && $0.repetitions > 0 }
            .map { s in
                BackupPairsSRS(
                    id:          s.id,
                    firestoreId: s.firestoreId,
                    title:       s.title,
                    cefrLevel:   s.cefrLevelRaw,
                    dueDate:     s.dueDate,
                    interval:    s.interval,
                    easeFactor:  s.easeFactor,
                    repetitions: s.repetitions,
                    lastReviewed: s.lastReviewed
                )
            }
    }

    private func writeToTemp(_ backup: SwipeLingoBackup) -> Result<URL, Error> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(backup)
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd_HH-mm"
            let name = "SwipeLingo_backup_\(fmt.string(from: .now)).json"
            let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: url)
            log("Exported \(backup.cardSets.count) sets, \(backup.pairsSRS.count) pairs SRS → \(name)", level: .info)
            return .success(url)
        } catch {
            log("Export failed: \(error)", level: .error)
            return .failure(error)
        }
    }

    // MARK: - Import

    struct ImportResult {
        let newSets: Int
        let newCards: Int
        let pairsSRSRestored: Int
    }

    func importBackup(from url: URL, into context: ModelContext, firebaseUID: String) -> ImportResult {
        do {
            let data    = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup  = try decoder.decode(SwipeLingoBackup.self, from: data)

            let (sets, cards) = restoreCardSets(backup.cardSets, into: context, firebaseUID: firebaseUID)
            let pairsCount    = restorePairsSRS(backup.pairsSRS, into: context)
            try context.save()

            let result = ImportResult(newSets: sets, newCards: cards, pairsSRSRestored: pairsCount)
            log("Imported: \(sets) sets, \(cards) cards, \(pairsCount) pairs SRS", level: .info)
            return result
        } catch {
            log("Import failed: \(error)", level: .error)
            return ImportResult(newSets: 0, newCards: 0, pairsSRSRestored: 0)
        }
    }

    /// Восстанавливает сеты и карточки из бэкапа. Сет попадает в свою коллекцию пользователя
    /// по названию (`collectionName`; нет такой — создаётся с иконкой из бэкапа), карточки Inbox —
    /// в текущий Inbox. В системную коллекцию (контейнер Inbox) новые сеты не попадают: она скрыта,
    /// и сеты пропали бы из библиотеки. Уже существующие сеты и карточки (по id) не дублируются.
    private func restoreCardSets(_ sets: [BackupCardSet], into context: ModelContext, firebaseUID: String) -> (sets: Int, cards: Int) {
        let collections = context.fetchWithErrorHandling(FetchDescriptor<Collection>())
        let existingSets   = context.fetchWithErrorHandling(FetchDescriptor<CardSet>())
        let existingSetIds = Set(existingSets.map { $0.id })
        // Свой Inbox (см. Collection.isMine(firebaseUID:)) — не чужой, оставшийся локально после гонки CloudKit.
        let inboxContainer = collections.first { $0.isInbox && $0.isMine(firebaseUID: firebaseUID) }
        let inbox = existingSets.first { $0.name == "Inbox" && $0.collectionId == inboxContainer?.id }
        // Свои пользовательские коллекции по названию; созданные в этом восстановлении добавляются сюда же,
        // чтобы несколько сетов одной коллекции не создали несколько одноимённых коллекций.
        var userCollections = Dictionary(
            collections
                .filter { $0.isUserCreated && !$0.isInbox && $0.isMine(firebaseUID: firebaseUID) }
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var newSets  = 0
        var newCards = 0

        for backupSet in sets {
            let setId: UUID

            if backupSet.isInbox {
                guard let inbox else {
                    log("Restore: Inbox not found, skipping \(backupSet.cards.count) Inbox card(s)", level: .warning)
                    continue
                }
                setId = inbox.id
            } else if existingSetIds.contains(backupSet.id) {
                setId = backupSet.id
            } else {
                // Пустое название — у сета в бэкапе не нашлось коллекции; кладём в общую "Restored".
                let name = backupSet.collectionName.isEmpty ? "Restored" : backupSet.collectionName
                let collection: Collection
                if let existing = userCollections[name] {
                    collection = existing
                } else {
                    collection = Collection(name: name, icon: backupSet.collectionIcon, ownerFirebaseUID: firebaseUID)
                    context.insert(collection)
                    userCollections[name] = collection
                }

                let newSet = CardSet(
                    id:             backupSet.id,
                    name:           backupSet.name,
                    collectionId:   collection.id,
                    level:          CEFRLevel(rawValue: backupSet.level) ?? .a1,
                    isUserCreated:  true,
                    setDescription: backupSet.setDescription,
                    createdAt:      backupSet.createdAt
                )
                context.insert(newSet)
                setId = backupSet.id
                newSets += 1
            }

            let lookupSetId = setId
            let existingCards = context.fetchWithErrorHandling(
                FetchDescriptor<Card>(predicate: #Predicate { $0.setId == lookupSetId })
            )
            let existingCardIds  = Set(existingCards.map { $0.id })

            for bc in backupSet.cards where !existingCardIds.contains(bc.id) {
                let card = Card(
                    id:            bc.id,
                    en:            bc.en,
                    item:          bc.item,
                    sampleEN:      bc.sampleEN,
                    sampleItem:    bc.sampleItem,
                    status:        CardStatus(rawValue: bc.status) ?? .active,
                    isFavorite:    bc.isFavorite,
                    tags:          bc.tags,
                    synonyms:      bc.synonyms,
                    easeFactor:    bc.easeFactor,
                    interval:      bc.interval,
                    repetitions:   bc.repetitions,
                    dueDate:       bc.dueDate,
                    lastReviewed:  bc.lastReviewed,
                    createdAt:     bc.createdAt,
                    setId:         setId
                )
                card.userSampleEN   = bc.userSampleEN
                card.userSampleItem = bc.userSampleItem
                context.insert(card)
                newCards += 1
            }
        }

        return (newSets, newCards)
    }

    private func restorePairsSRS(_ pairsSRS: [BackupPairsSRS], into context: ModelContext) -> Int {
        let existing = context.fetchWithErrorHandling(FetchDescriptor<PairsSet>())
        var restored = 0

        for srs in pairsSRS {
            let match = existing.first { $0.id == srs.id }
                     ?? existing.first { $0.firestoreId != nil && $0.firestoreId == srs.firestoreId }

            guard let set = match else { continue }
            set.dueDate     = srs.dueDate
            set.interval    = srs.interval
            set.easeFactor  = srs.easeFactor
            set.repetitions = srs.repetitions
            set.lastReviewed = srs.lastReviewed
            restored += 1
        }

        return restored
    }

    // MARK: - Cleanup

    func cleanupTempFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            log("Cleaned up temp file: \(url.lastPathComponent)", level: .info)
        } catch {
            log("Failed to cleanup temp file: \(error)", level: .warning)
        }
    }
}
