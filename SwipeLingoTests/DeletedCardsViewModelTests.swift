import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - DeletedCardsViewModelTests
//
// Имя системной коллекции Inbox — ключ в данных, на экране удалённых карточек его быть не должно:
//   • availableCollections — системная коллекция не попадает в фильтр коллекций
//   • collectionName — для карточки из Inbox `nil` (подпись только «Inbox»), для своей коллекции — её имя

@MainActor
final class DeletedCardsViewModelTests: XCTestCase {

    private let vm = DeletedCardsViewModel()

    func testAvailableCollections_ExcludeInboxCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let travel = Collection(name: "Travel")
        let verbs  = CardSet(name: "Verbs", collectionId: travel.id)
        let cards  = [deletedCard(in: inbox), deletedCard(in: verbs)]

        let result = vm.availableCollections(allCards: cards, allCardSets: [inbox, verbs], allCollections: [inboxCollection, travel])

        XCTAssertEqual(result.map(\.id), [travel.id])
    }

    func testCollectionName_NilForInbox_NameForOwnCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let travel = Collection(name: "Travel")
        let verbs  = CardSet(name: "Verbs", collectionId: travel.id)
        let collections = [inboxCollection, travel]

        XCTAssertNil(vm.collectionName(for: inbox, allCollections: collections))
        XCTAssertEqual(vm.collectionName(for: verbs, allCollections: collections), "Travel")
        XCTAssertNil(vm.collectionName(for: nil, allCollections: collections))
    }

    // MARK: - Helpers

    private func deletedCard(in set: CardSet) -> Card {
        let card = Card(en: "word", item: "", setId: set.id)
        card.status = .deleted
        return card
    }
}
