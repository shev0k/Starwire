import Foundation

// Ported from Starwire for Android's VbanSender.isHomeNetworkAddress (GPL-3.0).

/// Which addresses the microphone is sent to: the home network (private and link-local ranges),
/// this device, and the ranges private VPNs like Tailscale use (100.64.0.0/10 and fc00::/7).
///
/// This is a filter, not a security boundary: everyone on the network has such an address, a
/// sender's address is easy to fake, and 100.64.0.0/10 is also carrier-grade NAT space shared
/// with other customers of a mobile or internet provider. The encryption and pairing are the
/// security.
public enum HomeNetwork {
    /// `bytes` is an IPv4 (4 bytes) or IPv6 (16 bytes) address in network order.
    public static func contains(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4:
            let (a, b) = (bytes[0], bytes[1])
            return a == 10 || (a == 172 && b & 0xF0 == 16) || (a == 192 && b == 168)   // private
                || (a == 169 && b == 254)                                              // link-local
                || a == 127                                                            // loopback
                || (a == 100 && b & 0xC0 == 64)                                        // VPNs, CGNAT
        case 16:
            if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                // An IPv4 address written as IPv6
                return contains(Array(bytes[12...]))
            }
            let loopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
            return loopback
                || (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80)   // link-local fe80::/10
                || (bytes[0] == 0xFE && bytes[1] & 0xC0 == 0xC0)   // site-local fec0::/10
                || bytes[0] & 0xFE == 0xFC                          // unique local fc00::/7
        default:
            return false
        }
    }

    /// The same for an address written as text (dotted IPv4, or IPv6 such as "fe80::1"), or false if
    /// it isn't one.
    public static func contains(_ text: String) -> Bool {
        if let v4 = parseIPv4(text) {
            return contains(v4)
        }
        if let v6 = parseIPv6(text) {
            return contains(v6)
        }
        return false
    }

    public static func parseIPv4(_ text: String) -> [UInt8]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let value = UInt8(part) else { return nil }
            out.append(value)
        }
        return out
    }

    public static func parseIPv6(_ text: String) -> [UInt8]? {
        // Drop a zone ("fe80::1%en0")
        var address = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
        // An IPv4 address at the end ("::ffff:192.168.0.1") is the last two groups
        if let lastColon = address.lastIndex(of: ":"),
           let v4 = parseIPv4(String(address[address.index(after: lastColon)...])) {
            let high = String(Int(v4[0]) << 8 | Int(v4[1]), radix: 16)
            let low = String(Int(v4[2]) << 8 | Int(v4[3]), radix: 16)
            address = String(address[...lastColon]) + high + ":" + low
        }
        let halves = address.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ part: String) -> [UInt16]? {
            if part.isEmpty { return [] }
            var out: [UInt16] = []
            for group in part.split(separator: ":", omittingEmptySubsequences: false) {
                guard (1...4).contains(group.count), let value = UInt16(group, radix: 16) else { return nil }
                out.append(value)
            }
            return out
        }
        guard let head = groups(halves[0]) else { return nil }
        var all = head
        if halves.count == 2 {
            guard let tail = groups(halves[1]), head.count + tail.count < 8 else { return nil }
            all += [UInt16](repeating: 0, count: 8 - head.count - tail.count) + tail
        }
        guard all.count == 8 else { return nil }
        return all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
    }
}
