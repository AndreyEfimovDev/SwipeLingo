import SwiftUI

// MARK: - PairsSetEditorSheet

struct PairsSetEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let collectionId: String
    let pairsSet: FSPairsSet?

    // MARK: State

    @State private var title:       String      = ""
    @State private var subtitle:    String      = ""
    @State private var desc:        String      = ""
    @State private var leftTitle:   String      = ""
    @State private var rightTitle:  String      = ""
    @State private var displayMode: DisplayMode = .parallel
    @State private var accessTier:  AccessTier  = .free

    private var isEditing: Bool { pairsSet != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Title ─────────────────────────────────────
                    fieldLabel("Title")
                    clearableField("Set title", text: $title)

                    // ── Subtitle ──────────────────────────────────
                    fieldLabel("Subtitle (optional)")
                    clearableField("Subtitle", text: $subtitle)

                    // ── Description ───────────────────────────────
                    fieldLabel("Description (optional)")
                    clearableField("Longer description shown in the library", text: $desc)

                    // ── Columns ───────────────────────────────────
                    fieldLabel("Columns")
                    clearableField("Left column (e.g. B2, Basic)", text: $leftTitle)
                    clearableField("Right column (e.g. C1, Advanced)", text: $rightTitle)

                    // ── Display & Access ──────────────────────────
                    GroupBox("Display & Access") {
                        Picker("Display Mode", selection: $displayMode) {
                            Text("Parallel").tag(DisplayMode.parallel)
                            Text("Sequential").tag(DisplayMode.sequential)
                        }

                        Divider()

                        Picker("Access Tier", selection: $accessTier) {
                            ForEach(AccessTier.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .frame(minWidth: 420, minHeight: 360)
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
                title       = s.title ?? ""
                subtitle    = s.subtitle ?? ""
                desc        = s.description ?? ""
                leftTitle   = s.leftTitle ?? ""
                rightTitle  = s.rightTitle ?? ""
                displayMode = s.displayMode
                accessTier  = s.accessTier
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
        let trimmedTitle    = title.trimmingCharacters(in: .whitespaces)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespaces)
        let trimmedDesc     = desc.trimmingCharacters(in: .whitespaces)
        let trimmedLeft     = leftTitle.trimmingCharacters(in: .whitespaces)
        let trimmedRight    = rightTitle.trimmingCharacters(in: .whitespaces)

        if let existing = pairsSet {
            var updated = existing
            updated.title       = trimmedTitle
            updated.subtitle    = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
            updated.description = trimmedDesc.isEmpty ? nil : trimmedDesc
            updated.leftTitle   = trimmedLeft.isEmpty ? nil : trimmedLeft
            updated.rightTitle  = trimmedRight.isEmpty ? nil : trimmedRight
            updated.displayMode = displayMode
            updated.accessTier  = accessTier
            updated.updatedAt   = .now
            store.update(updated)
        } else {
            let new = FSPairsSet(
                id:          FirestoreID.make(name: trimmedTitle),
                collectionId: collectionId,
                title:       trimmedTitle,
                subtitle:    trimmedSubtitle.isEmpty ? nil : trimmedSubtitle,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                leftTitle:   trimmedLeft.isEmpty ? nil : trimmedLeft,
                rightTitle:  trimmedRight.isEmpty ? nil : trimmedRight,
                displayMode: displayMode,
                accessTier:  accessTier,
                items:       [],
                updatedAt:   .now,
                createdAt:   .now
            )
            store.add(new)
        }
        dismiss()
    }
}
