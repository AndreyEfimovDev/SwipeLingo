import Foundation

// MARK: - Результаты расчёта

/// Итог одного дня по всем устройствам аккаунта.
struct DayTotals: Equatable {
    let dayKey: String
    var cardsReviewed = 0
    var cardsLearnt = 0
    var easy = 0
    var hard = 0
    var forgot = 0
    var levelUpSets = 0

    /// Был ли день активным: хотя бы одна карточка или пройденный сет Level Up.
    var hasActivity: Bool { cardsReviewed > 0 || levelUpSets > 0 }
}

/// Серия дней подряд с занятиями.
struct StreakInfo: Equatable {
    /// Текущая серия: заканчивается сегодня или, если сегодня ещё не занимался, вчера.
    let current: Int
    /// Самая длинная серия за всю историю.
    let best: Int
    /// Занимался ли сегодня (серия уже продлена).
    let isTodayDone: Bool
}

/// Карточки по состоянию изучения. Без отдельного «новые»: признаков «ни разу не показана» у карточки нет
/// надёжного — свайп не трогает `lastReviewed`, а `isNew` ставится только облачным карточкам при импорте.
struct VocabularyCounts: Equatable {
    /// Выучены (`.learnt`).
    var learnt = 0
    /// Учатся: активные (`.active`).
    var learning = 0

    var total: Int { learnt + learning }
}

/// Словарь пользователя: облачные сеты — по уровням CEFR, свои слова — отдельно (у них нет уровня).
struct VocabularySummary: Equatable {
    var byLevel: [CEFRLevel: VocabularyCounts] = [:]
    var myWords = VocabularyCounts()
}

/// Сколько карточек придёт на повторение.
struct UpcomingReviews: Equatable {
    /// До конца сегодняшнего дня (включая уже просроченные).
    let today: Int
    /// Завтра.
    let tomorrow: Int
    /// Ближайшие 7 дней, считая сегодня.
    let nextSevenDays: Int
}

/// Прогресс одной коллекции: выучено из всех не удалённых карточек.
struct CollectionProgress: Equatable, Identifiable {
    let id: UUID
    let name: String
    let learnt: Int
    let total: Int
}

/// Период для графиков активности.
enum StatisticsPeriod: CaseIterable {
    case today, week, month, year, all
}

// MARK: - StudyStatisticsService
//
// Расчёт статистики без UI и без SwiftData-запросов: на вход — уже загруженные модели, на выход — значения
// для экрана Statistics, виджета и напоминаний. Чистые функции, поэтому тестируются без контейнера.
//
// Календарь — григорианский с явным часовым поясом (по умолчанию — устройства), как у `StudyDay.dayKey`,
// чтобы ключи дней и границы «сегодня/завтра» считались одинаково.

struct StudyStatisticsService {

    private let calendar: Calendar

    /// - Parameter timeZone: часовой пояс для границ дней; в тестах — фиксированный.
    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    // MARK: - История занятий

    /// Суммирует записи `StudyDay` по дням: устройства одного аккаунта складываются, чужие аккаунты (общий
    /// iCloud) не учитываются.
    /// - Parameters:
    ///   - days: все записи истории.
    ///   - firebaseUID: текущий аккаунт.
    /// - Returns: итоги по ключу дня.
    func dailyTotals(_ days: [StudyDay], firebaseUID: String) -> [String: DayTotals] {
        var result: [String: DayTotals] = [:]
        for day in days where day.ownerFirebaseUID == firebaseUID {
            var totals = result[day.dayKey] ?? DayTotals(dayKey: day.dayKey)
            totals.cardsReviewed += day.cardsReviewed
            totals.cardsLearnt += day.cardsLearnt
            totals.easy += day.easyCount
            totals.hard += day.hardCount
            totals.forgot += day.forgotCount
            totals.levelUpSets += day.levelUpSetsCompleted
            result[day.dayKey] = totals
        }
        return result
    }

    /// Текущая и лучшая серия. Пока сегодня не занимался, серия не рвётся: считается до вчера включительно.
    /// - Parameters:
    ///   - totals: итоги по дням (`dailyTotals`).
    ///   - today: текущий момент.
    func streak(totals: [String: DayTotals], today: Date) -> StreakInfo {
        let activeKeys = Set(totals.values.filter(\.hasActivity).map(\.dayKey))
        let todayKey = key(for: today)
        let isTodayDone = activeKeys.contains(todayKey)

        // Текущая: от сегодня (или вчера) назад, пока дни активны.
        var current = 0
        var cursor = isTodayDone ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while activeKeys.contains(key(for: cursor)) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        // Лучшая: самый длинный отрезок подряд идущих активных дней.
        let dates = activeKeys.compactMap(date(fromKey:)).sorted()
        var best = 0
        var run = 0
        var previousDate: Date?
        for date in dates {
            if let previousDate, calendar.date(byAdding: .day, value: 1, to: previousDate) == date {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previousDate = date
        }
        return StreakInfo(current: current, best: max(best, current), isTodayDone: isTodayDone)
    }

    /// Итоги дней, попадающих в период: неделя — последние 7 дней с сегодня, месяц и год — календарные.
    /// - Parameters:
    ///   - period: период.
    ///   - totals: итоги по дням.
    ///   - today: текущий момент.
    /// - Returns: итоги по возрастанию даты; только дни, по которым есть записи.
    func totals(
        in period: StatisticsPeriod,
        totals: [String: DayTotals],
        today: Date
    ) -> [DayTotals] {
        let todayStart = calendar.startOfDay(for: today)
        let selected = totals.values.filter { totals in
            guard let date = date(fromKey: totals.dayKey) else { return false }
            switch period {
            case .today:
                return date == todayStart
            case .week:
                guard let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) else { return false }
                return date >= weekStart && date <= todayStart
            case .month:
                return calendar.isDate(date, equalTo: today, toGranularity: .month)
            case .year:
                return calendar.isDate(date, equalTo: today, toGranularity: .year)
            case .all:
                return true
            }
        }
        return selected.sorted { $0.dayKey < $1.dayKey }
    }

