import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Routes the screen's touches to the touch mode, as Starwire for Android's Game.handleMotionEvent
// does (GPL-3.0): the three-finger tap for the stream menu, pan and zoom mode, pinch to zoom
// anytime (from Moonlit Artemis), multi-touch passthrough, and the two finger slots of the
// trackpad and direct modes. The app turns UIKit's touches into `TouchAction`s in the order
// Android's MotionEvent would give them.

/// Starwire's touch modes, in Android's order (Game.MOUSE_MODE_*); the raw value is saved.
public enum TouchMode: Int, CaseIterable, Sendable {
    case multiTouch = 0
    case direct = 1
    case naturalTrackpad = 2
    case gamingTrackpad = 3
    case disabled = 4
    case directSwapped = 5

    /// Android's names (mouse_mode_* in strings.xml)
    public var title: String {
        switch self {
        case .multiTouch: return "Multi-touch"
        case .direct: return "Direct touch"
        case .naturalTrackpad: return "Trackpad (natural)"
        case .gamingTrackpad: return "Trackpad (gaming)"
        case .disabled: return "Touch disabled"
        case .directSwapped: return "Direct touch, swapped clicks"
        }
    }

    /// How the mode is saved in `list_touch_mode`
    public var settingValue: String {
        switch self {
        case .multiTouch: return "multi_touch"
        case .direct: return "direct"
        case .naturalTrackpad: return "natural_trackpad"
        case .gamingTrackpad: return "gaming_trackpad"
        case .disabled: return "disabled"
        case .directSwapped: return "direct_swapped"
        }
    }

    public init?(settingValue: String) {
        guard let mode = Self.allCases.first(where: { $0.settingValue == settingValue }) else { return nil }
        self = mode
    }

    /// An SF Symbol for the menu and settings
    public var symbol: String {
        switch self {
        case .multiTouch: return "hand.raised.fingers.spread"
        case .direct: return "hand.point.up.left"
        case .naturalTrackpad: return "rectangle.and.hand.point.up.left"
        case .gamingTrackpad: return "gamecontroller"
        case .disabled: return "hand.raised.slash"
        case .directSwapped: return "arrow.left.arrow.right"
        }
    }

    /// The mode a stream starts in: `checkbox_touchscreen_trackpad` picks the gaming trackpad,
    /// otherwise direct touch (Game.java applyMouseMode at start).
    public static func initial(touchscreenTrackpad: Bool) -> TouchMode {
        touchscreenTrackpad ? .gamingTrackpad : .direct
    }
}

/// One finger, as the app sees it.
public struct TouchPointer: Equatable, Sendable {
    /// Stable for the finger's life
    public var id: Int
    public var point: CGPoint
    /// `force / maximumPossibleForce`, or 0 where the screen has no force sensing
    public var pressure: Double

    public init(id: Int, point: CGPoint, pressure: Double = 0) {
        self.id = id
        self.point = point
        self.pressure = pressure
    }
}

/// A change to the fingers on the screen. `pointers` are all fingers down, in the order they
/// touched, including one lifting in this action.
public enum TouchAction: Equatable, Sendable {
    /// The first finger, or another one (`index` into `pointers`)
    case down(index: Int, pointers: [TouchPointer])
    case move(pointers: [TouchPointer])
    /// A finger lifts; when it is the last one, `pointers` has one entry
    case up(index: Int, pointers: [TouchPointer])
    case cancel(pointers: [TouchPointer])
}

/// What the dispatcher wants besides input: the menu, or a new zoom.
public enum TouchOutcome: Equatable, Sendable {
    case openMenu
    /// A gesture shortcut (four or five-finger tap, or a three-finger tap set to something else)
    case gesture(GestureAction)
    case geometry(VideoGeometry)
    /// Toasts Android shows, e.g. leaving pan and zoom mode
    case notice(String)
}

public final class TouchDispatcher {
    public static let threeFingerTapThreshold: TimeInterval = 0.300
    public static let pinchStartFraction: CGFloat = 0.15
    public static let maxZoom: CGFloat = 10

    public private(set) var mode: TouchMode
    public private(set) var isPanZoomMode = false
    public var pinchToZoom: Bool
    /// The host takes `LiSendTouchEvent` (`LI_FF_PEN_TOUCH_EVENTS`); without it multi-touch
    /// falls back to direct touch, as on Android.
    public var hostSupportsTouch: Bool
    public var sensitivity: Int
    /// Points to pixels (the screen's scale), so Android's pixel thresholds keep their size
    public var pixelScale: CGFloat
    public let environment: TouchEnvironment
    /// Four and five-finger taps, and what the three-finger tap does
    public let gestures = GestureShortcuts()
    public var onOutcome: (TouchOutcome) -> Void = { _ in }

