import SwiftUI
import SwiftData

// MARK: - CollectionDetailView
// Second level: list of CardSets inside a Collection.

struct CollectionDetailView: View {

    @Environment(\.modelContext) private var context
    let collection: Collection
    // NB: экран нигде не сконструирован (мёртвый код — см. CLAUDE.md), но должен
    // компилироваться. authService/userService только для PlansView внутри CardSetDetailView.
    let authService: AuthService
    let userService: UserService

    // Та же бизнес-логика Library, что и в LibraryView — этот экран на уровень глубже
    // в том же графе Collection/CardSet/Pile, поэтому переиспользует ViewModel вместо
    // повторного дублирования toggleSet/createNewPile/deleteSetWithCards.
    @State private var vm = LibraryViewModel()

    @Query(sort: \CardSet.createdAt)  private var allSets:  [CardSet]
    @Query(sort: \Card.createdAt)     private var allCards: [Card]
    @Query(sort: \Pile.createdAt)     private var allPiles: [Pile]

    @State private var isShowingAddSet = false
    @State private var setToDelete:    CardSet?
    @State private var setForNewPile:  CardSet?
    @State private var newPileName  = ""
    @State private var selectedCEFRLevel: CEFRLevel? = nil
    @State private var searchText = ""

    // Сет видим если: нет карточек (только что создан), или есть хотя бы одна не-удалённая карточка
    private var cardSets: [CardSet] {
        allSets
            .filter { $0.collectionId == collection.id }
            .filter { set in
                let cards = allCards.filter { $0.setId == set.id }
                return cards.isEmpty || cards.contains { $0.status != .deleted }
            }
    }

    private var filteredCardSets: [CardSet] {
        var result = cardSets
        if let level = selectedCEFRLevel {
            result = result.filter { $0.cefrLevel == level }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    /// CEFR levels present across sets in this collection (non-user-created only).
    private var availableCEFRLevels: [CEFRLevel] {
        guard !collection.isUserCreated else { return [] }
        let levels = Set(cardSets.map { $0.cefrLevel })
        return CEFRLevel.allCases.filter { levels.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if availableCEFRLevels.count > 1 {
                cefrFilterRow
                    .background(Color.myColors.myBackground)
            }
            searchBar
                .background(Color.myColors.myBackground)
            ScrollView {
                VStack(spacing: 16) {
                    if !filteredCardSets.isEmpty {
                        setsSection
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .customBackButton("Library")
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingAddSet = true } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(Color.myColors.myBlue)
            }
        }
        .sheet(isPresented: $isShowingAddSet) {
            AddCardSetView(collectionId: collection.id)
        }
        .alert("New Pile", isPresented: Binding(
            get: { setForNewPile != nil },
            set: { if !$0 { setForNewPile = nil; newPileName = "" } }
        )) {
            TextField("Pile name", text: $newPileName)
            Button("Create") {
                if let set = setForNewPile {
                    vm.createNewPile(named: newPileName, with: set, context: context)
                }
                setForNewPile = nil
                newPileName   = ""
            }
            Button("Cancel", role: .cancel) {
                setForNewPile = nil
                newPileName   = ""
            }
        } message: {
            if let set = setForNewPile {
                Text("\"\(set.name)\" will be added to the new pile.")
            }
        }
        .overlay {
            if cardSets.isEmpty {
                emptyState
            } else if filteredCardSets.isEmpty && !searchText.isEmpty {
                SearchEmptyState(query: searchText)
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
    }

    // MARK: - Filter Bar

    private var cefrFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { selectedCEFRLevel = nil } label: {
                    FilterPill(label: "All", isActive: selectedCEFRLevel == nil)
                }
                .buttonStyle(.plain)

                ForEach(availableCEFRLevels, id: \.self) { level in
                    Button {
                        selectedCEFRLevel = selectedCEFRLevel == level ? nil : level
                    } label: {
                        FilterPill(label: level.displayCode, isActive: selectedCEFRLevel == level)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }

    private var searchBar: some View {
        SearchBar(text: $searchText, prompt: "Search sets")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    // MARK: - Sets Section

    private var setsSection: some View {
        VStack(spacing: 0) {
            ForEach(filteredCardSets) { cardSet in
                NavigationLink {
                    CardSetDetailView(cardSet: cardSet, allowsEditing: collection.isUserCreated, backTitle: collection.name,
                                       authService: authService, userService: userService)
                } label: {
                    HStack {
                        let count = vm.cardCount(forSet: cardSet, allCards: allCards)
                        HStack(alignment: .top, spacing: 2) {
                            HStack(spacing: 0) {
                                Text(cardSet.name)
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
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Menu {
                        ForEach(allPiles) { pile in
                            let inPile = pile.setIds.contains(cardSet.id)
                            Button {
                                vm.toggleSet(cardSet, in: pile, context: context)
                            } label: {
                                Label(
                                    pile.name,
                                    systemImage: inPile ? "checkmark.circle" : "circle"
                                )
                            }
                        }
                        Divider()
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
                if cardSet.id != filteredCardSets.last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 42))
            Text("No sets yet")
                .font(.title3.bold())
            Text("Tap + to add a set")
                .font(.subheadline)
        }
    }
}
