import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - LibraryViewModelTests
//
// Inbox на экране библиотеки — отдельная плашка над коллекциями, хотя в данных это сет внутри системной коллекции:
//   • inboxSet — Inbox своей системной коллекции; Inbox чужой (гонка CloudKit) не возвращается
//   • setsForCollection(системная коллекция) — без Inbox; у других коллекций сет с именем "Inbox" не прячется
//   • myCollections — системная коллекция не показывается никогда; своя коллекция видна и пустой

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

    func testMyCollections_NeverShowsInboxCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let legacy = CardSet(name: "My own set", collectionId: inboxCollection.id)

        let result = vm.myCollections(from: [inboxCollection], cardSets: [inbox, legacy], allCards: [], firebaseUID: uid)

        XCTAssertTrue(result.isEmpty, "системная коллекция не показывается, даже если в ней оказались другие сеты")
    }

    func testMyCollections_ShowsOwnCollectionsIncludingEmptyOne() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox   = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let first   = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let firstSet = CardSet(name: "1st set", collectionId: first.id)
        let second  = Collection(name: "My 2nd collection", ownerFirebaseUID: uid)
        let foreign = Collection(name: "Foreign", ownerFirebaseUID: "otherUID")

        let result = vm.myCollections(
            from: [inboxCollection, first, second, foreign], cardSets: [inbox, firstSet], allCards: [], firebaseUID: uid
        )

        XCTAssertEqual(result.map(\.id), [first.id, second.id], "только что созданная пустая коллекция видна, чужая — нет")
    }
}
