import SwiftUI
import SwiftData

// MARK: - DynamicCardsView
// Главный экран раздела Pairs.
// Центральная кнопка Play запускает PairsSessionView.
// Полоска под nav bar всегда показывает активный pile (или подсказку если его нет).

struct DynamicCardsView: View {

    @Environment(AppViewModel.self) private var appViewModel

    @Query(sort: \DynamicSet.createdAt, order: .reverse) private var allSets: [DynamicSet]
    @Query private var allPiles: [PairsPile]

    private let service = PairsPileService()

    private var activePile: PairsPile? { allPiles.first { $0.isActive } }

    private var displayedSets: [DynamicSet] {
        if let pile = activePile {
            return service.sets(for: pile, from: allSets)
        }
        return allSets
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayedSets.isEmpty {
                    emptyState
                } else {
                    playScreen
                }
            }
            .navigationTitle("Pairs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Play Screen

    private var playScreen: some View {
        VStack(spacing: 0) {
            pileStrip

            Spacer()

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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Pile Strip
    // Всегда видна: имя активного pile или подсказка, + кнопка смены pile.

    private var pileStrip: some View {
        HStack {
            if let pile = activePile {
                Text(pile.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.myColors.myAccent)
            } else {
                Text("No pile set — all sets will play")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.45))
            }

            Spacer()

            Button {
                appViewModel.selectedTab = .pairsLibrary
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
