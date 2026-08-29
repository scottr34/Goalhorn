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

// MARK: - Fixture geometry
//
// A direct port of `design/main-screen/build.mjs`, which is the source of truth
// for the shape. Everything is expressed in that file's 440 x 740 reference
// space and scaled as a whole, so the two stay comparable line for line.
//
// The fixture is the classic rink goal light: a TALL vertically-fluted red lens,
// a thin bright wire guard, and a heavy satin-aluminium base that flares at the
// foot.

enum Fixture {
    static let refW: CGFloat = 440
    static let refH: CGFloat = 740
    static let aspect: CGFloat = refH / refW

    static let cx: CGFloat = 220
    static let rLens: CGFloat = 118
    static let rCage: CGFloat = 125
    static let yApex: CGFloat = 40
    static let yShoulder: CGFloat = 158
    static let yLensBot: CGFloat = 406
    static let yCageApex: CGFloat = 34
    static var rvCage: CGFloat { yShoulder - yCageApex }
    /// Camera height, which sets how much each guard hoop curves.
    static let eye: CGFloat = 340

    /// Gradient endpoints spanning an x-range of the reference box. SwiftUI
    /// gradients are unit-space over the whole view, so this is how a sub-region
    /// gets its own ramp — the equivalent of SVG's `userSpaceOnUse`.
    static func hSpan(_ x0: CGFloat, _ x1: CGFloat) -> (start: UnitPoint, end: UnitPoint) {
        (UnitPoint(x: x0 / refW, y: 0.5), UnitPoint(x: x1 / refW, y: 0.5))
    }

    static func vSpan(_ y0: CGFloat, _ y1: CGFloat) -> (start: UnitPoint, end: UnitPoint) {
        (UnitPoint(x: 0.5, y: y0 / refH), UnitPoint(x: 0.5, y: y1 / refH))
    }

    // MARK: Guard wires

    struct Wire {
        let x: CGFloat
        let width: CGFloat
        /// How square-on this wire faces us: 1 at the front, 0 at the silhouette.
        let facing: CGFloat
        let path: Path
    }

    /// A point on the guard meridian at azimuth `t`, polar angle `phi` from the apex.
    private static func meridian(_ t: CGFloat, _ phi: CGFloat) -> CGPoint {
        CGPoint(
            x: cx + rCage * sin(phi) * sin(t),
            y: yCageApex + rvCage * (1 - cos(phi)) - 5 * cos(t) * cos(phi)
        )
    }

    private static var phiRing: CGFloat { asin(20 / rCage) }
    static var ringCY: CGFloat { yCageApex + rvCage * (1 - cos(phiRing)) }

    /// Wires sit at even azimuths, so on screen they bunch toward the silhouette
    /// and foreshorten. Over the cap each one follows its real meridian, so it
    /// hugs the lens instead of bowing past it.
    static let wires: [Wire] = [0, 20, -20, 40, -40, 60, -60, 80, -80].map { degrees in
        let t = CGFloat(degrees) * .pi / 180
        let x = cx + rCage * sin(t)
        let facing = abs(cos(t))

        var path = Path()
        path.move(to: CGPoint(x: x, y: 414))
        path.addLine(to: CGPoint(x: x, y: yShoulder - 2))
        let steps = 8
        for step in 1...steps {
            let phi = .pi / 2 + (phiRing - .pi / 2) * (CGFloat(step) / CGFloat(steps))
            path.addLine(to: meridian(t, phi))
        }

        return Wire(x: x, width: 6.4 * (0.32 + 0.68 * facing), facing: facing, path: path)
    }

    // MARK: Guard hoops

    struct Hoop {
        let y: CGFloat
        let front: Path
    }

    /// A hoop above eye level shows its near half as the TOP of the projected
    /// ellipse (it bulges up); below eye level the near half sags down.
    static let hoops: [Hoop] = [84, 132, 206, 282, 358].map { y in
        let dy = yShoulder - y
        let halfW = dy > 0
            ? rCage * sqrt(max(0, 1 - (dy / rvCage) * (dy / rvCage)))
            : rCage + 6
        let rise = ((eye - y) / 300) * 13

        var path = Path()
        path.move(to: CGPoint(x: cx - halfW, y: y))
        path.addQuadCurve(
            to: CGPoint(x: cx + halfW, y: y),
            control: CGPoint(x: cx, y: y - 2 * rise)
        )
        return Hoop(y: y, front: path)
    }

