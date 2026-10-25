import Foundation

/// Measures one touch gesture at a time, from the first finger down to the last one up: how often
/// UIKit delivered touches, how many samples each delivery carried (the coalesced touches), how
/// late they arrived, and what was sent to the PC per second. The statistics overlay shows the
/// last gesture's numbers as its "Touch rate:" line, so a device test can read them. Thread safe.
public final class TouchRateMeter: @unchecked Sendable {
    public struct Gesture: Equatable, Sendable {
        public var duration: TimeInterval = 0
        /// touchesMoved deliveries
        public var events = 0
        /// Samples in those deliveries (each coalesced touch of each finger that moved)
        public var samples = 0
        /// Seconds from a touch's own timestamp to its delivery, summed and at most
        public var deliverySum: TimeInterval = 0
        public var deliveryMax: TimeInterval = 0
        public var sent: [InputTally.Kind: Int] = [:]

        public var eventsPerSecond: Double { duration > 0 ? Double(events) / duration : 0 }
        public var samplesPerSecond: Double { duration > 0 ? Double(samples) / duration : 0 }
        public var meanDelivery: TimeInterval { events > 0 ? deliverySum / Double(events) : 0 }

        public func sentPerSecond(_ kind: InputTally.Kind) -> Double {
            duration > 0 ? Double(sent[kind] ?? 0) / duration : 0
        }
    }

    /// Gestures shorter than this aren't kept (a tap says nothing about rates)
    public static let minimumDuration: TimeInterval = 0.1

    private let lock = NSLock()
    private var current: Gesture?
    private var start: TimeInterval = 0
    private var last: Gesture?
    private var fingers = 0

    public init() {}

    /// Fingers went down or up; `count` is how many are down now.
    public func fingersChanged(to count: Int, at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if fingers == 0 && count > 0 {
            current = Gesture()
            start = now
        } else if fingers > 0 && count == 0, var gesture = current {
            gesture.duration = now - start
            if gesture.duration >= Self.minimumDuration && gesture.events > 0 {
                last = gesture
            }
            current = nil
        }
        fingers = count
    }

    /// One touchesMoved delivery: the latest touch's timestamp and the samples it carried.
    public func moved(samples: Int, touchTime: TimeInterval, at now: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard current != nil else { return }
        let delay = max(now - touchTime, 0)
        current!.events += 1
        current!.samples += samples
        current!.deliverySum += delay
        current!.deliveryMax = max(current!.deliveryMax, delay)
    }

    /// A packet went to the PC.
    public func sent(_ event: InputEvent) {
        lock.lock()
        defer { lock.unlock() }
        guard current != nil else { return }
        current!.sent[InputTally.kind(of: event), default: 0] += 1
    }

    public var lastGesture: Gesture? {
        lock.lock()
        defer { lock.unlock() }
        return last
    }

    /// "Touch rate: 120 events/s, 240 samples/s, delivery 4.2 ms (max 8.1); sent touch 240/s, scroll 0/s, mouse 120/s"
    public var line: String {
        guard let g = lastGesture else { return "Touch rate: no gesture yet" }
        let sent = [InputTally.Kind.touch, .scroll, .mouse].map { "\($0.rawValue) \(Int(g.sentPerSecond($0).rounded()))/s" }
        return String(format: "Touch rate: %d events/s, %d samples/s, delivery %.1f ms (max %.1f); sent ",
                      Int(g.eventsPerSecond.rounded()), Int(g.samplesPerSecond.rounded()),
                      g.meanDelivery * 1000, g.deliveryMax * 1000) + sent.joined(separator: ", ")
    }
}
