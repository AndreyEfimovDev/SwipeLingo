import SwiftUI

// MARK: - CollectionEditorSheet
//
// Sheet для создания (collection == nil) и редактирования коллекции.
// Тип (cards/pairs) задаётся снаружи и не меняется после создания.

struct CollectionEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let type: CollectionType
    let collection: FSCollection?

    // MARK: State

    @State private var name: String = ""
    @State private var icon: String = ""

    private var isEditing: Bool { collection != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var defaultIcon: String {
        type == .cards ? "rectangle.stack" : "square.grid.2x2"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                // ── Основное ──────────────────────────────────
                Section("Collection") {
                    TextField("Name", text: $name)

                    HStack(spacing: 12) {
                        TextField("Icon (SF Symbol or emoji)", text: $icon)
                        iconPreview
                    }
                }

                // ── Мета ──────────────────────────────────────
                Section("Info") {
                    LabeledContent("Type") {
                        Text(type == .cards ? "Cards" : "Pairs")
                            .foregroundStyle(.secondary)
                    }
                    if isEditing {
                        LabeledContent("Status") {
                            Text(collection?.isPublished == true ? "Published" : "Draft")
                                .foregroundStyle(collection?.isPublished == true ? .green : .secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 280)
            .navigationTitle(isEditing ? "Edit Collection" : "New Collection")
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
            if let c = collection {
                name = c.name
                icon = c.icon ?? ""
            }
        }
    }

    // MARK: Icon preview

    @ViewBuilder
    private var iconPreview: some View {
        let trimmed = icon.trimmingCharacters(in: .whitespaces)
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor.opacity(0.1))
            if trimmed.isEmpty {
                Image(systemName: defaultIcon)
                    .foregroundStyle(.tertiary)
            } else if trimmed.isEmoji {
                Text(trimmed)
                    .font(.title3)
            } else {
                Image(systemName: trimmed)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 36, height: 36)
    }

    // MARK: Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)
        let iconValue: String? = trimmedIcon.isEmpty ? nil : trimmedIcon

        if let existing = collection {
            var updated = existing
            updated.name = trimmedName
            updated.icon = iconValue
            updated.updatedAt = .now
            store.update(updated)
        } else {
            let new = FSCollection(
                id: FirestoreID.make(name: trimmedName),
                name: trimmedName,
                icon: iconValue,
                typeRaw: type.rawValue,
                isPublished: false,
                updatedAt: .now,
                createdAt: .now
            )
            store.add(new)
        }
        dismiss()
    }
}

// MARK: - String + emoji

private extension String {
    var isEmoji: Bool {
        !unicodeScalars.allSatisfy(\.isASCII)
    }
}
