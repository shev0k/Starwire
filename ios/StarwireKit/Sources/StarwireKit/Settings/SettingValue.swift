import Foundation

/// One saved setting, typed the way Starwire for Android saves it in SharedPreferences: check
/// boxes as Bool, sliders as Int, and every list and text field as String, even when it holds a
/// number ("60", "1500").
public enum SettingValue: Equatable, Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)

    public var kind: SettingKind {
        switch self {
        case .bool: return .bool
        case .int: return .int
        case .string: return .string
        }
    }

    /// The value as a property-list object, for UserDefaults.
    public var propertyListValue: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .string(let value): return value
        }
    }

    /// The value as JSON would carry it.
    var jsonValue: Any { propertyListValue }
}

public enum SettingKind: String, Sendable {
    case bool
    case int
    case string
}

extension SettingValue {
    /// Reads a value of the given kind from a property-list or JSON object. Numbers and strings
    /// that clearly mean the same thing are converted ("60" for an Int, 1 for a Bool), so a file
    /// written by hand or by another version still imports. Anything else is nil.
    public static func coerce(_ object: Any?, to kind: SettingKind) -> SettingValue? {
        guard let object else { return nil }
        switch kind {
        case .bool:
            if let value = object as? Bool, !(object is Int && !(type(of: object) == Bool.self)) {
                return .bool(value)
            }
            if let value = object as? String {
                switch value.lowercased() {
                case "true", "1", "yes": return .bool(true)
                case "false", "0", "no": return .bool(false)
                default: return nil
                }
            }
            if let value = object as? NSNumber {
                return .bool(value.intValue != 0)
            }
            return nil
        case .int:
            if let value = object as? String {
                return Int(value.trimmingCharacters(in: .whitespaces)).map(SettingValue.int)
            }
            if let value = object as? NSNumber {
                let double = value.doubleValue
                guard double.rounded() == double, abs(double) < Double(Int32.max) else { return nil }
                return .int(value.intValue)
            }
            return nil
        case .string:
            if let value = object as? String {
                return .string(value)
            }
            if let value = object as? NSNumber {
                // A JSON number for a list that stores digits, like list_fps
                let double = value.doubleValue
                if double.rounded() == double {
                    return .string(String(value.intValue))
                }
                return .string(String(double))
            }
            return nil
        }
    }
}
