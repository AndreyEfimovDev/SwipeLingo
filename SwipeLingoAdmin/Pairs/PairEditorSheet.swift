import SwiftUI

// MARK: - PairEditorSheet

struct PairEditorSheet: View {

    @Environment(\.dismiss) private var dismiss

    let pair:       FSPair?
    let leftTitle:  String
    let rightTitle: String
    let onSave:     (FSPair) -> Void

    // MARK: State

    @State private var leftText:  String = ""
    @State private var rightText: String = ""

    private var canSave: Bool {
        !leftText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    fieldLabel(leftTitle)
                    clearableField("Word or phrase", text: $leftText)

                    fieldLabel(rightTitle)
                    clearableField("Synonym / advanced form", text: $rightText)

                    Spacer()
                }
                .padding(20)
            }
            .frame(minWidth: 380, minHeight: 200)
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
            leftText  = pair?.left?.text  ?? ""
            rightText = pair?.right?.text ?? ""
        }
    }

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
        let trimmedLeft  = leftText.trimmingCharacters(in: .whitespaces)
        let trimmedRight = rightText.trimmingCharacters(in: .whitespaces)

        let saved = FSPair(
            id:    pair?.id ?? UUID().uuidString,
            left:  FSPairSide(text: trimmedLeft),
            right: trimmedRight.isEmpty ? nil : FSPairSide(text: trimmedRight)
        )
        onSave(saved)
    }
}
