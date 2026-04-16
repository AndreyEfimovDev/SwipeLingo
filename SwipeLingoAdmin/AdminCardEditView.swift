import SwiftUI
import Translation

// MARK: - AdminCardEditView
//
// Форма создания / редактирования FSCard в SwipeLingoAdmin.
// Auto-Fill: транскрипция через DictionaryService + переводы через Apple Translation
// для всех незаполненных полей.
// CEFR Level и Access Tier — read-only, наследуются из сета.

struct AdminCardEditView: View {

    // MARK: - Init

    /// Если card == nil — режим создания; иначе — редактирование.
    init(card: FSCard? = nil, setId: String, onSave: @escaping (FSCard) -> Void) {
        self.existingCard = card
        self.setId        = setId
        self.onSave       = onSave

        let c = card ?? FSCard(
            id: FirestoreID.make(name: ""),
            setId: setId,
            en: "",
            transcription: "",
            translations: [:],
            sampleEN: [],
            sampleTranslations: [:],
            tag: "",
            level: CEFRLevel.b1.rawValue,
            accessTierRaw: AccessTier.free.rawValue,
            isPublished: false,
            updatedAt: .now,
            createdAt: .now
        )

        _en            = State(initialValue: c.en)
        _transcription = State(initialValue: c.transcription)
        _sampleEN      = State(initialValue: c.sampleEN.joined(separator: "\n"))
        _tagText       = State(initialValue: c.tag)
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

    @Environment(\.dismiss) private var dismiss

    private let existingCard: FSCard?
    private let setId:        String
    private let onSave:       (FSCard) -> Void

    @State private var en:                 String
    @State private var transcription:      String
    @State private var sampleEN:           String
    @State private var tagText:            String
    @State private var level:              CEFRLevel
    @State private var accessTier:         AccessTier
    @State private var isPublished:        Bool

    // [NativeLanguage.rawValue: text]
    @State private var translations:       [String: String]
    @State private var sampleTranslations: [String: String]

    // Transcription fetch
    @State private var isFetchingTranscription = false
    @State private var fetchTask: Task<Void, Never>?

    // Auto-Fill (translation)
    @State private var isAutoFilling:      Bool                               = false
    @State private var translationConfig:  TranslationSession.Configuration?  = nil
    @State private var pendingFillLangs:   [NativeLanguage]                   = []
    @State private var currentFillLang:    NativeLanguage?                    = nil
    @State private var filledLangCount:    Int                                = 0

    private let dictionaryService = DictionaryService()

    private var isAnyOperationRunning: Bool { isFetchingTranscription || isAutoFilling }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── English ───────────────────────────────────
                fieldLabel("Word or phrase")
                clearableField("Word or phrase", text: $en)
                    .onChange(of: en) { _, newValue in
                        scheduleTranscriptionFetch(for: newValue)
                    }

                fieldLabel("Transcription")
                HStack {
                    clearableField("Transcription", text: $transcription)
                    if isFetchingTranscription {
                        ProgressView().scaleEffect(0.7).frame(width: 20, height: 20)
                    } else if !transcription.isEmpty {
                        Text("[\(transcription)]")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                fieldLabel("Examples EN (one per line)")
                TextEditor(text: $sampleEN)
                    .frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

                fieldLabel("Tag")
                clearableField("e.g. Family Members", text: $tagText)

                Divider()

                // ── Translations ──────────────────────────────
                HStack {
                    fieldLabel("Translations")
                    Spacer()
                    if isAutoFilling {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("\(filledLangCount)/\(NativeLanguage.allCases.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            startAutoFill()
                        } label: {
                            Label("Auto-Fill", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(en.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Fill transcription and missing translations automatically")
                    }
                }

                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(lang.flag) \(lang.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        clearableField("Translation", text: binding(for: lang, in: $translations))
                    }
                }

                Divider()

                // ── Example translations ───────────────────────
                fieldLabel("Example Translations (one per line)")
                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(lang.flag) \(lang.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: binding(for: lang, in: $sampleTranslations))
                            .frame(minHeight: 50)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    }
                }

                Divider()

                // ── Metadata (read-only level/tier) ───────────
                GroupBox("Metadata") {
                    LabeledContent("CEFR Level") {
                        Text(level.displayCode)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    LabeledContent("Access Tier") {
                        Text(accessTier.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    Toggle("Published", isOn: $isPublished)
                }

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(existingCard == nil ? "New Card" : "Edit Card")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    fetchTask?.cancel()
                    translationConfig = nil
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save", action: save)
                    .disabled(en.trimmingCharacters(in: .whitespaces).isEmpty || isAnyOperationRunning)
            }
        }
        .translationTask(translationConfig) { session in
            await runAutoFillTranslation(session: session)
        }
        .onDisappear {
            fetchTask?.cancel()
            translationConfig = nil
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func clearableField(_ placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 0) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.vertical, 5)
                .padding(.leading, 8)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor).opacity(0.5)))
    }

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
                    if sampleEN.trimmingCharacters(in: .whitespaces).isEmpty,
                       let example = entry.meanings.first?.definitions.first?.example {
                        sampleEN = example
                    }
                    isFetchingTranscription = false
                }
            } catch {
                await MainActor.run { isFetchingTranscription = false }
            }
        }
    }

    // MARK: - Auto-Fill

    private func startAutoFill() {
        isAutoFilling   = true
        filledLangCount = 0

        // Транскрипция — если пустая
        let word = en.trimmingCharacters(in: .whitespaces)
        if transcription.trimmingCharacters(in: .whitespaces).isEmpty, !word.isEmpty {
            fetchTask?.cancel()
            fetchTask = Task {
                await MainActor.run { isFetchingTranscription = true }
                do {
                    let entry = try await dictionaryService.lookup(word: word)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        transcription = entry.transcription
                        // Пример EN — если пустой
                        if sampleEN.trimmingCharacters(in: .whitespaces).isEmpty,
                           let example = entry.meanings.first?.definitions.first?.example {
                            sampleEN = example
                        }
                        isFetchingTranscription = false
                    }
                } catch {
                    await MainActor.run { isFetchingTranscription = false }
                }
            }
        }

        // Переводы — только пустые языки
        let emptyLangs = NativeLanguage.allCases.filter {
            (translations[$0.rawValue] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !emptyLangs.isEmpty else {
            isAutoFilling = false
            return
        }

        var langs    = emptyLangs
        let first    = langs.removeFirst()
        pendingFillLangs = langs
        currentFillLang  = first
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: first.langId)
        )
    }

    private func runAutoFillTranslation(session: TranslationSession) async {
        guard let lang = currentFillLang, isAutoFilling else { return }

        let word   = en.trimmingCharacters(in: .whitespaces)
        let sample = sampleEN.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""

        var requests: [TranslationSession.Request] = [
            .init(sourceText: word, clientIdentifier: "word")
        ]
        if !sample.isEmpty {
            requests.append(.init(sourceText: sample, clientIdentifier: "sample"))
        }

        do {
            let responses = try await session.translations(from: requests)
            await MainActor.run {
                for response in responses {
                    switch response.clientIdentifier {
                    case "word":
                        translations[lang.rawValue] = response.targetText
                    case "sample":
                        sampleTranslations[lang.rawValue] = response.targetText
                    default: break
                    }
                }
            }
        } catch {
            log("Auto-fill translation failed for \(lang.langId): \(error)", level: .warning)
        }

        await MainActor.run {
            filledLangCount += 1
            if let nextLang = pendingFillLangs.first, isAutoFilling {
                pendingFillLangs.removeFirst()
                currentFillLang   = nextLang
                translationConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: nextLang.langId)
                )
            } else {
                isAutoFilling     = false
                translationConfig = nil
                currentFillLang   = nil
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
            setId:              existingCard?.setId ?? setId,
            en:                 en.trimmingCharacters(in: .whitespaces),
            transcription:      transcription.trimmingCharacters(in: .whitespaces),
            translations:       translationsDict,
            sampleEN:           lines(from: sampleEN),
            sampleTranslations: sampleTranslationsDict,
            tag:                tagText.trimmingCharacters(in: .whitespaces),
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
