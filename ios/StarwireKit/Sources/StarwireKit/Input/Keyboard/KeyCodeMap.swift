import Foundation

// Ported from Starwire for Android (GPL-3.0): KeyboardTranslator.java, which maps key codes to
// Windows virtual-key codes. Here the input is the USB HID keyboard usage (page 7), which is what
// UIKeyboardHIDUsage and GCKeyCode carry. The table is checked against ios/Limelight/Input/
// KeyboardSupport.m, and the character table follows its translateKeyEvent.

/// Maps hardware keyboard keys and typed characters to Windows virtual-key codes.
public enum KeyCodeMap {
    /// `MODIFIER_EXTENDED` in moonlight-common-c: the key sends the 0xE0 scancode prefix. Needed
    /// for the numpad Enter, which shares its virtual key with the main Enter.
    public static let extendedModifier = 0x10

    /// What the host gets for a hardware key.
    public struct Entry: Equatable, Sendable {
        public let virtualKey: Int
        /// True when the packet must also carry `KeyCodeMap.extendedModifier`.
        public let extended: Bool

        init(_ virtualKey: Int, extended: Bool = false) {
            self.virtualKey = virtualKey
            self.extended = extended
        }
    }

    /// Windows virtual-key code for a HID keyboard usage, or nil when the key has no mapping.
    public static func virtualKey(forHIDUsage usage: Int) -> Int? {
        hidTable[usage]?.virtualKey
    }

    /// Like `virtualKey(forHIDUsage:)`, with the extended-key flag.
    public static func entry(forHIDUsage usage: Int) -> Entry? {
        hidTable[usage]
    }

    /// One US-layout key press: a virtual key, with Shift held when `needsShift` is set.
    public struct KeyStroke: Equatable, Sendable {
        public let virtualKey: Int
        public let needsShift: Bool
    }

    /// The key and Shift state that types `character` on a US layout, or nil for characters with
    /// no key on it (accents, emoji, and so on; send those as text).
    public static func keyStroke(for character: Character) -> KeyStroke? {
        characterTable[character]
    }

    /// The packets that type `character` as key presses: Shift down and up around the key when
    /// the character needs it. Nil when there is no US key for it.
    public static func keyEvents(for character: Character) -> [InputEvent]? {
        guard let stroke = keyStroke(for: character) else { return nil }
        let code = stroke.virtualKey
        guard stroke.needsShift else {
            return [.key(code: code, down: true, modifiers: 0), .key(code: code, down: false, modifiers: 0)]
        }
        return [
            .key(code: 0xA0, down: true, modifiers: KeyModifier.shift),
            .key(code: code, down: true, modifiers: KeyModifier.shift),
            .key(code: code, down: false, modifiers: KeyModifier.shift),
            .key(code: 0xA0, down: false, modifiers: 0),
        ]
    }

    // MARK: HID usage to virtual key

