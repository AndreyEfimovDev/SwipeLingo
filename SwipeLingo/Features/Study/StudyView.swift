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

    /// ISO 639-1 two-letter abbreviation for the selected native language (uppercase, e.g. "RU").
    private var langAbbr: String {
        DictionaryLookupViewModel.targetLangId(for: nativeLanguage).uppercased()
    }

    /// Button label reflecting the actual language, e.g. "EN→RU" or "RU→EN".
    private var directionLabel: String {
        studyDirection == "EN→Native" ? "EN→\(langAbbr)" : "\(langAbbr)→EN"
    }

    var body: some View {
        NavigationStack {
            content
                .animation(.spring(duration: 0.35, bounce: 0.1), value: viewModel.sessionID)
                .navigationTitle(viewModel.activePileName.isEmpty ? "Study" : viewModel.activePileName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $viewModel.isShowingAddCard) {
                    AddEditCardView()
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
        .onChange(of: activePileSnapshot) {
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
        } else if viewModel.isCaughtUp {
            caughtUpView
                .id(viewModel.sessionID)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else if viewModel.studyCards.isEmpty {
            ProgressView()
        } else {
            TinderCardsView(
                cards: viewModel.studyCards,
                contextLabels: viewModel.contextLabels,
                cefrLabels: viewModel.cefrLabels,
                pileTagsLine: viewModel.pileTagsLine,
                isDueMode: viewModel.studyMode == .due,
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
            .transition(.scale(scale: 0.95).combined(with: .opacity))
            .padding(.vertical)
        }
    }

    // MARK: - Caught-up Screen

    private var caughtUpView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.myColors.myBackground)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.myColors.myGreen)

                    Text("You're all caught up!")
                        .font(.title2.bold())

                    if !viewModel.nextReviewLabel.isEmpty {
                        Text("Next review: \(viewModel.nextReviewLabel)")
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                    }
                }
                .multilineTextAlignment(.center)

                Spacer()

                Button {
                    viewModel.studyAll(
                        piles: piles,
                        allCards: allCards,
                        cardSets: cardSets,
                        collections: collections
                    )
                } label: {
                    Text("Study anyway  ·  All: \(viewModel.allActiveCount)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.myColors.myBlue.opacity(0.12))
                        .foregroundStyle(Color.myColors.myBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.myColors.myBlue.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .myShadow()
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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
                    .font(.subheadline.weight(.medium))
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

    /// Changes when the active pile switches, its sets change, or shuffle method changes.
    private var activePileSnapshot: String {
        guard let pile = piles.first(where: { $0.isActive }) else { return "" }
        let sets = pile.setIds.map(\.uuidString).sorted().joined()
        return pile.id.uuidString + sets + pile.shuffleMethod.rawValue
    }

    private var activePileID: UUID? {
        piles.first(where: { $0.isActive })?.id
    }

    private var activeSetId: UUID? {
        guard let pile = piles.first(where: { $0.isActive }) else { return nil }
        return pile.setIds.first
    }
}
