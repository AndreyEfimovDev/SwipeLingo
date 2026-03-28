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

    @State private var isShowingAddCollection = false
    @State private var isShowingPileBuilder   = false
    /// Non-nil when editing an existing pile; nil when creating a new one.
    @State private var editingPile: Pile?
    @State private var collectionToDelete: Collection?

    private var deletedCardsCount: Int {
        allCards.filter { $0.status == .deleted }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pilesSection
                    collectionsSection
                    managingSection
                }
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingAddCollection) {
                AddCollectionView()
            }
            .sheet(isPresented: $isShowingPileBuilder, onDismiss: {
                editingPile = nil
            }) {
                PileBuilderView(editingPile: editingPile)
            }
            .overlay {
                if collections.isEmpty && piles.isEmpty { emptyState }
            }
            .confirmationDialog(
                "Delete \"\(collectionToDelete?.name ?? "Collection")\"?",
                isPresented: Binding(
                    get: { collectionToDelete != nil },
                    set: { if !$0 { collectionToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    if let col = collectionToDelete {
                        deleteCollectionWithCards(col)
                        collectionToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { collectionToDelete = nil }
            } message: {
                if let col = collectionToDelete {
                    let sets = cardSets.filter { $0.collectionId == col.id }
                    let count = allCards.filter { card in sets.contains { $0.id == card.setId } }.count
                    Text(count > 0
                        ? "\(count) card\(count == 1 ? "" : "s") will be moved to Deleted and can be restored later."
                        : "This empty collection will be permanently removed.")
                }
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
                    editingPile = nil
                    isShowingPileBuilder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
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
                                editingPile = pile
                                isShowingPileBuilder = true
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
                    isShowingAddCollection = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
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
                                    collectionToDelete = collection
                                } label: {
                                    Label("Delete Collection", systemImage: "trash")
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

    // MARK: - Managing Section

    private var managingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MANAGING CARD")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                deletedCards

                Divider().padding(.leading, 46)

                Label("Share Cards", systemImage: "square.and.arrow.up")
                    .labelStyle(.fixedIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Divider().padding(.leading, 46)

                Label("Backup Cards", systemImage: "arrow.clockwise.icloud")
                    .labelStyle(.fixedIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .foregroundStyle(Color.myColors.myAccent)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }
    
    @ViewBuilder
    private var deletedCards: some View {
        if deletedCardsCount > 0 {
            NavigationLink { DeletedCardsView() } label: {
                HStack {
                    Label("Deleted Cards", systemImage: "trash")
                        .labelStyle(.fixedIcon)
                        .foregroundStyle(Color.myColors.myAccent)
                    Spacer()
                    Text("\(deletedCardsCount)")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.mySecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

    }

    // Order: Inbox → My Sets → other user-created → developer collections (with CEFR)
    // Non-protected collections hidden when all their cards are soft-deleted
    private var regularCollections: [Collection] {
        let inbox    = collections.filter { $0.name == "Inbox" }
        let mySets   = collections.filter { $0.name == "My Sets" }
        let userRest = collections.filter {
            $0.isUserCreated && $0.name != "Inbox" && $0.name != "My Sets" && hasVisibleContent($0)
        }
        let devCols  = collections.filter { !$0.isUserCreated && hasVisibleContent($0) }
        return inbox + mySets + userRest + devCols
    }

    /// Коллекция видима если: нет сетов (только что создана), или хотя бы один сет имеет
    /// хотя бы одну не-удалённую карточку (или пустой сет — тоже видим).
    private func hasVisibleContent(_ collection: Collection) -> Bool {
        let setsInCollection = cardSets.filter { $0.collectionId == collection.id }
        if setsInCollection.isEmpty { return true }
        return setsInCollection.contains { set in
            let cards = allCards.filter { $0.setId == set.id }
            return cards.isEmpty || cards.contains { $0.status != .deleted }
        }
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

    private func deleteCollectionWithCards(_ collection: Collection) {
        let setsInCollection = cardSets.filter { $0.collectionId == collection.id }
        var hasSoftDeletedCards = false

        for set in setsInCollection {
            let cards = allCards.filter { $0.setId == set.id }
            if cards.isEmpty {
                context.delete(set)        // пустой сет — удаляем сразу
            } else {
                hasSoftDeletedCards = true
                cards.forEach { $0.status = .deleted }
                // сет остаётся в БД; удалится автоматически когда все карточки будут стёрты
            }
        }

        if !hasSoftDeletedCards {
            // коллекция была пустой — удаляем сразу
            context.delete(collection)
        }
        // иначе коллекция удалится автоматически вместе с последним сетом
        try? context.save()
    }

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
                .labelStyle(.fixedIcon)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.myBlue)
        }
    }
}
