import SwiftUI

// MARK: - CollectionEditorSheet

struct CollectionEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let type: CollectionType
    let collection: FSCollection?

    // MARK: State

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var showSymbolPicker = false

    private var isEditing: Bool { collection != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private var defaultIcon: String {
        type == .cards ? "rectangle.stack" : "square.grid.2x2"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Name ──────────────────────────────────────
                    fieldLabel("Name")
                    clearableField("Collection name", text: $name)

                    // ── Icon ──────────────────────────────────────
                    fieldLabel("Icon (SF Symbol or emoji)")
                    HStack(spacing: 10) {
                        clearableField("folder, star.fill, 📚 …", text: $icon)
                        iconPreview
                    }

                    // ── Info ──────────────────────────────────────
                    GroupBox("Info") {
                        LabeledContent("Type") {
                            Text(type == .cards ? "Cards" : "Pairs")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
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
                type: type,
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
