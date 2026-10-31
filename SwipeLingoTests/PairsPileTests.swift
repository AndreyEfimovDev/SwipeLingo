import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - PairsPileServiceTests
//
// Порядок показа СЕТОВ внутри PairsPile (shuffleMethod):
//   • .sequential — порядок pile.setIds (порядок добавления сетов в пайл)
//   • .random     — детерминированная перестановка по seed: тот же seed → тот же порядок,
//                   другой seed → (как правило) другой; состав сетов не теряется и не дублируется
//   • .prioritized в Pairs недоступен в UI → трактуется как .sequential
//   • id из setIds, для которых нет загруженного сета, пропускаются
// Регрессия: shuffleMethod выбирался в билдере, но нигде не применялся — порядок всегда был
// порядком setIds (а тот, в свою очередь, получался из Set<UUID> — произвольным).
// Порядок ПАР внутри сета не меняется — сервис возвращает те же PairsSet как есть.

@MainActor
final class PairsPileServiceTests: XCTestCase {

    private let service = PairsPileService()
    /// Контейнеры живут до конца теста: ModelContext не удерживает свой ModelContainer.
    private var containers: [ModelContainer] = []

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PairsSet.self, PairsPile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return ModelContext(container)
    }

    private func makeSets(_ count: Int, in context: ModelContext) -> [PairsSet] {
        (0..<count).map { index in
            let set = PairsSet(title: "Set \(index)")
            context.insert(set)
            return set
        }
    }

    private func makePile(setIds: [UUID], method: ShuffleMethod, in context: ModelContext) -> PairsPile {
        let pile = PairsPile(name: "Pile", setIds: setIds, shuffleMethod: method)
        context.insert(pile)
        return pile
    }

    private func ids(_ sets: [PairsSet]) -> [UUID] { sets.map(\.id) }

    // MARK: - .sequential

    func testSequentialKeepsPileOrder() throws {
        let context = try makeContext()
        let sets = makeSets(5, in: context)
        // Порядок в пайле намеренно не совпадает ни с порядком allSets, ни с createdAt
        let pileOrder = [sets[3], sets[0], sets[4], sets[1]].map(\.id)
        let pile = makePile(setIds: pileOrder, method: .sequential, in: context)

        let result = service.sets(for: pile, from: sets)

        XCTAssertEqual(ids(result), pileOrder)
    }

    func testSequentialIgnoresSeed() throws {
        let context = try makeContext()
        let sets = makeSets(5, in: context)
        let pile = makePile(setIds: ids(sets), method: .sequential, in: context)

        let first  = service.sets(for: pile, from: sets, seed: 1)
        let second = service.sets(for: pile, from: sets, seed: 999)

        XCTAssertEqual(ids(first), ids(second))
        XCTAssertEqual(ids(first), ids(sets))
    }

    func testPrioritizedFallsBackToPileOrder() throws {
        let context = try makeContext()
        let sets = makeSets(4, in: context)
        let pileOrder = [sets[2], sets[0], sets[3]].map(\.id)
        let pile = makePile(setIds: pileOrder, method: .prioritized, in: context)

        let result = service.sets(for: pile, from: sets, seed: 42)

        XCTAssertEqual(ids(result), pileOrder)
    }

    // MARK: - .random

    func testRandomWithSameSeedIsRepeatable() throws {
        let context = try makeContext()
        let sets = makeSets(8, in: context)
        let pile = makePile(setIds: ids(sets), method: .random, in: context)

        let first  = service.sets(for: pile, from: sets, seed: 12345)
        let second = service.sets(for: pile, from: sets, seed: 12345)

        XCTAssertEqual(ids(first), ids(second), "один seed — один порядок (иначе порядок менялся бы при каждой перерисовке)")
    }

    func testRandomWithDifferentSeedsProducesDifferentOrders() throws {
        let context = try makeContext()
        let sets = makeSets(6, in: context)
        let pile = makePile(setIds: ids(sets), method: .random, in: context)

        let orders = Set((UInt64(0)..<20).map { seed in
            service.sets(for: pile, from: sets, seed: seed).map(\.id)
        })

        XCTAssertGreaterThan(orders.count, 1, "random не должен возвращать один и тот же порядок для разных seed")
    }

    func testRandomKeepsExactlyTheSameSets() throws {
        let context = try makeContext()
        let sets = makeSets(7, in: context)
        let pile = makePile(setIds: ids(sets), method: .random, in: context)

        for seed in UInt64(0)..<10 {
            let result = service.sets(for: pile, from: sets, seed: seed)
            XCTAssertEqual(result.count, sets.count, "seed \(seed): сеты потеряны или продублированы")
            XCTAssertEqual(Set(ids(result)), Set(ids(sets)), "seed \(seed): изменился состав сетов")
        }
    }

    // MARK: - Общее

    func testUnknownIdsAreSkipped() throws {
        let context = try makeContext()
        let sets = makeSets(3, in: context)
        let unknown = UUID()
        let setIds = [sets[0].id, unknown, sets[2].id]

        let sequential = service.sets(
            for: makePile(setIds: setIds, method: .sequential, in: context), from: sets)
        let random = service.sets(
            for: makePile(setIds: setIds, method: .random, in: context), from: sets, seed: 7)

        XCTAssertEqual(ids(sequential), [sets[0].id, sets[2].id])
        XCTAssertEqual(Set(ids(random)), Set([sets[0].id, sets[2].id]))
        XCTAssertEqual(random.count, 2)
    }

    func testEmptyAndSingleSetPiles() throws {
        let context = try makeContext()
        let sets = makeSets(1, in: context)

        let empty = service.sets(
            for: makePile(setIds: [], method: .random, in: context), from: sets, seed: 3)
        let single = service.sets(
            for: makePile(setIds: [sets[0].id], method: .random, in: context), from: sets, seed: 3)

        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(ids(single), [sets[0].id])
    }
}

