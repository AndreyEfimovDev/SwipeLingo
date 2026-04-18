import SwiftUI

// MARK: - PairEditorSheet

struct PairEditorSheet: View {

    @Environment(\.dismiss) private var dismiss

    let pair:   FSPair?
    let onSave: (FSPair) -> Void

    // MARK: State

    @State private var leftText:   String = ""
    @State private var rightText:  String = ""
    @State private var descText:   String = ""
    @State private var sampleText: String = ""
    @State private var tagText:    String = ""

    private var canSave: Bool {
        !leftText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Left ──────────────────────────────────────
                    fieldLabel("Left")
                    clearableField("Word or phrase", text: $leftText)

                    // ── Right (optional) ──────────────────────────
                    fieldLabel("Right (optional)")
                    clearableField("Synonym / counterpart — short", text: $rightText)

                    // ── Description (optional) ────────────────────
                    fieldLabel("Description (optional)")
                    clearableField("Definition or explanation — full width", text: $descText)

                    // ── Sample (optional) ─────────────────────────
                    fieldLabel("Sample sentence (optional)")
                    clearableField("Example sentence", text: $sampleText)

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
            leftText   = pair?.left        ?? ""
            rightText  = pair?.right       ?? ""
            descText   = pair?.description ?? ""
            sampleText = pair?.sample      ?? ""
            tagText    = pair?.tag         ?? ""
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
        let trimmedLeft   = leftText.trimmingCharacters(in: .whitespaces)
        let trimmedRight  = rightText.trimmingCharacters(in: .whitespaces)
        let trimmedDesc   = descText.trimmingCharacters(in: .whitespaces)
        let trimmedSample = sampleText.trimmingCharacters(in: .whitespaces)
        let trimmedTag    = tagText.trimmingCharacters(in: .whitespaces)

        let saved = FSPair(
            id:          pair?.id ?? UUID().uuidString,
            left:        trimmedLeft,
            right:       trimmedRight.isEmpty  ? nil : trimmedRight,
            description: trimmedDesc.isEmpty   ? nil : trimmedDesc,
            sample:      trimmedSample.isEmpty ? nil : trimmedSample,
            tag:         trimmedTag
        )
        onSave(saved)
    }
}
