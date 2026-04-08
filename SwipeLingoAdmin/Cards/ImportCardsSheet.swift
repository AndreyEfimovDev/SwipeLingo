import SwiftUI

// MARK: - ImportDraft

private struct ImportDraft: Identifiable {
    let id = UUID()
    var word:          String
    var transcription: String   = ""
    var sampleEN:      [String] = []
    var status:        Status   = .pending

    enum Status: Equatable {
        case pending
        case enriching
        case done
        case failed
    }

    var statusIcon:  String {
        switch status {
        case .pending:   "circle"
        case .enriching: "arrow.trianglehead.clockwise"
        case .done:      "checkmark.circle.fill"
        case .failed:    "exclamationmark.circle"
        }
    }

    var statusColor: Color {
        switch status {
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
    @Environment(\.dismiss) private var dismiss

    let setId:           String
    let defaultLevel:    CEFRLevel
    let defaultTier:     AccessTier

    // MARK: State

    @State private var pasteText:   String        = ""
    @State private var drafts:      [ImportDraft] = []
    @State private var step:        Step          = .paste
    @State private var isEnriching: Bool          = false
    @State private var enrichTask:  Task<Void, Never>?

    private enum Step { case paste, review }

    private let dictionaryService = DictionaryService()

    // Прогресс обогащения
    private var enrichedCount: Int { drafts.filter { $0.status == .done || $0.status == .failed }.count }
    private var progress: Double  { drafts.isEmpty ? 0 : Double(enrichedCount) / Double(drafts.count) }

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
        .frame(minWidth: 540, minHeight: 480)
        .onDisappear { enrichTask?.cancel() }
    }

    // MARK: Step 1 — Paste

    private var pasteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste one word or phrase per line:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

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

    private var wordCount: Int {
        pasteText.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
    }

    // MARK: Step 2 — Review & Enrich

    private var reviewView: some View {
        VStack(spacing: 0) {
            // Прогресс-бар обогащения
            if isEnriching || enrichedCount > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .padding(.horizontal)
                    Text("Enriched \(enrichedCount) / \(drafts.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }

            // Список черновиков
            List(drafts) { draft in
                DraftRow(draft: draft)
            }

            Divider()

            // Нижняя панель
            HStack(spacing: 12) {
                Button("← Back") {
                    enrichTask?.cancel()
                    isEnriching = false
                    step = .paste
                }
                .disabled(isEnriching)

                Spacer()

                if !isEnriching && enrichedCount < drafts.count {
                    Button("Enrich All") { startEnrichment() }
                        .buttonStyle(.bordered)
                }

                if isEnriching {
                    Button("Stop") {
                        enrichTask?.cancel()
                        isEnriching = false
                    }
                    .foregroundStyle(.red)
                }

                Button("Import \(drafts.count) Cards") { importCards() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isEnriching)
            }
            .padding()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                enrichTask?.cancel()
                dismiss()
            }
        }
    }

    // MARK: Parse

    private func parseDrafts() {
        let words = pasteText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Убираем дубликаты, сохраняем порядок
        var seen = Set<String>()
        drafts = words.compactMap { word in
            let lower = word.lowercased()
            guard !seen.contains(lower) else { return nil }
            seen.insert(lower)
            return ImportDraft(word: word)
        }
        step = .review
    }

    // MARK: Enrich

    private func startEnrichment() {
        isEnriching = true

        // Сбрасываем статусы незавершённых
        for i in drafts.indices where drafts[i].status != .done {
            drafts[i].status = .pending
        }

        enrichTask = Task {
            let batchSize = 5
            let delayBetweenBatches: UInt64 = 1_000_000_000  // 1 секунда

            var idx = 0
            while idx < drafts.count {
                guard !Task.isCancelled else { break }

                let batchEnd = min(idx + batchSize, drafts.count)
                let batchIndices = Array(idx..<batchEnd)

                // Обрабатываем батч последовательно
                for i in batchIndices {
                    guard !Task.isCancelled else { break }

                    await MainActor.run { drafts[i].status = .enriching }

                    do {
                        let entry = try await dictionaryService.lookup(word: drafts[i].word)
                        await MainActor.run {
                            drafts[i].transcription = entry.transcription
                            if let firstDef = entry.meanings.first?.definitions.first,
                               let example = firstDef.example {
                                drafts[i].sampleEN = [example]
                            }
                            drafts[i].status = .done
                        }
                    } catch {
                        await MainActor.run { drafts[i].status = .failed }
                    }
                }

                idx = batchEnd

                // Пауза между батчами
                if idx < drafts.count && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: delayBetweenBatches)
                }
            }

            await MainActor.run { isEnriching = false }
        }
    }

    // MARK: Import

    private func importCards() {
        for draft in drafts {
            let card = FSCard(
                id:           FirestoreID.make(name: draft.word),
                setId:        setId,
                en:           draft.word,
                transcription: draft.transcription,
                translations: [:],
                sampleEN:     draft.sampleEN,
                sampleTranslations: [:],
                level:        defaultLevel.rawValue,
                accessTierRaw: defaultTier.rawValue,
                isPublished:  false,
                updatedAt:    .now,
                createdAt:    .now
            )
            store.add(card)
        }
        dismiss()
    }
}

// MARK: - DraftRow

private struct DraftRow: View {

    let draft: ImportDraft

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.statusIcon)
                .foregroundStyle(draft.statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.word)
                    .font(.body.weight(.medium))

                if !draft.transcription.isEmpty {
                    Text("[\(draft.transcription)]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let example = draft.sampleEN.first {
                    Text(example)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if draft.status == .enriching {
                ProgressView().scaleEffect(0.7).frame(width: 20)
            }
        }
        .padding(.vertical, 2)
    }
}
