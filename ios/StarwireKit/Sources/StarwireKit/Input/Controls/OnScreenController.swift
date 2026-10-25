import Foundation

// Ported from Starwire for Android's on-screen controller (GPL-3.0; Moonlight for Android, Karim
// Mreisi and contributors): VirtualController.java, VirtualControllerElement.java,
// VirtualControllerConfigurationLoader.java, DigitalButton.java, DigitalPad.java,
// AnalogStick.java, LeftAnalogStick.java, RightAnalogStick.java, LeftTrigger.java and
// RightTrigger.java.
//
// What this does like Android: a touch that goes down on a control belongs to that control until
// it lifts; controls on top are tried first; a stick only takes a touch that lands inside its
// circle; two thumbs work at once; a finger sliding from one button to another presses the second
// (within the same layer) and lets go of the first when it lifts.
//
// Where it differs, on purpose:
//   - A state equal to the one last sent is not sent again. Android sends one packet per touch
//     event and, after each, three more (25, 50 and 75 ms later) in case GFE dropped one.
//     `repeatsLikeAndroid` turns that back on.
//   - Android's angle for a finger exactly above or below a stick's centre is upside down (it
//     returns the angle of the opposite direction). The port gets it right.
//   - Android keeps the D-pad's, button's and stick's first finger and ignores a second finger
//     on the same control, but a lift of the first finger while the second is down is also
//     ignored there, so the control stays pressed until the last finger lifts. Here the control
//     lets go when its first finger lifts.
//   - Android's buttons have a "long click" after 3 seconds. Every control sets its long-click
//     flag to 0, so all that happens is the same packet sent again. It is left out.
//   - Android keeps the button flags in a Java short, so pressing Y (0x8000) also sets every
//     higher flag (paddles, touchpad, misc) in the packet. That bug is not copied.
//
// The controller is a plain state machine. The app turns UITouches into `touch(...)` calls and
// sends the returned events to an `InputSink`. If a real gamepad is also in use, the app should
// combine the two states before sending; Android does that in `sendControllerInputPacket`.

public enum OnScreenTouchPhase: Equatable, Sendable {
    case began, moved, ended, cancelled
}

/// What one touch did.
public struct OnScreenResponse: Equatable, Sendable {
    /// Input to send, in order
    public var events: [InputEvent]
    /// True if a control has this touch. Touches that no control has go to the touch-mode handler.
    public var captured: Bool
}

public final class OnScreenController {
    /// Android's `AnalogStick.timeoutDoubleClick`: two taps on a stick closer than this click it.
    public static let doubleTapWindow: TimeInterval = 0.350
    /// Android's `AnalogStick.timeoutDeadzone`: a finger that stays this long on a stick leaves
    /// the stick's inner dead circle behind, so small movements count.
    public static let deadCircleHold: TimeInterval = 0.150
    /// When Android sends the state again (the GFE workaround).
    public static let retransmitDelays: [TimeInterval] = [0.025, 0.050, 0.075]

    public let layout: OnScreenLayout
    public let screen: OnScreenSize
    public let controllerNumber: Int
    public var activeMask: Int
    public var repeatsLikeAndroid: Bool

    /// The state the on-screen controller has now.
    public private(set) var state: ControllerState
    /// The ids of the touches that controls hold now.
    public var capturedTouchIDs: Set<Int> { Set(owners.keys).union(inert) }
    /// When `tick` has something to send, if `repeatsLikeAndroid` is on.
    public var nextDeadline: TimeInterval? { retransmits.min() }

    private enum StickState { case noMovement, movedInDeadZone, movedActive }

    private struct Node {
        var element: OnScreenElement
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var pressed = false
        var movingButton: Int?
        // sticks
        var stickState = StickState.noMovement
        var doubleClick = false
        var lastClickMs: Int?
        var radiusComplete: Float = 0
        var radiusDeadZone: Float = 0
        var radiusStick: Float = 0
        var angle = 0.0
        var movementRadius = 0.0

        var rect: OnScreenRect {
            OnScreenRect(x: Double(x), y: Double(y), width: Double(width), height: Double(height))
        }

        var isDigitalButton: Bool {
            switch element.kind {
            case .button, .trigger: return true
            default: return false
            }
        }
    }

