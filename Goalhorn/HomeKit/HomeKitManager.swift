import Foundation
import HomeKit
import Combine

/// A single controllable light (a HomeKit lightbulb service) that can take part
/// in the goal-light effect.
///
/// Holds live references to the underlying `HMService`/`HMCharacteristic`s, so
/// it is only valid while the app is running and must be used on the main actor.
@MainActor
final class GoalLight: Identifiable {
    let id: String
    let name: String
    let accessoryName: String
    let service: HMService
    let isReachable: Bool

    // Resolved once, up front. These used to be computed properties that each
    // did a linear scan of `service.characteristics` with a string compare, and
    // the beacon loop touches them for every bulb on every tick — so a show with
    // six bulbs was doing thousands of redundant scans a second.
    let power: HMCharacteristic?
    let brightness: HMCharacteristic?
    let hue: HMCharacteristic?
    let saturation: HMCharacteristic?

    init(service: HMService, accessory: HMAccessory) {
        self.id = service.uniqueIdentifier.uuidString
        self.name = service.name
        self.accessoryName = accessory.name
        self.service = service
        self.isReachable = accessory.isReachable

        var power: HMCharacteristic?
        var brightness: HMCharacteristic?
        var hue: HMCharacteristic?
        var saturation: HMCharacteristic?
        for characteristic in service.characteristics {
            switch characteristic.characteristicType {
            case HMCharacteristicTypePowerState: power = characteristic
            case HMCharacteristicTypeBrightness: brightness = characteristic
            case HMCharacteristicTypeHue: hue = characteristic
            case HMCharacteristicTypeSaturation: saturation = characteristic
            default: break
            }
        }
        self.power = power
        self.brightness = brightness
        self.hue = hue
        self.saturation = saturation
    }

    /// A light we can spin colours on needs hue + saturation; otherwise we can
    /// still strobe brightness/power.
    var supportsColor: Bool { hue != nil && saturation != nil }
}

/// Bridges HomeKit into SwiftUI: manages authorization, exposes the user's homes
/// and their lightbulbs, and reports readiness.
@MainActor
final class HomeKitManager: NSObject, ObservableObject {
    enum Status {
        case notStarted
        case waiting        // manager created, homes not loaded yet
        case restricted     // permission denied
        case ready
    }

    @Published private(set) var status: Status = .notStarted
    @Published private(set) var homes: [HMHome] = []
    @Published private(set) var lights: [GoalLight] = []

    private var manager: HMHomeManager?

    /// Instantiate the HomeKit manager. Creating `HMHomeManager` is what
    /// triggers the system permission prompt, so we defer it until the user
    /// visits the Lights screen.
    func start() {
        guard manager == nil else { return }
        status = .waiting
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    /// Re-read lights from HomeKit (e.g. after adding an accessory).
    func refresh() {
        rebuildLights()
    }

    private func rebuildLights() {
        guard let manager else { return }
        homes = manager.homes

        var collected: [GoalLight] = []
        for home in manager.homes {
            for accessory in home.accessories {
                for service in accessory.services where service.serviceType == HMServiceTypeLightbulb {
                    collected.append(GoalLight(service: service, accessory: accessory))
                }
            }
        }
        lights = collected.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func updateStatus() {
        guard let manager else { status = .notStarted; return }
        let auth = manager.authorizationStatus
        if auth.contains(.restricted) {
            status = .restricted
        } else if auth.contains(.authorized) {
            status = .ready
        } else if auth.contains(.determined) {
            // Determined but not authorized == the user declined.
            status = .restricted
        } else {
            status = .waiting
        }
    }
}

extension HomeKitManager: HMHomeManagerDelegate {
    // HomeKit delivers these on the main thread; this class is @MainActor.
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        rebuildLights()
        updateStatus()
    }

    func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        updateStatus()
        rebuildLights()
    }
}
