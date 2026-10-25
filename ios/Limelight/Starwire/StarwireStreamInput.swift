//
//  StarwireStreamInput.swift
//  Starwire
//
//  One stream's input, between UIKit and StarwireKit: touches go to the touch modes, the Pencil
//  to pen events, keys and shortcuts out with their pauses, and the PC cursor's hide toggle. The
//  logic and its timings are in StarwireKit (Input/), tested there; this file only turns UIKit's
//  events into its calls, runs its timers and sends what comes back through LiveInputSink.
//

import Foundation
import StarwireKit
import UIKit

@objc(StarwireStreamInput)
final class StarwireStreamInput: NSObject {
    private let sink: InputSink
    let dispatcher: TouchDispatcher
    private var pencil: PencilInput
    private var hostCursor: HostCursorController?
    private let streamSize: CGSize

    /// Fingers down, in the order they touched (Android's pointer order)
    private var fingers: [UITouch] = []
    private var fingerIDs: [ObjectIdentifier: Int] = [:]
    private var nextFingerID = 1
    private var pencilTouch: UITouch?
    private var timer: Timer?

    /// When a finger last touched the stream (systemUptime), to pick the keyboard that suits
    private(set) var lastTouch: TimeInterval = -.infinity
    /// The last touch gesture's rates, for the statistics overlay's "Touch rate:" line
    static let touchRate = TouchRateMeter()

    /// The menu asked to open (three-finger tap)
    @objc var onOpenMenu: (() -> Void)?
    /// A gesture shortcut (four or five-finger tap)
    var onGesture: ((GestureAction) -> Void)?
    /// The picture's zoom and pan changed: apply this transform to the video
    @objc var onVideoTransform: ((CGAffineTransform) -> Void)?
    /// A short message for a toast
    @objc var onNotice: ((String) -> Void)?

    @objc init(streamWidth: Int, streamHeight: Int, viewSize: CGSize, scale: CGFloat) {
        let sink = LiveInputSink()
        self.sink = sink
        streamSize = CGSize(width: streamWidth, height: streamHeight)
        let settings = StarwireSettings.store
        var geometry = VideoGeometry(viewSize: viewSize, streamSize: streamSize)
        let scaling = PictureScaling(rawValue: settings.string("list_video_scaling") ?? "") ?? .fit
        geometry.stretch = scaling == .stretch
        geometry.fill = scaling == .fill
        let environment = TouchEnvironment(geometry: geometry, viewPixelSize: CGSize(width: viewSize.width * scale, height: viewSize.height * scale),
                                           longPressRightClick: settings.bool("checkbox_long_press_right_click"),
                                           absoluteMouseMode: settings.bool("checkbox_absolute_mouse_mode"),
                                           emit: { sink.send($0) })
        let sensitivity = settings.int("seekbar_touch_sensitivity")
        // Android starts with the custom sensitivity on when it isn't 100
        let mode = TouchMode(settingValue: settings.string("list_touch_mode") ?? "")
            ?? .initial(touchscreenTrackpad: settings.bool("checkbox_touchscreen_trackpad"))
        dispatcher = TouchDispatcher(mode: mode,
                                     environment: environment, pixelScale: scale,
                                     sensitivity: sensitivity == 0 ? 100 : sensitivity,
                                     pinchToZoom: settings.bool("checkbox_pinch_to_zoom"),
                                     hostSupportsTouch: true)
        pencil = PencilInput(curve: Self.pencilCurve(settings.string("list_pencil_pressure_curve")))
        super.init()
        dispatcher.gestures.settings = GestureSettings(store: settings)
        dispatcher.onOutcome = { [weak self] outcome in self?.handle(outcome) }
        LiveInputSink.tally.reset()
        StarwireLatencyProbeTap.streamStarted()
        StarwireLog.info("Input: touch mode \(dispatcher.mode.title), sensitivity \(dispatcher.sensitivity)%, stream \(streamWidth)x\(streamHeight)")
    }

