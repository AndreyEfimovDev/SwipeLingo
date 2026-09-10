import SwiftUI

// MARK: - Data Models

struct DailyActivity {
    let date: Date
    let cardsStudied: Int
    let easy: Int
    let hard: Int
    let forgot: Int
}

struct DeckProgress {
    let name: String
    let studied: Int
    let total: Int
    var percent: Double { Double(studied) / Double(max(1, total)) }
}

enum TimeRange: String, CaseIterable {
    case today = "Today"
    case week  = "Week"
    case month = "Month"
    case year  = "Year"
    case all   = "All"
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .all: return "All"
        }
    }
}

// MARK: - Mock Data
#warning("STUB: Remove before App Store release.")
struct StatisticsMockData {

    static let activities: [DailyActivity] = {
        var result: [DailyActivity] = []
        let cal = Calendar.current
        let today = Date()
        var rng = SystemRandomNumberGenerator()

        for daysAgo in 0..<365 {
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            // Some days have zero activity
            let studied = daysAgo % 3 == 0 ? 0 : Int.random(in: 1...45, using: &rng)
            if studied == 0 {
                result.append(DailyActivity(date: date, cardsStudied: 0, easy: 0, hard: 0, forgot: 0))
            } else {
                let easy   = max(0, Int(Double(studied) * Double.random(in: 0.45...0.70, using: &rng)))
                let hard   = max(0, Int(Double(studied) * Double.random(in: 0.10...0.25, using: &rng)))
                let forgot = max(0, studied - easy - hard)
                result.append(DailyActivity(date: date, cardsStudied: studied, easy: easy, hard: hard, forgot: forgot))
            }
        }
        return result
    }()

    static let deckProgress: [DeckProgress] = [
        DeckProgress(name: "IELTS Vocabulary",  studied: 142, total: 200),
        DeckProgress(name: "Academic Words",    studied:  67, total: 120),
        DeckProgress(name: "Business English",  studied:  30, total:  80),
        DeckProgress(name: "Phrasal Verbs",     studied:  12, total: 150),
    ]

    static let currentStreak: Int = 7
    static let bestStreak:    Int = 23
}

// MARK: - StatisticsView

struct StatisticsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var selectedRange: TimeRange    = .week
    @State private var isCalendarCompact: Bool     = false

    // MARK: Filtered helpers

    private var filteredActivities: [DailyActivity] {
        let cal  = Calendar.current
        let now  = Date()
        switch selectedRange {
        case .today:
            return StatisticsMockData.activities.filter { cal.isDateInToday($0.date) }
        case .week:
            guard let weekAgo = cal.date(byAdding: .day, value: -7, to: now) else { return [] }
            return StatisticsMockData.activities.filter { $0.date >= weekAgo }
        case .month:
            return StatisticsMockData.activities.filter {
                cal.component(.month, from: $0.date) == cal.component(.month, from: now) &&
                cal.component(.year,  from: $0.date) == cal.component(.year,  from: now)
            }
        case .year:
            return StatisticsMockData.activities.filter {
                cal.component(.year, from: $0.date) == cal.component(.year, from: now)
            }
        case .all:
            return StatisticsMockData.activities
        }
    }

    private var totalStudied: Int { filteredActivities.reduce(0) { $0 + $1.cardsStudied } }
    private var totalEasy:    Int { filteredActivities.reduce(0) { $0 + $1.easy    } }
    private var totalHard:    Int { filteredActivities.reduce(0) { $0 + $1.hard    } }
    private var totalForgot:  Int { filteredActivities.reduce(0) { $0 + $1.forgot  } }

    private var isEmpty: Bool {
        totalStudied == 0 && StatisticsMockData.currentStreak == 0
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    if isEmpty {
                        emptyState
                    } else {
                        UnderlineSegmentedPickerNotOptional(
                            selection: $selectedRange,
                            allItems: TimeRange.allCases,
                            titleForCase: { $0.displayName }
                        ).padding(.vertical, 8)
                        CardsStudiedCard(
                            total:  totalStudied,
                            easy:   totalEasy,
                            hard:   totalHard,
                            forgot: totalForgot
                        )
                        StreakCard(
                            current: StatisticsMockData.currentStreak,
                            best:    StatisticsMockData.bestStreak
                        )
                        ActivityCalendarCard(
                            activities: StatisticsMockData.activities,
                            isCompact:  $isCalendarCompact
                        )
                        DeckProgressCard(decks: StatisticsMockData.deckProgress)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                }
            }
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Range", selection: $selectedRange) {
            ForEach(TimeRange.allCases, id: \.self) {
                Text($0.displayName).tag($0)
            }
        }
        .pickerStyle(.segmented)
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
                .multilineTextAlignment(.center)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Streak Card

private struct StreakCard: View {
    let current: Int
    let best: Int