    private var nodes: [Node] = []
    /// touch id to the node it holds
    private var owners: [Int: Int] = [:]
    /// touch ids on a control that already has a finger: held, but they do nothing
    private var inert: Set<Int> = []
    private var lastSent: ControllerState
    private var retransmits: [TimeInterval] = []
    private var currentTime: TimeInterval = 0

    public init(layout: OnScreenLayout, screen: OnScreenSize, controllerNumber: Int = 0, activeMask: Int = 1,
                repeatsLikeAndroid: Bool = false) {
        self.layout = layout
        self.screen = screen
        self.controllerNumber = controllerNumber
        self.activeMask = activeMask
        self.repeatsLikeAndroid = repeatsLikeAndroid
        let idle = ControllerState(number: controllerNumber, activeMask: activeMask)
        state = idle
        lastSent = idle

        // Android's view sizes are whole pixels
        let strokeWidth = Int(Float(Int(screen.height)) * 0.004)
        for entry in layout.resolved(in: screen) {
            var node = Node(element: entry.element, x: Int(entry.rect.x.rounded()), y: Int(entry.rect.y.rounded()),
                            width: Int(entry.rect.width.rounded()), height: Int(entry.rect.height.rounded()))
            if case .stick = entry.element.kind {
                // AnalogStick.onSizeChanged: the radii come from half of the shorter side, cut
                // down to whole pixels, then taken as a percentage in floats
                let half = Float(min(node.width, node.height) / 2)
                node.radiusComplete = half / 100 * 100 - Float(2 * strokeWidth)
                node.radiusDeadZone = half / 100 * 30
                node.radiusStick = half / 100 * 20
            }
            nodes.append(node)
        }
    }

    // MARK: - Touches

    /// One touch event. `now` is in seconds on any clock that only goes forward.
    @discardableResult
    public func touch(id: Int, at point: OnScreenPoint, phase: OnScreenTouchPhase, now: TimeInterval) -> OnScreenResponse {
        currentTime = now
        var events: [InputEvent] = []
        let ms = Int((now * 1000).rounded())
        var captured = false

        switch phase {
        case .began:
            if owners[id] != nil || inert.contains(id) {
                captured = true
                break
            }
            // Controls on top are asked first. A stick can say no and pass the touch down.
            for index in nodes.indices.reversed() where nodes[index].rect.contains(point) {
                if owners.values.contains(index) {
                    inert.insert(id)
                    captured = true
                    break
                }
                if down(index, point, ms, &events) {
                    owners[id] = index
                    captured = true
                    break
                }
            }
        case .moved:
            if let index = owners[id] {
                move(index, point, ms, &events)
                captured = true
            } else {
                captured = inert.contains(id)
            }
        case .ended, .cancelled:
            if let index = owners.removeValue(forKey: id) {
                up(index, point, ms, &events)
                captured = true
            } else {
                captured = inert.remove(id) != nil
            }
        }
        return OnScreenResponse(events: events, captured: captured)
    }

    /// Lets go of everything, as when the app goes to the background or the controls are hidden.
    public func cancelAll(now: TimeInterval) -> [InputEvent] {
        var events: [InputEvent] = []
        currentTime = now
        for (_, index) in owners.sorted(by: { $0.key < $1.key }) {
            let node = nodes[index]
            up(index, OnScreenPoint(x: Double(node.x), y: Double(node.y)), Int((now * 1000).rounded()), &events)
        }
        owners = [:]
        inert = []
        return events
    }

    /// Sends the state again when Android would (only with `repeatsLikeAndroid`).
    public func tick(now: TimeInterval) -> [InputEvent] {
        var events: [InputEvent] = []
        for deadline in retransmits.sorted() where deadline <= now {
            events.append(.controller(state))
        }
        retransmits.removeAll { $0 <= now }
        return events
    }

    // MARK: - Sending

    private func send(_ events: inout [InputEvent]) {
        if repeatsLikeAndroid {
            // Another input before the retransmits cancels them
            events.append(.controller(state))
            retransmits = Self.retransmitDelays.map { currentTime + $0 }
        } else if state != lastSent {
            events.append(.controller(state))
        }
        lastSent = state
    }

    private func setFlag(_ flag: Int, _ on: Bool) {
        if on {
            state.buttons |= flag
        } else {
            state.buttons &= ~flag
        }
    }

    // MARK: - Dispatch

    private func local(_ point: OnScreenPoint, _ node: Node) -> (x: Float, y: Float) {
        (Float(point.x - Double(node.x)), Float(point.y - Double(node.y)))
    }

