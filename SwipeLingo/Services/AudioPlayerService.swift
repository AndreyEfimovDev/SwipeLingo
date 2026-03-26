import AVFoundation
import Foundation

// MARK: - AudioPlayerService
//
// @Observable class for remote audio playback (AVPlayer) and TTS (AVSpeechSynthesizer).
// Implicitly @MainActor via SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//
// currentURL tracks what is playing:
//   • regular URL string  — audio from network
//   • "tts:<text>"        — speech synthesis
//   • ""                  — nothing playing
//
// Diagnostics: all key events are printed with [AudioPlayer] prefix.

@Observable
final class AudioPlayerService: NSObject {

    // MARK: Observable state

    private(set) var isPlaying  = false
    private(set) var currentURL = ""

    // MARK: Private — AVPlayer

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    // MARK: Private — TTS

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: Public API — URL audio

    /// Starts playback of the audio at `urlString`.
    func play(urlString: String) {
        stop()

        guard !urlString.isEmpty else {
            print("[AudioPlayer] ❌ play() called with empty URL string")
            return
        }
        guard let url = URL(string: urlString) else {
            print("[AudioPlayer] ❌ Invalid URL: '\(urlString)'")
            return
        }

        print("[AudioPlayer] ▶ Attempting to play: \(url.absoluteString)")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("[AudioPlayer] ✅ AVAudioSession configured (.playback)")
        } catch {
            print("[AudioPlayer] ⚠️ AVAudioSession setup failed: \(error)")
        }

        let item = AVPlayerItem(url: url)
        player   = AVPlayer(playerItem: item)

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            print("[AudioPlayer] ✅ Playback finished")
            self?.isPlaying  = false
            self?.currentURL = ""
            self?.player     = nil
        }

        errorObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            print("[AudioPlayer] ❌ Failed to play to end: \(err?.localizedDescription ?? "unknown")")
            self?.isPlaying  = false
            self?.currentURL = ""
            self?.player     = nil
        }

        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor [weak self] in
                switch item.status {
                case .readyToPlay:
                    print("[AudioPlayer] ✅ AVPlayerItem ready to play")
                case .failed:
                    let msg = item.error?.localizedDescription ?? "unknown load error"
                    print("[AudioPlayer] ❌ AVPlayerItem failed: \(msg)")
                    self?.isPlaying  = false
                    self?.currentURL = ""
                    self?.player     = nil
                case .unknown:
                    print("[AudioPlayer] ⏳ AVPlayerItem status: buffering…")
                @unknown default:
                    break
                }
            }
        }

        timeControlObservation = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                switch player.timeControlStatus {
                case .playing:
                    print("[AudioPlayer] ▶ timeControlStatus: playing")
                case .paused:
                    if let reason = player.reasonForWaitingToPlay {
                        print("[AudioPlayer] ⏳ timeControlStatus: waiting — \(reason.rawValue)")
                    } else {
                        print("[AudioPlayer] ⏹ timeControlStatus: paused (stalled or timed out)")
                        self?.isPlaying  = false
                        self?.currentURL = ""
                        self?.player     = nil
                    }
                case .waitingToPlayAtSpecifiedRate:
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "unknown"
                    print("[AudioPlayer] ⏳ timeControlStatus: waitingToPlay — \(reason)")
                @unknown default:
                    break
                }
            }
        }

        currentURL = urlString
        player?.play()
        isPlaying = true
        print("[AudioPlayer] ▶ player.play() called — waiting for buffer")
    }

    // MARK: Public API — TTS

    /// Speaks `text` via AVSpeechSynthesizer.
    /// - Parameters:
    ///   - voiceIdentifier: `AVSpeechSynthesisVoice.identifier`; falls back to `language` if empty or not found.
    ///   - language: BCP-47 language tag used when no valid `voiceIdentifier` is provided.
    func speak(text: String, voiceIdentifier: String = "", language: String = "en-US") {
        stop()
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate  = AVSpeechUtteranceDefaultSpeechRate * 0.9

        currentURL = "tts:\(text)"
        isPlaying  = true
        synthesizer.delegate = self
        synthesizer.speak(utterance)
        print("[AudioPlayer] 🔈 TTS started: \(text.prefix(40))")
    }

    // MARK: Public API — Stop

    /// Stops all playback (both AVPlayer and TTS) and resets state.
    func stop() {
        player?.pause()
        player = nil
        cleanupObservers()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying  = false
        currentURL = ""
    }

    // MARK: Private

    private func cleanupObservers() {
        if let obs = endObserver   { NotificationCenter.default.removeObserver(obs); endObserver   = nil }
        if let obs = errorObserver { NotificationCenter.default.removeObserver(obs); errorObserver = nil }
        statusObservation?.invalidate();      statusObservation      = nil
        timeControlObservation?.invalidate(); timeControlObservation = nil
    }

    deinit { cleanupObservers() }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioPlayerService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isPlaying  = false
        currentURL = ""
        print("[AudioPlayer] ✅ TTS finished")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isPlaying  = false
        currentURL = ""
        print("[AudioPlayer] ⏹ TTS cancelled")
    }
}
