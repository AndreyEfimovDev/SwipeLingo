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
    @State private var selectedTag:   String? = nil

    private var cardSet: FSCardSet? {
        store.cardSets.first { $0.id == setId }
    }

    private var allCards: [FSCard] {
        store.cards(for: setId)
    }

    private var cards: [FSCard] {
        guard let tag = selectedTag else { return allCards }
        return allCards.filter { $0.tag == tag }
    }

    private var uniqueTags: [String] {
        Array(Set(allCards.compactMap { $0.tag.isEmpty ? nil : $0.tag })).sorted()
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            if uniqueTags.count > 1 {
                tagFilterBar
            }
            Group {
                if cards.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .navigationTitle(setName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if let level = cardSet?.cefrLevel {
                        Text(level.displayCode)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(level.color, in: RoundedRectangle(cornerRadius: 5))
                    }
                    Text(setName)
                        .font(.headline)
                }
                .padding(.horizontal)
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showImport = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import words from text")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New card")
            }
        }
        .sheet(isPresented: $showImport) {
            ImportCardsSheet(setId: setId)
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
            }

            // Строка 2: пример на EN
            if let example = card.sampleEN.first, !example.isEmpty {
                Text(example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Строка 3: русский перевод + тег + кол-во переводов
            HStack(spacing: 8) {
                let ruTranslation = card.translation(for: .russian)
                if !ruTranslation.isEmpty {
                    Text(ruTranslation)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
                if !card.tag.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(card.tag)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Spacer()
                let count = card.translations.count
                Text(count == 0 ? "No translations" : "\(count) lang")
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
                if !card.tag.isEmpty {
                    Label(card.tag, systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.blue)
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
