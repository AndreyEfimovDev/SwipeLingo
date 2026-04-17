import AVFoundation
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @AppStorage("nativeLanguage")     private var nativeLanguage: NativeLanguage = .russian
    @AppStorage("englishVariant")     private var englishVariant     = "en-US"
    @AppStorage("colorScheme")        private var theme: Theme       = .system
    @AppStorage("ttsVoiceIdentifier") private var ttsVoiceIdentifier = ""
    @AppStorage("studyStartHour")     private var studyStartHour: Int = 6
    @AppStorage("srsEnabled")         private var srsEnabled: Bool   = true
    @AppStorage("userPlan")           private var userPlan: AccessTier = .free

    private var titleFont: Font = .caption
    private var textFont: Font = .body
    
    private var currentVoiceName: String {
        guard !ttsVoiceIdentifier.isEmpty,
              let voice = AVSpeechSynthesisVoice(identifier: ttsVoiceIdentifier)
        else { return "Default" }
        return voice.name
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountSection
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.myColors.myBlue)
                    }
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACCOUNT")
                .font(titleFont)
                .padding(.horizontal, 32)

            NavigationLink { ProfileView() } label: {
                HStack {
                    Label("Your profile", systemImage: "person.circle")
                        .labelStyle(.fixedIcon)
                    AccessTierBadge(tier: userPlan)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.4))
                }
                .font(textFont)
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

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANGUAGE")
                .font(titleFont)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                HStack {
                    Text("Native language")
                    Spacer()
                    Text("\(nativeLanguage.flag) \(nativeLanguage.displayName)")
                        .foregroundStyle(Color.myColors.myAccent.opacity(0.5))
                }
                .font(textFont)
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
                .font(titleFont)
                .padding(.horizontal, 32)

            VStack(spacing: 0) {
                // SRS toggle
                HStack {
                    Label("Spaced Repetition (SRS)", systemImage: "brain")
                        .labelStyle(.fixedIcon)
                    Spacer()
                    Toggle("", isOn: $srsEnabled)
                        .labelsHidden()
                        .tint(Color.myColors.myBlue)
                }
                .font(textFont)
                .frame(height: 52)
                .padding(.horizontal, 16)

                // Due cards from — only when SRS is on
                if srsEnabled {
                    Divider().padding(.leading, 16)
                    HStack {
                        Label("Due from", systemImage: "clock")
                            .labelStyle(.fixedIcon)
                        Spacer()
                        Picker("", selection: $studyStartHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(Color.myColors.myBlue)
                    }
                    .font(textFont)
                    .frame(height: 52)
                    .padding(.horizontal, 16)
                }

            }
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
                .font(titleFont)
                .padding(.horizontal, 32)

            NavigationLink { VoiceSettingsView() } label: {
                HStack {
                    Label("Pronunciation Voice", systemImage: "waveform")
                        .labelStyle(.fixedIcon)
                    Spacer()
                    Text(currentVoiceName)
                        .font(.subheadline)
                }
                .font(textFont)
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
                .font(titleFont)
                .padding(.horizontal, 32)

            UnderlineSegmentedPickerNotOptional(
                selection: $theme,
                allItems: Theme.allCases,
                titleForCase: { $0.displayName },
                selectedFont: textFont
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
