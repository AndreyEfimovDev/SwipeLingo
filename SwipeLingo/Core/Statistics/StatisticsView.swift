import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - StatisticsView
//
// Экран статистики (открывается из AppView как `.fullScreenCover`). Данные — `@Query` здесь, расчёт —
// `StatisticsViewModel` → `StudyStatisticsService`. История занятий пишется `StudyActivityRecorder`.

struct StatisticsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let authService: AuthFBService

    @Query private var studyDays: [StudyDay]
    @Query private var allCards: [Card]
    @Query private var cardSets: [CardSet]
    @Query private var collections: [Collection]
    @Query private var profiles: [UserProfile]

    @State private var vm = StatisticsViewModel()
    @State private var isCalendarCompact = false

    /// - Parameter authService: текущий аккаунт — чтобы не считать данные чужого аккаунта на общем iCloud.
    init(authService: AuthFBService) {
        self.authService = authService
    }

    private var firebaseUID: String { authService.currentUser?.uid ?? "" }

    /// Уровень пользователя — как в CardsView: свой профиль по firebaseUID, не `profiles.first`.
    private var userLevel: CEFRLevel {
        UserProfileDedupeService().resolveProfile(
            firebaseUID: firebaseUID, allProfiles: profiles, context: context
        )?.cefrLevel ?? .c2
    }

    /// Меняется при появлении/удалении записей — повод пересчитать. Статусы карточек, пока экран открыт,
    /// не меняются: учиться можно только после его закрытия.
    private var dataVersion: [Int] {
        [studyDays.count, allCards.count, cardSets.count, collections.count, profiles.count]
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if vm.isEmpty {
                        emptyState
                    } else {
                        StreakCard(streak: vm.streak)
                        UpcomingCard(upcoming: vm.upcoming)
                        UnderlineSegmentedPickerNotOptional(
                            selection: $vm.period,
                            allItems: StatisticsPeriod.allCases,
                            titleForCase: { $0.displayName }
                        )
                        .padding(.vertical, 8)
                        CardsStudiedCard(summary: vm.periodSummary)
                        ActivityCalendarCard(activityByDay: vm.activityByDay, isCompact: $isCalendarCompact)
                        VocabularyCard(vocabulary: vm.vocabulary)
                        if !vm.collectionProgress.isEmpty {
                            CollectionProgressCard(collections: vm.collectionProgress)
                        }
                    }
                }
                .foregroundStyle(Color.myColors.myAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .navBarIconStyle()
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: dataVersion) { refresh() }
        .onChange(of: firebaseUID) { refresh() }
    }

    /// Пересчитывает статистику по текущим данным.
    private func refresh() {
        vm.update(days: studyDays, cards: allCards, sets: cardSets, collections: collections,
                  firebaseUID: firebaseUID, userLevel: userLevel)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56))
            Text("No data yet")
                .font(.title3.bold())
            Text("Start studying to see your progress")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Card Container

private extension View {
    /// Плашка блока статистики: фон страницы + скругление + тень (стандарт проекта).
    func statisticsCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.myColors.myBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .myShadow()
    }
}

/// Горизонтальная полоска прогресса `value` из `total`.
private struct ProgressBar: View {
    let value: Int
    let total: Int
    var height: CGFloat = 6

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(value) / Double(total), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.myColors.myAccent.opacity(0.15))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.myColors.myGreen)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Streak Card

private struct StreakCard: View {
    let streak: StreakInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak")
                        .font(.caption.uppercaseSmallCaps())
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(streak.current)")
                            .font(.title)
                            .fontWeight(.medium)
                        Text(streak.current == 1 ? "day" : "days")
                            .font(.subheadline)
                    }
                }
                Spacer()
                Text("Best \(streak.best) days")
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }

            ProgressBar(value: streak.current, total: streak.best, height: 4)

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
        }
        .statisticsCard(cornerRadius: 14)
    }

    /// Подсказка, пока сегодня ещё не занимался: серия держится до конца дня.
    private var hint: String? {
        guard !streak.isTodayDone else { return nil }
        return streak.current > 0 ? "Study today to keep your streak" : "Study today to start a streak"
    }
}

// MARK: - Upcoming Card

