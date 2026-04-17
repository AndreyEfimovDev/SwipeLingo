import SwiftUI

// MARK: - ImportPairsSheet
//
// Sheet для массового импорта пар из plain text.
// Формат: "left | right" — одна пара на строку.
// Разделитель по умолчанию "|", можно изменить в поле Separator.

struct ImportPairsSheet: View {

    @Environment(\.dismiss) private var dismiss

    let leftTitle:  String
    let rightTitle: String
    let onImport:   ([FSPair]) -> Void

    // MARK: State

    @State private var pasteText: String    = ""
    @State private var separator: String    = "|"
    @State private var drafts:    [PairDraft] = []
    @State private var step:      Step      = .paste

    private enum Step { case paste, review }

    private struct PairDraft: Identifiable {
        let id   = UUID()
        var left:  String
        var right: String
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
        .frame(minWidth: 520, minHeight: 440)
    }

    // MARK: — Step 1: Paste

    private var pasteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Hint
            HStack(spacing: 6) {
                Text("Format:")
                    .foregroundStyle(.secondary)
                Text("\(leftTitle)  \(separator)  \(rightTitle)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .font(.subheadline)

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
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                let parts = trimmed.components(separatedBy: sep)
                return parts.count >= 2 &&
                       !parts[0].trimmingCharacters(in: .whitespaces).isEmpty
            }
            .count
    }

    // MARK: — Step 2: Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            // Заголовки колонок
            HStack {
                Text(leftTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(rightTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            List(drafts) { draft in
                HStack(spacing: 0) {
                    Text(draft.left)
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                    Text(draft.right.isEmpty ? "—" : draft.right)
                        .font(.body)
                        .foregroundStyle(draft.right.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Button("← Back") {
                    step = .paste
                }
                Spacer()
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
            .components(separatedBy: "\n")
            .compactMap { line -> PairDraft? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.components(separatedBy: sep)
                let left  = parts[0].trimmingCharacters(in: .whitespaces)
                let right = parts.count >= 2 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                guard !left.isEmpty else { return nil }
                // Дедупликация по левой части
                let key = left.lowercased()
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return PairDraft(left: left, right: right)
            }
        step = .review
    }

    // MARK: — Import

    private func importPairs() {
        let pairs: [FSPair] = drafts.map { draft in
            FSPair(
                id:    UUID().uuidString,
                left:  FSPairSide(text: draft.left),
                right: draft.right.isEmpty ? nil : FSPairSide(text: draft.right)
            )
        }
        onImport(pairs)
        dismiss()
    }
}
