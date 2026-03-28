import SwiftUI
import SwiftData
import Translation

// MARK: - DictionaryLookupViewModel

@Observable
final class DictionaryLookupViewModel {

    // MARK: Phase

    enum Phase {
        case loading
        case loaded(DictionaryEntry)
        case error(String)
    }

    // MARK: State

    private(set) var phase: Phase = .loading

    /// Shows a cached entry immediately (called from the View's .task before the network fetch).
    func showCached(_ entry: DictionaryEntry) {
        phase = .loaded(entry)
    }
    let audioService = AudioPlayerService()

    /// Flips true the moment a successful entry is loaded — used for caching trigger.
    private(set) var didLoad = false

    // MARK: Service

    private let service = DictionaryService()

    // MARK: - Language helpers

    /// Maps display name ("Русский", "Español" …) → BCP-47 identifier used by Translation framework.
    static func targetLangId(for nativeLanguage: String) -> String {
        switch nativeLanguage {
        case "Русский":   return "ru"
        case "中文":       return "zh"
        case "Español":   return "es"
        case "Français":  return "fr"
        case "العربية":   return "ar"
        case "Português": return "pt"
        case "Deutsch":   return "de"
        case "日本語":     return "ja"
        default:          return String(nativeLanguage.prefix(2)).lowercased()
        }
    }

    // MARK: Actions

    func load(word: String) async {
        phase = .loading
        do {
            let entry = try await service.lookup(word: word)
            phase = .loaded(entry)
            didLoad = true
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func toggleAudio(urlString: String) {
        if audioService.isPlaying {
            audioService.stop()
        } else {
            audioService.play(urlString: urlString)
        }
    }

    // MARK: - Card mutation
    //
    // Context and card are passed explicitly — same pattern as SRSService / PileBuilderViewModel.
    // Using do-catch instead of try? so errors are visible in the console.

    /// Keys of texts already added in this session — drives the ✓ indicator in the UI.
    private(set) var addedItems: Set<String> = []

    func addDefinition(
        _ definition: DictionaryDefinition,
        to card: Card,
        context: ModelContext,
        translatedText: String? = nil,
        translatedExample: String? = nil
    ) {
        var samplesEN   = card.sampleEN
        var samplesItem = card.sampleItem
        var changed = false

        if !samplesEN.contains(definition.text) {
            samplesEN.append(definition.text)
            samplesItem.append(translatedText ?? "")
            changed = true
            log("[+] definition: \"\(definition.text.prefix(60))\"")
            if let t = translatedText { log("    translation: \"\(t.prefix(60))\"") }
        }
        if let example = definition.example, !samplesEN.contains(example) {
            samplesEN.append(example)
            samplesItem.append(translatedExample ?? "")
            changed = true
            log("[+] example: \"\(example.prefix(60))\"")
            if let t = translatedExample { log("    translation: \"\(t.prefix(60))\"") }
        }

        guard changed else {
            log("[+] already present — skipped")
            return
        }

        card.sampleEN   = samplesEN
        card.sampleItem = samplesItem
        save(context: context)
        addedItems.insert(definition.text)
    }

    func addSynonym(_ synonym: String, to card: Card, context: ModelContext) {
        var syns = card.synonyms
        guard !syns.contains(synonym) else {
            log("[+] '\(synonym)' already present — skipped")
            return
        }
        syns.append(synonym)
        card.synonyms = syns
        save(context: context)
        addedItems.insert(synonym)
        log("[+] synonym: '\(synonym)'")
    }

    private func save(context: ModelContext) {
        do {
            try context.save()
            log("context.save() OK", level: .info)
        } catch {
            log("context.save() failed: \(error)", level: .error)
        }
    }
}

// MARK: - DictionaryLookupView

struct DictionaryLookupView: View {

    let card: Card

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = DictionaryLookupViewModel()

    // Reads native language from the same AppStorage key used across the app.
    @AppStorage("nativeLanguage") private var nativeLanguage = "Русский"

    // Translation session — prepared once (or re-prepared if language changes) via .translationTask.
    // Simulator does not support Translation — config stays nil to suppress the error dialog.
    @State private var translationSession: TranslationSession?
    @State private var translationConfig: TranslationSession.Configuration?

    private func buildTranslationConfig() {
        #if !targetEnvironment(simulator)
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: DictionaryLookupViewModel.targetLangId(for: nativeLanguage))
        )
        #endif
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    loadingView
                case .loaded(let entry):
                    entryScrollView(entry)
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle(card.en.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Show cached transcription instantly while fetching full entry
            if !card.dictTranscription.isEmpty {
                viewModel.showCached(
                    DictionaryEntry(
                        word: card.en,
                        transcription: card.dictTranscription,
                        audioURL: card.dictAudioURL,
                        meanings: card.dictDefinition.isEmpty ? [] : [
                            DictionaryMeaning(
                                partOfSpeech: "",
                                definitions: [DictionaryDefinition(text: card.dictDefinition, example: nil)],
                                synonyms: []
                            )
                        ]
                    )
                )
            }
            // Always fetch fresh data
            await viewModel.load(word: card.en)
        }
        .onChange(of: viewModel.didLoad) { _, loaded in
            if loaded, case .loaded(let entry) = viewModel.phase {
                cacheEntry(entry)
            }
        }
        .onAppear {
            buildTranslationConfig()
        }
        .onChange(of: nativeLanguage) { _, _ in
            // Rebuild session when user changes native language in Settings.
            translationSession = nil
            buildTranslationConfig()
        }
        .onDisappear {
            viewModel.audioService.stop()
        }
        // Prepare translation session for selected target language.
        .translationTask(translationConfig) { session in
            translationSession = session
        }
    }

