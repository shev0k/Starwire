import Foundation

/// The time, for logic that waits or measures: grace periods, polls, debounces. Production code
/// uses `SystemClock`; tests use `FakeClock` and move it by hand, so they never wait or depend on
/// the wall clock.
public protocol Clock: AnyObject, Sendable {
    /// Seconds on a clock that only goes forward. Only differences between two readings mean
    /// anything.
    var now: TimeInterval { get }
}

/// The device's monotonic clock (`ProcessInfo.systemUptime`), which doesn't jump when the user
/// or the network changes the date.
public final class SystemClock: Clock {
    public static let shared = SystemClock()

    public init() {}

    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// A clock that only moves when told to.
public final class FakeClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval

    public init(now: TimeInterval = 1000) {
        current = now
    }

    public var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}
