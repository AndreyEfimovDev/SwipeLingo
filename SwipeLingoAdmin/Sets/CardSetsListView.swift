import SwiftUI

// MARK: - CardSetsListView
//
// Detail колонка для Cards-коллекции.
// Показывает список FSCardSet + кнопку создания нового сета.

struct CardSetsListView: View {

    @Environment(AdminStore.self) private var store

    let collectionId: String
    @Binding var selectedSetId: String?

    @State private var showNewEditor  = false
    @State private var editingSet:    FSCardSet?
    @State private var showDeleted    = false

    private var sets: [FSCardSet] {
        showDeleted
            ? store.cardSets.filter { $0.collectionId == collectionId && $0.deployStatus == .deleted }
            : store.cardSets(for: collectionId)
    }

    private var deletedCount: Int {
        store.cardSets.filter { $0.collectionId == collectionId && $0.deployStatus == .deleted }.count
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
                Text("Card sets")
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
                        showNewEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add card set")
                    .disabled(showDeleted)
                }
            }
        }
        .onChange(of: collectionId) { showDeleted = false }
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
        List(selection: showDeleted ? .constant(nil) : $selectedSetId) {
            ForEach(sets, id: \.id) { set in
                CardSetRow(set: set)
                    .opacity(showDeleted ? 0.5 : 1)
                    .tag(set.id)
                    .contextMenu {
                        if showDeleted {
                            Button("Restore") {
                                store.restore(cardSetId: set.id)
                                showDeleted = false
                            }
                            Divider()
                            Button("Delete Forever", role: .destructive) {
                                Task { await store.deleteForever(cardSetId: set.id) }
                            }
                        } else {
                            Button("Edit") { editingSet = set }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.delete(cardSetId: set.id)
                            }
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
        HStack(spacing: 8) {
            // Name + CEFR + Tier — все вместе слева, имя не смещается
            HStack(alignment: .center, spacing: 5) {
                let count = store.cards(for: set.id).count
                Text(count > 0 ? "\(set.name) (\(count))" : set.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)
                CEFRBadgeView(level: set.cefrLevel)
                    .font(.caption.weight(.semibold))
                AdminTierBadge(tier: set.accessTier)
            }

            Spacer(minLength: 8)

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

// MARK: - AdminTierBadge
// Показывает тир для всех уровней включая Free — используется только в Admin.

struct AdminTierBadge: View {
    let tier: AccessTier
    var body: some View {
        let (label, fg, bg): (String, Color, Color) = switch tier {
        case .free: ("Free",  .secondary,    Color.secondary.opacity(0.12))
        case .go:   ("GO",    Color.purple,   Color.purple.opacity(0.12))
        case .pro:  ("PRO",   Color.orange,   Color.orange.opacity(0.12))
        }
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(fg.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - FSCardSet + helper