    private static func pencilCurve(_ name: String?) -> PressureCurve {
        PressureCurve.presets.first { $0.name.lowercased() == name }?.curve ?? .linear
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Stream life

    /// The stream is up: the host's features are known now.
    @objc func streamStarted(hostFeatureFlags: UInt32, pcUUID: String?, host: String, appID: Int) {
        // LI_FF_PEN_TOUCH_EVENTS
        dispatcher.hostSupportsTouch = hostFeatureFlags & 0x01 != 0
        let mode = HideCursorMode(settingValue: StarwireSettings.store.string("hide_cursor_mode") ?? "never")
        let ledger = HostCursorLedger(store: UserDefaultsHostCursorLedgerStore(),
                                      hostKey: HostCursorLedger.hostKey(pcUUID: pcUUID, host: host))
        let controller = HostCursorController(mode: mode, ledger: ledger, toggle: KeyHostCursorToggle(sink: sink, isLinkUp: { true }),
                                              appID: appID)
        let reconcile = controller.onStreamStarted(resumedSession: false)
        hostCursor = controller
        StarwireLog.info("Input: host touch \(dispatcher.hostSupportsTouch ? "yes" : "no"), hide cursor \(mode.rawValue), ledger \(reconcile)")
    }

    /// The user is ending the stream. Returns true when the cursor was just shown again, so the
    /// caller waits a moment before stopping the connection.
    @objc func streamStopping() -> Bool {
        timer?.invalidate()
        return hostCursor?.onStopping() ?? false
    }

    @objc func streamStopFlushed() {
        hostCursor?.onShowFlushed()
    }

    @objc func connectionLost(errorCode: Int) {
        hostCursor?.onConnectionLost(errorCode: errorCode)
    }

    @objc var offersHostCursorFix: Bool {
        hostCursor?.isFixOffered(hostHasToggle: true) ?? false
    }

    @objc func fixHostCursor() {
        if hostCursor?.onManualFix() == true {
            onNotice?(StreamMenu.hostCursorFixNotice)
        }
    }

    // MARK: Layout and modes

    @objc func layout(viewSize: CGSize, scale: CGFloat) {
        var geometry = dispatcher.geometry
        guard geometry.viewSize != viewSize else { return }
        geometry.viewSize = viewSize
        dispatcher.geometry = geometry.clamped(maxZoom: TouchDispatcher.maxZoom)
        dispatcher.environment.viewPixelSize = CGSize(width: viewSize.width * scale, height: viewSize.height * scale)
        dispatcher.pixelScale = scale
        applyTransform(dispatcher.geometry)
    }

    /// How the picture fills the screen; touches follow it.
    func setPictureScaling(_ scaling: PictureScaling) {
        var geometry = dispatcher.geometry
        geometry.stretch = scaling == .stretch
        geometry.fill = scaling == .fill
        dispatcher.geometry = geometry.clamped(maxZoom: TouchDispatcher.maxZoom)
        applyTransform(dispatcher.geometry)
    }

    @objc static var touchRateSummary: String { touchRate.line }

    /// The latency probe's line, empty unless the probe is on
    @objc static var latencyProbeSummary: String { StarwireLatencyProbeTap.summary }

    @objc var touchModeIndex: Int {
        get { dispatcher.mode.rawValue }
        set {
            guard let mode = TouchMode(rawValue: newValue) else { return }
            dispatcher.setMode(mode)
            StarwireLog.info("Input: touch mode \(mode.title)")
        }
    }

    @objc static var touchModeTitles: [String] { TouchMode.allCases.map(\.title) }

    /// The statistics overlay's line: what has gone to the PC this stream, and the last packet
    @objc static var inputSummary: String { LiveInputSink.tally.line }

    /// The current touch mode, for the overlay
    @objc var touchModeTitle: String { dispatcher.mode.title + (dispatcher.isPanZoomMode ? ", pan and zoom" : "") }

    @objc var panZoomOn: Bool { dispatcher.isPanZoomMode }

    @objc func togglePanZoom() {
        dispatcher.togglePanZoomMode()
    }

    private var savedSensitivity: Int { max(StarwireSettings.store.int("seekbar_touch_sensitivity"), 25) }

    @objc var sensitivityOn: Bool { dispatcher.sensitivity != 100 }

    @objc func toggleSensitivity() {
        let on = !sensitivityOn && savedSensitivity != 100
        dispatcher.setSensitivity(on ? savedSensitivity : 100)
        onNotice?(StreamMenu.sensitivityNotice(on: on, percent: savedSensitivity))
    }

    private func handle(_ outcome: TouchOutcome) {
        switch outcome {
        case .openMenu:
            onOpenMenu?()
        case .gesture(let action):
            StarwireLog.info("Input: gesture \(action.rawValue)")
            onGesture?(action)
        case .geometry(let geometry):
            applyTransform(geometry)
        case .notice(let text):
            onNotice?(text == "Pan and zoom mode on" || text == "Pan and zoom mode off"
                      ? StreamMenu.panZoomNotice(on: dispatcher.isPanZoomMode) : text)
        }
    }

    private func applyTransform(_ geometry: VideoGeometry) {
        onVideoTransform?(CGAffineTransform(a: geometry.zoom, b: 0, c: 0, d: geometry.zoom, tx: geometry.pan.x, ty: geometry.pan.y))
    }

    // MARK: Touches

    private func pointers(in view: UIView) -> [TouchPointer] {
        fingers.map { touch in
            let force = touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 0
            return TouchPointer(id: fingerIDs[ObjectIdentifier(touch)] ?? 0, point: touch.location(in: view), pressure: force)
        }
    }

    @objc func touchesBegan(_ touches: Set<UITouch>, in view: UIView) {
        let now = ProcessInfo.processInfo.systemUptime
        lastTouch = now
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            if touch.type == .pencil && dispatcher.hostSupportsTouch {
                pencilTouch = touch
                sendPencil(touch, phase: .down, in: view)
                continue
            }
            if fingers.isEmpty {
                hostCursor?.onFingerDown(now: now)
            }
            fingers.append(touch)
            fingerIDs[ObjectIdentifier(touch)] = nextFingerID
            nextFingerID = nextFingerID % 0xFFFF + 1
            dispatcher.handle(.down(index: fingers.count - 1, pointers: pointers(in: view)), at: touch.timestamp)
        }
        Self.touchRate.fingersChanged(to: fingers.count, at: now)
        scheduleTimer()
    }

