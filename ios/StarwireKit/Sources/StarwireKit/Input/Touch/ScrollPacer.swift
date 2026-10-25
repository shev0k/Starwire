import Foundation

// Sends scrolling once per display refresh instead of once per touch delivery. Batch 4.5 measured
// touches reaching the app about 108 times a second on the 120 Hz iPad Pro, one scroll packet
// each, and the PC's page then moved in only 74 to 84% of the stream's frames: a frame with no
// delivery is a frame with no movement. Each delivery's scroll is split over two refreshes, half
// now and half at the next, so a refresh that gets no delivery still moves. That costs half a
// refresh (about 4 ms at 120 Hz) on half the movement. Fractions are kept, so nothing is lost.

public final class ScrollPacer {
    /// Split each delivery over two refreshes. Off sends everything at the next refresh.
    public var spread: Bool
    private var pendingV = 0.0, pendingH = 0.0
    private var carryV = 0.0, carryH = 0.0
    private var remainderV = 0.0, remainderH = 0.0

    public init(spread: Bool = true) {
        self.spread = spread
    }

    /// A scroll the touch modes made (high-resolution units, 120 a notch)
    public func add(_ event: InputEvent) -> Bool {
        switch event {
        case .scroll(let amount): pendingV += Double(amount)
        case .hScroll(let amount): pendingH += Double(amount)
        default: return false
        }
        return true
    }

    /// A display refresh: the scroll packets to send now.
    public func tick() -> [InputEvent] {
        let nowV = carryV + (spread ? pendingV / 2 : pendingV)
        let nowH = carryH + (spread ? pendingH / 2 : pendingH)
        carryV = spread ? pendingV / 2 : 0
        carryH = spread ? pendingH / 2 : 0
        pendingV = 0
        pendingH = 0
        remainderV += nowV
        remainderH += nowH
        let v = Int(remainderV.rounded(.towardZero)), h = Int(remainderH.rounded(.towardZero))
        remainderV -= Double(v)
        remainderH -= Double(h)
        var events: [InputEvent] = []
        if v != 0 { events.append(.scroll(amount: v)) }
        if h != 0 { events.append(.hScroll(amount: h)) }
        return events
    }

    /// Sends whatever is held, at once (the stream is ending)
    public func flush() -> [InputEvent] {
        let wasSpread = spread
        spread = false
        pendingV += carryV
        pendingH += carryH
        carryV = 0
        carryH = 0
        defer { spread = wasSpread }
        return tick()
    }
}
