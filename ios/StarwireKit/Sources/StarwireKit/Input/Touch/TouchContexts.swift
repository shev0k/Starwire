import Foundation

// The touch modes' gesture logic, one context per finger slot (the first and second finger), as
// Starwire for Android does it. Ported from Starwire for Android (GPL-3.0):
//   TrackpadContext.java       natural trackpad (from Artemide)
//   RelativeTouchContext.java  gaming trackpad (moonlight-android)
//   AbsoluteTouchContext.java  direct touch and swapped clicks (moonlight-android)
//
// Android's handlers post Runnables on a timer; here every context names its timers in a shared
// `InputTimers`, and the dispatcher fires the due ones from `tick(now:)`, so tests drive time.
// Coordinates are whole pixels (points times the screen scale), so Android's pixel thresholds
// keep their values. Times are seconds.

/// Timers by name, with deadlines on the caller's clock.
public final class InputTimers {
    private var deadlines: [String: TimeInterval] = [:]

    public init() {}

    public func schedule(_ name: String, at time: TimeInterval) {
        deadlines[name] = time
    }

    public func cancel(_ name: String) {
        deadlines[name] = nil
    }

    public func cancelAll(prefix: String) {
        for key in deadlines.keys where key.hasPrefix(prefix) {
            deadlines[key] = nil
        }
    }

    public func isScheduled(_ name: String) -> Bool {
        deadlines[name] != nil
    }

    public var nextDeadline: TimeInterval? {
        deadlines.values.min()
    }

    /// Removes and returns the timers due by `now`, earliest first.
    public func popDue(now: TimeInterval) -> [(name: String, time: TimeInterval)] {
        let due = deadlines.filter { $0.value <= now }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
        for (name, _) in due {
            deadlines[name] = nil
        }
        return due.map { ($0.key, $0.value) }
    }
}

/// A finger position in pixels, plus its point in the view for absolute positions.
public struct TouchSample: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var point: CGPoint

    public init(x: Int, y: Int, point: CGPoint) {
        self.x = x
        self.y = y
        self.point = point
    }
}

/// One finger slot's gesture logic.
public protocol TouchContext: AnyObject {
    var actionIndex: Int { get }
    var isCancelled: Bool { get }
    func touchDown(_ sample: TouchSample, at time: TimeInterval, isNewFinger: Bool)
    func touchUp(_ sample: TouchSample, at time: TimeInterval)
    func touchMove(_ sample: TouchSample, at time: TimeInterval)
    func cancel()
    func setPointerCount(_ count: Int, at time: TimeInterval)
    /// A timer this context scheduled is due.
    func fire(_ timer: String, at time: TimeInterval)
}

/// What the contexts need from the stream.
public final class TouchEnvironment {
    public var timers: InputTimers
    public var emit: (InputEvent) -> Void
    public var geometry: VideoGeometry
    /// The view's size in pixels, for the gaming trackpad's scaling.
    public var viewPixelSize: CGSize
    public var longPressRightClick: Bool
    /// Remote desktop mouse mode (`checkbox_absolute_mouse_mode`)
    public var absoluteMouseMode: Bool

    public init(timers: InputTimers = InputTimers(), geometry: VideoGeometry, viewPixelSize: CGSize,
                longPressRightClick: Bool = true, absoluteMouseMode: Bool = false, emit: @escaping (InputEvent) -> Void) {
        self.timers = timers
        self.geometry = geometry
        self.viewPixelSize = viewPixelSize
        self.longPressRightClick = longPressRightClick
        self.absoluteMouseMode = absoluteMouseMode
        self.emit = emit
    }

    func buttonDown(_ button: Int) { emit(.mouseButton(button: button, down: true)) }
    func buttonUp(_ button: Int) { emit(.mouseButton(button: button, down: false)) }
}

enum MouseButton {
    static let left = 1, middle = 2, right = 3, back = 4, forward = 5
}

// MARK: - Natural trackpad

