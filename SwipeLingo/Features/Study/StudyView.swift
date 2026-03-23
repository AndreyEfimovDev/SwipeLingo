import SwiftUI
import SwiftData

// MARK: - StudyView

struct StudyView: View {

    @Environment(\.modelContext) private var context
    @Query private var piles: [Pile]
    @Query private var allCards: [Card]
    @Query private var cardSets: [CardSet]

    @State private var viewModel = StudyViewModel()

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
            MockDataSeeder.seedIfNeeded(into: context)
            viewModel.startSessionIfNeeded(piles: piles, allCards: allCards, cardSets: cardSets)
        }
        .onChange(of: activePileID) {
            viewModel.startNewSession(piles: piles, allCards: allCards, cardSets: cardSets)
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
                pileTagsLine: viewModel.pileTagsLine
            )
            .id(viewModel.sessionID)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { viewModel.isShowingAddCard = true } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Нет карточек для изучения")
                .font(.title3.bold())
            Text("Добавьте карточки в Library или создайте Pile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
