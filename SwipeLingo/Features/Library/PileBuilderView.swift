import SwiftUI
import SwiftData

// MARK: - PileBuilderView
// Sheet for creating or editing a Pile.
// "Study" activates the pile and switches to the Study tab.

struct PileBuilderView: View {

    @Environment(\.modelContext)  private var context
    @Environment(\.dismiss)       private var dismiss
    @Environment(AppViewModel.self) private var appViewModel

    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    @Query(sort: \CardSet.createdAt)    private var cardSets:    [CardSet]
    @Query(sort: \Card.createdAt)       private var allCards:    [Card]
    @Query                              private var allPiles:    [Pile]

    @State private var viewModel: PileBuilderViewModel

    init(editingPile: Pile? = nil) {
        _viewModel = State(initialValue: PileBuilderViewModel(editingPile: editingPile))
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                shuffleSection
                setsSection
            }
            .navigationTitle(viewModel.editingPile == nil ? "New Pile" : "Edit Pile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarButtons }
        }
    }

    // MARK: - Form Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("e.g. Morning Session", text: $viewModel.name)
        }
    }

    private var shuffleSection: some View {
        Section {
            Picker("", selection: $viewModel.shuffleMethod) {
                Label("Random",     systemImage: "shuffle")        .tag(ShuffleMethod.random)
                Label("Sequential", systemImage: "arrow.down")     .tag(ShuffleMethod.sequential)
                Label("Hardest first", systemImage: "flame")       .tag(ShuffleMethod.prioritized)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Shuffle method")
        } footer: {
            Text(shuffleFooter)
                .font(.caption)
        }
    }

    private var setsSection: some View {
        ForEach(setGroups, id: \.collectionID) { group in
            Section(group.collectionName) {
                ForEach(group.sets) { set in
                    SetToggleRow(
                        name: set.name,
                        cardCount: activeCardCount(for: set.id),
                        isSelected: viewModel.selectedSetIds.contains(set.id)
                    ) {
                        viewModel.toggleSet(set.id)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        // "Study" — primary: save + activate + switch tab
        ToolbarItem(placement: .confirmationAction) {
            Button("Study") {
                viewModel.saveAndActivate(context: context, allPiles: allPiles)
                appViewModel.selectedTab = .study
                dismiss()
            }
            .disabled(!viewModel.isValid)
            .fontWeight(.semibold)
        }
        // "Save" — secondary: save only, stay in Library
        ToolbarItem(placement: .topBarLeading) {
            if viewModel.editingPile != nil || !viewModel.name.isEmpty {
                Button("Save") {
                    viewModel.save(context: context)
                    dismiss()
                }
                .disabled(!viewModel.isValid)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private struct SetGroup {
        let collectionID:   UUID
        let collectionName: String
        let sets: [CardSet]
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
    let name:      String
    let cardCount: Int
    let isSelected: Bool
    let onToggle:  () -> Void

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.title3)
                .animation(.spring(duration: 0.2), value: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                Text("\(cardCount) active cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
