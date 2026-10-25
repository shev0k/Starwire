import Foundation

/// The PC's MAC address, kept for Wake-on-LAN.
public enum MacAddress {
    /// What the host sends when it won't say: an unpaired (plain HTTP) serverinfo, or a host
    /// with no wired adapter.
    public static let unknown = "00:00:00:00:00:00"

    /// The MAC address to keep after a poll. A poll that doesn't know it (no element, empty, or
    /// all zeros) never replaces one the app already has, or Wake-on-LAN stops working after
    /// one plain HTTP answer.
    public static func merge(saved: String?, polled: String?) -> String? {
        if let polled = normalized(polled) {
            return polled
        }
        return normalized(saved)
    }

    /// The address in upper case with colons, or nil if it says nothing.
    public static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let upper = trimmed.uppercased().replacingOccurrences(of: "-", with: ":")
        if upper == unknown {
            return nil
        }
        return upper
    }
}
