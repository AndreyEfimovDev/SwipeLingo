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
//   • dueDate / lastReviewed fields

@MainActor
final class SRSServiceTests: XCTestCase {

    let srs = SRSService()

    // MARK: - Helpers

    /// Creates a fresh in-memory ModelContainer + ModelContext for each test.
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Card.self, configurations: config)
        return (container, ModelContext(container))
    }

    private func makeCard(
        context: ModelContext,
        ef: Double = 2.5,
        interval: Int = 1,
        reps: Int = 0
    ) -> Card {
        let card = Card(en: "test", item: "тест", setId: UUID())
        card.easeFactor  = ef
        card.interval    = interval
        card.repetitions = reps
        context.insert(card)
        return card
    }

    // MARK: - .again Tests

    func testAgain_ResetsRepetitionsToZero() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, reps: 3)
        srs.evaluate(card: card, rating: .again)
        XCTAssertEqual(card.repetitions, 0)
    }

    func testAgain_ResetsIntervalToOne() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, interval: 15)
        srs.evaluate(card: card, rating: .again)
        XCTAssertEqual(card.interval, 1)
    }

    func testAgain_DecrementsEFByPoint20() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 2.5)
        srs.evaluate(card: card, rating: .again)
        XCTAssertEqual(card.easeFactor, 2.3, accuracy: 0.001)
    }

    // MARK: - .hard Tests

    func testHard_DecrementsEFByPoint15() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 2.5)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertEqual(card.easeFactor, 2.35, accuracy: 0.001)
    }

    func testHard_DoesNotChangeInterval() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, interval: 6, reps: 2)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertEqual(card.interval, 6)
    }

    func testHard_DoesNotChangeRepetitions() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, reps: 2)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertEqual(card.repetitions, 2)
    }

    // MARK: - .easy Tests

    func testEasy_FirstRepetition_IntervalOne() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, reps: 0)
        srs.evaluate(card: card, rating: .easy)
        XCTAssertEqual(card.interval, 1)
        XCTAssertEqual(card.repetitions, 1)
    }

    func testEasy_SecondRepetition_IntervalSix() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, reps: 1)
        srs.evaluate(card: card, rating: .easy)
        XCTAssertEqual(card.interval, 6)
        XCTAssertEqual(card.repetitions, 2)
    }

    func testEasy_ThirdRepetition_IntervalGrows() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 2.5, interval: 6, reps: 2)
        srs.evaluate(card: card, rating: .easy)
        // EF is bumped to 2.6 first, then interval = round(6 × 2.6) = 16
        let expected = Int((6.0 * 2.6).rounded())
        XCTAssertEqual(card.interval, expected)
        XCTAssertEqual(card.repetitions, 3)
    }

    func testEasy_IncrementsEFByPoint10() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 2.5, reps: 0)
        srs.evaluate(card: card, rating: .easy)
        XCTAssertEqual(card.easeFactor, 2.6, accuracy: 0.001)
    }

    // MARK: - EF Floor

    func testEFNeverDropsBelowMinimum_WithAgain() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 1.3)
        srs.evaluate(card: card, rating: .again)
        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3)
    }

    func testEFNeverDropsBelowMinimum_WithHard() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 1.3)
        srs.evaluate(card: card, rating: .hard)
        XCTAssertGreaterThanOrEqual(card.easeFactor, 1.3)
    }

    func testEFNeverDropsBelowMinimum_MultipleAgains() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, ef: 2.5)
        for _ in 0..<20 { srs.evaluate(card: card, rating: .again) }
        XCTAssertEqual(card.easeFactor, 1.3, accuracy: 0.001)
    }

    // MARK: - dueDate

    func testDueDateIsSetToTodayPlusOneDay_Again() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx)
        let before = Date.now
        srs.evaluate(card: card, rating: .again)   // interval = 1
        let after = Date.now

        // Use addingTimeInterval — non-optional, no force unwrap needed
        XCTAssertGreaterThanOrEqual(card.dueDate, before.addingTimeInterval(86_400))
        XCTAssertLessThanOrEqual(card.dueDate,    after.addingTimeInterval(86_400))
    }

    func testDueDateIsSetToTodayPlusSixDays_Easy() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx, reps: 1)  // next easy → interval = 6
        let before = Date.now
        srs.evaluate(card: card, rating: .easy)
        let after = Date.now

        XCTAssertEqual(card.interval, 6)
        XCTAssertGreaterThanOrEqual(card.dueDate, before.addingTimeInterval(6 * 86_400))
        XCTAssertLessThanOrEqual(card.dueDate,    after.addingTimeInterval(6 * 86_400))
    }

    // MARK: - lastReviewed

    func testLastReviewedIsUpdatedOnEvaluate() throws {
        let (_, ctx) = try makeContext()
        let card = makeCard(context: ctx)
        let before = Date.now
        srs.evaluate(card: card, rating: .easy)
        XCTAssertGreaterThanOrEqual(card.lastReviewed, before)
    }
}
