import SwiftUI
import SwiftData

// MARK: - AppViewModel

@Observable
final class AppViewModel {
    var selectedTab: AppTab = .study

    enum AppTab {
        case study, library, preferences
    }
}

// MARK: - AppView

struct AppView: View {
    @Environment(\.modelContext) private var context
    @Query private var allCards: [Card]
    @Query private var cardSets: [CardSet]

    @State private var viewModel = AppViewModel()

    var body: some View {
        Group {
            if studyCards.isEmpty {
                seedingView
            } else {
                TinderCardsView(
                    cards: studyCards,
                    contextLabels: contextLabels
                )
            }
        }
        // Stage 3: replace Group with TabView (Study / Library / Preferences)
    }

    // MARK: - Derived

    /// Cards available for the current study session.
    private var studyCards: [Card] {
        allCards.filter { $0.status == .active }
    }

    /// Maps setId → CardSet name for display inside TinderCardsView.
    private var contextLabels: [UUID: String] {
        Dictionary(uniqueKeysWithValues: cardSets.map { ($0.id, $0.name) })
    }

    // MARK: - Seeding Placeholder

    /// Shown on first launch while MockDataSeeder writes cards into SwiftData.
    private var seedingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Загрузка карточек…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .task {
            MockDataSeeder.seedIfNeeded(into: context)
        }
    }
}
