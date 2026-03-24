import SwiftUI
import SwiftData

// MARK: - LibraryView
// Root of the Library tab: Piles + Collections → Sets → Cards (NavigationStack)

struct LibraryView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query(sort: \Pile.createdAt)       private var piles:       [Pile]
    @Query                              private var allCards:    [Card]
    @Query(sort: \CardSet.createdAt)    private var cardSets:    [CardSet]

    @State private var viewModel = LibraryViewModel()

    var body: some View {
        NavigationStack {
            List {
                pilesSection
                collectionsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .sheet(isPresented: $viewModel.isShowingAddCollection) {
                AddCollectionView()
            }
            .sheet(isPresented: $viewModel.isShowingPileBuilder, onDismiss: {
                viewModel.editingPile = nil
            }) {
                PileBuilderView(editingPile: viewModel.editingPile)
            }
            .overlay {
                if collections.isEmpty && piles.isEmpty { emptyState }
            }
        }
    }

    // MARK: - Piles Section

    private var pilesSection: some View {
        Section {
            ForEach(piles) { pile in
                PileRow(
                    pile: pile,
                    cardCount: activeCardCount(for: pile)
                )
                .contentShape(Rectangle())
                .onTapGesture { activatePile(pile) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        context.delete(pile)
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        viewModel.editingPile = pile
                        viewModel.isShowingPileBuilder = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        } header: {
            HStack {
                Text("Piles")
                Spacer()
                Button {
                    viewModel.editingPile = nil
                    viewModel.isShowingPileBuilder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        Section {
            ForEach(regularCollections) { collection in
                NavigationLink {
                    CollectionDetailView(collection: collection)
                } label: {
                    CollectionRow(collection: collection)
                }
            }
            .onDelete { offsets in
                deleteCollections(at: offsets, from: regularCollections)
            }
        } header: {
            HStack {
                Text("Collections")
                Spacer()
                Button {
                    viewModel.isShowingAddCollection = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // Inbox first, then the rest sorted by creation date
    private var regularCollections: [Collection] {
        let inbox = collections.filter { $0.name == "Inbox" }
        let rest  = collections.filter { $0.name != "Inbox" }
        return inbox + rest
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No collections yet")
                .font(.title3.bold())
            Text("Tap + to create your first collection")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func activatePile(_ pile: Pile) {
        for p in piles { p.isActive = false }
        pile.isActive = true
        try? context.save()
    }

    private func deleteCollections(at offsets: IndexSet, from list: [Collection]) {
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }

    // MARK: - Helpers

    private func activeCardCount(for pile: Pile) -> Int {
        allCards.filter { pile.setIds.contains($0.setId) && $0.status == .active }.count
    }
}

// MARK: - PileRow

private struct PileRow: View {
    let pile:      Pile
    let cardCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Image(systemName: pile.isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(pile.isActive ? Color.accentColor : Color.secondary)
                .font(.title3)
                .animation(.spring(duration: 0.2), value: pile.isActive)

            VStack(alignment: .leading, spacing: 2) {
                Text(pile.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Image(systemName: shuffleIcon(pile.shuffleMethod))
                        .font(.caption2)
                    Text("\(cardCount) active cards")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func shuffleIcon(_ method: ShuffleMethod) -> String {
        switch method {
        case .random:      return "shuffle"
        case .sequential:  return "arrow.down"
        case .prioritized: return "flame"
        }
    }
}

// MARK: - CollectionRow

private struct CollectionRow: View {
    let collection: Collection

    var body: some View {
        Label(collection.name, systemImage: collection.icon ?? "folder")
    }
}
