import SwiftUI

// MARK: - CardSetEditorSheet

struct CardSetEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let collectionId: String
    let cardSet: FSCardSet?

    // MARK: State

    @State private var name:       String      = ""
    @State private var desc:       String      = ""
    @State private var level:      CEFRLevel   = .b1
    @State private var accessTier: AccessTier  = .go

    private var isEditing: Bool { cardSet != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Name ──────────────────────────────────────
                    fieldLabel("Name")
                    clearableField("Set name", text: $name)

                    // ── Description ───────────────────────────────
                    fieldLabel("Description (optional)")
                    clearableField("Brief description shown in the library", text: $desc)

                    // ── Level & Access ────────────────────────────
                    GroupBox("Level & Access") {
                        Picker("CEFR Level", selection: $level) {
                            ForEach(CEFRLevel.allCases, id: \.self) { l in
                                HStack {
                                    Text(l.displayCode)
                                    Text("· \(l.displayName)").foregroundStyle(.secondary)
                                }
                                .tag(l)
                            }
                        }
                        .onChange(of: level) { _, newLevel in
                            switch newLevel {
                            case .a1, .a2: accessTier = .free
                            case .b1, .b2:   accessTier = .go
                            case .c1, .c2:   accessTier = .pro
                            }
                        }

                        Divider()

                        Picker("Access Tier", selection: $accessTier) {
                            ForEach(AccessTier.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                    }

                    // ── Status (read-only when editing) ──────────
                    if isEditing, let s = cardSet {
                        GroupBox("Status") {
                            HStack {
                                Text("Deploy Status")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(s.deployStatus.label)
                            }
                            .font(.subheadline)
                            Text("Managed automatically — use "Mark as Ready" in the set list to schedule publishing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
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
                name       = s.name
                desc       = s.description ?? ""
                level      = s.cefrLevel
                accessTier = s.accessTier
            }
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
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = desc.trimmingCharacters(in: .whitespaces)

        if let existing = cardSet {
            var updated = existing
            updated.name        = trimmedName
            updated.description = trimmedDesc.isEmpty ? nil : trimmedDesc
            updated.cefrLevel   = level
            updated.accessTier  = accessTier
            // deployStatus intentionally NOT set here — AdminStore.update() handles auto-transition
            store.update(updated)
        } else {
            let new = FSCardSet(
                id:           FirestoreID.make(name: trimmedName),
                collectionId: collectionId,
                name:         trimmedName,
                description:  trimmedDesc.isEmpty ? nil : trimmedDesc,
                cefrLevel:    level,
                accessTier:   accessTier,
                deployStatus: .new,
                updatedAt:    .now,
                createdAt:    .now
            )
            store.add(new)
        }
        dismiss()
    }
}
