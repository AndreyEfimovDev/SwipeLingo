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

    @State private var showEditor  = false
    @State private var showImport  = false
    @State private var editingPair: FSPair?

    private var pairsSet: FSPairsSet? {
        store.pairsSets.first { $0.id == setId }
    }

    private var items: [FSPair] {
        pairsSet?.items ?? []
    }

    private var leftTitle:  String { pairsSet?.leftTitle  ?? "Left"  }
    private var rightTitle: String { pairsSet?.rightTitle ?? "Right" }

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
        .navigationSubtitle("\(leftTitle) → \(rightTitle)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingPair = nil
                    showEditor  = true
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
            ImportPairsSheet(
                leftTitle:  leftTitle,
                rightTitle: rightTitle
            ) { newPairs in
                guard var updated = pairsSet else { return }
                updated.items.append(contentsOf: newPairs)
                store.update(updated)
            }
        }
        .sheet(isPresented: $showEditor) {
            PairEditorSheet(
                pair:       editingPair,
                leftTitle:  leftTitle,
                rightTitle: rightTitle
            ) { savedPair in
                savePair(savedPair)
                showEditor = false
            }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            ForEach(items) { pair in
                PairRow(pair: pair, leftTitle: leftTitle, rightTitle: rightTitle)
                    .contextMenu {
                        Button("Edit") {
                            editingPair = pair
                            showEditor  = true
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
                editingPair = nil
                showEditor  = true
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

    let pair:       FSPair
    let leftTitle:  String
    let rightTitle: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leftTitle)
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(pair.left?.text ?? "—")
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(rightTitle)
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(pair.right?.text ?? "—")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
