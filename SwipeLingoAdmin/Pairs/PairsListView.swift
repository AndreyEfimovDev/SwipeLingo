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

    @State private var showNewPair = false
    @State private var showImport  = false
    @State private var editingPair: FSPair?

    private var pairsSet: FSPairsSet? {
        store.pairsSets.first { $0.id == setId }
    }

    private var items: [FSPair] {
        pairsSet?.items ?? []
    }

    // MARK: Body

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(setName)
        .navigationSubtitle("\(items.count) pairs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewPair = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New pair")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import pairs from text")
            }
        }
        .sheet(isPresented: $showImport) {
            ImportPairsSheet { newPairs in
                guard var updated = pairsSet else { return }
                updated.items.append(contentsOf: newPairs)
                store.update(updated)
            }
        }
        // New pair — pair: nil гарантировано
        .sheet(isPresented: $showNewPair) {
            PairEditorSheet(pair: nil) { savedPair in
                savePair(savedPair)
                showNewPair = false
            }
        }
        // Edit pair — item передаётся напрямую, race condition исключена
        .sheet(item: $editingPair) { pair in
            PairEditorSheet(pair: pair) { savedPair in
                savePair(savedPair)
                editingPair = nil
            }
        }
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
