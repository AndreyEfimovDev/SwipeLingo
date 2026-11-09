import XCTest
import SwiftData
@testable import SwipeLingo

// MARK: - StudyStatisticsServiceTests
//
// Расчёт статистики (часовой пояс UTC, «сегодня» = 2026-11-05 12:00 UTC):
//   • итоги дня: устройства аккаунта складываются, чужой аккаунт не учитывается
//   • серия: подряд с сегодня; сегодня ещё не занимался — считается до вчера; пропуск рвёт серию; лучшая серия
//   • период «неделя» — последние 7 дней с сегодня
//   • словарь: облачные сеты не выше уровня по CEFR, свои слова отдельно; удалённые карточки, мягко удалённые
//     сеты и чужие коллекции не учитываются
//   • к повторению: сегодня (вместе с просроченными), завтра, 7 дней; новые и выученные не считаются
//   • прогресс коллекций: без системной коллекции Inbox, по убыванию доли выученного

@MainActor
final class StudyStatisticsServiceTests: XCTestCase {

    private let uid = "U1"
    private let service = StudyStatisticsService(timeZone: TimeZone(identifier: "UTC") ?? .current)
    private let today = ISO8601DateFormatter().date(from: "2026-11-05T12:00:00Z") ?? .distantPast

    /// Контейнер живёт до конца теста: ModelContext не удерживает свой ModelContainer.
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: - История занятий

    func testDailyTotals_SumsDevices_IgnoresOtherAccount() {
        let days = [
            studyDay("2026-11-05", device: "D1", reviewed: 5, easy: 2),
            studyDay("2026-11-05", device: "D2", reviewed: 3, easy: 1, levelUp: 1),
            studyDay("2026-11-05", device: "D1", owner: "OTHER", reviewed: 100)
        ]

        let totals = service.dailyTotals(days, firebaseUID: uid)

        XCTAssertEqual(totals["2026-11-05"], DayTotals(dayKey: "2026-11-05", cardsReviewed: 8, easy: 3, levelUpSets: 1))
        XCTAssertEqual(totals.count, 1)
    }

    func testStreak_ConsecutiveIncludingToday() {
        let totals = totals(activeDays: ["2026-11-03", "2026-11-04", "2026-11-05"])

        XCTAssertEqual(service.streak(totals: totals, today: today), StreakInfo(current: 3, best: 3, isTodayDone: true))
    }

    func testStreak_TodayNotDoneYet_CountsUntilYesterday() {
        let totals = totals(activeDays: ["2026-11-03", "2026-11-04"])

        XCTAssertEqual(service.streak(totals: totals, today: today), StreakInfo(current: 2, best: 2, isTodayDone: false))
    }

