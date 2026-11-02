import XCTest
@testable import SwipeLingo

// MARK: - ExampleEditorViewModelTests
//
// Удаление примеров карточки в ExampleEditorSheet:
//   • пример со словаря удаляется вместе со своим переводом
//   • у пользовательской карточки удаляются и основные примеры
//   • основные примеры облачной карточки не удаляются (их вернул бы Firestore-синк)
//   • переводов меньше, чем примеров — удаление не падает и не сдвигает чужие переводы
//   • hasChanges отражает только реальные изменения

@MainActor
final class ExampleEditorViewModelTests: XCTestCase {

    func testDeleteDictionaryExample_RemovesItsTranslation() {
        let vm = ExampleEditorViewModel(
            sampleEN: [], sampleItem: [],
            userSampleEN: ["one", "two"], userSampleItem: ["один", "два"],
            isUserCard: false
        )

        vm.delete(row(vm, .dictionary, 0))

        XCTAssertEqual(vm.userSampleEN, ["two"])
        XCTAssertEqual(vm.userSampleItem, ["два"])
        XCTAssertTrue(vm.hasChanges)
    }

    func testUserCard_CardExampleIsRemovable() {
        let vm = ExampleEditorViewModel(
            sampleEN: ["one", "two"], sampleItem: ["один", "два"],
            userSampleEN: [], userSampleItem: [],
            isUserCard: true
        )

        vm.delete(row(vm, .card, 1))

        XCTAssertEqual(vm.sampleEN, ["one"])
        XCTAssertEqual(vm.sampleItem, ["один"])
        XCTAssertFalse(vm.hasLockedRows)
    }

    func testCloudCard_CardExampleIsLocked() {
        let vm = ExampleEditorViewModel(
            sampleEN: ["cloud"], sampleItem: ["облако"],
            userSampleEN: ["mine"], userSampleItem: ["моё"],
            isUserCard: false
        )
        let cloudRow = row(vm, .card, 0)

        XCTAssertFalse(cloudRow.isRemovable)
        XCTAssertTrue(row(vm, .dictionary, 0).isRemovable)
        XCTAssertTrue(vm.hasLockedRows)

        vm.delete(cloudRow)

        XCTAssertEqual(vm.sampleEN, ["cloud"])
        XCTAssertFalse(vm.hasChanges)
    }

    func testFewerTranslationsThanExamples_TranslationsStayInTheirGroup() {
        // У облачной карточки 2 примера и 1 перевод: перевод примера со словаря
        // не должен «съехать» на второй облачный пример.
        let vm = ExampleEditorViewModel(
            sampleEN: ["a", "b"], sampleItem: ["а"],
            userSampleEN: ["mine"], userSampleItem: ["моё"],
            isUserCard: true
        )

        XCTAssertEqual(vm.rows.map(\.translation), ["а", nil, "моё"])

        vm.delete(row(vm, .card, 1))

        XCTAssertEqual(vm.sampleEN, ["a"])
        XCTAssertEqual(vm.sampleItem, ["а"])
        XCTAssertEqual(vm.rows.map(\.translation), ["а", "моё"])
    }

    func testNoDeletions_HasNoChanges() {
        let vm = ExampleEditorViewModel(
            sampleEN: ["a"], sampleItem: ["а"],
            userSampleEN: ["b"], userSampleItem: ["б"],
            isUserCard: true
        )

        XCTAssertFalse(vm.hasChanges)
    }

    // MARK: - Helpers

    private func row(_ vm: ExampleEditorViewModel, _ group: ExampleEditorViewModel.Row.Group, _ index: Int) -> ExampleEditorViewModel.Row {
        guard let row = vm.rows.first(where: { $0.group == group && $0.index == index }) else {
            XCTFail("Нет строки \(group) #\(index)")
            return ExampleEditorViewModel.Row(group: group, index: index, en: "", translation: nil, isRemovable: false)
        }
        return row
    }
}
