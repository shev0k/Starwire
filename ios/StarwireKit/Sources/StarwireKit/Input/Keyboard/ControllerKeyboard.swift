import Foundation

// A keyboard for a controller, in the manner of the PlayStation 5's: a grid of keys moved over
// with the d-pad or the left stick, A to type the key in focus, L1 for Backspace, R1 for Space,
// L2 for Shift (twice for Caps), R2 for the symbols, Start for Enter, B to close. New for the iOS
// client; Android has none. moonlight-switch's and imoonlight's controller keyboards were looked
// at for the idea, nothing was copied.
//
// Characters go to the PC as key presses where a US keyboard has the key (games and the Windows
// sign-in screen ignore typed text), and as text otherwise.

/// One key of the grid.
public struct ControllerKeyboardKey: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Types a character (`label` lower case; `shiftedLabel` with Shift)
        case character(Character, shifted: Character)
        /// Taps a Windows virtual key
        case key(Int)
        case shift, symbols, space, backspace, enter, close
    }

    public var label: String
    public var kind: Kind
    /// Columns the key covers (the bottom row's wide keys)
    public var span: Int

    public init(_ label: String, _ kind: Kind, span: Int = 1) {
        self.label = label
        self.kind = kind
        self.span = span
    }
}

public final class ControllerKeyboard {
    public enum Page: Equatable, Sendable { case letters, symbols }
    public enum ShiftState: Equatable, Sendable { case off, once, locked }

    public static let columns = 10
    /// The stick must lean this far (of 32767) to move, and come back under the lower value
    public static let stickOn = 16000
    public static let stickOff = 9000
    public static let triggerOn = 128
    /// Holding a direction repeats it after this delay, then at this interval
    public static let repeatDelay: TimeInterval = 0.4
    public static let repeatInterval: TimeInterval = 0.08
    /// Two Shift presses this close lock it (Caps)
    public static let shiftLockWindow: TimeInterval = 0.4
    /// Characters kept for the line above the keys that shows what was typed
    public static let previewLength = 40

    public private(set) var page: Page = .letters
    public private(set) var shift: ShiftState = .off
    /// Row and column of the key in focus
    public private(set) var focus = (row: 1, column: 0)
    /// What was typed, the last `previewLength` characters
    public private(set) var preview = ""
    public private(set) var isOpen = true

    private var buttons = 0
    private var leftTrigger = false
    private var rightTrigger = false
    private var stickDirection: Direction?
    private var heldDirection: (direction: Direction, next: TimeInterval)?
    private var lastShift: TimeInterval = -.infinity

    /// `holding`: buttons already down when the keyboard opens (the A that chose it), which
    /// count only once they are let go and pressed again.
    public init(holding: Int = 0) {
        buttons = holding
    }

    // MARK: Grid

    public var rows: [[ControllerKeyboardKey]] {
        (page == .letters ? Self.letterRows : Self.symbolRows) + [Self.actionRow]
    }

    static func characters(_ text: String, shifted: String) -> [ControllerKeyboardKey] {
        zip(text, shifted).map { ControllerKeyboardKey(String($0), .character($0, shifted: $1)) }
    }

    static let letterRows: [[ControllerKeyboardKey]] = [
        characters("1234567890", shifted: "!@#$%^&*()"),
        characters("qwertyuiop", shifted: "QWERTYUIOP"),
        characters("asdfghjkl'", shifted: "ASDFGHJKL\""),
        characters("zxcvbnm,.?", shifted: "ZXCVBNM<>/"),
    ]

    static let symbolRows: [[ControllerKeyboardKey]] = [
        characters("!@#$%^&*()", shifted: "!@#$%^&*()"),
        characters("-_=+[]{}\\|", shifted: "-_=+[]{}\\|"),
        characters(";:\"/<>`~,.", shifted: ";:\"/<>`~,."),
        [ControllerKeyboardKey("Esc", .key(0x1B)), ControllerKeyboardKey("Tab", .key(0x09)),
         ControllerKeyboardKey("\u{2190}", .key(0x25)), ControllerKeyboardKey("\u{2193}", .key(0x28)),
         ControllerKeyboardKey("\u{2191}", .key(0x26)), ControllerKeyboardKey("\u{2192}", .key(0x27)),
         ControllerKeyboardKey("Home", .key(0x24)), ControllerKeyboardKey("End", .key(0x23)),
         ControllerKeyboardKey("Del", .key(0x2E)), ControllerKeyboardKey("Win", .key(0x5B))],
    ]

    static let actionRow: [ControllerKeyboardKey] = [
        ControllerKeyboardKey("Shift", .shift, span: 2),
        ControllerKeyboardKey("&123", .symbols, span: 1),
        ControllerKeyboardKey("Space", .space, span: 4),
        ControllerKeyboardKey("Back", .backspace, span: 1),
        ControllerKeyboardKey("Enter", .enter, span: 2),
    ]

    /// The key at a column, counting the bottom row's wide keys as covering their columns.
    public func key(row: Int, column: Int) -> ControllerKeyboardKey {
        rows[row][keyIndex(row: row, column: column)]
    }

    public var focusedKey: ControllerKeyboardKey { key(row: focus.row, column: focus.column) }

    private func keyIndex(row: Int, column: Int) -> Int {
        var start = 0
        for (index, key) in rows[row].enumerated() {
            if column < start + key.span { return index }
            start += key.span
        }
        return rows[row].count - 1
    }

