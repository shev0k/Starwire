import Foundation

// Ported from Starwire for Android's ControllerHandler.java (GPL-3.0; Moonlight for Android, cgutman
// and contributors): handleDeadZone, handleFlipFaceButtons, sendControllerInputPacket (mouse
// emulation), the mouse emulation runnable, convertRawStickAxisToPixelMovement,
// sendEmulatedMouseMove and sendEmulatedMouseScroll, and the touchpad paths in
// tryHandleTouchpadEvent. The constants are Android's. Where this port differs on purpose, the
// comment says so.
//
// Nothing here reads a controller. The app reads its gamepads with GameController, turns the
// values into the plain numbers below, and sends what comes back to an `InputSink`.

/// Which stick scrolls while mouse emulation is on (`analog_scrolling`).
public enum AnalogScrolling: String, Equatable, Sendable, CaseIterable {
    /// Both sticks move the mouse.
    case none
    /// The left stick moves the mouse and the right stick scrolls.
    case right
    /// The right stick moves the mouse and the left stick scrolls.
    case left
}

/// The gamepad settings, read once.
public struct GamepadOptions: Equatable, Sendable {
    /// `seekbar_deadzone`, in percent. Android treats 0 or less as 1.
    public var deadzonePercent: Int
    /// `checkbox_flip_face_buttons`: A and B swap, X and Y swap.
    public var flipFaceButtons: Bool
    /// `analog_scrolling`
    public var analogScrolling: AnalogScrolling
    /// `checkbox_gamepad_touchpad_as_mouse`
    public var touchpadAsMouse: Bool

    public init(deadzonePercent: Int = 7, flipFaceButtons: Bool = false, analogScrolling: AnalogScrolling = .right,
                touchpadAsMouse: Bool = false) {
        self.deadzonePercent = deadzonePercent
        self.flipFaceButtons = flipFaceButtons
        self.analogScrolling = analogScrolling
        self.touchpadAsMouse = touchpadAsMouse
    }

    public init(store: SettingsStore) {
        var options = GamepadOptions()
        if case .int(let value)? = store.value("seekbar_deadzone") { options.deadzonePercent = value }
        if case .bool(let value)? = store.value("checkbox_flip_face_buttons") { options.flipFaceButtons = value }
        if case .string(let value)? = store.value("analog_scrolling") {
            // Android treats any other text as "none"
            options.analogScrolling = AnalogScrolling(rawValue: value) ?? .none
        }
        if case .bool(let value)? = store.value("checkbox_gamepad_touchpad_as_mouse") { options.touchpadAsMouse = value }
        self = options
    }
}

/// Android's gamepad arithmetic, as pure functions.
public enum GamepadMath {
    /// A stick at full deflection is sent as 0x7FFE (32766), not 32767.
    public static let stickScale: Float = 0x7FFE

    /// Android's trigger deadzone when the device reports none: 13%, around XInput's default.
    public static let defaultTriggerDeadzone: Float = 0.13

    /// The deadzone as a radius from 0 to 1: `seekbar_deadzone` percent over 100, at least 1%.
    /// `(float) ((double) percent / 100.0)` in Android.
    public static func deadzoneRadius(percent: Int) -> Float {
        Float(Double(percent <= 0 ? 1 : percent) / 100.0)
    }

    /// One stick as Android sends it. `x` runs right and `y` runs up, from -1 to 1, as
    /// GameController reports them (Android's own y runs down, and it negates it here).
    ///
    /// The deadzone is radial and not rescaled: inside it, or exactly on its edge, the stick is
    /// (0, 0). Outside it the value passes through unchanged, because "we let the computer handle
    /// the deadzones". Normalizing would make the deadzone larger once the PC applies its own.
    /// Full deflection is 32766.
    public static func stick(x: Float, y: Float, deadzone: Float) -> (x: Int, y: Int) {
        let magnitude = (Double(x) * Double(x) + Double(y) * Double(y)).squareRoot()
        if magnitude <= Double(deadzone) {
            return (0, 0)
        }
        return (Int(x * stickScale), Int(y * stickScale))
    }

