import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - CardsView

struct CardsView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Передаются из composition root через AppView — не через .environment().
    private let appViewModel: AppViewModel
    private let authService: AuthFBService
    private let userService: UserFBService
    /// Форвардятся дальше в TinderCardsView.
    private let appSyncStateService: AppSyncStateService
    private let appSettings: AppSettings
    private let audioService: AudioPlayerService

    init(appViewModel: AppViewModel, authService: AuthFBService, userService: UserFBService, appSyncStateService: AppSyncStateService, appSettings: AppSettings, audioService: AudioPlayerService) {
        self.appViewModel = appViewModel
        self.authService = authService
        self.userService = userService
        self.appSyncStateService = appSyncStateService
        self.appSettings = appSettings
        self.audioService = audioService
    }

    @Query private var piles:       [Pile]
    @Query private var allCards:    [Card]
    @Query private var cardSets:    [CardSet]
    @Query private var collections: [Collection]
    @Query private var profiles:    [UserProfile]

    /// Фильтрует по "моим" (firebaseUID) — не наивный `profiles.first`, иначе на
    /// общем iCloud с чужим уже синкнутым профилем контент фильтровался бы по
    /// чужому уровню.
    private var userLevel: CEFRLevel {
        UserProfileDedupeService().resolveProfile(
            firebaseUID: authService.currentUser?.uid ?? "", allProfiles: profiles, context: context
        )?.cefrLevel ?? .c2
    }

    /// Сеты ≤ уровня пользователя, не мягко удалённые.
    private var levelFilteredCardSets: [CardSet] {
        cardSets.filter { $0.cefrLevel <= userLevel && !$0.isSoftDeleted }
    }

    @State private var vm = FlashCardsViewModel()
    /// Единственный источник правды — AppSyncStateService (SwiftData + CloudKit-синк).
    private var studyStartHour: Int { appSyncStateService.studyStartHour }
    private var srsEnabled: Bool { appSyncStateService.srsEnabled }
    /// Единственный источник правды — UserFBService (см. UserFBService.swift).
    private var userPlan: AccessTier { userService.userPlan }

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// ID сетов ≤ уровня пользователя — для быстрой проверки принадлежности карточки.
    private var levelFilteredSetIds: Set<UUID> {
        Set(levelFilteredCardSets.map(\.id))
    }

    /// Сеты, доступные для текущей сессии: с учётом активной стопки (если есть).
    private var sessionSetIds: Set<UUID> {
        if let pile = piles.first(where: { $0.isActive }) {
            // Только сеты стопки, которые попадают в уровень пользователя
            return levelFilteredSetIds.intersection(pile.setIds)
        }
        return levelFilteredSetIds
    }

    /// true если есть хотя бы одна активная карточка в текущей сессии (с учётом стопки).
    private var hasActiveLevelCards: Bool {
        allCards.contains { $0.status == .active && sessionSetIds.contains($0.setId) }
    }

    /// true если есть хотя бы одна активная карточка с подошедшим dueDate
    private var hasDueCards: Bool {
        let now = Date.now
        return allCards.contains { $0.status == .active && $0.dueDate <= now && sessionSetIds.contains($0.setId) }
    }


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pileBadge
                    .padding(.top, 8)
                    .padding(.horizontal)
                content
                    .animation(.spring(duration: 0.35, bounce: 0.1), value: vm.sessionID)
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .background(Color.myColors.myBackground.ignoresSafeArea())
        }
        .onAppear {
            vm.startSessionIfNeeded(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        .onChange(of: activePileSnapshot) {
            vm.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        .onChange(of: srsEnabled) {
            vm.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        .onChange(of: userPlan) {
            vm.startNewSession(
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
            vm.startNewSession(
                piles: piles, allCards: allCards,
                cardSets: levelFilteredCardSets, collections: collections,
                dueHour: studyStartHour, srsEnabled: srsEnabled,
                userPlan: userPlan
            )
        }
        // Лёгкое обновление счётчиков (не полный reload сессии — studyCards/sessionID/
        // currentIndex/isCaughtUp не трогаются) один раз при закрытии ЛЮБОГО sheet
        // (Library/Settings/...) — а не при каждой мутации статуса карточки. Статус может
        // поменяться вне активной сессии (напр. swipe action "Restore" в CardSetDetailView,
        // или restore из DeletedCardsView в Settings), allCards.count при этом не меняется,
        // поэтому onChange(allCards.count) выше это не ловит. Пока sheet открыт, CardsView и
        // так не виден — обновлять счётчики раньше, чем пользователь их увидит, незачем;
        // раньше это делалось вычисляемым ключом (pileCountsSnapshot), пересчитывавшимся на
        // КАЖДЫЙ re-render CardsView (в т.ч. скрытого под sheet) — лишняя O(n)-работа на
        // каждую мутацию Card/Pile в БД, конкурировавшая за runloop с List/PreferenceKey
        // синхронизацией высоты строк в CardSetDetailView и заметно тормозившая свайп-жесты
        // там. Разовый пересчёт на закрытие sheet эту стоимость убирает.
        .onChange(of: appViewModel.activeSheet) { oldSheet, newSheet in
            if oldSheet != nil && newSheet == nil {
                vm.refreshPileCounts(piles: piles, allCards: allCards, cardSets: levelFilteredCardSets)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !hasActiveLevelCards {
            emptyStateView
        } else if vm.isCaughtUp {
            caughtUpView
                .id(vm.sessionID)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else if vm.studyCards.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TinderCardsView(
                cards: vm.studyCards,
                appViewModel: appViewModel,
                authService: authService,
                userService: userService,
                appSyncStateService: appSyncStateService,
                appSettings: appSettings,
                audioService: audioService,
                lockedCardIds: vm.lockedCardIds,
                contextLabels: vm.contextLabels,
                cefrLabels: vm.cefrLabels,
                pileTagsLine: vm.pileTagsLine,
                isDueMode: vm.studyMode == .due,
                pileLearntCount: vm.pileLearntCount,
                onToggleMode: srsEnabled ? {
                    if vm.studyMode == .due {
                        // Due → All: перезагружаем сессию со всеми карточками
                        vm.studyAll(
                            piles: piles, allCards: allCards,
                            cardSets: levelFilteredCardSets, collections: collections
                        )
                    } else if hasDueCards {
                        // All → Due: есть due карточки — загружаем их
                        vm.startNewSession(
                            piles: piles, allCards: allCards,
                            cardSets: levelFilteredCardSets, collections: collections,
                            dueHour: studyStartHour, srsEnabled: srsEnabled
                        )
                    } else {
                        // All → Due: нет due карточек — не сбрасываем сессию,
                        // только меняем режим отображения → покажет caught-up оверлей
                        vm.switchToDueDisplay()
                    }
                } : nil,
                hasDueCards: hasDueCards,
                onDone: {
                    vm.onSessionComplete(
                        piles: piles, allCards: allCards,
                        cardSets: levelFilteredCardSets, collections: collections,
                        dueHour: studyStartHour
                    )
                }
            )
            .id(vm.sessionID)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
            .padding(.vertical)
        }
    }

    // MARK: - Pile Badge

    private var pileBadge: some View {
        let name = vm.activePileName
        let hasActivePile = !name.isEmpty && name != "All Cards"
        return PileBadgeView(title: hasActivePile ? name : "All Cards", isActive: hasActivePile) {
            appViewModel.activeSheet = .cardsLibrary
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

                    if !vm.nextReviewLabel.isEmpty {
                        Text("Next review: \(vm.nextReviewLabel)")
                            .font(.subheadline)
                            .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                    }
                }
                .multilineTextAlignment(.center)

                Spacer()

                Button {
                    vm.studyAll(
                        piles: piles, allCards: allCards,
                        cardSets: levelFilteredCardSets, collections: collections,
                        userPlan: userPlan
                    )
                } label: {
                    Text("Study anyway  ·  All: \(vm.allActiveCount)")
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
        MainScreenToolbar(appViewModel: appViewModel, currentMode: .cards)
    }

    private var emptyStateView: some View {
        let activePile = piles.first(where: { $0.isActive })
        return VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Text("No cards to study")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text(activePile != nil
                 ? "Pile \"\(activePile!.name)\" has no active cards.\nAdd sets in Library."
                 : "Add cards in Library or create a Pile")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.myColors.myBackground.ignoresSafeArea())
    }

    // MARK: - Helpers

    // Включает userLevel чтобы смена уровня CEFR гарантированно перестраивала сессию
    // через уже проверенный onChange(of: activePileSnapshot) — надёжнее отдельного
    // onChange на profiles, который может не срабатывать пока view перекрыт fullScreenCover.
    private var activePileSnapshot: String {
        let levelPart = userLevel.rawValue
        guard let pile = piles.first(where: { $0.isActive }) else { return levelPart }
        let sets = pile.setIds.map(\.uuidString).sorted().joined()
        // pile.name включено, иначе переименование стопки (без изменения сетов/shuffleMethod)
        // не триггерит onChange → vm.activePileName остаётся закэшированным старым значением.
        return levelPart + pile.id.uuidString + pile.name + sets + pile.shuffleMethod.rawValue
    }
}
