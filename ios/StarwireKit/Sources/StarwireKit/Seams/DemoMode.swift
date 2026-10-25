import Foundation

/// The demo mode: the app working with no PC, built only from the fakes. It has one PC with a
/// few games and Vibeshine's tiles, and its streams show a generated test pattern that moves, so
/// the screens, the stream view and input can be tried anywhere.
public enum DemoMode {
    public static let hostName = "Demo PC"
    public static let hostUUID = "00000000-DE70-4000-8000-000000000001"

    /// The demo PC's serverinfo: Vibeshine, paired, with virtual displays, sleep and metrics.
    public static func serverInfo() -> ServerInfo {
        let fields = [
            "hostname": hostName, "uniqueid": hostUUID, "appversion": "7.1.431.-1", "HttpsPort": "47984",
            "PairStatus": "1", "state": "SUNSHINE_SERVER_FREE", "currentgame": "0", "mac": "00:00:5e:00:53:01",
            "VirtualDisplayCapable": "true", "VirtualDisplayDriverReady": "true", "VirtualDisplayHDRCapable": "true",
            "ServerCodecModeSupport": "65793", "HardwareMetricsVersion": "1", "PowerActionVersion": "1",
            "SleepSupported": "1", "SleepAllowed": "1",
        ]
        return ServerInfo(xml: HostXML(statusCode: 200, statusMessage: nil, fields: fields, records: []))
    }

    public static func apps() -> [HostApp] {
        [
            HostApp(id: "1", name: "Desktop", hdrSupported: true),
            HostApp(id: "2", name: "Starfield Racer"),
            HostApp(id: "3", name: "Colour Bars"),
            HostApp(id: "2147483506", name: "Remote Input", kind: .remoteInput),
            HostApp(id: "2147483505", name: "Remote Monitor", kind: .remoteMonitor),
        ]
    }

    public static func metrics() -> HardwareMetrics {
        HardwareMetrics(version: 1, sampled_at_unix_ms: nil, interval_ms: 1000, cpu: .init(cpu_usage_percent: 9),
                        gpus: [.init(id: 0, name: "Demo GPU", metrics: .init(gpu_usage_percent: 41, gpu_encoder_percent: 22,
                                                                             gpu_temperature_c: 55, gpu_vram_used_mb: nil,
                                                                             gpu_vram_usage_percent: nil))])
    }

    public static func hostService() -> FakeHostService {
        let host = FakeHostService(info: serverInfo(), apps: apps())
        host.maxBitrate = 150_000
        host.metrics = metrics()
        return host
    }

    /// One frame of the demo picture: eight colour bars, with a white block that crosses the
    /// screen once every 2 seconds at `fps`, so dropped or repeated frames show.
    public static func frame(index: Int, width: Int, height: Int, fps: Int) -> VideoFrame {
        let colours: [(UInt8, UInt8, UInt8)] = [
            (255, 255, 255), (0, 255, 255), (255, 255, 0), (0, 255, 0),
            (255, 0, 255), (0, 0, 255), (255, 0, 0), (0, 0, 0),
        ]
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let blockSize = max(height / 8, 1)
        let period = max(fps * 2, 1)
        let blockX = (index % period) * max(width - blockSize, 1) / period
        let blockY = (height - blockSize) / 2
        for y in 0..<height {
            for x in 0..<width {
                let inBlock = x >= blockX && x < blockX + blockSize && y >= blockY && y < blockY + blockSize
                let (r, g, b) = inBlock ? (255, 255, 255) : colours[min(x * colours.count / width, colours.count - 1)]
                let offset = (y * width + x) * 4
                pixels[offset] = b
                pixels[offset + 1] = g
                pixels[offset + 2] = r
                pixels[offset + 3] = 255
            }
        }
        return VideoFrame(index: index, width: width, height: height, presentationTime: Double(index) / Double(max(fps, 1)),
                          bgra: pixels)
    }
}

/// A stream with no PC: it starts after the same stages a real one goes through, then shows
/// the demo picture on the video sink at the stream's frame rate. Time comes from the clock,
/// and `tick()` makes the frames that are due, so tests drive it without waiting.
public final class DemoStreamSession: StreamSession {
    public private(set) var state: StreamState = .idle {
        didSet { onStateChange?(state) }
    }
    public var onStateChange: ((StreamState) -> Void)?

    public let video: VideoSink
    public let input: InputSink
    public let clock: Clock
    public let width: Int
    public let height: Int
    public let fps: Int
    private var startedAt: TimeInterval?
    private var framesMade = 0

    public static let stages = ["RTSP handshake", "control stream", "video stream", "audio stream", "input stream"]

    public init(video: VideoSink, input: InputSink, clock: Clock, width: Int = 320, height: Int = 180, fps: Int = 60) {
        self.video = video
        self.input = input
        self.clock = clock
        self.width = width
        self.height = height
        self.fps = fps
    }

    public func start() {
        guard state == .idle || state.isEnded else { return }
        for stage in Self.stages {
            state = .starting(stage: stage)
        }
        startedAt = clock.now
        framesMade = 0
        state = .streaming
    }

    /// Makes every frame due by now. Returns how many it made.
    @discardableResult
    public func tick() -> Int {
        guard state == .streaming, let startedAt else { return 0 }
        let due = Int((clock.now - startedAt) * Double(fps)) + 1
        var made = 0
        while framesMade < due {
            video.display(DemoMode.frame(index: framesMade, width: width, height: height, fps: fps))
            framesMade += 1
            made += 1
        }
        return made
    }

    public func stop() {
        guard state == .streaming || state.isStarting else { return }
        video.flush()
        state = .ended(error: nil)
    }
}

extension StreamState {
    public var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }

    public var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }
}