/// Natural trackpad (Android's TrackpadContext): tap to click, tap then drag to drag, two-finger
/// tap for right click, three-finger tap for middle click, two-finger scroll, flicks with
/// momentum, and a small speed curve.
public final class NaturalTrackpadContext: TouchContext {
    public static let tapMovementThreshold = 30
    public static let tapTimeThreshold: TimeInterval = 0.230
    public static let clickReleaseDelay: TimeInterval = 0.230
    public static let scrollSpeedFactorX = 2.0
    public static let scrollSpeedFactorY = 3.0
    public static let accelerationThreshold = 8.0
    public static let flickFriction = 0.93
    /// Pixels per millisecond
    public static let flickThreshold = 0.8
    public static let momentumInterval: TimeInterval = 0.010
    public static let flickVelocityDecayTimeout: TimeInterval = 0.050
    public static let scrollTransitionTimeout: TimeInterval = 0.200

    public let actionIndex: Int
    private let env: TouchEnvironment
    private let sensitivity: Double
    private var pendingX = 0.0, pendingY = 0.0
    private var lastX = 0, lastY = 0, originalX = 0, originalY = 0
    private var originalTime: TimeInterval = 0
    public private(set) var isCancelled = false
    private var confirmedMove = false, confirmedDrag = false, confirmedScroll = false
    private var distanceMoved = 0.0
    private var pointerCount = 0
    private var clickedMiddle = false
    private var maxPointerCount = 0
    private var isClickPending = false, isDoubleClickPending = false
    private var isFlicking = false
    private var flickIsScroll = false
    /// Pixels per millisecond, as Android keeps them
    private var velocityX = 0.0, velocityY = 0.0
    private var lastMoveTime: TimeInterval = 0
    private var isScrollTransitioning = false
    private var pendingClickButton = MouseButton.left

    private var timerPrefix: String { "natural\(actionIndex)." }
    private var momentumTimer: String { timerPrefix + "momentum" }
    private var clickTimer: String { timerPrefix + "click" }
    private var transitionTimer: String { timerPrefix + "transition" }

    /// `sensitivity` in percent, 100 for none.
    public init(actionIndex: Int, environment: TouchEnvironment, sensitivity: Int = 100) {
        self.actionIndex = actionIndex
        env = environment
        self.sensitivity = Double(sensitivity) / 100
    }

    private func withinTapBounds(_ x: Int, _ y: Int) -> Bool {
        abs(x - originalX) <= Self.tapMovementThreshold && abs(y - originalY) <= Self.tapMovementThreshold
    }

    private func isTap(_ time: TimeInterval) -> Bool {
        if confirmedDrag || confirmedMove || confirmedScroll { return false }
        if actionIndex + 1 != maxPointerCount { return false }
        return withinTapBounds(lastX, lastY) && time - originalTime <= Self.tapTimeThreshold + 1e-9
    }

    private func mouseButtonIndex() -> Int {
        if pointerCount == 2 { return MouseButton.right }
        if pointerCount == 3 {
            clickedMiddle = true
            return MouseButton.middle
        }
        return MouseButton.left
    }

    private func stopFlick() {
        isFlicking = false
        env.timers.cancel(momentumTimer)
    }

    /// Android's handler.removeCallbacksAndMessages(null): every pending runnable of this context
    private func cancelAllTimers() {
        env.timers.cancelAll(prefix: timerPrefix)
    }

