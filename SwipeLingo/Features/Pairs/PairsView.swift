import SwiftUI
import SwiftData

// MARK: - PairsView
// Главный экран раздела Pairs.
// Layout: pile badge (кнопка) вверху, два toggle по краям, Play внизу.

struct PairsView: View {

    @Environment(AppViewModel.self) private var appViewModel

    @Query(sort: \PairsSet.createdAt, order: .reverse) private var allSets: [PairsSet]
    @Query private var allPiles: [PairsPile]

    @AppStorage("srsEnabled")           private var srsEnabled: Bool = true
    @AppStorage("pairsAnimationMode") private var animationMode: AnimationMode = .manual

    @State private var isDueMode = false

    private let service = PairsPileService()

    private var activePile: PairsPile? { allPiles.first { $0.isActive } }

    private var candidateSets: [PairsSet] {
        if let pile = activePile { return service.sets(for: pile, from: allSets) }
        return allSets
    }

    private var dueSets: [PairsSet] {
        candidateSets.filter { $0.dueDate <= Date.now }
    }

    private var displayedSets: [PairsSet] {
        isDueMode && srsEnabled ? dueSets : candidateSets
    }

    private var displayedPairsCount: Int {
        displayedSets.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidateSets.isEmpty { emptyState } else { playScreen }
            }
            .navigationTitle("Pairs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { pairsToolbar }
            .onAppear { selectDefaultMode() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var pairsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { appViewModel.studyMode = .cards } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.stack").frame(width: 20)
                        Text("Switch to Cards")
                    }
                }
                Divider()
                Button { appViewModel.activeSheet = .statistics } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.line.uptrend.xyaxis").frame(width: 20)
                        Text("Statistics")
                    }
                }
                Button { appViewModel.activeSheet = .settings } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gear").frame(width: 20)
                        Text("Settings")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    // MARK: - Default Mode Selection

    private func selectDefaultMode() {
        guard srsEnabled else { isDueMode = false; return }
        isDueMode = !dueSets.isEmpty
    }

    // MARK: - Play Screen

    private var playScreen: some View {
        VStack(spacing: 0) {

            // Pile badge — кнопка, открывает библиотеку для смены pile
            pileBadge
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Preview: левая часть пар из активного pile/all sets
            previewContent

            // [Auto/Manual] · [Play / Caught up] · [Due/All]
            mainRow
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.myColors.myBackground.ignoresSafeArea())
    }

    // MARK: - Preview Content

    /// Первые 12 пар из displayedSets: left виден, right — размытый.
    /// Создаёт эффект «вижу структуру, но не могу прочитать ответы».
    /// Первые 12 пар из displayedSets, сгруппированных по tag.
    private var previewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(previewGroups.enumerated()), id: \.offset) { groupIdx, group in
                    // Разделитель между группами
                    if groupIdx > 0 {
                        Rectangle()
                            .fill(Color.myColors.myAccent.opacity(0.08))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                    }
                    // Заголовок группы с серым фоном
                    if !group.tag.isEmpty {
                        Text(group.tag.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                            .background(Color.myColors.myAccent.opacity(0.04))
                    }
                    // Пары группы
                    ForEach(Array(group.pairs.enumerated()), id: \.offset) { i, pair in
                        previewRow(pair)
                        if i < group.pairs.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                                .opacity(0.35)
                        }
                    }
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
            .padding(.top, 30)
        }
        .scrollDisabled(true)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func previewRow(_ pair: Pair) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Line 1: left [+ right]
            HStack(spacing: 0) {
                Text(pair.left ?? "—")
                    .font(.body)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let right = pair.right {
                    Rectangle()
                        .fill(Color.myColors.myAccent.opacity(0.1))
                        .frame(width: 1)
                        .padding(.vertical, 2)

                    Text(right)
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
            }

            // Line 2: description
            if let desc = pair.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.28))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Line 3: sample
            if let sample = pair.sample, !sample.isEmpty {
                Text(sample)
                    .font(.subheadline.italic())
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.22))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var previewGroups: [(tag: String, pairs: [Pair])] {
        var result: [(tag: String, pairs: [Pair])] = []
        var remaining = 12
        for set in displayedSets {
            var i = 0
            while i < set.items.count && remaining > 0 {
                let tag = set.items[i].tag
                var groupPairs: [Pair] = []
                while i < set.items.count && set.items[i].tag == tag && remaining > 0 {
                    groupPairs.append(set.items[i])
                    remaining -= 1
                    i += 1
                }
                if !groupPairs.isEmpty {
                    result.append((tag: tag, pairs: groupPairs))
                }
            }
            if remaining <= 0 { break }
        }
        return result
    }

    // MARK: - Main Row

    private var mainRow: some View {
        HStack(alignment: .center, spacing: 0) {

            // Auto / Manual
            PairsVerticalToggle(
                topLabel:    "Auto",
                bottomLabel: "Manual",
                activeColor: Color.myColors.myPurple,
                isOn: Binding(
                    get: { animationMode == .automatic },
                    set: { animationMode = $0 ? .automatic : .manual }
                )
            )
            .frame(width: 80)

            Spacer()

            // Play / Caught up — ZStack резервирует размер под бо́льший элемент
            ZStack {
                playButton
                    .opacity(displayedSets.isEmpty ? 0 : 1)
                caughtUpCenter
                    .opacity(displayedSets.isEmpty ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: displayedSets.isEmpty)

            Spacer()

            // Due / All (только если SRS включён, иначе placeholder для симметрии)
            if srsEnabled {
                PairsVerticalToggle(
                    topLabel:    "Due",
                    bottomLabel: "All",
                    activeColor: Color.myColors.myOrange,
                    isOn: $isDueMode
                )
                .frame(width: 80)
            } else {
                Color.clear.frame(width: 80)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 24)
    }

    // MARK: - Pile Badge

    private var pileBadge: some View {
        Button { appViewModel.activeSheet = .pairsLibrary } label: {
            HStack(spacing: 6) {
                Text(activePile?.name ?? "All Sets")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        activePile != nil
                            ? Color.myColors.myAccent.opacity(0.75)
                            : Color.myColors.myAccent.opacity(0.35)
                    )
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Play Button

    private var playButton: some View {
        NavigationLink(
            destination: PairsSessionView(
                sets: displayedSets,
                pileName: activePile?.name ?? "Pairs"
            )
        ) {
            VStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 88))
                Text("\(displayedSets.count) \(displayedSets.count == 1 ? "set" : "sets")")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
        }
        .foregroundStyle(Color.myColors.myBlue)
        .buttonStyle(.plain)
    }

    // MARK: - Caught Up (компактный, центр mainRow)

    private var caughtUpCenter: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.myColors.myGreen.opacity(0.7))
            Text("Nothing due right now")
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.45))
            NavigationLink(
                destination: PairsSessionView(
                    sets: candidateSets,
                    pileName: activePile?.name ?? "Pairs"
                )
            ) {
                Text("Play All")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.myColors.myBlue.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            pileBadge
                .padding(.bottom, 8)

            Image(systemName: "square.stack")
                .font(.system(size: 52))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Text(activePile != nil ? "No sets in this pile" : "No sets available")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text(activePile != nil
                 ? "Add sets to \"\(activePile!.name)\" to get started"
                 : "Pairs sets will appear here once downloaded")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.myColors.myBackground.ignoresSafeArea())
    }
}