    private var progress: Double {
        guard best > 0 else { return 0 }
        return min(Double(current) / Double(best), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak")
                        .font(.caption.uppercaseSmallCaps())
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(current)")
                            .font(.title)
                            .fontWeight(.medium)
                        Text("days")
                            .font(.subheadline)
                    }
                }
                Spacer()
                Text("Best \(best) days")
                    .font(.caption.uppercaseSmallCaps())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.myColors.myAccent.opacity(0.5))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.myColors.myGreen)
                        .frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .background(Color.myColors.myBackground, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .myShadow()
    }
}

// MARK: - Cards Studied Card

private struct CardsStudiedCard: View {
    let total: Int
    let easy: Int
    let hard: Int
    let forgot: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cards Studied")
                .font(.caption.uppercaseSmallCaps())

            Text("\(total)")
                .font(.system(size: 52, weight: .bold, design: .rounded))

            if total > 0 {
                // Proportional bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        let w = geo.size.width
                        barSegment(color: .green,  width: w * CGFloat(easy)   / CGFloat(total))
                        barSegment(color: .orange, width: w * CGFloat(hard)   / CGFloat(total))
                        barSegment(color: .indigo, width: w * CGFloat(forgot) / CGFloat(total))
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(height: 12)
            }

            // Legend
            HStack(spacing: 20) {
                legendDot(color: .green,  label: "Easy",   count: easy)
                legendDot(color: .orange, label: "Hard",   count: hard)
                legendDot(color: .indigo, label: "Forgot", count: forgot)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.myColors.myBackground, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .myShadow()
    }

    private func barSegment(color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(width, 0), height: 12)
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

    let activities: [DailyActivity]
    @Binding var isCompact: Bool

    private let activityMap: [String: Int]
    private static let dayKey: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init(activities: [DailyActivity], isCompact: Binding<Bool>) {
        self.activities  = activities
        self._isCompact  = isCompact
        var map: [String: Int] = [:]
        for a in activities { map[Self.dayKey.string(from: a.date)] = a.cardsStudied }
        self.activityMap = map
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
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

            // Intensity legend
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
        .padding()
        .background(Color.myColors.myBackground, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .myShadow()
    }

    // MARK: Intensity

    private func intensityColor(cards: Int) -> Color {
        switch cards {
        case 0:       return Color(.systemGray6)
        case 1...10:  return Color.green.opacity(0.30)
        case 11...30: return Color.green.opacity(0.65)
        default:      return Color.green
        }
    }

    private var yearString: String {
        Date().formatted(.dateTime.year())
    }

    // MARK: Monthly Grid (4-col)

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
        let offset  = (weekday - 2 + 7) % 7   // Monday = 0
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

    // MARK: Compact 52-week View

    private var compactView: some View {
        let weeks      = last52Weeks()
        let dayLabels  = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        let cell: CGFloat    = 12
        let gap:  CGFloat    = 2
        let monthRowH: CGFloat = 16
        let labelColW: CGFloat = 22   // width reserved for sticky day labels

        // Day-label overlay — sticky on the left, white background hides cells scrolling behind
        let dayLabelColumn = VStack(alignment: .leading, spacing: gap) {
            Color.clear.frame(height: monthRowH)
            ForEach(dayLabels.indices, id: \.self) { i in
                Text(dayLabels[i])
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: labelColW - 2, height: cell, alignment: .trailing)
            }
        }
        .frame(width: labelColW)
        .background(Color.myColors.myBackground)  // mask scrolled-behind content

        return ScrollViewReader { proxy in
            // ScrollView occupies the FULL card width
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: gap) {

                    // Month labels row — offset right by labelColW so they align with grid
                    HStack(alignment: .bottom, spacing: gap) {
                        Color.clear.frame(width: labelColW, height: monthRowH) // spacer under label column
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

                    // Day grid row — starts after label column spacer
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: labelColW) // spacer under label column
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
            .overlay(alignment: .leading) { dayLabelColumn }  // sticky day labels
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo(weeks.count - 1, anchor: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    private func cardsCount(for date: Date) -> Int {
        activityMap[Self.dayKey.string(from: date)] ?? 0
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
        let yr   = cal.component(.year, from: date) % 100   // last 2 digits
        let mon  = date.formatted(.dateTime.month(.abbreviated))
        return "\(mon)-\(String(format: "%02d", yr))"
    }
}

// MARK: - Deck Progress Card

private struct DeckProgressCard: View {
    let decks: [DeckProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deck Progress")
                .font(.caption.uppercaseSmallCaps())

            ForEach(decks.indices, id: \.self) { i in
                deckRow(decks[i])
                if i < decks.count - 1 { Divider() }
            }
        }
        .padding()
        .background(Color.myColors.myBackground, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .myShadow()
    }

    private func deckRow(_ deck: DeckProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(deck.name).font(.subheadline)
                Spacer()
                Text("\(Int(deck.percent * 100))%")
                    .font(.subheadline.weight(.semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.myColors.myAccent.opacity(0.5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.myColors.myGreen)
                        .frame(width: geo.size.width * deck.percent, height: 6)
                }
            }
            .frame(height: 6)
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
    StatisticsView()
}
