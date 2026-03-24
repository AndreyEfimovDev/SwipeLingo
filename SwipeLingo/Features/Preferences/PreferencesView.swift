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
            ScrollView {
                VStack(spacing: 16) {
                    languageSection
                    appearanceSection
                    managingCardsSection
                }
                .padding(.vertical, 16)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANGUAGE")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            HStack {
                Text("Native language")
                    .font(.body)
                Spacer()
                Picker("", selection: $nativeLanguage) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)

            Text("Defines which side of the card shows your native translation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPEARANCE")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Managing Cards

    private var managingCardsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MANAGING CARDS")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                NavigationLink { DeletedCardsView() } label: {
                    HStack {
                        Label("Deleted Cards", systemImage: "trash")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.leading, 52)

                HStack {
                    Label("Share Cards", systemImage: "square.and.arrow.up")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .foregroundStyle(.secondary)

                Divider().padding(.leading, 52)

                HStack {
                    Label("Backup Cards", systemImage: "arrow.clockwise.icloud")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .foregroundStyle(.secondary)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    PreferencesView()
}
