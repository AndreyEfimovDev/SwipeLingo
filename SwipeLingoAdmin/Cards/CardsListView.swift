import SwiftUI

// MARK: - CardsListView
//
// Список карточек FSCard для выбранного CardSet.
// Открывается push-навигацией из CardSetsListView.
// Toolbar: "+" — создание карточки.
// Context menu: Edit, Delete.

struct CardsListView: View {

    @Environment(AdminStore.self) private var store

    let setId:   String
    let setName: String

    @State private var showEditor  = false
    @State private var editingCard: FSCard?

    private var cards: [FSCard] {
        store.cards(for: setId)
    }

    // MARK: Body

    var body: some View {
        Group {
            if cards.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle(setName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingCard = nil
                    showEditor  = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New card")
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                AdminCardEditView(card: editingCard, setId: setId) { savedCard in
                    if editingCard != nil {
                        store.update(savedCard)
                    } else {
                        store.add(savedCard)
                    }
                    showEditor = false
                }
            }
        }
    }

    // MARK: List

    private var list: some View {
        List(cards, id: \.id) { card in
            CardRow(card: card)
                .contextMenu {
                    Button("Edit") {
                        editingCard = card
                        showEditor  = true
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.delete(cardId: card.id)
                    }
                }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No cards yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("New Card") {
                editingCard = nil
                showEditor  = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CardRow

private struct CardRow: View {

    let card: FSCard

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(card.en)
                        .font(.body.weight(.medium))
                    if !card.transcription.isEmpty {
                        Text("[\(card.transcription)]")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                let count = card.translations.count
                Text(count == 0 ? "No translations" : "\(count) language\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(count == 0 ? .red : .secondary)
            }

            Spacer()

            Text(card.isPublished ? "Published" : "Draft")
                .font(.caption)
                .foregroundStyle(card.isPublished ? .green : .secondary)
        }
        .padding(.vertical, 2)
    }
}
