import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - ExportServiceTests
//
// Бэкап карточек: экспорт из одной базы → восстановление в «чистую» (как после переустановки:
// системная коллекция и Inbox уже созданы заново, с другими id):
//   • карточки Inbox добавляются в текущий Inbox, второго Inbox не появляется
//   • сет попадает в свою коллекцию по названию; нет такой — создаётся с иконкой из бэкапа
//   • сеты одной коллекции не плодят одноимённые коллекции; существующая коллекция переиспользуется
//   • в системную коллекцию (контейнер Inbox) новые сеты не попадают — регрессия: раньше попадали все

@MainActor
final class ExportServiceTests: XCTestCase {

    private let uid = "uid1"
    private let service = ExportService()

    /// Контейнеры живут до конца теста: ModelContext не удерживает свой ModelContainer.
    private var containers: [ModelContainer] = []
    private var tempFiles: [URL] = []

    override func tearDown() {
        tempFiles.forEach { service.cleanupTempFile($0) }
        tempFiles.removeAll()
        containers.removeAll()
        super.tearDown()
    }

    // MARK: - Tests

    func testRestore_InboxCardsGoToCurrentInbox_SetsToTheirCollection() throws {
        let source = try makeContext()
        let sourceInbox = seedInbox(in: source)
        addCard("hello", to: sourceInbox, in: source)
        let travel = Collection(name: "Travel", icon: "airplane", ownerFirebaseUID: uid)
        source.insert(travel)
        let verbs = CardSet(name: "Verbs", collectionId: travel.id)
        source.insert(verbs)
        addCard("go", to: verbs, in: source)
        try source.save()

        let target = try makeContext()
        let targetInbox = seedInbox(in: target)
        try target.save()

        let result = service.importBackup(from: try export(source), into: target, firebaseUID: uid)

        XCTAssertEqual(result.newSets, 1, "Inbox не считается новым сетом")
        XCTAssertEqual(result.newCards, 2)

        let sets = try target.fetch(FetchDescriptor<CardSet>())
        XCTAssertEqual(sets.filter { $0.name == "Inbox" }.count, 1, "второго Inbox быть не должно")
        XCTAssertEqual(try cards(in: targetInbox, target).map(\.en), ["hello"])

        let restoredTravel = try XCTUnwrap(try target.fetch(FetchDescriptor<Collection>()).first { $0.name == "Travel" })
        XCTAssertEqual(restoredTravel.icon, "airplane")
        XCTAssertEqual(restoredTravel.ownerFirebaseUID, uid)
        let restoredVerbs = try XCTUnwrap(sets.first { $0.id == verbs.id })
        XCTAssertEqual(restoredVerbs.collectionId, restoredTravel.id)
        XCTAssertEqual(try cards(in: restoredVerbs, target).map(\.en), ["go"])

        let containerId = try XCTUnwrap(try target.fetch(FetchDescriptor<Collection>()).first { $0.isInbox }?.id)
        XCTAssertEqual(sets.filter { $0.collectionId == containerId }.map(\.id), [targetInbox.id],
                       "регрессия: восстановленные сеты уходили в скрытую системную коллекцию")
    }

    func testRestore_SetsOfOneCollectionShareOneCreatedCollection() throws {
        let source = try makeContext()
        _ = seedInbox(in: source)
        let travel = Collection(name: "Travel", ownerFirebaseUID: uid)
        source.insert(travel)
        source.insert(CardSet(name: "Verbs", collectionId: travel.id))
        source.insert(CardSet(name: "Nouns", collectionId: travel.id))
        try source.save()

        let target = try makeContext()
        _ = seedInbox(in: target)
        try target.save()

        _ = service.importBackup(from: try export(source), into: target, firebaseUID: uid)

        let travels = try target.fetch(FetchDescriptor<Collection>()).filter { $0.name == "Travel" }
        XCTAssertEqual(travels.count, 1)
        let setsInTravel = try target.fetch(FetchDescriptor<CardSet>()).filter { $0.collectionId == travels.first?.id }
        XCTAssertEqual(Set(setsInTravel.map(\.name)), ["Verbs", "Nouns"])
    }

    func testRestore_ReusesExistingCollectionWithSameName() throws {
        let source = try makeContext()
        _ = seedInbox(in: source)
        let travel = Collection(name: "Travel", ownerFirebaseUID: uid)
        source.insert(travel)
        source.insert(CardSet(name: "Verbs", collectionId: travel.id))
        try source.save()

        let target = try makeContext()
        _ = seedInbox(in: target)
        let existingTravel = Collection(name: "Travel", ownerFirebaseUID: uid)
        target.insert(existingTravel)
        try target.save()

        _ = service.importBackup(from: try export(source), into: target, firebaseUID: uid)

        XCTAssertEqual(try target.fetch(FetchDescriptor<Collection>()).filter { $0.name == "Travel" }.count, 1)
        let verbs = try XCTUnwrap(try target.fetch(FetchDescriptor<CardSet>()).first { $0.name == "Verbs" })
        XCTAssertEqual(verbs.collectionId, existingTravel.id)
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Collection.self, CardSet.self, Card.self, PairsSet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return ModelContext(container)
    }

    /// Системная коллекция со своим Inbox — как после `SystemSeeder` и claim.
    private func seedInbox(in context: ModelContext) -> CardSet {
        let container = Collection(name: Collection.inboxCollectionName, icon: "folder", ownerFirebaseUID: uid)
        context.insert(container)
        let inbox = CardSet(name: "Inbox", collectionId: container.id)
        context.insert(inbox)
        return inbox
    }

    private func addCard(_ en: String, to set: CardSet, in context: ModelContext) {
        context.insert(Card(en: en, item: "", setId: set.id))
    }

    private func cards(in set: CardSet, _ context: ModelContext) throws -> [Card] {
        let setId = set.id
        return try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.setId == setId }))
    }

    private func export(_ context: ModelContext) throws -> URL {
        let url = try service.exportAll(from: context).get()
        tempFiles.append(url)
        return url
    }
}
