import SwiftUI
import SwiftData

// MARK: - PileBuilderView
// Sheet for creating or editing a Pile.
// Save activates the pile and switches to the Study tab.

struct PileBuilderView: View {

    @Environment(\.modelContext)  private var context
    @Environment(\.dismiss)       private var dismiss
    @Environment(AppViewModel.self) private var appViewModel

    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query(sort: \CardSet.createdAt)    private var cardSets:    [CardSet]
    @Query(sort: \Card.createdAt)       private var allCards:    [Card]
    @Query                              private var allPiles:    [Pile]

    @State private var viewModel: PileBuilderViewModel
    @State private var isShowingDeleteConfirm = false
    @State private var searchText   = ""
    @State private var selectedLevel: String? = nil

    init(editingPile: Pile? = nil) {
        _viewModel = State(initialValue: PileBuilderViewModel(editingPile: editingPile))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nameSection
                    shuffleSection
                    setsSection
                }
                .padding(.vertical, 16)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                setsFilterHeader
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle(viewModel.editingPile == nil ? "New Pile" : "Edit Pile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarButtons }
            .confirmationDialog(
                "Delete \"\(viewModel.name)\"?",
                isPresented: $isShowingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Pile", role: .destructive) {
                    if let pile = viewModel.editingPile {
                        context.delete(pile)
                        context.saveWithErrorHandling()
                    }
                    dismiss()
                }

            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 32)

            TextField("e.g. Morning Session", text: $viewModel.name)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.myColors.myBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .myShadow()
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Shuffle Section

    private var shuffleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHUFFLE METHOD")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                shuffleRow(.random,      icon: "shuffle",    name: "Random")
                Divider().padding(.leading, 52)
                shuffleRow(.sequential,  icon: "arrow.down", name: "Sequential")
                Divider().padding(.leading, 52)
                shuffleRow(.prioritized, icon: "flame",      name: "Hardest first")
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)

            Text(shuffleFooter)
                .font(.footnote)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 32)
        }
    }

    private func shuffleRow(_ method: ShuffleMethod, icon: String, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            Text(name)
                .font(.body)
            Spacer()
            if viewModel.shuffleMethod == method {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.shuffleMethod = method }
    }

    // MARK: - Sets Filter Header

    private var setsFilterHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Level pills
            HStack(spacing: 8) {
                levelPill(nil, label: "All")
                ForEach(availableLevels, id: \.self) { level in
                    levelPill(level, label: level.uppercased())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Search bar
            SearchBar(text: $searchText, prompt: "Search sets")
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .background {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.myColors.myBackground.opacity(0.01), location: 0.0),
                    .init(color: Color.myColors.myBackground.opacity(0.95), location: 0.3),
                    .init(color: Color.myColors.myBackground,               location: 1.0)
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }

    @ViewBuilder
    private func levelPill(_ level: String?, label: String) -> some View {
        let isActive = selectedLevel == level
        Button { selectedLevel = level } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? Color.myColors.myBlue : Color.myColors.myBackground)
                .foregroundStyle(isActive ? Color.white : Color.myColors.myAccent)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    isActive ? Color.clear : Color.myColors.myAccent.opacity(0.25),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(.easeInOut(duration: 0.15), value: selectedLevel)
    }

    // MARK: - Sets Section

    private var setsSection: some View {
        ForEach(filteredSetGroups, id: \.collectionID) { group in
            VStack(alignment: .leading, spacing: 6) {
                Text(group.collectionName.uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                    .padding(.horizontal, 32)

                VStack(spacing: 0) {
                    ForEach(group.sets) { set in
                        SetToggleRow(
                            name: set.name,
                            level: group.isUserCreated ? nil : set.cefrLevel,
                            cardCount: activeCardCount(for: set.id),
                            isSelected: viewModel.selectedSetIds.contains(set.id)
                        ) {
                            viewModel.toggleSet(set.id)
                        }
                        if set.id != group.sets.last?.id {
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(Color.myColors.myRed)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                viewModel.saveAndActivate(context: context, allPiles: allPiles)
                appViewModel.selectedTab = .study
                dismiss()
            }
            .disabled(!viewModel.canSave)
            .foregroundStyle(viewModel.canSave ? Color.myColors.myGreen : Color.myAccent.opacity(0.8))
        }
        if viewModel.editingPile != nil {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    isShowingDeleteConfirm = true
                } label: {
                    Text("Delete Pile")
                        .foregroundStyle(Color.myColors.myRed)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct SetGroup {
        let collectionID:   UUID
        let collectionName: String
        let isUserCreated:  Bool
        let sets: [CardSet]
    }

    private var availableLevels: [String] {
        let levels = Set(setGroups.flatMap { $0.sets }.compactMap { $0.level })
        return levels.sorted()
    }

    private var filteredSetGroups: [SetGroup] {
        setGroups.compactMap { group in
            // User-created collections (My Sets etc.) always shown, no filtering
            if group.isUserCreated { return group }
            let sets = group.sets.filter { set in
                let matchesLevel  = selectedLevel == nil || set.level == selectedLevel
                let matchesSearch = searchText.isEmpty  || set.name.localizedCaseInsensitiveContains(searchText)
                return matchesLevel && matchesSearch
            }
            return sets.isEmpty ? nil : SetGroup(collectionID: group.collectionID, collectionName: group.collectionName, isUserCreated: false, sets: sets)
        }
    }

    private var setGroups: [SetGroup] {
        collections
            .compactMap { collection -> SetGroup? in
                let sets = cardSets.filter {
                    $0.collectionId == collection.id && $0.name != "Inbox"
                }
                guard !sets.isEmpty else { return nil }
                return SetGroup(
                    collectionID:   collection.id,
                    collectionName: collection.name,
                    isUserCreated:  collection.isUserCreated,
                    sets: sets
                )
            }
    }

    private func activeCardCount(for setId: UUID) -> Int {
        allCards.filter { $0.setId == setId && $0.status == .active }.count
    }

    private var shuffleFooter: String {
        switch viewModel.shuffleMethod {
        case .random:      return "Cards appear in a random order every session."
        case .sequential:  return "Cards appear in the order they were added."
        case .prioritized: return "Hardest cards (lowest ease) appear first."
        }
    }
}

// MARK: - SetToggleRow

private struct SetToggleRow: View {
    let name:       String
    let level:      CEFRLevel?
    let cardCount:  Int
    let isSelected: Bool
    let onToggle:   () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.title3)
                .animation(.spring(duration: 0.2), value: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                Text("\(cardCount) active cards")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
            }
            Spacer()
            CEFRBadgeView(level: level)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
