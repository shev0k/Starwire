import Foundation

// Ported from Starwire for Android (GPL-3.0): HostCursorController.java, and from Game.java the
// hostCursorToggle (isLinkUp, send) and isFixHostCursorOffered. Android's Handler is replaced by
// `now`, `nextDeadline` and `tick(now:)`, so tests never wait.

/// The "Hide PC cursor" setting (`hide_cursor_mode`).
public enum HideCursorMode: String, Equatable, Sendable, CaseIterable {
    case never
    /// Hidden while a finger is down.
    case touching
    case always

    /// Reads the setting's value as Android does: anything but "touching" or "always" is never.
    public init(settingValue: String) {
        self = HideCursorMode(rawValue: settingValue) ?? .never
    }
}

/// Sends the host's cursor toggle.
public protocol HostCursorToggle: AnyObject {
    /// False when there is no stream to send it on, or the host has no such toggle (Android
    /// says no for GeForce Experience, where the keys would only reach the game).
    var isLinkUp: Bool { get }
    func send()
}

/// A toggle that presses the keys on an `InputSink`.
public final class KeyHostCursorToggle: HostCursorToggle {
    private let sink: InputSink
    private let linkUp: () -> Bool

    public init(sink: InputSink, isLinkUp: @escaping () -> Bool) {
        self.sink = sink
        self.linkUp = isLinkUp
    }

    public var isLinkUp: Bool { linkUp() }

    public func send() {
        for event in HostCursorController.toggleEvents {
            sink.send(event)
        }
    }
}

/// What `onStreamStarted` did about a cursor an earlier stream left hidden.
public enum HostCursorReconcile: Equatable, Sendable {
    case nothing
    /// The toggle was sent to show it again.
    case shown
    /// This stream hides it anyway, so it is kept hidden without sending anything.
    case adopted
    /// It needed showing but there was no link to send on. The record stays.
    case failed
}

/// "Hide PC cursor": hides and shows the PC's cursor with the host's Ctrl+Alt+Shift+N toggle.
/// The toggle is one switch for the whole host and the host can't say which way it is set, so
/// Starwire keeps track itself. What it hid is written down per PC (`HostCursorLedger`) before
/// the toggle goes out, so a cursor left hidden by a crash, a force-quit or a dropped connection
/// is put right the next time Starwire connects to that PC.
///
/// Call `tick(now:)` when `nextDeadline` has passed. Time is in seconds on any steady clock.
public final class HostCursorController {
    /// Ctrl+Alt+Shift+N: the keys go down in that order, each carrying the modifiers before it,
    /// and come up in reverse order, all in one go, so the modifiers are up again before any
    /// touch or click that follows reaches the PC. Key codes are left Ctrl 0xA2, left Alt 0xA4,
    /// left Shift 0xA0 and N 0x4E.
    public static let toggleEvents: [InputEvent] = {
        let keys = [(code: 0xA2, flag: KeyModifier.ctrl), (code: 0xA4, flag: KeyModifier.alt),
                    (code: 0xA0, flag: KeyModifier.shift), (code: 0x4E, flag: 0)]
        var events: [InputEvent] = []
        var modifiers = 0
        for key in keys {
            events.append(.key(code: key.code, down: true, modifiers: modifiers))
            modifiers |= key.flag
        }
        for key in keys.reversed() {
            modifiers &= ~key.flag
            events.append(.key(code: key.code, down: false, modifiers: modifiers))
        }
        return events
    }()

    /// Showing it again waits this long (seconds) after the last finger lifts, so quick taps
    /// don't make it flicker or send the toggle twice in a row.
    public static let showAfterTouchDelay: TimeInterval = 0.3

    public let mode: HideCursorMode
    private let ledger: HostCursorLedger
    private let toggle: HostCursorToggle
    private let appID: Int

    private var believedHidden = false
    private var reconciled = false
    private var stopped = false
    private var showAt: TimeInterval?

    public init(mode: HideCursorMode, ledger: HostCursorLedger, toggle: HostCursorToggle, appID: Int) {
        self.mode = mode
        self.ledger = ledger
        self.toggle = toggle
        self.appID = appID
    }