    public func touchDown(_ s: TouchSample, at time: TimeInterval, isNewFinger: Bool) {
        if isFlicking {
            isFlicking = false
            cancelAllTimers()
        }
        originalX = s.x; lastX = s.x
        originalY = s.y; lastY = s.y
        pendingX = 0; pendingY = 0
        if isNewFinger {
            clickedMiddle = false
            env.timers.cancel(transitionTimer)
            isScrollTransitioning = false
            maxPointerCount = pointerCount
            originalTime = time
            isCancelled = false; confirmedMove = false; confirmedScroll = false
            distanceMoved = 0
            velocityX = 0; velocityY = 0
            lastMoveTime = time
            if isClickPending {
                isClickPending = false
                isDoubleClickPending = true
                confirmedDrag = true
            }
        } else {
            if pointerCount == 2 && !confirmedMove {
                env.buttonDown(MouseButton.middle)
                env.buttonUp(MouseButton.middle)
                isClickPending = false; isDoubleClickPending = false; confirmedDrag = false
                clickedMiddle = true
            } else if pointerCount == 1 && !confirmedMove && !clickedMiddle {
                // The second finger lifted first: right click at once
                env.buttonDown(MouseButton.right)
                env.buttonUp(MouseButton.right)
                isClickPending = false; isDoubleClickPending = false; confirmedDrag = false
            }
        }
    }

    public func touchUp(_ s: TouchSample, at time: TimeInterval) {
        if isCancelled { return }
        let sinceMove = time - lastMoveTime
        if sinceMove > 0 {
            let decay = max(0, 1 - sinceMove / Self.flickVelocityDecayTimeout)
            velocityX *= decay
            velocityY *= decay
        }
        let button = mouseButtonIndex()
        let speed = (velocityX * velocityX + velocityY * velocityY).squareRoot()
        if isDoubleClickPending {
            cancelAllTimers()
            env.buttonUp(button)
            env.buttonDown(button)
            env.buttonUp(button)
            isClickPending = false
            confirmedDrag = false
        } else if confirmedDrag {
            cancelAllTimers()
            if speed > Self.flickThreshold {
                startFlick(scroll: false, at: time)
            } else {
                env.buttonUp(button)
                confirmedDrag = false
            }
        } else if isTap(time) {
            env.buttonDown(button)
            isClickPending = true
            pendingClickButton = button
            cancelAllTimers()
            env.timers.schedule(clickTimer, at: time + Self.clickReleaseDelay)
        } else if confirmedMove, speed > Self.flickThreshold {
            if confirmedScroll {
                startFlick(scroll: true, at: time)
            } else if maxPointerCount == 1 {
                // Only a one-finger move flicks the mouse
                startFlick(scroll: false, at: time)
            }
        }
    }

    private func startFlick(scroll: Bool, at time: TimeInterval) {
        isFlicking = true
        flickIsScroll = scroll
        // Android posts the first frame at once
        fire(momentumTimer, at: time)
    }

    public func touchMove(_ s: TouchSample, at time: TimeInterval) {
        if isCancelled { return }
        guard s.x != lastX || s.y != lastY else { return }
        let deltaTimeMs = (time - lastMoveTime) * 1000
        checkForConfirmedMove(s.x, s.y)
        if isDoubleClickPending {
            isDoubleClickPending = false
            confirmedDrag = true
        }
        let rawX = Double(s.x - lastX), rawY = Double(s.y - lastY)
        let magnitude = (rawX * rawX + rawY * rawY).squareRoot()
        let precision = cbrt(magnitude / Self.accelerationThreshold)
        let deltaX = rawX * precision * sensitivity
        let deltaY = rawY * precision * sensitivity
        if deltaTimeMs > 0 && (confirmedMove || confirmedDrag) {
            let vx = deltaX / deltaTimeMs, vy = deltaY / deltaTimeMs
            if velocityX == 0 && velocityY == 0 {
                velocityX = vx; velocityY = vy
            } else {
                velocityX = velocityX * 0.8 + vx * 0.2
                velocityY = velocityY * 0.8 + vy * 0.2
            }
        }
        lastMoveTime = time
        pendingX += deltaX
        pendingY += deltaY
        lastX = s.x
        lastY = s.y
        let sendX = Int(pendingX), sendY = Int(pendingY)
        if pointerCount == 1 {
            // No mouse movement right after a scroll
            if !isScrollTransitioning && (sendX != 0 || sendY != 0) {
                env.emit(.mouseMove(dx: sendX, dy: sendY))
            }
        } else if actionIndex == 1 {
            if confirmedDrag {
                if sendX != 0 || sendY != 0 {
                    env.emit(.mouseMove(dx: sendX, dy: sendY))
                }
            } else if pointerCount == 2 {
                confirmedScroll = actionIndex == 1 && pointerCount == 2 && confirmedMove
                if confirmedScroll {
                    sendScroll(dx: Double(sendX), dy: Double(sendY), absX: abs(rawX), absY: abs(rawY))
                }
            }
        }
        pendingX -= Double(sendX)
        pendingY -= Double(sendY)
    }

