import Foundation
import Observation

// MARK: - AdminStore
//
// Data store для SwipeLingoAdmin с JSON-персистентностью.
// Данные сохраняются в Application Support при каждой мутации,
// загружаются автоматически при инициализации.
//
// Deploy Status автопереходы:
//   Создание                 → .new
//   Редактирование .live/.ready → .draft (автоматически)
//   "Mark as Ready"          → .ready
//   Deploy (Firestore write) → .live   (автоматически после успешного деплоя)
//   Soft delete              → .deleted (остаётся в store, скрывается из списка)

@Observable
final class AdminStore {

    // MARK: - State

    var collections: [FSCollection] = []
    var cardSets:    [FSCardSet]    = []
    var cards:       [FSCard]       = []
    var pairsSets:   [FSPairsSet]   = []
    var books:       [FSBook]       = []

    // Deploy state (shared — only one deploy runs at a time)
    var isDeploying    = false
    var deployError:   String? = nil
    var isDeleting     = false
    var deleteError:   String? = nil

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Collections

    func collections(of type: CollectionType) -> [FSCollection] {
        collections.filter { $0.type == type }
    }

    func add(_ collection: FSCollection) {
        collections.append(collection)
        save()
    }

    func update(_ collection: FSCollection) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[idx] = collection
        save()
    }

    func delete(collectionId: String) {
        collections.removeAll { $0.id == collectionId }
        let removedSetIds = cardSets.filter { $0.collectionId == collectionId }.map(\.id)
        for id in removedSetIds { softDeleteCardSet(id: id) }
        pairsSets.indices
            .filter { pairsSets[$0].collectionId == collectionId }
            .forEach { pairsSets[$0].deployStatus = .deleted }
        save()
    }

    /// Удаляет коллекцию из Firestore (все live-сеты + документ коллекции), затем локально.
    func deleteFromFirestore(collectionId: String) async {
        isDeleting  = true
        deleteError = nil
        do {
            let liveCardSetIds  = cardSets.filter  { $0.collectionId == collectionId && $0.deployStatus == .live }.map(\.id)
            let livePairsSetIds = pairsSets.filter { $0.collectionId == collectionId && $0.deployStatus == .live }.map(\.id)
            try await FirestoreService().deleteCollection(
                id: collectionId,
                cardSetIds: liveCardSetIds,
                pairsSetIds: livePairsSetIds
            )
            delete(collectionId: collectionId)
        } catch {
            deleteError = error.localizedDescription
            log("[Delete] Collection delete from Firestore failed: \(error)", level: .error)
        }
        isDeleting = false
    }

    // MARK: - CardSets

    func cardSets(for collectionId: String) -> [FSCardSet] {
        cardSets.filter { $0.collectionId == collectionId && $0.deployStatus != .deleted }
    }

    func add(_ set: FSCardSet) {
        cardSets.append(set)
        save()
    }

    /// Сохраняет изменения сета. Если сет был .live или .ready — автоматически переводит в .draft.
    func update(_ set: FSCardSet) {
        guard let idx = cardSets.firstIndex(where: { $0.id == set.id }) else { return }
        var updated = set
        if set.deployStatus == .live || set.deployStatus == .ready {
            updated.deployStatus = .draft
        }
        updated.updatedAt = .now
        cardSets[idx] = updated
        save()
    }

    /// Мягкое удаление — сет помечается .deleted, остаётся в store.
    func delete(cardSetId: String) {
        softDeleteCardSet(id: cardSetId)
        save()
    }

    /// Восстанавливает мягко удалённый сет → предыдущий статус (или .live если неизвестен).
    /// Fallback .live: soft-delete не трогает FB, значит после Restore сет там актуален.
    func restore(cardSetId: String) {
        guard let idx = cardSets.firstIndex(where: { $0.id == cardSetId }) else { return }
        cardSets[idx].deployStatus         = cardSets[idx].previousDeployStatus ?? .live
        cardSets[idx].previousDeployStatus = nil
        cardSets[idx].updatedAt            = .now
        save()
    }

    /// Переводит сет в .ready (ручное действие из UI).
    func markReady(cardSetId: String) {
        guard let idx = cardSets.firstIndex(where: { $0.id == cardSetId }),
              cardSets[idx].deployStatus != .live
        else { return }
        cardSets[idx].deployStatus = .ready
        cardSets[idx].updatedAt   = .now
        save()
    }

    /// Удаляет CardSet из FB (всегда пробуем — delete несуществующего doc в Firestore безопасен)
    /// и полностью убирает из store.json.
    func deleteForever(cardSetId: String) async {
        isDeleting  = true
        deleteError = nil
        do {
            try await FirestoreService().deleteCardSet(id: cardSetId)
            cardSets.removeAll { $0.id == cardSetId }
            cards.removeAll    { $0.setId == cardSetId }
            save()
        } catch {
            deleteError = error.localizedDescription
            log("[Delete] CardSet deleteForever failed: \(error)", level: .error)
        }
        isDeleting = false
    }

    private func softDeleteCardSet(id: String) {
        guard let idx = cardSets.firstIndex(where: { $0.id == id }) else { return }
        cardSets[idx].previousDeployStatus = cardSets[idx].deployStatus
        cardSets[idx].deployStatus         = .deleted
        cardSets[idx].updatedAt            = .now
    }

    // MARK: - Cards

    func cards(for setId: String) -> [FSCard] {
        cards.filter { $0.setId == setId }
    }

    func add(_ card: FSCard) {
        cards.append(card)
        markDraftIfPublished(cardSetId: card.setId)
        save()
    }

    func update(_ card: FSCard) {
        guard let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[idx] = card
        markDraftIfPublished(cardSetId: card.setId)
        save()
    }

    func delete(cardId: String) {
        if let card = cards.first(where: { $0.id == cardId }) {
            markDraftIfPublished(cardSetId: card.setId)
        }
        cards.removeAll { $0.id == cardId }
        save()
    }

    /// Переводит сет из .live или .ready → .draft при изменении его карточек.
    private func markDraftIfPublished(cardSetId: String) {
        guard let idx = cardSets.firstIndex(where: { $0.id == cardSetId }),
              cardSets[idx].deployStatus == .live || cardSets[idx].deployStatus == .ready
        else { return }
        cardSets[idx].deployStatus = .draft
        cardSets[idx].updatedAt   = .now
    }

    // MARK: - PairsSets

    func pairsSets(for collectionId: String) -> [FSPairsSet] {
        pairsSets.filter { $0.collectionId == collectionId && $0.deployStatus != .deleted }
    }

    func add(_ set: FSPairsSet) {
        pairsSets.append(set)
        save()
    }

    /// Сохраняет изменения сета. Если сет был .live или .ready — автоматически переводит в .draft.
    func update(_ set: FSPairsSet) {
        guard let idx = pairsSets.firstIndex(where: { $0.id == set.id }) else { return }
        var updated = set
        if set.deployStatus == .live || set.deployStatus == .ready {
            updated.deployStatus = .draft
        }
        updated.updatedAt = .now
        pairsSets[idx] = updated
        save()
    }

    /// Мягкое удаление — сет помечается .deleted, остаётся в store.
    func delete(pairsSetId: String) {
        guard let idx = pairsSets.firstIndex(where: { $0.id == pairsSetId }) else { return }
        pairsSets[idx].deployStatus = .deleted
        pairsSets[idx].updatedAt   = .now
        save()
    }

    /// Восстанавливает мягко удалённый сет → предыдущий статус (или .live если неизвестен).
    /// Fallback .live: soft-delete не трогает FB, значит после Restore сет там актуален.
    func restore(pairsSetId: String) {
        guard let idx = pairsSets.firstIndex(where: { $0.id == pairsSetId }) else { return }
        pairsSets[idx].deployStatus         = pairsSets[idx].previousDeployStatus ?? .live
        pairsSets[idx].previousDeployStatus = nil
        pairsSets[idx].updatedAt            = .now
        save()
    }

    /// Удаляет PairsSet из FB (всегда пробуем — delete несуществующего doc в Firestore безопасен)
    /// и полностью убирает из store.json.
    func deleteForever(pairsSetId: String) async {
        isDeleting  = true
        deleteError = nil
        do {
            try await FirestoreService().deletePairsSet(id: pairsSetId)
            pairsSets.removeAll { $0.id == pairsSetId }
            save()
        } catch {
            deleteError = error.localizedDescription
            log("[Delete] PairsSet deleteForever failed: \(error)", level: .error)
        }
        isDeleting = false
    }

    /// Переводит сет в .ready (ручное действие из UI).
    func markReady(pairsSetId: String) {
        guard let idx = pairsSets.firstIndex(where: { $0.id == pairsSetId }),
              pairsSets[idx].deployStatus != .live
        else { return }
        pairsSets[idx].deployStatus = .ready
        pairsSets[idx].updatedAt   = .now
        save()
    }

    // MARK: - Books

    func add(_ book: FSBook) {
        books.append(book)
        save()
    }

    func update(_ book: FSBook) {
        guard let idx = books.firstIndex(where: { $0.id == book.id }) else { return }
        var updated = book
        if book.deployStatus == .live || book.deployStatus == .ready {
            updated.deployStatus = .draft
        }
        updated.updatedAt = .now
        books[idx] = updated
        save()
    }

    func delete(bookId: String) {
        guard let idx = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[idx].previousDeployStatus = books[idx].deployStatus
        books[idx].deployStatus         = .deleted
        books[idx].updatedAt            = .now
        save()
    }

    func restore(bookId: String) {
        guard let idx = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[idx].deployStatus         = books[idx].previousDeployStatus ?? .live
        books[idx].previousDeployStatus = nil
        books[idx].updatedAt            = .now
        save()
    }

    func deployBook(id: String) async {
        guard let book = books.first(where: { $0.id == id }) else { return }
        isDeploying = true
        deployError = nil
        do {
            try await FirestoreService().deployBook(book)
            if let idx = books.firstIndex(where: { $0.id == id }) {
                books[idx].deployStatus = .live
                books[idx].updatedAt   = .now
            }
            save()
        } catch {
            deployError = error.localizedDescription
            log("[Deploy] Book deploy failed: \(error)", level: .error)
        }
        isDeploying = false
    }

    func deleteBookForever(id: String) async {
        isDeleting  = true
        deleteError = nil
        do {
            try await FirestoreService().deleteBook(id: id)
            books.removeAll { $0.id == id }
            save()
        } catch {
            deleteError = error.localizedDescription
            log("[Delete] Book deleteForever failed: \(error)", level: .error)
        }
        isDeleting = false
    }

    // MARK: - Deploy

    /// Deploys a CardSet (plus its cards and parent collection) to Firestore.
    /// On success marks the set as .live. On failure stores deployError.
    func deployCardSet(id: String) async {
        guard let set = cardSets.first(where: { $0.id == id }),
              let collection = collections.first(where: { $0.id == set.collectionId })
        else { return }

        let setCards = cards(for: id)

        isDeploying = true
        deployError = nil

        do {
            try await FirestoreService().deployCardSet(
                collection: collection,
                set: set,
                cards: setCards
            )
            // Mark set as .live
            if let idx = cardSets.firstIndex(where: { $0.id == id }) {
                cardSets[idx].deployStatus = .live
                cardSets[idx].updatedAt    = .now
            }
            // Mark collection as synced
            if let idx = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[idx].isSynced  = true
                collections[idx].updatedAt = .now
            }
            save()
        } catch {
            deployError = error.localizedDescription
            log("[Deploy] CardSet deploy failed: \(error)", level: .error)
        }

        isDeploying = false
    }

    /// Deploys a PairsSet (plus parent collection) to Firestore.
    /// On success marks the set as .live. On failure stores deployError.
    func deployPairsSet(id: String) async {
        guard let set = pairsSets.first(where: { $0.id == id }),
              let collection = collections.first(where: { $0.id == set.collectionId })
        else { return }

        isDeploying = true
        deployError = nil

        do {
            try await FirestoreService().deployPairsSet(
                collection: collection,
                set: set
            )
            // Mark set as .live
            if let idx = pairsSets.firstIndex(where: { $0.id == id }) {
                pairsSets[idx].deployStatus = .live
                pairsSets[idx].updatedAt    = .now
            }
            // Mark collection as synced
            if let idx = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[idx].isSynced  = true
                collections[idx].updatedAt = .now
            }
            save()
        } catch {
            deployError = error.localizedDescription
            log("[Deploy] PairsSet deploy failed: \(error)", level: .error)
        }

        isDeploying = false
    }

    // MARK: - Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static var storeURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwipeLingoAdmin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    private struct StoragePayload: Codable {
        var collections: [FSCollection]
        var cardSets:    [FSCardSet]
        var cards:       [FSCard]
        var pairsSets:   [FSPairsSet]
        var books:       [FSBook]

        init(collections: [FSCollection], cardSets: [FSCardSet], cards: [FSCard],
             pairsSets: [FSPairsSet], books: [FSBook]) {
            self.collections = collections
            self.cardSets    = cardSets
            self.cards       = cards
            self.pairsSets   = pairsSets
            self.books       = books
        }

        init(from decoder: Decoder) throws {
            let c        = try decoder.container(keyedBy: CodingKeys.self)
            collections  = try c.decode([FSCollection].self, forKey: .collections)
            cardSets     = try c.decode([FSCardSet].self,    forKey: .cardSets)
            cards        = try c.decode([FSCard].self,       forKey: .cards)
            pairsSets    = try c.decode([FSPairsSet].self,   forKey: .pairsSets)
            books        = (try? c.decode([FSBook].self,     forKey: .books)) ?? []
        }
    }

    private func save() {
        let payload = StoragePayload(
            collections: collections,
            cardSets:    cardSets,
            cards:       cards,
            pairsSets:   pairsSets,
            books:       books
        )
        do {
            let data = try Self.encoder.encode(payload)
            try data.write(to: Self.storeURL, options: .atomic)
        } catch {
            log("AdminStore save failed: \(error)", level: .error)
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.storeURL.path) else { return }
        do {
            let data    = try Data(contentsOf: Self.storeURL)
            let payload = try Self.decoder.decode(StoragePayload.self, from: data)
            collections = payload.collections
            cardSets    = payload.cardSets
            cards       = payload.cards
            pairsSets   = payload.pairsSets
            books       = payload.books
            log("AdminStore loaded: \(collections.count) collections, \(cardSets.count) sets, \(cards.count) cards, \(pairsSets.count) pairsSets, \(books.count) books")
        } catch {
            log("AdminStore load failed: \(error)", level: .error)
        }
    }
}
