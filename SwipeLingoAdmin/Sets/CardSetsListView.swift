import SwiftUI

// MARK: - CardSetsListView
//
// Detail колонка для Cards-коллекции.
// Показывает список FSCardSet + кнопку создания нового сета.

struct CardSetsListView: View {

    @Environment(AdminStore.self) private var store

    let collectionId: String

    @State private var showEditor = false
    @State private var editingSet: FSCardSet?

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
                    editingSet = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New set")
            }
        }
        .sheet(isPresented: $showEditor) {
            CardSetEditorSheet(collectionId: collectionId, cardSet: editingSet)
        }
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
                    showEditor = true
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

// MARK: - CardSetRow

private struct CardSetRow: View {

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
                Text(set.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(set.accessTier.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(set.isPublished ? "Published" : "Draft")
                .font(.caption)
                .foregroundStyle(set.isPublished ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - FSCardSet + helper

private extension FSCardSet {
    var cefrLevel: CEFRLevel { CEFRLevel(rawValue: level) ?? .b1 }
}