    // MARK: - Translation helper

    /// Translates definition + optional example in one batch call.
    /// Falls back silently (empty strings) if session unavailable or translation fails.
    private func translate(_ definition: DictionaryDefinition) async -> (text: String?, example: String?) {
        guard let session = translationSession else { return (nil, nil) }
        do {
            var requests: [TranslationSession.Request] = [
                TranslationSession.Request(sourceText: definition.text, clientIdentifier: "def")
            ]
            if let ex = definition.example {
                requests.append(TranslationSession.Request(sourceText: ex, clientIdentifier: "ex"))
            }
            let responses = try await session.translations(from: requests)
            let text    = responses.first { $0.clientIdentifier == "def" }?.targetText
            let example = responses.first { $0.clientIdentifier == "ex" }?.targetText
            return (text, example)
        } catch {
            log("Translation failed: \(error)", level: .warning)
            return (nil, nil)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Looking up \"\(card.en)\"…")
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Not found")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.myColors.mySecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await viewModel.load(word: card.en) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry scroll view

    private func entryScrollView(_ entry: DictionaryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerCard(entry)
                ForEach(entry.meanings.indices, id: \.self) { idx in
                    meaningSection(entry.meanings[idx])
                }
            }
            .padding()
        }
    }

    // MARK: - Header: word + transcription + audio

    private func headerCard(_ entry: DictionaryEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.word)
                    .font(.largeTitle.bold())
                if !entry.transcription.isEmpty {
                    Text(entry.transcription)
                        .font(.title3)
                        .foregroundStyle(Color.myColors.mySecondary)
                }
            }
            Spacer()
            if !entry.audioURL.isEmpty {
                Button {
                    viewModel.toggleAudio(urlString: entry.audioURL)
                } label: {
                    Image(systemName: viewModel.audioService.isPlaying
                          ? "stop.circle"
                          : "speaker.wave.2.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(viewModel.audioService.isPlaying ? "Stop audio" : "Play pronunciation")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Meaning section

    private func meaningSection(_ meaning: DictionaryMeaning) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !meaning.partOfSpeech.isEmpty {
                Text(meaning.partOfSpeech)
                    .font(.caption.uppercaseSmallCaps())
                    .foregroundStyle(Color.myColors.mySecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
            }

            ForEach(meaning.definitions.prefix(3).indices, id: \.self) { idx in
                definitionRow(meaning.definitions[idx])
            }

            if !meaning.synonyms.isEmpty {
                synonymsSection(meaning.synonyms)
            }

            Divider()
        }
    }

    // MARK: - Definition row

    private func definitionRow(_ definition: DictionaryDefinition) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(definition.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let example = definition.example {
                    Text("\"\(example)\"")
                        .font(.subheadline)
                        .foregroundStyle(Color.myColors.mySecondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            // [+] adds the definition (+ example) to card.sampleEN / sampleItem with translation
            let alreadyAdded = viewModel.addedItems.contains(definition.text) || card.sampleEN.contains(definition.text)
            Button {
                Task {
                    let (translatedText, translatedExample) = await translate(definition)
                    viewModel.addDefinition(
                        definition, to: card, context: context,
                        translatedText: translatedText,
                        translatedExample: translatedExample
                    )
                }
            } label: {
                Image(systemName: alreadyAdded ? "checkmark.circle" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(alreadyAdded ? Color.green : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(alreadyAdded ? "Added" : "Add to card examples")
        }
        .padding(.leading, 4)
    }

    // MARK: - Synonyms section

    private func synonymsSection(_ synonyms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synonyms")
                .font(.caption)
            DictionaryFlowLayout(spacing: 8) {
                ForEach(synonyms, id: \.self) { synonym in
                    synonymChip(synonym)
                }
            }
        }
    }

    private func synonymChip(_ synonym: String) -> some View {
        HStack(spacing: 4) {
            Text(synonym)
                .font(.subheadline)
            let synonymAdded = viewModel.addedItems.contains(synonym) || card.synonyms.contains(synonym)
            Button {
                viewModel.addSynonym(synonym, to: card, context: context)
            } label: {
                Image(systemName: synonymAdded ? "checkmark.circle" : "plus.circle")
                    .font(.caption)
                    .foregroundStyle(synonymAdded ? Color.green : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(synonymAdded ? "Added" : "Add \(synonym) to card")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Cache entry to Card

    private func cacheEntry(_ entry: DictionaryEntry) {
        card.dictTranscription = entry.transcription
        card.dictAudioURL      = entry.audioURL
        card.dictDefinition    = entry.meanings.first?.definitions.first?.text ?? ""
        try? context.save()
        log("cached to card '\(card.en)':")
        log("  transcription : '\(card.dictTranscription)'")
        log("  audioURL      : '\(card.dictAudioURL)'")
        log("  definition    : '\(card.dictDefinition.prefix(60))…'")
        log("  audioButton visible: \(!card.dictAudioURL.isEmpty)")
    }
}

// MARK: - DictionaryFlowLayout
//
// Wraps chips to a new row when the current row is full.
// Named with "Dictionary" prefix to avoid collision with other Layout types.

private struct DictionaryFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