    /// One trigger, 0 to 1, as the byte Android sends: 0 at or under the deadzone, else the
    /// value times 255, cut down to a whole number.
    public static func trigger(_ value: Float, deadzone: Float = defaultTriggerDeadzone) -> Int {
        if value <= deadzone {
            return 0
        }
        return min(max(Int(value * 255), 0), 255)
    }

    /// Swaps A and B, and X and Y, as `handleFlipFaceButtons` does to each key.
    public static func flipFaceButtons(_ buttons: Int) -> Int {
        let faces = GamepadButton.a | GamepadButton.b | GamepadButton.x | GamepadButton.y
        var result = buttons & ~faces
        if buttons & GamepadButton.a != 0 { result |= GamepadButton.b }
        if buttons & GamepadButton.b != 0 { result |= GamepadButton.a }
        if buttons & GamepadButton.x != 0 { result |= GamepadButton.y }
        if buttons & GamepadButton.y != 0 { result |= GamepadButton.x }
        return result
    }

    /// How far a stick moves the mouse (or scrolls) in one 50 ms report, in pixels (or high
    /// resolution scroll units), before the 1 pixel minimum. `convertRawStickAxisToPixelMovement`.
    ///
    /// The stick is scaled to 0...4, then multiplied again by the square of its length, so the
    /// length grows as the cube: a half push moves 8, a full push 64. `x` runs right and `y` up,
    /// the way `GamepadMath.stick` returns them. The float steps follow Android's, so the
    /// rounding matches.
    public static func emulatedMovement(stickX: Int, stickY: Int) -> (x: Float, y: Float, magnitude: Double) {
        var x = Float(stickX)
        var y = Float(stickY)
        func magnitude() -> Double {
            (Double(x) * Double(x) + Double(y) * Double(y)).squareRoot()
        }
        func scale(_ factor: Double) {
            x = Float(Double(x) * factor)
            y = Float(Double(y) * factor)
        }
        scale(Double(Float(1) / 32766.0))
        scale(4)
        let length = magnitude()
        if length > 0 {
            // Move faster as the stick is pressed further from the centre
            scale(pow(length, 2))
        }
        return (x, y, magnitude())
    }

    /// Mouse emulation's `sendEmulatedMouseMove`: nothing under one pixel.
    public static func emulatedMouseMove(stickX: Int, stickY: Int) -> [InputEvent] {
        let movement = emulatedMovement(stickX: stickX, stickY: stickY)
        guard movement.magnitude >= 1 else { return [] }
        return [.mouseMove(dx: Int(movement.x), dy: Int(-movement.y))]
    }

    /// Mouse emulation's `sendEmulatedMouseScroll`: nothing under one unit. Android sends both
    /// the vertical and the horizontal scroll, even when one of them is zero.
    public static func emulatedMouseScroll(stickX: Int, stickY: Int) -> [InputEvent] {
        let movement = emulatedMovement(stickX: stickX, stickY: stickY)
        guard movement.magnitude >= 1 else { return [] }
        return [.scroll(amount: Int(movement.y)), .hScroll(amount: Int(movement.x))]
    }
}

/// One gamepad on its way to the PC: the deadzone, flipped face buttons and mouse emulation that
/// Android's `ControllerHandler` applies, for one controller number.
///
/// Call `update` whenever a value changes and `tick` when `nextDeadline` passes. Both return the
/// events to send, in order.
///
/// This differs from Android in one way: a state equal to the last one sent is not sent again.
/// Android sends one packet per motion event.
public final class GamepadProcessor {
    /// Android's `mouseEmulationReportPeriod`
    public static let mouseEmulationPeriod: TimeInterval = 0.05