    /// The first column of the key at `column`, so moving along a row skips a wide key at once.
    private func keyStart(row: Int, column: Int) -> Int {
        let index = keyIndex(row: row, column: column)
        return rows[row][..<index].reduce(0) { $0 + $1.span }
    }

    // MARK: Input

    enum Direction { case up, down, left, right }

    /// A controller's new state. Returns the packets for the PC (key presses and text).
    public func handle(_ state: ControllerState, now: TimeInterval) -> [InputEvent] {
        guard isOpen else { return [] }
        var events: [InputEvent] = []
        let pressed = state.buttons & ~buttons
        buttons = state.buttons

        // Directions: the d-pad, or the left stick with some hysteresis
        let dpad: Direction? = state.buttons & GamepadButton.up != 0 ? .up : state.buttons & GamepadButton.down != 0 ? .down
            : state.buttons & GamepadButton.left != 0 ? .left : state.buttons & GamepadButton.right != 0 ? .right : nil
        stickDirection = Self.stickDirection(x: state.leftX, y: state.leftY, current: stickDirection)
        let direction = dpad ?? stickDirection
        if direction != heldDirection?.direction {
            if let direction {
                move(direction)
                heldDirection = (direction, now + Self.repeatDelay)
            } else {
                heldDirection = nil
            }
        }

        if pressed & GamepadButton.a != 0 { events += activate(focusedKey, now: now) }
        if pressed & (GamepadButton.leftBumper | GamepadButton.x) != 0 { events += activate(ControllerKeyboardKey("", .backspace), now: now) }
        if pressed & (GamepadButton.rightBumper | GamepadButton.y) != 0 { events += activate(ControllerKeyboardKey("", .space), now: now) }
        if pressed & GamepadButton.start != 0 { events += activate(ControllerKeyboardKey("", .enter), now: now) }
        if pressed & GamepadButton.b != 0 { isOpen = false }

        let left = state.leftTrigger >= Self.triggerOn
        if left && !leftTrigger { pressShift(now: now) }
        leftTrigger = left
        let right = state.rightTrigger >= Self.triggerOn
        if right && !rightTrigger { togglePage() }
        rightTrigger = right
        return events
    }

    /// When a held direction repeats next
    public var nextDeadline: TimeInterval? { heldDirection?.next }

    /// Repeats a held direction.
    public func tick(now: TimeInterval) {
        guard let held = heldDirection, now >= held.next else { return }
        move(held.direction)
        heldDirection = (held.direction, max(held.next + Self.repeatInterval, now))
    }

    /// Touch: a key was tapped on the screen.
    public func tap(row: Int, column: Int, now: TimeInterval) -> [InputEvent] {
        guard isOpen, row < rows.count else { return [] }
        focus = (row, keyStart(row: row, column: min(max(column, 0), Self.columns - 1)))
        return activate(focusedKey, now: now)
    }

    public func reopen(holding: Int = 0) {
        buttons = holding
        leftTrigger = false
        rightTrigger = false
        isOpen = true
        page = .letters
        shift = .off
        focus = (1, 0)
        heldDirection = nil
        stickDirection = nil
    }

    static func stickDirection(x: Int, y: Int, current: Direction?) -> Direction? {
        let size = max(abs(x), abs(y))
        if current != nil && size > stickOff && size <= stickOn { return current }
        guard size > stickOn else { return nil }
        // Up is positive on the wire
        return abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
    }

    private func move(_ direction: Direction) {
        let rowCount = rows.count
        switch direction {
        case .up: focus.row = (focus.row - 1 + rowCount) % rowCount
        case .down: focus.row = (focus.row + 1) % rowCount
        case .left:
            let start = keyStart(row: focus.row, column: focus.column)
            focus.column = keyStart(row: focus.row, column: (start - 1 + Self.columns) % Self.columns)
        case .right:
            let index = keyIndex(row: focus.row, column: focus.column)
            let end = keyStart(row: focus.row, column: focus.column) + rows[focus.row][index].span
            focus.column = end % Self.columns
        }
        // Moving onto a wide key focuses its start
        if direction == .up || direction == .down {
            focus.column = min(focus.column, Self.columns - 1)
        }
    }

    private func pressShift(now: TimeInterval) {
        switch shift {
        case .off:
            shift = .once
            lastShift = now
        case .once:
            shift = now - lastShift <= Self.shiftLockWindow ? .locked : .off
        case .locked:
            shift = .off
        }
    }

    private func togglePage() {
        page = page == .letters ? .symbols : .letters
    }

    private func activate(_ key: ControllerKeyboardKey, now: TimeInterval) -> [InputEvent] {
        switch key.kind {
        case .character(let lower, let upper):
            let character = shift == .off ? lower : upper
            if shift == .once { shift = .off }
            appendPreview(String(character))
            return KeyCodeMap.keyEvents(for: character) ?? [.text(String(character))]
        case .key(let code):
            return Self.tap(code)
        case .space:
            appendPreview(" ")
            return Self.tap(0x20)
        case .backspace:
            if !preview.isEmpty { preview.removeLast() }
            return Self.tap(0x08)
        case .enter:
            preview = ""
            return Self.tap(0x0D)
        case .shift:
            pressShift(now: now)
            return []
        case .symbols:
            togglePage()
            return []
        case .close:
            isOpen = false
            return []
        }
    }

    private func appendPreview(_ text: String) {
        preview += text
        if preview.count > Self.previewLength {
            preview = String(preview.suffix(Self.previewLength))
        }
    }

    private static func tap(_ code: Int) -> [InputEvent] {
        [.key(code: code, down: true, modifiers: 0), .key(code: code, down: false, modifiers: 0)]
    }
}
