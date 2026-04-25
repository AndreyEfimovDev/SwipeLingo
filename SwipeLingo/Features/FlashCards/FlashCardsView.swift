import SwiftUI
import SwiftData

// MARK: - FlashCardsView

struct FlashCardsView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppViewModel.self) private var appViewModel
    @Query private var piles:       [Pile]
    @Query private var allCards:    [Card]
    @Query private var cardSets:    [CardSet]
    @Query private var collections: [Collection]
    @Query private var profiles:    [UserProfile]

    private var userLevel: CEFRLevel { profiles.first?.cefrLevel ?? .c2 }

    /// Сеты ≤ уровня пользователя. Сеты выше уровня хранятся локально, но не показываются.
    private var levelFilteredCardSets: [CardSet] {
        cardSets.filter { $0.cefrLevel <= userLevel }
    }

    @State private var viewModel = FlashCardsViewModel()
    @AppStorage("studyStartHour")  private var studyStartHour: Int = 6
    @AppStorage("srsEnabled")      private var srsEnabled: Bool    = true
    @AppStorage("userPlan") private var userPlan: AccessTier = .free

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// ID сетов ≤ уровня пользователя — для быстрой проверки принадлежности карточки.
    private var levelFilteredSetIds: Set<UUID> {
        Set(levelFilteredCardSets.map(\.id))
    }

    /// true если есть хотя бы одна активная карточка на уровне пользователя.
    private var hasActiveLevelCards: Bool {
        allCards.contains { $0.status == .active && levelFilteredSetIds.contains($0.setId) }
    }

    /// true если есть хотя бы одна активная карточка с подошедшим dueDate
    private var hasDueCards: Bool {
        let now = Date.now
        return allCards.contains { $0.status == .active && $0.dueDate <= now && levelFilteredSetIds.contains($0.setId) }
    }


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pileBadge
                    .padding(.top, 4)
                content
                    .animation(.spring(duration: 0.35, bounce: 0.1), value: viewModel.sessionID)
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .onAppear {
            viewModel.startSessionIfNeeded(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        .onChange(of: activePileSnapshot) {
            viewModel.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        .onChange(of: srsEnabled) {
            viewModel.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        .onChange(of: userPlan) {
            viewModel.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        // Перезапускаем сессию когда Firestore sync добавляет или удаляет карточки.
        // Используем allCards.count (не cardSets.count): @Query обновляет свои свойства
        // независимо, и onChange(cardSets) мог срабатывать до того как allCards обновился —
        // тогда startNewSession строил сессию с пустым allCards и studyCards оставался пустым.
        // onChange(allCards.count) гарантирует что allCards уже актуален в момент вызова.
        //
        // Любое изменение числа карточек (sync добавил новый сет или удалил карточки) →
        // startNewSession: нужно перестроить сессию чтобы включить новый контент / убрать удалённый.
        // Sync запускается только из библиотеки, пока пользователь не изучает карточки,
        // поэтому прерывания активной сессии не происходит.
        .onChange(of: allCards.count) {
            viewModel.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !hasActiveLevelCards {
            emptyStateView
        } else if viewModel.isCaughtUp {
            caughtUpView
                .id(viewModel.sessionID)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else if viewModel.studyCards.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TinderCardsView(
                cards: viewModel.studyCards,
                lockedCardIds: viewModel.lockedCardIds,
                contextLabels: viewModel.contextLabels,
                cefrLabels: viewModel.cefrLabels,
                pileTagsLine: viewModel.pileTagsLine,
                isDueMode: viewModel.studyMode == .due,
                pileLearntCount: viewModel.pileLearntCount,
                onToggleMode: srsEnabled ? {
                    if viewModel.studyMode == .due {
                        // Due → All: перезагружаем сессию со всеми карточками
                        viewModel.studyAll(
                            piles: piles, allCards: allCards,
                            cardSets: levelFilteredCardSets, collections: collections
                        )
                    } else if hasDueCards {
                        // All → Due: есть due карточки — загружаем их
                        viewModel.startNewSession(
                            piles: piles, allCards: allCards,
                            cardSets: levelFilteredCardSets, collections: collections,
                            dueHour: studyStartHour, srsEnabled: srsEnabled
                        )
                    } else {
                        // All → Due: нет due карточек — не сбрасываем сессию,
                        // только меняем режим отображения → покажет caught-up оверлей
                        viewModel.switchToDueDisplay()
                    }
                } : nil,
                hasDueCards: hasDueCards,
                onDone: {
                    viewModel.onSessionComplete(
                        piles: piles, allCards: allCards,
                        cardSets: levelFilteredCardSets, collections: collections,
                        dueHour: studyStartHour
                    )
                }
            )
            .id(viewModel.sessionID)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
            .padding(.vertical)
        }
    }

    // MARK: - Pile Badge

    private var pileBadge: some View {
        let name = viewModel.activePileName
        let hasActivePile = !name.isEmpty && name != "All Cards"
        return Button { appViewModel.activeSheet = .cardsLibrary } label: {
            HStack(spacing: 6) {
                Text(hasActivePile ? name : "All Cards")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(
                        hasActivePile
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
                        piles: piles, allCards: allCards,
                        cardSets: levelFilteredCardSets, collections: collections,
                        userPlan: userPlan
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
            Menu {
                Button { appViewModel.studyMode = .pairs } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").frame(width: 20)
                        Text("Switch to Pairs")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    // Включает userLevel чтобы смена уровня CEFR гарантированно перестраивала сессию
    // через уже проверенный onChange(of: activePileSnapshot) — надёжнее отдельного
    // onChange на profiles, который может не срабатывать пока view перекрыт fullScreenCover.
    private var activePileSnapshot: String {
        let levelPart = userLevel.rawValue
        guard let pile = piles.first(where: { $0.isActive }) else { return levelPart }
        let sets = pile.setIds.map(\.uuidString).sorted().joined()
        return levelPart + pile.id.uuidString + sets + pile.shuffleMethod.rawValue
    }
}
