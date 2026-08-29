import Foundation

/// Discovers Sonos players on the local Wi-Fi network.
///
/// iOS restricts SSDP multicast (it needs the special multicast entitlement),
/// so instead we scan the `/24` subnet with plain unicast HTTP requests to each
/// host's Sonos description endpoint (`:1400/xml/device_description.xml`). This
/// only needs the standard Local Network permission, which any app can request.
@MainActor
final class SonosDiscovery: ObservableObject {
    @Published private(set) var devices: [SonosDevice] = []
    @Published private(set) var isScanning = false
    /// 0...1 progress across the subnet scan, for a progress bar in the UI.
    @Published private(set) var progress: Double = 0

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.2
        config.timeoutIntervalForResource = 1.5
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    /// Scan the current Wi-Fi subnet for Sonos players.
    func scan() async {
        guard !isScanning else { return }
        guard
            let ip = NetworkInterface.wifiIPv4Address(),
            let prefix = NetworkInterface.subnetPrefix(for: ip)
        else {
            return
        }

        isScanning = true
        progress = 0
        devices = []
        defer { isScanning = false }

        let hosts = (1...254).map { "\(prefix).\($0)" }
        var found: [SonosDevice] = []
        var completed = 0

        // A sliding window rather than discrete batches. Batching made every
        // probe in a batch wait for that batch's slowest host, and a dead host
        // only fails on the 1.2s timeout — so a mostly-empty subnet spent almost
        // the whole scan idle. Topping the group up as each probe finishes keeps
        // `maxInFlight` sockets busy start to finish.
        let maxInFlight = 32
        var next = 0

        await withTaskGroup(of: SonosDevice?.self) { group in
            while next < hosts.count && next < maxInFlight {
                let host = hosts[next]
                next += 1
                group.addTask { [session] in await Self.probe(host: host, session: session) }
            }

            while let result = await group.next() {
                completed += 1
                progress = Double(completed) / Double(hosts.count)

                if let device = result {
                    found.append(device)
                    // Surface results as they come in.
                    devices = found.sorted { $0.roomName.localizedCaseInsensitiveCompare($1.roomName) == .orderedAscending }
                }

                if next < hosts.count {
                    let host = hosts[next]
                    next += 1
                    group.addTask { [session] in await Self.probe(host: host, session: session) }
                }
            }
        }
    }

    /// Ask a single host whether it is a Sonos player and, if so, describe it.
    nonisolated private static func probe(host: String, session: URLSession) async -> SonosDevice? {
        guard let url = URL(string: "http://\(host):1400/xml/device_description.xml") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard
                let http = response as? HTTPURLResponse, http.statusCode == 200,
                let xml = String(data: data, encoding: .utf8),
                xml.contains("Sonos") || xml.contains("ZonePlayer")
            else {
                return nil
            }
            let room = xml.firstXMLValue(tag: "roomName")
                ?? xml.firstXMLValue(tag: "friendlyName")
                ?? host
            let model = xml.firstXMLValue(tag: "modelName") ?? xml.firstXMLValue(tag: "displayName")
            return SonosDevice(ipAddress: host, roomName: room, modelName: model)
        } catch {
            return nil
        }
    }
}

extension String {
    /// Extracts the text content of the first `<tag>...</tag>` occurrence.
    func firstXMLValue(tag: String) -> String? {
        guard
            let openRange = range(of: "<\(tag)>"),
            let closeRange = range(of: "</\(tag)>"),
            openRange.upperBound <= closeRange.lowerBound
        else {
            return nil
        }
        let value = self[openRange.upperBound..<closeRange.lowerBound]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