    private var contexts: [TouchContext] = []
    private var threeFingerDownTime: TimeInterval = -.infinity
    private var pinchStartSpan: CGFloat = 0
    private var pinchActive = false
    private var pinchLastSpan: CGFloat = 0
    private var pinchLastFocus: CGPoint = .zero
    private var panLast: CGPoint?
    private var lastPanTapTime: TimeInterval = -.infinity
    private var lastPanTapPoint: CGPoint = .zero
    private var panMoved = false
    private var panDownTime: TimeInterval = 0
    private var panDownPoint: CGPoint = .zero

    public init(mode: TouchMode, environment: TouchEnvironment, pixelScale: CGFloat = 2, sensitivity: Int = 100,
                pinchToZoom: Bool = true, hostSupportsTouch: Bool = true) {
        self.mode = mode
        self.environment = environment
        self.pixelScale = pixelScale
        self.sensitivity = sensitivity
        self.pinchToZoom = pinchToZoom
        self.hostSupportsTouch = hostSupportsTouch
        buildContexts()
    }

    public var geometry: VideoGeometry {
        get { environment.geometry }
        set { environment.geometry = newValue }
    }

    /// Changes the touch mode. Like Android, it lets go of anything held and leaves pan and zoom
    /// mode.
    public func setMode(_ newMode: TouchMode) {
        mode = newMode
        buildContexts()
        isPanZoomMode = false
    }

    public func setSensitivity(_ percent: Int) {
        sensitivity = percent
        buildContexts()
    }

    public func togglePanZoomMode() {
        isPanZoomMode.toggle()
        for context in contexts { context.cancel() }
        onOutcome(.notice(isPanZoomMode ? "Pan and zoom mode on" : "Pan and zoom mode off"))
    }

    private func buildContexts() {
        for context in contexts { context.cancel() }
        environment.timers.cancelAll(prefix: "")
        contexts = (0..<2).map { index -> TouchContext in
            switch mode {
            case .naturalTrackpad:
                return NaturalTrackpadContext(actionIndex: index, environment: environment, sensitivity: sensitivity)
            case .gamingTrackpad:
                return GamingTrackpadContext(actionIndex: index, environment: environment, sensitivity: sensitivity)
            case .directSwapped:
                return DirectTouchContext(actionIndex: index, environment: environment, swapped: true)
            default:
                // Multi-touch falls back to direct touch; disabled keeps contexts so cancels stay safe
                return DirectTouchContext(actionIndex: index, environment: environment)
            }
        }
    }

    public var nextDeadline: TimeInterval? { environment.timers.nextDeadline }

    /// Fires every timer due by `now`, each at its own time.
    public func tick(now: TimeInterval) {
        while let next = environment.timers.nextDeadline, next <= now {
            for (name, time) in environment.timers.popDue(now: next) {
                for context in contexts { context.fire(name, at: time) }
            }
        }
    }

    private func sample(_ pointer: TouchPointer) -> TouchSample {
        TouchSample(x: Int(pointer.point.x * pixelScale), y: Int(pointer.point.y * pixelScale), point: pointer.point)
    }

    /// Handles one touch change at `time`.
    public func handle(_ action: TouchAction, at time: TimeInterval) {
        tick(now: time)
        let pointers: [TouchPointer]
        switch action {
        case .down(_, let p), .move(let p), .up(_, let p), .cancel(let p): pointers = p
        }

        switch gestures.handle(action, at: time) {
        case .pass:
            break
        case .claim:
            letGoForGesture()
            return
        case .swallow:
            return
        case .fire(let gesture):
            onOutcome(gesture == .menu ? .openMenu : .gesture(gesture))
            return
        }

        // Pan and zoom, and touch disabled, have no three-finger tap of their own, so three
        // fingers down opens the menu at once (Game.opensMenuBeforeTouchHandling)
        if case .down = action, pointers.count == 3, isPanZoomMode || mode == .disabled {
            onOutcome(.openMenu)
            return
        }
        if isPanZoomMode {
            handlePanZoom(action, pointers: pointers, at: time)
            return
        }
        if handlePinch(action, pointers: pointers) {
            return
        }
        if mode == .disabled {
            return
        }
        if mode == .multiTouch && hostSupportsTouch {
            passThrough(action, pointers: pointers)
            return
        }
        dispatchToContexts(action, pointers: pointers, at: time)
    }

