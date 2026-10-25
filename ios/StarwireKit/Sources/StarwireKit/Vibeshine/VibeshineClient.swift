import Foundation

/// One request to a PC's HTTPS port (47984), authenticated by this client's certificate and the
/// PC's pinned one.
public struct HostRequest: Equatable, Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var method: Method
    public var path: String
    public var query: [URLQueryItem]
    public var timeout: TimeInterval

    public init(_ path: String, method: Method = .get, query: [URLQueryItem] = [], timeout: TimeInterval = 5) {
        self.method = method
        self.path = path
        self.query = query
        self.timeout = timeout
    }

    /// The path and query, as sent.
    public var pathAndQuery: String {
        guard !query.isEmpty else { return path }
        return path + "?" + query.map { "\($0.name)=\(LaunchOptions.encode($0.value ?? ""))" }.joined(separator: "&")
    }
}

public struct HostResponse: Equatable, Sendable {
    /// The HTTP status. Classic routes always answer 200 and put the result in the XML.
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Sends requests to one PC. The app's version pins the PC's certificate and presents the
/// client's; tests use `FakeHostTransport`.
public protocol HostTransport: AnyObject, Sendable {
    func send(_ request: HostRequest) async throws -> HostResponse
}

public enum VibeshineError: Error, Equatable {
    /// The host answered with an error: the status and its message.
    case host(Int, String)
    /// The answer wasn't what the endpoint sends.
    case unreadable(String)
}

/// Host CPU and GPU use from `/api/hardware-metrics`.
public struct HardwareMetrics: Equatable, Sendable, Decodable {
    public struct CPU: Equatable, Sendable, Decodable {
        public var cpu_usage_percent: Double?
    }

    public struct GPU: Equatable, Sendable, Decodable {
        public struct Metrics: Equatable, Sendable, Decodable {
            public var gpu_usage_percent: Double?
            public var gpu_encoder_percent: Double?
            public var gpu_temperature_c: Double?
            public var gpu_vram_used_mb: Double?
            public var gpu_vram_usage_percent: Double?
        }

        public var id: Int?
        public var name: String?
        public var metrics: Metrics
    }

    public var version: Int
    public var sampled_at_unix_ms: Int64?
    /// How often the host takes a new sample; asking faster gets the same one.
    public var interval_ms: Int?
    public var cpu: CPU?
    public var gpus: [GPU]?

    /// One line for the overlay, like "Host CPU 12%, GPU 64% (encoder 30%), 61 °C". Parts the
    /// host didn't send are left out.
    public var overlayText: String {
        var parts: [String] = []
        if let cpu = cpu?.cpu_usage_percent {
            parts.append("CPU \(Int(cpu.rounded()))%")
        }
        if let gpu = gpus?.first?.metrics {
            var text = gpu.gpu_usage_percent.map { "GPU \(Int($0.rounded()))%" } ?? "GPU"
            if let encoder = gpu.gpu_encoder_percent {
                text += " (encoder \(Int(encoder.rounded()))%)"
            }
            if let temperature = gpu.gpu_temperature_c {
                text += ", \(Int(temperature.rounded())) °C"
            }
            if text != "GPU" {
                parts.append(text)
            }
        }
        return parts.isEmpty ? "" : "Host " + parts.joined(separator: ", ")
    }
}

/// What `GET /power-actions/v1` says.
public struct PowerActions: Equatable, Sendable {
    public var supported: Bool
    public var allowed: Bool
    /// Supported, allowed and the PC idle: no game and no other stream.
    public var available: Bool
    /// For the sleep request; valid for 30 seconds, once.
    public var token: String?

