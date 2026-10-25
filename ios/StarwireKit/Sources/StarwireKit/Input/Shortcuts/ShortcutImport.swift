import Foundation

// Ported from Starwire for Android (GPL-3.0): ImportedShortcuts.java (the file format, its
// limits, the VK_ name table and the saved copy) and StreamSettings.java (the file size limit and
// the summary of what was imported). The file format is Artemide's "import custom shortcuts"
// (Axixi2233 and Artemis by Yukino Song, see CoverGlowSettings.CREDITS).

/// Why a shortcuts file was refused, in plain English. The messages are Android's.
public struct ShortcutImportError: Error, Equatable, CustomStringConvertible, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

/// Reads Starwire's shortcut file:
///
///     {"data": [
///       {"name": "Snipping tool", "keys": ["VK_LWIN", "VK_LSHIFT", "VK_S"]},
///       {"name": "Mute", "keys": ["0xAD"]}
///     ]}
///
/// A key is a Windows virtual-key name (`VK_...`), a hex code (`0x5B`) or a number. The keys are
/// pressed in order and let go in reverse order, like the built-in shortcuts. A bare list without
/// the "data" wrapper works too. Names are not checked for duplicates: two shortcuts may share a
/// name or keys.
///
/// Limits: 50 shortcuts, 8 keys each, key codes 1 to 254 (0xFE), a file of at most 256 KiB.
/// Unlike Android's JSON reader this one is strict, so a file with comments, single quotes or
/// text after the closing bracket is "not a JSON file".
public enum ShortcutImport {
    public static let maxShortcuts = 50
    public static let maxKeys = 8
    /// Shortcut files are tiny; anything bigger is the wrong file.
    public static let maxFileBytes = 256 * 1024
    /// Where the imported text is kept: Android's key.
    public static let storageKey = "overlay_imported_shortcuts"

    /// Reads a shortcuts file, or throws what is wrong with it.
    public static func parse(_ text: String) throws -> [Shortcut] {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\u{FEFF}") {
            trimmed.removeFirst()
        }
        guard let root = ShortcutJSONValue.parse(trimmed) else {
            throw ShortcutImportError("not a JSON file")
        }

        let list: [ShortcutJSONValue]
        switch root {
        case .object:
            guard case .array(let items)? = root["data"] else {
                throw ShortcutImportError("no \"data\" list of shortcuts")
            }
            list = items
        case .array(let items):
            list = items
        default:
            // A bare word or number is JSON, but not a file of shortcuts
            throw ShortcutImportError("not a JSON file")
        }
        if list.isEmpty {
            throw ShortcutImportError("the \"data\" list is empty")
        }
        if list.count > maxShortcuts {
            throw ShortcutImportError("more than \(maxShortcuts) shortcuts")
        }

        var shortcuts: [Shortcut] = []
        for (index, item) in list.enumerated() {
            let place = "shortcut \(index + 1)"
            guard case .object = item else {
                throw ShortcutImportError("\(place) is not an object")
            }
            let name = nameText(item["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                throw ShortcutImportError("\(place) has no name")
            }
            guard case .array(let keys)? = item["keys"], !keys.isEmpty else {
                throw ShortcutImportError("\"\(name)\" has no keys")
            }
            if keys.count > maxKeys {
                throw ShortcutImportError("\"\(name)\" has more than \(maxKeys) keys")
            }
            var codes: [Int] = []
            for key in keys {
                guard let code = keyCode(key) else {
                    throw ShortcutImportError("\"\(name)\" has an unknown key: \(keyText(key))")
                }
                codes.append(code)
            }
            shortcuts.append(Shortcut(id: "imported-\(index + 1)", name: name, keys: codes))
        }
        return shortcuts
    }