    /// The dominant axis scrolls; the other one too when it's nearly as large.
    private func sendScroll(dx: Double, dy: Double, absX: Double, absY: Double) {
        if absX > absY {
            env.emit(.hScroll(amount: Int(-dx * Self.scrollSpeedFactorX)))
            if absY * 1.05 > absX {
                env.emit(.scroll(amount: Int(dy * Self.scrollSpeedFactorY)))
            }
        } else {
            env.emit(.scroll(amount: Int(dy * Self.scrollSpeedFactorY)))
            if absX * 1.05 >= absY {
                env.emit(.hScroll(amount: Int(-dx * Self.scrollSpeedFactorX)))
            }
        }
    }

    private func checkForConfirmedMove(_ x: Int, _ y: Int) {
        if confirmedMove || confirmedDrag { return }
        if !withinTapBounds(x, y) {
            confirmedMove = true
            return
        }
        distanceMoved += (pow(Double(x - lastX), 2) + pow(Double(y - lastY), 2)).squareRoot()
        if distanceMoved >= Double(Self.tapMovementThreshold) {
            confirmedMove = true
        }
    }

    public func cancel() {
        isCancelled = true
        if isFlicking {
            isFlicking = false
            cancelAllTimers()
        }
        if confirmedDrag {
            env.buttonUp(mouseButtonIndex())
        }
    }

    public func setPointerCount(_ count: Int, at time: TimeInterval) {
        if pointerCount == 2 && count == 1 {
            // A two-finger scroll just ended: ignore the last finger's movement for a moment
            isScrollTransitioning = true
            env.timers.schedule(transitionTimer, at: time + Self.scrollTransitionTimeout)
        } else if pointerCount == 1 && count == 2 {
            env.timers.cancel(transitionTimer)
            isScrollTransitioning = false
        }
        if count < pointerCount && confirmedDrag && !isFlicking {
            env.buttonUp(mouseButtonIndex())
            confirmedDrag = false; confirmedMove = false; confirmedScroll = false
            isClickPending = false; isDoubleClickPending = false
        }
        pointerCount = count
        maxPointerCount = max(maxPointerCount, count)
    }

    public func fire(_ timer: String, at time: TimeInterval) {
        switch timer {
        case transitionTimer:
            isScrollTransitioning = false
        case clickTimer:
            if isClickPending {
                env.buttonUp(pendingClickButton)
                isClickPending = false
            }
            isDoubleClickPending = false
        case momentumTimer:
            guard isFlicking else { return }
            let interval = Self.momentumInterval * 1000
            if flickIsScroll {
                let fx = velocityX * interval, fy = velocityY * interval
                if abs(fx) > abs(fy) {
                    env.emit(.hScroll(amount: Int(-fx * Self.scrollSpeedFactorX)))
                    if abs(fy) * 1.05 > abs(fx) { env.emit(.scroll(amount: Int(fy * Self.scrollSpeedFactorY))) }
                } else {
                    env.emit(.scroll(amount: Int(fy * Self.scrollSpeedFactorY)))
                    if abs(fx) * 1.05 >= abs(fy) { env.emit(.hScroll(amount: Int(-fx * Self.scrollSpeedFactorX))) }
                }
            } else {
                pendingX += velocityX * interval
                pendingY += velocityY * interval
                let ix = Int(pendingX), iy = Int(pendingY)
                if ix != 0 || iy != 0 {
                    env.emit(.mouseMove(dx: ix, dy: iy))
                    pendingX -= Double(ix)
                    pendingY -= Double(iy)
                }
            }
            velocityX *= Self.flickFriction
            velocityY *= Self.flickFriction
            if (velocityX * velocityX + velocityY * velocityY).squareRoot() * interval < 0.5 {
                isFlicking = false
                if !flickIsScroll && confirmedDrag {
                    env.buttonUp(mouseButtonIndex())
                    confirmedDrag = false
                }
            }
            if isFlicking {
                env.timers.schedule(momentumTimer, at: time + Self.momentumInterval)
            }
        default:
            break
        }
    }
}

