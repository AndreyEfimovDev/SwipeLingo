import AVFoundation
import Foundation

// MARK: - AudioPlayerService
//
// @Observable класс для сетевого аудио-воспроизведения (AVPlayer) и TTS (AVSpeechSynthesizer).
// Неявно @MainActor через SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//
// currentURL отслеживает, что сейчас играет:
//   • обычная строка URL  — сетевое аудио
//   • "tts:<text>"        — синтез речи
//   • ""                  — ничего не играет
//
// Диагностика: все ключевые события логируются через log() из Logger.swift.

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

    /// Запускает воспроизведение аудио по `urlString`.
    func play(urlString: String) {
        stop()

        guard !urlString.isEmpty else {
            log("play() called with empty URL string", level: .error)
            return
        }
        guard let url = URL(string: urlString) else {
            log("Invalid URL: '\(urlString)'", level: .error)
            return
        }

        log("▶ Attempting to play: \(url.absoluteString)")

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            log("AVAudioSession configured (.playback)", level: .info)
        } catch {
            log("AVAudioSession setup failed: \(error)", level: .warning)
        }

        let item = AVPlayerItem(url: url)
        player   = AVPlayer(playerItem: item)

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            log("Playback finished", level: .info)
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
            log("Failed to play to end: \(err?.localizedDescription ?? "unknown")", level: .error)
            self?.isPlaying  = false
            self?.currentURL = ""
            self?.player     = nil
        }

        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor [weak self] in
                switch item.status {
                case .readyToPlay:
                    log("AVPlayerItem ready to play", level: .info)
                case .failed:
                    let msg = item.error?.localizedDescription ?? "unknown load error"
                    log("AVPlayerItem failed: \(msg)", level: .error)
                    self?.isPlaying  = false
                    self?.currentURL = ""
                    self?.player     = nil
                case .unknown:
                    log("⏳ AVPlayerItem status: buffering…")
                @unknown default:
                    break
                }
            }
        }

        timeControlObservation = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                switch player.timeControlStatus {
                case .playing:
                    log("▶ timeControlStatus: playing")
                case .paused:
                    if let reason = player.reasonForWaitingToPlay {
                        log("⏳ timeControlStatus: waiting — \(reason.rawValue)")
                    } else {
                        log("⏹ timeControlStatus: paused (stalled or timed out)")
                        self?.isPlaying  = false
                        self?.currentURL = ""
                        self?.player     = nil
                    }
                case .waitingToPlayAtSpecifiedRate:
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "unknown"
                    log("⏳ timeControlStatus: waitingToPlay — \(reason)")
                @unknown default:
                    break
                }
            }
        }

        currentURL = urlString
        player?.play()
        isPlaying = true
        log("▶ player.play() called — waiting for buffer")
    }

    // MARK: Public API — TTS

    /// Озвучивает `text` через AVSpeechSynthesizer.
    /// - Parameters:
    ///   - voiceIdentifier: `AVSpeechSynthesisVoice.identifier`; при пустом значении или если не найден — откат на `language`.
    ///   - language: BCP-47 языковой тег, используется, когда валидный `voiceIdentifier` не передан.
    func speak(text: String, voiceIdentifier: String = "", language: String = "en-US") {
        stop()
        guard !text.isEmpty else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log("AVAudioSession setup failed for TTS: \(error)", level: .warning)
        }

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
        log("🔈 TTS started: \(text.prefix(40))")
    }

    // MARK: Public API — Stop

    /// Останавливает всё воспроизведение (и AVPlayer, и TTS) и сбрасывает состояние.
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
        log("TTS finished", level: .info)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isPlaying  = false
        currentURL = ""
        log("⏹ TTS cancelled")
    }
}
