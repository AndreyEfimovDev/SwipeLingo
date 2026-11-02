import XCTest
import SwiftData
@testable import SwipeLingo

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
