import SwiftUI
import SwiftData

// MARK: - DynamicCardsView
// Главный экран раздела Pairs.
// Центральная кнопка Play запускает PairsSessionView.
// Если SRS включён — переключатель All/Due фильтрует сеты по dueDate.

struct DynamicCardsView: View {

    @Environment(AppViewModel.self) private var appViewModel

    @Query(sort: \DynamicSet.createdAt, order: .reverse) private var allSets: [DynamicSet]
    @Query private var allPiles: [PairsPile]

    @AppStorage("srsEnabled")           private var srsEnabled: Bool = true
    @AppStorage("dynamicAnimationMode") private var animationMode: AnimationMode = .manual

    @State private var isDueMode = false

    private let service = PairsPileService()

    private var activePile: PairsPile? { allPiles.first { $0.isActive } }

    private var candidateSets: [DynamicSet] {
        if let pile = activePile {
            return service.sets(for: pile, from: allSets)
        }
        return allSets
    }

    private var dueSets: [DynamicSet] {
        let now = Date.now
        return candidateSets.filter { $0.dueDate <= now }
    }

    private var displayedSets: [DynamicSet] {
        isDueMode && srsEnabled ? dueSets : candidateSets
    }

    /// Суммарное количество пар — вычисляется один раз на рендер, не инлайн в body.
    /// DynamicSet.items декодирует JSON при каждом обращении, поэтому важно не
    /// вызывать его внутри withAnimation или повторяющихся вложенных вычислений.
    private var displayedPairsCount: Int {
        displayedSets.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidateSets.isEmpty {
                    emptyState
                } else {
                    playScreen
                }
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
                Button { appViewModel.activeSheet = .pairsLibrary } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "books.vertical").frame(width: 20)
                        Text("Library")
                    }
                }
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
                Image(systemName: "ellipsis.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myBlue)
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
            pileStrip

            Spacer()

            // Auto/Manual toggle — всегда виден
            animationModeToggle
                .padding(.bottom, 8)

            // All/Due toggle — только если SRS включён
            if srsEnabled {
                modeToggle
                    .padding(.bottom, 20)
            }

            if displayedSets.isEmpty {
                // Due mode, но нет due-сетов
                caughtUpView
            } else {
                NavigationLink(destination: PairsSessionView(sets: displayedSets, pileName: activePile?.name ?? "Pairs")) {
                    VStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 80))
                        Text("Play")
                            .font(.title2.weight(.semibold))
                        Text("\(displayedSets.count) \(displayedSets.count == 1 ? "set" : "sets")")
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
                    }
                }
                .foregroundStyle(Color.myColors.myBlue)
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Animation Mode Toggle (Auto / Manual)

    private var animationModeToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "Manual", active: animationMode == .manual) {
                animationMode = .manual
            }
            toggleButton(title: "Auto", active: animationMode == .automatic) {
                animationMode = .automatic
            }
        }
        .background(Color.myColors.myAccent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 24)
    }

    // MARK: - All/Due Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "All", active: !isDueMode) {
                isDueMode = false
            }
            toggleButton(
                title: dueSets.isEmpty ? "Due" : "Due (\(dueSets.count))",
                active: isDueMode
            ) {
                isDueMode = true
            }
        }
        .background(Color.myColors.myAccent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 24)
    }

    private func toggleButton(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.myColors.myAccent : Color.myColors.myAccent.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(active ? Color.myColors.myAccent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Caught Up (Due mode, нет due-сетов)

    private var caughtUpView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 52))
                .foregroundStyle(Color.myColors.myGreen.opacity(0.7))
            Text("All caught up!")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text("No sets due for review")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
            Button {
                isDueMode = false
            } label: {
                Text("Play All")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.myColors.myBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Pile Strip

    private var pileStrip: some View {
        HStack {
            if let pile = activePile {
                Text("\(pile.name)  ·  \(displayedSets.count) \(displayedSets.count == 1 ? "set" : "sets") (\(displayedPairsCount))")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
            } else {
                Text("No pile set — all sets will play")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.45))
            }

            Spacer()

            Button {
                appViewModel.activeSheet = .pairsLibrary
            } label: {
                Text("Set Pile")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.myColors.myAccent.opacity(0.05))
    }

    // MARK: - Empty State (нет сетов вообще)

    private var emptyState: some View {
        VStack(spacing: 16) {
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

            VStack(spacing: 0) { pileStrip }
                .background(Color.myColors.myAccent.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
