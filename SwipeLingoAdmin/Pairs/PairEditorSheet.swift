import SwiftUI

// MARK: - PairGroupType
//
// Тип группы определяет, какие поля пары используются.
// Выводится автоматически из полей пары или передаётся явно (для новых пар).
//
//   classic:          Left + Right
//   pairsWithSample:  Left + Right + Sample
//   leftWithSample:   Left + Sample
//   leftDescSample:   Left + Desc + Sample

enum PairGroupType {
    case classic
    case pairsWithSample
    case leftWithSample
    case leftDescSample

    /// Вывести тип из заполненных полей существующей пары.
    init(from pair: FSPair) {
        if pair.right != nil {
            self = (pair.sample != nil) ? .pairsWithSample : .classic
        } else {
            self = (pair.description != nil) ? .leftDescSample : .leftWithSample
        }
    }

    var showRight:  Bool { self == .classic || self == .pairsWithSample }
    var showDesc:   Bool { self == .leftDescSample }
    var showSample: Bool { self != .classic }
    var showTitles: Bool { self == .classic || self == .pairsWithSample }

    var label: String {
        switch self {
        case .classic:         return "Classic"
        case .pairsWithSample: return "Pairs + Sample"
        case .leftWithSample:  return "Left + Sample"
        case .leftDescSample:  return "Left + Desc + Sample"
        }
    }
}

// MARK: - PairEditorSheet

struct PairEditorSheet: View {

    @Environment(\.dismiss) private var dismiss

    let pair:      FSPair?
    /// Тип группы для нового элемента (pair == nil).
    /// Если nil — показываем все поля.
    let groupType: PairGroupType?
    let onSave:    (FSPair) -> Void

    // MARK: State

    @State private var leftText:       String = ""
    @State private var rightText:      String = ""
    @State private var descText:       String = ""
    @State private var sampleText:     String = ""
    @State private var tagText:        String = ""
    @State private var leftTitleText:  String = ""
    @State private var rightTitleText: String = ""

    private var canSave: Bool {
        !leftText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Тип группы: из пары (при редактировании) или из параметра (при создании).
    /// nil — нет контекста, показываем все поля.
    private var resolvedType: PairGroupType? {
        if let pair { return PairGroupType(from: pair) }
        return groupType
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Тип группы — информационная строка
                    if let type = resolvedType {
                        Text(type.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }

                    // ── Left ──────────────────────────────────────
                    fieldLabel("Left")
                    clearableField("Word or phrase", text: $leftText)

                    // ── Right (только Classic и Pairs + Sample) ───
                    if resolvedType == nil || resolvedType!.showRight {
                        fieldLabel("Right" + (resolvedType == nil ? " (optional)" : ""))
                        clearableField("Synonym / counterpart — short", text: $rightText)
                    }

                    // ── Description (только Left + Desc + Sample) ─
                    if resolvedType == nil || resolvedType!.showDesc {
                        fieldLabel("Description" + (resolvedType == nil ? " (optional)" : ""))
                        clearableField("Definition or explanation — full width", text: $descText)
                    }

                    // ── Sample (все типы кроме Classic) ───────────
                    if resolvedType == nil || resolvedType!.showSample {
                        fieldLabel("Sample sentence" + (resolvedType == nil ? " (optional)" : ""))
                        clearableField("Example sentence", text: $sampleText)
                    }

                    // ── Column titles (только Classic и Pairs + Sample) ──
                    if resolvedType == nil || resolvedType!.showTitles {
                        fieldLabel("Left column title" + (resolvedType == nil ? " (optional)" : ""))
                        clearableField("e.g. Phrase, Verb, …", text: $leftTitleText)

                        fieldLabel("Right column title" + (resolvedType == nil ? " (optional)" : ""))
                        clearableField("e.g. Meaning, Synonym, …", text: $rightTitleText)
                    }

                    // ── Tag / Group ───────────────────────────────
                    fieldLabel("Group (optional)")
                    clearableField("e.g. Morning Routine, Verbs, …", text: $tagText)

                    Spacer()
                }
                .padding(20)
            }
            .frame(minWidth: 420, minHeight: 320)
            .navigationTitle(pair == nil ? "New Pair" : "Edit Pair")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear {
            leftText       = pair?.left        ?? ""
            rightText      = pair?.right       ?? ""
            descText       = pair?.description ?? ""
            sampleText     = pair?.sample      ?? ""
            tagText        = pair?.tag         ?? ""
            leftTitleText  = pair?.leftTitle   ?? ""
            rightTitleText = pair?.rightTitle  ?? ""
        }
    }

    // MARK: Helpers

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

    // MARK: Save

    private func save() {
        let t = resolvedType
        let trimmedLeft       = leftText.trimmingCharacters(in: .whitespaces)
        let trimmedRight      = rightText.trimmingCharacters(in: .whitespaces)
        let trimmedDesc       = descText.trimmingCharacters(in: .whitespaces)
        let trimmedSample     = sampleText.trimmingCharacters(in: .whitespaces)
        let trimmedTag        = tagText.trimmingCharacters(in: .whitespaces)
        let trimmedLeftTitle  = leftTitleText.trimmingCharacters(in: .whitespaces)
        let trimmedRightTitle = rightTitleText.trimmingCharacters(in: .whitespaces)

        let saved = FSPair(
            id:          pair?.id ?? UUID().uuidString,
            left:        trimmedLeft,
            right:       (t == nil || t!.showRight)  ? (trimmedRight.isEmpty  ? nil : trimmedRight)  : nil,
            description: (t == nil || t!.showDesc)   ? (trimmedDesc.isEmpty   ? nil : trimmedDesc)   : nil,
            sample:      (t == nil || t!.showSample) ? (trimmedSample.isEmpty ? nil : trimmedSample) : nil,
            tag:         trimmedTag,
            leftTitle:   (t == nil || t!.showTitles) ? (trimmedLeftTitle.isEmpty  ? nil : trimmedLeftTitle)  : nil,
            rightTitle:  (t == nil || t!.showTitles) ? (trimmedRightTitle.isEmpty ? nil : trimmedRightTitle) : nil,
            displayMode: pair?.displayMode ?? .parallel
        )
        onSave(saved)
    }
}
