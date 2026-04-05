import AVFoundation
import SwiftUI

// MARK: - VoiceSettingsView

struct VoiceSettingsView: View {

    @AppStorage("ttsVoiceIdentifier") private var selectedIdentifier = ""
    @AppStorage("englishVariant")     private var englishVariant    = "en-US"
    @State private var previewService       = AudioPlayerService()
    @State private var previewingVoiceId    = ""

    // MARK: - Voice data

    private struct VoiceGroup: Identifiable {
        let quality: AVSpeechSynthesisVoiceQuality
        var id: Int { quality.rawValue }

        var title: String {
            switch quality {
            case .premium:  return "PREMIUM"
            case .enhanced: return "ENHANCED"
            default:        return "STANDARD"
            }
        }
        var subtitle: String {
            switch quality {
            case .premium:  return "Best quality"
            case .enhanced: return "High quality"
            default:        return "Built-in"
            }
        }

        let voices: [AVSpeechSynthesisVoice]
    }

    private var voiceGroups: [VoiceGroup] {
        let allowed: Set<AVSpeechSynthesisVoiceQuality> = [
            AVSpeechSynthesisVoiceQuality.default,
            AVSpeechSynthesisVoiceQuality.enhanced,
            AVSpeechSynthesisVoiceQuality.premium
        ]
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") && allowed.contains($0.quality) }
        let grouped = Dictionary(grouping: english, by: \.quality)
        let qualityOrder: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]
        let preferred = englishVariant  // e.g. "en-US" or "en-GB"
        return qualityOrder.compactMap { q in
            guard let voices = grouped[q], !voices.isEmpty else { return nil }
            let sorted = voices.sorted {
                let aPreferred = $0.language == preferred
                let bPreferred = $1.language == preferred
                if aPreferred != bPreferred { return aPreferred }           // preferred dialect first
                if $0.language != $1.language { return $0.language < $1.language } // then alphabetical by locale
                return $0.name < $1.name                                    // then by name
            }
            return VoiceGroup(quality: q, voices: sorted)
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                infoCard
                defaultRow
                ForEach(voiceGroups) { group in
                    voiceGroupSection(group)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.myColors.myBackground.ignoresSafeArea())
        .customBackButton("Settings")
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { previewService.stop() }
        .onChange(of: previewService.isPlaying) { _, isPlaying in
            if !isPlaying { previewingVoiceId = "" }
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.myColors.myBlue)
                .padding(.top, 1)
            Text("Enhanced and Premium voices sound more natural but must be downloaded first: **iOS Settings → Accessibility → Spoken Content → Voices → English → Voices**")
                .font(.footnote)
        }
        .padding(14)
        .background(Color.myColors.myBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .myShadow()
        .padding(.horizontal, 16)
    }

    // MARK: - Default row

    private var defaultRow: some View {
        let isSelected = selectedIdentifier.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            Text("DEFAULT")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.myColors.myBlue : Color.myColors.myAccent)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("System Default")
                        .font(.body)
                    Text("iOS picks the voice automatically")
                        .font(.caption)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { selectedIdentifier = "" }
        }
    }

    // MARK: - Group section

    private func voiceGroupSection(_ group: VoiceGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(group.title)
                Text("·")
                Text(group.subtitle)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 32)

            VStack(spacing: 0) {
                ForEach(group.voices, id: \.identifier) { voice in
                    voiceRow(voice)
                    if voice.identifier != group.voices.last?.identifier {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.myColors.myBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .myShadow()
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Voice row

    private func voiceRow(_ voice: AVSpeechSynthesisVoice) -> some View {
        let isSelected       = selectedIdentifier == voice.identifier
        let isPreviewing     = previewingVoiceId  == voice.identifier && previewService.isPlaying

        return HStack(spacing: 12) {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle" : "circle")
                .foregroundStyle(isSelected ? Color.myColors.myBlue : Color.myColors.myAccent)
                .font(.title3)
                .frame(width: 28)

            // Name + language
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.body)
                Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)
                    .font(.caption)
            }

            Spacer()

            // Preview button
            Button {
                if isPreviewing {
                    previewService.stop()
                    previewingVoiceId = ""
                } else {
                    previewingVoiceId = voice.identifier
                    previewService.speak(
                        text: "The quick brown fox jumps over the lazy dog.",
                        voiceIdentifier: voice.identifier
                    )
                }
            } label: {
                Image(systemName: isPreviewing ? "stop.circle" : "speaker.wave.2.circle")
                    .foregroundStyle(isPreviewing ? Color.myColors.myRed : Color.myColors.myBlue)
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIdentifier = isSelected ? "" : voice.identifier
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VoiceSettingsView()
            .environment(AppViewModel())
    }
}
