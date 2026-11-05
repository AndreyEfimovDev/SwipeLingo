import XCTest
@testable import SwipeLingo

// MARK: - BookCatalogVisibilityTests
//
// Видимость книги каталога по флагу isPublished из Firestore:
//   • isPublished == true — видна всем, без плашки TESTING
//   • false или поля нет — только тестировщику, с плашкой TESTING; остальным не загружается
//   • тестировщик — только UID из списка; nil и пустой UID — не тестировщик
//   • после синка удаляются книги, которых нет в каталоге, и снятые с публикации; показанные остаются

@MainActor
final class BookCatalogVisibilityTests: XCTestCase {

    func testPublished_ShownToEveryone_WithoutTestingBadge() {
        XCTAssertEqual(BookCatalogVisibility.decide(isPublished: true, isTester: false), .show(isTesting: false))
        XCTAssertEqual(BookCatalogVisibility.decide(isPublished: true, isTester: true), .show(isTesting: false))
    }

    func testDraft_ShownOnlyToTester_WithTestingBadge() {
        XCTAssertEqual(BookCatalogVisibility.decide(isPublished: false, isTester: true), .show(isTesting: true))
        XCTAssertEqual(BookCatalogVisibility.decide(isPublished: false, isTester: false), .skip)
    }

    func testMissingFlag_TreatedAsDraft() {
        XCTAssertEqual(BookCatalogVisibility.decide(isPublished: nil, isTester: true), .show(isTesting: true))
        XCTAssertEqual(BookCatalogVisibility.decide(isPublished: nil, isTester: false), .skip)
    }

    func testIsTester_OnlyListedUID() {
        let testers: Set<String> = ["TESTER_UID"]
        XCTAssertTrue(BookCatalogVisibility.isTester(uid: "TESTER_UID", testerUIDs: testers))
        XCTAssertFalse(BookCatalogVisibility.isTester(uid: "OTHER_UID", testerUIDs: testers))
        XCTAssertFalse(BookCatalogVisibility.isTester(uid: nil, testerUIDs: testers))
        XCTAssertFalse(BookCatalogVisibility.isTester(uid: "", testerUIDs: [""]))
    }

    // MARK: - firestoreIdsToRemove

    func testRemove_BookMissingFromCatalog_Removed() {
        let ids = BookCatalogVisibility.firestoreIdsToRemove(localIds: ["A", "B"], catalogIds: ["A"], skippedIds: [])
        XCTAssertEqual(ids, ["B"])
    }

    func testRemove_UnpublishedForRegularUser_Removed() {
        let ids = BookCatalogVisibility.firestoreIdsToRemove(localIds: ["A", "B"], catalogIds: ["A", "B"], skippedIds: ["B"])
        XCTAssertEqual(ids, ["B"])
    }

    func testRemove_ShownBooks_IncludingTesterDrafts_Kept() {
        // Черновик у тестировщика решается как .show — в skippedIds не попадает.
        let ids = BookCatalogVisibility.firestoreIdsToRemove(localIds: ["A", "DRAFT"], catalogIds: ["A", "DRAFT"], skippedIds: [])
        XCTAssertTrue(ids.isEmpty)
    }
}