// MARK: - Gaming trackpad

/// Gaming trackpad (Android's RelativeTouchContext): relative mouse moves scaled to a 1280x720
/// reference, tap to click, two-finger tap for right click, hold to drag (or right click with
/// long-press right click on), two-finger scroll. Movement keeps its fractions.
public final class GamingTrackpadContext: TouchContext {
    public static let tapMovementThreshold = 20
    public static let tapDistanceThreshold = 25.0
    public static let tapTimeThreshold: TimeInterval = 0.250
    public static let dragTimeThreshold: TimeInterval = 0.650
    public static let scrollSpeedFactor = 5
    public static let tapReleaseDelay: TimeInterval = 0.100
    public static let referenceWidth = 1280.0
    public static let referenceHeight = 720.0

    public let actionIndex: Int
    private let env: TouchEnvironment
    private let sensitivity: Double
    private var lastX = 0, lastY = 0, originalX = 0, originalY = 0
    private var originalTime: TimeInterval = 0
    public private(set) var isCancelled = false
    private var confirmedMove = false, confirmedDrag = false, confirmedScroll = false
    private var distanceMoved = 0.0
    private var pointerCount = 0, maxPointerCount = 0
    private var dragButton = MouseButton.left
    private var accumulator = MouseAccumulator()
    private var scrollRemainder = 0.0

    private var dragTimer: String { "gaming\(actionIndex).drag" }
    private func releaseTimer(_ button: Int) -> String { "gaming\(actionIndex).release\(button)" }

    public init(actionIndex: Int, environment: TouchEnvironment, sensitivity: Int = 100) {
        self.actionIndex = actionIndex
        env = environment
        self.sensitivity = Double(sensitivity) / 100
    }

    private var xFactor: Double { Self.referenceWidth / max(Double(env.viewPixelSize.width), 1) }
    private var yFactor: Double { Self.referenceHeight / max(Double(env.viewPixelSize.height), 1) }

    private func withinTapBounds(_ x: Int, _ y: Int) -> Bool {
        abs(x - originalX) <= Self.tapMovementThreshold && abs(y - originalY) <= Self.tapMovementThreshold
    }

    private func isTap(_ time: TimeInterval) -> Bool {
        if confirmedDrag || confirmedMove || confirmedScroll { return false }
        if actionIndex + 1 != maxPointerCount { return false }
        return withinTapBounds(lastX, lastY) && time - originalTime <= Self.tapTimeThreshold + 1e-9
    }

    private var buttonIndex: Int { actionIndex == 1 ? MouseButton.right : MouseButton.left }

    public func touchDown(_ s: TouchSample, at time: TimeInterval, isNewFinger: Bool) {
        originalX = s.x; lastX = s.x
        originalY = s.y; lastY = s.y
        if isNewFinger {
            maxPointerCount = pointerCount
            originalTime = time
            isCancelled = false; confirmedDrag = false; confirmedMove = false; confirmedScroll = false
            distanceMoved = 0
            accumulator.reset()
            scrollRemainder = 0
            if actionIndex == 0 {
                env.timers.schedule(dragTimer, at: time + Self.dragTimeThreshold)
            }
        }
    }

    public func touchUp(_ s: TouchSample, at time: TimeInterval) {
        if isCancelled { return }
        env.timers.cancel(dragTimer)
        if confirmedDrag {
            env.buttonUp(dragButton)
        } else if isTap(time) {
            let button = buttonIndex
            env.buttonDown(button)
            env.timers.schedule(releaseTimer(button), at: time + Self.tapReleaseDelay)
        }
    }

