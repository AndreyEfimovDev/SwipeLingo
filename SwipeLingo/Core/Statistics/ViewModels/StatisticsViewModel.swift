import Foundation
import Observation

// MARK: - PeriodSummary

/// Итог за выбранный период (сумма дней `DayTotals`).
struct PeriodSummary: Equatable {
    var cardsReviewed = 0
    var cardsLearnt = 0
    var easy = 0
    var hard = 0
    var forgot = 0
    var levelUpSets = 0

    /// Карточки, пройденные без оценки: свайп с лицевой стороны или удаление. Оценки ставятся только на
    /// обороте, поэтому `cardsReviewed` больше суммы Easy/Hard/Forgot — разница идёт отдельным сегментом.
    var swiped: Int { max(0, cardsReviewed - easy - hard - forgot) }
}

// MARK: - StatisticsViewModel
//
// Состояние экрана Statistics. Сам ничего не считает — расчёт в `StudyStatisticsService`; данные SwiftData
// приходят из `@Query` во View через `update(...)`. Пересчёт — только по вызову `update`, не в каждом `body`:
// карточек могут быть тысячи.

@Observable
final class StatisticsViewModel {

    /// Выбранный период блока «Cards Studied».
    var period: StatisticsPeriod = .week

    private(set) var streak = StreakInfo(current: 0, best: 0, isTodayDone: false)
    private(set) var upcoming = UpcomingReviews(today: 0, tomorrow: 0, nextSevenDays: 0)
    private(set) var vocabulary = VocabularySummary()
    private(set) var collectionProgress: [CollectionProgress] = []
    /// Пройдено карточек по ключу дня (`StudyDay.dayKey`) — для календаря активности.
    private(set) var activityByDay: [String: Int] = [:]

    private var dailyTotals: [String: DayTotals] = [:]
    private var now = Date.now
    private let service: StudyStatisticsService

    init() {
        self.service = StudyStatisticsService()
    }

    /// Итог за выбранный период.
    var periodSummary: PeriodSummary {
        service.totals(in: period, totals: dailyTotals, today: now).reduce(into: PeriodSummary()) { sum, day in
            sum.cardsReviewed += day.cardsReviewed
            sum.cardsLearnt += day.cardsLearnt
            sum.easy += day.easy
            sum.hard += day.hard
            sum.forgot += day.forgot
            sum.levelUpSets += day.levelUpSets
        }
    }

    /// Нечего показывать: ни одного дня занятий и ни одной карточки в словаре.
    var isEmpty: Bool {
        !dailyTotals.values.contains(where: \.hasActivity)
            && vocabulary.myWords.total == 0
            && vocabulary.byLevel.values.allSatisfy { $0.total == 0 }
    }

    /// Пересчитывает все блоки экрана.
    /// - Parameters:
    ///   - days: все записи истории занятий.
    ///   - cards: все карточки.
    ///   - sets: все сеты карточек.
    ///   - collections: все коллекции.
    ///   - firebaseUID: текущий аккаунт (`""` — до входа, как пишет `StudyActivityRecorder`).
    ///   - userLevel: уровень пользователя — облачные сеты выше него не учитываются, как в Cards.
    ///   - now: текущий момент.
    func update(
        days: [StudyDay],
        cards: [Card],
        sets: [CardSet],
        collections: [Collection],
        firebaseUID: String,
        userLevel: CEFRLevel,
        now: Date = .now
    ) {
        self.now = now
        let totals = service.dailyTotals(days, firebaseUID: firebaseUID)
        dailyTotals = totals
        activityByDay = totals.mapValues(\.cardsReviewed)
        streak = service.streak(totals: totals, today: now)

        let visible = service.visibleCards(
            cards: cards,
            sets: sets,
            collections: collections,
            firebaseUID: firebaseUID,
            userLevel: userLevel
        )
        upcoming = service.upcoming(cards: visible, now: now)
        vocabulary = service.vocabulary(
            cards: cards,
            sets: sets,
            collections: collections,
            firebaseUID: firebaseUID,
            userLevel: userLevel
        )
        collectionProgress = service.collectionProgress(
            cards: cards,
            sets: sets,
            collections: collections,
            firebaseUID: firebaseUID,
            userLevel: userLevel
        )
    }
}
