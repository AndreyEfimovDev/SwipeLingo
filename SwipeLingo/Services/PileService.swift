import Foundation

// MARK: - PileService
//
// Определяет карточки Pile из уже загруженного среза [Card].
// Принимает allCards из @Query, поэтому работает без прямого вызова ModelContext.

struct PileService {

    /// Возвращает активные карточки, принадлежащие сетам Pile, отсортированные по shuffleMethod.
    func cards(for pile: Pile, from allCards: [Card]) -> [Card] {
        apply(pile.shuffleMethod, to: activeCards(for: pile, from: allCards))
    }

    /// Возвращает активные карточки Pile без применения порядка сортировки.
    /// Используй, когда нужно дополнительно отфильтровать список (напр. по dueDate) перед сортировкой.
    func activeCards(for pile: Pile, from allCards: [Card]) -> [Card] {
        let setIds = Set(pile.setIds)
        return allCards.filter { setIds.contains($0.setId) && $0.status == .active }
    }

    func apply(_ method: ShuffleMethod, to cards: [Card]) -> [Card] {
        switch method {
        case .random:
            return cards.shuffled()
        case .sequential:
            return cards.sorted { $0.createdAt < $1.createdAt }
        case .prioritized:
            // Сначала самые сложные (наименьший easeFactor); при равенстве — по более старому dueDate
            return cards.sorted {
                if abs($0.easeFactor - $1.easeFactor) > 0.001 { return $0.easeFactor < $1.easeFactor }
                return $0.dueDate < $1.dueDate
            }
        }
    }
}
