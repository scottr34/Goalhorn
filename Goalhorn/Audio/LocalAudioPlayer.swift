import Foundation
import AVFoundation

/// Plays a goal song through the iPhone's own speaker.
///
/// Used when the audio target is "This iPhone", or as a fallback if Sonos can't
/// be reached. Configures the audio session for playback so it works even with
/// the ringer switched to silent.
@MainActor
final class LocalAudioPlayer {
    private var player: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?

    func play(fileURL: URL, volume: Float = 1.0) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // Playback is best-effort; surface nothing to the user for a failed horn.
            NSLog("Goalhorn local playback failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        fadeTask?.cancel()
        fadeTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ramp down and then stop, so a capped song ends rather than being cut off
    /// mid-note. `AVAudioPlayer` does the ramp itself; we just stop afterwards.
    func fadeOut(over seconds: TimeInterval = 1.5) {
        guard let player, player.isPlaying else {
            stop()
            return
        }
        player.setVolume(0, fadeDuration: seconds)
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }
}
