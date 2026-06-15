import SwiftUI
import Translation

// MARK: - ImportDraft

private struct ImportDraft: Identifiable {
    let id = UUID()
    var word:               String
    var transcription:      String          = ""
    var sampleEN:           [String]        = []
    var translations:       [String: String] = [:]   // [langId: translatedWord]
    var sampleTranslations: [String: String] = [:]   // [langId: translatedExample]
    var enrichStatus:       EnrichStatus    = .pending
    var translateStatus:    TranslateStatus = .pending

    enum EnrichStatus: Equatable {
        case pending, enriching, done, failed
    }

    enum TranslateStatus: Equatable {
        case pending, translating, done
    }

    var enrichIcon:  String {
        switch enrichStatus {
        case .pending:   "circle"
        case .enriching: "arrow.trianglehead.clockwise"
        case .done:      "checkmark.circle.fill"
        case .failed:    "exclamationmark.circle"
        }
    }

    var enrichColor: Color {
        switch enrichStatus {
        case .pending:   .secondary
        case .enriching: .blue
        case .done:      .green
        case .failed:    .orange
        }
    }
}

// MARK: - ImportCardsSheet

struct ImportCardsSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss)       private var dismiss

    let setId: String

    /// Topic context added to each word before translation so Apple Translation picks the right meaning.
    private var setContext: String? {
        guard let set = store.cardSets.first(where: { $0.id == setId }) else { return nil }
        let collection = store.collections.first(where: { $0.id == set.collectionId })
        if let col = collection {
            return "\(col.name) — \(set.name)"
        }
        return set.name
    }

    // MARK: State

    @State private var pasteText:   String        = ""
    @State private var tagText:     String        = ""
    @State private var drafts:      [ImportDraft] = []
    @State private var step:        Step          = .paste
    @State private var isEnriching: Bool          = false
    @State private var enrichTask:  Task<Void, Never>?

    // Translation state
    @State private var isTranslating:        Bool                              = false
    @State private var translationConfig:    TranslationSession.Configuration? = nil
    @State private var currentLang:          NativeLanguage?                   = nil
    @State private var pendingLangs:         [NativeLanguage]                  = []
    @State private var translatedLangCount:  Int                               = 0

    private enum Step { case paste, review }

    private let dictionaryService = DictionaryService()

    // MARK: Computed

    private var enrichedCount: Int {
        drafts.filter { $0.enrichStatus == .done || $0.enrichStatus == .failed }.count
    }
    private var enrichProgress: Double {
        drafts.isEmpty ? 0 : Double(enrichedCount) / Double(drafts.count)
    }
    private var translateProgress: Double {
        Double(translatedLangCount) / Double(NativeLanguage.allCases.count)
    }
    private var isAnyOperationRunning: Bool { isEnriching || isTranslating }

    private var wordCount: Int {
        parseWords(from: pasteText).count
    }

    private func parseWords(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .paste:  pasteView
                case .review: reviewView
                }
            }
            .navigationTitle(step == .paste ? "Import Cards" : "Review & Enrich")
            .toolbar { toolbarItems }
        }
        .frame(minWidth: 560, minHeight: 500)
        .onDisappear {
            enrichTask?.cancel()
            translationConfig = nil
        }
        .translationTask(translationConfig) { session in
            await runTranslationBatch(session: session)
        }
    }

    // MARK: — Step 1: Paste

    private var pasteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste words or phrases — one per line or comma-separated:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Text("Tag:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. Family Members", text: $tagText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text(wordCount == 0 ? "No words" : "\(wordCount) word\(wordCount == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Parse →") { parseDrafts() }
                    .buttonStyle(.borderedProminent)
                    .disabled(wordCount == 0)
            }
        }
        .padding()
    }

    // MARK: — Step 2: Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            progressBars
            List(drafts) { draft in DraftRow(draft: draft) }
            Divider()
            bottomBar
        }
    }

    @ViewBuilder
    private var progressBars: some View {
        if isEnriching || enrichedCount > 0 || isTranslating || translatedLangCount > 0 {
            VStack(spacing: 8) {
                if isEnriching || enrichedCount > 0 {
                    LabeledProgressRow(
                        label: "Enriched",
                        value: enrichProgress,
                        detail: "\(enrichedCount)/\(drafts.count)"
                    )
                }
                if isTranslating || translatedLangCount > 0 {
                    LabeledProgressRow(
                        label: "Translated",
                        value: translateProgress,
                        detail: "\(translatedLangCount)/\(NativeLanguage.allCases.count) languages"
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("← Back") {
                enrichTask?.cancel()
                isEnriching = false
                translationConfig = nil
                isTranslating = false
                step = .paste
            }
            .disabled(isAnyOperationRunning)

            Spacer()

            // Enrich button
            if !isEnriching && enrichedCount < drafts.count {
                Button("Enrich All") { startEnrichment() }
                    .buttonStyle(.bordered)
                    .disabled(isTranslating)
            }
            if isEnriching {
                Button("Stop Enrich") {
                    enrichTask?.cancel()
                    isEnriching = false
                }
                .foregroundStyle(.red)
            }

            // Translate button — доступен только после завершения Enrich
            if enrichedCount == drafts.count && !isTranslating && translatedLangCount < NativeLanguage.allCases.count {
                Button("Translate All") { startTranslation() }
                    .buttonStyle(.bordered)
            }
            if isTranslating {
                Button("Stop Translate") {
                    isTranslating = false
                    translationConfig = nil
                    pendingLangs = []
                }
                .foregroundStyle(.red)
            }

            Button("Import \(drafts.count) Cards") { importCards() }
                .buttonStyle(.borderedProminent)
                .disabled(isAnyOperationRunning)
        }
        .padding()
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                enrichTask?.cancel()
                translationConfig = nil
                dismiss()
            }
        }
    }

    // MARK: — Parse

    private func parseDrafts() {
        var seen = Set<String>()
        drafts = parseWords(from: pasteText)
            .compactMap { word in
                let lower = word.lowercased()
                guard !seen.contains(lower) else { return nil }
                seen.insert(lower)
                return ImportDraft(word: word)
            }
        step = .review
    }

    // MARK: — Enrich (MW + FreeDictionary)

    private func startEnrichment() {
        isEnriching = true
        for i in drafts.indices where drafts[i].enrichStatus != .done {
            drafts[i].enrichStatus = .pending
        }

        enrichTask = Task {
            let batchSize = 5
            var idx = 0
            while idx < drafts.count {
                guard !Task.isCancelled else { break }
                let end = min(idx + batchSize, drafts.count)
                for i in idx..<end {
                    guard !Task.isCancelled else { break }
                    let word = drafts[i].word
                    let isPhrase = word.contains(" ")

                    // Фразы: словарный lookup не имеет смысла — сразу done
                    if isPhrase {
                        await MainActor.run { drafts[i].enrichStatus = .done }
                        continue
                    }

                    await MainActor.run { drafts[i].enrichStatus = .enriching }
                    do {
                        let entry = try await dictionaryService.lookup(word: word)
                        await MainActor.run {
                            drafts[i].transcription = entry.transcription
                            if let example = bestExample(from: entry) {
                                drafts[i].sampleEN = [example]
                            }
                            drafts[i].enrichStatus = .done
                        }
                    } catch {
                        await MainActor.run { drafts[i].enrichStatus = .failed }
                    }
                }
                idx = end
                if idx < drafts.count && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            await MainActor.run { isEnriching = false }
        }
    }

    // MARK: — Best example selection

    /// Picks the most contextually relevant example from all dictionary meanings.
    /// Scores each definition by how many set-context keywords appear in its text + example.
    /// Falls back to the first available example if no keyword match is found.
    private func bestExample(from entry: DictionaryEntry) -> String? {
        let contextKeywords = contextKeywords()

        // Collect all definitions that have an example
        let candidates: [(score: Int, example: String)] = entry.meanings.flatMap { meaning in
            meaning.definitions.compactMap { def -> (Int, String)? in
                guard let example = def.example else { return nil }
                guard !example.isEmpty else { return nil }
                let haystack = (def.text + " " + example).lowercased()
                let score = contextKeywords.reduce(0) { $0 + (haystack.contains($1) ? 1 : 0) }
                return (score, example)
            }
        }

        // Best scoring candidate, fallback to first
        return candidates.max(by: { $0.score < $1.score })?.example
            ?? candidates.first?.example
    }

    /// Splits the set context string into lowercase keywords for scoring.
    private func contextKeywords() -> [String] {
        guard let ctx = setContext else { return [] }
        let stopWords: Set<String> = ["and", "the", "a", "an", "of", "in", "&", "—", "-"]
        return ctx
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    // MARK: — Translate (Apple Translation)

    private func startTranslation() {
        translatedLangCount = 0
        isTranslating = true

        // Сбрасываем статусы переводов
        for i in drafts.indices {
            drafts[i].translations = [:]
            drafts[i].sampleTranslations = [:]
            drafts[i].translateStatus = .pending
        }

        var allLangs = NativeLanguage.allCases
        let first = allLangs.removeFirst()
        pendingLangs  = allLangs
        currentLang   = first
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: first.translationLocaleId)
        )
    }

    private func runTranslationBatch(session: TranslationSession) async {
        guard let lang = currentLang, isTranslating else { return }

        // Строим батч: слово (с контекстом темы) + пример (если есть)
        // clientIdentifier: "w_<idx>" для слова, "s_<idx>" для примера
        let context = setContext
        var requests: [TranslationSession.Request] = []
        for (i, draft) in drafts.enumerated() {
            let wordSource = context.map { "\(draft.word) (\($0))" } ?? draft.word
            requests.append(.init(sourceText: wordSource, clientIdentifier: "w_\(i)"))
            if let sample = draft.sampleEN.first, !sample.isEmpty {
                requests.append(.init(sourceText: sample, clientIdentifier: "s_\(i)"))
            }
        }

        do {
            let responses = try await session.translations(from: requests)
            await MainActor.run {
                for response in responses {
                    guard let key = response.clientIdentifier else { continue }
                    if key.hasPrefix("w_"), let idx = Int(key.dropFirst(2)) {
                        // Strip any context the translation engine may have echoed back
                        let raw = response.targetText
                        let cleaned = raw.components(separatedBy: " (").first ?? raw
                        drafts[idx].translations[lang.langId] = cleaned
                    } else if key.hasPrefix("s_"), let idx = Int(key.dropFirst(2)) {
                        drafts[idx].sampleTranslations[lang.langId] = response.targetText
                    }
                }
                for i in drafts.indices {
                    drafts[i].translateStatus = .done
                }
            }
        } catch {
            // Язык не доступен — пропускаем
            log("Translation failed for \(lang.langId): \(error)", level: .warning)
        }

        // Переходим к следующему языку
        await MainActor.run {
            translatedLangCount += 1
            if let nextLang = pendingLangs.first, isTranslating {
                pendingLangs.removeFirst()
                currentLang = nextLang
                translationConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: nextLang.translationLocaleId)
                )
            } else {
                isTranslating     = false
                translationConfig = nil
                currentLang       = nil
            }
        }
    }

    // MARK: — Import

    private func importCards() {
        let tag = tagText.trimmingCharacters(in: .whitespaces)

        for draft in drafts {
            var sampleTranslationsDict: [String: [String]] = [:]
            for (langId, sample) in draft.sampleTranslations {
                sampleTranslationsDict[langId] = [sample]
            }
            let card = FSCard(
                id:                 FirestoreID.make(name: draft.word),
                setId:              setId,
                en:                 draft.word,
                transcription:      draft.transcription,
                translations:       draft.translations,
                sampleEN:           draft.sampleEN,
                sampleTranslations: sampleTranslationsDict,
                tag:                tag,
                updatedAt:          .now,
                createdAt:          .now
            )
            store.add(card)
        }
        dismiss()
    }
}

// MARK: - LabeledProgressRow

private struct LabeledProgressRow: View {
    let label:  String
    let value:  Double
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            ProgressView(value: value)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
    }
}

// MARK: - DraftRow

private struct DraftRow: View {

    let draft: ImportDraft

    var body: some View {
        HStack(spacing: 12) {
            // Статус обогащения
            Image(systemName: draft.enrichIcon)
                .foregroundStyle(draft.enrichColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(draft.word).font(.body.weight(.medium))
                    if !draft.transcription.isEmpty {
                        Text("[\(draft.transcription)]")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let example = draft.sampleEN.first {
                    Text(example)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Статус переводов
            if draft.translateStatus == .done {
                let count = draft.translations.count
                Text("\(count) lang\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if draft.enrichStatus == .enriching {
                ProgressView().scaleEffect(0.7).frame(width: 20)
            }
        }
        .padding(.vertical, 2)
    }
}