    @objc func touchesMoved(_ touches: Set<UITouch>, in view: UIView) {
        touchesMoved(touches, event: nil, in: view)
    }

    /// With the event, the coalesced touches are counted for the "Touch rate:" line.
    @objc func touchesMoved(_ touches: Set<UITouch>, event: UIEvent?, in view: UIView) {
        if let pen = pencilTouch, touches.contains(pen) {
            sendPencil(pen, phase: .move, in: view)
        }
        let moved = touches.filter { fingers.contains($0) }
        if let latest = moved.map(\.timestamp).max() {
            let samples = moved.reduce(0) { $0 + max(event?.coalescedTouches(for: $1)?.count ?? 1, 1) }
            Self.touchRate.moved(samples: samples, touchTime: latest, at: ProcessInfo.processInfo.systemUptime)
            dispatcher.handle(.move(pointers: pointers(in: view)), at: latest)
        }
        scheduleTimer()
    }

    @objc func touchesEnded(_ touches: Set<UITouch>, in view: UIView) {
        if let pen = pencilTouch, touches.contains(pen) {
            sendPencil(pen, phase: .up, in: view)
            pencilTouch = nil
        }
        // Fingers that lift in the same event go last-touched first, as Android would see them
        // lift one by one: a two-finger tap is then the second finger's tap (a right click)
        var lifting: [(touch: UITouch, index: Int)] = []
        for touch in touches {
            if let index = fingers.firstIndex(of: touch) {
                lifting.append((touch, index))
            }
        }
        lifting.sort { a, b in
            if a.touch.timestamp != b.touch.timestamp {
                return a.touch.timestamp < b.touch.timestamp
            }
            return a.index > b.index
        }
        for (touch, _) in lifting {
            guard let index = fingers.firstIndex(of: touch) else { continue }
            dispatcher.handle(.up(index: index, pointers: pointers(in: view)), at: touch.timestamp)
            fingers.remove(at: index)
            fingerIDs[ObjectIdentifier(touch)] = nil
        }
        if fingers.isEmpty {
            hostCursor?.onFingersUp(now: ProcessInfo.processInfo.systemUptime)
        }
        Self.touchRate.fingersChanged(to: fingers.count, at: ProcessInfo.processInfo.systemUptime)
        scheduleTimer()
    }

