import AVFoundation
import Foundation

// MARK: - AudioPlayerService
//
// @Observable class for remote audio playback via AVPlayer.
// Implicitly @MainActor via SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor.
//
// Diagnostics: all key events are printed with [AudioPlayer] prefix.

@Observable
final class AudioPlayerService {

    // MARK: Observable state

    private(set) var isPlaying = false

    // MARK: Private

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    // MARK: Public API

    /// Starts playback of the audio at `urlString`.
    /// Logs all outcomes to the console for debugging.
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

        // Must activate .playback session or AVPlayer stays silent on
        // simulator and real device when the ringer switch is off.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("[AudioPlayer] ✅ AVAudioSession configured (.playback)")
        } catch {
            print("[AudioPlayer] ⚠️ AVAudioSession setup failed: \(error)")
        }

        let item = AVPlayerItem(url: url)
        player   = AVPlayer(playerItem: item)

        // ── Playback finished normally ──────────────────────────────────
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            print("[AudioPlayer] ✅ Playback finished")
            self?.isPlaying = false
            self?.player    = nil
        }

        // ── Playback failed to reach the end ───────────────────────────
        errorObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            print("[AudioPlayer] ❌ Failed to play to end: \(err?.localizedDescription ?? "unknown")")
            self?.isPlaying = false
            self?.player    = nil
        }

        // ── Item load status (catches bad URL / network errors early) ──
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor [weak self] in
                switch item.status {
                case .readyToPlay:
                    print("[AudioPlayer] ✅ AVPlayerItem ready to play")
                case .failed:
                    let msg = item.error?.localizedDescription ?? "unknown load error"
                    print("[AudioPlayer] ❌ AVPlayerItem failed: \(msg)")
                    self?.isPlaying = false
                    self?.player    = nil
                case .unknown:
                    print("[AudioPlayer] ⏳ AVPlayerItem status: buffering…")
                @unknown default:
                    break
                }
            }
        }

        // ── timeControlStatus: detects stall / network timeout ─────────
        // failedToPlayToEndTime only fires after playback starts.
        // A network timeout during buffering never triggers it — only
        // timeControlStatus dropping to .paused with a waitingReason of
        // .toMinimizeStalls (or nil after a hard timeout) reveals the stall.
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
                        self?.isPlaying = false
                        self?.player    = nil
                    }
                case .waitingToPlayAtSpecifiedRate:
                    let reason = player.reasonForWaitingToPlay?.rawValue ?? "unknown"
                    print("[AudioPlayer] ⏳ timeControlStatus: waitingToPlay — \(reason)")
                @unknown default:
                    break
                }
            }
        }

        player?.play()
        isPlaying = true
        print("[AudioPlayer] ▶ player.play() called — waiting for buffer")
    }

    /// Stops playback and resets all state.
    func stop() {
        player?.pause()
        player = nil
        cleanupObservers()
        isPlaying = false
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
