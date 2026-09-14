import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - SwipeLingoMigrationPlanTests
//
// Smoke-тест: schema + migrationPlan вместе реально собирают ModelContainer, а
// SchemaV1 перечисляет все 11 моделей приложения без опечаток/пропусков. Глубже
// тестировать пока нечего — версия схемы одна, переходов (MigrationStage) ещё
// нет; этот тест — страховка на будущее: если кто-то забудет добавить новую
// модель в SchemaV1.models, тест упадёт явно вместо тихого исчезновения данных.

@MainActor
final class SwipeLingoMigrationPlanTests: XCTestCase {

    func testSchemaV1_ContainsAllExpectedModels() {
        let modelNames = Set(SchemaV1.models.map { String(describing: $0) })
        let expected: Set<String> = [
            "Card", "CardSet", "Collection", "Pile", "PairsSet", "PairsPile",
            "UserProfile", "Book", "BookProgress", "BookBookmark", "AppSyncState"
        ]
        XCTAssertEqual(modelNames, expected)
    }

    func testContainer_BuildsSuccessfully_WithMigrationPlan() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        XCTAssertNoThrow(
            try ModelContainer(for: schema, migrationPlan: SwipeLingoMigrationPlan.self, configurations: [config])
        )
    }

    func testMigrationPlan_HasNoStagesYet() {
        // Единственная версия схемы — переходов между версиями пока нет.
        // Как только появится SchemaV2, этот тест нужно будет обновить —
        // намеренно хрупкий, чтобы напомнить об этом.
        XCTAssertTrue(SwipeLingoMigrationPlan.stages.isEmpty)
    }
}
