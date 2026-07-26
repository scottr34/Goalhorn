import SwiftUI

// MARK: - Color hex helper

extension Color {
    /// Create a Color from a 0xRRGGBB hex literal.
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Design tokens (from the "1A — Arena Realism" handoff)

private enum Lamp {
    // Reference dome geometry (px). Everything scales off `domeWidth / refWidth`.
    static let refWidth: CGFloat = 198
    static let refHeight: CGFloat = 327

    static let glassStops: [Gradient.Stop] = [
        .init(color: Color(hex: 0xFFCFC4), location: 0.00),
        .init(color: Color(hex: 0xFF8A70), location: 0.16),
        .init(color: Color(hex: 0xE80C0C), location: 0.46),
        .init(color: Color(hex: 0x8A0000), location: 0.78),
        .init(color: Color(hex: 0x4A0000), location: 1.00),
    ]

    // Brushed-steel gradient for cage bars (linear-gradient 180deg).
    static let metal = Gradient(stops: [
        .init(color: Color(hex: 0x7A7A7E), location: 0.00),
        .init(color: Color(hex: 0x55555A), location: 0.55),
        .init(color: Color(hex: 0x333336), location: 1.00),
    ])

    // Base/mount bar gradient (55% -> 60% midpoint per source).
    static let base = Gradient(stops: [
        .init(color: Color(hex: 0x7A7A7E), location: 0.00),
        .init(color: Color(hex: 0x55555A), location: 0.60),
        .init(color: Color(hex: 0x333336), location: 1.00),
    ])

    static let frame = Color(hex: 0x5E5E63)
    static let glow = Color(hex: 0xFF2828)
}

// MARK: - Goal lamp

/// The caged arena goal light: glass dome + steel cage + mount bar, with the
/// three concurrent animations (flash / glow pulse / sweeping beam) driven while
/// `isActive`, and a one-shot strobe fired each time `flashTrigger` changes.
struct GoalLampView: View {
    /// Rendered width of the glass dome; all other metrics scale from it.
    var domeWidth: CGFloat
    /// While true, the glow pulses and the beam sweeps (the 2.4s window).
    var isActive: Bool
    /// Increment to fire the 2.2s flash/strobe once.
    var flashTrigger: Int

    @State private var glowPeak = false
    @State private var sweepRight = false
    @State private var beamVisible = false

    private var s: CGFloat { domeWidth / Lamp.refWidth }
    private var domeHeight: CGFloat { Lamp.refHeight * s }

    var body: some View {
        let baseH = 34 * s
        ZStack(alignment: .bottom) {
            // Soft shadow on the "floor" beneath everything.
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 130 * s))
                .frame(width: 260 * s, height: 26 * s)
                .offset(y: baseH * 0.4)

            // The glass dome + cage — this whole group strobes with the flash.
            domeGroup
                .offset(y: -baseH * 0.5)

