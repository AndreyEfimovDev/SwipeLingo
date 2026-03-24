import SwiftUI
import SwiftData

// MARK: - AddCardView
// Sheet for creating a new Card. Accessible from Study (+) and CardSetDetailView (+).

struct AddCardView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CardSet.createdAt) private var cardSets: [CardSet]

    let preselectedSetId: UUID?

    @State private var en: String = ""
    @State private var item: String = ""
    @State private var sampleEN: String = ""
    @State private var sampleItem: String = ""
    @State private var selectedSetId: UUID?

    private var isValid: Bool {
        !en.trimmingCharacters(in: .whitespaces).isEmpty &&
        !item.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word / Phrase") {
                    TextField("English", text: $en)
                    TextField("Translation", text: $item)
                }
                Section("Examples (optional)") {
                    TextField("Example in English", text: $sampleEN)
                    TextField("Example translated", text: $sampleItem)
                }
                Section("Save to") {
                    Picker("Set", selection: $selectedSetId) {
                        Text("Inbox")
                            .tag(Optional<UUID>.none)
                        ForEach(nonInboxSets) { set in
                            Text(set.name)
                                .tag(Optional(set.id))
                        }
                    }
                }
            }
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .onAppear {
            selectedSetId = preselectedSetId
        }
    }

    // MARK: - Helpers

    private var nonInboxSets: [CardSet] {
        cardSets.filter { $0.name != "Inbox" }
    }

    private var inboxSetId: UUID? {
        cardSets.first(where: { $0.name == "Inbox" })?.id
    }

    private func save() {
        let targetSetId = selectedSetId ?? inboxSetId ?? UUID()
        let sampleENArray   = sampleEN.trimmingCharacters(in: .whitespaces).isEmpty
            ? [] : [sampleEN.trimmingCharacters(in: .whitespaces)]
        let sampleItemArray = sampleItem.trimmingCharacters(in: .whitespaces).isEmpty
            ? [] : [sampleItem.trimmingCharacters(in: .whitespaces)]

        let card = Card(
            en: en.trimmingCharacters(in: .whitespaces),
            item: item.trimmingCharacters(in: .whitespaces),
            sampleEN: sampleENArray,
            sampleItem: sampleItemArray,
            setId: targetSetId
        )
        context.insert(card)
        try? context.save()
        dismiss()
    }
}