    // MARK: - Карточки

    /// Карточки, которые пользователь видит в приложении: не удалённые; облачные — из не удалённых сетов не
    /// выше его уровня (как в Cards); свои — из своих коллекций (`Collection.isMine`).
    /// - Returns: видимые карточки, без `.deleted`.
    func visibleCards(
        cards: [Card],
        sets: [CardSet],
        collections: [Collection],
        firebaseUID: String,
        userLevel: CEFRLevel
    ) -> [Card] {
        let visibleSetIds = visibleSets(sets: sets, collections: collections,
                                        firebaseUID: firebaseUID, userLevel: userLevel).map(\.id)
        let allowed = Set(visibleSetIds)
        return cards.filter { $0.status != .deleted && allowed.contains($0.setId) }
    }

    /// Словарь: облачные карточки по уровню их сета, свои — в `myWords`.
    func vocabulary(
        cards: [Card],
        sets: [CardSet],
        collections: [Collection],
        firebaseUID: String,
        userLevel: CEFRLevel
    ) -> VocabularySummary {
        let setsById = Dictionary(sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var summary = VocabularySummary()
        for card in visibleCards(cards: cards, sets: sets, collections: collections,
                                 firebaseUID: firebaseUID, userLevel: userLevel) {
            guard let set = setsById[card.setId] else { continue }
            if set.isUserCreated {
                Self.count(card, into: &summary.myWords)
            } else {
                Self.count(card, into: &summary.byLevel[set.cefrLevel, default: VocabularyCounts()])
            }
        }
        return summary
    }

    /// Сколько активных карточек придёт на повторение. Новые (ни разу не проверенные) не считаются: у них
    /// `dueDate` в далёком будущем, в режим Due они не попадают.
    /// - Parameters:
    ///   - cards: видимые карточки (`visibleCards`).
    ///   - now: текущий момент.
    func upcoming(cards: [Card], now: Date) -> UpcomingReviews {
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let dayAfterStart = calendar.date(byAdding: .day, value: 2, to: todayStart),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart)
        else { return UpcomingReviews(today: 0, tomorrow: 0, nextSevenDays: 0) }

        let active = cards.filter { $0.status == .active }
        return UpcomingReviews(
            today: active.filter { $0.dueDate < tomorrowStart }.count,
            tomorrow: active.filter { $0.dueDate >= tomorrowStart && $0.dueDate < dayAfterStart }.count,
            nextSevenDays: active.filter { $0.dueDate < weekEnd }.count
        )
    }

    /// Прогресс по видимым коллекциям с карточками. Системная коллекция Inbox не показывается (её имя — ключ
    /// в данных, не текст UI); её слова входят в `VocabularySummary.myWords`.
    /// - Returns: коллекции по убыванию доли выученного, затем по имени.
    func collectionProgress(
        cards: [Card],
        sets: [CardSet],
        collections: [Collection],
        firebaseUID: String,
        userLevel: CEFRLevel
    ) -> [CollectionProgress] {
        let visible = visibleCards(cards: cards, sets: sets, collections: collections,
                                   firebaseUID: firebaseUID, userLevel: userLevel)
        let collectionIdBySet = Dictionary(sets.map { ($0.id, $0.collectionId) }, uniquingKeysWith: { first, _ in first })
        let cardsByCollection = Dictionary(grouping: visible) { collectionIdBySet[$0.setId] }

        let progress: [CollectionProgress] = collections.compactMap { collection in
            guard !collection.isInbox,
                  let cards = cardsByCollection[collection.id], !cards.isEmpty else { return nil }
            return CollectionProgress(id: collection.id, name: collection.name,
                                      learnt: cards.filter { $0.status == .learnt }.count, total: cards.count)
        }
        return progress.sorted {
            let lhs = Double($0.learnt) / Double($0.total)
            let rhs = Double($1.learnt) / Double($1.total)
            return lhs != rhs ? lhs > rhs : $0.name < $1.name
        }
    }

    // MARK: - Private

    /// Сеты, видимые пользователю (см. `visibleCards`).
    private func visibleSets(
        sets: [CardSet],
        collections: [Collection],
        firebaseUID: String,
        userLevel: CEFRLevel
    ) -> [CardSet] {
        let mineIds = Set(collections.filter { $0.isMine(firebaseUID: firebaseUID) }.map(\.id))
        return sets.filter { set in
            guard !set.isSoftDeleted, mineIds.contains(set.collectionId) else { return false }
            return set.isUserCreated || set.cefrLevel <= userLevel
        }
    }

    /// Относит карточку к выученным или учащимся (удалённые сюда не попадают — их отсекает `visibleCards`).
    private static func count(_ card: Card, into counts: inout VocabularyCounts) {
        if card.status == .learnt {
            counts.learnt += 1
        } else {
            counts.learning += 1
        }
    }

    /// Ключ дня в календаре сервиса.
    private func key(for date: Date) -> String {
        StudyDay.dayKey(for: date, timeZone: calendar.timeZone)
    }

    /// Начало дня по ключу `yyyy-MM-dd`; `nil` — ключ не разобран.
    private func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
