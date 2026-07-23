import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Helpers for discovering this device's IPv4 address on the Wi-Fi network.
///
/// We need the phone's LAN address so we can hand Sonos a URL it can reach
/// (`http://<phoneIP>:<port>/song`) when streaming an uploaded file.
enum NetworkInterface {

    /// The IPv4 address of the Wi-Fi interface (`en0`), e.g. "192.168.1.42".
    /// Returns `nil` when not connected to Wi-Fi.
    static func wifiIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            // en0 is Wi-Fi on iPhone. Fall back to en1 just in case.
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            if result == 0 {
                address = String(cString: hostname)
                if name == "en0" { break } // prefer Wi-Fi
            }
        }
        return address
    }

    /// The `/24` subnet prefix for a dotted-quad address, e.g.
    /// "192.168.1.42" -> "192.168.1". Used to scan the LAN for Sonos players.
    static func subnetPrefix(for ipv4: String) -> String? {
        let parts = ipv4.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.prefix(3).joined(separator: ".")
    }
}
