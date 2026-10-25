import Foundation

// Ported from Starwire for Android's PairingCode.java (GPL-3.0).

/// The one-time code the PC's receiver shows for pairing: 10 random bytes (80 bits) in Crockford's
/// base32, 16 characters in groups of four, like 2491-650N-2RBH-G690. There's no I, L, O or U, so
/// the code can't be misread; typing O for 0 or I or L for 1 still works.
public enum PairingCode {
    public static let bytes = 10
    public static let characters = 16
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// 10 bytes as the receiver shows them.
    public static func encode(_ code: [UInt8]) -> String {
        precondition(code.count == bytes, "a pairing code is 10 bytes")
        var out = ""
        var buffer = 0
        var bits = 0
        var count = 0
        for byte in code {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                if count > 0 && count % 4 == 0 {
                    out.append("-")
                }
                out.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
                count += 1
            }
        }
        return out
    }

    /// The 10 bytes of a typed code, or nil if it isn't 16 valid characters. Case, spaces and
    /// hyphens don't matter, and O reads as 0, I and L as 1.
    public static func decode(_ text: String) -> [UInt8]? {
        var values: [Int] = []
        for character in text.uppercased() {
            if character == "-" || character == " " {
                continue
            }
            guard let value = value(of: character), values.count < characters else {
                return nil
            }
            values.append(value)
        }
        guard values.count == characters else { return nil }
        var out: [UInt8] = []
        var buffer = 0
        var bits = 0
        for value in values {
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                out.append(UInt8(truncatingIfNeeded: buffer >> (bits - 8)))
                bits -= 8
            }
        }
        return out
    }

    /// What the code field shows while the user types: capitals, no spaces, a hyphen after every
    /// four characters. Characters that can't be in a code stay, so `decode` can say it's wrong
    /// instead of the field quietly dropping what was typed.
    public static func format(_ typed: String) -> String {
        var out = ""
        var count = 0
        for character in typed.uppercased() where character != "-" && !character.isWhitespace {
            if count > 0 && count % 4 == 0 {
                out.append("-")
            }
            out.append(character)
            count += 1
        }
        return out
    }

    private static func value(of character: Character) -> Int? {
        let c: Character
        switch character {
        case "O": c = "0"
        case "I", "L": c = "1"
        default: c = character
        }
        return alphabet.firstIndex(of: c)
    }
}
