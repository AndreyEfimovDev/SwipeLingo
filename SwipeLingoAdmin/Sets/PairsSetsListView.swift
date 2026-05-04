import SwiftUI

// MARK: - PairsSetsListView
//
// Detail колонка для Pairs-коллекции.
// Показывает список FSPairsSet + кнопку создания нового сета.

struct PairsSetsListView: View {

    @Environment(AdminStore.self) private var store

    let collectionId: String

    @State private var showNewSet   = false
    @State private var editingSet:  FSPairsSet?
    @State private var showDeleted  = false

    private var sets: [FSPairsSet] {
        showDeleted
            ? store.pairsSets.filter { $0.collectionId == collectionId && $0.deployStatus == .deleted }
            : store.pairsSets(for: collectionId)
    }

    private var deletedCount: Int {
        store.pairsSets.filter { $0.collectionId == collectionId && $0.deployStatus == .deleted }.count
    }

    // MARK: Body

    var body: some View {
        Group {
            if sets.isEmpty {
                if showDeleted { deletedEmptyState } else { emptyState }
            } else {
                list
            }
        }
        .navigationTitle(collectionName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Pairs Sets")
                    .font(.headline)
                    .padding(.horizontal)
            }
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if deletedCount > 0 {
                        Button {
                            showDeleted.toggle()
                        } label: {
                            Image(systemName: showDeleted ? "trash.slash" : "trash")
                                .foregroundStyle(showDeleted ? .red : .secondary)
                        }
                        .help(showDeleted ? "Hide deleted sets" : "Show deleted sets (\(deletedCount))")
                    }
                    Button {
                        showNewSet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New set")
                    .disabled(showDeleted)
                }
            }
        }
        .onChange(of: collectionId) { showDeleted = false }
        // Создание нового сета
        .sheet(isPresented: $showNewSet) {
            PairsSetEditorSheet(collectionId: collectionId, pairsSet: nil)
        }
        // Редактирование существующего сета — sheet(item:) исключает race condition
        .sheet(item: $editingSet) { set in
            PairsSetEditorSheet(collectionId: collectionId, pairsSet: set)
        }
        .alert(
            "Deploy Failed",
            isPresented: Binding(
                get: { store.deployError != nil },
                set: { if !$0 { store.deployError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { store.deployError = nil } },
            message: {
                if let err = store.deployError { Text(err) }
            }
        )
        .alert(
            "Delete Failed",
            isPresented: Binding(
                get: { store.deleteError != nil },
                set: { if !$0 { store.deleteError = nil } }
            ),
            actions: { Button("OK", role: .cancel) { store.deleteError = nil } },
            message: {
                if let err = store.deleteError { Text(err) }
            }
        )
    }

    // MARK: List

    private var list: some View {
        List(sets, id: \.id) { set in
            NavigationLink {
                PairsListView(setId: set.id, setName: set.title ?? "Untitled")
            } label: {
                PairsSetRow(set: set)
                    .opacity(showDeleted ? 0.5 : 1)
            }
            .contextMenu {
                if showDeleted {
                    Button("Restore") {
                        store.restore(pairsSetId: set.id)
                        showDeleted = false
                    }
                    Divider()
                    Button("Delete Forever", role: .destructive) {
                        Task { await store.deleteForever(pairsSetId: set.id) }
                    }
                } else {
                    Button("Edit") { editingSet = set }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.delete(pairsSetId: set.id)
                    }
                }
            }
        }
    }

    // MARK: Empty states

    private var deletedEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No deleted sets")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No sets yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("New Set") {
                showNewSet = true
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

    @Environment(AdminStore.self) private var store
    let set: FSPairsSet

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                let count = set.items.count
                Text(count > 0 ? "\(set.title ?? "Untitled") (\(count))" : (set.title ?? "Untitled"))
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(set.cefrLevel.displayCode)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Status badge
                deployStatusBadge(set.deployStatus)

                // Mark as Ready — for .new and .draft
                if set.deployStatus == .new || set.deployStatus == .draft {
                    Button("Mark as Ready") {
                        store.markReady(pairsSetId: set.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                // Deploy — for .ready only
                if set.deployStatus == .ready {
                    Button {
                        Task { await store.deployPairsSet(id: set.id) }
                    } label: {
                        if store.isDeploying {
                            Label("Deploying…", systemImage: "arrow.up.circle")
                                .font(.caption)
                        } else {
                            Label("Deploy", systemImage: "arrow.up.circle")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(store.isDeploying)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func deployStatusBadge(_ status: SetDeployStatus) -> some View {
        let color: Color = switch status {
            case .new:     .green
            case .draft:   .orange
            case .ready:   .red
            case .live:    .blue
            case .deleted: .gray
        }
        Text(status.label)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
    }
}
