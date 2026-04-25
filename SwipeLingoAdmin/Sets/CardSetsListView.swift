import SwiftUI

// MARK: - CardSetsListView
//
// Detail колонка для Cards-коллекции.
// Показывает список FSCardSet + кнопку создания нового сета.

struct CardSetsListView: View {

    @Environment(AdminStore.self) private var store

    let collectionId: String

    @State private var showNewEditor = false
    @State private var editingSet:   FSCardSet?

    private var sets: [FSCardSet] {
        store.cardSets(for: collectionId)
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
                    showNewEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New set")
            }
        }
        .sheet(isPresented: $showNewEditor) {
            CardSetEditorSheet(collectionId: collectionId, cardSet: nil)
        }
        .sheet(item: $editingSet) { set in
            CardSetEditorSheet(collectionId: collectionId, cardSet: set)
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
    }

    // MARK: List

    private var list: some View {
        List(sets, id: \.id) { set in
            NavigationLink {
                CardsListView(setId: set.id, setName: set.name)
            } label: {
                CardSetRow(set: set)
            }
            .contextMenu {
                Button("Edit") {
                    editingSet = set
                }
                Divider()
                Button("Delete", role: .destructive) {
                    store.delete(cardSetId: set.id)
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No sets yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("New Set") {
                showNewEditor = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var collectionName: String {
        store.collections.first { $0.id == collectionId }?.name ?? "Sets"
    }
}

// MARK: - CardSetRow

private struct CardSetRow: View {

    @Environment(AdminStore.self) private var store
    let set: FSCardSet

    var body: some View {
        HStack(spacing: 12) {
            // CEFR badge
            Text(set.cefrLevel.displayCode)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(set.cefrLevel.color, in: RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                let count = store.cards(for: set.id).count
                Text(count > 0 ? "\(set.name) (\(count))" : set.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(set.accessTier.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                // Status badge
                deployStatusBadge(set.deployStatus)

                // Mark as Ready — for .new and .draft
                if set.deployStatus == .new || set.deployStatus == .draft {
                    Button("Mark as Ready") {
                        store.markReady(cardSetId: set.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                // Deploy — for .ready only
                if set.deployStatus == .ready {
                    Button {
                        Task { await store.deployCardSet(id: set.id) }
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

// MARK: - FSCardSet + helper