    // MARK: Vertical flutes

    struct Flute {
        let grooveX: CGFloat
        let grooveW: CGFloat
        let ridgeX: CGFloat
        let ridgeW: CGFloat
    }

    static let fluteTop: CGFloat = yShoulder - 30
    static var fluteHeight: CGFloat { yLensBot - fluteTop }

    /// The lens is a fluted Fresnel cylinder. Flutes are evenly spaced in ANGLE,
    /// so they bunch toward the silhouette exactly as the guard wires do — the
    /// strongest single cue that the red thing is glass and not a shape.
    static let flutes: [Flute] = stride(from: CGFloat(-84), through: 84, by: 8).map { degrees in
        let c = cos(degrees * .pi / 180)
        return Flute(
            grooveX: cx + rLens * sin(degrees * .pi / 180),
            grooveW: max(0.9, 2.6 * c),
            ridgeX: cx + rLens * sin((degrees + 4) * .pi / 180),
            ridgeW: max(0.9, 3.1 * c)
        )
    }

    // MARK: Materials

    /// Satin aluminium, shaded as a cylinder: key highlight left of centre, a
    /// dark turn, then a weaker bounce off the room on the far side. A
    /// top-to-bottom ramp would read as a flat slab.
    static let metal = Gradient(stops: [
        .init(color: Color(hex: 0x3F3B35), location: 0.00),
        .init(color: Color(hex: 0x6B665D), location: 0.06),
        .init(color: Color(hex: 0xCEC8BA), location: 0.22),
        .init(color: Color(hex: 0xB3ADA0), location: 0.34),
        .init(color: Color(hex: 0x8D887E), location: 0.50),
        .init(color: Color(hex: 0x615D56), location: 0.68),
        .init(color: Color(hex: 0x9C978C), location: 0.85),
        .init(color: Color(hex: 0x3A3731), location: 1.00),
    ])

    /// Bright warm chrome for the wire guard, dimmed as a wire turns away.
    static func wireGradient(facing: CGFloat) -> Gradient {
        func dim(_ hex: UInt, _ f: CGFloat) -> Color {
            Color(
                .sRGB,
                red: Double(CGFloat((hex >> 16) & 0xFF) / 255 * f),
                green: Double(CGFloat((hex >> 8) & 0xFF) / 255 * f),
                blue: Double(CGFloat(hex & 0xFF) / 255 * f),
                opacity: 1
            )
        }
        return Gradient(stops: [
            .init(color: dim(0x161513, 1), location: 0.00),
            .init(color: dim(0x6A655C, 0.60 + 0.40 * facing), location: 0.16),
            .init(color: dim(0xE8E2D5, 0.55 + 0.45 * facing), location: 0.38),
            .init(color: dim(0xA49D92, 0.58 + 0.42 * facing), location: 0.56),
            .init(color: dim(0x48453F, 0.70 + 0.30 * facing), location: 0.78),
            .init(color: dim(0x121110, 1), location: 1.00),
        ])
    }

    static let hoopGradient = Gradient(stops: [
        .init(color: Color(hex: 0x171614), location: 0.00),
        .init(color: Color(hex: 0xDED8CB), location: 0.30),
        .init(color: Color(hex: 0x8E8880), location: 0.55),
        .init(color: Color(hex: 0x3C3A35), location: 0.80),
        .init(color: Color(hex: 0x131211), location: 1.00),
    ])

    /// The lens with the lamp off: deep cherry, near-black where it turns away.
    static let lensDark = Gradient(stops: [
        .init(color: Color(hex: 0xA51E19), location: 0.00),
        .init(color: Color(hex: 0x78100E), location: 0.30),
        .init(color: Color(hex: 0x450807), location: 0.62),
        .init(color: Color(hex: 0x1C0303), location: 1.00),
    ])

    /// The lens with the lamp burning, in whatever colour the beat calls for.
    /// Red is just the default case of this, not a special one.
    static func lensLit(_ color: GoalLightColor) -> Gradient {
        let hue = color.hue / 360
        let sat = color.saturation / 100
        return Gradient(stops: [
            .init(color: .white, location: 0.00),
            .init(color: Color(hue: hue, saturation: sat * 0.5, brightness: 1.0), location: 0.12),
            .init(color: Color(hue: hue, saturation: sat, brightness: 1.0), location: 0.36),
            .init(color: Color(hue: hue, saturation: min(1, sat * 1.05), brightness: 0.52), location: 0.68),
            .init(color: Color(hue: hue, saturation: min(1, sat * 1.05), brightness: 0.22), location: 1.00),
        ])
    }
}

