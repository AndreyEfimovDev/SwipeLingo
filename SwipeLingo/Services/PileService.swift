import Foundation

// MARK: - PileService
//
// Resolves a Pile's cards from a pre-fetched [Card] slice.
// Accepts allCards from @Query so it works without a direct ModelContext call.

struct PileService {

    /// Returns active cards that belong to the Pile's sets, sorted by shuffleMethod.
    func cards(for pile: Pile, from allCards: [Card]) -> [Card] {
        let setIds = Set(pile.setIds)
        let active = allCards.filter { setIds.contains($0.setId) && $0.status == .active }
        return apply(pile.shuffleMethod, to: active)
    }

    func apply(_ method: ShuffleMethod, to cards: [Card]) -> [Card] {
        switch method {
        case .random:
            return cards.shuffled()
        case .sequential:
            return cards.sorted { $0.createdAt < $1.createdAt }
        case .prioritized:
            // Hardest (lowest easeFactor) first; ties broken by oldest dueDate
            return cards.sorted {
                if abs($0.easeFactor - $1.easeFactor) > 0.001 { return $0.easeFactor < $1.easeFactor }
                return $0.dueDate < $1.dueDate
            }
        }
    }
}
