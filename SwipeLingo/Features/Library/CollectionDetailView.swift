import SwiftUI
import SwiftData

// MARK: - CollectionDetailView
// Second level: list of CardSets inside a Collection.

struct CollectionDetailView: View {

    @Environment(\.modelContext) private var context
    let collection: Collection

    @Query(sort: \CardSet.createdAt) private var allSets: [CardSet]
    @State private var isShowingAddSet = false

    private var cardSets: [CardSet] {
        allSets.filter { $0.collectionId == collection.id }
    }

    var body: some View {
        List {
            ForEach(cardSets) { cardSet in
                NavigationLink {
                    CardSetDetailView(cardSet: cardSet)
                } label: {
                    CardSetRow(cardSet: cardSet, allCards: [])
                }
            }
            .onDelete { offsets in
                deleteCardSets(at: offsets)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingAddSet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddSet) {
            AddCardSetView(collectionId: collection.id)
        }
        .overlay {
            if cardSets.isEmpty { emptyState }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No sets yet")
                .font(.title3.bold())
            Text("Tap + to add a set")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteCardSets(at offsets: IndexSet) {
        let list = cardSets
        for index in offsets {
            context.delete(list[index])
        }
        try? context.save()
    }
}

// MARK: - CardSetRow

private struct CardSetRow: View {
    let cardSet: CardSet
    let allCards: [Card]   // injected for card count badge (future use)

    var body: some View {
        Text(cardSet.name)
    }
}
