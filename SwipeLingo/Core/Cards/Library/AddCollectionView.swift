import SwiftUI
import SwiftData

// MARK: - AddCollectionView

struct AddCollectionView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "folder"

    private let icons = [
        "folder", "book", "star", "heart",
        "airplane", "briefcase.fill", "house", "graduationcap",
        "cart", "fork.knife", "car", "music.note"
    ]

    private var isNameEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection name", text: $name)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(
                                    selectedIcon == icon
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { selectedIcon = icon }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .sheetNavigationBar("New Collection")
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
                            let collection = Collection(
                                name: name.trimmingCharacters(in: .whitespaces),
                                icon: selectedIcon
                            )
                            context.insert(collection)
                            context.saveWithErrorHandling()
                            dismiss()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .hiddenSharedBackgroundIfAvailable()
            }
        }
    }
}
