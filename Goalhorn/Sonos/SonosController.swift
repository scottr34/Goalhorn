import Foundation

/// Controls a Sonos player over its local UPnP (SOAP) endpoints.
///
/// Sonos exposes standard UPnP `AVTransport` and `RenderingControl` services on
/// port 1400. We POST SOAP envelopes to set the playback URI, set volume, and
/// press play/stop — no cloud account required.
@MainActor
final class SonosController: ObservableObject {
    @Published var lastErrorMessage: String?

    private enum Service {
        static let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"
        static let rendering = "urn:schemas-upnp-org:service:RenderingControl:1"
        static let avControlPath = "/MediaRenderer/AVTransport/Control"
        static let renderingControlPath = "/MediaRenderer/RenderingControl/Control"
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - High-level

    /// Set the volume, point the player at `url`, and start playing.
    func playURL(_ url: URL, contentType: String, title: String, volume: Int?, on device: SonosDevice) async throws {
        if let volume {
            try? await setVolume(volume, on: device) // volume is best-effort
        }
        try await setTransportURI(url, contentType: contentType, title: title, on: device)
        try await play(on: device)
    }

    // MARK: - AVTransport

    func setTransportURI(_ url: URL, contentType: String, title: String, on device: SonosDevice) async throws {
        let didl = didlLite(url: url, contentType: contentType, title: title)
        let body = """
        <u:SetAVTransportURI xmlns:u="\(Service.avTransport)">\
        <InstanceID>0</InstanceID>\
        <CurrentURI>\(Self.xmlEscape(url.absoluteString))</CurrentURI>\
        <CurrentURIMetaData>\(Self.xmlEscape(didl))</CurrentURIMetaData>\
        </u:SetAVTransportURI>
        """
        try await post(action: "SetAVTransportURI", service: Service.avTransport,
                       controlPath: Service.avControlPath, innerBody: body, on: device)
    }

    func play(on device: SonosDevice) async throws {
        let body = """
        <u:Play xmlns:u="\(Service.avTransport)"><InstanceID>0</InstanceID><Speed>1</Speed></u:Play>
        """
        try await post(action: "Play", service: Service.avTransport,
                       controlPath: Service.avControlPath, innerBody: body, on: device)
    }

    func stop(on device: SonosDevice) async throws {
        let body = """
        <u:Stop xmlns:u="\(Service.avTransport)"><InstanceID>0</InstanceID></u:Stop>
        """
        try await post(action: "Stop", service: Service.avTransport,
                       controlPath: Service.avControlPath, innerBody: body, on: device)
    }

    // MARK: - RenderingControl

    func setVolume(_ volume: Int, on device: SonosDevice) async throws {
        let clamped = max(0, min(100, volume))
        let body = """
        <u:SetVolume xmlns:u="\(Service.rendering)">\
        <InstanceID>0</InstanceID><Channel>Master</Channel>\
        <DesiredVolume>\(clamped)</DesiredVolume></u:SetVolume>
        """
        try await post(action: "SetVolume", service: Service.rendering,
                       controlPath: Service.renderingControlPath, innerBody: body, on: device)
    }

    // MARK: - Transport

    private func post(action: String, service: String, controlPath: String, innerBody: String, on device: SonosDevice) async throws {
        guard let base = device.baseURL, let url = URL(string: controlPath, relativeTo: base) else {
            throw SonosError.invalidDevice
        }

        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body>\(innerBody)</s:Body></s:Envelope>
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = envelope.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SonosError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = String(data: data, encoding: .utf8).flatMap { $0.firstXMLValue(tag: "errorDescription") }
                throw SonosError.upnp(status: http.statusCode, action: action, detail: detail)
            }
            lastErrorMessage = nil
        } catch let error as SonosError {
            lastErrorMessage = error.localizedDescription
            throw error
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Helpers

    /// Minimal DIDL-Lite metadata so Sonos accepts and labels the stream.
    private func didlLite(url: URL, contentType: String, title: String) -> String {
        let safeTitle = Self.xmlEscape(title)
        return """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="goalhorn-song" parentID="-1" restricted="1">\
        <dc:title>\(safeTitle)</dc:title>\
        <upnp:class>object.item.audioItem.musicTrack</upnp:class>\
        <res protocolInfo="http-get:*:\(contentType):*">\(Self.xmlEscape(url.absoluteString))</res>\
        </item></DIDL-Lite>
        """
    }

    static func xmlEscape(_ string: String) -> String {
        var out = string
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&apos;")
        return out
    }
}

enum SonosError: LocalizedError {
    case invalidDevice
    case badResponse
    case upnp(status: Int, action: String, detail: String?)

    var errorDescription: String? {
        switch self {
        case .invalidDevice:
            return "The Sonos speaker address is invalid."
        case .badResponse:
            return "The Sonos speaker returned an unexpected response."
        case let .upnp(status, action, detail):
            if let detail { return "Sonos \(action) failed (\(status)): \(detail)" }
            return "Sonos \(action) failed with status \(status)."
        }
    }
}