    func testStreak_GapBreaksCurrent_BestKept() {
        let totals = totals(activeDays: ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-04"])

        XCTAssertEqual(service.streak(totals: totals, today: today), StreakInfo(current: 1, best: 3, isTodayDone: false))
    }

    func testStreak_DaysWithoutActivity_NotCounted() {
        let days = [studyDay("2026-11-05", device: "D1", reviewed: 0)]

        let streak = service.streak(totals: service.dailyTotals(days, firebaseUID: uid), today: today)

        XCTAssertEqual(streak, StreakInfo(current: 0, best: 0, isTodayDone: false))
    }

    func testWeek_IsLastSevenDaysIncludingToday() {
        let totals = totals(activeDays: ["2026-10-29", "2026-10-30", "2026-11-05"])

        let week = service.totals(in: .week, totals: totals, today: today).map(\.dayKey)

        XCTAssertEqual(week, ["2026-10-30", "2026-11-05"], "2026-10-29 — восьмой день назад, вне недели")
    }

    // MARK: - Карточки

    func testVocabulary_ByLevelAndMyWords_ExcludesHiddenContent() throws {
        let context = try makeContext()
        let cloud = insert(Collection(name: "IELTS", isUserCreated: false), context)
        let mine = insert(Collection(name: "Travel", ownerFirebaseUID: uid), context)
        let foreign = insert(Collection(name: "Foreign", ownerFirebaseUID: "OTHER"), context)

        let b1 = insert(CardSet(name: "B1", collectionId: cloud.id, level: .b1, isUserCreated: false), context)
        let c1 = insert(CardSet(name: "C1", collectionId: cloud.id, level: .c1, isUserCreated: false), context)
        let removed = insert(CardSet(name: "Removed", collectionId: cloud.id, level: .a2, isUserCreated: false), context)
        removed.isSoftDeleted = true
        let own = insert(CardSet(name: "Own", collectionId: mine.id), context)
        let foreignSet = insert(CardSet(name: "Foreign", collectionId: foreign.id), context)

        card(in: b1, .learnt, context); card(in: b1, .active, context); card(in: b1, .deleted, context)
        card(in: c1, .active, context)          // выше уровня B1
        card(in: removed, .active, context)     // мягко удалённый сет
        card(in: own, .learnt, context); card(in: own, .active, context)
        card(in: foreignSet, .active, context)  // чужой аккаунт

        let summary = service.vocabulary(cards: try context.fetch(FetchDescriptor<Card>()),
                                         sets: try context.fetch(FetchDescriptor<CardSet>()),
                                         collections: try context.fetch(FetchDescriptor<Collection>()),
                                         firebaseUID: uid, userLevel: .b1)

        XCTAssertEqual(summary.byLevel, [.b1: VocabularyCounts(learnt: 1, learning: 1)])
        XCTAssertEqual(summary.myWords, VocabularyCounts(learnt: 1, learning: 1))
    }

    func testUpcoming_TodayTomorrowWeek_SkipsNewAndLearnt() throws {
        let context = try makeContext()
        let collection = insert(Collection(name: "Mine", ownerFirebaseUID: uid), context)
        let set = insert(CardSet(name: "Set", collectionId: collection.id), context)
        let hour: TimeInterval = 3600
        card(in: set, .active, context, due: today.addingTimeInterval(-48 * hour))   // просрочена → сегодня
        card(in: set, .active, context, due: today.addingTimeInterval(6 * hour))     // сегодня вечером
        card(in: set, .active, context, due: today.addingTimeInterval(24 * hour))    // завтра
        card(in: set, .active, context, due: today.addingTimeInterval(5 * 24 * hour))  // через 5 дней
        card(in: set, .active, context, due: today.addingTimeInterval(10 * 24 * hour)) // вне недели
        card(in: set, .active, context)                                              // новая: farFuture
        card(in: set, .learnt, context, due: today)                                  // выучена

        let upcoming = service.upcoming(cards: try context.fetch(FetchDescriptor<Card>()), now: today)

        XCTAssertEqual(upcoming, UpcomingReviews(today: 2, tomorrow: 1, nextSevenDays: 4))
    }

    func testCollectionProgress_ExcludesInbox_SortedByShareLearnt() throws {
        let context = try makeContext()
        let inbox = insert(Collection(name: Collection.inboxCollectionName, ownerFirebaseUID: uid), context)
        let travel = insert(Collection(name: "Travel", ownerFirebaseUID: uid), context)
        let work = insert(Collection(name: "Work", ownerFirebaseUID: uid), context)
        let inboxSet = insert(CardSet(name: "Inbox", collectionId: inbox.id), context)
        let travelSet = insert(CardSet(name: "T", collectionId: travel.id), context)
        let workSet = insert(CardSet(name: "W", collectionId: work.id), context)
        card(in: inboxSet, .learnt, context)
        card(in: travelSet, .active, context); card(in: travelSet, .learnt, context)   // 1/2
        card(in: workSet, .learnt, context)                                             // 1/1

        let progress = service.collectionProgress(cards: try context.fetch(FetchDescriptor<Card>()),
                                                  sets: try context.fetch(FetchDescriptor<CardSet>()),
                                                  collections: try context.fetch(FetchDescriptor<Collection>()),
                                                  firebaseUID: uid, userLevel: .c2)
        
        XCTAssertEqual(progress.map(\.name), ["Work", "Travel"])
        XCTAssertEqual(progress.map(\.learnt), [1, 1])
        XCTAssertEqual(progress.map(\.total), [1, 2])
    }

    // MARK: - Helpers

    private func studyDay(_ key: String, device: String, owner: String? = nil,
                          reviewed: Int, easy: Int = 0, levelUp: Int = 0) -> StudyDay {
        let day = StudyDay(dayKey: key, deviceID: device, ownerFirebaseUID: owner ?? uid)
        day.cardsReviewed = reviewed
        day.easyCount = easy
        day.levelUpSetsCompleted = levelUp
        return day
    }

    private func totals(activeDays keys: [String]) -> [String: DayTotals] {
        service.dailyTotals(keys.map { studyDay($0, device: "D1", reviewed: 1) }, firebaseUID: uid)
    }

    @discardableResult
    private func insert<T: PersistentModel>(_ model: T, _ context: ModelContext) -> T {
        context.insert(model)
        return model
    }

    /// `due == nil` — новая карточка (`Date.farFuture`, как у карточки до первой оценки). Не default-значением
    /// параметра: `Date.farFuture` объявлен в модуле с изоляцией MainActor, а default-выражения неизолированы.
    private func card(in set: CardSet, _ status: CardStatus, _ context: ModelContext, due: Date? = nil) {
        context.insert(Card(en: "word", item: "слово", status: status, dueDate: due ?? Date.farFuture, setId: set.id))
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Card.self, CardSet.self, Collection.self, configurations: config)
        self.container = container
        return ModelContext(container)
    }
}
