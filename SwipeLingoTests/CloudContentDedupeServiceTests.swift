import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - CloudContentDedupeServiceTests
//
// Дубли облачного контента с одним firestoreId (гонка CloudKit: синк вставил контент раньше, чем CloudKit
// довёз копии с прошлой установки/другого устройства). Без дедупа ImportFSService падал на
// Dictionary(uniqueKeysWithValues:) при следующем синке.
//   • коллекции: выживает самая старая, сеты и PairsSet переводятся на неё
//   • сеты: выживает самая старая (при равной дате — по id), карточки и Pile.setIds переводятся, порядок сохранён
//   • карточки: выживает проверенная последней (SRS), статус/избранное/isNew/примеры объединяются
//   • мягкое удаление любой копии переходит на выжившую
//   • PairsSet: выживает проверенный последним, PairsPile.setIds переводится
//   • пользовательский контент и записи без firestoreId не трогаются; повторный вызов ничего не меняет

@MainActor
final class CloudContentDedupeServiceTests: XCTestCase {

    private let service = CloudContentDedupeService()

    // MARK: - Collections

    func testDuplicateCollections_OldestSurvives_SetsRepointed() throws {
        let context = try makeContext()
        let old = cloudCollection("COLL", createdAt: date(1))
        let new = cloudCollection("COLL", createdAt: date(2))
        context.insert(old)
        context.insert(new)
        let cardSet = CardSet(name: "Set", collectionId: new.id, isUserCreated: false)
        let pairsSet = PairsSet(title: "Pairs", collectionId: new.id)
        context.insert(cardSet)
        context.insert(pairsSet)

        let removed = service.mergeDuplicates(context: context)

        let collections = try context.fetch(FetchDescriptor<Collection>())
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(collections.map(\.id), [old.id])
        XCTAssertEqual(cardSet.collectionId, old.id)
        XCTAssertEqual(pairsSet.collectionId, old.id)
    }

    // MARK: - CardSets

    func testDuplicateCardSets_EqualDates_SmallerIdSurvives_CardsAndPileRepointed() throws {
        let context = try makeContext()
        let collectionId = UUID()
        let small = cloudSet("SET", id: uuid("00000000-0000-0000-0000-000000000001"), collectionId: collectionId)
        let big   = cloudSet("SET", id: uuid("00000000-0000-0000-0000-000000000002"), collectionId: collectionId)
        let other = cloudSet("OTHER", id: UUID(), collectionId: collectionId)
        [small, big, other].forEach { context.insert($0) }
        let card = cloudCard("CARD", setId: big.id)
        context.insert(card)
        // Пайл ссылается на обе копии и на другой сет: после мержа — без повтора, порядок сохранён.
        let pile = Pile(name: "Pile", setIds: [big.id, other.id, small.id])
        context.insert(pile)

        let removed = service.mergeDuplicates(context: context)

        let sets = try context.fetch(FetchDescriptor<CardSet>())
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(Set(sets.map(\.id)), [small.id, other.id])
        XCTAssertEqual(card.setId, small.id)
        XCTAssertEqual(pile.setIds, [small.id, other.id])
    }

    func testDuplicateCardSets_SoftDeletedCopy_SurvivorSoftDeleted() throws {
        let context = try makeContext()
        let old = cloudSet("SET", id: UUID(), collectionId: UUID(), createdAt: date(1))
        let deleted = cloudSet("SET", id: UUID(), collectionId: UUID(), createdAt: date(2))
        deleted.isSoftDeleted = true
        context.insert(old)
        context.insert(deleted)

        service.mergeDuplicates(context: context)

        let sets = try context.fetch(FetchDescriptor<CardSet>())
        XCTAssertEqual(sets.map(\.id), [old.id])
        XCTAssertTrue(old.isSoftDeleted)
    }

    // MARK: - Cards

    func testDuplicateCards_ReviewedSurvives_FieldsMerged() throws {
        let context = try makeContext()
        let setId = UUID()
        let reviewed = cloudCard("CARD", setId: setId)
        reviewed.lastReviewed = date(10)
        reviewed.repetitions = 3
        reviewed.isNew = false
        let fresh = cloudCard("CARD", setId: setId)
        fresh.isNew = true
        fresh.isFavorite = true
        fresh.status = .learnt
        fresh.userSampleEN = ["My example"]
        fresh.userSampleItem = ["Мой пример"]
        context.insert(reviewed)
        context.insert(fresh)

        let removed = service.mergeDuplicates(context: context)

        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(cards.map(\.id), [reviewed.id])
        XCTAssertEqual(reviewed.repetitions, 3)
        XCTAssertEqual(reviewed.status, .learnt)
        XCTAssertTrue(reviewed.isFavorite)
        XCTAssertFalse(reviewed.isNew)
        XCTAssertEqual(reviewed.userSampleEN, ["My example"])
        XCTAssertEqual(reviewed.userSampleItem, ["Мой пример"])
    }

