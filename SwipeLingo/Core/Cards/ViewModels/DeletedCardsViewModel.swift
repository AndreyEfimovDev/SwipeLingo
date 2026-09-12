import SwiftUI
import SwiftData

// MARK: - DeletedCardsViewModel
//
// Бизнес-логика DeletedCardsView: фильтрация удалённых карточек и Restore/Erase Forever
// мутации. Фильтры/выбор (selectedCollectionId/selectedSetId/selectedCardIds/searchText/
// editMode/cardToErase) остаются во View как @State — та же конвенция, что уже
// используется в PileBuilderView (isShowingDeleteConfirm, searchText, selectedLevel) —
// и передаются сюда параметром, как и @Query-результаты (allCards/allCardSets/allCollections).
// ViewModel не хранит собственного состояния — как LibraryViewModel.

@Observable
final class DeletedCardsViewModel {

    // MARK: - Фильтрация

    func deletedCards(allCards: [Card]) -> [Card] {
        allCards.filter { $0.status == .deleted }
    }

    func filteredCards(
        allCards: [Card], allCardSets: [CardSet],
        selectedCollectionId: UUID?, selectedSetId: UUID?, searchText: String
    ) -> [Card] {
        var cards = deletedCards(allCards: allCards)
        if let colId = selectedCollectionId {
            let setIds = Set(allCardSets.filter { $0.collectionId == colId }.map { $0.id })
            cards = cards.filter { setIds.contains($0.setId) }
        }
        if let setId = selectedSetId {
            cards = cards.filter { $0.setId == setId }
        }
        return cards.filtered(by: searchText)
    }

    /// Коллекции, в которых есть хотя бы одна удалённая карточка.
    func availableCollections(allCards: [Card], allCardSets: [CardSet], allCollections: [Collection]) -> [Collection] {
        let deletedSetIds = Set(deletedCards(allCards: allCards).map { $0.setId })
        let collectionIds = Set(allCardSets.filter { deletedSetIds.contains($0.id) }.map { $0.collectionId })
        return allCollections.filter { collectionIds.contains($0.id) }
    }

    /// Сеты, в которых есть хотя бы одна удалённая карточка; сужается выбранной коллекцией, если она активна.
    func availableSets(allCards: [Card], allCardSets: [CardSet], selectedCollectionId: UUID?) -> [CardSet] {
        let deletedSetIds = Set(deletedCards(allCards: allCards).map { $0.setId })
        var sets = allCardSets.filter { deletedSetIds.contains($0.id) }
        if let colId = selectedCollectionId {
            sets = sets.filter { $0.collectionId == colId }
        }
        return sets
    }

    func isCurated(_ card: Card, allCardSets: [CardSet]) -> Bool {
        !(allCardSets.first(where: { $0.id == card.setId })?.isUserCreated ?? true)
    }

    /// Выбранные карточки из user-created сетов — только их можно стереть навсегда.
    func selectedErasableCards(filteredCards: [Card], selectedCardIds: Set<UUID>, allCardSets: [CardSet]) -> [Card] {
        filteredCards.filter { card in
            guard selectedCardIds.contains(card.id) else { return false }
            return allCardSets.first(where: { $0.id == card.setId })?.isUserCreated ?? true
        }
    }

    // MARK: - Restore

    /// Восстанавливает карточку в `.active`. Если она принадлежит soft-deleted облачному
    /// сету — снимает tombstone, чтобы сет снова появился в библиотеке.
    func restoreCard(_ card: Card, allCardSets: [CardSet], context: ModelContext) {
        card.status = .active
        if let cardSet = allCardSets.first(where: { $0.id == card.setId }),
           !cardSet.isUserCreated, cardSet.isSoftDeleted {
            cardSet.isSoftDeleted = false
        }
        context.saveWithErrorHandling()
    }

    /// Восстанавливает несколько карточек — та же логика на карточку, одно сохранение.
    func restoreSelected(_ cards: [Card], allCardSets: [CardSet], context: ModelContext) {
        cards.forEach { card in
            card.status = .active
            if let cardSet = allCardSets.first(where: { $0.id == card.setId }),
               !cardSet.isUserCreated, cardSet.isSoftDeleted {
                cardSet.isSoftDeleted = false
            }
        }
        context.saveWithErrorHandling()
    }

    // MARK: - Erase Forever

    /// Стирает одну карточку навсегда — используется в swipe action / single-erase confirmation.
    func eraseCard(_ card: Card, allCards: [Card], allCardSets: [CardSet], allCollections: [Collection], context: ModelContext) {
        cleanupAfterErase(erasingIds: [card.id], allCards: allCards, allCardSets: allCardSets, allCollections: allCollections, context: context)
        context.delete(card)
        context.saveWithErrorHandling()
    }

    /// Стирает несколько карточек навсегда — используется в bulk action bar.
    func eraseSelected(_ cards: [Card], allCards: [Card], allCardSets: [CardSet], allCollections: [Collection], context: ModelContext) {
        let ids = Set(cards.map { $0.id })
        cleanupAfterErase(erasingIds: ids, allCards: allCards, allCardSets: allCardSets, allCollections: allCollections, context: context)
        cards.forEach { context.delete($0) }
        context.saveWithErrorHandling()
    }

    /// Удаляет сеты и коллекции, в которых после стирания карточек не осталось ни одной.
    /// Вызывать ДО `context.delete()` карточек, пока @Query ещё содержит стираемые карточки.
    private func cleanupAfterErase(
        erasingIds: Set<UUID>, allCards: [Card], allCardSets: [CardSet], allCollections: [Collection], context: ModelContext
    ) {
        let affectedSetIds = Set(allCards.filter { erasingIds.contains($0.id) }.map { $0.setId })

        for setId in affectedSetIds {
            // Карточки в сете, которые останутся после стирания
            let remaining = allCards.filter { $0.setId == setId && !erasingIds.contains($0.id) }
            guard remaining.isEmpty,
                  let set = allCardSets.first(where: { $0.id == setId }),
                  set.isUserCreated,                              // кураторские сеты остаются как tombstone
                  let collection = allCollections.first(where: { $0.id == set.collectionId }),
                  collection.name != "Inbox" else { continue }  // Inbox set никогда не удаляем

            let collectionId = set.collectionId
            context.delete(set)

            // проверяем, остались ли в коллекции другие сеты.
            let remainingSets = allCardSets.filter { $0.collectionId == collectionId && $0.id != setId }
            guard remainingSets.isEmpty,
                  collection.name != "My Sets" else { continue }  // My Sets никогда не удаляется
            context.delete(collection)
        }
    }
}