    /// A four-finger gesture took over: let go of everything the fingers were doing on the PC.
    private func letGoForGesture() {
        threeFingerDownTime = -.infinity
        pinchActive = false
        pinchStartSpan = 0
        panLast = nil
        if mode == .multiTouch && hostSupportsTouch && !isPanZoomMode {
            environment.emit(.touch(id: 0, phase: .cancelAll, x: 0, y: 0, pressure: 0, contactMajor: 0, contactMinor: 0,
                                    rotation: InputEvent.unknownRotation))
        }
        for context in contexts {
            context.cancel()
        }
    }

    /// The three-finger tap: Android's menu, or what the settings make it.
    private func threeFingerTap() {
        let action = gestures.settings.threeFingerTap
        if action == .menu {
            onOutcome(.openMenu)
        } else if action != .none {
            onOutcome(.gesture(action))
        }
    }

    // MARK: Multi-touch passthrough

    private func passThrough(_ action: TouchAction, pointers: [TouchPointer]) {
        func send(_ pointer: TouchPointer, _ phase: TouchPhase) {
            let n = geometry.normalized(pointer.point)
            environment.emit(.touch(id: pointer.id, phase: phase, x: Double(n.x), y: Double(n.y), pressure: pointer.pressure,
                                    contactMajor: 0, contactMinor: 0, rotation: InputEvent.unknownRotation))
        }
        switch action {
        case .down(let index, _): send(pointers[index], .down)
        case .move: pointers.forEach { send($0, .move) }
        case .up(let index, _): send(pointers[index], .up)
        case .cancel:
            environment.emit(.touch(id: 0, phase: .cancelAll, x: 0, y: 0, pressure: 0, contactMajor: 0, contactMinor: 0,
                                    rotation: InputEvent.unknownRotation))
        }
    }

    // MARK: Trackpad and direct modes

    private func dispatchToContexts(_ action: TouchAction, pointers: [TouchPointer], at time: TimeInterval) {
        switch action {
        case .down(let index, _):
            if pointers.count == 3 {
                // Three fingers: the start of a menu tap. Let go of what the first two did.
                threeFingerDownTime = time
                for context in contexts { context.cancel() }
                return
            }
            guard index < contexts.count else { return }
            for context in contexts { context.setPointerCount(pointers.count, at: time) }
            contexts[index].touchDown(sample(pointers[index]), at: time, isNewFinger: true)
        case .up(let index, _):
            if pointers.count == 1 && time - threeFingerDownTime < Self.threeFingerTapThreshold {
                threeFingerDownTime = -.infinity
                threeFingerTap()
                return
            }
            if index < contexts.count {
                contexts[index].touchUp(sample(pointers[index]), at: time)
            }
            for context in contexts { context.setPointerCount(pointers.count - 1, at: time) }
            if index == 0 && pointers.count > 1 && !contexts[0].isCancelled {
                // The second finger becomes the first
                contexts[0].touchDown(sample(pointers[1]), at: time, isNewFinger: false)
            }
        case .move:
            for context in contexts where context.actionIndex < pointers.count {
                context.touchMove(sample(pointers[context.actionIndex]), at: time)
            }
        case .cancel:
            for context in contexts {
                context.cancel()
                context.setPointerCount(0, at: time)
            }
        }
    }

    // MARK: Pinch to zoom anytime

    private static func span(_ pointers: [TouchPointer]) -> CGFloat {
        guard pointers.count >= 2 else { return 0 }
        return hypot(pointers[0].point.x - pointers[1].point.x, pointers[0].point.y - pointers[1].point.y)
    }

    private static func focus(_ pointers: [TouchPointer]) -> CGPoint {
        let count = CGFloat(pointers.count)
        return CGPoint(x: pointers.map(\.point.x).reduce(0, +) / count, y: pointers.map(\.point.y).reduce(0, +) / count)
    }

