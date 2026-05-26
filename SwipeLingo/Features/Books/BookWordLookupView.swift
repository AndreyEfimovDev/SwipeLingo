import SwiftUI
import SwiftData
import Translation

// MARK: - BookWordLookupView
//
// Dictionary lookup triggered by word tap in BookReaderView.
// Unlike DictionaryLookupView (which mutates an existing Card),
// this view can save the word as a new Card into the Inbox CardSet.

struct BookWordLookupView: View {

    let word: String

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context

    @Query private var cardSets: [CardSet]

    @AppStorage(Constants.StorageKey.nativeLanguage)     private var nativeLanguage: NativeLanguage = .russian
    @AppStorage(Constants.StorageKey.ttsVoiceIdentifier) private var ttsVoiceIdentifier = ""
    @AppStorage(Constants.StorageKey.englishVariant)     private var englishVariant = "en-US"

    @State private var viewModel = DictionaryLookupViewModel()
    @State private var savedToInbox = false

    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationSession: TranslationSession?
    @State private var translatedWord = ""

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .loading:
                    loadingView
                case .loaded(let entry):
                    entryView(entry)
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle(word.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await viewModel.load(word: word)
        }
        .onAppear { buildTranslationConfig() }
        .onDisappear { viewModel.audioService.stop() }
        .translationTask(translationConfig) { session in
            translationSession = session
            await translateWord(session: session)
        }
    }

    // MARK: - Entry view

    private func entryView(_ entry: DictionaryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Transcription + audio
                headerView(entry)

                // Definitions
                if !entry.meanings.isEmpty {
                    definitionsSection(entry)
                }

                // Save to Inbox button
                saveButton
            }
            .padding(20)
        }
    }

    private func headerView(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.capitalized)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.myColors.myAccent)
                if !entry.transcription.isEmpty {
                    Text(entry.transcription)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
                }
                if !translatedWord.isEmpty {
                    Text(translatedWord)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.myColors.myBlue)
                }
            }
            Spacer()
            if !entry.audioURL.isEmpty {
                Button {
                    viewModel.toggleAudio(urlString: entry.audioURL)
                } label: {
                    Image(systemName: viewModel.audioService.isPlaying ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(viewModel.audioService.isPlaying ? Color.myColors.myRed : Color.myColors.myBlue)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
    }

    private func definitionsSection(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(entry.meanings, id: \.partOfSpeech) { meaning in
                VStack(alignment: .leading, spacing: 8) {
                    Text(meaning.partOfSpeech)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.myColors.myBlue)
                        .textCase(.uppercase)

                    ForEach(Array(meaning.definitions.prefix(3).enumerated()), id: \.offset) { idx, def in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(idx + 1). \(def.text)")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.myColors.myAccent)
                            if let example = def.example {
                                Text("\"" + example + "\"")
                                    .font(.system(size: 14))
                                    .italic()
                                    .foregroundStyle(Color.myColors.myAccent.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            saveToInbox()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: savedToInbox ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18))
                Text(savedToInbox ? "Saved to Inbox" : "Save to Cards")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(savedToInbox ? Color.myColors.myGreen : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(savedToInbox ? Color.myColors.myGreen.opacity(0.12) : Color.myColors.myBlue,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(savedToInbox ? Color.myColors.myGreen.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(savedToInbox)
        .animation(.easeInOut(duration: 0.2), value: savedToInbox)
    }

    // MARK: - Loading / error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.myColors.myBlue)
            Text("Looking up \"" + word + "\"…")
                .foregroundStyle(Color.myColors.myAccent.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(Color.myColors.myRed.opacity(0.6))
            Text("Couldn't find \"" + word + "\"")
                .font(.headline)
                .foregroundStyle(Color.myColors.myAccent)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                .multilineTextAlignment(.center)

            saveButton
        }
        .padding(32)
    }

    // MARK: - Save to Inbox

    private func saveToInbox() {
        guard let inboxSet = cardSets.first(where: { $0.name == "Inbox" }) else {
            log("[BookLookup] Inbox not found", level: .warning)
            return
        }

        let inboxSetId = inboxSet.id
        let existing = (try? context.fetch(
            FetchDescriptor<Card>(predicate: #Predicate { $0.setId == inboxSetId })
        )) ?? []

        guard !existing.contains(where: { $0.en.lowercased() == word.lowercased() }) else {
            savedToInbox = true
            return
        }

        let card = Card(en: word, item: translatedWord, setId: inboxSet.id)
        context.insert(card)
        context.saveWithErrorHandling()
        savedToInbox = true
        log("[BookLookup] Saved '\(word)' to Inbox", level: .info)
    }

    // MARK: - Translation

    private func buildTranslationConfig() {
        #if !targetEnvironment(simulator)
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: nativeLanguage.langId)
        )
        #endif
    }

    private func translateWord(session: TranslationSession) async {
        do {
            let request   = TranslationSession.Request(sourceText: word, clientIdentifier: "word")
            let responses = try await session.translations(from: [request])
            translatedWord = responses.first?.targetText ?? ""
        } catch {
            log("[BookLookup] Translation failed: \(error)", level: .warning)
        }
    }
}
