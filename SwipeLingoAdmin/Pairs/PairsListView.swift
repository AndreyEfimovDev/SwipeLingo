import SwiftUI

// MARK: - PairsListView
//
// Список пар FSPair для выбранного PairsSet.
// Открывается push-навигацией из PairsSetsListView.
// Поддерживает добавление, редактирование, удаление и перестановку пар.

struct PairsListView: View {

    @Environment(AdminStore.self) private var store

    let setId:   String
    let setName: String

    @State private var showNewPair  = false
    @State private var showImport   = false
    @State private var editingPair: FSPair?
    @State private var selectedTag: String? = nil

    private var pairsSet: FSPairsSet? {
        store.pairsSets.first { $0.id == setId }
    }

    private var allItems: [FSPair] {
        pairsSet?.items ?? []
    }

    private var items: [FSPair] {
        guard let tag = selectedTag else { return allItems }
        return allItems.filter { $0.tag == tag }
    }

    private var uniqueTags: [String] {
        Array(Set(allItems.compactMap { $0.tag.isEmpty ? nil : $0.tag })).sorted()
    }

    /// Тип группы для новых пар — выводится из первой пары сета.
    /// nil если сет пуст — редактор покажет все поля.
    private var setGroupType: PairGroupType? {
        guard let first = items.first else { return nil }
        return PairGroupType(from: first)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if uniqueTags.count > 1 {
                tagFilterBar
            }
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .navigationTitle(setName)
        .navigationSubtitle("\(allItems.count) pairs")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import pairs from text")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewPair = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New pair")
            }
        }
        .sheet(isPresented: $showImport) {
            ImportPairsSheet { newPairs in
                guard var updated = pairsSet else { return }
                updated.items.append(contentsOf: newPairs)
                store.update(updated)
            }
        }
        // New pair — тип группы выводится из первой пары сета
        .sheet(isPresented: $showNewPair) {
            PairEditorSheet(pair: nil, groupType: setGroupType) { savedPair in
                savePair(savedPair)
                showNewPair = false
            }
        }
        // Edit pair — тип группы выводится из самой пары
        .sheet(item: $editingPair) { pair in
            PairEditorSheet(pair: pair, groupType: nil) { savedPair in
                savePair(savedPair)
                editingPair = nil
            }
        }
    }

    // MARK: Tag Filter Bar

    private var tagFilterBar: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "All", isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(uniqueTags, id: \.self) { tag in
                        filterChip(title: tag, isSelected: selectedTag == tag) {
                            selectedTag = (selectedTag == tag) ? nil : tag
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.bar)
            Divider()
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var list: some View {
        List {
            ForEach(items) { pair in
                PairRow(pair: pair)
                    .contextMenu {
                        Button("Edit") {
                            editingPair = pair   // sheet(item:) откроется сам
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            deletePair(id: pair.id)
                        }
                    }
            }
            .onMove { indices, newOffset in
                movePairs(from: indices, to: newOffset)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No pairs yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("New Pair") {
                showNewPair = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Mutations

    private func savePair(_ pair: FSPair) {
        guard var updated = pairsSet else { return }
        if let idx = updated.items.firstIndex(where: { $0.id == pair.id }) {
            updated.items[idx] = pair
        } else {
            updated.items.append(pair)
        }
        store.update(updated)
    }

    private func deletePair(id: String) {
        guard var updated = pairsSet else { return }
        updated.items.removeAll { $0.id == id }
        store.update(updated)
    }

    private func movePairs(from indices: IndexSet, to newOffset: Int) {
        guard var updated = pairsSet else { return }
        updated.items.move(fromOffsets: indices, toOffset: newOffset)
        store.update(updated)
    }
}

// MARK: - PairRow

private struct PairRow: View {

    let pair: FSPair

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // Line 1: left → right
            HStack(spacing: 0) {
                Text(pair.left ?? "—")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)

                Text(pair.right ?? "—")
                    .font(.body)
                    .foregroundStyle(pair.right != nil ? .primary : .tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Line 2: description (optional)
            if let desc = pair.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Line 3: sample (optional, italic)
            if let sample = pair.sample, !sample.isEmpty {
                Text(sample)
                    .font(.subheadline.italic())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Tag badge (optional)
            if !pair.tag.isEmpty {
                Text(pair.tag)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