    /// Returns true while a pinch owns the gesture.
    private func handlePinch(_ action: TouchAction, pointers: [TouchPointer]) -> Bool {
        guard pinchToZoom, mode != .multiTouch else { return false }
        if pinchActive {
            switch action {
            case .move:
                if pointers.count >= 2 { zoomStep(pointers) }
            case .up(_, let p) where p.count == 1:
                pinchActive = false
                pinchStartSpan = 0
            case .cancel:
                pinchActive = false
                pinchStartSpan = 0
            case .down:
                beginZoomStep(pointers)
            case .up(let index, var remaining):
                remaining.remove(at: index)
                beginZoomStep(remaining)
            }
            return true
        }
        switch action {
        case .down where pointers.count == 2:
            pinchStartSpan = Self.span(pointers)
        case .move where pointers.count == 2 && pinchStartSpan > 0:
            let span = Self.span(pointers)
            if abs(span - pinchStartSpan) > pinchStartSpan * Self.pinchStartFraction {
                // A pinch: let go of anything the fingers were doing on the PC
                pinchActive = true
                for context in contexts { context.cancel() }
                pinchLastSpan = pinchStartSpan
                pinchLastFocus = Self.focus(pointers)
                zoomStep(pointers)
                return true
            }
        case .up(_, let p) where p.count <= 2:
            pinchStartSpan = 0
        case .cancel:
            pinchStartSpan = 0
        default:
            break
        }
        return false
    }

    private func beginZoomStep(_ pointers: [TouchPointer]) {
        pinchLastSpan = Self.span(pointers)
        pinchLastFocus = pointers.isEmpty ? .zero : Self.focus(pointers)
    }

    /// Zooms about the point between the fingers and pans with it (PanZoomHandler).
    private func zoomStep(_ pointers: [TouchPointer]) {
        let span = Self.span(pointers)
        let focus = Self.focus(pointers)
        var g = geometry
        if pinchLastSpan > 0 && span > 0 {
            g = g.zoomed(by: span / pinchLastSpan, around: focus, maxZoom: Self.maxZoom)
        }
        g.pan.x += focus.x - pinchLastFocus.x
        g.pan.y += focus.y - pinchLastFocus.y
        g = g.clamped(maxZoom: Self.maxZoom)
        pinchLastSpan = span
        pinchLastFocus = focus
        geometry = g
        onOutcome(.geometry(g))
    }

    // MARK: Pan and zoom mode

    private func handlePanZoom(_ action: TouchAction, pointers: [TouchPointer], at time: TimeInterval) {
        switch action {
        case .down(_, _) where pointers.count == 1:
            panLast = pointers[0].point
            panMoved = false
            panDownTime = time
            panDownPoint = pointers[0].point
        case .down:
            beginZoomStep(pointers)
            panLast = nil
            panMoved = true
        case .move:
            if pointers.count >= 2 {
                zoomStep(pointers)
            } else if let last = panLast, let p = pointers.first?.point {
                if hypot(p.x - panDownPoint.x, p.y - panDownPoint.y) > 8 { panMoved = true }
                var g = geometry
                g.pan.x += p.x - last.x
                g.pan.y += p.y - last.y
                g = g.clamped(maxZoom: Self.maxZoom)
                geometry = g
                panLast = p
                onOutcome(.geometry(g))
            }
        case .up(let index, let all):
            if all.count == 1 {
                // A double tap resets the zoom (Android's GestureDetector: 300 ms apart, close by)
                if !panMoved && time - panDownTime < 0.3 {
                    let p = all[0].point
                    if time - lastPanTapTime < 0.3 && hypot(p.x - lastPanTapPoint.x, p.y - lastPanTapPoint.y) < 50 {
                        var g = geometry
                        g.zoom = 1
                        g.pan = .zero
                        geometry = g
                        onOutcome(.geometry(g))
                        lastPanTapTime = -.infinity
                    } else {
                        lastPanTapTime = time
                        lastPanTapPoint = p
                    }
                }
                panLast = nil
            } else {
                var remaining = all
                remaining.remove(at: index)
                beginZoomStep(remaining)
                panLast = remaining.count == 1 ? remaining[0].point : nil
            }
        case .cancel:
            panLast = nil
        }
    }
}

extension VideoGeometry {
    /// Zoomed by `factor` about `focus` (a view point), which stays over the same spot.
    public func zoomed(by factor: CGFloat, around focus: CGPoint, maxZoom: CGFloat = 10) -> VideoGeometry {
        var g = self
        let newZoom = min(max(zoom * factor, 1), maxZoom)
        let applied = newZoom / zoom
        let rect = videoRect
        // The picture's new top-left corner keeps the focus over the same spot
        let newMinX = focus.x + (rect.minX - focus.x) * applied
        let newMinY = focus.y + (rect.minY - focus.y) * applied
        g.zoom = newZoom
        let moved = g.videoRect
        g.pan.x += newMinX - moved.minX
        g.pan.y += newMinY - moved.minY
        return g
    }
}
