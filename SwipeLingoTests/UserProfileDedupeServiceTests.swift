import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - UserProfileDedupeServiceTests
//
// Tests cover:
//   • resolveProfile — no profiles / single "mine" / multiple "mine" (merges,
//     most recently updated wins) / mix of "mine" + foreign (foreign untouched) /
//     only foreign (returns nil, foreign untouched)
//   • hasForeignProfiles — pure predicate over the same "mine vs foreign" split

@MainActor
final class UserProfileDedupeServiceTests: XCTestCase {

    let service = UserProfileDedupeService()

    // MARK: - Helpers

    /// Creates a fresh in-memory ModelContainer + ModelContext for each test.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserProfile.self, configurations: config)
        return ModelContext(container)
    }

    @discardableResult
    private func makeProfile(
        firebaseUID: String,
        name: String = "",
        updatedAt: Date = .now,
        context: ModelContext
    ) -> UserProfile {
        let profile = UserProfile(name: name)
        profile.firebaseUID = firebaseUID
        profile.updatedAt = updatedAt   // plain assignment — no didSet on updatedAt itself
        context.insert(profile)
        return profile
    }

    private func fetchAll(_ context: ModelContext) throws -> [UserProfile] {
        try context.fetch(FetchDescriptor<UserProfile>())
    }

    // MARK: - resolveProfile

    func testResolveProfile_NoProfiles_ReturnsNil() throws {
        let ctx = try makeContext()
        let result = service.resolveProfile(firebaseUID: "uid1", allProfiles: [], context: ctx)
        XCTAssertNil(result)
    }

    func testResolveProfile_SingleMatchingProfile_ReturnsIt() throws {
        let ctx = try makeContext()
        let profile = makeProfile(firebaseUID: "uid1", context: ctx)
        let result = service.resolveProfile(firebaseUID: "uid1", allProfiles: [profile], context: ctx)
        XCTAssertTrue(result === profile)
    }

    func testResolveProfile_SingleUnclaimedProfile_ReturnsIt() throws {
        // Empty firebaseUID — just created, UID not yet stamped (see UserSessionSyncService).
        let ctx = try makeContext()
        let profile = makeProfile(firebaseUID: "", context: ctx)
        let result = service.resolveProfile(firebaseUID: "uid1", allProfiles: [profile], context: ctx)
        XCTAssertTrue(result === profile)
    }

    func testResolveProfile_MultipleMineProfiles_MergesKeepingMostRecent() throws {
        let ctx = try makeContext()
        let older = makeProfile(firebaseUID: "uid1", updatedAt: .now.addingTimeInterval(-100), context: ctx)
        let newer = makeProfile(firebaseUID: "uid1", updatedAt: .now, context: ctx)

        let result = service.resolveProfile(firebaseUID: "uid1", allProfiles: [older, newer], context: ctx)

        XCTAssertTrue(result === newer)
        let remaining = try fetchAll(ctx)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first === newer)
    }

    func testResolveProfile_UnclaimedAndMatchingUID_CountAsSameGroup_Merges() throws {
        // Empty-firebaseUID profile + matching-firebaseUID profile — both "mine", must merge together.
        let ctx = try makeContext()
        let unclaimed = makeProfile(firebaseUID: "", updatedAt: .now.addingTimeInterval(-100), context: ctx)
        let claimed = makeProfile(firebaseUID: "uid1", updatedAt: .now, context: ctx)

        let result = service.resolveProfile(firebaseUID: "uid1", allProfiles: [unclaimed, claimed], context: ctx)

        XCTAssertTrue(result === claimed)
        XCTAssertEqual(try fetchAll(ctx).count, 1)
    }

    func testResolveProfile_MixOfMineAndForeign_OnlyMergesMine_ForeignUntouched() throws {
        let ctx = try makeContext()
        let mineOlder = makeProfile(firebaseUID: "uid1", updatedAt: .now.addingTimeInterval(-100), context: ctx)
        let mineNewer = makeProfile(firebaseUID: "uid1", updatedAt: .now, context: ctx)
        let foreign = makeProfile(firebaseUID: "otherUID", context: ctx)

        let result = service.resolveProfile(
            firebaseUID: "uid1", allProfiles: [mineOlder, mineNewer, foreign], context: ctx
        )

        XCTAssertTrue(result === mineNewer)
        let remaining = try fetchAll(ctx)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.contains { $0 === mineNewer })
        XCTAssertTrue(remaining.contains { $0 === foreign })
    }

    func testResolveProfile_OnlyForeignProfiles_ReturnsNil_LeavesForeignUntouched() throws {
        let ctx = try makeContext()
        let foreign = makeProfile(firebaseUID: "otherUID", context: ctx)

        let result = service.resolveProfile(firebaseUID: "uid1", allProfiles: [foreign], context: ctx)

        XCTAssertNil(result)
        let remaining = try fetchAll(ctx)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first === foreign)
    }

    // MARK: - hasForeignProfiles

    func testHasForeignProfiles_Empty_ReturnsFalse() {
        XCTAssertFalse(service.hasForeignProfiles(firebaseUID: "uid1", allProfiles: []))
    }

    func testHasForeignProfiles_OnlyMineAndUnclaimed_ReturnsFalse() throws {
        let ctx = try makeContext()
        let mine = makeProfile(firebaseUID: "uid1", context: ctx)
        let unclaimed = makeProfile(firebaseUID: "", context: ctx)
        XCTAssertFalse(service.hasForeignProfiles(firebaseUID: "uid1", allProfiles: [mine, unclaimed]))
    }

    func testHasForeignProfiles_WithForeign_ReturnsTrue() throws {
        let ctx = try makeContext()
        let mine = makeProfile(firebaseUID: "uid1", context: ctx)
        let foreign = makeProfile(firebaseUID: "otherUID", context: ctx)
        XCTAssertTrue(service.hasForeignProfiles(firebaseUID: "uid1", allProfiles: [mine, foreign]))
    }
}
