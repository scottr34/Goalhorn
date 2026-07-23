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

        // Probe in bounded-concurrency batches so we don't open 254 sockets at once.
        let batchSize = 24
        for batch in hosts.chunked(into: batchSize) {
            let results = await withTaskGroup(of: SonosDevice?.self) { group -> [SonosDevice] in
                for host in batch {
                    group.addTask { [session] in
                        await Self.probe(host: host, session: session)
                    }
                }
                var collected: [SonosDevice] = []
                for await device in group where device != nil {
                    collected.append(device!)
                }
                return collected
            }

            found.append(contentsOf: results)
            completed += batch.count
            progress = Double(completed) / Double(hosts.count)
            // Surface results as they come in.
            devices = found.sorted { $0.roomName.localizedCaseInsensitiveCompare($1.roomName) == .orderedAscending }
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

extension Array {
    /// Splits the array into consecutive chunks of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
