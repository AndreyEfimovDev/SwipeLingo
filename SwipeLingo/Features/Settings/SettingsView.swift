import AVFoundation
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @AppStorage("nativeLanguage")     private var nativeLanguage     = "Русский"
    @AppStorage("englishVariant")     private var englishVariant     = "en-US"
    @AppStorage("colorScheme")        private var theme: Theme       = .system
    @AppStorage("ttsVoiceIdentifier") private var ttsVoiceIdentifier = ""
    @AppStorage("studyStartHour")     private var studyStartHour: Int = 6

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
                    studySection
                    voiceSection
                    appearanceSection
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
                .font(.footnote)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
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

            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Study

    private var studySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STUDY")
                .font(.footnote)
                .padding(.horizontal, 32)

            HStack {
                Label("Due cards from", systemImage: "clock")
                    .labelStyle(.fixedIcon)
                Spacer()
                Picker("", selection: $studyStartHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .frame(height: 52)
            .padding(.horizontal, 16)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h      = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let period = hour < 12 ? "AM" : "PM"
        return "\(h):00 \(period)"
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
                        .labelStyle(.fixedIcon)
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
}

#Preview {
    SettingsView()
}
