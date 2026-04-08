import SwiftUI

// MARK: - AdminCardEditView
//
// Форма создания / редактирования FSCard в SwipeLingoAdmin.
//
// Логика транскрипции:
//   • При изменении поля "en" (с задержкой 0.8 с) автоматически вызывается
//     DictionaryService.lookup() и заполняет поле transcription.
//   • Пользователь может скорректировать транскрипцию вручную.
//   • Для фраз (несколько слов) API ничего не вернёт — поле останется пустым.
//   • При сохранении transcription записывается в FSCard.transcription →
//     при импорте в SwiftData попадёт в card.dictTranscription.

struct AdminCardEditView: View {

    // MARK: - Init

    /// Если card == nil — режим создания; иначе — редактирование.
    init(card: FSCard? = nil, setId: String, onSave: @escaping (FSCard) -> Void) {
        self.existingCard = card
        self.onSave = onSave
        let c = card ?? FSCard(
            id: FirestoreID.make(name: ""),
            setId: setId,
            en: "",
            item: "",
            transcription: "",
            sampleEN: [],
            sampleItem: [],
            level: CEFRLevel.b1.rawValue,
            accessTierRaw: AccessTier.free.rawValue,
            isPublished: false,
            updatedAt: .now,
            createdAt: .now
        )
        _en            = State(initialValue: c.en)
        _item          = State(initialValue: c.item)
        _transcription = State(initialValue: c.transcription)
        _sampleEN      = State(initialValue: c.sampleEN.joined(separator: "\n"))
        _sampleItem    = State(initialValue: c.sampleItem.joined(separator: "\n"))
        _level         = State(initialValue: CEFRLevel(rawValue: c.level) ?? .b1)
        _accessTier    = State(initialValue: AccessTier(rawValue: c.accessTierRaw) ?? .free)
        _isPublished   = State(initialValue: c.isPublished)
    }

    // MARK: - State

    private let existingCard: FSCard?
    private let onSave: (FSCard) -> Void

    @State private var en:            String
    @State private var item:          String
    @State private var transcription: String
    @State private var sampleEN:      String   // многострочный — каждая строка = один пример
    @State private var sampleItem:    String
    @State private var level:         CEFRLevel
    @State private var accessTier:    AccessTier
    @State private var isPublished:   Bool

    @State private var isFetchingTranscription = false
    @State private var fetchTask: Task<Void, Never>? = nil

    private let dictionaryService = DictionaryService()

    // MARK: - Body

    var body: some View {
        Form {
            // ── English word ──────────────────────────────
            Section("English") {
                TextField("Word or phrase", text: $en)
                    .onChange(of: en) { _, newValue in
                        scheduleTranscriptionFetch(for: newValue)
                    }

                HStack {
                    TextField("Transcription", text: $transcription)
                        .foregroundStyle(transcription.isEmpty
                                         ? Color.secondary
                                         : Color.primary)
                    if isFetchingTranscription {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20, height: 20)
                    } else if !transcription.isEmpty {
                        Text("[\(transcription)]")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Translation (item)", text: $item)
            }

            // ── Examples ──────────────────────────────────
            Section("Examples (one per line)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("English examples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $sampleEN)
                        .frame(minHeight: 80)
                        .font(.body)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Translated examples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $sampleItem)
                        .frame(minHeight: 80)
                        .font(.body)
                }
            }

            // ── Metadata ──────────────────────────────────
            Section("Metadata") {
                Picker("CEFR Level", selection: $level) {
                    ForEach(CEFRLevel.allCases, id: \.self) { l in
                        Text(l.rawValue.uppercased()).tag(l)
                    }
                }
                Picker("Access Tier", selection: $accessTier) {
                    ForEach(AccessTier.allCases, id: \.self) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                Toggle("Published", isOn: $isPublished)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(existingCard == nil ? "New Card" : "Edit Card")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(en.trimmingCharacters(in: .whitespaces).isEmpty ||
                              item.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Transcription auto-fetch

    private func scheduleTranscriptionFetch(for word: String) {
        fetchTask?.cancel()
        let trimmed = word.trimmingCharacters(in: .whitespaces)

        // Не фетчим для пустых строк и фраз (больше одного слова)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else {
            if trimmed.isEmpty { transcription = "" }
            return
        }

        fetchTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }

            await MainActor.run { isFetchingTranscription = true }
            do {
                let entry = try await dictionaryService.lookup(word: trimmed)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    transcription = entry.transcription
                    isFetchingTranscription = false
                }
            } catch {
                await MainActor.run {
                    isFetchingTranscription = false
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let existing = existingCard
        let card = FSCard(
            id:            existing?.id ?? FirestoreID.make(name: en),
            setId:         existing?.setId ?? "",
            en:            en.trimmingCharacters(in: .whitespaces),
            item:          item.trimmingCharacters(in: .whitespaces),
            transcription: transcription.trimmingCharacters(in: .whitespaces),
            sampleEN:      lines(from: sampleEN),
            sampleItem:    lines(from: sampleItem),
            level:         level.rawValue,
            accessTierRaw: accessTier.rawValue,
            isPublished:   isPublished,
            updatedAt:     .now,
            createdAt:     existing?.createdAt ?? .now
        )
        onSave(card)
    }

    private func lines(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
