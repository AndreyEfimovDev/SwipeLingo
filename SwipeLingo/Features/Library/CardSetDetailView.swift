import SwiftUI
import SwiftData

// MARK: - CardSetDetailView
// Third level: list of Cards inside a CardSet.

struct CardSetDetailView: View {

    @Environment(\.modelContext) private var context
    let cardSet: CardSet

    @Query(sort: \Card.createdAt) private var allCards: [Card]
    @State private var isShowingAddCard = false

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
                if !activeCards.isEmpty || learntCards.isEmpty {
                    cardSection(
                        title: learntCards.isEmpty ? nil : "ACTIVE",
                        cards: activeCards,
                        isLearnt: false
                    )
                }
                if !learntCards.isEmpty {
                    cardSection(
                        title: "LEARNT",
                        cards: learntCards,
                        isLearnt: true
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
            if activeCards.isEmpty && learntCards.isEmpty { emptyState }
        }
    }

    // MARK: - Card Section

    @ViewBuilder
    private func cardSection(title: String?, cards: [Card], isLearnt: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 0) {
                ForEach(cards) { card in
                    CardRow(card: card)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contextMenu {
                            if isLearnt {
                                Button {
                                    card.status = .active
                                    try? context.save()
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.left")
                                }
                            }
                            Button(role: .destructive) {
                                card.status = .deleted
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    if card.id != cards.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty State

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
    }
}
