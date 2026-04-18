import Foundation
import Observation

// MARK: - AdminStore
//
// Data store для SwipeLingoAdmin с JSON-персистентностью.
// Данные сохраняются в Application Support при каждой мутации,
// загружаются автоматически при инициализации.
// Phase 4: методы add/update/delete будут дополнены записью в Firestore.
//
// Deploy Status автопереходы:
//   Создание                 → .new
//   Редактирование .live/.ready → .draft (автоматически)
//   "Mark as Ready"          → .ready
//   Publish (Phase 4)        → .live
//   Soft delete              → .deleted (остаётся в store, скрывается из списка)

@Observable
final class AdminStore {

    // MARK: - State

    var collections: [FSCollection] = []
    var cardSets:    [FSCardSet]    = []
    var cards:       [FSCard]       = []
    var pairsSets:   [FSPairsSet]   = []

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
        // Soft-delete sets and their cards
        for id in removedSetIds { softDeleteCardSet(id: id) }
        pairsSets.indices
            .filter { pairsSets[$0].collectionId == collectionId }
            .forEach { pairsSets[$0].deployStatus = .deleted }
        save()
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

    /// Переводит сет в .ready (ручное действие из UI).
    func markReady(cardSetId: String) {
        guard let idx = cardSets.firstIndex(where: { $0.id == cardSetId }),
              cardSets[idx].deployStatus != .live
        else { return }
        cardSets[idx].deployStatus = .ready
        cardSets[idx].updatedAt   = .now
        save()
    }

    private func softDeleteCardSet(id: String) {
        guard let idx = cardSets.firstIndex(where: { $0.id == id }) else { return }
        cardSets[idx].deployStatus = .deleted
        cardSets[idx].updatedAt   = .now
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

    /// Переводит сет в .ready (ручное действие из UI).
    func markReady(pairsSetId: String) {
        guard let idx = pairsSets.firstIndex(where: { $0.id == pairsSetId }),
              pairsSets[idx].deployStatus != .live
        else { return }
        pairsSets[idx].deployStatus = .ready
        pairsSets[idx].updatedAt   = .now
        save()
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
    }

    private func save() {
        let payload = StoragePayload(
            collections: collections,
            cardSets:    cardSets,
            cards:       cards,
            pairsSets:   pairsSets
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
            log("AdminStore loaded: \(collections.count) collections, \(cardSets.count) sets, \(cards.count) cards, \(pairsSets.count) pairsSets")
        } catch {
            log("AdminStore load failed: \(error)", level: .error)
        }
    }
}
