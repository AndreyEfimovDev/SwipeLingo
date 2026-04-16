import SwiftUI

// MARK: - CardsListView
//
// Список карточек FSCard для выбранного CardSet.
// Открывается push-навигацией из CardSetsListView.
// Toolbar: "+" — создание, import — импорт.
// Тап на строку → CardDetailView (просмотр всех полей).
// Context menu: Edit, Delete.

struct CardsListView: View {

    @Environment(AdminStore.self) private var store

    let setId:   String
    let setName: String

    @State private var showNewEditor: Bool    = false
    @State private var showImport:    Bool    = false
    @State private var editingCard:   FSCard? = nil
    @State private var selectedCard:  FSCard? = nil

    private var cards: [FSCard] {
        store.cards(for: setId)
    }

    private var cardSet: FSCardSet? {
        store.cardSets.first { $0.id == setId }
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
            ToolbarItem(placement: .principal) {
                Text(setName).font(.headline)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New card")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import words from text")
            }
        }
        .sheet(isPresented: $showImport) {
            ImportCardsSheet(
                setId:        setId,
                defaultLevel: cardSet.map { CEFRLevel(rawValue: $0.level) ?? .b1 } ?? .b1,
                defaultTier:  cardSet?.accessTier ?? .free
            )
        }
        .sheet(isPresented: $showNewEditor) {
            NavigationStack {
                AdminCardEditView(card: nil, setId: setId) { savedCard in
                    store.add(savedCard)
                    showNewEditor = false
                }
            }
        }
        .sheet(item: $editingCard) { card in
            NavigationStack {
                AdminCardEditView(card: card, setId: setId) { savedCard in
                    store.update(savedCard)
                    editingCard = nil
                }
            }
        }
        .navigationDestination(item: $selectedCard) { card in
            CardDetailView(card: card) {
                selectedCard = nil
                editingCard  = card
            }
        }
    }

    // MARK: List

    private var list: some View {
        List(cards, id: \.id) { card in
            CardRow(card: card)
                .contentShape(Rectangle())
                .onTapGesture { selectedCard = card }
                .contextMenu {
                    Button("Edit") {
                        editingCard = card
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
                showNewEditor = true
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
        VStack(alignment: .leading, spacing: 4) {

            // Строка 1: слово + транскрипция
            HStack(spacing: 8) {
                Text(card.en)
                    .font(.body.weight(.medium))
                if !card.transcription.isEmpty {
                    Text("[\(card.transcription)]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Уровень
                if let level = CEFRLevel(rawValue: card.level) {
                    Text(level.displayCode)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                // Статус
                Text(card.isPublished ? "Published" : "Draft")
                    .font(.caption)
                    .foregroundStyle(card.isPublished ? .green : .secondary)
            }

            // Строка 2: пример на EN
            if let example = card.sampleEN.first, !example.isEmpty {
                Text(example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Строка 3: тег + кол-во переводов
            HStack(spacing: 8) {
                if !card.tag.isEmpty {
                    Text(card.tag)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                let count = card.translations.count
                Text(count == 0 ? "No translations" : "\(count) language\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(count == 0 ? .red : .secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - CardDetailView

struct CardDetailView: View {

    let card:     FSCard
    let onEdit:   () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Заголовок ─────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.en)
                        .font(.title2.weight(.semibold))
                    if !card.transcription.isEmpty {
                        Text("[\(card.transcription)]")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── Метаданные ────────────────────────────────
                HStack(spacing: 16) {
                    if !card.tag.isEmpty {
                        Label(card.tag, systemImage: "tag")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    if let level = CEFRLevel(rawValue: card.level) {
                        Label(level.displayCode, systemImage: "chart.bar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Label(card.accessTier.rawValue.capitalized, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(card.isPublished ? "Published" : "Draft", systemImage: card.isPublished ? "checkmark.circle" : "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(card.isPublished ? .green : .secondary)
                }

                Divider()

                // ── Примеры EN ────────────────────────────────
                if !card.sampleEN.isEmpty {
                    sectionHeader("Examples EN")
                    ForEach(card.sampleEN, id: \.self) { example in
                        Text("• \(example)")
                            .font(.body)
                    }
                    Divider()
                }

                // ── Переводы ──────────────────────────────────
                sectionHeader("Translations")
                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    let translation = card.translation(for: lang)
                    let samples     = card.sampleTranslation(for: lang)
                    if !translation.isEmpty || !samples.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(lang.flag)
                                Text(lang.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if !translation.isEmpty {
                                    Text(translation)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(samples, id: \.self) { sample in
                                Text("  • \(sample)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        Divider()
                    }
                }

                // Если переводов нет
                if card.translations.isEmpty {
                    Text("No translations yet")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
        .navigationTitle(card.en)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", action: onEdit)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
