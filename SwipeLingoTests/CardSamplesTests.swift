import XCTest
@testable import SwipeLingo

// MARK: - CardSamplesTests
//
// Card.allSampleItem — переводы идут индекс в индекс с allSampleEN:
//   • переводов основных примеров меньше, чем примеров — перевод примера со словаря не съезжает
//   • переводов основных примеров больше, чем примеров — лишние отбрасываются

@MainActor
final class CardSamplesTests: XCTestCase {

    func testAllSampleItem_FewerCardTranslations_DictionaryTranslationStaysWithItsExample() {
        let card = Card(en: "word", item: "слово", sampleEN: ["a", "b"], sampleItem: ["а"], setId: UUID())
        card.userSampleEN = ["mine"]
        card.userSampleItem = ["моё"]

        XCTAssertEqual(card.allSampleEN, ["a", "b", "mine"])
        XCTAssertEqual(card.allSampleItem, ["а", "", "моё"])
    }

    func testAllSampleItem_ExtraCardTranslations_AreDropped() {
        let card = Card(en: "word", item: "слово", sampleEN: ["a"], sampleItem: ["а", "лишний"], setId: UUID())
        card.userSampleEN = ["mine"]
        card.userSampleItem = ["моё"]

        XCTAssertEqual(card.allSampleItem, ["а", "моё"])
    }
}
