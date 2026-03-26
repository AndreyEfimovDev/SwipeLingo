import SwiftUI
import SwiftData

// MARK: - StudyView

struct StudyView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var piles: [Pile]
    @Query private var allCards: [Card]
    @Query private var cardSets: [CardSet]
    @Query private var collections: [Collection]

    @State private var viewModel = StudyViewModel()
    @AppStorage("studyDirection") private var studyDirection = "EN→Native"
    @AppStorage("nativeLanguage") private var nativeLanguage = "Русский"

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// ISO 639-1 two-letter abbreviation for the selected native language.
    private var langAbbr: String {
        switch nativeLanguage {
        case "Русский":   return "RU"  // Russian
        case "中文":       return "ZH"  // Chinese (Mandarin)
        case "Español":   return "ES"  // Spanish
        case "Français":  return "FR"  // French
        case "العربية":   return "AR"  // Arabic
        case "Português": return "PT"  // Portuguese
        case "Deutsch":   return "DE"  // German
        case "日本語":     return "JA"  // Japanese
        default:          return String(nativeLanguage.prefix(2)).uppercased()
        }
    }

    /// Button label reflecting the actual language, e.g. "EN→RU" or "RU→EN".
    private var directionLabel: String {
        studyDirection == "EN→Native" ? "EN→\(langAbbr)" : "\(langAbbr)→EN"
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(viewModel.activePileName.isEmpty ? "Study" : viewModel.activePileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $viewModel.isShowingAddCard) {
                    AddCardView(preselectedSetId: activeSetId)
                }
        }
        .onAppear {
            // Seeding happens in SwipeLingoApp.init() before any view renders,
            // so @Query results are already populated here.
            viewModel.startSessionIfNeeded(
                piles: piles,
                allCards: allCards,
                cardSets: cardSets,
                collections: collections
            )
        }
        .onChange(of: activePileID) {
            viewModel.startNewSession(
                piles: piles,
                allCards: allCards,
                cardSets: cardSets,
                collections: collections
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if allCards.filter({ $0.status == .active }).isEmpty {
            emptyStateView
        } else if viewModel.studyCards.isEmpty {
            ProgressView()
        } else {
            TinderCardsView(
                cards: viewModel.studyCards,
                contextLabels: viewModel.contextLabels,
                pileTagsLine: viewModel.pileTagsLine,
                onDone: {
                    viewModel.startNewSession(
                        piles: piles,
                        allCards: allCards,
                        cardSets: cardSets,
                        collections: collections
                    )
                }
            )
            .id(viewModel.sessionID)
            .padding(.vertical)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                studyDirection = studyDirection == "EN→Native" ? "Native→EN" : "EN→Native"
            } label: {
                Text(directionLabel)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { viewModel.isShowingAddCard = true } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52))
            Text("No cards to study")
                .font(.title3.bold())
            Text("Add cards in Library or create a Pile")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    private var activePileID: UUID? {
        piles.first(where: { $0.isActive })?.id
    }

    private var activeSetId: UUID? {
        guard let pile = piles.first(where: { $0.isActive }) else { return nil }
        return pile.setIds.first
    }
}
