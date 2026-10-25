import Foundation

/// Counts what a stream has sent to the PC, by kind, and remembers the last packet, for the
/// statistics overlay's "Input:" line. Thread safe.
public final class InputTally: @unchecked Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case touch, pen, mouse, buttons, scroll, keys, text, controller, motion
    }

    private let lock = NSLock()
    private var counts: [Kind: Int] = [:]
    private var last: InputEvent?

    public init() {}

    public static func kind(of event: InputEvent) -> Kind {
        switch event {
        case .touch: return .touch
        case .pen: return .pen
        case .mouseMove, .mousePosition, .mouseMoveAsPosition: return .mouse
        case .mouseButton: return .buttons
        case .scroll, .hScroll: return .scroll
        case .key: return .keys
        case .text: return .text
        case .controller, .controllerArrival, .controllerBattery, .controllerTouch: return .controller
        case .controllerMotion: return .motion
        }
    }

    public func record(_ event: InputEvent) {
        lock.lock()
        counts[Self.kind(of: event), default: 0] += 1
        last = event
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        counts.removeAll()
        last = nil
        lock.unlock()
    }

    public func count(_ kind: Kind) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[kind] ?? 0
    }

    /// "Input: touch 0, pen 0, mouse 12, buttons 4, scroll 0, keys 8, text 1, controller 0, motion 0; last key 0x41 up"
    public var line: String {
        lock.lock()
        let parts = Kind.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }
        let lastEvent = last
        lock.unlock()
        return "Input: " + parts.joined(separator: ", ") + "; last " + (lastEvent.map(Self.describe) ?? "none")
    }

    /// A short description of one packet.
    public static func describe(_ event: InputEvent) -> String {
        switch event {
        case .mouseMove(let dx, let dy): return "move \(dx),\(dy)"
        case .mousePosition(let x, let y, _, _): return "position \(x),\(y)"
        case .mouseMoveAsPosition(let dx, let dy, _, _): return "move as position \(dx),\(dy)"
        case .mouseButton(let button, let down): return "button \(button) \(down ? "down" : "up")"
        case .scroll(let amount): return "scroll \(amount)"
        case .hScroll(let amount): return "hscroll \(amount)"
        case .key(let code, let down, let modifiers, _):
            return String(format: "key 0x%02X %@", code, down ? "down" : "up") + (modifiers != 0 ? " mods \(modifiers)" : "")
        case .text(let text): return "text \(text.count) characters"
        case .touch(let id, let phase, _, _, _, _, _, _): return "touch \(id) \(phase)"
        case .pen(let phase, _, _, _, _, let pressure, _, _): return String(format: "pen %@ %.2f", "\(phase)", pressure)
        case .controller(let state): return String(format: "controller %d buttons 0x%X", state.number, state.buttons)
        case .controllerArrival(let number, _, let type, _, let capabilities):
            return String(format: "arrival %d %@ caps 0x%X", number, "\(type)", capabilities)
        case .controllerMotion(let number, let sensor, _, _, _): return "motion \(number) \(sensor)"
        case .controllerBattery(let number, let state, let percent): return "battery \(number) \(state) \(percent)%"
        case .controllerTouch(let number, let phase, _, _, _, _): return "pad \(number) \(phase)"
        }
    }
}
