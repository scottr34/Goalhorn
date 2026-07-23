import SwiftUI

/// An animated arena goal light. When `active` it spins fast and cycles red/blue
/// like the real thing; at rest it glows a slow, dim red.
struct BeaconView: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let spinSpeed: Double = active ? 300 : 40
            let angle = Angle(degrees: (t * spinSpeed).truncatingRemainder(dividingBy: 360))
            let isRed = Int(t / 0.9) % 2 == 0
            let beam: Color = active ? (isRed ? .red : Color(red: 0.15, green: 0.45, blue: 1.0)) : .red

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                ZStack {
                    // Ambient glow cast onto the surroundings.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [beam.opacity(active ? 0.55 : 0.22), .clear],
                                center: .center,
                                startRadius: size * 0.1,
                                endRadius: size * 0.75
                            )
                        )
                        .blur(radius: 18)
                        .scaleEffect(1.35)

                    // Metallic housing.
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.28), Color(white: 0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().strokeBorder(Color(white: 0.5), lineWidth: size * 0.02))
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 8)

                    // Illuminated dome.
                    Circle()
                        .inset(by: size * 0.1)
                        .fill(
                            RadialGradient(
                                colors: [beam.opacity(0.95), beam.opacity(0.5), beam.opacity(0.2)],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.4
                            )
                        )

                    // Rotating light lobes (the "sweep").
                    Circle()
                        .inset(by: size * 0.1)
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    beam.opacity(0), beam, .white.opacity(active ? 0.9 : 0.4), beam, beam.opacity(0),
                                    .clear,
                                    beam.opacity(0), beam, .white.opacity(active ? 0.9 : 0.4), beam, beam.opacity(0),
                                    .clear
                                ]),
                                center: .center
                            )
                        )
                        .rotationEffect(angle)
                        .blur(radius: size * 0.02)
                        .mask(Circle().inset(by: size * 0.1))

                    // Glass highlight.
                    Circle()
                        .inset(by: size * 0.1)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .mask(Circle().inset(by: size * 0.1))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        BeaconView(active: true)
            .frame(width: 240, height: 240)
    }
}
