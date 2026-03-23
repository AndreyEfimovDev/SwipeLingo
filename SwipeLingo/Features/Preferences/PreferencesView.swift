import SwiftUI

// MARK: - PreferencesView
// Placeholder — full implementation in Stage 4.

struct PreferencesView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    LabeledContent("Native language", value: "Russian")
                    LabeledContent("English variant", value: "American")
                }
                Section("Appearance") {
                    LabeledContent("Theme", value: "System")
                }
                Section("Data") {
                    LabeledContent("Backup & Restore", value: "—")
                    LabeledContent("Import .apkg", value: "—")
                }
            }
            .navigationTitle("Preferences")
        }
    }
}
