import SwiftUI
import SwiftData

// MARK: - DeletedCardsView

struct DeletedCardsView: View {
    
    @Environment(\.modelContext)        private var context
    @Environment(\.verticalSizeClass)   private var verticalSizeClass
    @Query(sort: \Card.createdAt)       private var allCards:       [Card]
    @Query(sort: \CardSet.createdAt)    private var allCardSets:    [CardSet]
    @Query(sort: \Collection.createdAt) private var allCollections: [Collection]
    
    @State private var selectedCollectionId:     UUID?     = nil
    @State private var selectedSetId:            UUID?     = nil
    @State private var editMode:                 EditMode  = .inactive
    @State private var selectedCardIds:          Set<UUID> = []
    @State private var cardToErase:              Card?     = nil
    @State private var showEraseSelectedConfirm: Bool      = false
    @State private var searchText:               String    = ""
    @State private var isHeaderVisible:          Bool      = true
    @State private var showOnTopButton:          Bool      = false
    
    /// Scroll-aware behaviour kicks in only when there are enough cards to scroll.
    private let scrollAwareThreshold = 11
    
    // MARK: - Computed
    
    private var deletedCards: [Card] {
        allCards.filter { $0.status == .deleted }
    }
    
    private var filteredCards: [Card] {
        var cards = deletedCards
        if let colId = selectedCollectionId {
            let setIds = Set(allCardSets.filter { $0.collectionId == colId }.map { $0.id })
            cards = cards.filter { setIds.contains($0.setId) }
        }
        if let setId = selectedSetId {
            cards = cards.filter { $0.setId == setId }
        }
        return cards.filtered(by: searchText)
    }
    
    /// Collections that have at least one deleted card
    private var availableCollections: [Collection] {
        let deletedSetIds = Set(deletedCards.map { $0.setId })
        let collectionIds = Set(allCardSets.filter { deletedSetIds.contains($0.id) }.map { $0.collectionId })
        return allCollections.filter { collectionIds.contains($0.id) }
    }
    
    /// Sets that have at least one deleted card; restricted by selected collection if active
    private var availableSets: [CardSet] {
        let deletedSetIds = Set(deletedCards.map { $0.setId })
        var sets = allCardSets.filter { deletedSetIds.contains($0.id) }
        if let colId = selectedCollectionId {
            sets = sets.filter { $0.collectionId == colId }
        }
        return sets
    }
    
    private var isFiltered: Bool { selectedCollectionId != nil || selectedSetId != nil }
    
    private var isAllSelected: Bool {
        !filteredCards.isEmpty && selectedCardIds.count == filteredCards.count
    }
    
    private func toggleSelectAll() {
        if isAllSelected {
            selectedCardIds = []
        } else {
            selectedCardIds = Set(filteredCards.map { $0.id })
        }
    }
    
    private var isLandscape: Bool { verticalSizeClass == .compact }
    
    /// Header is only relevant when there are enough cards to warrant filtering/searching.
    private var headerRelevant: Bool {
        deletedCards.count >= scrollAwareThreshold
    }
    
    /// Force-show when search is active or in edit mode; otherwise follow scroll state.
    private var showHeader: Bool {
        guard headerRelevant else { return false }
        return isHeaderVisible || !searchText.isEmpty || editMode == .active
    }
    
