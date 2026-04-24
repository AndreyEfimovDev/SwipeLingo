import SwiftUI
import SwiftData

// MARK: - LibraryView
// Root of the Library tab: Piles + Collections → Sets → Cards (NavigationStack)

struct LibraryView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query(sort: \Pile.createdAt)       private var piles:       [Pile]
    @Query                              private var allCards:    [Card]
    @Query(sort: \CardSet.createdAt)    private var cardSets:    [CardSet]

    @AppStorage("nativeLanguage") private var nativeLangRaw: String = ""
    @Query private var profiles: [UserProfile]
    @State private var isSyncing = false

    @State private var isShowingAddCollection = false
    @State private var pileSheet:             PileSheet?
    @State private var collectionToDelete:    Collection?
    @State private var showAddSetSheet     = false
    @State private var addSetCollectionId: UUID  = UUID()   // set before showAddSetSheet = true
    @State private var setToDelete:           CardSet?
    @State private var setForNewPile:         CardSet?
    @State private var newPileName            = ""
    @State private var showAllPiles           = false

    private var deletedCardsCount: Int {
        allCards.filter { $0.status == .deleted }.count
    }

    private func syncContent() async {
        isSyncing = true
        let language = NativeLanguage(rawValue: nativeLangRaw) ?? .russian
        let level    = profiles.first?.cefrLevel ?? .c2
        await FirestoreImportService().syncFromFirestore(into: context, language: language, upToLevel: level)
        isSyncing = false
    }

    private func setCount(for collection: Collection) -> Int {
        cardSets.filter { $0.collectionId == collection.id }.count
    }

    private func cardCount(for collection: Collection) -> Int {
        let setIds = Set(cardSets.filter { $0.collectionId == collection.id }.map(\.id))
        return allCards.filter { setIds.contains($0.setId) && $0.status != .deleted }.count
    }

    private func cardCount(forSet cardSet: CardSet) -> Int {
        allCards.filter { $0.setId == cardSet.id && $0.status != .deleted }.count
    }

    private func setsForCollection(_ collection: Collection) -> [CardSet] {
        cardSets
            .filter { $0.collectionId == collection.id }
            .filter { set in
                let cards = allCards.filter { $0.setId == set.id }
                return cards.isEmpty || cards.contains { $0.status != .deleted }
            }
    }

    private func toggleSet(_ set: CardSet, in pile: Pile) {
        if pile.setIds.contains(set.id) {
            pile.setIds.removeAll { $0 == set.id }
        } else {
            pile.setIds.append(set.id)
        }
        context.saveWithErrorHandling()
    }

    private func deleteSetWithCards(_ cardSet: CardSet) {
        let cards = allCards.filter { $0.setId == cardSet.id }
        if cards.isEmpty {
            context.delete(cardSet)
        } else {
            cards.forEach { $0.status = .deleted }
        }
        context.saveWithErrorHandling()
    }

    private func createNewPile(named name: String, with set: CardSet) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let pile = Pile(name: trimmed, setIds: [set.id])
        context.insert(pile)
        context.saveWithErrorHandling()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pilesSection
                    setsSection
                    managingSection
                }
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await syncContent() }
                    } label: {
                        if isSyncing {
                            ProgressView().tint(Color.myColors.myBlue)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.myColors.myBlue)
                        }
                    }
                    .disabled(isSyncing)
                }
            }
            .sheet(isPresented: $isShowingAddCollection) {
                AddCollectionView()
            }
            .sheet(isPresented: $showAddSetSheet) {
                AddCardSetView(collectionId: addSetCollectionId)
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
            .confirmationDialog(
                "Delete \"\(setToDelete?.name ?? "Set")\"?",
                isPresented: Binding(
                    get: { setToDelete != nil },
                    set: { if !$0 { setToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Set", role: .destructive) {
                    if let set = setToDelete {
                        deleteSetWithCards(set)
                        setToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { setToDelete = nil }
            } message: {
                if let set = setToDelete {
                    let count = allCards.filter { $0.setId == set.id }.count
                    Text(count > 0
                        ? "\(count) card\(count == 1 ? "" : "s") will be moved to Deleted and can be restored later."
                        : "This empty set will be permanently removed.")
                }
            }
            .alert("New Pile", isPresented: Binding(
                get: { setForNewPile != nil },
                set: { if !$0 { setForNewPile = nil; newPileName = "" } }
            )) {
                TextField("Pile name", text: $newPileName)
                Button("Create") {
                    if let set = setForNewPile { createNewPile(named: newPileName, with: set) }
                    setForNewPile = nil; newPileName = ""
                }
                Button("Cancel", role: .cancel) { setForNewPile = nil; newPileName = "" }
            } message: {
                if let set = setForNewPile {
                    Text("\"\(set.name)\" will be added to the new pile.")
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

    // MARK: - Sets Section (flat list with collection groups)

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ─────────────────────────────────────────
            HStack {
                Text("MY SETS")
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

            // ── User collections ────────────────────────────────
            if myCollections.isEmpty {
                Text("No collections yet — tap + to create one")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .background(Color.myColors.myBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .myShadow()
                    .padding(.horizontal, 16)
            } else {
                ForEach(myCollections) { collection in
                    collectionSetBlock(collection)
                }
            }

            // ── Curated collections ─────────────────────────────
            if !curatedCollections.isEmpty {
                Text("CURATED")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)
                    .padding(.horizontal, 32)

                ForEach(curatedCollections) { collection in
                    collectionSetBlock(collection)
                }
            }
        }
    }

    // MARK: - Collection Set Block

    /// Одна карточка-блок: заголовок коллекции + список сетов под ним.
    @ViewBuilder
    private func collectionSetBlock(_ collection: Collection) -> some View {
        let sets = setsForCollection(collection)

        VStack(spacing: 0) {
            // Collection header
            HStack(spacing: 0) {
                Label(collection.name, systemImage: collection.icon ?? "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)
                    .labelStyle(.fixedIcon)
                    .lineLimit(1)

                let count = cardCount(for: collection)
                if count > 0 {
                    Text(" (\(count))")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                }

                Spacer(minLength: 8)

                if collection.isUserCreated {
                    Button {
                        addSetCollectionId = collection.id
                        showAddSetSheet    = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.myColors.myAccent.opacity(0.04))
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

            // Set rows
            if sets.isEmpty {
                Divider().padding(.leading, 16)
                Text("No sets yet")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach(sets) { set in
                    let isLast = set.id == sets.last?.id
                    Divider().padding(.leading, 16)
                    setRow(set, in: collection)
                    if !isLast { EmptyView() }
                }
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func setRow(_ cardSet: CardSet, in collection: Collection) -> some View {
        NavigationLink {
            if collection.name == "Inbox" {
                CardSetDetailView(cardSet: cardSet, backTitle: "Library")
            } else {
                CardSetDetailView(
                    cardSet: cardSet,
                    allowsEditing: collection.isUserCreated,
                    backTitle: collection.name
                )
            }
        } label: {
            HStack {
                let count = cardCount(forSet: cardSet)
                HStack(alignment: .top, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(cardSet.name)
                            .font(.body)
                        if count > 0 {
                            Text(" (\(count))")
                                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                        }
                    }
                    AccessTierBadge(tier: cardSet.accessTier)
                        .offset(y: -4)
                }
                Spacer()
                CEFRBadgeView(level: collection.isUserCreated ? nil : cardSet.cefrLevel)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.myColors.myBlue)
            }
            .foregroundStyle(Color.myColors.myAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu {
                ForEach(piles) { pile in
                    let inPile = pile.setIds.contains(cardSet.id)
                    Button {
                        toggleSet(cardSet, in: pile)
                    } label: {
                        Label(pile.name, systemImage: inPile ? "checkmark.circle" : "circle")
                    }
                }
                if !piles.isEmpty { Divider() }
                Button {
                    setForNewPile = cardSet
                } label: {
                    Label("New Pile…", systemImage: "plus")
                }
            } label: {
                Label("Add to Pile", systemImage: "square.stack.3d.up")
            }

            if collection.isUserCreated {
                Button(role: .destructive) {
                    setToDelete = cardSet
                } label: {
                    Label("Delete Set", systemImage: "trash")
                }
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

