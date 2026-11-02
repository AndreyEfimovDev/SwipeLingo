import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - AddEditCardViewModelTests
//
// Новый сет в карточке создаётся явной кнопкой «Add set» и только в своей коллекции пользователя:
//   • targetCollections / userSets — без системной коллекции Inbox и без чужих коллекций
//   • beginNewSet — коллекция по умолчанию: коллекция выбранного сета, иначе первая своя
//   • canAddNewSet — пустое имя, дубль в коллекции, нет коллекции → нельзя
//   • addNewSet — сет создаётся в выбранной коллекции (регрессия: раньше всегда в системную коллекцию) и выбирается
//   • canSave — во время ввода нового сета сохранить карточку нельзя

@MainActor
final class AddEditCardViewModelTests: XCTestCase {

    private let uid = "uid1"

    /// Контейнеры живут до конца теста: ModelContext не удерживает свой ModelContainer.
    private var containers: [ModelContainer] = []

    override func tearDown() {
        containers.removeAll()
        super.tearDown()
    }

    // MARK: - targetCollections / userSets

    func testTargetCollections_ExcludeInboxCollectionAndForeign() {
        let inboxCollection  = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let own     = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let foreign = Collection(name: "Foreign", ownerFirebaseUID: "otherUID")
        let curated = Collection(name: "Core Vocabulary", isUserCreated: false)

        let result = makeVM().targetCollections(allCollections: [inboxCollection, own, foreign, curated], firebaseUID: uid)

        XCTAssertEqual(result.map(\.id), [own.id])
    }

    func testUserSets_ExcludeInboxAndSetsOfInboxCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let own    = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let inbox  = CardSet(name: "Inbox", collectionId: inboxCollection.id)
        let legacy = CardSet(name: "My own set", collectionId: inboxCollection.id)
        let first  = CardSet(name: "1st set", collectionId: own.id)

        let result = makeVM().userSets(allSets: [inbox, legacy, first], allCollections: [inboxCollection, own], firebaseUID: uid)

