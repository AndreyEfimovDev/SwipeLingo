import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - LibraryViewModelTests
//
// Inbox на экране библиотеки — отдельная плашка над коллекциями, хотя в данных это сет внутри системной коллекции:
//   • inboxSet — Inbox своей системной коллекции; Inbox чужой (гонка CloudKit) не возвращается
//   • setsForCollection(системная коллекция) — без Inbox; у других коллекций сет с именем "Inbox" не прячется
//   • myCollections — системная коллекция только если в ней есть сеты, кроме Inbox; своя коллекция видна и пустой

@MainActor
final class LibraryViewModelTests: XCTestCase {

    private let vm = LibraryViewModel()
    private let uid = "uid1"

    // MARK: - inboxSet

    func testInboxSet_ReturnsInboxOfOwnInboxCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let other  = CardSet(name: "My own set", collectionId: inboxCollection.id)

        let result = vm.inboxSet(collections: [inboxCollection], cardSets: [other, inbox], firebaseUID: uid)

        XCTAssertEqual(result?.id, inbox.id)
    }

    func testInboxSet_IgnoresForeignInboxCollection() {
        let foreign = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: "otherUID")
        let inbox   = CardSet(name: "Inbox", collectionId: foreign.id)

        XCTAssertNil(vm.inboxSet(collections: [foreign], cardSets: [inbox], firebaseUID: uid))
    }

    // MARK: - setsForCollection

    func testSetsForCollection_InboxCollectionExcludesInbox() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let own    = CardSet(name: "My own set", collectionId: inboxCollection.id)

        let sets = vm.setsForCollection(inboxCollection, cardSets: [inbox, own], allCards: [], userLevel: .c2)

        XCTAssertEqual(sets.map(\.name), ["My own set"])
    }

    func testSetsForCollection_OtherCollectionKeepsSetNamedInbox() {
        let travel = Collection(name: "Travel", ownerFirebaseUID: uid)
        let set    = CardSet(name: "Inbox", collectionId: travel.id)

        let sets = vm.setsForCollection(travel, cardSets: [set], allCards: [], userLevel: .c2)

        XCTAssertEqual(sets.map(\.name), ["Inbox"], "прячется только Inbox системной коллекции")
    }

    // MARK: - myCollections

    func testMyCollections_HidesInboxCollectionWithOnlyInbox() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)

        let result = vm.myCollections(from: [inboxCollection], cardSets: [inbox], allCards: [], firebaseUID: uid, userLevel: .c2)

        XCTAssertTrue(result.isEmpty)
    }

    func testMyCollections_ShowsInboxCollectionWithOwnSet() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let own    = CardSet(name: "My own set", collectionId: inboxCollection.id)

        let result = vm.myCollections(from: [inboxCollection], cardSets: [inbox, own], allCards: [], firebaseUID: uid, userLevel: .c2)

        XCTAssertEqual(result.map(\.id), [inboxCollection.id])
    }

    func testMyCollections_ShowsEmptyUserCollectionAfterInboxCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let own    = CardSet(name: "My own set", collectionId: inboxCollection.id)
        let second = Collection(name: "My 2nd collection", ownerFirebaseUID: uid)

        let result = vm.myCollections(
            from: [second, inboxCollection], cardSets: [inbox, own], allCards: [], firebaseUID: uid, userLevel: .c2
        )

        XCTAssertEqual(result.map(\.id), [inboxCollection.id, second.id], "системная коллекция первой, только что созданная коллекция видна")
    }
}
