import SwiftUI

// MARK: - BookEditorSheet
//
// Редактирование метаданных существующей книги (без повторной загрузки файлов).
// После сохранения книга переходит в .draft — нужен повторный Deploy.

struct BookEditorSheet: View {

    let book: FSBook

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss)       private var dismiss

    @State private var title:       String
    @State private var author:      String
    @State private var description: String
    @State private var cefrLevel:   CEFRLevel
    @State private var accessTier:  AccessTier

    init(book: FSBook) {
        self.book        = book
        _title       = State(initialValue: book.title)
        _author      = State(initialValue: book.author)
        _description = State(initialValue: book.description ?? "")
        _cefrLevel   = State(initialValue: book.cefrLevel)
        _accessTier  = State(initialValue: book.accessTier)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Book Info") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Classification") {
                    Picker("CEFR Level", selection: $cefrLevel) {
                        ForEach(CEFRLevel.allCases, id: \.self) { level in
                            Text(level.displayCode + " — " + level.displayName).tag(level)
                        }
                    }

                    Picker("Access Tier", selection: $accessTier) {
                        ForEach(AccessTier.allCases, id: \.self) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }
                }

                Section("Storage (read-only)") {
                    LabeledContent("Cover path", value: book.coverStoragePath)
                        .foregroundStyle(.secondary)
                    LabeledContent("Chapters", value: "\(book.totalChapters)")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func save() {
        var updated          = book
        updated.title        = title.trimmingCharacters(in: .whitespaces)
        updated.author       = author.trimmingCharacters(in: .whitespaces)
        updated.description  = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
        updated.cefrLevel    = cefrLevel
        updated.accessTier   = accessTier
        store.update(updated)
        dismiss()
    }
}
