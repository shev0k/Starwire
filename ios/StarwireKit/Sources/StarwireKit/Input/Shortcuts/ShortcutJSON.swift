import Foundation

// A small JSON reader and writer for the shortcut files and the saved custom commands. It is here
// instead of JSONSerialization because the shortcut file lists keys as numbers or strings and a
// `true` must never be read as the key number 1, which JSONSerialization can't tell apart on every
// platform. Also, the files come from outside the app, so nesting is capped.
//
// Reads what Android's org.json reads for these files, except that it is strict: comments, single
// quotes, unquoted words and text after the value are errors here.

/// One JSON value. Objects keep their order; a repeated key means the last one counts, as in
/// Android's org.json.
enum ShortcutJSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ShortcutJSONValue])
    case object([(key: String, value: ShortcutJSONValue)])

    static func == (lhs: ShortcutJSONValue, rhs: ShortcutJSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    /// The value for `key` in an object, or nil.
    subscript(key: String) -> ShortcutJSONValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.last(where: { $0.key == key })?.value
    }

    static let maxDepth = 64

    /// Parses `text`, or returns nil if it isn't one JSON value.
    static func parse(_ text: String) -> ShortcutJSONValue? {
        var reader = Reader(scalars: Array(text.unicodeScalars))
        reader.skipSpace()
        guard let value = reader.value(depth: 0) else { return nil }
        reader.skipSpace()
        return reader.atEnd ? value : nil
    }

    /// The value as compact JSON text.
    func serialized() -> String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return Self.quote(value)
        case .array(let items): return "[" + items.map { $0.serialized() }.joined(separator: ",") + "]"
        case .object(let pairs):
            return "{" + pairs.map { Self.quote($0.key) + ":" + $0.value.serialized() }.joined(separator: ",") + "}"
        }
    }

    private static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        var atEnd: Bool { index >= scalars.count }

        mutating func skipSpace() {
            while index < scalars.count, [" ", "\t", "\n", "\r"].contains(scalars[index]) {
                index += 1
            }
        }

        mutating func value(depth: Int) -> ShortcutJSONValue? {
            guard depth <= ShortcutJSONValue.maxDepth, index < scalars.count else { return nil }
            switch scalars[index] {
            case "{": return object(depth: depth)
            case "[": return array(depth: depth)
            case "\"": return string().map { .string($0) }
            case "t": return word("true", .bool(true))
            case "f": return word("false", .bool(false))
            case "n": return word("null", .null)
            default: return number()
            }
        }

        mutating func word(_ text: String, _ result: ShortcutJSONValue) -> ShortcutJSONValue? {
            let letters = Array(text.unicodeScalars)
            guard index + letters.count <= scalars.count, Array(scalars[index..<index + letters.count]) == letters else {
                return nil
            }
            index += letters.count
            return result
        }

        mutating func number() -> ShortcutJSONValue? {
            let start = index
            func isDigit(_ i: Int) -> Bool { i < scalars.count && scalars[i].value >= 0x30 && scalars[i].value <= 0x39 }
            if index < scalars.count, scalars[index] == "-" { index += 1 }
            guard isDigit(index) else { return nil }
            if scalars[index] == "0" {
                index += 1
            } else {
                while isDigit(index) { index += 1 }
            }
            var isInteger = true
            if index < scalars.count, scalars[index] == "." {
                isInteger = false
                index += 1
                guard isDigit(index) else { return nil }
                while isDigit(index) { index += 1 }
            }
            if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
                isInteger = false
                index += 1
                if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" { index += 1 }
                guard isDigit(index) else { return nil }
                while isDigit(index) { index += 1 }
            }
            var text = ""
            text.unicodeScalars.append(contentsOf: scalars[start..<index])
            if isInteger, let whole = Int(text) {
                return .int(whole)
            }
            guard let real = Double(text), real.isFinite else { return nil }
            return .double(real)
        }

        mutating func string() -> String? {
            guard index < scalars.count, scalars[index] == "\"" else { return nil }
            index += 1
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"":
                    return String(out)
                case "\\":
                    guard index < scalars.count else { return nil }
                    let escape = scalars[index]
                    index += 1
                    switch escape {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u":
                        guard var code = hex4() else { return nil }
                        if (0xD800...0xDBFF).contains(code) {
                            // A high surrogate needs its low half right after it
                            guard index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u" else { return nil }
                            index += 2
                            guard let low = hex4(), (0xDC00...0xDFFF).contains(low) else { return nil }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let decoded = Unicode.Scalar(code) else { return nil }
                        out.append(decoded)
                    default:
                        return nil
                    }
                default:
                    // Raw control characters must be escaped
                    if scalar.value < 0x20 { return nil }
                    out.append(scalar)
                }
            }
            return nil
        }

        mutating func hex4() -> UInt32? {
            guard index + 4 <= scalars.count else { return nil }
            var code: UInt32 = 0
            for _ in 0..<4 {
                guard let digit = Character(scalars[index]).hexDigitValue else { return nil }
                code = code * 16 + UInt32(digit)
                index += 1
            }
            return code
        }

        mutating func array(depth: Int) -> ShortcutJSONValue? {
            index += 1
            var items: [ShortcutJSONValue] = []
            skipSpace()
            if index < scalars.count, scalars[index] == "]" {
                index += 1
                return .array(items)
            }
            while true {
                skipSpace()
                guard let item = value(depth: depth + 1) else { return nil }
                items.append(item)
                skipSpace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," {
                    index += 1
                } else if scalars[index] == "]" {
                    index += 1
                    return .array(items)
                } else {
                    return nil
                }
            }
        }

        mutating func object(depth: Int) -> ShortcutJSONValue? {
            index += 1
            var pairs: [(key: String, value: ShortcutJSONValue)] = []
            skipSpace()
            if index < scalars.count, scalars[index] == "}" {
                index += 1
                return .object(pairs)
            }
            while true {
                skipSpace()
                guard let key = string() else { return nil }
                skipSpace()
                guard index < scalars.count, scalars[index] == ":" else { return nil }
                index += 1
                skipSpace()
                guard let item = value(depth: depth + 1) else { return nil }
                pairs.append((key: key, value: item))
                skipSpace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," {
                    index += 1
                } else if scalars[index] == "}" {
                    index += 1
                    return .object(pairs)
                } else {
                    return nil
                }
            }
        }
    }
}