    /// Reads the bytes of a file. Refuses a file over 256 KiB before reading it.
    public static func parse(_ data: Data) throws -> [Shortcut] {
        if data.count > maxFileBytes {
            throw ShortcutImportError("the file is too big to be a shortcuts file")
        }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    /// A key from the file: "VK_LWIN", "0x5B", "91" or the number 91. Nil if it isn't a key
    /// from 1 to 254.
    static func keyCode(_ key: ShortcutJSONValue?) -> Int? {
        var code = -1
        switch key {
        case .int(let number)?:
            code = number
        case .double(let number)?:
            // Android takes the whole part
            code = abs(number) < 1_000_000_000 ? Int(number) : -1
        case .string(let name)?:
            code = keyCode(named: name) ?? -1
        default:
            break
        }
        return code >= 0x01 && code <= 0xFE ? code : nil
    }

    /// The code for a name or number in text form, or nil.
    public static func keyCode(named name: String) -> Int? {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let code: Int?
        if text.hasPrefix("0X") {
            code = Int(text.dropFirst(2), radix: 16)
        } else if text.hasPrefix("VK_") {
            code = vkNames[text]
        } else {
            code = Int(text)
        }
        guard let code, code >= 0x01, code <= 0xFE else { return nil }
        return code
    }

    // The name as Android's optString reads it: text, or a number written out
    private static func nameText(_ value: ShortcutJSONValue?) -> String {
        switch value {
        case .string(let text)?: return text
        case .int(let number)?: return String(number)
        case .double(let number)?: return String(number)
        default: return ""
        }
    }

    // A key as it is shown in "has an unknown key: ..."
    private static func keyText(_ value: ShortcutJSONValue) -> String {
        if case .string(let text) = value {
            return text
        }
        return value.serialized()
    }

    /// The first names of the shortcuts, as Android shows them under "Import shortcuts": four
    /// names, then an ellipsis if there are more.
    public static func summaryNames(_ shortcuts: [Shortcut]) -> String {
        var names = shortcuts.prefix(4).map(\.name).joined(separator: ", ")
        if shortcuts.count > 4 {
            names += ", \u{2026}"
        }
        return names
    }

    /// Windows virtual-key names, listed as Android lists them.
    static let vkNames: [String: Int] = {
        var names: [String: Int] = [:]
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".unicodeScalars {
            names["VK_" + String(letter)] = Int(letter.value)
        }
        for digit in 0...9 {
            names["VK_\(digit)"] = 0x30 + digit
            names["VK_NUMPAD\(digit)"] = 0x60 + digit
        }
        for number in 1...24 {
            names["VK_F\(number)"] = 0x6F + number
        }
        let named: [(String, Int)] = [
            ("VK_BACK", 0x08), ("VK_TAB", 0x09), ("VK_CLEAR", 0x0C), ("VK_RETURN", 0x0D),
            ("VK_SHIFT", 0x10), ("VK_CONTROL", 0x11), ("VK_MENU", 0x12), ("VK_PAUSE", 0x13),
            ("VK_CAPITAL", 0x14), ("VK_ESCAPE", 0x1B), ("VK_SPACE", 0x20),
            ("VK_PRIOR", 0x21), ("VK_NEXT", 0x22), ("VK_END", 0x23), ("VK_HOME", 0x24),
            ("VK_LEFT", 0x25), ("VK_UP", 0x26), ("VK_RIGHT", 0x27), ("VK_DOWN", 0x28),
            ("VK_SNAPSHOT", 0x2C), ("VK_INSERT", 0x2D), ("VK_DELETE", 0x2E),
            ("VK_LWIN", 0x5B), ("VK_RWIN", 0x5C), ("VK_APPS", 0x5D),
            ("VK_MULTIPLY", 0x6A), ("VK_ADD", 0x6B), ("VK_SEPARATOR", 0x6C),
            ("VK_SUBTRACT", 0x6D), ("VK_DECIMAL", 0x6E), ("VK_DIVIDE", 0x6F),
            ("VK_NUMLOCK", 0x90), ("VK_SCROLL", 0x91),
            ("VK_LSHIFT", 0xA0), ("VK_RSHIFT", 0xA1), ("VK_LCONTROL", 0xA2),
            ("VK_RCONTROL", 0xA3), ("VK_LMENU", 0xA4), ("VK_RMENU", 0xA5),
            ("VK_VOLUME_MUTE", 0xAD), ("VK_VOLUME_DOWN", 0xAE), ("VK_VOLUME_UP", 0xAF),
            ("VK_MEDIA_NEXT_TRACK", 0xB0), ("VK_MEDIA_PREV_TRACK", 0xB1),
            ("VK_MEDIA_STOP", 0xB2), ("VK_MEDIA_PLAY_PAUSE", 0xB3),
            ("VK_OEM_1", 0xBA), ("VK_OEM_PLUS", 0xBB), ("VK_OEM_COMMA", 0xBC),
            ("VK_OEM_MINUS", 0xBD), ("VK_OEM_PERIOD", 0xBE), ("VK_OEM_2", 0xBF),
            ("VK_OEM_3", 0xC0), ("VK_OEM_4", 0xDB), ("VK_OEM_5", 0xDC),
            ("VK_OEM_6", 0xDD), ("VK_OEM_7", 0xDE),
            // Common short names
            ("VK_ALT", 0x12), ("VK_LALT", 0xA4), ("VK_RALT", 0xA5), ("VK_CTRL", 0x11),
            ("VK_LCTRL", 0xA2), ("VK_RCTRL", 0xA3), ("VK_WIN", 0x5B), ("VK_ENTER", 0x0D),
            ("VK_ESC", 0x1B), ("VK_BACKSPACE", 0x08), ("VK_DEL", 0x2E),
            ("VK_PAGEUP", 0x21), ("VK_PAGEDOWN", 0x22), ("VK_PRINTSCREEN", 0x2C),
        ]
        for (name, code) in named {
            names[name] = code
        }
        return names
    }()
}

/// The imported shortcuts, saved as the file's own text in the settings storage (UserDefaults in
/// the app) under Android's key `overlay_imported_shortcuts`, so a new import replaces the old
/// one. This key isn't in `SettingsCatalog`, so `SettingsJSON` doesn't carry it between devices.
///
/// Android's "Import shortcuts from a file" setting is `save`, and "Remove imported shortcuts"
/// is `clear`.
public final class ImportedShortcutsStore {
    private let storage: SettingsStorage

    public init(storage: SettingsStorage) {
        self.storage = storage
    }

    /// The saved text, if any.
    public var savedText: String? {
        storage.object(forKey: ShortcutImport.storageKey) as? String
    }

    /// The imported shortcuts, or none if there are none or the saved text no longer reads.
    public func load() -> [Shortcut] {
        guard let text = savedText, !text.isEmpty else { return [] }
        return (try? ShortcutImport.parse(text)) ?? []
    }

    /// Checks a file's text and saves it in place of any earlier import. Returns how many
    /// shortcuts it has. Throws, and keeps the earlier import, if the file is wrong.
    @discardableResult
    public func save(_ text: String) throws -> Int {
        let count = try ShortcutImport.parse(text).count
        storage.set(text, forKey: ShortcutImport.storageKey)
        return count
    }

    /// Checks a file's bytes (including its size) and saves it.
    @discardableResult
    public func save(_ data: Data) throws -> Int {
        let count = try ShortcutImport.parse(data).count
        storage.set(String(decoding: data, as: UTF8.self), forKey: ShortcutImport.storageKey)
        return count
    }

    public func clear() {
        storage.removeObject(forKey: ShortcutImport.storageKey)
    }
}
