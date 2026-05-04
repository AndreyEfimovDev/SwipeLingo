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
    @State private var searchText = ""

    init(editingPile: PairsPile? = nil) {
        _viewModel = State(initialValue: PairsPileBuilderViewModel(editingPile: editingPile))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    nameSection
                    setsSection
                }
                .padding(.vertical, 16)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                searchHeader
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

    // MARK: - Search Header

    private var searchHeader: some View {
        SearchBar(text: $searchText, prompt: "Search sets")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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

    private var filteredSets: [PairsSet] {
        guard !searchText.isEmpty else { return allSets }
        return allSets.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.setDescription ?? "").localizedCaseInsensitiveContains(searchText)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
