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

    @Query(sort: \Card.createdAt) private var allCards: [Card]
    @State private var isShowingAddCard  = false
    @State private var isActiveExpanded  = true
    @State private var isLearntExpanded  = false

    // Fallback covers first render; updated by PreferenceKey after layout
    @State private var rowHeight: CGFloat = 68

    // MARK: Filtered sections

    private var activeCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status == .active }
    }

    private var learntCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status == .learnt }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // MARK: Active section
                if !activeCards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        collapsibleHeader(
                            title: "ACTIVE",
                            count: activeCards.count,
                            color: CardStatus.active.color,
                            isExpanded: $isActiveExpanded
                        )
                        .padding(.horizontal, 32)

                        if isActiveExpanded {
                            List {
                                ForEach(activeCards) { card in
                                    CardRow(card: card)
                                        .background(GeometryReader { geo in
                                            Color.clear.preference(
                                                key: CardRowHeightKey.self,
                                                value: geo.size.height
                                            )
                                        })
                                        .listRowBackground(Color.myColors.myBackground)
                                        .listRowInsets(EdgeInsets())
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                card.status = .deleted
                                                try? context.save()
                                            } label: {
                                                Label("Delete", systemImage: "trash")
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
                            .frame(height: CGFloat(activeCards.count) * rowHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .myShadow()
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // MARK: Learnt section
                if !learntCards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        collapsibleHeader(
                            title: "LEARNT",
                            count: learntCards.count,
                            color: CardStatus.learnt.color,
                            isExpanded: $isLearntExpanded
                        )
                        .padding(.horizontal, 32)

                        if isLearntExpanded {
                            List {
                                ForEach(learntCards) { card in
                                    CardRow(card: card)
                                        .background(GeometryReader { geo in
                                            Color.clear.preference(
                                                key: CardRowHeightKey.self,
                                                value: geo.size.height
                                            )
                                        })
                                        .listRowBackground(Color.myColors.myBackground)
                                        .listRowInsets(EdgeInsets())
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                card.status = .deleted
                                                try? context.save()
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            Button {
                                                card.status = .active
                                                try? context.save()
                                            } label: {
                                                Label("Restore", systemImage: "arrow.uturn.up")
                                            }
                                            .tint(Color.myColors.myBlue)
                                        }
                                }
                            }
                            .listStyle(.plain)
                            .scrollDisabled(true)
                            .scrollContentBackground(.hidden)
                            .onPreferenceChange(CardRowHeightKey.self) { value in
                                if value > 0 { rowHeight = value }
                            }
                            .frame(height: CGFloat(learntCards.count) * rowHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .myShadow()
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle(cardSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity)
        .toolbar {
            if cardSet.name != "Inbox" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingAddCard = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddCard) {
            AddCardView(preselectedSetId: cardSet.id)
        }
        .overlay {
            if activeCards.isEmpty && learntCards.isEmpty {
                emptyState
            }
        }
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
                    .foregroundStyle(Color.myColors.myAccent)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.en)
                .font(.headline)
            Text(card.item)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