    private var headerLayout: AnyLayout {
        isLandscape
        ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        headerLayout {
            filterPillsRow
                .padding(.leading, 16)
                .padding(.trailing, isLandscape ? 0 : 16)
            SearchBar(text: $searchText, prompt: "Search words")
                .padding(.leading, isLandscape ? 0 : 16)
                .padding(.trailing, 16)
                .padding(.top, isLandscape ? 0 : 8)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .background { Color.myColors.myBackground }
        .frame(maxHeight: showHeader ? nil : 0, alignment: isLandscape ? .center : .top)
        .clipped()
        .animation(.easeInOut(duration: 0.22), value: showHeader)  // frame collapse
        .opacity(showHeader ? 1 : 0)
        .animation(.easeInOut(duration: 0.38), value: showHeader)  // opacity — softer and longer
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .bottom) {
                List(selection: $selectedCardIds) {
                    ForEach(filteredCards) { card in
                        let cardSet        = allCardSets.first(where: { $0.id == card.setId })
                        let setName        = cardSet?.name
                        let collectionName = cardSet.flatMap { set in
                            allCollections.first(where: { $0.id == set.collectionId })?.name
                        }
                        DeletedCardRow(card: card, setName: setName, collectionName: collectionName)
                            .id(card.id)
                            .listRowBackground(Color.myColors.myBackground)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    cardToErase = card
                                } label: {
                                    Label("Erase Forever", systemImage: "trash")
                                }
                                Button {
                                    restoreCard(card)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.left")
                                }
                                .tint(Color.myColors.myGreen)
                            }
                    }
                }
                .myShadow()
                .contentMargins(.top, 16, for: .scrollContent)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !deletedCards.isEmpty { headerView }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
                .onChange(of: selectedCollectionId) { _, _ in selectedCardIds = [] }
                .onChange(of: selectedSetId)        { _, _ in selectedCardIds = [] }
                .onScrollGeometryChange(for: ScrollInfo.self) { geo in
                    ScrollInfo(
                        offsetY:       geo.contentOffset.y,
                        contentHeight: geo.contentSize.height,
                        visibleHeight: geo.visibleRect.height
                    )
                } action: { old, new in
                    let maxOffset = new.contentHeight - new.visibleHeight

                    // OnTopButton always works, regardless of filters and searches.
                    let shouldShowOnTop = new.offsetY > 300
                    if showOnTopButton != shouldShowOnTop { showOnTopButton = shouldShowOnTop }

                    // Hide/show header - only if there is no search and there are enough cards
                    guard headerRelevant, searchText.isEmpty else { return }
                    // Ignore bounce at the bottom: overscroll snaps back and looks like
                    // a rapid upward scroll, which would incorrectly show the header.
                    guard new.offsetY < maxOffset - 6 else { return }
                    if new.offsetY < 10 {
                        isHeaderVisible = true          // at the top - always show
                    } else if new.offsetY > old.offsetY + 11 {
                        isHeaderVisible = false         // scroll up (deep) → hide
                    } else if new.offsetY < old.offsetY - 11 {
                        isHeaderVisible = true          // scroll down (back to top) → show
                    }
                }
                OnTopButton(isVisible: showOnTopButton) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        scrollProxy.scrollTo(filteredCards.first?.id, anchor: .top)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showOnTopButton)
                .padding(.bottom, 16)
            }
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .navigationTitle("Deleted Cards")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editMode == .active)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !deletedCards.isEmpty {
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if editMode == .active {
                                editMode = .inactive
                                selectedCardIds = []
                            } else {
                                editMode = .active
                            }
                        }
                    }
                    .foregroundStyle(Color.myColors.myBlue)
                    .disabled(deletedCards.isEmpty)
                }
            }
            if editMode == .active {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isAllSelected ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }
                    .foregroundStyle(Color.myColors.myBlue)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode == .active {
                bulkActionBar
            }
        }
        .overlay {
            if deletedCards.isEmpty {
                emptyState
            } else if filteredCards.isEmpty {
                filteredEmptyState
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
                    cleanupAfterErase(erasingIds: [card.id])
                    context.delete(card)
                    context.saveWithErrorHandling()
                    cardToErase = nil
                }
            }
            Button("Cancel", role: .cancel) { cardToErase = nil }
        } message: {
            if let card = cardToErase {
                Text("\"\(card.en)\" will be permanently deleted and cannot be recovered.")
            }
        }
        .confirmationDialog(
            "Erase \(selectedCardIds.count) card\(selectedCardIds.count == 1 ? "" : "s") forever?",
            isPresented: $showEraseSelectedConfirm,
            titleVisibility: .visible
        ) {
            Button("Erase Forever", role: .destructive) { eraseSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("These cards will be permanently deleted and cannot be recovered.")
        }
    }
    
    // MARK: - Filter Pills
    
    private var filterPillsRow: some View {
        HStack(spacing: 8) {
            // All
            Button {
                selectedCollectionId = nil
                selectedSetId = nil
            } label: {
                FilterPill(label: "All", isActive: !isFiltered)
            }
            .buttonStyle(.plain)
            .fixedSize()
            
            // Collection
            Menu {
                ForEach(availableCollections) { col in
                    Button {
                        if selectedCollectionId == col.id {
                            selectedCollectionId = nil
                        } else {
                            selectedCollectionId = col.id
                            if let setId = selectedSetId,
                               let set = allCardSets.first(where: { $0.id == setId }),
                               set.collectionId != col.id {
                                selectedSetId = nil
                            }
                        }
                    } label: {
                        HStack {
                            Text(col.name)
                            if selectedCollectionId == col.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if selectedCollectionId != nil {
                    Divider()
                    Button("Clear Filter") { selectedCollectionId = nil }
                }
            } label: {
                FilterPill(
                    label: selectedCollectionId
                        .flatMap { id in allCollections.first(where: { $0.id == id })?.name }
                    ?? "Collection",
                    isActive: selectedCollectionId != nil,
                    showChevron: true
                )
            }
            .fixedSize()
            .opacity(availableCollections.isEmpty ? 0.45 : 1)
            .disabled(availableCollections.isEmpty)
            
            // Set
            Menu {
                if selectedCollectionId == nil && availableCollections.count > 1 {
                    ForEach(availableCollections) { col in
                        let setsForCol = availableSets.filter { $0.collectionId == col.id }
                        if !setsForCol.isEmpty {
                            Section(col.name) {
                                ForEach(setsForCol) { set in setMenuButton(set) }
                            }
                        }
                    }
                } else {
                    ForEach(availableSets) { set in setMenuButton(set) }
                }
                if selectedSetId != nil {
                    Divider()
                    Button("Clear Filter") { selectedSetId = nil }
                }
            } label: {
                FilterPill(
                    label: selectedSetId
                        .flatMap { id in allCardSets.first(where: { $0.id == id })?.name }
                    ?? "Set",
                    isActive: selectedSetId != nil,
                    showChevron: true
                )
            }
            .fixedSize()
            .opacity(availableSets.isEmpty ? 0.45 : 1)
            .disabled(availableSets.isEmpty)
            
            if !isLandscape { Spacer(minLength: 0) }
        }
    }
    
    @ViewBuilder
    private func setMenuButton(_ set: CardSet) -> some View {
        Button {
            if selectedSetId == set.id {
                selectedSetId = nil
            } else {
                selectedSetId = set.id
                // Auto-fill Collection if not already selected
                if selectedCollectionId == nil {
                    selectedCollectionId = set.collectionId
                }
            }
        } label: {
            HStack {
                Text(set.name)
                if selectedSetId == set.id { Image(systemName: "checkmark") }
            }
        }
    }
    
    // MARK: - Bulk Action Bar
    
    private var bulkActionBar: some View {
        HStack {
            Button {
                restoreSelected()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.left")
                    Text("Restore")
                }
                .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selectedCardIds.isEmpty ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myGreen)
            .disabled(selectedCardIds.isEmpty)
            
            Spacer()
            
            if !selectedCardIds.isEmpty {
                Text("\(selectedCardIds.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
            
            Spacer()
            
            Button {
                showEraseSelectedConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(selectedCardIds.isEmpty ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myRed)
            .disabled(selectedCardIds.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }
    
    // MARK: - Empty States
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            Text("No deleted cards")
                .font(.title3.bold())
                .foregroundStyle(Color.myColors.myAccent)
            Text("Cards you delete will appear here")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
        }
    }
    
    private var filteredEmptyState: some View {
        Group {
            if !searchText.isEmpty {
                SearchEmptyState(query: searchText)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    Text("No cards here")
                        .font(.title3.bold())
                        .foregroundStyle(Color.myColors.myAccent)
                    Text("Try a different filter")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func restoreCard(_ card: Card) {
        card.status = .active
        context.saveWithErrorHandling()
    }
    
    private func restoreSelected() {
        filteredCards
            .filter { selectedCardIds.contains($0.id) }
            .forEach { restoreCard($0) }
        selectedCardIds = []
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editMode = .inactive }
    }
    
    private func eraseSelected() {
        let toErase = filteredCards.filter { selectedCardIds.contains($0.id) }
        let ids = Set(toErase.map { $0.id })
        cleanupAfterErase(erasingIds: ids)
        toErase.forEach { context.delete($0) }
        context.saveWithErrorHandling()
        selectedCardIds = []
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { editMode = .inactive }
    }
    
    /// Deletes sets and collections that have no cards remaining after erasing.
    /// Call BEFORE context.delete so that @Query still contains the cards being erased.
    private func cleanupAfterErase(erasingIds: Set<UUID>) {
        let affectedSetIds = Set(allCards.filter { erasingIds.contains($0.id) }.map { $0.setId })
        
        for setId in affectedSetIds {
            // Cards in the set that will remain after erasing
            let remaining = allCards.filter { $0.setId == setId && !erasingIds.contains($0.id) }
            guard remaining.isEmpty,
                  let set = allCardSets.first(where: { $0.id == setId }),
                  let collection = allCollections.first(where: { $0.id == set.collectionId }),
                  collection.name != "Inbox" else { continue }  // Inbox set никогда не удаляем
            
            let collectionId = set.collectionId
            context.delete(set)
            
            // check if there are any other sets left in the collection.
            let remainingSets = allCardSets.filter { $0.collectionId == collectionId && $0.id != setId }
            guard remainingSets.isEmpty,
                  collection.name != "My Sets" else { continue }  // My Sets never deleted
            context.delete(collection)
        }
    }
}

// MARK: - ScrollInfo

private struct ScrollInfo: Equatable {
    let offsetY:       CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat
}

// MARK: - FilterPill

struct FilterPill: View {
    let label:        String
    let isActive:     Bool
    var showChevron:  Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .leading)
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(isActive ? Color.myColors.buttonTextAccent : Color.myColors.myBlue)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            if isActive {
                Capsule().fill(Color.myColors.myBlue)
            } else {
                Capsule().strokeBorder(Color.myColors.myBlue, lineWidth: 1.5)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive)
    }
}

// MARK: - DeletedCardRow

private struct DeletedCardRow: View {
    let card:           Card
    let setName:        String?
    let collectionName: String?
    
    private var locationLabel: String? {
        switch (collectionName, setName) {
        case (let col?, let set?): return "\(col) › \(set)"
        case (nil, let set?): return set
        case (let col?, nil): return col
        case (nil, nil): return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.en)
                .font(.headline)
                .foregroundStyle(Color.myColors.myAccent)
            Text(card.item)
                .font(.subheadline)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            if let locationLabel {
                Text(locationLabel)
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
            }
        }
        .padding(.vertical, 2)
    }
}
