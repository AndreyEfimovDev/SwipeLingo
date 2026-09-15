import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - CollectionDedupeServiceTests
//
// Tests cover:
//   • claimSystemCollections — empty firebaseUID / no collections / bootstrap
//     → claimed / already own (idempotent) / only foreign (untouched, no new
//     collection created) / multiple bootstrap duplicates (all claimed, NOT
//     merged — that's mergeProtectedCollections' job) / Inbox and My Sets
//     handled independently / non-user-created collection with a protected
//     name is not a claim candidate
//   • mergeProtectedCollections — no duplicates / bootstrap duplicates merge
//     (oldest wins) / different owners NOT merged / bootstrap vs claimed NOT
//     merged / CardSet reparenting + same-name CardSet collapse (cards
//     reparented onto the oldest CardSet) / differently-named CardSets stay
//     separate after reparenting / Inbox and My Sets dedupe independently

@MainActor
final class CollectionDedupeServiceTests: XCTestCase {

    let service = CollectionDedupeService()

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Collection.self, CardSet.self, Card.self, configurations: config)
        return ModelContext(container)
    }

    @discardableResult
    private func makeCollection(
        name: String,
        ownerFirebaseUID: String = "",
        isUserCreated: Bool = true,
        createdAt: Date = .now,
        context: ModelContext
    ) -> Collection {
        let collection = Collection(
            name: name, isUserCreated: isUserCreated, createdAt: createdAt, ownerFirebaseUID: ownerFirebaseUID
        )
        context.insert(collection)
        return collection
    }

    @discardableResult
    private func makeCardSet(
        name: String, collectionId: UUID, createdAt: Date = .now, context: ModelContext
    ) -> CardSet {
        let set = CardSet(name: name, collectionId: collectionId, createdAt: createdAt)
        context.insert(set)
        return set
    }

    @discardableResult
    private func makeCard(en: String, setId: UUID, context: ModelContext) -> Card {
        let card = Card(en: en, item: "", setId: setId)
        context.insert(card)
        return card
    }

    private func fetchCollections(_ context: ModelContext) throws -> [Collection] {
        try context.fetch(FetchDescriptor<Collection>())
    }

    private func fetchCardSets(_ context: ModelContext) throws -> [CardSet] {
        try context.fetch(FetchDescriptor<CardSet>())
    }

    private func fetchCards(_ context: ModelContext) throws -> [Card] {
        try context.fetch(FetchDescriptor<Card>())
    }

    // MARK: - claimSystemCollections

    func testClaim_EmptyFirebaseUID_DoesNothing() throws {
        let ctx = try makeContext()
        makeCollection(name: "Inbox", ownerFirebaseUID: "", context: ctx)

        service.claimSystemCollections(firebaseUID: "", context: ctx)

        let inbox = try fetchCollections(ctx).first { $0.name == "Inbox" }
        XCTAssertEqual(inbox?.ownerFirebaseUID, "")
    }

    func testClaim_NoCollections_DoesNothing() throws {
        let ctx = try makeContext()
        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)
        XCTAssertTrue(try fetchCollections(ctx).isEmpty)
    }

    func testClaim_BootstrapCollection_GetsClaimed() throws {
        let ctx = try makeContext()
        let inbox = makeCollection(name: "Inbox", ownerFirebaseUID: "", context: ctx)

        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)

        XCTAssertEqual(inbox.ownerFirebaseUID, "uid1")
    }

    func testClaim_AlreadyOwn_IsIdempotent() throws {
        let ctx = try makeContext()
        let inbox = makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", context: ctx)

        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)

        XCTAssertEqual(inbox.ownerFirebaseUID, "uid1")
        XCTAssertEqual(try fetchCollections(ctx).count, 1)
    }

    func testClaim_OnlyForeignExists_UntouchedNoCreation() throws {
        let ctx = try makeContext()
        let foreign = makeCollection(name: "Inbox", ownerFirebaseUID: "otherUID", context: ctx)

        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)

        XCTAssertEqual(foreign.ownerFirebaseUID, "otherUID")
        XCTAssertEqual(try fetchCollections(ctx).count, 1)   // no new collection created for uid1
    }

    func testClaim_MultipleBootstrapDuplicates_AllClaimed_NotMerged() throws {
        let ctx = try makeContext()
        let first = makeCollection(name: "Inbox", ownerFirebaseUID: "", context: ctx)
        let second = makeCollection(name: "Inbox", ownerFirebaseUID: "", context: ctx)

        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)

        XCTAssertEqual(first.ownerFirebaseUID, "uid1")
        XCTAssertEqual(second.ownerFirebaseUID, "uid1")
        XCTAssertEqual(try fetchCollections(ctx).count, 2)   // merging is mergeProtectedCollections' job
    }

    func testClaim_InboxAndMySets_HandledIndependently() throws {
        let ctx = try makeContext()
        let inbox = makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", context: ctx)
        let mySets = makeCollection(name: "My Sets", ownerFirebaseUID: "", context: ctx)

        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)

        XCTAssertEqual(inbox.ownerFirebaseUID, "uid1")
        XCTAssertEqual(mySets.ownerFirebaseUID, "uid1")
    }

    func testClaim_NonUserCreatedCollectionWithProtectedName_Untouched() throws {
        let ctx = try makeContext()
        let curated = makeCollection(name: "Inbox", ownerFirebaseUID: "", isUserCreated: false, context: ctx)

        service.claimSystemCollections(firebaseUID: "uid1", context: ctx)

        XCTAssertEqual(curated.ownerFirebaseUID, "")   // not user-created — not a claim candidate
    }

    // MARK: - mergeProtectedCollections

    func testMerge_NoDuplicates_DoesNothing() throws {
        let ctx = try makeContext()
        makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", context: ctx)

        service.mergeProtectedCollections(context: ctx)

        XCTAssertEqual(try fetchCollections(ctx).count, 1)
    }

    func testMerge_BootstrapDuplicates_OldestSurvives() throws {
        let ctx = try makeContext()
        let older = makeCollection(
            name: "Inbox", ownerFirebaseUID: "", createdAt: .now.addingTimeInterval(-100), context: ctx
        )
        makeCollection(name: "Inbox", ownerFirebaseUID: "", createdAt: .now, context: ctx)

        service.mergeProtectedCollections(context: ctx)

        let remaining = try fetchCollections(ctx)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first === older)
    }

    func testMerge_DifferentOwners_NotMerged() throws {
        let ctx = try makeContext()
        makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", context: ctx)
        makeCollection(name: "Inbox", ownerFirebaseUID: "otherUID", context: ctx)

        service.mergeProtectedCollections(context: ctx)

        XCTAssertEqual(try fetchCollections(ctx).count, 2)
    }

    func testMerge_BootstrapVsClaimed_NotMerged() throws {
        let ctx = try makeContext()
        makeCollection(name: "Inbox", ownerFirebaseUID: "", context: ctx)
        makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", context: ctx)

        service.mergeProtectedCollections(context: ctx)

        XCTAssertEqual(try fetchCollections(ctx).count, 2)
    }

    func testMerge_ReparentsCardSets_AndCollapsesSameNameSets_MovingCards() throws {
        let ctx = try makeContext()
        let older = makeCollection(
            name: "Inbox", ownerFirebaseUID: "uid1", createdAt: .now.addingTimeInterval(-100), context: ctx
        )
        let newer = makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", createdAt: .now, context: ctx)

        let olderSet = makeCardSet(
            name: "Inbox", collectionId: older.id, createdAt: .now.addingTimeInterval(-100), context: ctx
        )
        let newerSet = makeCardSet(name: "Inbox", collectionId: newer.id, createdAt: .now, context: ctx)

        makeCard(en: "hello", setId: olderSet.id, context: ctx)
        makeCard(en: "world", setId: newerSet.id, context: ctx)

        service.mergeProtectedCollections(context: ctx)

        let remainingCollections = try fetchCollections(ctx)
        XCTAssertEqual(remainingCollections.count, 1)
        XCTAssertTrue(remainingCollections.first === older)

        let remainingSets = try fetchCardSets(ctx)
        XCTAssertEqual(remainingSets.count, 1)
        XCTAssertTrue(remainingSets.first === olderSet)

        let remainingCards = try fetchCards(ctx)
        XCTAssertEqual(remainingCards.count, 2)
        XCTAssertTrue(remainingCards.allSatisfy { $0.setId == olderSet.id })
    }

    func testMerge_DifferentlyNamedCardSets_StaySeparateAfterReparenting() throws {
        let ctx = try makeContext()
        let older = makeCollection(
            name: "My Sets", ownerFirebaseUID: "uid1", createdAt: .now.addingTimeInterval(-100), context: ctx
        )
        let newer = makeCollection(name: "My Sets", ownerFirebaseUID: "uid1", createdAt: .now, context: ctx)

        let travelSet = makeCardSet(name: "Travel", collectionId: older.id, context: ctx)
        let foodSet = makeCardSet(name: "Food", collectionId: newer.id, context: ctx)

        service.mergeProtectedCollections(context: ctx)

        XCTAssertEqual(try fetchCollections(ctx).count, 1)

        let remainingSets = try fetchCardSets(ctx)
        XCTAssertEqual(remainingSets.count, 2)   // different names — not collapsed
        XCTAssertTrue(remainingSets.allSatisfy { $0.collectionId == older.id })
        XCTAssertTrue(remainingSets.contains { $0 === travelSet })
        XCTAssertTrue(remainingSets.contains { $0 === foodSet })
    }

    func testMerge_InboxAndMySets_DedupeIndependently() throws {
        let ctx = try makeContext()
        let inboxOlder = makeCollection(
            name: "Inbox", ownerFirebaseUID: "uid1", createdAt: .now.addingTimeInterval(-100), context: ctx
        )
        makeCollection(name: "Inbox", ownerFirebaseUID: "uid1", createdAt: .now, context: ctx)
        let mySetsOnly = makeCollection(name: "My Sets", ownerFirebaseUID: "uid1", context: ctx)

        service.mergeProtectedCollections(context: ctx)

        let remaining = try fetchCollections(ctx)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains { $0 === inboxOlder })
        XCTAssertTrue(remaining.contains { $0 === mySetsOnly })
    }
}
