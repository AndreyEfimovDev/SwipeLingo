import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - SRSServiceTests
//
// Tests cover every branch of the SM-2 algorithm:
//   • .again — full reset (EF −0.20, reps = 0, interval = 1)
//   • .hard  — hold position (EF −0.15, reps/interval unchanged)
//   • .easy  — SM-2 progression (EF +0.10, reps++, interval grows)
//   • EF floor enforcement (never < 1.3)
//   • dueDate calculation

@MainActor
final class SRSServiceTests: XCTestCase {

    // MARK: Setup

    var container: ModelContainer!
    var context:   ModelContext!
    let srs = SRSService()

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container  = try ModelContainer(for: Card.self, configurations: config)
        context    = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context   = nil
        container = nil
    }

    // MARK: Helpers

    private func makeCard(
        ef:    Double = 2.5,
        interval: Int = 1,
        reps:  Int = 0
    ) -> Card {
        let card = Card(en: "test", item: "тест", setId: UUID())
        card.easeFactor  = ef
        card.interval    = interval
        card.repetitions = reps
        context.insert(card)
        return card
    }

    // MARK: - .again Tests

    func testAgain_ResetsRepetitionsToZero() {
        let card = makeCard(reps: 3)
        srs.evaluate(card: card, rating: .again)
        XCTAssertEqual(card.repetitions, 0)
    }

    func testAgain_ResetsIntervalToOne() {
        let card = makeCard(interval: 15)
        srs.evaluate(card: card, rating: .again)
        XCTAssertEqual(card.interval, 1)
    }

    func testAgain_DecrementsEFByPoint20() {
        let card = makeCard(ef: 2.5)
        srs.evaluate(card: card, rating: .again)
        XCTAssertEqual(card.easeFactor, 2.3, accuracy: 0.001)
    }

    // MARK: - .hard Tests

    func testHard_DecrementsEFByPoint15() {
        let card = makeCard(ef: 2.5)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertEqual(card.easeFactor, 2.35, accuracy: 0.001)
    }

    func testHard_DoesNotChangeInterval() {
        let card = makeCard(interval: 6, reps: 2)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertEqual(card.interval, 6)
    }

    func testHard_DoesNotChangeRepetitions() {
        let card = makeCard(reps: 2)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertEqual(card.repetitions, 2)
    }

    // MARK: - .easy Tests

    func testEasy_FirstRepetition_IntervalOne() {
        let card = makeCard(reps: 0)
        srs.evaluate(card: card, rating: .easy)
        XCTAssertEqual(card.interval, 1)
        XCTAssertEqual(card.repetitions, 1)
    }

    func testEasy_SecondRepetition_IntervalSix() {
        let card = makeCard(reps: 1)
        srs.evaluate(card: card, rating: .easy)
        XCTAssertEqual(card.interval, 6)
        XCTAssertEqual(card.repetitions, 2)
    }

    func testEasy_ThirdRepetition_IntervalGrows() {
        let card = makeCard(ef: 2.5, interval: 6, reps: 2)
        srs.evaluate(card: card, rating: .easy)
        // interval = round(6 * 2.6) = 16 (EF bumped by +0.10 first)
        let expected = Int((6.0 * 2.6).rounded())
        XCTAssertEqual(card.interval, expected)
        XCTAssertEqual(card.repetitions, 3)
    }

    func testEasy_IncrementsEFByPoint10() {
        let card = makeCard(ef: 2.5, reps: 0)
        srs.evaluate(card: card, rating: .easy)
        XCTAssertEqual(card.easeFactor, 2.6, accuracy: 0.001)
    }

    // MARK: - EF Floor

    func testEFNeverDropsBelowMinimum_WithAgain() {
        let card = makeCard(ef: 1.3)
        srs.evaluate(card: card, rating: .again)
        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3)
    }

    func testEFNeverDropsBelowMinimum_WithHard() {
        let card = makeCard(ef: 1.3)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3)
    }

    func testEFNeverDropsBelowMinimum_MultipleAgains() {
        let card = makeCard(ef: 2.5)
        for _ in 0..<20 { srs.evaluate(card: card, rating: .again) }
        XCTAssertEqual(card.easeFactor, 1.3, accuracy: 0.001)
    }

    // MARK: - dueDate

    func testDueDateIsSetToTodayPlusInterval_Again() {
        let card = makeCard()
        let before = Date.now
        srs.evaluate(card: card, rating: .again)   // interval = 1
        let after = Date.now

        let due = card.dueDate
        let oneDayAfterBefore = Calendar.current.date(byAdding: .day, value: 1, to: before)!
        let oneDayAfterAfter  = Calendar.current.date(byAdding: .day, value: 1, to: after)!

        XCTAssertGreaterThanOrEqual(due, oneDayAfterBefore)
        XCTAssertLessThanOrEqual(due, oneDayAfterAfter)
    }

    func testDueDateMatchesIntervalAfterEasy() {
        let card = makeCard(reps: 1)           // next easy → interval = 6
        let before = Date.now
        srs.evaluate(card: card, rating: .easy)
        let after = Date.now

        XCTAssertEqual(card.interval, 6)
        let sixDaysAfterBefore = Calendar.current.date(byAdding: .day, value: 6, to: before)!
        let sixDaysAfterAfter  = Calendar.current.date(byAdding: .day, value: 6, to: after)!
        XCTAssertGreaterThanOrEqual(card.dueDate, sixDaysAfterBefore)
        XCTAssertLessThanOrEqual(card.dueDate, sixDaysAfterAfter)
    }

    // MARK: - lastReviewed

    func testLastReviewedIsUpdatedOnEvaluate() {
        let card = makeCard()
        let before = Date.now
        srs.evaluate(card: card, rating: .easy)
        XCTAssertGreaterThanOrEqual(card.lastReviewed, before)
    }
}
