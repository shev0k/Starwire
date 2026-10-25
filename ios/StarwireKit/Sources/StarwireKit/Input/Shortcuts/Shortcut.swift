import Foundation

// Ported from Starwire for Android (GPL-3.0): OverlayMenuView.java (the Shortcut class and the
// tile that sends it) and Game.java (sendKeys and getModifierForKey). The set and order of the
// built-in shortcuts come from Artemide's "Send keys" menu.

/// Some input events and how long to wait before sending them.
public struct ShortcutStep: Equatable, Sendable {
    /// Wait this long after the step before it (or after the start, for the first step).
    public var pauseBeforeMilliseconds: Int
    public var events: [InputEvent]

    public init(pauseBeforeMilliseconds: Int = 0, events: [InputEvent]) {
        self.pauseBeforeMilliseconds = pauseBeforeMilliseconds
        self.events = events
    }
}

/// A key combination for the stream menu: Windows virtual-key codes, pressed in order and
/// released in reverse order.
public struct Shortcut: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Windows virtual-key codes, in the order they are pressed.
    public var keys: [Int]

    /// Android waits 25 ms between the last key going down and the first one coming up.
    public static let releaseDelayMilliseconds = 25

    public init(id: String, name: String, keys: [Int]) {
        self.id = id
        self.name = name
        self.keys = keys
    }

    /// The modifier flag a key adds to the keys after it. Only the left Shift, Ctrl and Alt and
    /// the left Windows key count, as on Android: the general `VK_SHIFT` (0x10), `VK_CONTROL`
    /// (0x11) and `VK_MENU` (0x12) add nothing.
    public static func modifierFlag(forKey key: Int) -> Int {
        switch key {
        case 0xA0: return KeyModifier.shift
        case 0xA2: return KeyModifier.ctrl
        case 0xA4: return KeyModifier.alt
        case 0x5B: return KeyModifier.meta
        default: return 0
        }
    }

    /// What Android sends: every key down in order, each carrying the modifiers pressed before it.
    /// Then, 25 ms later, every key up in reverse order, each carrying the modifiers still held
    /// after the key itself is let go.
    public func steps() -> [ShortcutStep] {
        var modifiers = 0
        var downs: [InputEvent] = []
        for key in keys {
            downs.append(.key(code: key, down: true, modifiers: modifiers))
            modifiers |= Shortcut.modifierFlag(forKey: key)
        }
        var ups: [InputEvent] = []
        for key in keys.reversed() {
            modifiers &= ~Shortcut.modifierFlag(forKey: key)
            ups.append(.key(code: key, down: false, modifiers: modifiers))
        }
        return [ShortcutStep(events: downs),
                ShortcutStep(pauseBeforeMilliseconds: Shortcut.releaseDelayMilliseconds, events: ups)]
    }

    /// All the events in order, without the pause between the presses and the releases.
    public func events() -> [InputEvent] {
        steps().flatMap(\.events)
    }
}

extension Array where Element == ShortcutStep {
    /// Sends the steps in order. `wait` is asked to pause for each step's delay before the
    /// step goes out; in the app it schedules the rest, in tests it just records the delay.
    public func send(to sink: InputSink, wait: @escaping (Int, @escaping () -> Void) -> Void) {
        guard let step = first else { return }
        let rest = Array(dropFirst())
        let sendStep = {
            for event in step.events {
                sink.send(event)
            }
            rest.send(to: sink, wait: wait)
        }
        if step.pauseBeforeMilliseconds > 0 {
            wait(step.pauseBeforeMilliseconds, sendStep)
        } else {
            sendStep()
        }
    }
}
