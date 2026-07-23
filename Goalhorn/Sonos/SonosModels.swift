import Foundation

/// A Sonos zone player found on the local network.
struct SonosDevice: Identifiable, Codable, Hashable {
    /// The device's LAN IP address, e.g. "192.168.1.50". Serves as identity.
    let ipAddress: String
    /// The room name reported by the player, e.g. "Living Room".
    var roomName: String
    /// The player's model, e.g. "Sonos One". Optional/best-effort.
    var modelName: String?

    var id: String { ipAddress }

    /// Sonos exposes its UPnP services on port 1400.
    var baseURL: URL? {
        URL(string: "http://\(ipAddress):1400")
    }
}
