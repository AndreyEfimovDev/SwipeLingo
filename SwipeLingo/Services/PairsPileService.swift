import Foundation

// MARK: - PairsPileService
// Resolves a PairsPile's DynamicSets from a pre-fetched [DynamicSet] slice.
// Preserves the order defined in pile.setIds.

struct PairsPileService {

    func sets(for pile: PairsPile, from allSets: [DynamicSet]) -> [DynamicSet] {
        pile.setIds.compactMap { id in allSets.first { $0.id == id } }
    }
}
