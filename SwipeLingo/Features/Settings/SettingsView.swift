import AVFoundation
import SwiftUI

// MARK: - PreferencesView

struct SettingsView: View {

    @AppStorage("nativeLanguage")     private var nativeLanguage      = "Русский"
    @AppStorage("englishVariant")     private var englishVariant      = "en-US"
    @AppStorage("colorScheme")        private var theme: Theme         = .system
    @AppStorage("ttsVoiceIdentifier") private var ttsVoiceIdentifier  = ""

    private var currentVoiceName: String {
        guard !ttsVoiceIdentifier.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: ttsVoiceIdentifier)
        else { return "Default" }
        return voice.name
    }

    private let languages = [
        "Русский", "中文", "Español", "Français",
        "العربية", "Português", "Deutsch", "日本語"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    languageSection
                    voiceSection
                    appearanceSection
                    managingCardsSection
                }
                .padding(.vertical, 16)
            }
            .background(Color.myColors.myBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANGUAGE")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                // Native language
                HStack {
                    Text("Native language")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $nativeLanguage) {
                        ForEach(languages, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(.subheadline.weight(.bold))
                }
                .frame(height: 52)
                .padding(.horizontal, 16)

                Divider().padding(.leading, 16)

                // English variant
                HStack {
                    Text("Preferred English")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $englishVariant) {
                        Text("American").tag("en-US")
                        Text("British").tag("en-GB")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(.subheadline.weight(.bold))
                }
                .frame(height: 52)
                .padding(.horizontal, 16)
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)

//            Text("Select your native language for translation and preferred English variant.")
//                .font(.footnote)
//                .opacity(0.75)
//                .padding(.horizontal, 32)
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VOICE")
                .font(.footnote)
                .padding(.horizontal, 32)

            NavigationLink { VoiceSettingsView() } label: {
                HStack {
                    Label("Pronunciation Voice", systemImage: "waveform")
                    Spacer()
                    Text(currentVoiceName)
                        .font(.subheadline)
                }
                .frame(height: 52)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)

//            Text("Voice used when reading English words aloud.")
//                .font(.footnote)
//                .opacity(0.75)
//                .padding(.horizontal, 32)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPEARANCE")
                .font(.footnote)
                .padding(.horizontal, 32)

            UnderlineSegmentedPickerNotOptional(
                selection: $theme,
                allItems: Theme.allCases,
                titleForCase: { $0.displayName },
                selectedFont: .subheadline
            )
            .frame(height: 52)
            .padding(.horizontal, 16)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Managing Cards

    private var managingCardsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MANAGING CARDS")
                .font(.footnote)
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

                Divider().padding(.leading, 52)

                HStack {
                    Label("Backup Cards", systemImage: "arrow.clockwise.icloud")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    SettingsView()
}