    public init(xml: HostXML) {
        supported = xml["SleepSupported"] == "1"
        allowed = xml["SleepAllowed"] == "1"
        available = xml["SleepAvailable"] == "1"
        token = xml["SleepToken"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Vibeshine's own endpoints, over a transport.
public final class VibeshineClient: Sendable {
    public let transport: HostTransport

    public init(transport: HostTransport) {
        self.transport = transport
    }

    public func serverInfo() async throws -> ServerInfo {
        let response = try await transport.send(HostRequest("/serverinfo"))
        return ServerInfo(xml: try xml(response))
    }

    public func appList() async throws -> [HostApp] {
        let response = try await transport.send(HostRequest("/applist"))
        let (list, apps) = try HostAppList.parse(response.body)
        guard list.isOK else { throw VibeshineError.host(list.statusCode, list.statusMessage ?? "") }
        return apps
    }

    /// Changes the bitrate of this client's running stream. Returns the bitrate the host
    /// applied, after its own limit.
    public func setBitrate(kbps: Int) async throws -> Int {
        let response = try await transport.send(HostRequest("/bitrate", query: [URLQueryItem(name: "bitrate", value: String(kbps))]))
        let result = try xml(response)
        guard let applied = result["bitrate"].flatMap(Int.init), applied > 0 else {
            throw VibeshineError.unreadable("no bitrate in the answer")
        }
        return applied
    }

    /// True when the host says the client should run its own bitrate control and change it
    /// with `setBitrate`.
    public func supportsRuntimeBitrate() async throws -> Bool {
        let response = try await transport.send(HostRequest("/api/abr/capabilities"))
        guard response.status == 200,
              let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let features = json["features"] as? [String] else {
            return false
        }
        return features.contains("runtime_bitrate")
    }

    public func powerActions() async throws -> PowerActions {
        let response = try await transport.send(HostRequest("/power-actions/v1"))
        return PowerActions(xml: try xml(response))
    }

    /// Puts the PC to sleep: asks for a token, then sends it. Throws with the host's message
    /// when it says no (not allowed, a game still running, ...).
    public func sleep() async throws {
        let actions = try await powerActions()
        guard actions.supported else { throw VibeshineError.host(501, "This PC can't sleep from Starwire.") }
        guard actions.allowed else { throw VibeshineError.host(403, "The PC's owner hasn't allowed this device to sleep it.") }
        guard actions.available, let token = actions.token else {
            throw VibeshineError.host(409, "Close the game and any other streams first.")
        }
        let response = try await transport.send(HostRequest("/power-actions/v1/sleep", method: .post,
                                                            query: [URLQueryItem(name: "token", value: token)]))
        guard response.status == 202 else {
            let answer = try? HostXML.parse(response.body)
            throw VibeshineError.host(response.status, answer?.statusMessage ?? "")
        }
    }

    public func hardwareMetrics() async throws -> HardwareMetrics {
        let response = try await transport.send(HostRequest("/api/hardware-metrics", timeout: 3))
        guard response.status == 200 else {
            let error = (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any])?["error"] as? String
            throw VibeshineError.host(response.status, error ?? "")
        }
        do {
            return try JSONDecoder().decode(HardwareMetrics.self, from: response.body)
        } catch {
            throw VibeshineError.unreadable("\(error)")
        }
    }

    /// The XML of a classic answer, throwing its error. (Power actions put the result in the
    /// HTTP status as well as the XML; the XML says the same.)
    private func xml(_ response: HostResponse) throws -> HostXML {
        let parsed: HostXML
        do {
            parsed = try HostXML.parse(response.body)
        } catch {
            throw VibeshineError.unreadable("HTTP \(response.status), not XML")
        }
        guard parsed.isOK else {
            throw VibeshineError.host(parsed.statusCode, parsed.statusMessage ?? "")
        }
        return parsed
    }
}

/// A transport that answers from a script, for tests and the demo mode. It records what it was
/// asked.
public final class FakeHostTransport: HostTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: [HostResponse]] = [:]
    public private(set) var requests: [HostRequest] = []

    public init() {}

    /// Answers requests to `path` with these, in order; the last one repeats.
    public func answer(_ path: String, _ responses: HostResponse...) {
        lock.lock()
        answers[path] = responses
        lock.unlock()
    }

    public func answer(_ path: String, status: Int = 200, body: String) {
        answer(path, HostResponse(status: status, body: Data(body.utf8)))
    }

    public func send(_ request: HostRequest) async throws -> HostResponse {
        respond(to: request)
    }

    private func respond(to request: HostRequest) -> HostResponse {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        guard var queue = answers[request.path], !queue.isEmpty else {
            return HostResponse(status: 200, body: Data(#"<?xml version="1.0"?><root status_code="404"/>"#.utf8))
        }
        let response = queue.removeFirst()
        answers[request.path] = queue.isEmpty ? [response] : queue
        return response
    }
}
