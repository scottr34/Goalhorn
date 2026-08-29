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

/// The main screen: the goal light standing in a dark room, on the floor it
/// lights up. Tapping anywhere fires the horn and the light show.
///
/// The fixture itself is `GoalLampView`; this view is the room around it and
/// the app chrome. Both follow `design/main-screen/`.
struct GoalScreen: View {
    @EnvironmentObject private var celebration: CelebrationController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var audioLibrary: AudioLibrary

    /// Which beat of the colour sequence the on-screen lamp is showing.
    @State private var beat = 0

    /// The controller owns the celebration window, so hitting Stop anywhere
    /// clears the screen too.
    private var isFiring: Bool { celebration.isCelebrating }

    /// Matches `GoalLightEngine.colorHoldPeriod`, so the screen and the bulbs
    /// change colour together.
    private let beatTimer = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    private var palette: [GoalLightColor] {
        settings.goalColors.isEmpty ? GoalLightColor.defaultSequence : settings.goalColors
    }

    private var currentColor: GoalLightColor? {
        guard isFiring else { return nil }
        return palette[beat % palette.count]
    }

    var body: some View {
        GeometryReader { geo in
            // The fixture is tall, so size it to whatever is left after the
            // label and the status chips.
            // Label + chips + their padding, which the lamp has to fit around.
            let chromeHeight: CGFloat = 112
            let lampWidth = min(geo.size.width * 0.9,
                                (geo.size.height - chromeHeight - 56) / Fixture.aspect,
                                420)
            let lampHeight = lampWidth * Fixture.aspect
            // Where the fixture's foot actually lands, so the floor line meets
            // the base rather than floating near it.
            let lampTop = max(12, (geo.size.height - lampHeight - chromeHeight) / 2)
            let floorY = lampTop + lampHeight * (694 / Fixture.refH)

            ZStack {
                room(size: geo.size, floorY: floorY)

                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    GoalLampView(width: lampWidth, isActive: isFiring, lit: currentColor)
                    statusLabel
                        .padding(.top, 10)
                    readyChips
                        .padding(.top, 14)
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .compositingGroup()
            .contentShape(Rectangle())
            .onTapGesture { score() }
            .overlay(alignment: .topTrailing) {
                settingsGlyph
                    .padding(.top, 18)
                    .padding(.trailing, 20)
            }
        }
        .onReceive(beatTimer) { _ in
            if isFiring { beat += 1 }
        }
        .onChange(of: celebration.isCelebrating) { _, firing in
            if firing { beat = 0 }
        }
    }

    // MARK: - The room

    private func room(size: CGSize, floorY: CGFloat) -> some View {
        ZStack {
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0x26262B), location: 0.00),
                    .init(color: Color(hex: 0x16161A), location: 0.34),
                    .init(color: Color(hex: 0x0A0A0C), location: 0.68),
                    .init(color: Color(hex: 0x050506), location: 1.00),
                ],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.8
            )
            .ignoresSafeArea()

            // The surface the fixture stands on, and the pool of light it casts.
            VStack(spacing: 0) {
                Spacer().frame(height: floorY)
                LinearGradient(
                    colors: [.white.opacity(0.05), .black.opacity(0.34), .black.opacity(0.64)],
                    startPoint: .top, endPoint: .bottom
                )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.14), .white.opacity(0.14), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 1)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if let color = currentColor, !color.isOff {
                Ellipse()
                    .fill(RadialGradient(colors: [color.swatch.opacity(0.66), color.swatch.opacity(0.22), .clear],
                                         center: .center, startRadius: 0, endRadius: 200))
                    .frame(width: size.width * 1.5, height: 150)
                    .blur(radius: 22)
                    .position(x: size.width / 2, y: floorY + 24)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Chrome

    private var statusLabel: some View {
        Text(isFiring ? "GOAL!" : "TAP FOR A GOAL!")
            .font(.system(size: isFiring ? 46 : 19, weight: isFiring ? .bold : .medium))
            .tracking(isFiring ? 3 : 4)
            .foregroundStyle(isFiring ? Color(hex: 0xFF4D3D) : Color(hex: 0x8A8A90))
            .shadow(color: isFiring ? Color(hex: 0xFF3C32, alpha: 0.8) : .clear, radius: isFiring ? 20 : 0)
            .animation(.easeInOut(duration: 0.2), value: isFiring)
            .frame(height: 54)
    }

    /// What is armed right now, so the screen is not just a button.
    private var readyChips: some View {
        HStack(spacing: 8) {
            chip(systemImage: "music.note", text: songName)
            chip(systemImage: "waveform", text: outputName)
        }
    }

    private var songName: String {
        let track = audioLibrary.track(withID: settings.selectedTrackID) ?? audioLibrary.tracks.first
        return track?.title ?? "No song yet"
    }

    private var outputName: String {
        switch settings.audioTarget {
        case .phone: return "This iPhone"
        case .sonos: return settings.sonosDevice.map { "\($0.roomName) · \(settings.sonosVolume)%" } ?? "No Sonos"
        }
    }

    private func chip(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: 0x6F6F77))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x9A9AA1))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
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
        beat = 0
        celebration.triggerGoal()       // audio + HomeKit lights
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