        XCTAssertEqual(result.map(\.id), [first.id])
    }

    // MARK: - beginNewSet

    func testBeginNewSet_DefaultsToCollectionOfSelectedSet() {
        let a = Collection(name: "A", ownerFirebaseUID: uid)
        let b = Collection(name: "B", ownerFirebaseUID: uid)
        let setInB = CardSet(name: "set", collectionId: b.id)
        let vm = makeVM(preselectedSetId: setInB.id)

        vm.beginNewSet(allSets: [setInB], allCollections: [a, b], firebaseUID: uid)

        XCTAssertTrue(vm.isCreatingNewSet)
        XCTAssertEqual(vm.newSetCollectionId, b.id)
        XCTAssertEqual(vm.selectedSetId, setInB.id, "выбранный сет не сбрасывается — «Back» вернёт к нему")
    }

    func testBeginNewSet_WithoutSelectedSet_DefaultsToFirstOwnCollectionNotInboxCollection() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let own    = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let vm = makeVM()

        vm.beginNewSet(allSets: [], allCollections: [inboxCollection, own], firebaseUID: uid)

        XCTAssertEqual(vm.newSetCollectionId, own.id)
    }

    func testBeginNewSet_NoOwnCollections_LeavesCollectionEmpty() {
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let vm = makeVM()

        vm.beginNewSet(allSets: [], allCollections: [inboxCollection], firebaseUID: uid)

        XCTAssertNil(vm.newSetCollectionId)
    }

    func testEnsureNewSetCollection_PicksJustCreatedCollection() {
        let vm = makeVM()
        vm.beginNewSet(allSets: [], allCollections: [], firebaseUID: uid)
        let created = Collection(name: "New", ownerFirebaseUID: "")

        vm.ensureNewSetCollection(allCollections: [created], firebaseUID: uid)

        XCTAssertEqual(vm.newSetCollectionId, created.id)
    }

    // MARK: - canAddNewSet

    func testCanAddNewSet_FalseForEmptyName() {
        let own = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let vm = makeVM()
        vm.beginNewSet(allSets: [], allCollections: [own], firebaseUID: uid)
        vm.newSetName = "   "

        XCTAssertFalse(vm.canAddNewSet(allSets: [], allCollections: [own], firebaseUID: uid))
    }

    func testCanAddNewSet_FalseForDuplicateNameInSameCollection() {
        let own      = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let existing = CardSet(name: "Verbs", collectionId: own.id)
        let vm = makeVM()
        vm.beginNewSet(allSets: [existing], allCollections: [own], firebaseUID: uid)
        vm.newSetName = " verbs "

        XCTAssertFalse(vm.canAddNewSet(allSets: [existing], allCollections: [own], firebaseUID: uid))
    }

    func testCanAddNewSet_TrueForSameNameInOtherCollection() {
        let a = Collection(name: "A", ownerFirebaseUID: uid)
        let b = Collection(name: "B", ownerFirebaseUID: uid)
        let inA = CardSet(name: "Verbs", collectionId: a.id)
        let vm = makeVM()
        vm.beginNewSet(allSets: [inA], allCollections: [a, b], firebaseUID: uid)
        vm.newSetCollectionId = b.id
        vm.newSetName = "Verbs"

        XCTAssertTrue(vm.canAddNewSet(allSets: [inA], allCollections: [a, b], firebaseUID: uid))
    }

    func testCanAddNewSet_FalseWithoutCollection() {
        let vm = makeVM()
        vm.beginNewSet(allSets: [], allCollections: [], firebaseUID: uid)
        vm.newSetName = "Verbs"

        XCTAssertFalse(vm.canAddNewSet(allSets: [], allCollections: [], firebaseUID: uid))
    }

    // MARK: - addNewSet

    func testAddNewSet_CreatesSetInChosenCollectionAndSelectsIt() throws {
        let context = try makeContext()
        let inboxCollection = Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid)
        let own    = Collection(name: "1st collection", ownerFirebaseUID: uid)
        context.insert(inboxCollection)
        context.insert(own)
        let collections = [inboxCollection, own]
        let vm = makeVM()
        vm.beginNewSet(allSets: [], allCollections: collections, firebaseUID: uid)
        vm.newSetName = " My new set "

        let added = vm.addNewSet(context: context, allSets: [], allCollections: collections, firebaseUID: uid)

        XCTAssertTrue(added)
        let sets = try context.fetch(FetchDescriptor<CardSet>())
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.name, "My new set")
        XCTAssertEqual(sets.first?.collectionId, own.id, "регрессия: новый сет уходил в скрытую системную коллекцию")
        XCTAssertEqual(vm.selectedSetId, sets.first?.id)
        XCTAssertFalse(vm.isCreatingNewSet)
        XCTAssertEqual(vm.newSetName, "")
    }

    func testAddNewSet_RejectedLeavesStateUntouched() throws {
        let context = try makeContext()
        let vm = makeVM()
        vm.beginNewSet(allSets: [], allCollections: [], firebaseUID: uid)
        vm.newSetName = "Verbs"

        XCTAssertFalse(vm.addNewSet(context: context, allSets: [], allCollections: [], firebaseUID: uid))
        XCTAssertTrue(vm.isCreatingNewSet)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CardSet>()).isEmpty)
    }

    // MARK: - canSave

    func testCanSave_FalseWhileCreatingNewSet() {
        let own = Collection(name: "1st collection", ownerFirebaseUID: uid)
        let set = CardSet(name: "1st set", collectionId: own.id)
        let vm = makeVM(preselectedSetId: set.id)
        vm.en = "reliable"
        XCTAssertTrue(vm.canSave)

        vm.beginNewSet(allSets: [set], allCollections: [own], firebaseUID: uid)
        vm.newSetName = "My new set"

        XCTAssertFalse(vm.canSave, "сет создаётся только кнопкой «Add set», не при Save")
    }

    // MARK: - Helpers

    private func makeVM(preselectedSetId: UUID? = nil) -> AddEditCardViewModel {
        AddEditCardViewModel(card: nil, preselectedSetId: preselectedSetId)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Collection.self, CardSet.self, Card.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return ModelContext(container)
    }
}
