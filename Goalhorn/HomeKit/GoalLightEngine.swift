import Foundation
import HomeKit
import Combine

/// Drives the selected HomeKit lights as a spinning arena goal beacon.
///
/// The effect: a bright "beam" sweeps around the ring of selected bulbs while
/// the colour steps through the user's sequence (`AppSettings.goalColors`) —
/// red/blue by default, but red/white/blue, red/white or red/off all work. A
/// step marked `isOff` is a dark beat: brightness drops to zero without a power
/// cycle, which is the only way a strobe stays in time.
/// When the show finishes (or is stopped) each light's previous state is restored.
///
/// HomeKit writes are slow and serialise per accessory, so the loop is built to
/// send as few of them as possible: colour is written only when the step
/// changes, and brightness only when a bulb's value has actually moved.
@MainActor
final class GoalLightEngine: ObservableObject {
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?
    /// Distinguishes runs, so a cancelled show cannot clear `isRunning` out from
    /// under the show that replaced it.
    private var generation = 0

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
    private let colorHoldPeriod: TimeInterval = 0.9   // seconds per colour step
    /// Skip a brightness write unless the value moved at least this much; the
    /// bulbs at the back of the sweep otherwise get the same value every tick.
    private let brightnessEpsilon = 3

    func start(on lights: [GoalLight], colors: [GoalLightColor], duration: TimeInterval) {
        guard !lights.isEmpty else { return }
        stop()
        generation += 1
        let runID = generation
        isRunning = true
        task = Task { [weak self] in
            await self?.run(lights: lights, colors: colors, duration: duration)
            guard let self, self.generation == runID else { return }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    // MARK: - Effect

    private func run(lights: [GoalLight], colors: [GoalLightColor], duration: TimeInterval) async {
        let palette = colors.isEmpty ? GoalLightColor.defaultSequence : colors
        let saved = await captureStates(lights)

        // Prime: power on. Saturation is written with each colour step now that
        // white (saturation 0) is a legal step, so it is not set here.
        var primeWrites: [(Any, HMCharacteristic)] = []
        for light in lights {
            if let power = light.power { primeWrites.append((true as Any, power)) }
        }
        await writeAll(primeWrites)

        let start = DispatchTime.now()
        func elapsed() -> TimeInterval {
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        }

        var lastStepIndex = -1
        var lastBrightness = [Int](repeating: -1, count: lights.count)
        let n = max(lights.count, 1)
        var tick = 0

        while !Task.isCancelled {
            let now = elapsed()
            if now >= duration { break }

            let beamPos = (now / rotationPeriod).truncatingRemainder(dividingBy: 1)
            let stepIndex = Int(now / colorHoldPeriod) % palette.count
            let step = palette[stepIndex]

            // Colour only moves a few times a second, and only then is it written.
            if stepIndex != lastStepIndex {
                if !step.isOff {
                    for light in lights {
                        fireWrite(step.hue, to: light.hue)
                        fireWrite(step.saturation, to: light.saturation)
                    }
                }
                lastStepIndex = stepIndex
            }

            // Sweep the brightness "beam" around the ring of lights.
            for (index, light) in lights.enumerated() {
                let target: Int
                if step.isOff {
                    target = 0
                } else {
                    let slot = Double(index) / Double(n)
                    let distance = circularDistance(beamPos, slot)
                    // Sharp falloff so one bulb clearly leads the sweep.
                    let intensity = pow(max(0, 1 - distance * Double(n) * 0.6), 2)
                    target = Int(12 + 88 * intensity)
                }

                let previous = lastBrightness[index]
                let crossesDark = (target == 0) != (previous == 0)
                guard target != previous, crossesDark || abs(target - previous) >= brightnessEpsilon else { continue }
                fireWrite(target, to: light.brightness)
                lastBrightness[index] = target
            }

            // Sleep to an absolute deadline so ticks do not drift by the time
            // the writes above take.
            tick += 1
            let delay = Double(tick) * tickInterval - elapsed()
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        await restore(saved, lights: lights)
    }

    /// Shortest distance between two positions on a unit circle (0...0.5).
    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }

    // MARK: - Capture / restore

    /// Reads every characteristic we care about in one batch. Doing these one at
    /// a time meant four serial HomeKit round-trips per bulb before the show
    /// could start, which is a visible pause between the tap and the lights.
    private func captureStates(_ lights: [GoalLight]) async -> [String: LightState] {
        let characteristics = lights.flatMap { light in
            [light.power, light.brightness, light.hue, light.saturation].compactMap { $0 }
        }
        await readAll(characteristics)

        var states: [String: LightState] = [:]
        states.reserveCapacity(lights.count)
        for light in lights {
            states[light.id] = LightState(
                power: light.power?.value as? Bool,
                brightness: (light.brightness?.value as? NSNumber)?.intValue,
                hue: (light.hue?.value as? NSNumber)?.doubleValue,
                saturation: (light.saturation?.value as? NSNumber)?.doubleValue
            )
        }
        return states
    }

    private func restore(_ states: [String: LightState], lights: [GoalLight]) async {
        var appearance: [(Any, HMCharacteristic)] = []
        var power: [(Any, HMCharacteristic)] = []

        for light in lights {
            guard let state = states[light.id] else { continue }
            if let hue = state.hue, let characteristic = light.hue { appearance.append((hue, characteristic)) }
            if let saturation = state.saturation, let characteristic = light.saturation { appearance.append((saturation, characteristic)) }
            if let brightness = state.brightness, let characteristic = light.brightness { appearance.append((brightness, characteristic)) }
            if let isOn = state.power, let characteristic = light.power { power.append((isOn, characteristic)) }
        }

        // Colour and brightness together, then power — restoring power last stops
        // a light that was off from flashing its old colour on the way out.
        await writeAll(appearance)
        await writeAll(power)
    }

    // MARK: - Characteristic I/O

    /// Fire-and-forget write, used inside the animation loop for speed.
    private func fireWrite(_ value: Any, to characteristic: HMCharacteristic?) {
        characteristic?.writeValue(value) { _ in }
    }

    /// Issue every write at once and wait for the last one. HomeKit delivers
    /// these completions on the main queue, and this type is main-actor bound,
    /// so the counter needs no further synchronisation.
    private func writeAll(_ writes: [(Any, HMCharacteristic)]) async {
        guard !writes.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = writes.count
            for (value, characteristic) in writes {
                characteristic.writeValue(value) { _ in
                    remaining -= 1
                    if remaining == 0 { continuation.resume() }
                }
            }
        }
    }

    /// As `writeAll`, for reads. Values are then read off each characteristic.
    private func readAll(_ characteristics: [HMCharacteristic]) async {
        guard !characteristics.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = characteristics.count
            for characteristic in characteristics {
                characteristic.readValue { _ in
                    remaining -= 1
                    if remaining == 0 { continuation.resume() }
                }
            }
        }
    }
}
