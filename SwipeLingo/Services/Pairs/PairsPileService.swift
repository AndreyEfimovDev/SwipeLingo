import Foundation

// MARK: - PairsPileService
// Определяет PairsSets для PairsPile из уже загруженного среза [PairsSet].
// Сохраняет порядок, заданный в pile.setIds.

struct PairsPileService {

    func sets(for pile: PairsPile, from allSets: [PairsSet]) -> [PairsSet] {
        pile.setIds.compactMap { id in allSets.first { $0.id == id } }
    }
}
