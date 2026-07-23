import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            GoalScreen()
                .tabItem { Label("Goal", systemImage: "hockey.puck.fill") }

            AudioLibraryView()
                .tabItem { Label("Songs", systemImage: "music.note.list") }

            SonosSettingsView()
                .tabItem { Label("Sonos", systemImage: "hifispeaker.fill") }

            LightsSettingsView()
                .tabItem { Label("Lights", systemImage: "lightbulb.fill") }
        }
        .tint(.red)
    }
}

/// The main screen: a giant goal light you tap to score.
struct GoalScreen: View {
    @EnvironmentObject private var celebration: CelebrationController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var audioLibrary: AudioLibrary

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Text(celebration.isCelebrating ? "GOOOAL!" : "TAP THE LIGHT")
                    .font(.system(size: celebration.isCelebrating ? 44 : 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(celebration.isCelebrating ? .red : .white)
                    .animation(.spring(duration: 0.35), value: celebration.isCelebrating)
                    .shadow(color: .red.opacity(celebration.isCelebrating ? 0.8 : 0), radius: 20)

                Button(action: score) {
                    BeaconView(active: celebration.isCelebrating)
                        .frame(maxWidth: 300)
                        .scaleEffect(celebration.isCelebrating ? 1.05 : 1.0)
                        .animation(.spring(duration: 0.4), value: celebration.isCelebrating)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trigger goal horn")

                if celebration.isCelebrating {
                    Button(role: .destructive, action: celebration.stop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .tint(.white)
                    .transition(.opacity)
                }

                readinessSummary
            }
            .padding()
        }
    }

    @ViewBuilder
    private var readinessSummary: some View {
        VStack(spacing: 8) {
            if let message = celebration.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            HStack(spacing: 18) {
                statusChip(
                    ok: audioLibrary.track(withID: settings.selectedTrackID) != nil || !audioLibrary.tracks.isEmpty,
                    icon: "music.note",
                    label: songLabel
                )
                statusChip(
                    ok: !settings.selectedLightIDs.isEmpty,
                    icon: "lightbulb",
                    label: "\(settings.selectedLightIDs.count) light\(settings.selectedLightIDs.count == 1 ? "" : "s")"
                )
                statusChip(
                    ok: settings.audioTarget == .phone || settings.sonosDevice != nil,
                    icon: settings.audioTarget == .phone ? "iphone" : "hifispeaker",
                    label: settings.audioTarget == .phone ? "iPhone" : (settings.sonosDevice?.roomName ?? "No Sonos")
                )
            }
        }
        .padding(.top, 8)
        .animation(.default, value: celebration.statusMessage)
    }

    private var songLabel: String {
        if let track = audioLibrary.track(withID: settings.selectedTrackID) { return track.title }
        if let first = audioLibrary.tracks.first { return first.title }
        return "No song"
    }

    private func statusChip(ok: Bool, icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(ok ? .green : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: 90)
    }

    private func score() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        celebration.triggerGoal()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(HomeKitManager())
        .environmentObject(AudioLibrary())
        .environmentObject(SonosController())
        .environmentObject(CelebrationController(
            settings: AppSettings(),
            homeKit: HomeKitManager(),
            audioLibrary: AudioLibrary(),
            sonos: SonosController()
        ))
}