    public var options: GamepadOptions
    public let controllerNumber: Int
    /// Bit n set for each controller n that is connected
    public var activeMask: Int
    /// Triggers' deadzone, 0 to 1. Android uses 13% unless the device says otherwise.
    public var triggerDeadzone: Float = GamepadMath.defaultTriggerDeadzone

    public private(set) var mouseEmulationActive = false
    /// When `tick` should be called next, or nil when nothing is waiting.
    public private(set) var nextDeadline: TimeInterval?

    // The context's values: what the controller says now, after the deadzone
    private var buttons = 0
    private var leftTrigger = 0
    private var rightTrigger = 0
    private var leftX = 0
    private var leftY = 0
    private var rightX = 0
    private var rightY = 0
    private var lastEmulationButtons = 0
    private var lastSent: ControllerState?

    public init(options: GamepadOptions = GamepadOptions(), controllerNumber: Int = 0, activeMask: Int = 1) {
        self.options = options
        self.controllerNumber = controllerNumber
        self.activeMask = activeMask
    }

    /// Turns mouse emulation on or off (the overlay menu's switch). Android doesn't clear the
    /// buttons it last saw, and doesn't release a mouse button held at the time.
    public func toggleMouseEmulation(now: TimeInterval) {
        mouseEmulationActive.toggle()
        nextDeadline = mouseEmulationActive ? now + Self.mouseEmulationPeriod : nil
    }

    /// The controller's whole state. Sticks run -1...1 with y up, triggers 0...1, and `buttons`
    /// are `GamepadButton` flags.
    public func update(buttons: Int, leftStick: (x: Float, y: Float), rightStick: (x: Float, y: Float),
                       leftTrigger: Float, rightTrigger: Float) -> [InputEvent] {
        let deadzone = GamepadMath.deadzoneRadius(percent: options.deadzonePercent)
        let left = GamepadMath.stick(x: leftStick.x, y: leftStick.y, deadzone: deadzone)
        let right = GamepadMath.stick(x: rightStick.x, y: rightStick.y, deadzone: deadzone)
        self.buttons = options.flipFaceButtons ? GamepadMath.flipFaceButtons(buttons) : buttons
        leftX = left.x
        leftY = left.y
        rightX = right.x
        rightY = right.y
        self.leftTrigger = GamepadMath.trigger(leftTrigger, deadzone: triggerDeadzone)
        self.rightTrigger = GamepadMath.trigger(rightTrigger, deadzone: triggerDeadzone)
        return packet()
    }

    /// Runs the mouse emulation report if it is due.
    public func tick(now: TimeInterval) -> [InputEvent] {
        guard let deadline = nextDeadline, now >= deadline else { return [] }
        // Android requeues from the time it ran, not from the time it was due
        nextDeadline = now + Self.mouseEmulationPeriod
        guard mouseEmulationActive else { return [] }
        switch options.analogScrolling {
        case .right:
            return GamepadMath.emulatedMouseMove(stickX: leftX, stickY: leftY)
                + GamepadMath.emulatedMouseScroll(stickX: rightX, stickY: rightY)
        case .left:
            return GamepadMath.emulatedMouseMove(stickX: rightX, stickY: rightY)
                + GamepadMath.emulatedMouseScroll(stickX: leftX, stickY: leftY)
        case .none:
            return GamepadMath.emulatedMouseMove(stickX: leftX, stickY: leftY)
                + GamepadMath.emulatedMouseMove(stickX: rightX, stickY: rightY)
        }
    }

