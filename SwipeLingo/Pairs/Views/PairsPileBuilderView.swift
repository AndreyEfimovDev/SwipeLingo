import SwiftUI
import SwiftData

// MARK: - PairsPileBuilderView
// Sheet for creating or editing a PairsPile.
// Save activates the pile and dismisses.

struct PairsPileBuilderView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss

    @Query(sort: \PairsSet.createdAt, order: .reverse) private var allSets: [PairsSet]
    @Query private var allPiles: [PairsPile]

    @State private var viewModel: PairsPileBuilderViewModel
    @State private var isShowingDeleteConfirm = false
    @State private var searchText   = ""
    @State private var selectedLevel: CEFRLevel? = nil

    init(editingPile: PairsPile? = nil) {
        _viewModel = State(initialValue: PairsPileBuilderViewModel(editingPile: editingPile))
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

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NAME")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 32)

            TextField("e.g. Evening Session", text: $viewModel.name)
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
                shuffleRow(.random,     icon: "shuffle",     name: "Random")
                Divider().padding(.leading, 52)
                shuffleRow(.sequential, icon: "arrow.down",  name: "Sequential")
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

    private var shuffleFooter: String {
        switch viewModel.shuffleMethod {
        case .random:      return "Sets appear in a random order every session."
        case .sequential:  return "Sets appear in the order they were added."
        case .prioritized: return "Hardest sets appear first."
        }
    }

    // MARK: - Sets Filter Header

    private var setsFilterHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                levelPill(nil, label: "All")
                ForEach(availableLevels, id: \.self) { level in
                    levelPill(level, label: level.displayCode)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

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
    private func levelPill(_ level: CEFRLevel?, label: String) -> some View {
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

    // MARK: - Sets

    private var setsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SETS")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.myColors.myAccent.opacity(0.8))
                .padding(.horizontal, 32)

            if filteredSets.isEmpty {
                Text("No sets found")
                    .font(.subheadline)
                    .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredSets) { set in
                        PairsSetToggleRow(
                            set: set,
                            isSelected: viewModel.selectedSetIds.contains(set.id)
                        ) {
                            viewModel.toggleSet(set.id)
                        }
                        if set.id != filteredSets.last?.id {
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
            Button(viewModel.editingPile == nil ? "Create" : "Save") {
                viewModel.saveAndActivate(context: context, allPiles: allPiles)
                dismiss()
            }
            .disabled(!viewModel.canSave)
            .foregroundStyle(viewModel.canSave ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.8))
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

    private var availableLevels: [CEFRLevel] {
        let levels = Set(allSets.map { $0.cefrLevel })
        return CEFRLevel.allCases.filter { levels.contains($0) }
    }

    private var filteredSets: [PairsSet] {
        allSets.filter { set in
            let matchesLevel  = selectedLevel == nil || set.cefrLevel == selectedLevel
            let matchesSearch = searchText.isEmpty   || (set.title ?? "").localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }
}

// MARK: - PairsSetToggleRow

private struct PairsSetToggleRow: View {
    let set: PairsSet
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.myColors.myBlue : Color.myColors.myAccent.opacity(0.3))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 4) {
                    Text(set.title ?? "Untitled")
                        .font(.body)
                        .foregroundStyle(Color.myColors.myAccent)
                    AccessTierBadge(tier: set.accessTier, isSmall: true)
                        .offset(y: -3)
                }
                let count = set.items.count
                if count > 0 {
                    Text("\(count) \(count == 1 ? "pair" : "pairs")")
                        .font(.caption)
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                }
            }

            Spacer()

            CEFRBadgeView(level: set.cefrLevel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