// MARK: - Shapes

/// The lens: a tall cylinder closed by a hemispherical cap.
struct LensShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Fixture.refW
        let sy = rect.height / Fixture.refH
        var path = Path()
        path.move(to: CGPoint(x: (Fixture.cx - Fixture.rLens) * sx, y: Fixture.yLensBot * sy))
        path.addLine(to: CGPoint(x: (Fixture.cx - Fixture.rLens) * sx, y: Fixture.yShoulder * sy))
        let capHeight = Fixture.yShoulder - Fixture.yApex
        let controlY = (Fixture.yShoulder - capHeight * 4 / 3) * sy
        path.addCurve(
            to: CGPoint(x: (Fixture.cx + Fixture.rLens) * sx, y: Fixture.yShoulder * sy),
            control1: CGPoint(x: (Fixture.cx - Fixture.rLens) * sx, y: controlY),
            control2: CGPoint(x: (Fixture.cx + Fixture.rLens) * sx, y: controlY)
        )
        path.addLine(to: CGPoint(x: (Fixture.cx + Fixture.rLens) * sx, y: Fixture.yLensBot * sy))
        path.closeSubpath()
        return path
    }
}

/// The flared skirt at the foot of the base.
private struct SkirtShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Fixture.refW
        let sy = rect.height / Fixture.refH
        var path = Path()
        path.move(to: CGPoint(x: 88 * sx, y: 614 * sy))
        path.addLine(to: CGPoint(x: 352 * sx, y: 614 * sy))
        path.addLine(to: CGPoint(x: 386 * sx, y: 674 * sy))
        path.addLine(to: CGPoint(x: 54 * sx, y: 674 * sy))
        path.closeSubpath()
        return path
    }
}

// MARK: - The fixture, drawn at reference scale

/// Everything below is laid out in the 440 x 740 reference box; `GoalLampView`
/// scales the whole thing, so these are the same numbers as the design file.
private struct FixtureView: View {
    /// The colour beat currently showing, or nil when the lamp is off.
    var lit: GoalLightColor?

    private var isDark: Bool { lit == nil || lit?.isOff == true }

    var body: some View {
        ZStack(alignment: .topLeading) {
            contactShadow
            lens
            guardCage
            base
        }
        .frame(width: Fixture.refW, height: Fixture.refH, alignment: .topLeading)
    }

    // MARK: Lens

    private var lens: some View {
        ZStack {
            LensShape().fill(
                RadialGradient(gradient: Fixture.lensDark, center: UnitPoint(x: 0.40, y: 0.30),
                               startRadius: 0, endRadius: 250)
            )

            if let lit, !lit.isOff {
                LensShape().fill(
                    RadialGradient(gradient: Fixture.lensLit(lit), center: UnitPoint(x: 0.50, y: 0.60),
                                   startRadius: 0, endRadius: 265)
                )
                .transition(.opacity)
            }

            lensInterior
            // Outline last, so the silhouette stays crisp.
            LensShape().stroke(Color(hex: 0x0A0A0D, alpha: 0.85), lineWidth: 2)
        }
        .frame(width: Fixture.refW, height: Fixture.refH)
    }

    private var lensInterior: some View {
        ZStack {
            flutes

            // Cylinder form: the left-right falloff that makes a tube a tube.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.74), location: 0.00),
                    .init(color: .black.opacity(0.24), location: 0.13),
                    .init(color: .white.opacity(0.08), location: 0.34),
                    .init(color: .black.opacity(0.12), location: 0.60),
                    .init(color: .black.opacity(0.60), location: 0.86),
                    .init(color: .black.opacity(0.82), location: 1.00),
                ],
                startPoint: Fixture.hSpan(102, 338).start,
                endPoint: Fixture.hSpan(102, 338).end
            )

