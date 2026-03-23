import SwiftUI

// MARK: - PreferencesView

struct PreferencesView: View {

    // MARK: Stored preferences
    @AppStorage("nativeLanguage")  private var nativeLanguage  = "Русский"
    @AppStorage("studyDirection")  private var studyDirection  = "EN→RU"
    @AppStorage("colorScheme")     private var colorSchemeKey  = "auto"

    private let languages = [
        "Русский", "中文", "Español", "Français",
        "العربية", "Português", "Deutsch", "日本語"
    ]

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                studySection
                appearanceSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker("Native language", selection: $nativeLanguage) {
                ForEach(languages, id: \.self) { lang in
                    Text(lang).tag(lang)
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("Defines which side of the card shows your native translation.")
        }
    }

    // MARK: - Study

    private var studySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Study direction")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $studyDirection) {
                    Text("EN → \(nativeLanguage)").tag("EN→RU")
                    Text("\(nativeLanguage) → EN").tag("RU→EN")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)
        } header: {
            Text("Study")
        } footer: {
            Text("EN→RU: see the English word, recall the translation.\n\(nativeLanguage)→EN: see the translation, recall the English word.")
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
}

#Preview {
    PreferencesView()
}