    private func checkForConfirmedMove(_ x: Int, _ y: Int) {
        if confirmedMove || confirmedDrag { return }
        if !withinTapBounds(x, y) {
            confirmedMove = true
            env.timers.cancel(dragTimer)
            return
        }
        distanceMoved += (pow(Double(x - lastX), 2) + pow(Double(y - lastY), 2)).squareRoot()
        if distanceMoved >= Self.tapDistanceThreshold {
            confirmedMove = true
            env.timers.cancel(dragTimer)
        }
    }

    public func touchMove(_ s: TouchSample, at time: TimeInterval) {
        if isCancelled { return }
        guard s.x != lastX || s.y != lastY else { return }
        checkForConfirmedMove(s.x, s.y)
        confirmedScroll = actionIndex == 0 && pointerCount == 2 && confirmedMove
        if actionIndex == 0 {
            let dx = Double(s.x - lastX) * xFactor * sensitivity
            let dy = Double(s.y - lastY) * yFactor * sensitivity
            if pointerCount == 2 {
                if confirmedScroll {
                    scrollRemainder += dy * Double(Self.scrollSpeedFactor)
                    let whole = Int(scrollRemainder)
                    if whole != 0 {
                        env.emit(.scroll(amount: whole))
                        scrollRemainder -= Double(whole)
                    }
                }
            } else if let move = accumulator.add(dx: dx, dy: dy), case .mouseMove(let mx, let my) = move {
                if env.absoluteMouseMode {
                    env.emit(.mouseMoveAsPosition(dx: mx, dy: my, width: Int(env.viewPixelSize.width),
                                                  height: Int(env.viewPixelSize.height)))
                } else {
                    env.emit(move)
                }
            }
        }
        lastX = s.x
        lastY = s.y
    }

    public func cancel() {
        isCancelled = true
        env.timers.cancel(dragTimer)
        if confirmedDrag {
            env.buttonUp(dragButton)
        }
    }

    public func setPointerCount(_ count: Int, at time: TimeInterval) {
        pointerCount = count
        maxPointerCount = max(maxPointerCount, count)
    }

    public func fire(_ timer: String, at time: TimeInterval) {
        if timer == dragTimer {
            if confirmedMove || actionIndex != maxPointerCount - 1 { return }
            confirmedDrag = true
            dragButton = env.longPressRightClick && actionIndex == 0 ? MouseButton.right : buttonIndex
            env.buttonDown(dragButton)
        } else if timer.hasPrefix("gaming\(actionIndex).release"), let button = Int(timer.dropFirst("gaming\(actionIndex).release".count)) {
            env.buttonUp(button)
        }
    }
}

// MARK: - Direct touch

/// Direct touch (Android's AbsoluteTouchContext): the cursor goes under the finger, a tap
/// clicks there, a long press right clicks, and a second finger scrolls. Swapped clicks trade
/// the left and right buttons.
public final class DirectTouchContext: TouchContext {
    public static let scrollSpeedFactor = 3
    public static let longPressTime: TimeInterval = 0.650
    public static let longPressDistance = 30.0
    public static let doubleTapTime: TimeInterval = 0.250
    public static let doubleTapDistance = 60.0
    public static let touchDownDeadZoneTime: TimeInterval = 0.100
    public static let touchDownDeadZoneDistance = 20.0
    public static let tapReleaseDelay: TimeInterval = 0.100

    public let actionIndex: Int
    private let env: TouchEnvironment
    private let primary: Int
    private let secondary: Int
    private var lastDown = TouchSample(x: 0, y: 0, point: .zero)
    private var lastDownTime: TimeInterval = 0
    private var lastUp = TouchSample(x: 0, y: 0, point: .zero)
    private var lastUpTime: TimeInterval = -.infinity
    private var lastLocationY = 0
    public private(set) var isCancelled = false
    private var confirmedLongPress = false, confirmedTap = false

