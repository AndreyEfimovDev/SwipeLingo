import XCTest
@testable import SwipeLingo

// MARK: - BookCatalogVisibilityTests
//
// Видимость книги каталога по флагу isPublished из Firestore:
//   • isPublished == true — видна всем, без плашки TESTING
//   • false или поля нет — только тестировщику, с плашкой TESTING; остальным не загружается
//   • тестировщик — только UID из списка; nil и пустой UID — не тестировщик

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
}
