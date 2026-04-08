import SwiftUI

// MARK: - PairsSetEditorSheet
//
// Sheet для создания и редактирования FSPairsSet.
// Пары (items) редактируются отдельно в Phase 1.6.

struct PairsSetEditorSheet: View {

    @Environment(AdminStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let collectionId: String
    let pairsSet: FSPairsSet?

    // MARK: State

    @State private var title:       String      = ""
    @State private var subtitle:    String      = ""
    @State private var leftTitle:   String      = ""
    @State private var rightTitle:  String      = ""
    @State private var displayMode: DisplayMode = .parallel
    @State private var accessTier:  AccessTier  = .free
    @State private var isPublished: Bool        = false

    private var isEditing: Bool { pairsSet != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Set") {
                    TextField("Title", text: $title)
                    TextField("Subtitle (optional)", text: $subtitle)
                }

                Section("Columns") {
                    TextField("Left column title (e.g. B2, Basic)", text: $leftTitle)
                    TextField("Right column title (e.g. C1, Advanced)", text: $rightTitle)

                    Picker("Display Mode", selection: $displayMode) {
                        Text("Parallel").tag(DisplayMode.parallel)
                        Text("Sequential").tag(DisplayMode.sequential)
                    }
                }

                Section("Access") {
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
                leftTitle   = s.leftTitle ?? ""
                rightTitle  = s.rightTitle ?? ""
                displayMode = s.displayMode
                accessTier  = s.accessTier
                isPublished = s.isPublished
            }
        }
    }

    // MARK: Save

    private func save() {
        let trimmedTitle    = title.trimmingCharacters(in: .whitespaces)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespaces)
        let trimmedLeft     = leftTitle.trimmingCharacters(in: .whitespaces)
        let trimmedRight    = rightTitle.trimmingCharacters(in: .whitespaces)

        if let existing = pairsSet {
            var updated = existing
            updated.title        = trimmedTitle
            updated.subtitle     = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
            updated.leftTitle    = trimmedLeft.isEmpty ? nil : trimmedLeft
            updated.rightTitle   = trimmedRight.isEmpty ? nil : trimmedRight
            updated.displayModeRaw = displayMode.rawValue
            updated.accessTierRaw = accessTier.rawValue
            updated.isPublished  = isPublished
            updated.updatedAt    = .now
            store.update(updated)
        } else {
            let new = FSPairsSet(
                id:           FirestoreID.make(name: trimmedTitle),
                collectionId: collectionId,
                title:        trimmedTitle,
                subtitle:     trimmedSubtitle.isEmpty ? nil : trimmedSubtitle,
                leftTitle:    trimmedLeft.isEmpty ? nil : trimmedLeft,
                rightTitle:   trimmedRight.isEmpty ? nil : trimmedRight,
                displayModeRaw: displayMode.rawValue,
                accessTierRaw: accessTier.rawValue,
                items:        [],
                isPublished:  isPublished,
                updatedAt:    .now,
                createdAt:    .now
            )
            store.add(new)
        }
        dismiss()
    }
}