            // Mount bar, drawn in front so it overlaps the cage's lower edge.
            RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                .fill(LinearGradient(gradient: Lamp.base, startPoint: .top, endPoint: .bottom))
                .frame(width: 232 * s, height: baseH)
                .shadow(color: .black.opacity(0.55), radius: 10 * s, x: 0, y: 8 * s)
        }
        .frame(width: 260 * s, height: domeHeight + baseH * 0.9)
        .onChange(of: isActive) { _, active in animateLoops(active) }
    }

    // MARK: Dome group (flash target)

    private var domeGroup: some View {
        ZStack {
            glowLayers
            domeShape.fill(glassStyle)
                .frame(width: domeWidth, height: domeHeight)
            clippedInterior
            domeShape
                .strokeBorder(Lamp.frame, lineWidth: 12 * s)
                .frame(width: domeWidth, height: domeHeight)
        }
        .frame(width: domeWidth, height: domeHeight)
        .keyframeAnimator(initialValue: 1.0, trigger: flashTrigger) { content, opacity in
            content.opacity(opacity)
        } keyframes: { _ in
            // flashA: 2.2s, dips to 0.25 at 15/45/75%, back to 1 at 30/60/90%.
            KeyframeTrack(\.self) {
                CubicKeyframe(0.25, duration: 0.33)
                CubicKeyframe(1.00, duration: 0.33)
                CubicKeyframe(0.25, duration: 0.33)
                CubicKeyframe(1.00, duration: 0.33)
                CubicKeyframe(0.25, duration: 0.33)
                CubicKeyframe(1.00, duration: 0.33)
                CubicKeyframe(1.00, duration: 0.22)
            }
        }
    }

    // Ambient red halo (present at rest, intensifies on the glow pulse).
    private var glowLayers: some View {
        ZStack {
            domeShape.fill(Lamp.glow)
                .frame(width: domeWidth, height: domeHeight)
                .blur(radius: (glowPeak ? 48 : 30) * s)
                .opacity(glowPeak ? 0.90 : 0.55)
                .scaleEffect(glowPeak ? 1.15 : 1.00)
            domeShape.fill(Lamp.glow)
                .frame(width: domeWidth, height: domeHeight)
                .blur(radius: (glowPeak ? 100 : 70) * s)
                .opacity(glowPeak ? 0.50 : 0.25)
                .scaleEffect(glowPeak ? 1.30 : 1.15)
        }
    }

    // Beam + cage bars + glass highlight, clipped to the dome bounds.
    private var clippedInterior: some View {
        ZStack {
            // Sweeping beam — reads as the bulb spinning. mix-blend screen.
            Rectangle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .white.opacity(0.85), location: 0.45),
                        .init(color: .white.opacity(0.85), location: 0.55),
                        .init(color: .clear, location: 1.00),
                    ],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 0.55 * domeWidth, height: domeHeight)
                .blendMode(.screen)
                .opacity(beamVisible ? 1 : 0)
                .offset(x: sweepRight ? 0.385 * domeWidth : -0.385 * domeWidth)

            // Horizontal cage bars at 68 / 140 / 213px tops (centers +6).
            ForEach([74.0, 146.0, 219.0], id: \.self) { cy in
                Rectangle()
                    .fill(LinearGradient(gradient: Lamp.metal, startPoint: .top, endPoint: .bottom))
                    .frame(width: domeWidth, height: 12 * s)
                    .shadow(color: .black.opacity(0.6), radius: 1.5 * s, y: 2 * s)
                    .position(x: domeWidth / 2, y: cy * s)
            }

            // Vertical center bar (horizontal metal gradient).
            Rectangle()
                .fill(LinearGradient(gradient: Lamp.metal, startPoint: .leading, endPoint: .trailing))
                .frame(width: 12 * s, height: domeHeight)
                .shadow(color: .black.opacity(0.6), radius: 1.5 * s, x: 2 * s)
                .position(x: domeWidth / 2, y: domeHeight / 2)

            // Glass reflection highlight, top-left.
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.40), .clear],
                                     center: .center, startRadius: 0, endRadius: 40 * s))
                .frame(width: 48 * s, height: 90 * s)
                .position(x: 58 * s, y: 85 * s)
        }
        .frame(width: domeWidth, height: domeHeight)
        .clipShape(domeShape)
    }

    // MARK: Shape + styles

    private var domeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 91 * s,
            bottomLeadingRadius: 26 * s,
            bottomTrailingRadius: 26 * s,
            topTrailingRadius: 91 * s,
            style: .continuous
        )
    }

    // Glass fill: radial red gradient + inset shadows for the 3D curve.
    private var glassStyle: some ShapeStyle {
        RadialGradient(
            gradient: Gradient(stops: Lamp.glassStops),
            center: UnitPoint(x: 0.38, y: 0.26),
            startRadius: 0,
            endRadius: domeWidth * 1.368
        )
        .shadow(.inner(color: .black.opacity(0.55), radius: 25 * s, x: -15 * s, y: -18 * s))
        .shadow(.inner(color: .white.opacity(0.35), radius: 20 * s, x: 11 * s, y: 13 * s))
        .shadow(.inner(color: .black.opacity(0.70), radius: 10 * s))
    }

    // MARK: Animation control

    private func animateLoops(_ active: Bool) {
        if active {
            beamVisible = true
            withAnimation(.easeInOut(duration: 0.30).repeatForever(autoreverses: true)) {
                glowPeak = true
            }
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                sweepRight = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                glowPeak = false
                sweepRight = false
                beamVisible = false
            }
        }
    }
}

#Preview {
    ZStack {
        RadialGradient(colors: [Color(hex: 0x232326), Color(hex: 0x08080A)],
                       center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 500)
            .ignoresSafeArea()
        GoalLampView(domeWidth: 240, isActive: false, flashTrigger: 0)
    }
}
