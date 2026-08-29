import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One beat in the goal-light sequence: a colour the bulbs turn, or a dark beat.
///
/// The beacon cycles through `AppSettings.goalColors` in order, holding each for
/// a beat, so `[.red, .white, .blue]` gives a red/white/blue spin and
/// `[.red, .off]` gives a red strobe.
struct GoalLightColor: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// HomeKit hue, 0–360. Ignored when `isOff`.
    var hue: Double
    /// HomeKit saturation, 0–100. Zero is white. Ignored when `isOff`.
    var saturation: Double
    /// A dark beat. The bulbs drop to zero brightness rather than powering off —
    /// a power cycle is far too slow in HomeKit to read as a strobe.
    var isOff: Bool

    init(id: UUID = UUID(), name: String, hue: Double, saturation: Double, isOff: Bool = false) {
        self.id = id
        self.name = name
        self.hue = hue
        self.saturation = saturation
        self.isOff = isOff
    }

    /// A copy with a fresh identity, so the same preset can appear twice in a
    /// sequence without colliding in a `ForEach`.
    func fresh() -> GoalLightColor {
        var copy = self
        copy.id = UUID()
        return copy
    }

    /// Equal as a *colour* — ignores identity, for comparing sequences.
    func matches(_ other: GoalLightColor) -> Bool {
        isOff == other.isOff && (isOff || (hue == other.hue && saturation == other.saturation))
    }

    /// How this beat looks in the UI.
    var swatch: Color {
        isOff ? Color(white: 0.12) : Color(hue: hue / 360, saturation: saturation / 100, brightness: 1)
    }
}

// MARK: - Presets

extension GoalLightColor {
    static let red = GoalLightColor(name: "Red", hue: 0, saturation: 100)
    static let white = GoalLightColor(name: "White", hue: 0, saturation: 0)
    static let blue = GoalLightColor(name: "Blue", hue: 222, saturation: 100)
    static let green = GoalLightColor(name: "Green", hue: 120, saturation: 100)
    static let amber = GoalLightColor(name: "Amber", hue: 38, saturation: 100)
    static let purple = GoalLightColor(name: "Purple", hue: 280, saturation: 100)
    static let cyan = GoalLightColor(name: "Cyan", hue: 190, saturation: 100)
    static let pink = GoalLightColor(name: "Pink", hue: 330, saturation: 75)
    static let off = GoalLightColor(name: "Off", hue: 0, saturation: 0, isOff: true)

    static var presets: [GoalLightColor] {
        [red, white, blue, green, amber, purple, cyan, pink, off]
    }

    /// The classic arena red/blue spin, used until the user changes it.
    static var defaultSequence: [GoalLightColor] { [red, blue].map { $0.fresh() } }

    #if canImport(UIKit)
    /// Build a beat from a colour the user picked in a `ColorPicker`.
    init(custom color: Color, name: String = "Custom") {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.init(name: name, hue: Double(h) * 360, saturation: Double(s) * 100)
    }
    #endif
}

// MARK: - Ready-made sequences

/// A named sequence the user can apply in one tap.
struct GoalLightSequence: Identifiable {
    var name: String
    var colors: [GoalLightColor]

    var id: String { name }

    /// Fresh copies, so applying a preset twice never duplicates identities.
    var freshColors: [GoalLightColor] { colors.map { $0.fresh() } }

    static let presets: [GoalLightSequence] = [
        GoalLightSequence(name: "Red / Blue", colors: [.red, .blue]),
        GoalLightSequence(name: "Red / White / Blue", colors: [.red, .white, .blue]),
        GoalLightSequence(name: "Red / White", colors: [.red, .white]),
        GoalLightSequence(name: "Red / Off", colors: [.red, .off]),
    ]
}

extension Array where Element == GoalLightColor {
    /// Sequence comparison that ignores identity.
    func matchesSequence(_ other: [GoalLightColor]) -> Bool {
        count == other.count && zip(self, other).allSatisfy { $0.matches($1) }
    }

    /// "Red → White → Blue"
    var sequenceDescription: String {
        isEmpty ? "None" : map(\.name).joined(separator: " → ")
    }
}
