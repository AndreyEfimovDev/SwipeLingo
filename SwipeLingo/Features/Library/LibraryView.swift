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
    @State private var pileSheet: PileSheet?
    @State private var collectionToDelete: Collection?
    @State private var showAllCurated = false
    @State private var showAllPiles   = false

    private let curatedPreviewCount = 3

    private var deletedCardsCount: Int {
        allCards.filter { $0.status == .deleted }.count
    }

    private func setCount(for collection: Collection) -> Int {
        cardSets.filter { $0.collectionId == collection.id }.count
    }

    private func cardCount(for collection: Collection) -> Int {
        let setIds = Set(cardSets.filter { $0.collectionId == collection.id }.map(\.id))
        return allCards.filter { setIds.contains($0.setId) && $0.status != .deleted }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pilesSection
                    myCollectionsSection
                    if !curatedCollections.isEmpty { curatedCollectionsSection }
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
            .sheet(item: $pileSheet) { mode in
                switch mode {
                case .new:          PileBuilderView(editingPile: nil)
                case .edit(let p):  PileBuilderView(editingPile: p)
                }
            }
            .overlay {
                if myCollections.isEmpty && piles.isEmpty { emptyState }
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
                Button { pileSheet = .new } label: {
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
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else {
                let activePile   = piles.first(where: { $0.isActive })
                let sortedPiles  = piles.sorted { $0.name.lowercased() < $1.name.lowercased() }
                let showToggle   = piles.count > 1

                VStack(spacing: 0) {
                    if showAllPiles {
                        ForEach(Array(sortedPiles.enumerated()), id: \.element.id) { idx, pile in
                            pileRow(pile)
                            if idx < sortedPiles.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    } else {
                        if let pile = activePile {
                            pileRow(pile)
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "circle")
                                    .font(.title3)
                                    .foregroundStyle(Color.myColors.myAccent.opacity(0.35))
                                Text("No active pile")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.myColors.myAccent.opacity(0.55))
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }

                    if showToggle {
                        Divider().padding(.leading, 44)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showAllPiles.toggle() }
                        } label: {
                            HStack {
                                Text(showAllPiles ? "Show less" : "All piles (\(piles.count))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.myColors.myBlue)
                                Spacer()
                                Image(systemName: showAllPiles ? "chevron.up" : "chevron.down")
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
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func pileRow(_ pile: Pile) -> some View {
        HStack(spacing: 10) {
            Button { activatePile(pile) } label: {
                Image(systemName: pile.isActive ? "checkmark.circle" : "circle")
                    .foregroundStyle(pile.isActive ? Color.myColors.myGreen : Color.myColors.myAccent.opacity(0.8))
                    .font(.title3)
                    .animation(.spring(duration: 0.2), value: pile.isActive)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 3) {
                Text(pile.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: pileShuffleIcon(pile.shuffleMethod))
                        .font(.caption2)
                    Text("\(activeCardCount(for: pile)) active cards")
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
                }
            }

            Spacer(minLength: 0)

            Button { pileSheet = .edit(pile) } label: {
                Image(systemName: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                context.delete(pile)
                context.saveWithErrorHandling()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func pileShuffleIcon(_ method: ShuffleMethod) -> String {
        switch method {
        case .random:      return "shuffle"
        case .sequential:  return "arrow.down"
        case .prioritized: return "flame"
        }
    }

    // MARK: - My Collections Section

    private var myCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MY COLLECTIONS")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Button { isShowingAddCollection = true } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                }
                .buttonStyle(.borderless)
            }
            .foregroundStyle(Color.myColors.myAccent)
            .padding(.horizontal, 32)

            if myCollections.isEmpty {
                Text("No collections yet — tap + to create one")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else {
                collectionList(myCollections)
            }
        }
    }

    // MARK: - Curated Collections Section

    private var curatedCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CURATED COLLECTIONS")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent)
                .padding(.horizontal, 32)

            let visible = showAllCurated ? curatedCollections : Array(curatedCollections.prefix(curatedPreviewCount))
            VStack(spacing: 0) {
                ForEach(visible) { collection in
                    collectionRow(collection, in: visible)
                }
                if curatedCollections.count > curatedPreviewCount {
                    Divider().padding(.leading, 52)
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showAllCurated.toggle() }
                    } label: {
                        HStack {
                            Text(showAllCurated ? "Show less" : "Show all (\(curatedCollections.count))")
                                .font(.subheadline)
                                .foregroundStyle(Color.myColors.myBlue)
                            Spacer()
                            Image(systemName: showAllCurated ? "chevron.up" : "chevron.down")
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
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Collection List Helpers

    @ViewBuilder
    private func collectionList(_ items: [Collection]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { collection in
                collectionRow(collection, in: items)
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func collectionRow(_ collection: Collection, in list: [Collection]) -> some View {
        NavigationLink {
            if collection.name == "Inbox",
               let inboxSet = cardSets.first(where: { $0.collectionId == collection.id }) {
                CardSetDetailView(cardSet: inboxSet)
            } else {
                CollectionDetailView(collection: collection)
            }
        } label: {
            CollectionRow(
                collection: collection,
                setCount:   setCount(for: collection),
                cardCount:  cardCount(for: collection)
            )
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
        if collection.id != list.last?.id {
            Divider().padding(.leading, 52)
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
                    Label {
                        HStack(spacing: 0) {
                            Text("Deleted Cards")
                            Text(" (\(deletedCardsCount))")
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                        }
                    } icon: {
                        Image(systemName: "trash")
                    }
                    .labelStyle(.fixedIcon)
                    .foregroundStyle(Color.myColors.myAccent)
                    Spacer()
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

    // Inbox + My Sets + other user-created collections
    private var myCollections: [Collection] {
        let inbox    = collections.filter { $0.name == "Inbox" }
        let mySets   = collections.filter { $0.name == "My Sets" }
        let userRest = collections.filter {
            $0.isUserCreated && $0.name != "Inbox" && $0.name != "My Sets" && hasVisibleContent($0)
        }
        return inbox + mySets + userRest
    }

    // Developer / imported / curated collections (non-user-created) — always visible
    private var curatedCollections: [Collection] {
        collections.filter { !$0.isUserCreated }
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
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            Text("No collections yet")
                .font(.title3.bold())
            Text("Tap + to create your first collection")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
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
        context.saveWithErrorHandling()
    }

    private func activatePile(_ pile: Pile) {
        for p in piles { p.isActive = false }
        pile.isActive = true
        context.saveWithErrorHandling()
    }

    // MARK: - Helpers

    private func activeCardCount(for pile: Pile) -> Int {
        allCards.filter { pile.setIds.contains($0.setId) && $0.status == .active }.count
    }
}

// MARK: - PileSheet

private enum PileSheet: Identifiable {
    case new
    case edit(Pile)

    var id: String {
        switch self {
        case .new:           return "new"
        case .edit(let p):   return p.id.uuidString
        }
    }
}

// MARK: - CollectionRow

private struct CollectionRow: View {
    let collection: Collection
    let setCount:   Int
    let cardCount:  Int

    /// Badge text: "(S/C)" for regular collections, "(C)" for Inbox; hidden when empty.
    private var badge: String? {
        guard cardCount > 0 || setCount > 0 else { return nil }
        if collection.name == "Inbox" { return "(\(cardCount))" }
        return "(\(setCount)/\(cardCount))"
    }

    var body: some View {
        HStack {
            Label(collection.name, systemImage: collection.icon ?? "folder")
                .labelStyle(.fixedIcon)
                .lineLimit(1)
            if let badge {
                Text(badge)
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.myColors.myBlue)
        }
    }
}
