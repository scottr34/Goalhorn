import SwiftUI

@main
struct GoalhornApp: App {
    /// Shared services, created once in `init` and injected into the hierarchy.
    @StateObject private var settings: AppSettings
    @StateObject private var homeKit: HomeKitManager
    @StateObject private var audioLibrary: AudioLibrary
    @StateObject private var sonos: SonosController

    /// The orchestrator that fires lights + audio together, built from the
    /// services above so everything shares the same instances.
    @StateObject private var celebration: CelebrationController

    init() {
        let settings = AppSettings()
        let homeKit = HomeKitManager()
        let audioLibrary = AudioLibrary()
        let sonos = SonosController()

        _settings = StateObject(wrappedValue: settings)
        _homeKit = StateObject(wrappedValue: homeKit)
        _audioLibrary = StateObject(wrappedValue: audioLibrary)
        _sonos = StateObject(wrappedValue: sonos)
        _celebration = StateObject(wrappedValue: CelebrationController(
            settings: settings,
            homeKit: homeKit,
            audioLibrary: audioLibrary,
            sonos: sonos
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(homeKit)
                .environmentObject(audioLibrary)
                .environmentObject(sonos)
                .environmentObject(celebration)
                .preferredColorScheme(.dark)
        }
    }
}
