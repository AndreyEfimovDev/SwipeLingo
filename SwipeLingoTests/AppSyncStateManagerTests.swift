import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - AppSyncStateManagerTests
//
// Tests cover:
//   • claim(firebaseUID:) — all three outcomes (own record exists / unclaimed
//     bootstrap record gets claimed, settings preserved / neither exists, fresh
//     record created without touching a foreign account's record), plus the
//     duplicate-merge path (race: two own-account records already present).
//   • hasForeignAccountData(excluding:) — empty / only own record / only
//     bootstrap (doesn't count as foreign) / a foreign record present.
//
// mergeDuplicates is `private` — not directly testable even via @testable
// import — covered indirectly through claim()'s merge scenario below.

@MainActor
final class AppSyncStateManagerTests: XCTestCase {

    // MARK: - Helpers

    // On-disk, не isStoredInMemoryOnly: true — попытка воспроизвести malloc-краш
    // ("pointer being freed was not allocated"), стабильно всплывавший в этом
    // классе после save() на in-memory сторе (см. заголовочный комментарий
    // AppSyncStateService.swift). Файлы стора создаются во временной директории
    // и удаляются в tearDown.
    private var storeURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in storeURLs {
            removeStoreFiles(at: url)
        }
        storeURLs = []
    }

    /// Creates a fresh on-disk ModelContainer + ModelContext, and a manager
    /// bound to it, for each test. The store file is unique per call and
    /// removed in tearDown.
    private func makeManager() throws -> (ModelContext, AppSyncStateManager) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).store")
        storeURLs.append(url)
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: AppSyncState.self, configurations: config)
        let context = ModelContext(container)
        return (context, AppSyncStateManager(modelContext: context))
    }

    /// Удаляет .store + сопутствующие -wal/-shm файлы (тот же паттерн, что
    /// ModelContainerFactory.deleteStoreFiles).
    private func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: base.appendingPathExtension(ext + suffix))
        }
    }

    private func fetchAll(_ context: ModelContext) throws -> [AppSyncState] {
        try context.fetch(FetchDescriptor<AppSyncState>())
    }

    // fetch-all + .filter, не #Predicate — см. заголовочный комментарий
    // AppSyncStateService.swift про malloc-краш с #Predicate в этой версии Xcode/SDK.
    private func fetch(id: String, _ context: ModelContext) throws -> [AppSyncState] {
        try context.fetch(FetchDescriptor<AppSyncState>()).filter { $0.id == id }
    }

    // MARK: - claim: no existing records

    func testClaim_NoExistingRecords_CreatesFreshAccountScopedRecord() throws {
        let (ctx, manager) = try makeManager()

        let result = manager.claim(firebaseUID: "uid1")

        XCTAssertEqual(result.id, "app_state_uid1")
        XCTAssertEqual(manager.currentID, "app_state_uid1")
        XCTAssertFalse(result.hasCompletedOnboarding)
        XCTAssertEqual(try fetchAll(ctx).count, 1)
    }

    // MARK: - claim: unclaimed bootstrap record

    func testClaim_BootstrapRecordExists_ClaimsIt_PreservesSettings() throws {
        let (ctx, manager) = try makeManager()
        let bootstrap = AppSyncState(hasCompletedOnboarding: true)
        // AppSyncState.id defaults to the unclaimed bootstrap bucket — left as-is.
        ctx.insert(bootstrap)

        let result = manager.claim(firebaseUID: "uid1")

        XCTAssertEqual(result.id, "app_state_uid1")
        XCTAssertTrue(result.hasCompletedOnboarding)   // preserved, not reset
        XCTAssertTrue(try fetch(id: Constants.appSyncBootstrapID, ctx).isEmpty)   // renamed away
        XCTAssertEqual(try fetchAll(ctx).count, 1)   // same physical row, not duplicated
    }

    // MARK: - claim: own record already exists

    func testClaim_OwnRecordAlreadyExists_ReturnsIt_NoDuplicateCreated() throws {
        let (ctx, manager) = try makeManager()
        let existing = AppSyncState(hasCompletedOnboarding: true)
        existing.id = "app_state_uid1"
        ctx.insert(existing)

        let result = manager.claim(firebaseUID: "uid1")

        XCTAssertTrue(result === existing)
        XCTAssertEqual(try fetchAll(ctx).count, 1)
    }

    func testClaim_MultipleOwnRecordsRace_MergesToOne() throws {
        let (ctx, manager) = try makeManager()
        let older = AppSyncState(srsEnabled: false, hasCompletedOnboarding: false)
        older.id = "app_state_uid1"
        older.settingsUpdatedAt = .now.addingTimeInterval(-100)
        let newer = AppSyncState(srsEnabled: true, hasCompletedOnboarding: false)
        newer.id = "app_state_uid1"
        newer.settingsUpdatedAt = .now
        ctx.insert(older)
        ctx.insert(newer)

        let result = manager.claim(firebaseUID: "uid1")

        XCTAssertEqual(try fetch(id: "app_state_uid1", ctx).count, 1)
        XCTAssertTrue(result.srsEnabled)   // from the most recently updated duplicate
    }

    func testClaim_MultipleOwnRecordsRace_HasCompletedOnboardingTrueWins() throws {
        // hasCompletedOnboarding is a special case in mergeDuplicates: true wins
        // regardless of recency — once onboarding is done, a fresher-but-not-yet-
        // onboarded duplicate must not un-complete it.
        let (ctx, manager) = try makeManager()
        let olderCompleted = AppSyncState(hasCompletedOnboarding: true)
        olderCompleted.id = "app_state_uid1"
        olderCompleted.settingsUpdatedAt = .now.addingTimeInterval(-100)
        let newerNotCompleted = AppSyncState(hasCompletedOnboarding: false)
        newerNotCompleted.id = "app_state_uid1"
        newerNotCompleted.settingsUpdatedAt = .now
        ctx.insert(olderCompleted)
        ctx.insert(newerNotCompleted)

        let result = manager.claim(firebaseUID: "uid1")

        XCTAssertTrue(result.hasCompletedOnboarding)
    }

    // MARK: - claim: foreign record present

    func testClaim_ForeignRecordExists_NotTouched_CreatesOwnSeparateRecord() throws {
        let (ctx, manager) = try makeManager()
        let foreign = AppSyncState(hasCompletedOnboarding: true)
        foreign.id = "app_state_otherUID"
        ctx.insert(foreign)

        let result = manager.claim(firebaseUID: "uid1")

        XCTAssertEqual(result.id, "app_state_uid1")
        XCTAssertFalse(result.hasCompletedOnboarding)   // not inherited from the foreign record
        let stillForeign = try fetch(id: "app_state_otherUID", ctx)
        XCTAssertEqual(stillForeign.count, 1)
        XCTAssertTrue(stillForeign.first?.hasCompletedOnboarding == true)   // untouched
        XCTAssertEqual(try fetchAll(ctx).count, 2)
    }

    // MARK: - hasForeignAccountData

    func testHasForeignAccountData_Empty_ReturnsFalse() throws {
        let (_, manager) = try makeManager()
        XCTAssertFalse(manager.hasForeignAccountData(excluding: "uid1"))
    }

    func testHasForeignAccountData_OnlyOwnRecord_ReturnsFalse() throws {
        let (ctx, manager) = try makeManager()
        let own = AppSyncState()
        own.id = "app_state_uid1"
        ctx.insert(own)

        XCTAssertFalse(manager.hasForeignAccountData(excluding: "uid1"))
    }

    func testHasForeignAccountData_OnlyUnclaimedBootstrap_ReturnsFalse() throws {
        let (ctx, manager) = try makeManager()
        ctx.insert(AppSyncState())   // default id — unclaimed bootstrap bucket

        XCTAssertFalse(manager.hasForeignAccountData(excluding: "uid1"))
    }

    func testHasForeignAccountData_ForeignRecordExists_ReturnsTrue() throws {
        let (ctx, manager) = try makeManager()
        let foreign = AppSyncState()
        foreign.id = "app_state_otherUID"
        ctx.insert(foreign)

        XCTAssertTrue(manager.hasForeignAccountData(excluding: "uid1"))
    }
}