    @objc func touchesCancelled(_ touches: Set<UITouch>, in view: UIView) {
        if let pen = pencilTouch, touches.contains(pen) {
            sendPencil(pen, phase: .cancel, in: view)
            pencilTouch = nil
        }
        if !fingers.isEmpty, touches.contains(where: { fingers.contains($0) }) {
            dispatcher.handle(.cancel(pointers: pointers(in: view)), at: ProcessInfo.processInfo.systemUptime)
            fingers.removeAll()
            fingerIDs.removeAll()
            hostCursor?.onFingersUp(now: ProcessInfo.processInfo.systemUptime)
            Self.touchRate.fingersChanged(to: 0, at: ProcessInfo.processInfo.systemUptime)
        }
        scheduleTimer()
    }

    // MARK: Pencil

    private func sendPencil(_ touch: UITouch, phase: PencilSample.Phase, in view: UIView) {
        let force = touch.maximumPossibleForce > 0 ? Double(touch.force / touch.maximumPossibleForce) : 0
        let sample = PencilSample(phase: phase, location: touch.location(in: view), force: force,
                                  altitude: Double(touch.altitudeAngle), azimuth: Double(touch.azimuthAngle(in: view)))
        sink.send(pencil.event(for: sample, geometry: dispatcher.geometry))
    }

    /// A hover from UIHoverGestureRecognizer (iPad Pro with a Pencil that hovers).
    @objc func pencilHover(at location: CGPoint, distance: CGFloat, altitude: CGFloat, azimuth: CGFloat, ended: Bool) {
        guard dispatcher.hostSupportsTouch else { return }
        let sample = PencilSample(phase: ended ? .hoverEnded : .hover, location: location, altitude: Double(altitude),
                                  azimuth: Double(azimuth), hoverDistance: Double(distance))
        sink.send(pencil.event(for: sample, geometry: dispatcher.geometry))
    }

    // MARK: Keys

    /// Sends a shortcut's keys with its pauses.
    func send(_ shortcut: Shortcut) {
        send(steps: shortcut.steps())
    }

    func send(steps: [ShortcutStep]) {
        steps.send(to: sink) { milliseconds, next in
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: next)
        }
    }

    /// Runs a custom command; `after` gets its after-step at the right moment.
    func run(_ command: CustomCommand, after: @escaping (CommandAfterAction) -> Void) {
        let run = command.run()
        switch run.afterTiming {
        case .none:
            send(steps: run.steps)
        case .beforeKeys:
            after(run.after)
            send(steps: run.steps)
        case .afterKeys(let delay):
            send(steps: run.steps)
            let total = run.steps.reduce(0) { $0 + $1.pauseBeforeMilliseconds } + delay
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(total)) { after(run.after) }
        }
    }

    func send(_ events: [InputEvent]) {
        events.forEach(sink.send)
    }

    @objc func sendMonitor(_ number: Int) {
        if let shortcut = MonitorSwitch.shortcut(monitor: number) {
            send(shortcut)
        }
    }

    /// Text from the system keyboard's text field: what was typed and how many characters were
    /// deleted before it.
    @objc func systemKeyboardText(inserted: String, deleted: Int) {
        send(SystemKeyboardText.events(inserted: inserted, deleted: deleted))
    }

    // MARK: Timers

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        let deadlines = [dispatcher.nextDeadline, hostCursor?.nextDeadline].compactMap { $0 }
        guard let next = deadlines.min() else { return }
        let delay = max(next - ProcessInfo.processInfo.systemUptime, 0)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.dispatcher.tick(now: now)
            self.hostCursor?.tick(now: now)
            self.scheduleTimer()
        }
    }
}

extension SettingsStore {
    func bool(_ key: String) -> Bool {
        if case .bool(let value)? = value(key) { return value }
        return false
    }

    func int(_ key: String) -> Int {
        if case .int(let value)? = value(key) { return value }
        return 0
    }

    func string(_ key: String) -> String? {
        if case .string(let value)? = value(key) { return value }
        return nil
    }
}