private struct UpcomingCard: View {
    let upcoming: UpcomingReviews

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Due for Review")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            HStack {
                column(title: "Today", value: upcoming.today)
                column(title: "Tomorrow", value: upcoming.tomorrow)
                column(title: "7 days", value: upcoming.nextSevenDays)
            }
        }
        .statisticsCard()
    }

    private func column(title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Cards Studied Card

private struct CardsStudiedCard: View {
    let summary: PeriodSummary

    /// Сегменты полоски: оценки + пройденные без оценки (свайп/удаление).
    private var segments: [(label: String, count: Int, color: Color)] {
        [("Easy", summary.easy, Color.myColors.myGreen),
         ("Hard", summary.hard, Color.myColors.myOrange),
         ("Forgot", summary.forgot, Color.myColors.myRed),
         ("Swiped", summary.swiped, Color.myColors.myAccent.opacity(0.3))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cards Studied")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))

            HStack(alignment: .firstTextBaseline) {
                Text("\(summary.cardsReviewed)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Learnt \(summary.cardsLearnt)")
                    Text("Level Up sets \(summary.levelUpSets)")
                }
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }

            if summary.cardsReviewed > 0 {
                // Пропорциональная полоска
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(segments.indices, id: \.self) { i in
                            let segment = segments[i]
                            if segment.count > 0 {
                                Rectangle()
                                    .fill(segment.color)
                                    .frame(width: max(0, geo.size.width * CGFloat(segment.count)
                                                         / CGFloat(summary.cardsReviewed) - 2))
                            }
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.myColors.myAccent.opacity(0.15))
                    .frame(height: 12)
            }

            // Легенда
            HStack(spacing: 14) {
                ForEach(segments.indices, id: \.self) { i in
                    legendDot(color: segments[i].color, label: segments[i].label, count: segments[i].count)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .statisticsCard()
    }

    private func legendDot(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(.caption)
        }
    }
}

// MARK: - Activity Calendar Card

private struct ActivityCalendarCard: View {

    /// Пройдено карточек по ключу дня (`StudyDay.dayKey`).
    let activityByDay: [String: Int]
    @Binding var isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок
            HStack {
                Text("Activity — \(yearString)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        isCompact.toggle()
                    }
                } label: {
                    Text(isCompact ? "Show full" : "Show compact")
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myBlue)
                        .animation(nil, value: isCompact) // label меняется без анимации
                }
            }

            if isCompact {
                compactView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
            } else {
                monthlyGridView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                    ))
            }

            // Легенда интенсивности
            HStack(spacing: 6) {
                Text("Less")
                    .font(.system(size: 9))
                ForEach([0, 5, 15, 35], id: \.self) { n in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intensityColor(cards: n))
                        .frame(width: 10, height: 10)
                }
                Text("More")
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isCompact)
        .statisticsCard()
    }

    // MARK: Интенсивность

    private func intensityColor(cards: Int) -> Color {
        switch cards {
        case 0:       return Color.myColors.myAccent.opacity(0.08)
        case 1...10:  return Color.myColors.myGreen.opacity(0.30)
        case 11...30: return Color.myColors.myGreen.opacity(0.65)
        default:      return Color.myColors.myGreen
        }
    }

    private var yearString: String {
        Date().formatted(.dateTime.year())
    }

    // MARK: Сетка по месяцам (4 колонки)

    private var monthlyGridView: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 10
        ) {
            ForEach(last12Months(), id: \.self) { monthStart in
                miniMonthBlock(for: monthStart)
            }
        }
    }

    @ViewBuilder
    private func miniMonthBlock(for monthStart: Date) -> some View {
        let cal   = Calendar.current
        let days  = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekday = cal.component(.weekday, from: monthStart)
        let offset  = (weekday - 2 + 7) % 7   // Понедельник = 0
        let total   = offset + days
        let rows    = Int(ceil(Double(total) / 7.0))
        let name    = monthStart.formatted(.dateTime.month(.abbreviated))
        let yearNum = cal.component(.year, from: monthStart)

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(name)
                Text(String(yearNum))
            }
            .font(.system(size: 9, weight: .semibold))

            VStack(spacing: 1) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<7, id: \.self) { col in
                            let cell   = row * 7 + col
                            let dayNum = cell - offset + 1
                            if dayNum >= 1, dayNum <= days,
                               let date = cal.date(byAdding: .day, value: dayNum - 1, to: monthStart) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(intensityColor(cards: cardsCount(for: date)))
                                    .frame(width: 5, height: 5)
                            } else {
                                Color.clear.frame(width: 5, height: 5)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Компактный вид на 52 недели

    private var compactView: some View {
        let weeks      = last52Weeks()
        let dayLabels  = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        let cell: CGFloat    = 12
        let gap:  CGFloat    = 2
        let monthRowH: CGFloat = 16
        let labelColW: CGFloat = 22   // ширина, зарезервированная под прилипающие лейблы дней

        // Оверлей с лейблами дней — прилипает слева, фон скрывает ячейки, прокручивающиеся под ним
        let dayLabelColumn = VStack(alignment: .leading, spacing: gap) {
            Color.clear.frame(height: monthRowH)
            ForEach(dayLabels.indices, id: \.self) { i in
                Text(dayLabels[i])
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: labelColW - 2, height: cell, alignment: .trailing)
            }
        }
        .frame(width: labelColW)
        .background(Color.myColors.myBackground)  // маскирует контент, прокручивающийся под лейблами

        return ScrollViewReader { proxy in
            // ScrollView занимает ВСЮ ширину карточки
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {

                    // Строка лейблов месяцев — смещена вправо на labelColW, чтобы совпадать с сеткой
                    HStack(alignment: .bottom, spacing: gap) {
                        Color.clear.frame(width: labelColW, height: monthRowH) // отступ под колонку лейблов
                        ForEach(weeks.indices, id: \.self) { wi in
                            Group {
                                if shouldShowMonthLabel(for: weeks[wi]) {
                                    Text(monthLabel(for: weeks[wi]))
                                        .font(.system(size: 9, weight: .semibold))
                                        .fixedSize()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: cell, height: monthRowH, alignment: .bottomLeading)
                        }
                    }

                    // Строка сетки дней — начинается после отступа под колонку лейблов
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: labelColW) // отступ под колонку лейблов
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(weeks.indices, id: \.self) { wi in
                                VStack(spacing: gap) {
                                    ForEach(0..<7, id: \.self) { di in
                                        if let date = weeks[wi][di] {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(intensityColor(cards: cardsCount(for: date)))
                                                .frame(width: cell, height: cell)
                                        } else {
                                            Color.clear.frame(width: cell, height: cell)
                                        }
                                    }
                                }
                                .id(wi)
                            }
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 4)
            }
            .background(Color.myColors.myBackground)
            .overlay(alignment: .leading) { dayLabelColumn }  // прилипающие лейблы дней
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Вспомогательные функции

    private func cardsCount(for date: Date) -> Int {
        activityByDay[StudyDay.dayKey(for: date)] ?? 0
    }

    private func last12Months() -> [Date] {
        let cal = Calendar.current
        let now = Date()
        return (0..<12).compactMap { i in
            cal.date(byAdding: .month, value: -11 + i, to: cal.startOfMonth(for: now))
        }
    }

    private func last52Weeks() -> [[Date?]] {
        let cal  = Calendar.current
        let today = Date()
        let weekday      = cal.component(.weekday, from: today)
        let daysFromMon  = (weekday - 2 + 7) % 7
        guard let weekStart = cal.date(byAdding: .day, value: -daysFromMon, to: today) else { return [] }

        return (0..<52).compactMap { w -> [Date?]? in
            guard let start = cal.date(byAdding: .day, value: -(51 - w) * 7, to: weekStart) else { return nil }
            return (0..<7).map { d -> Date? in
                guard let date = cal.date(byAdding: .day, value: d, to: start) else { return nil }
                return date <= today ? date : nil
            }
        }
    }

    private func shouldShowMonthLabel(for week: [Date?]) -> Bool {
        guard let date = week.compactMap({ $0 }).first else { return false }
        return Calendar.current.component(.day, from: date) <= 7
    }

    private func monthLabel(for week: [Date?]) -> String {
        guard let date = week.compactMap({ $0 }).first else { return "" }
        let cal  = Calendar.current
        let yr   = cal.component(.year, from: date) % 100   // последние 2 цифры
        let mon  = date.formatted(.dateTime.month(.abbreviated))
        return "\(mon)-\(String(format: "%02d", yr))"
    }
}

