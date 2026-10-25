import Foundation

/// A PC that answers from memory: its serverinfo, its apps and what launching does. It records
/// what it was asked.
public final class FakeHostService: HostService, @unchecked Sendable {
    public var info: ServerInfo
    public var apps: [HostApp]
    /// Answers to launches, in order; the last one repeats.
    public var launchOutcomes: [LaunchOutcome] = [.started(sessionURL: "rtsp://demo:48010", virtualDisplayDriverReady: true, warning: nil)]
    /// The host's bitrate limit, kbps.
    public var maxBitrate = 500_000
    public var metrics: HardwareMetrics?
    /// Errors to throw instead of answering, by method name ("sleep", "setBitrate", ...).
    public var failures: [String: Error] = [:]

    public private(set) var launches: [LaunchRequest] = []
    public private(set) var bitrates: [Int] = []
    public private(set) var quits = 0
    public private(set) var sleeps = 0

    public init(info: ServerInfo, apps: [HostApp]) {
        self.info = info
        self.apps = apps
    }

    private func check(_ name: String) throws {
        if let error = failures[name] { throw error }
    }

    public func serverInfo() async throws -> ServerInfo {
        try check("serverInfo")
        return info
    }

    public func appList() async throws -> [HostApp] {
        try check("appList")
        return apps
    }

    public func launch(_ request: LaunchRequest) async throws -> LaunchOutcome {
        try check("launch")
        launches.append(request)
        return launchOutcomes.count > 1 ? launchOutcomes.removeFirst() : launchOutcomes[0]
    }

    public func quit() async throws {
        try check("quit")
        quits += 1
    }

    public func setBitrate(kbps: Int) async throws -> Int {
        try check("setBitrate")
        let applied = min(kbps, maxBitrate)
        bitrates.append(applied)
        return applied
    }

    public func sleep() async throws {
        try check("sleep")
        guard info.sleepAllowed else { throw VibeshineError.host(403, "Sleep control is disabled for this paired client") }
        sleeps += 1
    }

    public func hardwareMetrics() async throws -> HardwareMetrics {
        try check("hardwareMetrics")
        guard let metrics, info.hardwareMetricsVersion > 0 else {
            throw VibeshineError.host(403, "Hardware metrics are disabled")
        }
        return metrics
    }
}

/// Pairs after the PIN is shown, or fails with a message.
public final class FakePairingService: PairingService {
    public var pin = "1234"
    public var result: Result<PairingResult, PairingError> = .success(.paired(serverCertificate: Data("demo certificate".utf8)))
    public private(set) var addresses: [String] = []

    public init() {}

    public func pair(address: String, showPIN: @escaping (String) -> Void) async throws -> PairingResult {
        addresses.append(address)
        showPIN(pin)
        return try result.get()
    }
}

/// Keeps every input event, so tests can check the exact sequence.
public final class RecordingInputSink: InputSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [InputEvent] = []

    public init() {}

    public var events: [InputEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    public func send(_ event: InputEvent) {
        lock.lock()
        recorded.append(event)
        lock.unlock()
    }
}

/// Counts frames and keeps the last one.
public final class CountingVideoSink: VideoSink, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var last: VideoFrame?
    public private(set) var flushes = 0

    public init() {}

    public var framesShown: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    public var lastFrame: VideoFrame? {
        lock.lock()
        defer { lock.unlock() }
        return last
    }

    public func display(_ frame: VideoFrame) {
        lock.lock()
        count += 1
        last = frame
        lock.unlock()
    }

    public func flush() {
        lock.lock()
        flushes += 1
        lock.unlock()
    }
}
