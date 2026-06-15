import SwiftUI
import Translation

// MARK: - RetranslateSetSheet
//
// Re-translates all cards in a set using topic context so Apple Translation
// picks the domain-correct meaning (e.g. "browse" → "просматривать" in Internet context).
// Translates EN → each of 17 languages directly.
// 30-second timeout per language — skips if Apple Translation hangs (e.g. language pack missing).

struct RetranslateSetSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss)       private var dismiss

    let setId:   String
    let setName: String

    // MARK: State

    @State private var isTranslating:     Bool                              = false
    @State private var isDone:            Bool                              = false
    @State private var translatedCount:   Int                               = 0
    @State private var currentLang:       NativeLanguage?                   = nil
    @State private var pendingLangs:      [NativeLanguage]                  = []
    @State private var translationConfig: TranslationSession.Configuration? = nil
    @State private var updatedCards:      [FSCard]                          = []

    // MARK: Computed

    private var cards: [FSCard] { store.cards(for: setId) }

    private var progress: Double {
        guard !NativeLanguage.allCases.isEmpty else { return 0 }
        return Double(translatedCount) / Double(NativeLanguage.allCases.count)
    }

    private var setContext: String {
        guard let set = store.cardSets.first(where: { $0.id == setId }) else { return setName }
        if let col = store.collections.first(where: { $0.id == set.collectionId }) {
            return "\(col.name) — \(set.name)"
        }
        return set.name
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isDone {
                    doneView
                } else {
                    infoView
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Re-translate Set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isTranslating)
                }
            }
        }
        .translationTask(translationConfig) { session in
            Task {
                // Race: translation vs 30-second timeout
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await applyBatch(session: session) }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        log("RetranslateSet: timeout for \(currentLang?.langId ?? "?")", level: .warning)
                    }
                    await group.next()   // first to finish wins
                    group.cancelAll()
                }
                // Always advance to next language regardless of timeout or success
                await MainActor.run { advanceToNextLang() }
            }
        }
    }

    // MARK: - Info / progress view

    private var infoView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set: \(setName)")
                    .font(.headline)
                Text("Cards: \(cards.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Context: \(setContext)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Text("Each word will be translated as:\n\"\(cards.first.map { "\($0.en) (\(setContext))" } ?? "word (context)")\"")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isTranslating {
                VStack(alignment: .leading, spacing: 8) {
                    if let lang = currentLang {
                        Text("Translating: \(lang.displayName)…")
                            .font(.subheadline)
                    }
                    ProgressView(value: progress)
                    Text("\(translatedCount) / \(NativeLanguage.allCases.count) languages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Start Re-translation") {
                    startTranslation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(cards.isEmpty)
            }
        }
    }

    // MARK: - Done view

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Done!")
                .font(.title2.bold())
            Text("\(updatedCards.count) cards updated and saved to Firebase.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Translation logic

    private func startTranslation() {
        updatedCards = cards
        translatedCount = 0
        isDone = false
        isTranslating = true

        var langs = NativeLanguage.allCases
        let first = langs.removeFirst()
        pendingLangs = langs
        currentLang  = first
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: first.translationLocaleId)
        )
    }

    /// Sends requests to Apple Translation and writes results into updatedCards.
    /// Does NOT advance to the next language — caller does that after this returns.
    private func applyBatch(session: TranslationSession) async {
        guard let lang = currentLang else { return }

        let context = setContext
        var requests: [TranslationSession.Request] = []

        for (i, card) in updatedCards.enumerated() {
            let wordSource = "\(card.en) (\(context))"
            requests.append(.init(sourceText: wordSource, clientIdentifier: "w_\(i)"))
            for (j, sample) in card.sampleEN.enumerated() where !sample.isEmpty {
                requests.append(.init(sourceText: sample, clientIdentifier: "s_\(i)_\(j)"))
            }
        }

        do {
            let responses = try await session.translations(from: requests)
            await MainActor.run {
                for response in responses {
                    guard let key = response.clientIdentifier else { continue }
                    if key.hasPrefix("w_"), let idx = Int(key.dropFirst(2)) {
                        let raw = response.targetText
                        let cleaned = raw.components(separatedBy: " (").first
                            .map { $0.trimmingCharacters(in: .whitespaces) } ?? raw
                        updatedCards[idx].translations[lang.langId] = cleaned
                    } else if key.hasPrefix("s_") {
                        let parts = key.dropFirst(2).split(separator: "_")
                        if parts.count == 2, let ci = Int(parts[0]), let si = Int(parts[1]) {
                            var samples = updatedCards[ci].sampleTranslations[lang.langId] ?? []
                            while samples.count <= si { samples.append("") }
                            samples[si] = response.targetText
                            updatedCards[ci].sampleTranslations[lang.langId] = samples
                        }
                    }
                }
            }
        } catch {
            log("RetranslateSet: failed for \(lang.langId): \(error)", level: .warning)
        }
    }

    /// Advances to the next language, or finishes and saves if all languages are done.
    private func advanceToNextLang() {
        translatedCount += 1

        if let next = pendingLangs.first {
            pendingLangs.removeFirst()
            currentLang = next
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: next.translationLocaleId)
            )
        } else {
            isTranslating = false
            translationConfig = nil
            currentLang = nil
            for card in updatedCards {
                store.update(card)
            }
            isDone = true
        }
    }
}