// MARK: - PairsPileBuilderViewModelTests
//
// Порядок выбора сетов в билдере = порядок в PairsPile.setIds (это порядок для .sequential).
// Раньше выбор хранился в Set<UUID>, а Array(Set) давал произвольный порядок — «Sequential»
// не соответствовал подписи "in the order they were added".

@MainActor
final class PairsPileBuilderViewModelTests: XCTestCase {

    private var containers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PairsSet.self, PairsPile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return ModelContext(container)
    }

    func testSaveKeepsSelectionOrder() throws {
        let context = try makeContext()
        let (a, b, c) = (UUID(), UUID(), UUID())
        let vm = PairsPileBuilderViewModel()
        vm.name = "Pile"

        vm.toggleSet(a)
        vm.toggleSet(c)
        vm.toggleSet(b)
        let pile = vm.save(context: context)

        XCTAssertEqual(pile.setIds, [a, c, b])
    }

    func testDeselectKeepsOrderOfOthersAndReselectAppendsToEnd() {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let vm = PairsPileBuilderViewModel()

        vm.toggleSet(a)
        vm.toggleSet(b)
        vm.toggleSet(c)
        vm.toggleSet(b)
        XCTAssertEqual(vm.selectedSetIds, [a, c])

        vm.toggleSet(b)
        XCTAssertEqual(vm.selectedSetIds, [a, c, b])
    }

    func testEditingPileLoadsPileOrder() throws {
        let context = try makeContext()
        let (a, b, c) = (UUID(), UUID(), UUID())
        let pile = PairsPile(name: "Pile", setIds: [c, a, b])
        context.insert(pile)

        let vm = PairsPileBuilderViewModel(editingPile: pile)

        XCTAssertEqual(vm.selectedSetIds, [c, a, b])
        XCTAssertFalse(vm.hasChanges, "без правок билдер не должен считать пайл изменённым")
    }

    func testChangingOrderCountsAsChangeAndIsSaved() throws {
        let context = try makeContext()
        let (a, b) = (UUID(), UUID())
        let pile = PairsPile(name: "Pile", setIds: [a, b])
        context.insert(pile)
        let vm = PairsPileBuilderViewModel(editingPile: pile)

        vm.toggleSet(a)   // убрали
        vm.toggleSet(a)   // вернули — теперь в конце: [b, a]

        XCTAssertEqual(vm.selectedSetIds, [b, a])
        XCTAssertTrue(vm.hasChanges, "порядок влияет на показ при Sequential — это изменение")

        vm.save(context: context)
        XCTAssertEqual(pile.setIds, [b, a])
    }
}