    private var longPressTimer: String { "direct\(actionIndex).longpress" }
    private var tapDownTimer: String { "direct\(actionIndex).tapdown" }
    private var releaseTimer: String { "direct\(actionIndex).release" }

    public init(actionIndex: Int, environment: TouchEnvironment, swapped: Bool = false) {
        self.actionIndex = actionIndex
        env = environment
        primary = swapped ? MouseButton.right : MouseButton.left
        secondary = swapped ? MouseButton.left : MouseButton.right
    }

    private func distance(_ a: TouchSample, _ b: TouchSample) -> Double {
        (pow(Double(a.x - b.x), 2) + pow(Double(a.y - b.y), 2)).squareRoot()
    }

    public func touchDown(_ s: TouchSample, at time: TimeInterval, isNewFinger: Bool) {
        guard isNewFinger else { return }
        lastDown = s
        lastLocationY = s.y
        lastDownTime = time
        isCancelled = false; confirmedTap = false; confirmedLongPress = false
        if actionIndex == 0 {
            env.timers.schedule(tapDownTimer, at: time + Self.touchDownDeadZoneTime)
            if env.longPressRightClick {
                env.timers.schedule(longPressTimer, at: time + Self.longPressTime)
            }
        }
    }

    private func updatePosition(_ point: CGPoint) {
        env.emit(env.geometry.mousePosition(point))
    }

    private func tapConfirmed() {
        if confirmedTap || confirmedLongPress { return }
        confirmedTap = true
        env.timers.cancel(tapDownTimer)
        // A second tap close to the first, soon after it, clicks where the first one did, so a
        // double click lands on one spot
        if lastDownTime - lastUpTime > Self.doubleTapTime || distance(lastDown, lastUp) > Self.doubleTapDistance {
            updatePosition(lastDown.point)
        }
        env.buttonDown(primary)
    }

    public func touchUp(_ s: TouchSample, at time: TimeInterval) {
        if isCancelled { return }
        if actionIndex == 0 {
            env.timers.cancel(longPressTimer)
            env.timers.cancel(tapDownTimer)
            if confirmedLongPress {
                env.buttonUp(secondary)
            } else if confirmedTap {
                env.buttonUp(primary)
            } else {
                tapConfirmed()
                env.timers.schedule(releaseTimer, at: time + Self.tapReleaseDelay)
            }
        }
        lastUp = s
        lastLocationY = s.y
        lastUpTime = time
    }

    public func touchMove(_ s: TouchSample, at time: TimeInterval) {
        if isCancelled { return }
        if actionIndex == 0 {
            let moved = distance(s, lastDown)
            if moved > Self.longPressDistance {
                env.timers.cancel(longPressTimer)
            }
            if confirmedTap || moved > Self.touchDownDeadZoneDistance {
                tapConfirmed()
                updatePosition(s.point)
            }
        } else if actionIndex == 1 {
            env.emit(.scroll(amount: (s.y - lastLocationY) * Self.scrollSpeedFactor))
        }
        lastLocationY = s.y
    }

    public func cancel() {
        isCancelled = true
        env.timers.cancel(longPressTimer)
        env.timers.cancel(tapDownTimer)
        if confirmedLongPress {
            env.buttonUp(secondary)
        } else if confirmedTap {
            env.buttonUp(primary)
        }
    }

    public func setPointerCount(_ count: Int, at time: TimeInterval) {
        if actionIndex == 0 && count > 1 {
            cancel()
        }
    }

    public func fire(_ timer: String, at time: TimeInterval) {
        switch timer {
        case longPressTimer:
            env.timers.cancel(tapDownTimer)
            confirmedLongPress = true
            if confirmedTap {
                env.buttonUp(primary)
            }
            env.buttonDown(secondary)
        case tapDownTimer:
            tapConfirmed()
        case releaseTimer:
            env.buttonUp(primary)
        default:
            break
        }
    }
}
