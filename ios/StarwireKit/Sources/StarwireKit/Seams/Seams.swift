import Foundation

// The seams between the app's screens and the streaming core. Screens talk only to these
// protocols. Each has a real version in the app, over the ObjC core and moonlight-common-c, and
// a fake here, for tests and the demo mode. Nothing in a production view knows which it has.
//
//   HostService     one PC: serverinfo, apps, launch, quit, bitrate, sleep, metrics
//                   real: VibeshineClient (this package) over the app's pinned transport
//   PairingService  pairing with a PIN. real: LivePairingService (app) over PairManager
//   StreamSession   one stream's life. real: LiveStreamSession (app) over StreamManager
//   InputSink       input to the PC. real: LiveInputSink (app) over moonlight-common-c
//   VideoSink       frames to the screen. real: SampleBufferVideoSink (app), on a system video layer
//   Clock           time. real: SystemClock (this package)

/// One PC, as the app talks to it.
public protocol HostService: AnyObject {
    func serverInfo() async throws -> ServerInfo
    func appList() async throws -> [HostApp]
    /// Starts or joins an app. May come back asking to confirm (see `ConfirmedLaunch`).
    func launch(_ request: LaunchRequest) async throws -> LaunchOutcome
    /// Ends this client's game.
    func quit() async throws
    /// Changes the running stream's bitrate; returns what the host applied.
    func setBitrate(kbps: Int) async throws -> Int
    func sleep() async throws
    func hardwareMetrics() async throws -> HardwareMetrics
}

/// What `/launch` needs beyond the options: the app and the stream's keys.
public struct LaunchRequest: Equatable, Sendable {
    public var appID: String
    public var options: LaunchOptions
    /// The AES key for the stream's input and its ID (`rikey`, `rikeyid`).
    public var inputKey: Data
    public var inputKeyID: Int32
    public var resume: Bool
    public var playAudioOnPC: Bool
    public var optimizeGameSettings: Bool
    public var hdr: Bool
    /// `surroundAudioInfo`: stereo is 196610.
    public var surroundAudioInfo: Int
    public var gamepadMask: Int

    public init(appID: String, options: LaunchOptions, inputKey: Data, inputKeyID: Int32, resume: Bool = false,
                playAudioOnPC: Bool = false, optimizeGameSettings: Bool = true, hdr: Bool = false,
                surroundAudioInfo: Int = 196_610, gamepadMask: Int = 0) {
        self.appID = appID
        self.options = options
        self.inputKey = inputKey
        self.inputKeyID = inputKeyID
        self.resume = resume
        self.playAudioOnPC = playAudioOnPC
        self.optimizeGameSettings = optimizeGameSettings
        self.hdr = hdr
        self.surroundAudioInfo = surroundAudioInfo
        self.gamepadMask = gamepadMask
    }

    public var hostRequest: HostRequest {
        var query = [
            URLQueryItem(name: "uniqueid", value: "0123456789ABCDEF"),
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "mode", value: options.mode),
            URLQueryItem(name: "additionalStates", value: "1"),
            URLQueryItem(name: "sops", value: optimizeGameSettings ? "1" : "0"),
            URLQueryItem(name: "rikey", value: inputKey.map { String(format: "%02X", $0) }.joined()),
            URLQueryItem(name: "rikeyid", value: String(inputKeyID)),
            URLQueryItem(name: "localAudioPlayMode", value: playAudioOnPC ? "1" : "0"),
            URLQueryItem(name: "surroundAudioInfo", value: String(surroundAudioInfo)),
            URLQueryItem(name: "remoteControllersBitmap", value: String(gamepadMask)),
            URLQueryItem(name: "gcmap", value: String(gamepadMask)),
        ]
        if hdr {
            query.append(URLQueryItem(name: "hdrMode", value: "1"))
        }
        query += options.extraQueryItems
        return HostRequest(resume ? "/resume" : "/launch", query: query, timeout: 60)
    }
}

/// Pairing with a PC: the app shows the PIN, the owner types it on the PC.
public protocol PairingService: AnyObject {
    /// Pairs with the PC at `address`. `showPIN` gets the PIN to show while the host waits.
    /// Returns the PC's certificate, to pin.
    func pair(address: String, showPIN: @escaping (String) -> Void) async throws -> PairingResult
}

public enum PairingResult: Equatable, Sendable {
    case paired(serverCertificate: Data)
    case alreadyPaired
}

public enum PairingError: Error, Equatable {
    case failed(String)
}

/// One stream from start to end.
public protocol StreamSession: AnyObject {
    var state: StreamState { get }
    /// Called on every change of state.
    var onStateChange: ((StreamState) -> Void)? { get set }
    func start()
    func stop()
}

public enum StreamState: Equatable, Sendable {
    case idle
    case starting(stage: String)
    case streaming
    /// Ended, with the reason if it wasn't the user.
    case ended(error: String?)
}

/// Input for the PC: what the touch, keyboard and controller code produces.
public protocol InputSink: AnyObject {
    func send(_ event: InputEvent)
}

public enum InputEvent: Equatable, Sendable {
    case mouseMove(dx: Int, dy: Int)
    /// Buttons: 1 left, 2 middle, 3 right, 4 back, 5 forward (moonlight-common-c's numbers).
    case mouseButton(button: Int, down: Bool)
    case scroll(amount: Int)
    /// A Windows virtual-key code, with moonlight-common-c's modifier flags.
    case key(code: Int, down: Bool, modifiers: Int)
    case touch(id: Int, phase: TouchPhase, x: Double, y: Double)
}

public enum TouchPhase: String, Equatable, Sendable {
    case down, move, up, cancel
}

/// A decoded frame. Real frames are pixel buffers inside `payload`; the demo makes plain BGRA.
public struct VideoFrame: @unchecked Sendable {
    public var index: Int
    public var width: Int
    public var height: Int
    /// Seconds on the session's clock.
    public var presentationTime: TimeInterval
    /// BGRA rows, `width * 4` bytes each, for generated frames. Nil for decoded frames.
    public var bgra: [UInt8]?
    /// The platform's own frame (a CMSampleBuffer in the app), when it has one.
    public var payload: AnyObject?

    public init(index: Int, width: Int, height: Int, presentationTime: TimeInterval, bgra: [UInt8]? = nil,
                payload: AnyObject? = nil) {
        self.index = index
        self.width = width
        self.height = height
        self.presentationTime = presentationTime
        self.bgra = bgra
        self.payload = payload
    }
}

public protocol VideoSink: AnyObject {
    func display(_ frame: VideoFrame)
    /// The stream ended: show nothing more.
    func flush()
}

extension VibeshineClient: HostService {
    public func launch(_ request: LaunchRequest) async throws -> LaunchOutcome {
        let response = try await transport.send(request.hostRequest)
        return LaunchOutcome.classify(try HostXML.parse(response.body))
    }

    public func quit() async throws {
        let response = try await transport.send(HostRequest("/cancel", timeout: 60))
        let xml = try HostXML.parse(response.body)
        guard xml.isOK else { throw VibeshineError.host(xml.statusCode, xml.statusMessage ?? "") }
    }
}
