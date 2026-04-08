import SwiftUI

// MARK: - AdminCardEditView
//
// Форма создания / редактирования FSCard в SwipeLingoAdmin.
// Phase 1: базовый редактор — EN слово, транскрипция, примеры EN,
//          переводы на все 13 языков (NativeLanguage).
// Phase 2: авто-обогащение через DictionaryService + Apple Translation.

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
            transcription: "",
            translations: [:],
            sampleEN: [],
            sampleTranslations: [:],
            level: CEFRLevel.b1.rawValue,
            accessTierRaw: AccessTier.free.rawValue,
            isPublished: false,
            updatedAt: .now,
            createdAt: .now
        )

        _en            = State(initialValue: c.en)
        _transcription = State(initialValue: c.transcription)
        _sampleEN      = State(initialValue: c.sampleEN.joined(separator: "\n"))
        _level         = State(initialValue: CEFRLevel(rawValue: c.level) ?? .b1)
        _accessTier    = State(initialValue: AccessTier(rawValue: c.accessTierRaw) ?? .free)
        _isPublished   = State(initialValue: c.isPublished)

        var translationsInit: [String: String] = [:]
        var sampleTranslationsInit: [String: String] = [:]
        for lang in NativeLanguage.allCases {
            translationsInit[lang.rawValue] = c.translations[lang.langId] ?? ""
            let samples = c.sampleTranslations[lang.langId] ?? []
            sampleTranslationsInit[lang.rawValue] = samples.joined(separator: "\n")
        }
        _translations       = State(initialValue: translationsInit)
        _sampleTranslations = State(initialValue: sampleTranslationsInit)
    }

    // MARK: - State

    private let existingCard: FSCard?
    private let onSave: (FSCard) -> Void

    @State private var en:                 String
    @State private var transcription:      String
    @State private var sampleEN:           String          // каждая строка = один пример
    @State private var level:              CEFRLevel
    @State private var accessTier:         AccessTier
    @State private var isPublished:        Bool

    // [NativeLanguage.rawValue: text]
    @State private var translations:       [String: String]
    @State private var sampleTranslations: [String: String]

    @State private var isFetchingTranscription = false
    @State private var fetchTask: Task<Void, Never>?

    private let dictionaryService = DictionaryService()

    // MARK: - Body

    var body: some View {
        Form {
            // ── English ───────────────────────────────────
            Section("English") {
                TextField("Word or phrase", text: $en)
                    .onChange(of: en) { _, newValue in
                        scheduleTranscriptionFetch(for: newValue)
                    }

                HStack {
                    TextField("Transcription", text: $transcription)
                        .foregroundStyle(transcription.isEmpty ? Color.secondary : Color.primary)
                    if isFetchingTranscription {
                        ProgressView().scaleEffect(0.7).frame(width: 20, height: 20)
                    } else if !transcription.isEmpty {
                        Text("[\(transcription)]")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples EN (one per line)")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $sampleEN)
                        .frame(minHeight: 70)
                }
            }

            // ── Translations ──────────────────────────────
            Section("Translations") {
                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(lang.flag) \(lang.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Translation", text: binding(for: lang, in: $translations))
                    }
                }
            }

            // ── Example translations ───────────────────────
            Section("Example Translations (one per line)") {
                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(lang.flag) \(lang.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: binding(for: lang, in: $sampleTranslations))
                            .frame(minHeight: 50)
                    }
                }
            }

            // ── Metadata ──────────────────────────────────
            Section("Metadata") {
                Picker("CEFR Level", selection: $level) {
                    ForEach(CEFRLevel.allCases, id: \.self) { l in
                        Text(l.displayCode).tag(l)
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
                Button("Save", action: save)
                    .disabled(en.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Binding helpers

    private func binding(for lang: NativeLanguage, in dict: Binding<[String: String]>) -> Binding<String> {
        Binding(
            get: { dict.wrappedValue[lang.rawValue] ?? "" },
            set: { dict.wrappedValue[lang.rawValue] = $0 }
        )
    }

    // MARK: - Transcription auto-fetch

    private func scheduleTranscriptionFetch(for word: String) {
        fetchTask?.cancel()
        let trimmed = word.trimmingCharacters(in: .whitespaces)
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
                await MainActor.run { isFetchingTranscription = false }
            }
        }
    }

    // MARK: - Save

    private func save() {
        var translationsDict: [String: String] = [:]
        var sampleTranslationsDict: [String: [String]] = [:]

        for lang in NativeLanguage.allCases {
            let text = (translations[lang.rawValue] ?? "").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { translationsDict[lang.langId] = text }

            let samples = lines(from: sampleTranslations[lang.rawValue] ?? "")
            if !samples.isEmpty { sampleTranslationsDict[lang.langId] = samples }
        }

        let card = FSCard(
            id:                 existingCard?.id ?? FirestoreID.make(name: en),
            setId:              existingCard?.setId ?? "",
            en:                 en.trimmingCharacters(in: .whitespaces),
            transcription:      transcription.trimmingCharacters(in: .whitespaces),
            translations:       translationsDict,
            sampleEN:           lines(from: sampleEN),
            sampleTranslations: sampleTranslationsDict,
            level:              level.rawValue,
            accessTierRaw:      accessTier.rawValue,
            isPublished:        isPublished,
            updatedAt:          .now,
            createdAt:          existingCard?.createdAt ?? .now
        )
        onSave(card)
    }

    private func lines(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
