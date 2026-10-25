import Foundation

/// Moving a highlight between a screen's buttons with a controller's d-pad or stick, the way TV
/// apps do. iOS has no public way to move its own focus in a direction, so the app keeps its own
/// highlight: every button reports its frame, and this picks the next one.
///
/// The rule: of the targets whose centre lies in the pressed direction, the one with the smallest
/// distance along that direction plus twice the sideways offset, so the button straight ahead wins
/// over a closer one off to the side. Buttons in the same row or column as the current one count
/// as straight ahead when their frames overlap on the other axis.
public enum SpatialNavigation {
    public enum Direction: Equatable, Sendable {
        case up, down, left, right
    }

    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }

    /// The target to move to from `current` in `direction`, or nil when there's none that way.
    /// `targets` are ids with frames in one coordinate space. Ties go to the first in `targets`.
    public static func next<ID: Equatable>(from current: ID?, direction: Direction,
                                           targets: [(id: ID, frame: Rect)]) -> ID? {
        guard let current, let from = targets.first(where: { $0.id == current })?.frame else {
            // Nothing highlighted yet: start at the top left
            return targets.min { a, b in
                (a.frame.y, a.frame.x) < (b.frame.y, b.frame.x)
            }?.id
        }
        var best: (id: ID, score: Double)?
        for target in targets where target.id != current {
            guard let score = score(from: from, to: target.frame, direction: direction) else { continue }
            if best == nil || score < best!.score {
                best = (target.id, score)
            }
        }
        return best?.id
    }

    /// Lower is better; nil when `to` isn't in that direction at all.
    static func score(from: Rect, to: Rect, direction: Direction) -> Double? {
        let along: Double
        let sideways: Double
        switch direction {
        case .up:
            guard to.midY < from.midY - 0.5, to.y < from.y + 0.5 else { return nil }
            along = from.y - to.maxY
            sideways = overlap(from.x, from.maxX, to.x, to.maxX) ? 0 : abs(to.midX - from.midX)
        case .down:
            guard to.midY > from.midY + 0.5, to.maxY > from.maxY - 0.5 else { return nil }
            along = to.y - from.maxY
            sideways = overlap(from.x, from.maxX, to.x, to.maxX) ? 0 : abs(to.midX - from.midX)
        case .left:
            guard to.midX < from.midX - 0.5, to.x < from.x + 0.5 else { return nil }
            along = from.x - to.maxX
            sideways = overlap(from.y, from.maxY, to.y, to.maxY) ? 0 : abs(to.midY - from.midY)
        case .right:
            guard to.midX > from.midX + 0.5, to.maxX > from.maxX - 0.5 else { return nil }
            along = to.x - from.maxX
            sideways = overlap(from.y, from.maxY, to.y, to.maxY) ? 0 : abs(to.midY - from.midY)
        }
        return max(along, 0) + 2 * sideways
    }

    private static func overlap(_ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Bool {
        a0 < b1 && b0 < a1
    }

    /// A stick held past this much (of 1) counts as a press in its direction.
    public static let stickThreshold = 0.6
    /// Holding a direction repeats after this long, then at this interval (seconds).
    public static let repeatDelay = 0.4
    public static let repeatInterval = 0.12

    /// The direction a stick or d-pad position points in, or nil in the middle. y is up-positive.
    public static func direction(x: Double, y: Double, threshold: Double = stickThreshold) -> Direction? {
        guard max(abs(x), abs(y)) >= threshold else { return nil }
        if abs(x) > abs(y) {
            return x > 0 ? .right : .left
        }
        return y > 0 ? .up : .down
    }
}

/// Turns a held direction into presses: one at once, then repeats after a delay, with injected
/// time as the other state machines do.
public struct DirectionRepeater: Equatable, Sendable {
    private var held: SpatialNavigation.Direction?
    private var nextAt: TimeInterval = 0

    public init() {}

    /// The direction now held (nil for none) at time `now`. Returns a press to act on, if any.
    public mutating func update(_ direction: SpatialNavigation.Direction?, now: TimeInterval) -> SpatialNavigation.Direction? {
        guard let direction else {
            held = nil
            return nil
        }
        if direction != held {
            held = direction
            nextAt = now + SpatialNavigation.repeatDelay
            return direction
        }
        if now >= nextAt {
            nextAt = now + SpatialNavigation.repeatInterval
            return direction
        }
        return nil
    }

    /// When `update` should be called again to repeat, or nil when nothing is held.
    public var nextDeadline: TimeInterval? {
        held == nil ? nil : nextAt
    }
}
