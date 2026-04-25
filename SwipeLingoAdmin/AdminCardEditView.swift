import SwiftUI
import Translation

// MARK: - AdminCardEditView
//
// Форма создания / редактирования FSCard в SwipeLingoAdmin.
// Auto-Fill: транскрипция через DictionaryService + переводы через Apple Translation
// для всех незаполненных полей.
// Clear All: очищает sampleEN, все переводы и примеры переводов (Transcription не трогает —
//   обновляется автоматически при изменении EN).

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
            updatedAt:    .now,
            createdAt:    .now
        )

        _en            = State(initialValue: c.en)
        _transcription = State(initialValue: c.transcription)
        _sampleEN      = State(initialValue: c.sampleEN.joined(separator: "\n"))
        _tagText       = State(initialValue: c.tag)

        var translationsInit: [String: String] = [:]
        var sampleTranslationsInit: [String: String] = [:]
        for lang in NativeLanguage.allCases {
            translationsInit[lang.langId] = c.translations[lang.langId] ?? ""
            let samples = c.sampleTranslations[lang.langId] ?? []
            sampleTranslationsInit[lang.langId] = samples.joined(separator: "\n")
        }
        _translations       = State(initialValue: translationsInit)
        _sampleTranslations = State(initialValue: sampleTranslationsInit)
    }

    // MARK: - State

    @Environment(\.dismiss)   private var dismiss
    @Environment(AdminStore.self) private var store

    private let existingCard: FSCard?
    private let setId:        String
    private let onSave:       (FSCard) -> Void

    @State private var en:                 String
    @State private var transcription:      String
    @State private var sampleEN:           String
    @State private var tagText:            String

    // [lang.langId: text]
    @State private var translations:       [String: String]
    @State private var sampleTranslations: [String: String]

    // Transcription fetch
    @State private var isFetchingTranscription = false
    @State private var fetchTask: Task<Void, Never>?

    // Examples EN fetch
    @State private var isFetchingExamples = false
    @State private var examplesTask: Task<Void, Never>?

    // Auto-Fill (translation)
    @State private var isAutoFilling:      Bool                               = false
    @State private var translationConfig:  TranslationSession.Configuration?  = nil
    @State private var pendingFillLangs:   [NativeLanguage]                   = []
    @State private var currentFillLang:    NativeLanguage?                    = nil
    @State private var filledLangCount:    Int                                = 0
    @State private var failedFillLangs:    Set<NativeLanguage>                = []

    private let dictionaryService = DictionaryService()

    private var isAnyOperationRunning: Bool { isFetchingTranscription || isAutoFilling || isFetchingExamples }

    /// Уникальные теги из других карточек этого сета — для dropdown в поле Tag.
    private var existingTags: [String] {
        let allTags = store.cards(for: setId)
            .filter { $0.id != existingCard?.id }
            .map    { $0.tag.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return allTags.filter { seen.insert($0).inserted }.sorted()
    }

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

                HStack(spacing: 8) {
                    fieldLabel("Examples EN (one per line)")
                    Spacer()
                    if isFetchingExamples {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button { fetchExamples() } label: {
                            Label("Enrich", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(en.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Fetch example sentences from dictionary (replaces current content)")
                    }
                }
                clearableTextEditor(text: $sampleEN, minHeight: 70)

                // ── Tag ───────────────────────────────────────
                fieldLabel("Tag")
                HStack(spacing: 6) {
                    clearableField("e.g. Family Members", text: $tagText)

                    if !existingTags.isEmpty {
                        Menu {
                            ForEach(existingTags, id: \.self) { tag in
                                Button(tag) { tagText = tag }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Pick an existing tag")
                    }
                }

                Divider()

                // ── Translations ──────────────────────────────
                HStack(spacing: 8) {
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
                            clearAllContent()
                        } label: {
                            Label("Clear All", systemImage: "xmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .help("Clear examples and all translations (Transcription is kept)")

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
                        HStack(spacing: 4) {
                            Text("\(lang.flag) \(lang.displayName)")
                                .font(.caption).foregroundStyle(.secondary)
                            if failedFillLangs.contains(lang) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .help("Translation unavailable — language pack may not be installed")
                            }
                        }
                        clearableField("Translation", text: binding(for: lang, in: $translations))
                    }
                }

                Divider()

                // ── Example translations ───────────────────────
                HStack(spacing: 8) {
                    fieldLabel("Example Translations (one per line)")
                    Spacer()
                    if isAutoFilling {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7)
                            Text("\(filledLangCount)/\(NativeLanguage.allCases.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button { startSampleFill() } label: {
                            Label("Auto-Fill", systemImage: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .disabled(sampleEN.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Translate example sentences into all languages")
                    }
                }
                ForEach(NativeLanguage.allCases, id: \.self) { lang in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(lang.flag) \(lang.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        clearableTextEditor(
                            text: binding(for: lang, in: $sampleTranslations),
                            minHeight: 50
                        )
                    }
                }

                Divider()

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(existingCard == nil ? "New Card" : "Edit Card")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    fetchTask?.cancel()
                    examplesTask?.cancel()
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
            examplesTask?.cancel()
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
                        .foregroundStyle(Color.myColors.myRed.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor).opacity(0.5)))
    }

    /// TextEditor с кнопкой очистки (xmark) в правом верхнем углу.
    private func clearableTextEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .padding(.trailing, text.wrappedValue.isEmpty ? 0 : 20)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.myColors.myAccent.opacity(0.25)))

            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.myColors.myRed.opacity(0.5))
                        .background(Color(NSColor.textBackgroundColor), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
    }

    private func binding(for lang: NativeLanguage, in dict: Binding<[String: String]>) -> Binding<String> {
        Binding(
            get: { dict.wrappedValue[lang.langId] ?? "" },
            set: { dict.wrappedValue[lang.langId] = $0 }
        )
    }

    // MARK: - Clear All

    /// Очищает все поля кроме EN и Transcription.
    /// Transcription обновляется автоматически при изменении EN.
    private func clearAllContent() {
        sampleEN = ""
        for lang in NativeLanguage.allCases {
            translations[lang.langId]       = ""
            sampleTranslations[lang.langId] = ""
        }
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

    // MARK: - Examples Enrich

    /// Загружает примеры предложений из словаря и заменяет содержимое поля sampleEN.
    /// Собирает все примеры из всех meanings/definitions — каждый на новой строке.
    private func fetchExamples() {
        let word = en.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        examplesTask?.cancel()
        examplesTask = Task {
            await MainActor.run { isFetchingExamples = true }
            do {
                let entry = try await dictionaryService.lookup(word: word)
                guard !Task.isCancelled else { return }
                let examples = entry.meanings
                    .flatMap { $0.definitions }
                    .compactMap { $0.example }
                    .filter { !$0.isEmpty }
                await MainActor.run {
                    if !examples.isEmpty {
                        sampleEN = examples.joined(separator: "\n")
                    }
                    isFetchingExamples = false
                }
            } catch {
                await MainActor.run { isFetchingExamples = false }
            }
        }
    }

    // MARK: - Auto-Fill

    private func startAutoFill() {
        isAutoFilling   = true
        filledLangCount = 0
        failedFillLangs = []

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

        // Языки где пусто слово ИЛИ пуст пример перевода (если sampleEN заполнен)
        let hasSample = !sampleEN.trimmingCharacters(in: .whitespaces).isEmpty
        let emptyLangs = NativeLanguage.allCases.filter {
            let wordEmpty   = (translations[$0.langId]       ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            let sampleEmpty = (sampleTranslations[$0.langId] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            return wordEmpty || (hasSample && sampleEmpty)
        }
        guard !emptyLangs.isEmpty else {
            isAutoFilling = false
            return
        }

        startTranslationLoop(langs: emptyLangs)
    }

    /// Заполняет только пустые примеры переводов (слова не трогает).
    private func startSampleFill() {
        guard !sampleEN.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAutoFilling   = true
        filledLangCount = 0
        failedFillLangs = []

        let emptyLangs = NativeLanguage.allCases.filter {
            (sampleTranslations[$0.langId] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !emptyLangs.isEmpty else {
            isAutoFilling = false
            return
        }

        startTranslationLoop(langs: emptyLangs)
    }

    private func startTranslationLoop(langs: [NativeLanguage]) {
        var list = langs
        let first = list.removeFirst()
        pendingFillLangs  = list
        currentFillLang   = first
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: first.translationLocaleId)
        )
    }

    private func runAutoFillTranslation(session: TranslationSession) async {
        guard let lang = currentFillLang, isAutoFilling else { return }

        let word   = en.trimmingCharacters(in: .whitespaces)
        let sample = sampleEN.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""

        // Запрашиваем только то, что реально пустое для этого языка
        var requests: [TranslationSession.Request] = []
        if (translations[lang.langId] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            requests.append(.init(sourceText: word, clientIdentifier: "word"))
        }
        if !sample.isEmpty,
           (sampleTranslations[lang.langId] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            requests.append(.init(sourceText: sample, clientIdentifier: "sample"))
        }

        if !requests.isEmpty {
            do {
                let responses = try await session.translations(from: requests)
                await MainActor.run {
                    for response in responses {
                        switch response.clientIdentifier {
                        case "word":   translations[lang.langId]       = response.targetText
                        case "sample": sampleTranslations[lang.langId] = response.targetText
                        default: break
                        }
                    }
                }
            } catch {
                log("Auto-fill translation failed for \(lang.langId): \(error)", level: .warning)
                await MainActor.run { failedFillLangs.insert(lang) }
            }
        }

        await MainActor.run { advanceTranslation() }
    }

    private func advanceTranslation() {
        filledLangCount += 1
        if let nextLang = pendingFillLangs.first, isAutoFilling {
            pendingFillLangs.removeFirst()
            currentFillLang   = nextLang
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: nextLang.translationLocaleId)
            )
        } else {
            isAutoFilling     = false
            translationConfig = nil
            currentFillLang   = nil
        }
    }

    // MARK: - Save

    private func save() {
        var translationsDict: [String: String] = [:]
        var sampleTranslationsDict: [String: [String]] = [:]

        for lang in NativeLanguage.allCases {
            let text = (translations[lang.langId] ?? "").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { translationsDict[lang.langId] = text }

            let samples = lines(from: sampleTranslations[lang.langId] ?? "")
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
