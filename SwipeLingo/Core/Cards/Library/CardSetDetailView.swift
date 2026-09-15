import SwiftUI
import SwiftData

// MARK: - CardSetDetailView
// Третий уровень: список Cards внутри CardSet.
//
// Delete/Restore — двумя параллельными механизмами, как в системных приложениях Apple
// (Mail/Reminders/Notes): swipe actions на строке — для одной карточки, Edit-режим с
// мультивыбором + bulk action bar — для массовых операций. Не взаимоисключающие
// альтернативы — разные скорости работы с одним и тем же списком (см. HIG: Lists and
// Tables). List — с selection (как в DeletedCardsView), не голый List { } — тот вариант
// раньше давал лаг swipe-жеста в этом экране, у DeletedCardsView с тем же .swipeActions
// такого не было.

struct CardSetDetailView: View {

    @Environment(\.modelContext) private var context
    let cardSet: CardSet
    let allowsEditing: Bool
    let backTitle: String
    /// Передаются из composition root — не через .environment(). Только для PlansView.
    private let authService: AuthFBService
    private let userService: UserFBService
    /// Форвардится дальше в AddEditCardView.
    private let appSyncStateService: AppSyncStateService

    init(cardSet: CardSet, allowsEditing: Bool = false, backTitle: String = "Library",
         authService: AuthFBService, userService: UserFBService, appSyncStateService: AppSyncStateService) {
        self.cardSet = cardSet
        self.allowsEditing = allowsEditing
        self.backTitle = backTitle
        self.authService = authService
        self.userService = userService
        self.appSyncStateService = appSyncStateService
    }

    @Query(sort: \Card.createdAt) private var allCards: [Card]
    /// Единственный источник правды — UserFBService (см. UserFBService.swift).
    private var userPlan: AccessTier { userService.userPlan }
    @State private var isShowingAddCard  = false
    @State private var editingCard: Card? = nil
    @State private var showPlans         = false
    @State private var statusFilter: CardStatusFilter = .all
    @State private var editMode:     EditMode = .inactive
    @State private var selectedCardIds: Set<UUID> = []

    private var isPaywalled: Bool { !userPlan.canAccess(cardSet.accessTier) }

    // MARK: Filtered content

    private var isInbox: Bool { cardSet.name == "Inbox" }

