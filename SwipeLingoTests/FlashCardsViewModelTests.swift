import XCTest
@testable import SwipeLingo

// MARK: - FlashCardsViewModelTests
//
// Переход Due → All по завершении Due-сессии:
//   • при наличии due-карточек сессия стартует в режиме Due и содержит только их
//   • continueWithAllCards по завершении Due переключает сессию в All со всеми активными карточками
//     (кнопка "Study all cards" на экране завершения TinderCardsView)

@MainActor
final class FlashCardsViewModelTests: XCTestCase {

    private let set = CardSet(name: "Verbs", collectionId: UUID())

    func testStartNewSession_WithDueCards_StartsInDueMode() {
        let due = card("due", dueDate: .distantPast)
        let later = card("later", dueDate: .distantFuture)
        let vm = FlashCardsViewModel()

        vm.startNewSession(piles: [], allCards: [due, later], cardSets: [set],
                           collections: [], dueHour: 0, srsEnabled: true)

        XCTAssertEqual(vm.studyMode, .due)
        XCTAssertEqual(vm.studyCards.map(\.id), [due.id])
    }

    func testContinueWithAllCards_AfterDue_SwitchesToAllWithAllActiveCards() {
        let due = card("due", dueDate: .distantPast)
        let later = card("later", dueDate: .distantFuture)
        let learnt = card("learnt", dueDate: .distantPast, status: .learnt)
        let allCards = [due, later, learnt]
        let vm = FlashCardsViewModel()
        vm.startNewSession(piles: [], allCards: allCards, cardSets: [set],
                           collections: [], dueHour: 0, srsEnabled: true)
        let dueSessionID = vm.sessionID

        vm.continueWithAllCards(piles: [], allCards: allCards, cardSets: [set],
                                collections: [], dueHour: 0)

        XCTAssertEqual(vm.studyMode, .all)
        XCTAssertEqual(Set(vm.studyCards.map(\.id)), [due.id, later.id])
        XCTAssertNotEqual(vm.sessionID, dueSessionID)
    }

    // MARK: - Helpers

    private func card(_ en: String, dueDate: Date, status: CardStatus = .active) -> Card {
        Card(en: en, item: "", status: status, dueDate: dueDate, setId: set.id)
    }
}
