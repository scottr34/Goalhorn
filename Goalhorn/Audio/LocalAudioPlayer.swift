import Foundation
import AVFoundation

/// Plays a goal song through the iPhone's own speaker.
///
/// Used when the audio target is "This iPhone", or as a fallback if Sonos can't
/// be reached. Configures the audio session for playback so it works even with
/// the ringer switched to silent.
final class LocalAudioPlayer {
    private var player: AVAudioPlayer?

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
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
