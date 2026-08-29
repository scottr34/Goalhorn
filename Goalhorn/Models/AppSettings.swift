import Foundation
import Combine

/// Where the goal song should play when a goal is triggered.
enum AudioTarget: String, Codable, CaseIterable, Identifiable {
    case sonos
    case phone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonos: return "Sonos speaker"
        case .phone: return "This iPhone"
        }
    }
}

/// How long the goal song plays for.
enum SongPlaybackMode: String, Codable, CaseIterable, Identifiable {
    /// Let the track run to its end (the app's original behaviour).
    case full
    /// Stop when the light show does.
    case matchLights
    /// Stop after `AppSettings.songDuration` seconds.
    case fixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: return "Play in full"
        case .matchLights: return "Match light show"
        case .fixed: return "Set length"
        }
    }
}

/// User-facing configuration, persisted to `UserDefaults`.
///
/// This is the single source of truth for "which lights", "which song",
/// "how long", and "where does the audio play".
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    private enum Key {
        static let audioTarget = "audioTarget"
        static let celebrationDuration = "celebrationDuration"
        static let selectedLightIDs = "selectedLightIDs"
        static let selectedTrackID = "selectedTrackID"
        static let sonosDevice = "sonosDevice"
        static let sonosVolume = "sonosVolume"
        static let goalColors = "goalColors"
        static let songPlayback = "songPlayback"
        static let songDuration = "songDuration"
    }

    /// How long the light show + horn runs, in seconds.
    @Published var celebrationDuration: TimeInterval {
        didSet { defaults.set(celebrationDuration, forKey: Key.celebrationDuration) }
    }

    /// Which HomeKit light services participate in the beacon effect.
    /// Stored as `HMService.uniqueIdentifier` UUID strings.
    @Published var selectedLightIDs: Set<String> {
        didSet { defaults.set(Array(selectedLightIDs), forKey: Key.selectedLightIDs) }
    }

    /// The chosen goal song.
    @Published var selectedTrackID: UUID? {
        didSet { defaults.set(selectedTrackID?.uuidString, forKey: Key.selectedTrackID) }
    }

    /// Where the song plays.
    @Published var audioTarget: AudioTarget {
        didSet { defaults.set(audioTarget.rawValue, forKey: Key.audioTarget) }
    }

    /// The Sonos speaker to play on (nil until one is chosen).
    @Published var sonosDevice: SonosDevice? {
        didSet {
            if let device = sonosDevice, let data = try? JSONEncoder().encode(device) {
                defaults.set(data, forKey: Key.sonosDevice)
            } else {
                defaults.removeObject(forKey: Key.sonosDevice)
            }
        }
    }

    /// The colours the beacon cycles through, in order. An entry may be a
    /// "dark beat" (`isOff`), which is what makes red/off strobe.
    @Published var goalColors: [GoalLightColor] {
        didSet {
            if let data = try? JSONEncoder().encode(goalColors) {
                defaults.set(data, forKey: Key.goalColors)
            }
        }
    }

    /// How long the goal song runs for.
    @Published var songPlayback: SongPlaybackMode {
        didSet { defaults.set(songPlayback.rawValue, forKey: Key.songPlayback) }
    }

    /// Song length in seconds, used when `songPlayback` is `.fixed`.
    @Published var songDuration: TimeInterval {
        didSet { defaults.set(songDuration, forKey: Key.songDuration) }
    }

    /// Volume (0–100) to set on Sonos before playing the horn.
    @Published var sonosVolume: Int {
        didSet { defaults.set(sonosVolume, forKey: Key.sonosVolume) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.celebrationDuration = defaults.object(forKey: Key.celebrationDuration) as? TimeInterval ?? 12
        self.selectedLightIDs = Set((defaults.array(forKey: Key.selectedLightIDs) as? [String]) ?? [])
        self.audioTarget = AudioTarget(rawValue: defaults.string(forKey: Key.audioTarget) ?? "") ?? .sonos
        self.sonosVolume = defaults.object(forKey: Key.sonosVolume) as? Int ?? 45

        self.songPlayback = SongPlaybackMode(rawValue: defaults.string(forKey: Key.songPlayback) ?? "") ?? .full
        self.songDuration = defaults.object(forKey: Key.songDuration) as? TimeInterval ?? 20

        if let data = defaults.data(forKey: Key.goalColors),
           let colors = try? JSONDecoder().decode([GoalLightColor].self, from: data),
           !colors.isEmpty {
            self.goalColors = colors
        } else {
            self.goalColors = GoalLightColor.defaultSequence
        }

        if let raw = defaults.string(forKey: Key.selectedTrackID) {
            self.selectedTrackID = UUID(uuidString: raw)
        } else {
            self.selectedTrackID = nil
        }

        if let data = defaults.data(forKey: Key.sonosDevice),
           let device = try? JSONDecoder().decode(SonosDevice.self, from: data) {
            self.sonosDevice = device
        } else {
            self.sonosDevice = nil
        }
    }
}
