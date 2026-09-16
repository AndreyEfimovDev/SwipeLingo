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
            .sheetNavigationBar("New Set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    NavBarButtonForSheet(
                        title: "Cancel",
                        color: Color.myColors.myRed) {
                            dismiss()
                        }
                }
                .hiddenSharedBackgroundIfAvailable()
                ToolbarItem(placement: .confirmationAction) {
                    NavBarButtonForSheet(
                        title: "Create",
                        color: isNameEmpty ? Color.myColors.myAccent.opacity(0.8) : Color.myColors.myBlue) {
                            let cardSet = CardSet(
                                name: name.trimmingCharacters(in: .whitespaces),
                                collectionId: collectionId
                            )
                            context.insert(cardSet)
                            context.saveWithErrorHandling()
                            dismiss()
                        }
                        .disabled(isNameEmpty)
                }
                .hiddenSharedBackgroundIfAvailable()
            }
        }
    }
}