// MARK: - Vocabulary Card

private struct VocabularyCard: View {
    let vocabulary: VocabularySummary

    /// Уровни, по которым есть карточки, по возрастанию.
    private var levels: [(level: CEFRLevel, counts: VocabularyCounts)] {
        CEFRLevel.allCases.compactMap { level in
            guard let counts = vocabulary.byLevel[level], counts.total > 0 else { return nil }
            return (level, counts)
        }
    }

    private var totalLearnt: Int {
        vocabulary.byLevel.values.reduce(vocabulary.myWords.learnt) { $0 + $1.learnt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vocabulary")
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                Spacer()
                Text("\(totalLearnt) learnt")
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(levels.indices, id: \.self) { i in
                let item = levels[i]
                row(badge: CEFRBadgeView(level: item.level), title: item.level.displayName, counts: item.counts)
                if i < levels.count - 1 || vocabulary.myWords.total > 0 { Divider() }
            }
            if vocabulary.myWords.total > 0 {
                row(badge: EmptyView(), title: "My words", counts: vocabulary.myWords)
            }
        }
        .statisticsCard()
    }

    private func row(badge: some View, title: String, counts: VocabularyCounts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                badge
                Text(title).font(.subheadline)
                Spacer()
                Text("\(counts.learnt) / \(counts.total)")
                    .font(.subheadline.weight(.semibold))
            }
            ProgressBar(value: counts.learnt, total: counts.total)
        }
    }
}

// MARK: - Collection Progress Card

private struct CollectionProgressCard: View {
    let collections: [CollectionProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collection Progress")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))

            ForEach(collections) { collection in
                row(collection)
                if collection.id != collections.last?.id { Divider() }
            }
        }
        .statisticsCard()
    }

    private func row(_ collection: CollectionProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(collection.name).font(.subheadline)
                Spacer()
                Text("\(collection.learnt) / \(collection.total)")
                    .font(.subheadline.weight(.semibold))
            }
            ProgressBar(value: collection.learnt, total: collection.total)
        }
    }
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Preview

#Preview {
    StatisticsView(authService: AuthFBService())
        .modelContainer(for: [StudyDay.self, Card.self, CardSet.self, Collection.self, UserProfile.self],
                        inMemory: true)
}
