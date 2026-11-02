import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - LibraryViewModelTests
//
// Inbox на экране библиотеки — отдельная плашка над коллекциями, хотя в данных это сет внутри "My Sets":
//   • inboxSet — Inbox своей "My Sets"; Inbox чужой "My Sets" (гонка CloudKit) не возвращается
//   • setsForCollection("My Sets") — без Inbox; у других коллекций сет с именем "Inbox" не прячется
//   • myCollections — "My Sets" только если в ней есть сеты, кроме Inbox; своя коллекция видна и пустой

@MainActor
final class LibraryViewModelTests: XCTestCase {

    private let vm = LibraryViewModel()
    private let uid = "uid1"

    // MARK: - inboxSet

    func testInboxSet_ReturnsInboxOfOwnMySets() {
        let mySets = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: mySets.id)
        let other  = CardSet(name: "My own set", collectionId: mySets.id)

        let result = vm.inboxSet(collections: [mySets], cardSets: [other, inbox], firebaseUID: uid)

        XCTAssertEqual(result?.id, inbox.id)
    }

    func testInboxSet_IgnoresForeignMySets() {
        let foreign = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: "otherUID")
        let inbox   = CardSet(name: "Inbox", collectionId: foreign.id)

        XCTAssertNil(vm.inboxSet(collections: [foreign], cardSets: [inbox], firebaseUID: uid))
    }

    // MARK: - setsForCollection

    func testSetsForCollection_MySetsExcludesInbox() {
        let mySets = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: mySets.id)
        let own    = CardSet(name: "My own set", collectionId: mySets.id)

        let sets = vm.setsForCollection(mySets, cardSets: [inbox, own], allCards: [], userLevel: .c2)

        XCTAssertEqual(sets.map(\.name), ["My own set"])
    }

    func testSetsForCollection_OtherCollectionKeepsSetNamedInbox() {
        let travel = Collection(name: "Travel", ownerFirebaseUID: uid)
        let set    = CardSet(name: "Inbox", collectionId: travel.id)

        let sets = vm.setsForCollection(travel, cardSets: [set], allCards: [], userLevel: .c2)

        XCTAssertEqual(sets.map(\.name), ["Inbox"], "прячется только Inbox системной My Sets")
    }

    // MARK: - myCollections

    func testMyCollections_HidesMySetsWithOnlyInbox() {
        let mySets = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: mySets.id)

        let result = vm.myCollections(from: [mySets], cardSets: [inbox], allCards: [], firebaseUID: uid, userLevel: .c2)

        XCTAssertTrue(result.isEmpty)
    }

    func testMyCollections_ShowsMySetsWithOwnSet() {
        let mySets = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: mySets.id)
        let own    = CardSet(name: "My own set", collectionId: mySets.id)

        let result = vm.myCollections(from: [mySets], cardSets: [inbox, own], allCards: [], firebaseUID: uid, userLevel: .c2)

        XCTAssertEqual(result.map(\.id), [mySets.id])
    }

    func testMyCollections_ShowsEmptyUserCollectionAfterMySets() {
        let mySets = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: mySets.id)
        let own    = CardSet(name: "My own set", collectionId: mySets.id)
        let second = Collection(name: "My 2nd collection", ownerFirebaseUID: uid)

        let result = vm.myCollections(
            from: [second, mySets], cardSets: [inbox, own], allCards: [], firebaseUID: uid, userLevel: .c2
        )

        XCTAssertEqual(result.map(\.id), [mySets.id, second.id], "My Sets первой, только что созданная коллекция видна")
    }
}