            // Cap and foot darkening.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.30), location: 0.00),
                    .init(color: .clear, location: 0.16),
                    .init(color: .clear, location: 0.88),
                    .init(color: .black.opacity(0.50), location: 1.00),
                ],
                startPoint: Fixture.vSpan(Fixture.yApex, Fixture.yLensBot).start,
                endPoint: Fixture.vSpan(Fixture.yApex, Fixture.yLensBot).end
            )

            highlights

            // Inner rim darkening, and the meniscus where the lens meets the base.
            LensShape().stroke(Color.black.opacity(0.72), lineWidth: 24).blur(radius: 6)
            Rectangle()
                .fill(Color.black.opacity(0.45))
                .frame(width: 236, height: 22)
                .position(x: Fixture.cx, y: 357)
        }
        .frame(width: Fixture.refW, height: Fixture.refH)
        .clipShape(LensShape())
    }

    /// Drawn in a Canvas: ~40 thin bars is a lot of view tree for something
    /// entirely static.
    private var flutes: some View {
        Canvas { context, _ in
            for flute in Fixture.flutes {
                context.fill(
                    Path(CGRect(x: flute.ridgeX - flute.ridgeW / 2, y: Fixture.fluteTop,
                                width: flute.ridgeW, height: Fixture.fluteHeight)),
                    with: .color(.white.opacity(0.16))
                )
                context.fill(
                    Path(CGRect(x: flute.grooveX - flute.grooveW / 2, y: Fixture.fluteTop,
                                width: flute.grooveW, height: Fixture.fluteHeight)),
                    with: .color(Color(hex: 0x1A0000, alpha: 0.36))
                )
            }
        }
        .frame(width: Fixture.refW, height: Fixture.refH)
        // Fade the flutes in below the shoulder; over the cap they would be
        // parallel lines on a dome, which is wrong.
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .white, location: 0.24),
                    .init(color: .white, location: 1.00),
                ],
                startPoint: Fixture.vSpan(Fixture.fluteTop, Fixture.yLensBot).start,
                endPoint: Fixture.vSpan(Fixture.fluteTop, Fixture.yLensBot).end
            )
        }
    }

    private var highlights: some View {
        ZStack {
            // Broad soft highlight down the tube.
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.42), .clear],
                                     center: .center, startRadius: 0, endRadius: 96))
                .frame(width: 60, height: 192)
                .rotationEffect(.degrees(-4))
                .position(x: 160, y: 272)

            // Crisp specular core.
            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: 18, height: 104)
                .rotationEffect(.degrees(-5))
                .blur(radius: 3)
                .position(x: 157, y: 218)

            // Cap sheen.
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.34), .clear],
                                     center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 132, height: 52)
                .position(x: 197, y: 82)

            // Environment rim down the far edge.
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 11, height: 240)
                .blur(radius: 6)
                .position(x: 324, y: 264)
        }
    }

    // MARK: Guard

    private var guardCage: some View {
        ZStack {
            // Contact shadow the guard drops onto the lens.
            ZStack {
                ForEach(Array(Fixture.wires.enumerated()), id: \.offset) { _, wire in
                    wire.path.stroke(Color.black, lineWidth: wire.width)
                }
                ForEach(Array(Fixture.hoops.enumerated()), id: \.offset) { _, hoop in
                    hoop.front.stroke(Color.black, lineWidth: 6)
                }
            }
            .frame(width: Fixture.refW, height: Fixture.refH)
            .clipShape(LensShape())
            .offset(x: 2, y: 3)
            .blur(radius: 6)
            .opacity(0.18)

            ForEach(Array(Fixture.hoops.enumerated()), id: \.offset) { _, hoop in
                let span = Fixture.vSpan(hoop.y - 3.4, hoop.y + 3.4)
                hoop.front.stroke(
                    LinearGradient(gradient: Fixture.hoopGradient, startPoint: span.start, endPoint: span.end),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
            }

            // Hoop ends darken as they turn away from us.
            ForEach(Array(Fixture.hoops.enumerated()), id: \.offset) { _, hoop in
                hoop.front.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: 0x0A0908, alpha: 0.85), location: 0.0),
                            .init(color: Color(hex: 0x0A0908, alpha: 0.25), location: 0.2),
                            .init(color: .clear, location: 0.5),
                            .init(color: Color(hex: 0x0A0908, alpha: 0.25), location: 0.8),
                            .init(color: Color(hex: 0x0A0908, alpha: 0.85), location: 1.0),
                        ],
                        startPoint: Fixture.hSpan(Fixture.cx - Fixture.rCage - 6, Fixture.cx + Fixture.rCage + 6).start,
                        endPoint: Fixture.hSpan(Fixture.cx - Fixture.rCage - 6, Fixture.cx + Fixture.rCage + 6).end
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
            }

            ForEach(Array(Fixture.wires.enumerated()), id: \.offset) { _, wire in
                let span = Fixture.hSpan(wire.x - wire.width / 2, wire.x + wire.width / 2)
                wire.path.stroke(
                    LinearGradient(gradient: Fixture.wireGradient(facing: wire.facing),
                                   startPoint: span.start, endPoint: span.end),
                    style: StrokeStyle(lineWidth: wire.width, lineCap: .round)
                )
            }

            // Top hub the wires fan into.
            Ellipse()
                .fill(LinearGradient(
                    colors: [Color(hex: 0xCAC4B7), Color(hex: 0x7D786F), Color(hex: 0x26241F)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 48, height: 16)
                .position(x: Fixture.cx, y: Fixture.ringCY)
        }
        .frame(width: Fixture.refW, height: Fixture.refH)
    }

    // MARK: Base

    private var base: some View {
        ZStack(alignment: .topLeading) {
            tier(x: 90, y: 396, w: 260, h: 36, radius: 3)
            Ellipse()
                .fill(LinearGradient(gradient: Fixture.metal, startPoint: .leading, endPoint: .trailing))
                .frame(width: 260, height: 14)
                .position(x: Fixture.cx, y: 398)

            tier(x: 96, y: 430, w: 248, h: 96, radius: 2)
            topEdge(x: 96, y: 430, w: 248)

            // Raised boss and vent slot.
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient(gradient: Fixture.metal, startPoint: .leading, endPoint: .trailing))
                .frame(width: 176, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color(hex: 0x211F1B, alpha: 0.45), lineWidth: 1)
                )
                .position(x: 220, y: 471)
            Capsule()
                .fill(Color(hex: 0x141311, alpha: 0.82))
                .frame(width: 92, height: 11)
                .position(x: 196, y: 470.5)

            tier(x: 88, y: 522, w: 264, h: 96, radius: 2)
            topEdge(x: 88, y: 522, w: 264)
            rivets

            SkirtShape().fill(
                LinearGradient(gradient: Fixture.metal,
                               startPoint: Fixture.hSpan(54, 386).start,
                               endPoint: Fixture.hSpan(54, 386).end)
            )
            .opacity(0.78)
            .frame(width: Fixture.refW, height: Fixture.refH)

            tier(x: 50, y: 670, w: 340, h: 24, radius: 3)
            topEdge(x: 50, y: 670, w: 340)
        }
        .frame(width: Fixture.refW, height: Fixture.refH, alignment: .topLeading)
        .overlay(baseSpill)
    }

    /// One cylindrical tier of the base, shaded across rather than down.
    private func tier(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(gradient: Fixture.metal, startPoint: .leading, endPoint: .trailing))
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
    }

    private func topEdge(x: CGFloat, y: CGFloat, w: CGFloat) -> some View {
        Rectangle()
            .fill(Color(hex: 0xE6E0D2, alpha: 0.32))
            .frame(width: w, height: 2.5)
            .position(x: x + w / 2, y: y + 1.25)
    }

    private var rivets: some View {
        ForEach(0..<9, id: \.self) { index in
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xE4DED1), Color(hex: 0x8E8980), Color(hex: 0x33302B)],
                    center: UnitPoint(x: 0.34, y: 0.3), startRadius: 0, endRadius: 9))
                .frame(width: 9.2, height: 9.2)
                .position(x: 110 + CGFloat(index) * 27.5, y: 537)
        }
    }

    /// Red bounce the metal picks up once the lamp is burning.
    @ViewBuilder
    private var baseSpill: some View {
        if let lit, !lit.isOff {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(lit.swatch).frame(width: 260, height: 36).position(x: 220, y: 414)
                Rectangle().fill(lit.swatch).frame(width: 248, height: 96).position(x: 220, y: 478)
                Rectangle().fill(lit.swatch).frame(width: 264, height: 96).position(x: 220, y: 570)
            }
            .frame(width: Fixture.refW, height: Fixture.refH, alignment: .topLeading)
            .blendMode(.screen)
            .opacity(0.13)
            .allowsHitTesting(false)
        }
    }

    private var contactShadow: some View {
        Ellipse()
            .fill(RadialGradient(colors: [.black.opacity(0.75), .black.opacity(0.28), .clear],
                                 center: .center, startRadius: 0, endRadius: 212))
            .frame(width: 424, height: 36)
            .position(x: Fixture.cx, y: 706)
    }
}

