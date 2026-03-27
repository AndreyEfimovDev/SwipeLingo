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
            ScrollView {
                VStack(spacing: 16) {
                    pilesSection
                    collectionsSection
                }
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PILES")
                    .font(.footnote.weight(.semibold))
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
            .foregroundStyle(Color.myColors.myAccent)
            .padding(.horizontal, 32)

            if piles.isEmpty {
                Text("No piles yet — tap + to create one")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.mySecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(piles) { pile in
                        PileRow(
                            pile: pile,
                            cardCount: activeCardCount(for: pile),
                            onActivate: { activatePile(pile) },
                            onEdit: {
                                viewModel.editingPile = pile
                                viewModel.isShowingPileBuilder = true
                            }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                context.delete(pile)
                                try? context.save()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        if pile.id != piles.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COLLECTIONS")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button {
                    viewModel.isShowingAddCollection = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 32)

            if regularCollections.isEmpty {
                Text("No collections yet — tap + to create one")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(regularCollections) { collection in
                        NavigationLink {
                            // Inbox skips CollectionDetailView and goes straight to its CardSet
                            if collection.name == "Inbox",
                               let inboxSet = cardSets.first(where: { $0.collectionId == collection.id }) {
                                CardSetDetailView(cardSet: inboxSet)
                            } else {
                                CollectionDetailView(collection: collection)
                            }
                        } label: {
                            CollectionRow(collection: collection)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            let isProtected = collection.name == "Inbox" || collection.name == "My Sets"
                            if !isProtected {
                                Button(role: .destructive) {
                                    context.delete(collection)
                                    try? context.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        if collection.id != regularCollections.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
            }
        }
    }

    // Order: Inbox → My Sets → other user-created → developer collections (with CEFR)
    private var regularCollections: [Collection] {
        let inbox    = collections.filter { $0.name == "Inbox" }
        let mySets   = collections.filter { $0.name == "My Sets" }
        let userRest = collections.filter { $0.isUserCreated && $0.name != "Inbox" && $0.name != "My Sets" }
        let devCols  = collections.filter { !$0.isUserCreated }
        return inbox + mySets + userRest + devCols
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(Color.myColors.mySecondary)
            Text("No collections yet")
                .font(.title3.bold())
            Text("Tap + to create your first collection")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
        }
    }

    // MARK: - Actions

    private func activatePile(_ pile: Pile) {
        for p in piles { p.isActive = false }
        pile.isActive = true
        try? context.save()
    }

    // MARK: - Helpers

    private func activeCardCount(for pile: Pile) -> Int {
        allCards.filter { pile.setIds.contains($0.setId) && $0.status == .active }.count
    }
}

// MARK: - PileRow

private struct PileRow: View {
    let pile:       Pile
    let cardCount:  Int
    let onActivate: () -> Void
    let onEdit:     () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onActivate) {
                Image(systemName: pile.isActive ? "checkmark.circle" : "circle")
                    .foregroundStyle(pile.isActive ? Color.myColors.myGreen : Color.myColors.mySecondary)
                    .font(.title3)
                    .animation(.spring(duration: 0.2), value: pile.isActive)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(pile.name)
                    .font(.body)
                HStack(spacing: 4) {
                    Image(systemName: shuffleIcon(pile.shuffleMethod))
                        .font(.caption2)
                    Text("\(cardCount) active cards")
                        .font(.caption)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
        HStack {
            Label(collection.name, systemImage: collection.icon ?? "folder")
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
    }
}
