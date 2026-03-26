import SwiftUI
import SwiftData

// MARK: - CardSetDetailView
// Third level: list of Cards inside a CardSet.

struct CardSetDetailView: View {

    @Environment(\.modelContext) private var context
    let cardSet: CardSet

    @Query(sort: \Card.createdAt) private var allCards: [Card]
    @State private var isShowingAddCard = false
    @State private var cardToErase: Card?

    // MARK: Filtered sections

    private var activeCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status == .active }
    }

    private var learntCards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status == .learnt }
    }

    var body: some View {
        List {
            if !activeCards.isEmpty {
                Section(learntCards.isEmpty ? "" : "ACTIVE") {
                    ForEach(activeCards) { card in
                        CardRow(card: card)
                            .listRowBackground(Color.myColors.myBackground)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    card.status = .deleted
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            if !learntCards.isEmpty {
                Section("LEARNT") {
                    ForEach(learntCards) { card in
                        CardRow(card: card)
                            .listRowBackground(Color.myColors.myBackground)
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
                                    Label("Restore", systemImage: "arrow.uturn.left")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
        .myShadow()
        .scrollContentBackground(.hidden)
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle(cardSet.name)
        .navigationBarTitleDisplayMode(.inline)
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
            if activeCards.isEmpty && learntCards.isEmpty { emptyState }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(Color.myColors.mySecondary)
            Text("No cards yet")
                .font(.title3.bold())
            Text("Tap + to add your first card")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - CardRow

private struct CardRow: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.en)
                .font(.body)
            Text(card.item)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