    func testDuplicateCards_DeletedStatusWinsOverLearnt() throws {
        let context = try makeContext()
        let setId = UUID()
        let learnt = cloudCard("CARD", setId: setId)
        learnt.status = .learnt
        learnt.lastReviewed = date(10)
        let deleted = cloudCard("CARD", setId: setId)
        deleted.status = .deleted
        context.insert(learnt)
        context.insert(deleted)

        service.mergeDuplicates(context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).map(\.status), [.deleted])
    }

    func testCardsOfDuplicateSets_MergedInSamePass() throws {
        let context = try makeContext()
        let collectionId = UUID()
        let old = cloudSet("SET", id: UUID(), collectionId: collectionId, createdAt: date(1))
        let new = cloudSet("SET", id: UUID(), collectionId: collectionId, createdAt: date(2))
        context.insert(old)
        context.insert(new)
        context.insert(cloudCard("CARD", setId: old.id))
        context.insert(cloudCard("CARD", setId: new.id))

        // Даже в «лёгком» режиме наблюдателя: сеты схлопнулись → карточки проверяются.
        let removed = service.mergeDuplicates(context: context, cardCheck: .onlyAfterSetMerge)

        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(cards.map(\.setId), [old.id])
    }

    func testOnlyAfterSetMerge_NoSetDuplicates_CardsUntouched() throws {
        let context = try makeContext()
        let setId = UUID()
        context.insert(cloudCard("CARD", setId: setId))
        context.insert(cloudCard("CARD", setId: setId))

        let removed = service.mergeDuplicates(context: context, cardCheck: .onlyAfterSetMerge)

        XCTAssertEqual(removed, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Card>()), 2)
    }

    // MARK: - PairsSets

    func testDuplicatePairsSets_ReviewedSurvives_PairsPileRepointed() throws {
        let context = try makeContext()
        let reviewed = cloudPairsSet("PAIRS", createdAt: date(2))
        reviewed.lastReviewed = date(10)
        reviewed.isNew = false
        let fresh = cloudPairsSet("PAIRS", createdAt: date(1))
        fresh.isNew = true
        context.insert(reviewed)
        context.insert(fresh)
        let pile = PairsPile(name: "Pile", setIds: [fresh.id])
        context.insert(pile)

        let removed = service.mergeDuplicates(context: context)

        let sets = try context.fetch(FetchDescriptor<PairsSet>())
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(sets.map(\.id), [reviewed.id])
        XCTAssertFalse(reviewed.isNew)
        XCTAssertEqual(pile.setIds, [reviewed.id])
    }

    // MARK: - Не трогаем лишнего

    func testUserContentAndMissingFirestoreId_Untouched_SecondRunNoOp() throws {
        let context = try makeContext()
        let collectionId = UUID()
        // Пользовательские сеты с одинаковым (случайно совпавшим) firestoreId — не облачный контент.
        let userA = CardSet(name: "A", collectionId: collectionId, isUserCreated: true)
        let userB = CardSet(name: "B", collectionId: collectionId, isUserCreated: true)
        userA.firestoreId = "SAME"
        userB.firestoreId = "SAME"
        // Облачные сеты без firestoreId — сопоставлять не по чему.
        let noIdA = CardSet(name: "C", collectionId: collectionId, isUserCreated: false)
        let noIdB = CardSet(name: "D", collectionId: collectionId, isUserCreated: false)
        [userA, userB, noIdA, noIdB].forEach { context.insert($0) }
        context.insert(cloudSet("ONE", id: UUID(), collectionId: collectionId))
        context.insert(cloudSet("TWO", id: UUID(), collectionId: collectionId))

        XCTAssertEqual(service.mergeDuplicates(context: context), 0)
        XCTAssertEqual(service.mergeDuplicates(context: context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardSet>()), 6)
    }

    // MARK: - replacingIds

    func testReplacingIds_NothingToReplace_ReturnsSameOrder() {
        let ids = [UUID(), UUID(), UUID()]
        XCTAssertEqual(CloudContentDedupeService.replacingIds(in: ids, with: [UUID(): UUID()]), ids)
    }

    // MARK: - Helpers

    private func cloudCollection(_ firestoreId: String, createdAt: Date) -> Collection {
        let collection = Collection(name: "Cloud", isUserCreated: false, createdAt: createdAt)
        collection.firestoreId = firestoreId
        return collection
    }

    private func cloudSet(_ firestoreId: String, id: UUID, collectionId: UUID, createdAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> CardSet {
        let set = CardSet(id: id, name: firestoreId, collectionId: collectionId, isUserCreated: false, createdAt: createdAt)
        set.firestoreId = firestoreId
        return set
    }

    private func cloudCard(_ firestoreId: String, setId: UUID) -> Card {
        let card = Card(en: "word", item: "слово", setId: setId)
        card.firestoreId = firestoreId
        return card
    }

    private func cloudPairsSet(_ firestoreId: String, createdAt: Date) -> PairsSet {
        let set = PairsSet(title: firestoreId, createdAt: createdAt)
        set.firestoreId = firestoreId
        return set
    }

    private func uuid(_ string: String) -> UUID {
        UUID(uuidString: string) ?? UUID()
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + seconds)
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Collection.self, CardSet.self, Card.self, Pile.self, PairsSet.self, PairsPile.self,
            configurations: config
        )
        return ModelContext(container)
    }
}
