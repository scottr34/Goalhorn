import Foundation
import HomeKit
import Combine

/// Drives the selected HomeKit lights as a spinning arena goal beacon.
///
/// The effect: a bright "beam" sweeps around the ring of selected bulbs while
/// the colour alternates between red and blue, mimicking a rotating goal light.
/// When it finishes (or is stopped) each light's previous state is restored.
///
/// HomeKit writes are relatively slow, so per-tick brightness updates are sent
/// fire-and-forget; only colour changes (a couple of times a second) are the
/// heavier writes.
@MainActor
final class GoalLightEngine: ObservableObject {
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?

    /// Snapshot of a light's characteristics so we can restore it afterwards.
    private struct LightState {
        var power: Bool?
        var brightness: Int?
        var hue: Double?
        var saturation: Double?
    }

    // Tuning.
    private let tickInterval: TimeInterval = 0.28
    private let rotationPeriod: TimeInterval = 1.15   // seconds per full sweep
    private let colorFlipPeriod: TimeInterval = 0.9   // seconds between red/blue
    private let redHue: Double = 0
    private let blueHue: Double = 222

    func start(on lights: [GoalLight], duration: TimeInterval) {
        guard !lights.isEmpty else { return }
        stop()
        isRunning = true
        task = Task { [weak self] in
            await self?.run(lights: lights, duration: duration)
            self?.isRunning = false
            self?.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    // MARK: - Effect

    private func run(lights: [GoalLight], duration: TimeInterval) async {
        let saved = await captureStates(lights)

        // Prime: power on, full saturation for vivid colour.
        for light in lights {
            fireWrite(true, to: light.power)
            fireWrite(100 as Int, to: light.saturation)
        }

        let start = Date()
        var lastColorWasRed: Bool?
        let n = max(lights.count, 1)

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= duration { break }

            let beamPos = (elapsed / rotationPeriod).truncatingRemainder(dividingBy: 1)
            let isRed = Int(elapsed / colorFlipPeriod) % 2 == 0

            // Flip colour only when it actually changes.
            if lastColorWasRed != isRed {
                let hue = isRed ? redHue : blueHue
                for light in lights { fireWrite(hue, to: light.hue) }
                lastColorWasRed = isRed
            }

            // Sweep the brightness "beam" around the ring of lights.
            for (index, light) in lights.enumerated() {
                let slot = Double(index) / Double(n)
                let distance = circularDistance(beamPos, slot)
                // Sharp falloff so one bulb clearly leads the sweep.
                let intensity = pow(max(0, 1 - distance * Double(n) * 0.6), 2)
                let brightness = Int(12 + 88 * intensity)
                fireWrite(brightness, to: light.brightness)
            }

            try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
        }

        await restore(saved, lights: lights)
    }

    /// Shortest distance between two positions on a unit circle (0...0.5).
    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }

    // MARK: - Capture / restore

    private func captureStates(_ lights: [GoalLight]) async -> [String: LightState] {
        var states: [String: LightState] = [:]
        for light in lights {
            let state = LightState(
                power: await readValue(light.power) as? Bool,
                brightness: (await readValue(light.brightness) as? NSNumber)?.intValue,
                hue: (await readValue(light.hue) as? NSNumber)?.doubleValue,
                saturation: (await readValue(light.saturation) as? NSNumber)?.doubleValue
            )
            states[light.id] = state
        }
        return states
    }

    private func restore(_ states: [String: LightState], lights: [GoalLight]) async {
        for light in lights {
            guard let state = states[light.id] else { continue }
            if let hue = state.hue { await write(hue, to: light.hue) }
            if let saturation = state.saturation { await write(saturation, to: light.saturation) }
            if let brightness = state.brightness { await write(brightness, to: light.brightness) }
            // Restore power last so an "off" light doesn't flash its old colour.
            if let power = state.power { await write(power, to: light.power) }
        }
    }

    // MARK: - Characteristic I/O

    /// Fire-and-forget write, used inside the animation loop for speed.
    private func fireWrite(_ value: Any, to characteristic: HMCharacteristic?) {
        characteristic?.writeValue(value) { _ in }
    }

    /// Awaited write, used for restoring state.
    private func write(_ value: Any, to characteristic: HMCharacteristic?) async {
        guard let characteristic else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            characteristic.writeValue(value) { _ in continuation.resume() }
        }
    }

    private func readValue(_ characteristic: HMCharacteristic?) async -> Any? {
        guard let characteristic else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Any?, Never>) in
            characteristic.readValue { error in
                continuation.resume(returning: error == nil ? characteristic.value : nil)
            }
        }
    }
}
