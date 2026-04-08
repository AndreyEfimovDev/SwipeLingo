import SwiftUI

// MARK: - CardSetEditorSheet
//
// Sheet для создания и редактирования FSCardSet.
// При изменении CEFR уровня автоматически предлагает AccessTier.

struct CardSetEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let collectionId: String
    let cardSet: FSCardSet?

    // MARK: State

    @State private var name:        String     = ""
    @State private var level:       CEFRLevel  = .b1
    @State private var accessTier:  AccessTier = .go
    @State private var isPublished: Bool       = false

    private var isEditing: Bool { cardSet != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    TextField("Name", text: $name)

                    Picker("CEFR Level", selection: $level) {
                        ForEach(CEFRLevel.allCases, id: \.self) { l in
                            HStack {
                                Text(l.displayCode)
                                Text("· \(l.displayName)")
                                    .foregroundStyle(.secondary)
                            }
                            .tag(l)
                        }
                    }
                    .onChange(of: level) { _, newLevel in
                        // Авто-предзаполнение accessTier по CEFR
                        switch newLevel {
                        case .a0a1, .a2: accessTier = .free
                        case .b1, .b2:   accessTier = .go
                        case .c1, .c2:   accessTier = .pro
                        }
                    }

                    Picker("Access Tier", selection: $accessTier) {
                        ForEach(AccessTier.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("Publishing") {
                    Toggle("Published", isOn: $isPublished)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 400, minHeight: 260)
            .navigationTitle(isEditing ? "Edit Set" : "New Set")
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
            if let s = cardSet {
                name        = s.name
                level       = CEFRLevel(rawValue: s.level) ?? .b1
                accessTier  = s.accessTier
                isPublished = s.isPublished
            }
        }
    }

    // MARK: Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let existing = cardSet {
            var updated = existing
            updated.name          = trimmedName
            updated.level         = level.rawValue
            updated.accessTierRaw = accessTier.rawValue
            updated.isPublished   = isPublished
            updated.updatedAt     = .now
            store.update(updated)
        } else {
            let new = FSCardSet(
                id:           FirestoreID.make(name: trimmedName),
                collectionId: collectionId,
                name:         trimmedName,
                level:        level.rawValue,
                accessTierRaw: accessTier.rawValue,
                isPublished:  isPublished,
                updatedAt:    .now,
                createdAt:    .now
            )
            store.add(new)
        }
        dismiss()
    }
}
