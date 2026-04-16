import SwiftUI

// MARK: - CollectionsListView
//
// Средняя колонка 3-panel layout.
// Показывает список FSCollection для выбранного типа (cards / pairs).
// Toolbar: кнопка "+" для создания новой коллекции.
// Context menu на строке: Edit, Delete.

struct CollectionsListView: View {

    @Environment(AdminStore.self) private var store

    let type: CollectionType
    @Binding var selectedCollectionId: String?

    @State private var showNewEditor:      Bool          = false
    @State private var editingCollection:  FSCollection? = nil

    private var collections: [FSCollection] {
        store.collections(of: type)
    }

    // MARK: Body

    var body: some View {
        Group {
            if collections.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .navigationTitle(type == .cards ? "Cards" : "Pairs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New collection")
            }
        }
        .sheet(isPresented: $showNewEditor) {
            CollectionEditorSheet(type: type, collection: nil)
        }
        .sheet(item: $editingCollection) { collection in
            CollectionEditorSheet(type: type, collection: collection)
        }
    }

    // MARK: List

    private var list: some View {
        List(collections, selection: $selectedCollectionId) { collection in
            CollectionRow(collection: collection)
                .tag(collection.id)
                .contextMenu {
                    Button("Edit") {
                        editingCollection = collection
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.delete(collectionId: collection.id)
                        if selectedCollectionId == collection.id {
                            selectedCollectionId = nil
                        }
                    }
                }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: type == .cards ? "rectangle.stack" : "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No collections yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("New Collection") {
                showNewEditor = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CollectionRow

private struct CollectionRow: View {

    let collection: FSCollection

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(collection.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if !collection.isSynced {
                        Text("New")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = collection.icon, !icon.isEmpty {
            if icon.isEmoji {
                Text(icon)
                    .font(.title3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Image(systemName: collection.type == .cards ? "rectangle.stack" : "square.grid.2x2")
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - String + emoji helper

private extension String {
    /// true если строка — emoji (не ASCII символы, не SF Symbol name)
    var isEmoji: Bool {
        !unicodeScalars.allSatisfy(\.isASCII)
    }
}
