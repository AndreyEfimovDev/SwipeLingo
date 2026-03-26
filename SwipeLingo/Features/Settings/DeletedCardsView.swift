import SwiftUI
import SwiftData

// MARK: - DeletedCardsView

struct DeletedCardsView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Card.createdAt) private var allCards: [Card]
    @State private var cardToErase: Card?

    private var deletedCards: [Card] {
        allCards.filter { $0.status == .deleted }
    }

    var body: some View {
        List {
            ForEach(deletedCards) { card in
                DeletedCardRow(card: card)
                    .listRowBackground(Color.myColors.myBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            cardToErase = card
                        } label: {
                            Label("Erase Forever", systemImage: "trash")
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
        .myShadow()
        .scrollContentBackground(.hidden)
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Deleted Cards")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if deletedCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.myColors.mySecondary)
                    Text("No deleted cards")
                        .font(.title3.bold())
                    Text("Cards you delete will appear here")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.mySecondary)
                }
            }
        }
        .confirmationDialog(
            "Erase Forever?",
            isPresented: Binding(
                get: { cardToErase != nil },
                set: { if !$0 { cardToErase = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Erase Forever", role: .destructive) {
                if let card = cardToErase {
                    context.delete(card)
                    try? context.save()
                    cardToErase = nil
                }
            }
            Button("Cancel", role: .cancel) { cardToErase = nil }
        } message: {
            if let card = cardToErase {
                Text("\"\(card.en)\" will be permanently deleted and cannot be recovered.")
            }
        }
    }
}

// MARK: - DeletedCardRow

private struct DeletedCardRow: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.en)
                .font(.body)
            Text(card.item)
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
        }
        .padding(.vertical, 2)
    }
}