// MARK: - The lamp, plus the light it throws into the room

/// The goal light as it appears on the Goal screen: the fixture itself, the halo
/// around the lens, and the two opposing beams a spinning reflector throws.
struct GoalLampView: View {
    /// Rendered width; the height follows the fixture's aspect.
    var width: CGFloat
    /// While true the beams sweep and the halo pulses.
    var isActive: Bool
    /// The colour beat currently showing. Nil leaves the lamp dark.
    var lit: GoalLightColor?

    @State private var spin = false
    @State private var pulse = false

    private var scale: CGFloat { width / Fixture.refW }
    private var height: CGFloat { width * Fixture.aspect }
    private var glowColor: Color { lit.map { $0.isOff ? .black : $0.swatch } ?? Color(hex: 0xFF2A14) }
    private var isGlowing: Bool { lit != nil && lit?.isOff != true }

    var body: some View {
        ZStack {
            beams
            halo
            FixtureView(lit: lit)
                .frame(width: Fixture.refW, height: Fixture.refH)
                .scaleEffect(scale, anchor: .center)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .onAppear { spin = true }
        .onChange(of: isActive) { _, active in
            withAnimation(active
                          ? .easeInOut(duration: 0.52).repeatForever(autoreverses: true)
                          : .easeOut(duration: 0.3)) {
                pulse = active
            }
        }
    }

    /// Two opposing wedges off a spinning reflector.
    private var beams: some View {
        let size = height * 2.2
        return ZStack {
            beamLayer(
                colors: [glowColor.opacity(0), glowColor.opacity(0.72), glowColor.opacity(0)],
                blur: 16 * scale
            )
            beamLayer(
                colors: [.clear, .white.opacity(0.55), .clear],
                blur: 4 * scale
            )
            .opacity(0.7)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: spin)
        .mask {
            RadialGradient(
                stops: [
                    .init(color: .white, location: 0.00),
                    .init(color: .white.opacity(0.9), location: 0.24),
                    .init(color: .white.opacity(0.45), location: 0.58),
                    .init(color: .clear, location: 0.86),
                ],
                center: .center, startRadius: 0, endRadius: size / 2)
        }
        .blendMode(.screen)
        .opacity(isGlowing ? 1 : 0)
        .animation(.easeInOut(duration: 0.45), value: isGlowing)
        .allowsHitTesting(false)
    }

    private func beamLayer(colors: [Color], blur: CGFloat) -> some View {
        let stops: [Gradient.Stop] = [
            .init(color: colors[0], location: 0.00),
            .init(color: colors[1], location: 0.025),
            .init(color: colors[2], location: 0.085),
            .init(color: colors[0], location: 0.47),
            .init(color: colors[1], location: 0.525),
            .init(color: colors[2], location: 0.585),
            .init(color: colors[0], location: 1.00),
        ]
        return AngularGradient(gradient: Gradient(stops: stops), center: .center)
            .blur(radius: blur)
    }

    /// The bloom around the lens itself.
    private var halo: some View {
        let lensTop = Fixture.yApex * scale
        let lensBottom = Fixture.yLensBot * scale
        return Ellipse()
            .fill(RadialGradient(
                colors: [glowColor.opacity(0.95), glowColor.opacity(0.42), .clear],
                center: .center, startRadius: 0, endRadius: 210 * scale))
            .frame(width: 420 * scale, height: (lensBottom - lensTop) + 150 * scale)
            .blur(radius: 38 * scale)
            .position(x: width / 2, y: (lensTop + lensBottom) / 2)
            .scaleEffect(pulse ? 1.05 : 1)
            .opacity(isGlowing ? (pulse ? 1 : 0.82) : 0.12)
            .blendMode(.screen)
            .animation(.easeInOut(duration: 0.35), value: isGlowing)
            .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        RadialGradient(colors: [Color(hex: 0x26262B), Color(hex: 0x050506)],
                       center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 500)
            .ignoresSafeArea()
        GoalLampView(width: 340, isActive: false, lit: nil)
    }
}
