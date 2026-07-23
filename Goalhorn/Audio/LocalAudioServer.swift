import Foundation
import Network

/// A tiny local HTTP/1.1 server that streams a single audio file.
///
/// Sonos can't read the app's sandbox, so to play an uploaded file we host it at
/// `http://<phoneIP>:<port>/…` and hand that URL to the player. The server
/// supports `HEAD`, `GET`, and byte-range requests (Sonos issues a `Range`
/// request while buffering), which is enough for reliable playback.
final class LocalAudioServer {
    private let queue = DispatchQueue(label: "com.goalhorn.LocalAudioServer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    private var fileData: Data = Data()
    private var contentType: String = "application/octet-stream"

    /// The port the server is listening on, once started.
    private(set) var port: UInt16?

    /// Start serving `fileURL`. Returns the URL Sonos should fetch, using the
    /// phone's Wi-Fi address, or `nil` if the file can't be read or there's no
    /// Wi-Fi address available.
    func start(fileURL: URL, contentType: String, pathHint: String) -> URL? {
        stop()

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let ip = NetworkInterface.wifiIPv4Address() else { return nil }

        self.fileData = data
        self.contentType = contentType

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            self.listener = listener

            // Signalled once the listener is ready (or fails) so we can read the
            // assigned port without racing the callback queue.
            let ready = DispatchSemaphore(value: 0)

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = listener.port?.rawValue
                    ready.signal()
                case .failed, .cancelled:
                    self?.port = nil
                    ready.signal()
                default:
                    break
                }
            }
            listener.start(queue: queue)

            guard ready.wait(timeout: .now() + 2) == .success,
                  let assignedPort = queue.sync(execute: { self.port }) else {
                stop()
                return nil
            }

            let sanitizedPath = pathHint.hasPrefix("/") ? pathHint : "/\(pathHint)"
            return URL(string: "http://\(ip):\(assignedPort)\(sanitizedPath)")
        } catch {
            return nil
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for connection in connections.values { connection.cancel() }
            connections.removeAll()
            port = nil
        }
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        queue.async { self.connections[key] = connection }

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.connections[key] = nil }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }

            // Have we received the full header block yet?
            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated.subdata(in: accumulated.startIndex..<headerEnd.lowerBound)
                let header = String(data: headerData, encoding: .utf8) ?? ""
                self.respond(to: header, on: connection)
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }
            // Keep reading until the header terminator arrives.
            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    private func respond(to header: String, on connection: NWConnection) {
        let lines = header.split(separator: "\r\n", omittingEmptySubsequences: false)
        let requestLine = lines.first.map(String.init) ?? ""
        let method = requestLine.split(separator: " ").first.map(String.init)?.uppercased() ?? "GET"
        let isHead = method == "HEAD"

        let total = fileData.count
        var rangeHeader: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("range:") {
                rangeHeader = String(line.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces)
            }
        }

        let (start, end, isPartial) = Self.parseRange(rangeHeader, total: total)
        let length = max(0, end - start + 1)

        var responseHeader = ""
        if isPartial {
            responseHeader += "HTTP/1.1 206 Partial Content\r\n"
            responseHeader += "Content-Range: bytes \(start)-\(end)/\(total)\r\n"
        } else {
            responseHeader += "HTTP/1.1 200 OK\r\n"
        }
        responseHeader += "Content-Type: \(contentType)\r\n"
        responseHeader += "Content-Length: \(length)\r\n"
        responseHeader += "Accept-Ranges: bytes\r\n"
        responseHeader += "Connection: close\r\n"
        responseHeader += "\r\n"

        var payload = Data(responseHeader.utf8)
        if !isHead, length > 0, start < total {
            let sliceEnd = min(start + length, total)
            payload.append(fileData.subdata(in: start..<sliceEnd))
        }

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Parse a `Range: bytes=a-b` header. Returns the resolved byte window and
    /// whether a partial (206) response is warranted.
    private static func parseRange(_ header: String?, total: Int) -> (start: Int, end: Int, partial: Bool) {
        guard total > 0 else { return (0, -1, false) }
        guard let header, header.lowercased().hasPrefix("bytes=") else {
            return (0, total - 1, false)
        }
        let spec = header.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let startStr = parts.first.map(String.init) ?? ""
        let endStr = parts.count > 1 ? String(parts[1]) : ""

        if startStr.isEmpty, let suffix = Int(endStr) {
            // "bytes=-N" -> last N bytes.
            let start = max(0, total - suffix)
            return (start, total - 1, true)
        }
        let start = Int(startStr) ?? 0
        let end = Int(endStr) ?? (total - 1)
        let clampedStart = max(0, min(start, total - 1))
        let clampedEnd = max(clampedStart, min(end, total - 1))
        return (clampedStart, clampedEnd, true)
    }
}
