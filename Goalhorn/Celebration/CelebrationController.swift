import Foundation
import Combine

/// Ties the whole celebration together: when a goal is triggered it starts the
/// spinning light beacon and plays the goal song (on Sonos or the phone).
@MainActor
final class CelebrationController: ObservableObject {
    /// True while the on-screen beacon animation should be running.
    @Published private(set) var isCelebrating = false
    /// Non-nil when the most recent trigger hit a problem worth surfacing.
    @Published var statusMessage: String?

    let lightEngine = GoalLightEngine()

    private let settings: AppSettings
    private let homeKit: HomeKitManager
    private let audioLibrary: AudioLibrary
    private let sonos: SonosController

    private let audioServer = LocalAudioServer()
    private let localPlayer = LocalAudioPlayer()

    private var endTask: Task<Void, Never>?

    init(settings: AppSettings, homeKit: HomeKitManager, audioLibrary: AudioLibrary, sonos: SonosController) {
        self.settings = settings
        self.homeKit = homeKit
        self.audioLibrary = audioLibrary
        self.sonos = sonos
    }

    /// Whether a song is selected/available to play.
    var hasPlayableSong: Bool { resolvedTrack != nil }

    private var resolvedTrack: AudioTrack? {
        audioLibrary.track(withID: settings.selectedTrackID) ?? audioLibrary.tracks.first
    }

    /// GOOOAL! Fire lights + horn.
    func triggerGoal() {
        guard !isCelebrating else { return }
        statusMessage = nil
        isCelebrating = true

        let duration = settings.celebrationDuration

        // Lights: run the beacon on the selected bulbs.
        let selected = homeKit.lights.filter { settings.selectedLightIDs.contains($0.id) }
        if !selected.isEmpty {
            lightEngine.start(on: selected, duration: duration)
        }

        // Audio.
        startAudio()

        // End the on-screen celebration after the configured duration. The song
        // itself is left to play out (the Sonos stream server stays alive until
        // the next goal).
        endTask?.cancel()
        endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isCelebrating = false
        }
    }

    /// Stop everything immediately.
    func stop() {
        endTask?.cancel()
        endTask = nil
        lightEngine.stop()
        localPlayer.stop()
        if let device = settings.sonosDevice {
            Task { try? await sonos.stop(on: device) }
        }
        isCelebrating = false
    }

    // MARK: - Audio routing

    private func startAudio() {
        guard let track = resolvedTrack else {
            statusMessage = "Add a goal song in the Songs tab to hear the horn."
            return
        }
        let fileURL = audioLibrary.fileURL(for: track)

        switch settings.audioTarget {
        case .phone:
            localPlayer.play(fileURL: fileURL)
        case .sonos:
            guard let device = settings.sonosDevice else {
                statusMessage = "No Sonos selected — playing on this iPhone instead."
                localPlayer.play(fileURL: fileURL)
                return
            }
            playOnSonos(track: track, fileURL: fileURL, device: device)
        }
    }

    private func playOnSonos(track: AudioTrack, fileURL: URL, device: SonosDevice) {
        // Host the file so Sonos can stream it from the phone.
        let pathHint = "/goalsong.\((track.fileName as NSString).pathExtension)"
        guard let streamURL = audioServer.start(fileURL: fileURL, contentType: track.contentType, pathHint: pathHint) else {
            statusMessage = "Couldn't start the local stream — playing on this iPhone instead."
            localPlayer.play(fileURL: fileURL)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sonos.playURL(
                    streamURL,
                    contentType: track.contentType,
                    title: track.title,
                    volume: self.settings.sonosVolume,
                    on: device
                )
            } catch {
                // Sonos unreachable — fall back to the phone speaker.
                self.statusMessage = "Sonos didn't respond — playing on this iPhone instead."
                self.audioServer.stop()
                self.localPlayer.play(fileURL: fileURL)
            }
        }
    }
}
