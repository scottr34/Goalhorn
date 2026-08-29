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
///
/// **Putting the lights back is a first-class job, not a best effort.** Every
/// bulb's state is read before the show and written back after it, and the
/// restore path defends against the four ways that used to fail: a write from
/// the animation loop landing *after* the restore, HomeKit rejecting a restore
/// write, a second show starting before the first had finished restoring, and
/// the app being killed mid-celebration. See `restore(_:lights:)`.
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
    /// `Codable` so an interrupted show can still be undone on the next launch.
    private struct LightState: Codable {
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
    /// How long to wait for loop writes to land before restoring anyway.
    private let drainTimeout: TimeInterval = 2

    private let defaults: UserDefaults
    private static let pendingRestoreKey = "pendingLightRestore"

    /// Fire-and-forget writes still in flight, so the restore can wait them out.
    private var outstandingWrites = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start(on lights: [GoalLight], colors: [GoalLightColor], duration: TimeInterval) {
        guard !lights.isEmpty else { return }

        // Hold on to the outgoing run and wait for it below: if a second show
        // started while the first was still restoring, the new capture would
        // record beacon colours as the "previous" state and the bulbs would
        // never get home.
        let previous = task
        previous?.cancel()

        generation += 1
        let runID = generation
        isRunning = true
        task = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == runID, !Task.isCancelled else { return }
            await self.run(lights: lights, colors: colors, duration: duration)
            guard self.generation == runID else { return }
            self.isRunning = false
        }
    }

    func stop() {
        // Keep the task reference: the next `start` awaits it so the restore
        // this cancellation kicks off is allowed to finish first.
        task?.cancel()
        isRunning = false
    }

    /// Put the lights back after a show that never got to clean up — the app was
    /// killed or crashed mid-celebration. Safe to call whenever lights load; it
    /// does nothing when there is no unfinished show on record.
    func restoreInterruptedShow(on lights: [GoalLight]) async {
        guard hasPendingRestore else { return }
        await restorePending(lights: lights)
    }

    // MARK: - Effect

    private func run(lights: [GoalLight], colors: [GoalLightColor], duration: TimeInterval) async {
        // Undo any unfinished show first, so what we capture below is the user's
        // own lighting rather than a half-finished beacon.
        await restorePending(lights: lights)

        let palette = colors.isEmpty ? GoalLightColor.defaultSequence : colors
        let saved = await captureStates(lights)
        persistPending(saved)

        // Prime: power on AND put the bulbs into colour mode before the first
        // beat. A colour bulb sitting in colour-temperature mode ignores hue
        // until it gets a saturation write and just shows warm white — which is
        // why a red sequence came out yellow. Awaited, so it has landed before
        // the loop starts writing brightness over the top of it.
        let firstLit = palette.first(where: { !$0.isOff }) ?? .red
        var primeWrites: [(Any, HMCharacteristic)] = []
        for light in lights {
            if let power = light.power { primeWrites.append((true as Any, power)) }
            if let saturation = light.saturation {
                primeWrites.append((light.clampSaturation(firstLit.saturation) as Any, saturation))
            }
            if let hue = light.hue {
                primeWrites.append((light.clampHue(firstLit.hue) as Any, hue))
            }
        }
        await writeRetrying(primeWrites)

        let start = DispatchTime.now()
        func elapsed() -> TimeInterval {
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        }

        var lastStepIndex = -1
        var lastBrightness = [Int](repeating: -1, count: lights.count)
        var poweredOff = false
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
                if step.isOff {
                    // Cut power for a dark beat. Dropping brightness alone is not
                    // enough: most bulbs floor at 1, so they stay dimly lit.
                    for light in lights { fireWrite(false, to: light.power) }
                    poweredOff = true
                } else {
                    if poweredOff {
                        for light in lights { fireWrite(true, to: light.power) }
                        poweredOff = false
                        // The bulbs came back at whatever level they were; make
                        // the next brightness write unconditional.
                        for index in lastBrightness.indices { lastBrightness[index] = -1 }
                    }
                    // Saturation first: that is the write that takes a bulb out
                    // of white mode, and hue means nothing until it has.
                    for light in lights {
                        fireWrite(light.clampSaturation(step.saturation), to: light.saturation)
                        fireWrite(light.clampHue(step.hue), to: light.hue)
                    }
                }
                lastStepIndex = stepIndex
            }

            // Sweep the brightness "beam" around the ring of lights. Nothing to
            // do on a dark beat: the bulbs are powered off.
            if !step.isOff {
                for (index, light) in lights.enumerated() {
                    let slot = Double(index) / Double(n)
                    let distance = circularDistance(beamPos, slot)
                    // Sharp falloff so one bulb clearly leads the sweep.
                    let intensity = pow(max(0, 1 - distance * Double(n) * 0.6), 2)
                    let target = light.clampBrightness(Int(12 + 88 * intensity))

                    let previous = lastBrightness[index]
                    guard target != previous, abs(target - previous) >= brightnessEpsilon else { continue }
                    fireWrite(target, to: light.brightness)
                    lastBrightness[index] = target
                }
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
        let readOK = await readAll(characteristics)

        /// Only trust a value we actually managed to read — a failed read leaves
        /// whatever HomeKit had cached, and restoring that is worse than
        /// leaving the characteristic alone.
        func value(of characteristic: HMCharacteristic?) -> Any? {
            guard let characteristic, readOK.contains(ObjectIdentifier(characteristic)) else { return nil }
            return characteristic.value
        }

        var states: [String: LightState] = [:]
        states.reserveCapacity(lights.count)
        for light in lights {
            states[light.id] = LightState(
                power: value(of: light.power) as? Bool,
                brightness: (value(of: light.brightness) as? NSNumber)?.intValue,
                hue: (value(of: light.hue) as? NSNumber)?.doubleValue,
                saturation: (value(of: light.saturation) as? NSNumber)?.doubleValue
            )
        }
        return states
    }

    private func restore(_ states: [String: LightState], lights: [GoalLight]) async {
        // Let the loop's fire-and-forget writes land first. Otherwise a
        // brightness write queued on the final tick arrives after the restore
        // and leaves the bulb sitting at beacon level.
        await drainWrites()

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
        await writeRetrying(appearance)
        await writeRetrying(power)

        clearPending()
    }

    // MARK: - Unfinished shows

    private var hasPendingRestore: Bool { defaults.data(forKey: Self.pendingRestoreKey) != nil }

    private func persistPending(_ states: [String: LightState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: Self.pendingRestoreKey)
    }

    private func clearPending() {
        defaults.removeObject(forKey: Self.pendingRestoreKey)
    }

    /// Restore a snapshot left behind by a show that never finished.
    private func restorePending(lights: [GoalLight]) async {
        guard
            let data = defaults.data(forKey: Self.pendingRestoreKey),
            let states = try? JSONDecoder().decode([String: LightState].self, from: data)
        else {
            clearPending()
            return
        }
        // Only clear once the writes have gone out, so a second interruption
        // does not lose the snapshot.
        await restore(states, lights: lights)
    }

    // MARK: - Characteristic I/O

    /// Fire-and-forget write, used inside the animation loop for speed. The
    /// count lets `restore` wait for these to land before it writes.
    private func fireWrite(_ value: Any, to characteristic: HMCharacteristic?) {
        guard let characteristic else { return }
        outstandingWrites += 1
        characteristic.writeValue(value) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.outstandingWrites = max(0, self.outstandingWrites - 1)
            }
        }
    }

    /// Wait for loop writes to land, giving up after `drainTimeout` so an
    /// unreachable bulb cannot stall the restore forever.
    private func drainWrites() async {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(drainTimeout * 1_000_000_000)
        while outstandingWrites > 0 && DispatchTime.now().uptimeNanoseconds < deadline {
            await pause(0.03)
        }
    }

    /// Issue every write at once and report whatever HomeKit rejected. Writes
    /// complete on the main queue and this type is main-actor bound, so the
    /// counters need no further synchronisation.
    private func writeAll(_ writes: [(Any, HMCharacteristic)]) async -> [(Any, HMCharacteristic)] {
        guard !writes.isEmpty else { return [] }
        return await withCheckedContinuation { (continuation: CheckedContinuation<[(Any, HMCharacteristic)], Never>) in
            var remaining = writes.count
            var failed: [(Any, HMCharacteristic)] = []
            for (value, characteristic) in writes {
                characteristic.writeValue(value) { error in
                    if error != nil { failed.append((value, characteristic)) }
                    remaining -= 1
                    if remaining == 0 { continuation.resume(returning: failed) }
                }
            }
        }
    }

    /// Write, then retry whatever failed. Accessories routinely reject a write
    /// straight after a burst of them, and a dropped restore is exactly what
    /// leaves a bulb stuck on beacon red.
    private func writeRetrying(_ writes: [(Any, HMCharacteristic)], attempts: Int = 3) async {
        var pending = writes
        for attempt in 0..<attempts {
            if pending.isEmpty { return }
            if attempt > 0 { await pause(0.3 * Double(attempt)) }
            pending = await writeAll(pending)
        }
    }

    /// Reads in one batch, returning the characteristics that actually answered.
    private func readAll(_ characteristics: [HMCharacteristic]) async -> Set<ObjectIdentifier> {
        guard !characteristics.isEmpty else { return [] }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Set<ObjectIdentifier>, Never>) in
            var remaining = characteristics.count
            var succeeded: Set<ObjectIdentifier> = []
            for characteristic in characteristics {
                characteristic.readValue { error in
                    if error == nil { succeeded.insert(ObjectIdentifier(characteristic)) }
                    remaining -= 1
                    if remaining == 0 { continuation.resume(returning: succeeded) }
                }
            }
        }
    }

    /// A sleep that still sleeps when the surrounding task is cancelled. The
    /// restore path usually runs *because* the show was cancelled, so it cannot
    /// use `Task.sleep` — that would return instantly and spin.
    private func pause(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }
}