    /// `sendControllerInputPacket`
    private func packet() -> [InputEvent] {
        var events: [InputEvent] = []
        let state: ControllerState
        if mouseEmulationActive {
            // A and B click, and each press of the d-pad is one notch of scroll. The PC sees an
            // idle controller meanwhile.
            let changed = buttons ^ lastEmulationButtons
            lastEmulationButtons = buttons
            if changed & GamepadButton.a != 0 {
                events.append(.mouseButton(button: 1, down: buttons & GamepadButton.a != 0))
            }
            if changed & GamepadButton.b != 0 {
                events.append(.mouseButton(button: 3, down: buttons & GamepadButton.b != 0))
            }
            if changed & GamepadButton.up != 0, buttons & GamepadButton.up != 0 {
                events.append(.scroll(amount: 120))
            }
            if changed & GamepadButton.down != 0, buttons & GamepadButton.down != 0 {
                events.append(.scroll(amount: -120))
            }
            if changed & GamepadButton.right != 0, buttons & GamepadButton.right != 0 {
                events.append(.hScroll(amount: 120))
            }
            if changed & GamepadButton.left != 0, buttons & GamepadButton.left != 0 {
                events.append(.hScroll(amount: -120))
            }
            state = ControllerState(number: controllerNumber, activeMask: activeMask)
        } else {
            state = ControllerState(number: controllerNumber, activeMask: activeMask, buttons: buttons,
                                    leftTrigger: leftTrigger, rightTrigger: rightTrigger,
                                    leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY)
        }
        if state != (lastSent ?? ControllerState(number: controllerNumber, activeMask: activeMask)) {
            events.append(.controller(state))
        }
        lastSent = state
        return events
    }
}

/// The DualSense touchpad, as Android handles it (`tryHandleTouchpadEvent`).
///
/// With "touchpad as mouse" off, touches go to the PC as the controller's own touchpad, 0 to 1
/// across the pad. With it on, they are not sent that way: finger movement moves the mouse and
/// a click of the pad is a left mouse click. The pad's button is also in the controller's
/// buttons (`GamepadButton.touchpad`) in both cases; the app sets it.
public struct GamepadTouchpad {
    public var controllerNumber: Int
    public var asMouse: Bool
    /// Mouse counts for a finger crossing the whole pad. On Android the system works out the
    /// movement of a touchpad and this number does not exist, so this one is a starting guess
    /// to tune on a device.
    public var countsAcrossPad: Double

    private var lastPoint: [Int: (x: Double, y: Double)] = [:]

    public init(controllerNumber: Int = 0, asMouse: Bool = false, countsAcrossPad: Double = 1500) {
        self.controllerNumber = controllerNumber
        self.asMouse = asMouse
        self.countsAcrossPad = countsAcrossPad
    }

    /// One finger on the pad. `x` and `y` run from 0 to 1 with y down. Only `.down`, `.move`,
    /// `.up` and `.cancel` mean anything; `.cancelAll` cancels every finger.
    public mutating func touch(id: Int, phase: TouchPhase, x: Double, y: Double, pressure: Double = 0) -> [InputEvent] {
        if !asMouse {
            switch phase {
            case .down, .move, .up, .cancel:
                return [.controllerTouch(number: controllerNumber, phase: phase, id: id, x: x, y: y, pressure: pressure)]
            case .cancelAll:
                return [.controllerTouch(number: controllerNumber, phase: .cancelAll, id: 0, x: 0, y: 0, pressure: 0)]
            default:
                return []
            }
        }
        switch phase {
        case .down:
            lastPoint[id] = (x, y)
            return []
        case .move:
            guard let last = lastPoint[id] else {
                lastPoint[id] = (x, y)
                return []
            }
            lastPoint[id] = (x, y)
            // Android casts each report to a short, which cuts toward zero
            let dx = Int(((x - last.x) * countsAcrossPad).rounded(.towardZero))
            let dy = Int(((y - last.y) * countsAcrossPad).rounded(.towardZero))
            return dx != 0 || dy != 0 ? [.mouseMove(dx: dx, dy: dy)] : []
        case .up, .cancel:
            lastPoint[id] = nil
            return []
        case .cancelAll:
            lastPoint = [:]
            return []
        default:
            return []
        }
    }

    /// The pad's button going down or up: a left click when the pad is a mouse.
    public func click(down: Bool) -> [InputEvent] {
        asMouse ? [.mouseButton(button: 1, down: down)] : []
    }
}