    /// Returns false if the control doesn't want the touch (only a stick says that).
    private func down(_ index: Int, _ point: OnScreenPoint, _ ms: Int, _ events: inout [InputEvent]) -> Bool {
        switch nodes[index].element.kind {
        case .button, .trigger:
            nodes[index].movingButton = nil
            nodes[index].pressed = true
            click(index, &events)
            return true
        case .dpad:
            padDirection(index, point, &events)
            return true
        case .stick:
            return stickTouch(index, point, .began, ms, &events)
        }
    }

    private func move(_ index: Int, _ point: OnScreenPoint, _ ms: Int, _ events: inout [InputEvent]) {
        switch nodes[index].element.kind {
        case .button, .trigger:
            checkMovementForAllButtons(point, moving: index, &events)
        case .dpad:
            padDirection(index, point, &events)
        case .stick:
            _ = stickTouch(index, point, .moved, ms, &events)
        }
    }

    private func up(_ index: Int, _ point: OnScreenPoint, _ ms: Int, _ events: inout [InputEvent]) {
        switch nodes[index].element.kind {
        case .button, .trigger:
            nodes[index].pressed = false
            release(index, &events)
            checkMovementForAllButtons(point, moving: index, &events)
        case .dpad:
            setPadFlags(0, &events)
        case .stick:
            _ = stickTouch(index, point, .ended, ms, &events)
        }
    }

    // MARK: - Buttons and triggers

    private func click(_ index: Int, _ events: inout [InputEvent]) {
        let element = nodes[index].element
        switch element.kind {
        case .trigger(let left):
            if left { state.leftTrigger = 255 } else { state.rightTrigger = 255 }
        default:
            setFlag(element.flag, true)
        }
        send(&events)
    }

    private func release(_ index: Int, _ events: inout [InputEvent]) {
        let element = nodes[index].element
        switch element.kind {
        case .trigger(let left):
            if left { state.leftTrigger = 0 } else { state.rightTrigger = 0 }
        default:
            setFlag(element.flag, false)
        }
        send(&events)
    }

    /// `DigitalButton.checkMovementForAllButtons`: a moving finger presses the buttons it is over
    /// and lets go of the ones it has left, if they are in the same layer.
    private func checkMovementForAllButtons(_ point: OnScreenPoint, moving: Int, _ events: inout [InputEvent]) {
        for index in nodes.indices where index != moving && nodes[index].isDigitalButton {
            checkMovement(index, point, moving: moving, &events)
        }
    }

    private func checkMovement(_ index: Int, _ point: OnScreenPoint, moving: Int, _ events: inout [InputEvent]) {
        guard nodes[moving].element.layer == nodes[index].element.layer else { return }
        let wasPressed = nodes[index].pressed
        let node = nodes[index]
        let inRange = Double(node.x) < point.x && Double(node.x + node.width) > point.x
            && Double(node.y) < point.y && Double(node.y + node.height) > point.y

        if (node.movingButton == nil || node.movingButton == moving) && inRange {
            if node.pressed != nodes[moving].pressed {
                nodes[index].pressed = nodes[moving].pressed
            }
        } else if node.movingButton == moving {
            nodes[index].pressed = false
        }

        if wasPressed != nodes[index].pressed {
            if nodes[index].pressed {
                nodes[index].movingButton = moving
                click(index, &events)
            } else {
                nodes[index].movingButton = nil
                release(index, &events)
            }
        }
    }

    // MARK: - D-pad

    private func padDirection(_ index: Int, _ point: OnScreenPoint, _ events: inout [InputEvent]) {
        let node = nodes[index]
        let position = local(point, node)
        let width = Float(node.width)
        let height = Float(node.height)
        var flags = 0
        if position.x < width / 100 * 33 { flags |= GamepadButton.left }
        if position.x > width / 100 * 66 { flags |= GamepadButton.right }
        if position.y > height / 100 * 66 { flags |= GamepadButton.down }
        if position.y < height / 100 * 33 { flags |= GamepadButton.up }
        setPadFlags(flags, &events)
    }

    private func setPadFlags(_ flags: Int, _ events: inout [InputEvent]) {
        let all = GamepadButton.left | GamepadButton.right | GamepadButton.up | GamepadButton.down
        state.buttons = (state.buttons & ~all) | flags
        send(&events)
    }

    // MARK: - Sticks