    /// Whether Starwire has toggled the cursor off and not back on.
    public var isBelievedHidden: Bool { believedHidden }

    /// Whether this stream turned the cursor back on after an earlier one left it hidden.
    public var reconciledThisStream: Bool { reconciled }

    /// When `tick(now:)` next has something to do, or nil.
    public var nextDeadline: TimeInterval? { showAt }

    /// Whether the stream menu should offer "Fix PC cursor": where hiding is used, and where a
    /// cursor left hidden by an earlier stream was just turned back on (that guess can be wrong
    /// if the host's software restarted). Not on a host without the toggle.
    public func isFixOffered(hostHasToggle: Bool) -> Bool {
        hostHasToggle && (mode != .never || reconciled)
    }

    /// The stream is up. If an earlier stream to this PC left the cursor hidden, put that right
    /// for this stream's setting; otherwise hide it now for "Always".
    @discardableResult
    public func onStreamStarted(resumedSession: Bool) -> HostCursorReconcile {
        if stopped {
            return .nothing
        }
        guard ledger.read() != nil else {
            if mode == .always {
                hide(reason: "always")
            }
            return .nothing
        }

        // Nothing on the PC says which way the cursor is now. It would be showing again if the
        // host's software restarted or another client pressed the toggle, but usually neither
        // has happened, so take it as still hidden.
        if mode == .always {
            believedHidden = true
            ledger.markHidden(appID: appID, reason: "adopted")
            return .adopted
        }
        if !toggle.isLinkUp {
            return .failed
        }
        toggle.send()
        reconciled = true
        ledger.markShown()
        return .shown
    }

    /// First finger down, for "While touching".
    public func onFingerDown(now: TimeInterval) {
        guard mode == .touching, !stopped else { return }
        showAt = nil
        hide(reason: "touch")
    }

    /// Last finger up, or the touch was cancelled.
    public func onFingersUp(now: TimeInterval) {
        guard mode == .touching, !stopped else { return }
        showAt = now + Self.showAfterTouchDelay
    }

    /// Does what is due at `now`: shows the cursor once the pause after the last finger is over.
    public func tick(now: TimeInterval) {
        guard let due = showAt, now >= due else { return }
        showAt = nil
        if show() {
            ledger.markShown()
        }
    }

    /// The stream is ending while the link still works: show the cursor if Starwire hid it.
    /// Returns true when the toggle was just sent. The host throws away input it hasn't handled
    /// yet when the session stops, so the caller should wait a moment before stopping the
    /// connection, then call `onShowFlushed()`.
    public func onStopping() -> Bool {
        if stopped {
            return false
        }
        stopped = true
        showAt = nil

        if !believedHidden {
            return false
        }
        if !show() {
            // Keep the record, so the next connection to this PC shows it
            believedHidden = false
            ledger.setReason("stopped without a link")
            return false
        }
        return true
    }

    /// The show toggle from `onStopping()` has had time to arrive: clear the record.
    public func onShowFlushed() {
        ledger.markShown()
    }

    /// The connection dropped or the PC ended it. The toggle can't get through any more, so the
    /// record stays and the next connection to this PC shows the cursor.
    public func onConnectionLost(errorCode: Int) {
        if stopped {
            return
        }
        stopped = true
        showAt = nil

        if believedHidden {
            believedHidden = false
            ledger.setReason("terminated:\(errorCode)")
        }
    }

    /// "Fix PC cursor": the PC's cursor is the wrong way round, so send the toggle once. What
    /// Starwire believes stays the same, since the toggle brings the PC back in line with it.
    /// Returns false when there was no link to send it on.
    public func onManualFix() -> Bool {
        if stopped || !toggle.isLinkUp {
            return false
        }
        toggle.send()
        return true
    }

    private func hide(reason: String) {
        if believedHidden || !toggle.isLinkUp {
            return
        }
        // Written first, so it is there even if the app dies right after the toggle goes out
        ledger.markHidden(appID: appID, reason: reason)
        toggle.send()
        believedHidden = true
    }

    // Sends the show toggle; the caller removes the record once it is sure it got there
    private func show() -> Bool {
        if !believedHidden || !toggle.isLinkUp {
            return false
        }
        toggle.send()
        believedHidden = false
        return true
    }
}
