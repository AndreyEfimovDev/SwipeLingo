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
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle(viewModel.editingPile == nil ? "New Pile" : "Edit Pile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarButtons }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.mySecondary)
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
                .foregroundStyle(Color.myColors.mySecondary)
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
                .foregroundStyle(Color.myColors.mySecondary)
                .padding(.horizontal, 32)
        }
    }

    private func shuffleRow(_ method: ShuffleMethod, icon: String, name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.myColors.mySecondary)
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

    // MARK: - Sets Section

    private var setsSection: some View {
        ForEach(setGroups, id: \.collectionID) { group in
            VStack(alignment: .leading, spacing: 6) {
                Text(group.collectionName.uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.myColors.mySecondary)
                    .padding(.horizontal, 32)

                VStack(spacing: 0) {
                    ForEach(group.sets) { set in
                        SetToggleRow(
                            name: set.name,
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
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                viewModel.saveAndActivate(context: context, allPiles: allPiles)
                appViewModel.selectedTab = .study
                dismiss()
            }
            .disabled(!viewModel.canSave)
            .fontWeight(.semibold)
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
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.title3)
                .animation(.spring(duration: 0.2), value: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                Text("\(cardCount) active cards")
                    .font(.caption)
                    .foregroundStyle(Color.myColors.mySecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
