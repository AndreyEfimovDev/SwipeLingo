import Foundation

// MARK: - PairsPileService
// Resolves a PairsPile's PairsSets from a pre-fetched [PairsSet] slice.
// Preserves the order defined in pile.setIds.

struct PairsPileService {

    func sets(for pile: PairsPile, from allSets: [PairsSet]) -> [PairsSet] {
        pile.setIds.compactMap { id in allSets.first { $0.id == id } }
    }
}
