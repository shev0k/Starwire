import Foundation

// Ported from Starwire for Android (GPL-3.0): KeyBoardLayoutController.java (the touch listener
// and the long press lock) and Game.sendFullKeyboardKey (the modifier flags on each key packet).
// The keyboard comes from Artemide.

/// The modifier behaviour of the on-screen full keyboard, as Starwire for Android does it.
///
/// Every touch on a key sends a key down, and lifting the finger sends a key up. Shift, Ctrl, Alt
/// and Win are special only when the "sticky modifier keys" setting is on (it is by default):
///
/// - A short tap sends down and up at once, as for any other key. It does not stay latched.
/// - Holding the key for 0.3 seconds locks it. The key up is held back when the finger lifts, so
///   the PC sees the modifier as still down.
/// - While locked, every key packet carries the modifier in its flags.
/// - Touching a locked key again unlocks it: nothing is sent on touch, and the key up is sent
///   when the finger lifts.
///
/// With the setting off, modifiers are plain keys: hold one with one finger while tapping another
/// with a second finger. Android never releases a lock by itself, not even when the keyboard is
/// hidden.
///
/// The modifier flags on a packet follow Android's `sendFullKeyboardKey`: a modifier's own down
/// adds its flag before the packet is sent, and its up removes the flag before it is sent. So
/// Shift down carries Shift and Shift up carries none.
///
/// Time is passed in, never read. Call `tick(now:)` when `nextDeadline` has passed; `press` and
/// `release` also settle anything already due, so a late timer cannot reorder events.
public struct StickyModifiers: Equatable, Sendable {
    /// How long a modifier must be held to lock (Android's `LONG_CLICK_TIMEOUT_MS`).
    public static let lockDelay: TimeInterval = 0.3

    /// What a call produced.
    public struct Output: Equatable, Sendable {
        /// Packets to send to the PC, in order.
        public var events: [InputEvent]
        /// True when Android would give haptic feedback for this call. Only set when the
        /// "keyboard vibrate" setting is on.
        public var shouldVibrate: Bool
        /// True when Android would show the key's popup above it (a non-special key going down).
        public var showsPopup: Bool

        public init(events: [InputEvent] = [], shouldVibrate: Bool = false, showsPopup: Bool = false) {
            self.events = events
            self.shouldVibrate = shouldVibrate
            self.showsPopup = showsPopup
        }
    }

    public let layout: FullKeyboardLayout
    /// The "sticky modifier keys" setting (`checkbox_sticky_modifier_keys`, default true).
    public let sticky: Bool
    /// The "keyboard vibrate" setting (`checkbox_keyboard_vibrate`, default true).
    public let vibrate: Bool

    /// Modifier keys that are down and waiting to lock, with the time they lock at.
    private var lockDeadlines: [String: TimeInterval] = [:]
    private var locked: Set<String> = []
    /// `KeyModifier` flags currently sent with packets.
    public private(set) var activeModifiers = 0

    public init(layout: FullKeyboardLayout = .android, sticky: Bool = true, vibrate: Bool = true) {
        self.layout = layout
        self.sticky = sticky
        self.vibrate = vibrate
    }

    /// Ids of the modifier keys that are locked down, for drawing them as on.
    public var lockedKeyIDs: Set<String> { locked }

    /// `KeyModifier` flags of the locked keys.
    public var lockedModifiers: Int {
        locked.reduce(0) { $0 | (layout.key(id: $1)?.modifierMask ?? 0) }
    }

    /// When `tick(now:)` next has something to do, or nil.
    public var nextDeadline: TimeInterval? { lockDeadlines.values.min() }

    /// A finger went down on a key.
    public mutating func press(keyID: String, now: TimeInterval) -> Output {
        var output = settle(now: now)
        guard let key = layout.key(id: keyID), key.kind != .hide else { return output }
        let isSticky = sticky && key.kind == .modifier

        if isSticky && locked.contains(keyID) {
            // Touching a locked key unlocks it; the key up goes out when the finger lifts
            locked.remove(keyID)
            return output
        }

        let flags = flagsAfter(key: key, down: true)
        output.events.append(.key(code: key.virtualKey, down: true, modifiers: flags))
        output.showsPopup = !key.isSpecial
        output.shouldVibrate = vibrate
        if isSticky { lockDeadlines[keyID] = now + Self.lockDelay }
        return output
    }

    /// A finger came up from a key (or the touch was cancelled).
    public mutating func release(keyID: String, now: TimeInterval) -> Output {
        var output = settle(now: now)
        guard let key = layout.key(id: keyID), key.kind != .hide else { return output }
        let isSticky = sticky && key.kind == .modifier

        if isSticky && locked.contains(keyID) {
            // The lock holds: the PC keeps seeing the modifier down
            return output
        }
        if isSticky { lockDeadlines[keyID] = nil }

        let flags = flagsAfter(key: key, down: false)
        output.events.append(.key(code: key.virtualKey, down: false, modifiers: flags))
        output.shouldVibrate = vibrate
        return output
    }

    /// Locks every modifier whose hold time is up. Call it when `nextDeadline` has passed.
    public mutating func tick(now: TimeInterval) -> Output {
        settle(now: now)
    }

    private mutating func settle(now: TimeInterval) -> Output {
        var output = Output()
        for (keyID, deadline) in lockDeadlines.sorted(by: { ($0.value, $0.key) < ($1.value, $1.key) }) where now >= deadline {
            lockDeadlines[keyID] = nil
            locked.insert(keyID)
            // Android gives a tap of feedback when the lock happens
            if vibrate { output.shouldVibrate = true }
        }
        return output
    }

    /// Updates the active modifier flags for a key going down or up and returns the flags to send.
    private mutating func flagsAfter(key: FullKeyboardKey, down: Bool) -> Int {
        if down {
            activeModifiers |= key.modifierMask
        } else {
            activeModifiers &= ~key.modifierMask
        }
        return activeModifiers
    }
}
