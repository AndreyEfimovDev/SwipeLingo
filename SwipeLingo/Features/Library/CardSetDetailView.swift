import SwiftUI
import SwiftData

// MARK: - CardSetDetailView
// Third level: list of Cards inside a CardSet.

struct CardSetDetailView: View {

    @Environment(\.modelContext) private var context
    let cardSet: CardSet

    @Query(sort: \Card.createdAt) private var allCards: [Card]
    @State private var isShowingAddCard = false

    private var cards: [Card] {
        allCards.filter { $0.setId == cardSet.id && $0.status != .deleted }
    }

    var body: some View {
        List {
            ForEach(cards) { card in
                CardRow(card: card)
            }
            .onDelete { offsets in
                softDeleteCards(at: offsets)
            }
        }
        .navigationTitle(cardSet.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingAddCard = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddCard) {
            AddCardView(preselectedSetId: cardSet.id)
        }
        .overlay {
            if cards.isEmpty { emptyState }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No cards yet")
                .font(.title3.bold())
            Text("Tap + to add your first card")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func softDeleteCards(at offsets: IndexSet) {
        let list = cards
        for index in offsets {
            list[index].status = .deleted
        }
        try? context.save()
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
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
