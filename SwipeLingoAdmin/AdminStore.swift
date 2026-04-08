import Foundation
import Observation

// MARK: - AdminStore
//
// In-memory data store для SwipeLingoAdmin.
// Phase 1: чисто in-memory (без Firebase и персистентности).
// Phase 4: методы add/update/delete будут дополнены записью в Firestore.

@Observable
final class AdminStore {

    // MARK: - State

    var collections: [FSCollection] = []
    var cardSets:    [FSCardSet]    = []
    var cards:       [FSCard]       = []
    var pairsSets:   [FSPairsSet]   = []

    // MARK: - Collections

    func collections(of type: CollectionType) -> [FSCollection] {
        collections.filter { $0.collectionType == type }
    }

    func add(_ collection: FSCollection) {
        collections.append(collection)
    }

    func update(_ collection: FSCollection) {
        guard let idx = collections.firstIndex(where: { $0.id == collection.id }) else { return }
        collections[idx] = collection
    }

    func delete(collectionId: String) {
        collections.removeAll { $0.id == collectionId }
        // Cascade delete
        let removedSetIds = cardSets.filter { $0.collectionId == collectionId }.map(\.id)
        cardSets.removeAll  { $0.collectionId == collectionId }
        cards.removeAll     { removedSetIds.contains($0.setId) }
        pairsSets.removeAll { $0.collectionId == collectionId }
    }

    // MARK: - CardSets

    func cardSets(for collectionId: String) -> [FSCardSet] {
        cardSets.filter { $0.collectionId == collectionId }
    }

    func add(_ set: FSCardSet) {
        cardSets.append(set)
    }

    func update(_ set: FSCardSet) {
        guard let idx = cardSets.firstIndex(where: { $0.id == set.id }) else { return }
        cardSets[idx] = set
    }

    func delete(cardSetId: String) {
        cardSets.removeAll { $0.id == cardSetId }
        cards.removeAll    { $0.setId == cardSetId }
    }

    // MARK: - Cards

    func cards(for setId: String) -> [FSCard] {
        cards.filter { $0.setId == setId }
    }

    func add(_ card: FSCard) {
        cards.append(card)
    }

    func update(_ card: FSCard) {
        guard let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[idx] = card
    }

    func delete(cardId: String) {
        cards.removeAll { $0.id == cardId }
    }

    // MARK: - PairsSets

    func pairsSets(for collectionId: String) -> [FSPairsSet] {
        pairsSets.filter { $0.collectionId == collectionId }
    }

    func add(_ set: FSPairsSet) {
        pairsSets.append(set)
    }

    func update(_ set: FSPairsSet) {
        guard let idx = pairsSets.firstIndex(where: { $0.id == set.id }) else { return }
        pairsSets[idx] = set
    }

    func delete(pairsSetId: String) {
        pairsSets.removeAll { $0.id == pairsSetId }
    }
}
