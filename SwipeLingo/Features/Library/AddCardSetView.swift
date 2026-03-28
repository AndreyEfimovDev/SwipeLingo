import SwiftUI
import SwiftData

// MARK: - AddCardSetView

struct AddCardSetView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let collectionId: UUID
    @State private var name = ""

    private var isNameEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Set name", text: $name)
            }
            .navigationTitle("New Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.myColors.myRed)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let cardSet = CardSet(
                            name: name.trimmingCharacters(in: .whitespaces),
                            collectionId: collectionId
                        )
                        context.insert(cardSet)
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(isNameEmpty ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myBlue)
                    .disabled(isNameEmpty)
                }
            }
        }
    }
}
