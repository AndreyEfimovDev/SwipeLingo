import SwiftUI
import SwiftData

// MARK: - PairsView
// Главный экран раздела Pairs.
// Layout: pile badge вверху, тройка (toggle | Set Pile | toggle) по центру, Play внизу.

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

            // Pile badge
            pileBadge
                .padding(.top, 8)

            Spacer()

            // Центральная тройка: toggle | Set Pile | toggle
            controlsRow

            Spacer()

            // Play button / Caught up — ZStack резервирует высоту под бо́льший элемент,
            // переключение через opacity не вызывает прыжков layout
            ZStack {
                playButton
                    .opacity(displayedSets.isEmpty ? 0 : 1)
                caughtUpView
                    .opacity(displayedSets.isEmpty ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: displayedSets.isEmpty)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.myColors.myBackground.ignoresSafeArea())
    }

    // MARK: - Pile Badge

    private var pileBadge: some View {
        Text(activePile?.name ?? "All Sets")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(
                activePile != nil
                    ? Color.myColors.myAccent.opacity(0.75)
                    : Color.myColors.myAccent.opacity(0.35)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.myColors.myAccent.opacity(activePile != nil ? 0.09 : 0.05))
            )
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(alignment: .center, spacing: 0) {

            // Auto / Manual
            PairsVerticalToggle(
                topLabel:    "Auto",
                bottomLabel: "Manual",
                activeColor: Color.myColors.myBlue,
                isOn: Binding(
                    get: { animationMode == .automatic },
                    set: { animationMode = $0 ? .automatic : .manual }
                )
            )
            .frame(width: 80)

            Spacer()

            // Set Pile — центральный элемент
            setPileButton

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
        .padding(.horizontal, 32)
    }

    // MARK: - Set Pile Button

    private var setPileButton: some View {
        Button { appViewModel.activeSheet = .pairsLibrary } label: {
            VStack(spacing: 6) {
                Image(systemName: activePile != nil ? "folder.fill" : "folder.badge.plus")
                    .font(.system(size: 22))
                Text("Set Pile")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(Color.myColors.myBlue)
            .frame(width: 100, height: 76)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.myColors.myBlue.opacity(0.08))
            )
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
                    .font(.system(size: 108))
//                Text("Play")
//                    .font(.largeTitle.weight(.semibold))
                Text("\(displayedSets.count) \(displayedSets.count == 1 ? "set" : "sets")")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
        }
        .foregroundStyle(Color.myColors.myBlue)
        .buttonStyle(.plain)
    }

    // MARK: - Caught Up

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
            Button { isDueMode = false } label: {
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

    // MARK: - Empty State

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

            Button { appViewModel.activeSheet = .pairsLibrary } label: {
                Text("Set Pile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myBlue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.myColors.myBlue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.myColors.myBackground.ignoresSafeArea())
    }
}