    /// Active + Learnt вместе, один плоский список — .deleted сюда не попадают.
    private var visibleCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && ($0.status == .active || $0.status == .learnt) }
    }

    /// Пилюли имеют смысл, только пока есть хоть одна Learnt-карточка — иначе "фильтровать"
    /// нечего (весь сет и так Active), пилюли не показываются вовсе.
    private var hasLearntCards: Bool {
        visibleCards.contains { $0.status == .learnt }
    }

    /// visibleCards, дополнительно суженные пилюлями All/Active/Learnt. Если пилюли скрыты
    /// (hasLearntCards == false), а statusFilter почему-то остался на .learnt (напр. Restore
    /// увёл последнюю Learnt-карточку, пока фильтр был на ней) — считаем как .all, чтобы
    /// список не показал пустоту незаметно для пользователя.
    private var filteredCards: [Card] {
        switch statusFilter {
        case .all:    return visibleCards
        case .active: return visibleCards.filter { $0.status == .active }
        case .learnt: return hasLearntCards ? visibleCards.filter { $0.status == .learnt } : visibleCards
        }
    }

    private var hasMetadata: Bool {
        !(cardSet.setDescription ?? "").isEmpty || !cardSet.isUserCreated
    }

    private var isAllSelected: Bool {
        !filteredCards.isEmpty && selectedCardIds.count == filteredCards.count
    }

    /// Среди выбранных — только Learnt, остальные восстанавливать нечего (Active уже активны).
    private var selectedLearntCards: [Card] {
        filteredCards.filter { selectedCardIds.contains($0.id) && $0.status == .learnt }
    }

    private func toggleSelectAll() {
        if isAllSelected {
            selectedCardIds = []
        } else {
            selectedCardIds = Set(filteredCards.map(\.id))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            metadataCard
            if hasLearntCards {
                filterPillsRow
            }
            List(selection: $selectedCardIds) {
                ForEach(filteredCards) { card in
                    cardRow(card)
                        .id(card.id)
                        .listRowBackground(Color.myColors.myBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                setStatus(.deleted, for: card)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            // Restore — только для Learnt; Active восстанавливать не из чего.
                            if card.status == .learnt {
                                Button {
                                    setStatus(.active, for: card)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.up")
                                }
                                .tint(Color.myColors.myBlue)
                            }
                        }
                }
            }
//            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .myShadow()
            .environment(\.editMode, $editMode)
            .onChange(of: statusFilter) { _, _ in selectedCardIds = [] }
            .overlay {
                if visibleCards.isEmpty {
                    emptyState
                } else if filteredCards.isEmpty {
                    filteredEmptyState
                }
            }
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .customBackButton("", isHidden: editMode == .active)
        .navigationTitle(cardSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editMode == .active {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isAllSelected ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }
                    .foregroundStyle(Color.myColors.myBlue)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if editMode == .active {
                        Button("Done") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                editMode = .inactive
                                selectedCardIds = []
                            }
                        }
                    } else {
                        if allowsEditing && !isInbox {
                            Button { isShowingAddCard = true } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        if !filteredCards.isEmpty {
                            Button("Edit") { editMode = .active }
                        }
                    }
                }
                .foregroundStyle(Color.myColors.myBlue)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode == .active {
                bulkActionBar
            }
        }
        .sheet(isPresented: $isShowingAddCard) {
            AddEditCardView(preselectedSetId: cardSet.id, appSyncStateService: appSyncStateService)
        }
        .sheet(item: $editingCard) { card in
            AddEditCardView(card: card, appSyncStateService: appSyncStateService)
        }
        .sheet(isPresented: $showPlans) {
            PlansView(authService: authService, userService: userService)
        }
    }

    // MARK: - Metadata Card (CEFR + expandable description)

    @ViewBuilder
    private var metadataCard: some View {
        if hasMetadata {
            let hasDesc = !(cardSet.setDescription ?? "").isEmpty
            let hasCEFR = !cardSet.isUserCreated

            VStack(alignment: .leading, spacing: (hasDesc && hasCEFR) ? 8 : 0) {
                if hasCEFR {
                    CEFRBadgeView(level: cardSet.cefrLevel)
                        .font(.caption.weight(.semibold))
                }

                if let desc = cardSet.setDescription, !desc.isEmpty {
                    ExpandableSection(
                        text:        desc,
                        font:        .subheadline,
                        lineSpacing: 2,
                        linesLimit:  3
                    )
                    .foregroundStyle(Color.myColors.mySecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Filter Pills

    /// All/Active/Learnt — по аналогии с filterPillsRow в DeletedCardsView; FilterPill —
    /// тот же переиспользуемый компонент (объявлен там, не private, — используется и здесь).
    private var filterPillsRow: some View {
        HStack(spacing: 8) {
            ForEach(CardStatusFilter.allCases, id: \.self) { filter in
                Button { statusFilter = filter } label: {
                    FilterPill(label: filter.label, isActive: statusFilter == filter)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Card Row

    private func cardRow(_ card: Card) -> some View {
        let paywalled = isInbox ? false : isPaywalled
        return CardRow(
            card: card,
            onEdit: (allowsEditing || isInbox) ? { editingCard = card } : nil,
            isPaywalled: paywalled,
            onUpgrade: paywalled ? { showPlans = true } : nil
        )
    }

    /// Меняет статус карточки (Delete/Restore из swipe action) без анимации List'а —
    /// смягчает гонку между анимированным сжатием списка и распознаванием swipe-жеста на
    /// соседней строке.
    private func setStatus(_ status: CardStatus, for card: Card) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            card.status = status
            context.saveWithErrorHandling()
        }
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        HStack {
            Button {
                restoreSelected()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.up")
                    Text("Restore")
                }
                .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selectedLearntCards.isEmpty ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myBlue)
            .disabled(selectedLearntCards.isEmpty)

            Spacer()

            if !selectedCardIds.isEmpty {
                Text("\(selectedCardIds.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }

            Spacer()

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selectedCardIds.isEmpty ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myRed)
            .disabled(selectedCardIds.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Bulk Actions

    private func restoreSelected() {
        for card in selectedLearntCards { card.status = .active }
        context.saveWithErrorHandling()
        selectedCardIds = []
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editMode = .inactive }
    }

    private func deleteSelected() {
        let cards = filteredCards.filter { selectedCardIds.contains($0.id) }
        for card in cards { card.status = .deleted }
        context.saveWithErrorHandling()
        selectedCardIds = []
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editMode = .inactive }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Text("No cards yet")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
                .multilineTextAlignment(.center)

            Text("Cards will be sent here from outside the App.")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    /// Показывается, когда сет не пуст, но текущий фильтр (Active/Learnt) не даёт совпадений —
    /// отличается от emptyState (сет пуст вообще), как filteredEmptyState в DeletedCardsView.
    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
            Text("No cards here")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text("Try a different filter")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - CardStatusFilter

private enum CardStatusFilter: CaseIterable {
    case all, active, learnt

    var label: String {
        switch self {
        case .all:    return "All"
        case .active: return "Active"
        case .learnt: return "Learnt"
        }
    }
}

// MARK: - CardRow

private struct CardRow: View {
    let card: Card
    var onEdit: (() -> Void)? = nil
    var isPaywalled: Bool = false
    var onUpgrade: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 2) {
                    Text(card.en)
                        .font(.headline)
                        .lineLimit(1)
                    if card.isNew {
                        Circle()
                            .fill(Color.myColors.myGreen)
                            .frame(width: 7, height: 7)
                            .padding(.top, 3)
                    }
                }
                if isPaywalled {
                    Button { onUpgrade?() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text("Upgrade your plan")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.myColors.myBlue.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(card.item)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onEdit, !isPaywalled {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myBlue)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
