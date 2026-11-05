import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - StudyActivityRecorderTests
//
// Запись действий в историю занятий (StudyDay):
//   • первое действие за день создаёт запись (день, устройство, аккаунт), следующие — увеличивают её
//   • свайп вправо/влево, удаление, оценки и пройденный сет Level Up попадают в свои счётчики
//   • новый день, другое устройство, другой аккаунт — отдельные записи
//   • ключ дня — по местной полуночи, не зависит от календаря пользователя

@MainActor
final class StudyActivityRecorderTests: XCTestCase {

    /// Контейнер живёт до конца теста: ModelContext не удерживает свой ModelContainer.
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testEvents_IncrementTheirCounters_InOneRecordPerDay() throws {
        let context = try makeContext()
        let recorder = StudyActivityRecorder(firebaseUID: "U1", deviceID: "D1")
        let now = date("2026-11-05T10:00:00Z")

        recorder.record(.cardSwiped(learnt: true), context: context, now: now)
        recorder.record(.cardSwiped(learnt: false), context: context, now: now)
        recorder.record(.cardDeleted, context: context, now: now)
        recorder.record(.cardRated(.easy), context: context, now: now)
        recorder.record(.cardRated(.hard), context: context, now: now)
        recorder.record(.cardRated(.again), context: context, now: now)
        recorder.record(.levelUpSetCompleted, context: context, now: now)

        let days = try context.fetch(FetchDescriptor<StudyDay>())
        XCTAssertEqual(days.count, 1, "действия до сохранения не должны плодить записи")
        let day = try XCTUnwrap(days.first)
        XCTAssertEqual(day.cardsReviewed, 6)
        XCTAssertEqual(day.cardsLearnt, 1)
        XCTAssertEqual(day.easyCount, 1)
        XCTAssertEqual(day.hardCount, 1)
        XCTAssertEqual(day.forgotCount, 1)
        XCTAssertEqual(day.levelUpSetsCompleted, 1)
        XCTAssertEqual(day.deviceID, "D1")
        XCTAssertEqual(day.ownerFirebaseUID, "U1")
        XCTAssertTrue(day.hasActivity)
    }

    func testNewDay_DeviceOrAccount_GetSeparateRecords() throws {
        let context = try makeContext()
        let day1 = date("2026-11-05T10:00:00Z")
        let day2 = date("2026-11-06T10:00:00Z")

        StudyActivityRecorder(firebaseUID: "U1", deviceID: "D1").record(.cardDeleted, context: context, now: day1)
        StudyActivityRecorder(firebaseUID: "U1", deviceID: "D1").record(.cardDeleted, context: context, now: day2)
        StudyActivityRecorder(firebaseUID: "U1", deviceID: "D2").record(.cardDeleted, context: context, now: day1)
        StudyActivityRecorder(firebaseUID: "U2", deviceID: "D1").record(.cardDeleted, context: context, now: day1)
        try context.save()

        let days = try context.fetch(FetchDescriptor<StudyDay>())
        XCTAssertEqual(days.count, 4)
        XCTAssertTrue(days.allSatisfy { $0.cardsReviewed == 1 })
    }

    func testSavedRecord_IsReusedOnNextAction() throws {
        let context = try makeContext()
        let recorder = StudyActivityRecorder(firebaseUID: "U1", deviceID: "D1")
        let now = date("2026-11-05T10:00:00Z")

        recorder.record(.cardDeleted, context: context, now: now)
        try context.save()
        recorder.record(.cardDeleted, context: context, now: now.addingTimeInterval(3600))

        let days = try context.fetch(FetchDescriptor<StudyDay>())
        XCTAssertEqual(days.map(\.cardsReviewed), [2])
    }

    func testDayKey_LocalMidnightBoundary() throws {
        let moscow = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))   // UTC+3
        // 20:59 UTC = 23:59 в Москве — ещё 5-е; 21:00 UTC = 00:00 — уже 6-е.
        XCTAssertEqual(StudyDay.dayKey(for: date("2026-11-05T20:59:00Z"), timeZone: moscow), "2026-11-05")
        XCTAssertEqual(StudyDay.dayKey(for: date("2026-11-05T21:00:00Z"), timeZone: moscow), "2026-11-06")
    }

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StudyDay.self, configurations: config)
        self.container = container
        return ModelContext(container)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? .distantPast
    }
}