    private static let hidTable: [Int: Entry] = {
        var table: [Int: Entry] = [:]

        func add(_ usage: Int, _ vk: Int, extended: Bool = false) {
            table[usage] = Entry(vk, extended: extended)
        }
        func addRange(_ firstUsage: Int, count: Int, firstVK: Int) {
            for offset in 0..<count { add(firstUsage + offset, firstVK + offset) }
        }

        addRange(0x04, count: 26, firstVK: 0x41)   // A to Z
        addRange(0x1E, count: 9, firstVK: 0x31)    // 1 to 9
        add(0x27, 0x30)                            // 0 sits after 9 in HID but before 1 in Windows
        addRange(0x3A, count: 12, firstVK: 0x70)   // F1 to F12
        addRange(0x68, count: 12, firstVK: 0x7C)   // F13 to F24
        addRange(0x59, count: 9, firstVK: 0x61)    // numpad 1 to 9
        add(0x62, 0x60)                            // numpad 0

        add(0x28, 0x0D)  // Return
        add(0x29, 0x1B)  // Escape
        add(0x2A, 0x08)  // Backspace
        add(0x2B, 0x09)  // Tab
        add(0x2C, 0x20)  // Space
        add(0x2D, 0xBD)  // - _
        add(0x2E, 0xBB)  // = +
        add(0x2F, 0xDB)  // [ {
        add(0x30, 0xDD)  // ] }
        add(0x31, 0xDC)  // \ |
        add(0x33, 0xBA)  // ; :
        add(0x34, 0xDE)  // ' "
        add(0x35, 0xC0)  // ` ~
        add(0x36, 0xBC)  // , <
        add(0x37, 0xBE)  // . >
        add(0x38, 0xBF)  // / ?
        add(0x39, 0x14)  // Caps Lock

        // Windows names PrintScreen VK_SNAPSHOT (0x2C). KeyboardSupport.m sends 0x2A (VK_PRINT).
        add(0x46, 0x2C)  // Print Screen
        add(0x47, 0x91)  // Scroll Lock
        add(0x48, 0x13)  // Pause
        add(0x49, 0x2D)  // Insert
        add(0x4A, 0x24)  // Home
        add(0x4B, 0x21)  // Page Up
        add(0x4C, 0x2E)  // Delete Forward
        add(0x4D, 0x23)  // End
        add(0x4E, 0x22)  // Page Down
        add(0x4F, 0x27)  // Right
        add(0x50, 0x25)  // Left
        add(0x51, 0x28)  // Down
        add(0x52, 0x26)  // Up

        add(0x53, 0x90)  // Num Lock
        add(0x54, 0x6F)  // numpad /
        add(0x55, 0x6A)  // numpad *
        add(0x56, 0x6D)  // numpad -
        add(0x57, 0x6B)  // numpad +
        add(0x58, 0x0D, extended: true)  // numpad Enter
        add(0x63, 0x6E)  // numpad .
        add(0x85, 0x6C)  // numpad comma

        add(0x64, 0xE2)  // non-US \ and |
        add(0x65, 0x5D)  // Application (the menu key)

        // Keys past Android's table, taken from KeyboardSupport.m
        add(0x9B, 0x03)  // Cancel
        add(0x9C, 0x0C)  // Clear
        add(0xA3, 0xF7)  // CrSel
        add(0xA4, 0xF8)  // ExSel
        add(669, 0x1B)   // Apple Globe key, as Escape because Apple keyboards have none

        // International and language keys. Android has no entries; these are the usual Windows
        // names (ABNT C1, Yen as OEM 5, Convert, Non-convert, Hangul, Hanja).
        add(0x87, 0xC1)  // International 1
        add(0x89, 0xDC)  // International 3 (Yen)
        add(0x8A, 0x1C)  // International 4 (Henkan)
        add(0x8B, 0x1D)  // International 5 (Muhenkan)
        add(0x90, 0x15)  // Language 1 (Hangul)
        add(0x91, 0x19)  // Language 2 (Hanja)

        // Modifiers, left then right
        add(0xE0, 0xA2)  // Left Control
        add(0xE1, 0xA0)  // Left Shift
        add(0xE2, 0xA4)  // Left Alt
        add(0xE3, 0x5B)  // Left Windows
        add(0xE4, 0xA3)  // Right Control
        add(0xE5, 0xA1)  // Right Shift
        add(0xE6, 0xA5)  // Right Alt
        add(0xE7, 0x5C)  // Right Windows
        return table
    }()

    // MARK: Characters to US keys

    private static let characterTable: [Character: KeyStroke] = {
        var table: [Character: KeyStroke] = [:]

        for (offset, scalar) in "abcdefghijklmnopqrstuvwxyz".unicodeScalars.enumerated() {
            table[Character(scalar)] = KeyStroke(virtualKey: 0x41 + offset, needsShift: false)
            table[Character(Unicode.Scalar(scalar.value - 0x20)!)] = KeyStroke(virtualKey: 0x41 + offset, needsShift: true)
        }

        // Each row: the key, the character without Shift, the character with Shift
        let keys: [(vk: Int, plain: Character, shifted: Character)] = [
            (0x30, "0", ")"), (0x31, "1", "!"), (0x32, "2", "@"), (0x33, "3", "#"), (0x34, "4", "$"),
            (0x35, "5", "%"), (0x36, "6", "^"), (0x37, "7", "&"), (0x38, "8", "*"), (0x39, "9", "("),
            (0xBD, "-", "_"), (0xBB, "=", "+"), (0xDB, "[", "{"), (0xDD, "]", "}"), (0xDC, "\\", "|"),
            (0xBA, ";", ":"), (0xDE, "'", "\""), (0xC0, "`", "~"), (0xBC, ",", "<"), (0xBE, ".", ">"),
            (0xBF, "/", "?"),
        ]
        for key in keys {
            table[key.plain] = KeyStroke(virtualKey: key.vk, needsShift: false)
            table[key.shifted] = KeyStroke(virtualKey: key.vk, needsShift: true)
        }

        table[" "] = KeyStroke(virtualKey: 0x20, needsShift: false)
        table["\t"] = KeyStroke(virtualKey: 0x09, needsShift: false)
        table["\n"] = KeyStroke(virtualKey: 0x0D, needsShift: false)
        table["\r"] = KeyStroke(virtualKey: 0x0D, needsShift: false)
        return table
    }()
}
