import SwiftUI

// MARK: - PairEditorSheet
//
// Sheet для создания (pair == nil) и редактирования одной пары FSPair.
// leftTitle / rightTitle берутся из родительского PairsSet и используются
// как заголовки секций, чтобы контекст был понятен при вводе.

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
            Form {
                Section(leftTitle) {
                    TextField("Word or phrase", text: $leftText)
                }
                Section(rightTitle) {
                    TextField("Synonym / advanced form", text: $rightText)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 380, minHeight: 240)
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
