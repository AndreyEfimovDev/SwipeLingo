import SwiftUI

// MARK: - PreferencesView

struct PreferencesView: View {

    @AppStorage("nativeLanguage") private var nativeLanguage = "Русский"
    @AppStorage("colorScheme")    private var colorSchemeKey = "auto"

    private let languages = [
        "Русский", "中文", "Español", "Français",
        "العربية", "Português", "Deutsch", "日本語"
    ]

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                appearanceSection
                managingCardsSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .navigationTitle("Settings")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker("Native language", selection: $nativeLanguage) {
                ForEach(languages, id: \.self) { Text($0).tag($0) }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Defines which side of the card shows your native translation.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $colorSchemeKey) {
                    Text("Auto").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Managing Cards

    private var managingCardsSection: some View {
        Section("Managing Cards") {
            NavigationLink {
                DeletedCardsView()
            } label: {
                Label("Deleted Cards", systemImage: "trash")
            }

            Label("Share Cards", systemImage: "square.and.arrow.up")
                .foregroundStyle(.secondary)

            Label("Backup Cards", systemImage: "arrow.clockwise.icloud")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PreferencesView()
}
