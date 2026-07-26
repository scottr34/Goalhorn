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

/// The main screen ("1A — Arena Realism"): a caged goal light on a dark radial
/// field. Tapping anywhere fires the goal horn and runs the ~2.4s light show.
struct GoalScreen: View {
    @EnvironmentObject private var celebration: CelebrationController

    /// Local 2.4s visual window (independent of the longer HomeKit light show).
    @State private var isFiring = false
    /// Bumped on each tap to fire the one-shot flash/strobe.
    @State private var flashTick = 0

    var body: some View {
        GeometryReader { geo in
            let domeWidth = min(geo.size.width * 0.72, 300)
            let s = domeWidth / 198

            ZStack {
                // Background: radial gradient #232326 (center) -> #08080a (edges).
                RadialGradient(
                    gradient: Gradient(colors: [Color(hex: 0x232326), Color(hex: 0x08080A)]),
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    GoalLampView(domeWidth: domeWidth, isActive: isFiring, flashTrigger: flashTick)
                    statusLabel(scale: s)
                        .padding(.top, 26 * s)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { score() }
            .overlay(alignment: .topTrailing) {
                settingsGlyph
                    .padding(.top, 18)
                    .padding(.trailing, 20)
            }
        }
    }

    private func statusLabel(scale s: CGFloat) -> some View {
        Text(isFiring ? "GOAL!" : "TAP FOR A GOAL!")
            .font(.system(size: (isFiring ? 34 : 14) * s, weight: isFiring ? .bold : .medium))
            .tracking((isFiring ? 3 : 4) * s)
            .foregroundStyle(isFiring ? Color(hex: 0xFF4D3D) : Color(hex: 0x8A8A90))
            .shadow(color: isFiring ? Color(hex: 0xFF3C32, alpha: 0.8) : .clear, radius: isFiring ? 18 * s : 0)
            .animation(.easeInOut(duration: 0.2), value: isFiring)
    }

    /// Top-right equalizer/settings glyph — stub entry to the sound/HomeKit
    /// picker (navigation intentionally not wired yet).
    private var settingsGlyph: some View {
        Button {
            // TODO: navigate to sound / HomeKit picker screen.
        } label: {
            HStack(alignment: .bottom, spacing: 4) {
                bar(height: 8, color: Color(hex: 0xBBBBBB))
                bar(height: 14, color: Color(hex: 0xDDDDDD))
                bar(height: 6, color: Color(hex: 0x999999))
            }
            .padding(8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private func bar(height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: height)
    }

    private func score() {
        guard !isFiring else { return } // debounce repeat taps while active
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        celebration.triggerGoal()       // existing: audio + HomeKit lights

        flashTick += 1
        isFiring = true
        // Auto-reset to idle after the 2.4s show.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            isFiring = false
        }
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
