import SwiftUI
import SwiftData

// MARK: - LibraryView
// Root of the Library tab: Piles + Collections → Sets → Cards (NavigationStack)

struct LibraryView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    /// Передаются из composition root через AppView — не через .environment().
    private let appViewModel: AppViewModel
    private let authService:  AuthFBService
    private let userService:  FBUserService

    init(appViewModel: AppViewModel, authService: AuthFBService, userService: FBUserService) {
        self.appViewModel = appViewModel
        self.authService = authService
        self.userService = userService
    }

    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query(sort: \Pile.createdAt)       private var piles:       [Pile]
    @Query                              private var allCards:    [Card]
    @Query(sort: \CardSet.createdAt)    private var cardSets:    [CardSet]

    @AppStorage(Constants.StorageKey.nativeLanguage) private var nativeLangRaw: String = ""
    @Query private var profiles: [UserProfile]
    @State private var vm = LibraryViewModel()

    @State private var isShowingAddCollection = false
    @State private var pileSheet:             PileSheet?
    @State private var collectionToDelete:    Collection?
    @State private var showAddSetSheet     = false
    @State private var addSetCollectionId: UUID  = UUID()   // set before showAddSetSheet = true
    @State private var setToDelete:           CardSet?
    @State private var setForNewPile:         CardSet?
    @State private var newPileName            = ""
    @State private var showAllPiles           = false

    private var userLevel: CEFRLevel { profiles.first?.cefrLevel ?? .c2 }

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
                        Task { await vm.syncContent(context: context, nativeLangRaw: nativeLangRaw, level: userLevel) }
                    } label: {
                        if vm.isSyncing {
                            ProgressView().tint(Color.myColors.myBlue)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.myColors.myBlue)
                        }
                    }
                    .disabled(vm.isSyncing)
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
                case .new:          PileBuilderView(editingPile: nil, appViewModel: appViewModel)
                case .edit(let p):  PileBuilderView(editingPile: p, appViewModel: appViewModel)
                }
            }
//            .overlay {
//                // Перекрываем контент во время синхронизации — SwiftData @Query обновляется
//                // после каждого context.insert(), что вызывает мигание пустых коллекций
//                // пока cleanup ещё не удалил их. Overlay скрывает промежуточные состояния.
//                if isSyncing {
//                    ZStack {
//                        Color.myColors.myBackground.ignoresSafeArea()
//                        ProgressView("Syncing…")
//                            .tint(Color.myColors.myBlue)
//                            .foregroundStyle(Color.myColors.myAccent)
//                    }
//                }
//            }
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
                        vm.deleteCollectionWithCards(col, cardSets: cardSets, allCards: allCards, context: context)
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
                        vm.deleteSetWithCards(set, allCards: allCards, context: context)
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
                    if let set = setForNewPile,
                       vm.createNewPile(named: newPileName, with: set, context: context) {
                        showAllPiles = true   // раскрыть список чтобы новый пайл был виден
                    }
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
                let showToggle   = piles.count > 1 || (piles.count == 1 && activePile == nil)

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
            Button { vm.activatePile(pile, among: piles, context: context) } label: {
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
                    Text("\(vm.activeCardCount(for: pile, allCards: allCards)) active cards")
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
                vm.deletePile(pile, context: context)
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
        let sets = vm.setsForCollection(collection, cardSets: cardSets, allCards: allCards, userLevel: userLevel)

        VStack(spacing: 0) {
            // Collection header
            HStack(spacing: 0) {
                Label(collection.name, systemImage: collection.icon ?? "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent)
                    .labelStyle(.fixedIcon)
                    .lineLimit(1)

                let count = vm.cardCount(for: collection, cardSets: cardSets, allCards: allCards)
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
                CardSetDetailView(cardSet: cardSet, backTitle: "Library",
                                   authService: authService, userService: userService)
            } else {
                CardSetDetailView(
                    cardSet: cardSet,
                    allowsEditing: collection.isUserCreated,
                    backTitle: collection.name,
                    authService: authService, userService: userService
                )
            }
        } label: {
            HStack {
                let count = vm.cardCount(forSet: cardSet, allCards: allCards)
                let newCards = vm.newCount(forSet: cardSet, allCards: allCards)
                HStack(alignment: .top, spacing: 2) {
                    HStack(alignment: .top, spacing: 1) {
                        Group {
                            if count > 0 {
                                Text(cardSet.name)
                                + Text(" (\(count))")
                                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                            } else {
                                Text(cardSet.name)
                            }
                        }
                        .font(.body)
                        if newCards > 0 {
                            Circle()
                                .fill(Color.myColors.myGreen)
                                .frame(width: 7, height: 7)
                                .padding(.top, 2)
                        }
                    }
                    if !collection.isUserCreated {
                        AccessTierBadge(tier: cardSet.accessTier)
                            .offset(y: -4)
                    }
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
                        vm.toggleSet(cardSet, in: pile, context: context)
                    } label: {
                        Label(pile.name, systemImage: inPile ? "checkmark.circle" : "circle")
                    }
                    .disabled(inPile)
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

            Button(role: .destructive) {
                setToDelete = cardSet
            } label: {
                Label("Delete Set", systemImage: "trash")
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
        let deletedCount = vm.deletedCardsCount(allCards: allCards)
        if deletedCount > 0 {
            NavigationLink { DeletedCardsView() } label: {
                HStack {
                    Label {
                        HStack(spacing: 0) {
                            Text("Deleted Cards")
                            Text(" (\(deletedCount))")
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
        vm.myCollections(from: collections, cardSets: cardSets, allCards: allCards)
    }

    // Curated (Firestore) collections — показываем только если есть хотя бы один сет.
    // Скрываем пустые: они появляются кратковременно пока sync ещё не выполнил cleanup,
    // и могут оставаться если у пользователя нет контента на его уровне CEFR.
    private var curatedCollections: [Collection] {
        vm.curatedCollections(from: collections, cardSets: cardSets, allCards: allCards, userLevel: userLevel)
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

