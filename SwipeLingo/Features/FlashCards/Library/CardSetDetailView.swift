import SwiftUI
import SwiftData

// MARK: - CardSetDetailView
// Third level: list of Cards inside a CardSet.

// PreferenceKey: measures actual CardRow height after first layout
private struct CardRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CardSetDetailView: View {

    @Environment(\.modelContext) private var context
    let cardSet: CardSet
    var allowsEditing: Bool = false
    var backTitle: String = "Library"

    @Query(sort: \Card.createdAt) private var allCards: [Card]
    @State private var isActiveExpanded  = true
    @State private var isLearntExpanded  = false
    @State private var isShowingAddCard  = false
    @State private var editingCard: Card? = nil

    // Fallback covers first render; updated by PreferenceKey after layout
    @State private var rowHeight: CGFloat = 68

    // MARK: Filtered sections

    private var isInbox: Bool { cardSet.name == "Inbox" }

    private var activeCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status == .active }
    }

    private var learntCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status == .learnt }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // MARK: Metadata card (CEFR + description)
                metadataCard

                // MARK: Active section
                if !activeCards.isEmpty {
                    if isInbox {
                        // Inbox: flat list, no section header, pencil visible
                        cardList(cards: activeCards, showRestore: false)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            collapsibleHeader(
                                title: "ACTIVE",
                                count: activeCards.count,
                                color: CardStatus.active.color,
                                isExpanded: $isActiveExpanded
                            )
                            .padding(.horizontal, 32)

                            if isActiveExpanded {
                                cardList(cards: activeCards, showRestore: false)
                            }
                        }
                    }
                }

                // MARK: Learnt section (not shown for Inbox)
                if !isInbox && !learntCards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        collapsibleHeader(
                            title: "LEARNT",
                            count: learntCards.count,
                            color: CardStatus.learnt.color,
                            isExpanded: $isLearntExpanded
                        )
                        .padding(.horizontal, 32)

                        if isLearntExpanded {
                            cardList(cards: learntCards, showRestore: true)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .customBackButton(backTitle)
        .navigationTitle(cardSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity)
        .toolbar {
            if allowsEditing && !isInbox {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingAddCard = true } label: {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Color.myColors.myBlue)
                }
            }
        }
        .sheet(isPresented: $isShowingAddCard) {
            AddEditCardView(preselectedSetId: cardSet.id)
        }
        .sheet(item: $editingCard) { card in
            AddEditCardView(card: card)
        }
        .overlay {
            let hasCards = allCards.contains { $0.setId == cardSet.id && $0.status != .deleted }
            if !hasCards { emptyState }
        }
    }

    // MARK: - Metadata Card (CEFR + expandable description)

    @ViewBuilder
    private var metadataCard: some View {
        let hasDesc = !(cardSet.setDescription ?? "").isEmpty
        let hasCEFR = !cardSet.isUserCreated

        if hasDesc || hasCEFR {
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
        }
    }

    // MARK: - Card List

    private func cardList(cards: [Card], showRestore: Bool) -> some View {
        List {
            ForEach(cards) { card in
                CardRow(card: card, onEdit: (allowsEditing || isInbox) ? { editingCard = card } : nil)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: CardRowHeightKey.self, value: geo.size.height)
                    })
                    .listRowBackground(Color.myColors.myBackground)
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            card.status = .deleted
                            context.saveWithErrorHandling()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if showRestore {
                            Button {
                                card.status = .active
                                context.saveWithErrorHandling()
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.up")
                            }
                            .tint(Color.myColors.myBlue)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .onPreferenceChange(CardRowHeightKey.self) { value in
            if value > 0 { rowHeight = value }
        }
        .frame(height: CGFloat(cards.count) * rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: - Collapsible Header

    private func collapsibleHeader(
        title: String,
        count: Int,
        color: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("\(title)  (\(count))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myBlue)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
            Text("No cards yet")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text("Cards will be sent here from outside the App.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - CardRow

private struct CardRow: View {
    let card: Card
    var onEdit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.en)
                    .font(.headline)
                Text(card.item)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myBlue)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
