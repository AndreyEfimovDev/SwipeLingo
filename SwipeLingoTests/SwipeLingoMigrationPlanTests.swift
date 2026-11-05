import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - SwipeLingoMigrationPlanTests
//
// Схема и миграции:
//   • SchemaV1 перечисляет все 11 исходных моделей; SchemaV2 = SchemaV1 + StudyDay — если кто-то забудет
//     модель в списке, тест упадёт явно вместо тихого исчезновения данных
//   • schema + migrationPlan собирают ModelContainer
//   • план: V1 → V2 одной лёгкой миграцией; приложение открывает CurrentSchema = SchemaV2
//   • настоящая миграция: стор, созданный в V1 на диске, открывается в V2 без потери данных и принимает StudyDay

@MainActor
final class SwipeLingoMigrationPlanTests: XCTestCase {

    private let v1Models: Set<String> = [
        "Card", "CardSet", "Collection", "Pile", "PairsSet", "PairsPile",
        "UserProfile", "Book", "BookProgress", "BookBookmark", "AppSyncState"
    ]

    func testSchemaV1_ContainsAllExpectedModels() {
        XCTAssertEqual(Set(SchemaV1.models.map { String(describing: $0) }), v1Models)
    }

    func testSchemaV2_IsV1PlusStudyDay() {
        XCTAssertEqual(Set(SchemaV2.models.map { String(describing: $0) }), v1Models.union(["StudyDay"]))
        XCTAssertTrue(CurrentSchema.self == SchemaV2.self)
    }

    func testContainer_BuildsSuccessfully_WithMigrationPlan() throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        XCTAssertNoThrow(
            try ModelContainer(for: schema, migrationPlan: SwipeLingoMigrationPlan.self, configurations: [config])
        )
    }

    func testMigrationPlan_OneLightweightStageV1ToV2() {
        // Намеренно хрупкий: при появлении SchemaV3 тест напомнит обновить план и этот список.
        XCTAssertEqual(SwipeLingoMigrationPlan.schemas.count, 2)
        XCTAssertEqual(SwipeLingoMigrationPlan.stages.count, 1)
    }

    func testMigration_V1StoreOnDisk_OpensInV2_KeepsData() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")

        // Стор «как у пользователя до обновления»: схема V1.
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: V1OnlyPlan.self, configurations: [config])
            let context = ModelContext(container)
            context.insert(Collection(name: "Travel"))
            try context.save()
        }

        // Тот же файл в текущей схеме через план миграции.
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: SwipeLingoMigrationPlan.self, configurations: [config])
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Collection>()).map(\.name), ["Travel"])
        context.insert(StudyDay(dayKey: "2026-11-05", deviceID: "D", ownerFirebaseUID: "U"))
        XCTAssertNoThrow(try context.save())
    }
}

/// План «до обновления» — только SchemaV1: им создаётся стор старой версии для теста миграции.
private enum V1OnlyPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
