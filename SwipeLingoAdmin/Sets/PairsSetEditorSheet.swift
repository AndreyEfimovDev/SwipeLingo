import SwiftUI

// MARK: - PairsSetEditorSheet

struct PairsSetEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let collectionId: String
    let pairsSet: FSPairsSet?

    // MARK: State

    @State private var title:      String      = ""
    @State private var desc:       String      = ""
    @State private var cefrLevel:  CEFRLevel   = .b2
    @State private var accessTier: AccessTier  = .free

    private var isEditing: Bool { pairsSet != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var collectionName: String {
        store.collections.first { $0.id == collectionId }?.name ?? "—"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Collection (read-only) ─────────────────────
                    GroupBox {
                        HStack {
                            Text("Collection")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(collectionName)
                                .foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                    }

                    // ── Title ─────────────────────────────────────
                    fieldLabel("Title")
                    clearableField("Set title", text: $title)

                    // ── Description ───────────────────────────────
                    fieldLabel("Description (optional)")
                    clearableField("Shown in the library below the title", text: $desc)

                    // ── Level & Access ────────────────────────────
                    GroupBox("Level & Access") {
                        Picker("CEFR Level", selection: $cefrLevel) {
                            ForEach(CEFRLevel.allCases, id: \.self) { l in
                                Text(l.displayCode).tag(l)
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
                    if isEditing, let s = pairsSet {
                        GroupBox("Status") {
                            HStack {
                                Text("Deploy Status")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(s.deployStatus.label)
                            }
                            .font(.subheadline)
                            Text("Managed automatically — use 'Mark as Ready' in the set list to schedule publishing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .frame(minWidth: 400, minHeight: 320)
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
            if let s = pairsSet {
                title      = s.title ?? ""
                desc       = s.description ?? ""
                cefrLevel  = s.cefrLevel
                accessTier = s.accessTier
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

    // MARK: Save

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDesc  = desc.trimmingCharacters(in: .whitespaces)

        if let existing = pairsSet {
            var updated = existing
            updated.title       = trimmedTitle
            updated.description = trimmedDesc.isEmpty ? nil : trimmedDesc
            updated.cefrLevel   = cefrLevel
            updated.accessTier  = accessTier
            // deployStatus intentionally NOT set here — AdminStore.update() handles auto-transition
            store.update(updated)
        } else {
            let new = FSPairsSet(
                id:           FirestoreID.make(name: trimmedTitle),
                collectionId: collectionId,
                title:        trimmedTitle,
                description:  trimmedDesc.isEmpty ? nil : trimmedDesc,
                cefrLevel:    cefrLevel,
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
