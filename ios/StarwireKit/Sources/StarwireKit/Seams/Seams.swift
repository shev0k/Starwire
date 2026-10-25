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

/// One input call to moonlight-common-c. Each case is one `LiSend...` function, with its
/// values as the library takes them, so a recording sink shows the exact packets a gesture makes.
public enum InputEvent: Equatable, Sendable {
    /// `LiSendMouseMoveEvent`
    case mouseMove(dx: Int, dy: Int)
    /// `LiSendMousePositionEvent`: a point in a `width` x `height` reference area (the video)
    case mousePosition(x: Int, y: Int, width: Int, height: Int)
    /// `LiSendMouseMoveAsMousePositionEvent`: a relative move sent as an absolute position, for
    /// remote desktop mouse mode
    case mouseMoveAsPosition(dx: Int, dy: Int, width: Int, height: Int)
    /// `LiSendMouseButtonEvent`. Buttons: 1 left, 2 middle, 3 right, 4 back, 5 forward.
    case mouseButton(button: Int, down: Bool)
    /// `LiSendHighResScrollEvent`: 120 is one wheel notch, positive scrolls up
    case scroll(amount: Int)
    /// `LiSendHighResHScrollEvent`: 120 is one notch, positive scrolls right
    case hScroll(amount: Int)
    /// `LiSendKeyboardEvent2`: a Windows virtual-key code, `KeyModifier` flags, and
    /// `KeyFlags` (non-normalized for keys typed on a layout the host may not share)
    case key(code: Int, down: Bool, modifiers: Int, flags: Int = 0)
    /// `LiSendUtf8TextEvent`
    case text(String)
    /// `LiSendTouchEvent`. x and y from 0 to 1 across the video. `pressure` is pressure for a
    /// touch and distance for a hover; contact sizes are fractions of the video; rotation in
    /// degrees, or `InputEvent.unknownRotation`.
    case touch(id: Int, phase: TouchPhase, x: Double, y: Double, pressure: Double = 0,
               contactMajor: Double = 0, contactMinor: Double = 0, rotation: Int = 0xFFFF)
    /// `LiSendPenEvent`. Tilt 0 (upright) to 90, or `InputEvent.unknownTilt`.
    case pen(phase: TouchPhase, tool: PenTool, buttons: Int, x: Double, y: Double, pressure: Double,
             rotation: Int, tilt: Int)
    /// `LiSendMultiControllerEvent`
    case controller(ControllerState)
    /// `LiSendControllerArrivalEvent`
    case controllerArrival(number: Int, activeMask: Int, type: ControllerType, buttons: Int, capabilities: Int)
    /// `LiSendControllerMotionEvent`: accelerometer in m/s², gyro in degrees per second
    case controllerMotion(number: Int, sensor: MotionSensor, x: Float, y: Float, z: Float)
    /// `LiSendControllerBatteryEvent`. Percent 0 to 100, or 255 when unknown.
    case controllerBattery(number: Int, state: BatteryState, percent: Int)
    /// `LiSendControllerTouchEvent`: the controller's touchpad, x and y from 0 to 1
    case controllerTouch(number: Int, phase: TouchPhase, id: Int, x: Double, y: Double, pressure: Double)

    public static let unknownRotation = 0xFFFF
    public static let unknownTilt = 0xFF
}

/// moonlight-common-c's `LI_TOUCH_EVENT_*` values.
public enum TouchPhase: Int, Equatable, Sendable {
    case hover = 0, down = 1, up = 2, move = 3, cancel = 4, buttonOnly = 5, hoverLeave = 6, cancelAll = 7
}

/// `LI_TOOL_TYPE_*`
public enum PenTool: Int, Equatable, Sendable {
    case unknown = 0, pen = 1, eraser = 2
}

/// `MODIFIER_*` flags for key events.
public enum KeyModifier {
    public static let shift = 0x01
    public static let ctrl = 0x02
    public static let alt = 0x04
    public static let meta = 0x08
}

/// `SS_KBE_FLAG_*` flags for key events.
public enum KeyFlags {
    public static let nonNormalized = 0x01
}

/// `LI_CTYPE_*`
public enum ControllerType: Int, Equatable, Sendable {
    case unknown = 0, xbox = 1, playStation = 2, nintendo = 3
}

/// `LI_MOTION_TYPE_*`
public enum MotionSensor: Int, Equatable, Sendable {
    case accelerometer = 1, gyroscope = 2
}

/// `LI_BATTERY_STATE_*`
public enum BatteryState: Int, Equatable, Sendable {
    case unknown = 0, notPresent = 1, discharging = 2, charging = 3, notCharging = 4, full = 5
}

/// One gamepad's whole state, as `LiSendMultiControllerEvent` sends it. Sticks run from -32768 to
/// 32767 with up positive; triggers from 0 to 255.
public struct ControllerState: Equatable, Sendable {
    public var number: Int
    /// Bit n set for each controller n that is connected
    public var activeMask: Int
    /// `GamepadButton` flags
    public var buttons: Int
    public var leftTrigger: Int
    public var rightTrigger: Int
    public var leftX: Int
    public var leftY: Int
    public var rightX: Int
    public var rightY: Int

    public init(number: Int = 0, activeMask: Int = 1, buttons: Int = 0, leftTrigger: Int = 0, rightTrigger: Int = 0,
                leftX: Int = 0, leftY: Int = 0, rightX: Int = 0, rightY: Int = 0) {
        self.number = number
        self.activeMask = activeMask
        self.buttons = buttons
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.leftX = leftX
        self.leftY = leftY
        self.rightX = rightX
        self.rightY = rightY
    }
}

/// moonlight-common-c's button flags for `ControllerState.buttons`.
public enum GamepadButton {
    public static let up = 0x0001
    public static let down = 0x0002
    public static let left = 0x0004
    public static let right = 0x0008
    public static let start = 0x0010
    public static let back = 0x0020
    public static let leftStick = 0x0040
    public static let rightStick = 0x0080
    public static let leftBumper = 0x0100
    public static let rightBumper = 0x0200
    public static let guide = 0x0400
    public static let a = 0x1000
    public static let b = 0x2000
    public static let x = 0x4000
    public static let y = 0x8000
    public static let paddle1 = 0x010000
    public static let paddle2 = 0x020000
    public static let paddle3 = 0x040000
    public static let paddle4 = 0x080000
    public static let touchpad = 0x100000
    public static let misc = 0x200000
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
