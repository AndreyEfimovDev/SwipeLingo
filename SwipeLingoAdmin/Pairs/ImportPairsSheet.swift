import SwiftUI

// MARK: - ImportPairsSheet
//
// Sheet для массового импорта пар из plain text.
// Формат строки зависит от выбранного PairType — разделитель "|".
//
// PairType → колонки:
//   classic:                 left | right
//   pairsWithSample:         left | right | sample
//   leftSample:              left | sample
//   leftDescriptionSample:   left | description | sample

struct ImportPairsSheet: View {

    @Environment(\.dismiss) private var dismiss

    let onImport: ([FSPair]) -> Void

    // MARK: State

    @State private var pasteText:    String      = ""
    @State private var separator:    String      = "|"
    @State private var tag:          String      = ""
    @State private var leftTitle:    String      = ""
    @State private var rightTitle:   String      = ""
    @State private var pairType:     PairType    = .classic
    @State private var displayMode:  DisplayMode = .parallel
    @State private var drafts:    [PairDraft] = []
    @State private var step:      Step      = .paste

    private enum Step { case paste, review }

    // MARK: Pair type

    private enum PairType: String, CaseIterable, Identifiable {
        case classic               = "Classic"
        case pairsWithSample       = "Pairs + Sample"
        case leftSample            = "Left + Sample"
        case leftDescriptionSample = "Left + Desc + Sample"

        var id: String { rawValue }

        var columnHint: String {
            switch self {
            case .classic:               "word  |  synonym"
            case .pairsWithSample:       "word  |  synonym  |  example sentence"
            case .leftSample:            "word  |  example sentence"
            case .leftDescriptionSample: "word  |  definition  |  example sentence"
            }
        }

        var columnCount: Int {
            switch self {
            case .classic:               2
            case .pairsWithSample:       3
            case .leftSample:            2
            case .leftDescriptionSample: 3
            }
        }
    }

    // MARK: Draft

    private struct PairDraft: Identifiable {
        let id          = UUID()
        var left:        String
        var right:       String
        var description: String
        var sample:      String
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
            .navigationTitle(step == .paste ? "Import Pairs" : "Review Pairs")
            .toolbar { toolbarItems }
        }
        .frame(minWidth: 540, minHeight: 480)
    }

    // MARK: — Step 1: Paste

    private var pasteView: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Pair type picker
            HStack(spacing: 8) {
                Text("Type:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $pairType) {
                    ForEach(PairType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Format hint
            HStack(spacing: 6) {
                Text("Format:")
                    .foregroundStyle(.secondary)
                Text(pairType.columnHint)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .font(.subheadline)

            // Group name
            HStack(spacing: 8) {
                Text("Group:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Group name (optional)", text: $tag)
                    .textFieldStyle(.roundedBorder)
            }

            // Column titles + display mode — только для classic и pairsWithSample
            if pairType == .classic || pairType == .pairsWithSample {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Left title:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("e.g. B2, Informal", text: $leftTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 8) {
                        Text("Right title:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("e.g. C1, Formal", text: $rightTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack(spacing: 8) {
                    Text("Display mode:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $displayMode) {
                        Text("Parallel").tag(DisplayMode.parallel)
                        Text("Sequential").tag(DisplayMode.sequential)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }

            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Separator:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $separator)
                        .frame(width: 36)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Text(pairCount == 0 ? "No pairs" : "\(pairCount) pair\(pairCount == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Parse →") { parseDrafts() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairCount == 0)
            }
        }
        .padding()
    }

    private var pairCount: Int {
        let sep = separator.isEmpty ? "|" : separator
        return pasteText
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                let parts = trimmed.components(separatedBy: sep)
                return parts.count >= pairType.columnCount &&
                       !parts[0].trimmingCharacters(in: .whitespaces).isEmpty
            }
            .count
    }

    // MARK: — Step 2: Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("Left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Right / Description / Sample")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            List(drafts) { draft in
                HStack(alignment: .top, spacing: 0) {
                    Text(draft.left)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        if !draft.right.isEmpty {
                            Text(draft.right)
                                .font(.body)
                        }
                        if !draft.description.isEmpty {
                            Text(draft.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !draft.sample.isEmpty {
                            Text(draft.sample)
                                .font(.subheadline.italic())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Button("← Back") { step = .paste }
                Spacer()
                if !tag.isEmpty {
                    Text("Group: \(tag)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(drafts.count) pair\(drafts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Import \(drafts.count) Pairs") { importPairs() }
                    .buttonStyle(.borderedProminent)
                    .disabled(drafts.isEmpty)
            }
            .padding()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: — Parse

    private func parseDrafts() {
        let sep = separator.isEmpty ? "|" : separator
        var seen = Set<String>()

        drafts = pasteText
            .components(separatedBy: .newlines)
            .compactMap { line -> PairDraft? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.components(separatedBy: sep).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let left = parts[0]
                guard !left.isEmpty else { return nil }
                let key = left.lowercased()
                guard !seen.contains(key) else { return nil }
                seen.insert(key)

                switch pairType {
                case .classic:
                    let right = parts.count >= 2 ? parts[1] : ""
                    return PairDraft(left: left, right: right, description: "", sample: "")

                case .pairsWithSample:
                    let right  = parts.count >= 2 ? parts[1] : ""
                    let sample = parts.count >= 3 ? parts[2] : ""
                    return PairDraft(left: left, right: right, description: "", sample: sample)

                case .leftSample:
                    let sample = parts.count >= 2 ? parts[1] : ""
                    return PairDraft(left: left, right: "", description: "", sample: sample)

                case .leftDescriptionSample:
                    let desc   = parts.count >= 2 ? parts[1] : ""
                    let sample = parts.count >= 3 ? parts[2] : ""
                    return PairDraft(left: left, right: "", description: desc, sample: sample)
                }
            }
        step = .review
    }

    // MARK: — Import

    private func importPairs() {
        let trimmedTag   = tag.trimmingCharacters(in: .whitespaces)
        let trimmedLeft  = leftTitle.trimmingCharacters(in: .whitespaces)
        let trimmedRight = rightTitle.trimmingCharacters(in: .whitespaces)

        // Заголовки колонок и displayMode — только для classic и pairsWithSample
        let hasColumns = pairType == .classic || pairType == .pairsWithSample
        let colLeft:  String? = hasColumns && !trimmedLeft.isEmpty  ? trimmedLeft  : nil
        let colRight: String? = hasColumns && !trimmedRight.isEmpty ? trimmedRight : nil
        let colMode:  DisplayMode = hasColumns ? displayMode : .sequential

        let pairs: [FSPair] = drafts.map { draft in
            FSPair(
                id:          UUID().uuidString,
                left:        draft.left.isEmpty        ? nil : draft.left,
                right:       draft.right.isEmpty       ? nil : draft.right,
                description: draft.description.isEmpty ? nil : draft.description,
                sample:      draft.sample.isEmpty      ? nil : draft.sample,
                tag:         trimmedTag,
                leftTitle:   colLeft,
                rightTitle:  colRight,
                displayMode: colMode
            )
        }
        onImport(pairs)
        dismiss()
    }
}
