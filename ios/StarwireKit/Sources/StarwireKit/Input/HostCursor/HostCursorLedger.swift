import Foundation

// Ported from Starwire for Android (GPL-3.0): HostCursorLedger.java. Android keeps one small file
// per PC; this keeps one string per PC in a store the app backs with UserDefaults.

/// Where the ledger writes its records: a string per key. In the app this is UserDefaults.
public protocol HostCursorLedgerStore: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
    func removeString(forKey key: String)
}

/// A store in memory, for tests. Make a second ledger on the same store to stand for the app
/// being killed and started again.
public final class MemoryHostCursorLedgerStore: HostCursorLedgerStore {
    public private(set) var values: [String: String] = [:]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public func string(forKey key: String) -> String? { values[key] }
    public func setString(_ value: String, forKey key: String) { values[key] = value }
    public func removeString(forKey key: String) { values[key] = nil }
}

/// UserDefaults as a ledger store. UserDefaults hands a write to the system at once, so it
/// should survive the app being killed straight after; that hasn't been tested on a device.
public final class UserDefaultsHostCursorLedgerStore: HostCursorLedgerStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func setString(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    public func removeString(forKey key: String) { defaults.removeObject(forKey: key) }
}

/// A cursor that Starwire hid and hasn't shown again.
public struct HostCursorDebt: Equatable, Sendable, CustomStringConvertible {
    /// Unix time in milliseconds when it was written down.
    public var hiddenAtMilliseconds: Int64
    public var appID: Int
    public var reason: String

    public init(hiddenAtMilliseconds: Int64, appID: Int, reason: String) {
        self.hiddenAtMilliseconds = hiddenAtMilliseconds
        self.appID = appID
        self.reason = reason
    }

    public var description: String {
        "hidden at \(hiddenAtMilliseconds) (app \(appID), \(reason))"
    }
}

/// Remembers, per PC, that Starwire has hidden the PC's cursor and hasn't shown it again yet.
/// The host's cursor toggle is one switch for the whole host that only resets when the host's
/// streaming software restarts, so if Starwire is killed while the cursor is hidden, this record
/// is the only way to know it has to be turned back on at the next connection.
///
/// The record exists while the cursor is hidden: `v1 hidden <unix ms> <app ID> <reason>`, the
/// same text Android writes to its file.
public final class HostCursorLedger {
    static let version = "v1"
    static let keyPrefix = "host_cursor."

    private let store: HostCursorLedgerStore
    public let hostKey: String
    private let nowMilliseconds: () -> Int64
    private var appID = 0

    /// `nowMilliseconds` is the Unix time in milliseconds, for the record's timestamp. Tests pass
    /// a fixed one.
    public init(store: HostCursorLedgerStore, hostKey: String,
                nowMilliseconds: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.store = store
        self.hostKey = hostKey
        self.nowMilliseconds = nowMilliseconds
    }

    /// The PC's UUID, or its address when the UUID isn't known.
    public static func hostKey(pcUUID: String?, host: String) -> String {
        pcUUID ?? "addr:" + host
    }

    var storeKey: String { Self.keyPrefix + hostKey }

    /// The open debt for this PC, or nil when the cursor wasn't left hidden. A record that
    /// doesn't read is ignored.
    public func read() -> HostCursorDebt? {
        guard let text = store.string(forKey: storeKey) else { return nil }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == Self.version, parts[1] == "hidden",
              let hiddenAt = Int64(parts[2]), let app = Int(parts[3]) else {
            return nil
        }
        return HostCursorDebt(hiddenAtMilliseconds: hiddenAt, appID: app, reason: String(parts[4]))
    }

    /// Write down that the cursor is about to be hidden. Call before sending the toggle.
    public func markHidden(appID: Int, reason: String) {
        self.appID = appID
        write(reason)
    }

    /// Change why the cursor is hidden, keeping it hidden (for the logs). Does nothing if no
    /// cursor is recorded as hidden.
    public func setReason(_ reason: String) {
        if let debt = read() {
            appID = debt.appID
            write(reason)
        }
    }

    /// The cursor was shown again, so there is nothing left to fix.
    public func markShown() {
        store.removeString(forKey: storeKey)
    }

    private func write(_ reason: String) {
        let text = reason.isEmpty ? "-" : reason.replacingOccurrences(of: "\n", with: " ")
        store.setString("\(Self.version) hidden \(nowMilliseconds()) \(appID) \(text)", forKey: storeKey)
    }
}
