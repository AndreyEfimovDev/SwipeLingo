import SwiftUI

// MARK: - PairsSetsListView
//
// Detail колонка для Pairs-коллекции.
// Показывает список FSPairsSet + кнопку создания нового сета.

struct PairsSetsListView: View {

    @Environment(AdminStore.self) private var store

    let collectionId: String

    @State private var showEditor = false
    @State private var editingSet: FSPairsSet?

    private var sets: [FSPairsSet] {
        store.pairsSets(for: collectionId)
    }

    // MARK: Body

    var body: some View {
        Group {
            if sets.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(collectionName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingSet = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New set")
            }
        }
        .sheet(isPresented: $showEditor) {
            PairsSetEditorSheet(collectionId: collectionId, pairsSet: editingSet)
        }
    }

    // MARK: List

    private var list: some View {
        List(sets, id: \.id) { set in
            NavigationLink {
                PairsListView(setId: set.id, setName: set.title ?? "Untitled")
            } label: {
                PairsSetRow(set: set)
            }
            .contextMenu {
                Button("Edit") {
                    editingSet = set
                    showEditor = true
                }
                Divider()
                Button("Delete", role: .destructive) {
                    store.delete(pairsSetId: set.id)
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No sets yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("New Set") {
                editingSet = nil
                showEditor = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var collectionName: String {
        store.collections.first { $0.id == collectionId }?.name ?? "Sets"
    }
}

// MARK: - PairsSetRow

private struct PairsSetRow: View {

    let set: FSPairsSet

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(set.title ?? "Untitled")
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(set.cefrLevel.displayCode)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(set.deployStatus.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(set.items.count) pairs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