    private static func movementRadius(_ x: Float, _ y: Float) -> Double {
        Double(x * x + y * y).squareRoot()
    }

    /// `AnalogStick.getAngle`, in radians: 0 for a finger straight above the centre, a quarter
    /// turn (pi/2) for left, pi for below and 3pi/2 for right. Android returns the opposite
    /// angle when the finger is exactly above or below the centre; here it is the right one.
    private static func angle(_ wayX: Float, _ wayY: Float) -> Double {
        if wayX == 0 {
            return wayY > 0 ? Double.pi : 0
        }
        if wayY == 0 {
            return wayX > 0 ? Double.pi * 3 / 2 : Double.pi / 2
        }
        if wayX > 0 {
            if wayY < 0 {
                return 3 * Double.pi / 2 + atan(Double(-wayY / wayX))
            }
            return Double.pi + atan(Double(wayX / wayY))
        }
        if wayY > 0 {
            return Double.pi / 2 + atan(Double(wayY / -wayX))
        }
        return atan(Double(-wayX / -wayY))
    }

    /// `AnalogStick.onElementTouchEvent`. Returns false when the touch isn't on the stick's circle.
    private func stickTouch(_ index: Int, _ point: OnScreenPoint, _ phase: OnScreenTouchPhase, _ ms: Int,
                            _ events: inout [InputEvent]) -> Bool {
        var node = nodes[index]
        let left: Bool
        if case .stick(let isLeft) = node.element.kind { left = isLeft } else { return false }

        let position = local(point, node)
        let relativeX = position.x - Float(node.width / 2)
        let relativeY = position.y - Float(node.height / 2)
        node.movementRadius = Self.movementRadius(relativeX, relativeY)
        node.angle = Self.angle(relativeX, relativeY)

        // Outside the circle, and not already held: pass the touch on
        if node.movementRadius > Double(node.radiusComplete) && !node.pressed {
            return false
        }
        // Chop the radius at the edge, where the stick is at full deflection
        let reach = node.radiusComplete - node.radiusStick
        if node.movementRadius > Double(reach) {
            node.movementRadius = Double(reach)
        }

        switch phase {
        case .began:
            node.stickState = .movedInDeadZone
            let lastWasSingle = !node.doubleClick
            if lastWasSingle, let last = node.lastClickMs, ms - last <= Int(Self.doubleTapWindow * 1000) {
                node.doubleClick = true
                stickClick(left: left, on: true, &events)
            } else {
                node.doubleClick = false
            }
            node.lastClickMs = ms
            node.pressed = true
        case .ended, .cancelled:
            node.pressed = false
        case .moved:
            break
        }

        if node.pressed {
            // Stay active once active, so the stick doesn't snap back into the dead circle. A
            // finger that has stayed long enough is active too, for precise movement.
            let last = node.lastClickMs ?? ms
            let held = ms - last > Int(Self.deadCircleHold * 1000)
            node.stickState = (node.stickState == .movedActive || held || node.movementRadius > Double(node.radiusDeadZone))
                ? .movedActive : .movedInDeadZone
            nodes[index] = node
            if node.stickState == .movedActive {
                let complete = reach
                let correlatedY = Float(sin(Double.pi / 2 - node.angle) * node.movementRadius)
                let correlatedX = Float(cos(Double.pi / 2 - node.angle) * node.movementRadius)
                stickMoved(left: left, x: -correlatedX / complete, y: correlatedY / complete, &events)
            }
        } else {
            node.stickState = .noMovement
            nodes[index] = node
            // Let go of the click, and put the stick back in the middle
            stickClick(left: left, on: false, &events)
            stickMoved(left: left, x: 0, y: 0, &events)
        }
        return true
    }

    private func stickClick(left: Bool, on: Bool, _ events: inout [InputEvent]) {
        setFlag(left ? GamepadButton.leftStick : GamepadButton.rightStick, on)
        send(&events)
    }

    /// LeftAnalogStick.onMovement: a fraction of full deflection (-1...1, y up) times 0x7FFE.
    private func stickMoved(left: Bool, x: Float, y: Float, _ events: inout [InputEvent]) {
        let scaledX = Int(x * GamepadMath.stickScale)
        let scaledY = Int(y * GamepadMath.stickScale)
        if left {
            state.leftX = scaledX
            state.leftY = scaledY
        } else {
            state.rightX = scaledX
            state.rightY = scaledY
        }
        send(&events)
    }
}
