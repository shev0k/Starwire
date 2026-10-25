import Foundation

// Ported from Starwire for Android (GPL-3.0): the on-screen full keyboard in
// app/src/main/res/layout/layout_axixi_keyboard.xml (keys, order, widths, margins) and
// KeyBoardLayoutController.java (which keys are modifiers and "special"). The keyboard comes from
// Artemide; Android's key tags are Android key codes, kept here as `androidKeyCode`.

/// What a key does when tapped.
public enum FullKeyboardKeyKind: Equatable, Sendable {
    /// An ordinary key: down on touch, up on release.
    case normal
    /// Shift, Ctrl, Alt or Win. With sticky modifier keys on, a long press locks it down.
    case modifier
    /// Caps Lock. Android sends it like any other key; the host keeps the lock state.
    case toggle
    /// The key that hides the keyboard. It sends nothing to the PC.
    case hide
}

/// One key of the full keyboard.
public struct FullKeyboardKey: Equatable, Sendable {
    /// Stable name, such as "a", "shift" or "f12". Unique in the layout.
    public let id: String
    /// What the key shows. Android shows letters in capitals.
    public let label: String
    /// The character above the main one on keys that show two ("~" over "`"), if any.
    public let shiftedLabel: String?
    /// Windows virtual-key code sent to the PC. 0 for the hide key.
    public let virtualKey: Int
    /// The Android key code the key carries as its tag. 0 for the hide key.
    public let androidKeyCode: Int
    /// Android's layout weight. A weight of 100 is a standard key.
    public let weight: Int
    public let kind: FullKeyboardKeyKind
    /// Row from the top, starting at 0.
    public let row: Int
    /// Extra space before and after the key, in dp, from Android's layout margins.
    public let marginBefore: Int
    public let marginAfter: Int
    /// `KeyModifier` flag the key sets while it is down. 0 unless the key is a modifier.
    public let modifierMask: Int
    /// True for keys that show no popup above them when pressed (Android's "special" keys).
    public let isSpecial: Bool

    /// Width relative to a standard key.
    public var relativeWidth: Double { Double(weight) / 100 }
}

/// A keyboard: rows of keys, top to bottom, each row left to right.
public struct FullKeyboardLayout: Equatable, Sendable {
    public let rows: [[FullKeyboardKey]]

    public init(rows: [[FullKeyboardKey]]) {
        self.rows = rows
    }

    /// Every key, in row order.
    public var keys: [FullKeyboardKey] { rows.flatMap { $0 } }

    /// The keys that send something to the PC (every key except Hide).
    public var sendingKeys: [FullKeyboardKey] { keys.filter { $0.kind != .hide } }

    public func key(id: String) -> FullKeyboardKey? {
        keys.first { $0.id == id }
    }

    /// Android's full keyboard: 6 rows, 80 keys (79 that send, plus Hide). Android's layout file
    /// also holds two commented-out keys (a second Alt and Ctrl); they aren't in the keyboard.
    public static let android = FullKeyboardLayout(rows: [
        // Row 0
        [
            k("esc", "ESC", vk: 0x1B, android: 111, weight: 150, special: true, after: 5),
            k("f1", "F1", vk: 0x70, android: 131), k("f2", "F2", vk: 0x71, android: 132),
            k("f3", "F3", vk: 0x72, android: 133), k("f4", "F4", vk: 0x73, android: 134),
            k("f5", "F5", vk: 0x74, android: 135), k("f6", "F6", vk: 0x75, android: 136),
            k("f7", "F7", vk: 0x76, android: 137), k("f8", "F8", vk: 0x77, android: 138),
            k("f9", "F9", vk: 0x78, android: 139), k("f10", "F10", vk: 0x79, android: 140),
            k("f11", "F11", vk: 0x7A, android: 141), k("f12", "F12", vk: 0x7B, android: 142),
            k("ins", "Ins", vk: 0x2D, android: 124, special: true, before: 5),
            k("del", "Del", vk: 0x2E, android: 112, special: true),
        ],
        // Row 1
        [
            k("grave", "`", shifted: "~", vk: 0xC0, android: 68, weight: 90),
            k("1", "1", vk: 0x31, android: 8), k("2", "2", vk: 0x32, android: 9),
            k("3", "3", vk: 0x33, android: 10), k("4", "4", vk: 0x34, android: 11),
            k("5", "5", vk: 0x35, android: 12), k("6", "6", vk: 0x36, android: 13),
            k("7", "7", vk: 0x37, android: 14), k("8", "8", vk: 0x38, android: 15),
            k("9", "9", vk: 0x39, android: 16), k("0", "0", vk: 0x30, android: 7),
            k("minus", "-", shifted: "_", vk: 0xBD, android: 69),
            k("equals", "=", shifted: "+", vk: 0xBB, android: 70),
            k("backspace", "Back", vk: 0x08, android: 67, weight: 150, special: true),
        ],
        // Row 2
        [
            k("tab", "Tab", vk: 0x09, android: 61, weight: 140, special: true),
            k("q", "Q", vk: 0x51, android: 45), k("w", "W", vk: 0x57, android: 51),
            k("e", "E", vk: 0x45, android: 33), k("r", "R", vk: 0x52, android: 46),
            k("t", "T", vk: 0x54, android: 48), k("y", "Y", vk: 0x59, android: 53),
            k("u", "U", vk: 0x55, android: 49), k("i", "I", vk: 0x49, android: 37),
            k("o", "O", vk: 0x4F, android: 43), k("p", "P", vk: 0x50, android: 44),
            k("lbracket", "[", shifted: "{", vk: 0xDB, android: 71),
            k("rbracket", "]", shifted: "}", vk: 0xDD, android: 72),
            k("backslash", "\\", shifted: "|", vk: 0xDC, android: 73),
        ],
        // Row 3
        [
            k("caps", "Caps", vk: 0x14, android: 115, weight: 160, kind: .toggle, special: true),
            k("a", "A", vk: 0x41, android: 29), k("s", "S", vk: 0x53, android: 47),
            k("d", "D", vk: 0x44, android: 32), k("f", "F", vk: 0x46, android: 34),
            k("g", "G", vk: 0x47, android: 35), k("h", "H", vk: 0x48, android: 36),
            k("j", "J", vk: 0x4A, android: 38), k("k", "K", vk: 0x4B, android: 39),
            k("l", "L", vk: 0x4C, android: 40),
            k("semicolon", ";", shifted: ":", vk: 0xBA, android: 74),
            k("quote", "'", shifted: "\"", vk: 0xDE, android: 75),
            k("enter", "Enter", vk: 0x0D, android: 66, weight: 160, special: true),
        ],
        // Row 4
        [
            k("shift", "Shift", vk: 0xA0, android: 59, weight: 160, kind: .modifier, mask: KeyModifier.shift),
            k("z", "Z", vk: 0x5A, android: 54), k("x", "X", vk: 0x58, android: 52),
            k("c", "C", vk: 0x43, android: 31), k("v", "V", vk: 0x56, android: 50),
            k("b", "B", vk: 0x42, android: 30), k("n", "N", vk: 0x4E, android: 42),
            k("m", "M", vk: 0x4D, android: 41),
            k("comma", ",", shifted: "<", vk: 0xBC, android: 55),
            k("period", ".", shifted: ">", vk: 0xBE, android: 56),
            k("slash", "/", shifted: "?", vk: 0xBF, android: 76),
            k("up", "\u{2191}", vk: 0x26, android: 19, weight: 103, special: true),
            k("hide", "Hide\nKBD", vk: 0, android: 0, weight: 103, kind: .hide, special: true),
        ],
        // Row 5
        [
            k("ctrl", "Ctrl", vk: 0xA2, android: 113, weight: 105, kind: .modifier, mask: KeyModifier.ctrl),
            k("win", "Win", vk: 0x5B, android: 117, weight: 105, kind: .modifier, mask: KeyModifier.meta),
            k("alt", "Alt", vk: 0xA4, android: 57, weight: 105, kind: .modifier, mask: KeyModifier.alt),
            k("space", "___", vk: 0x20, android: 62, weight: 310, special: true, before: 5, after: 5),
            k("home", "Home", vk: 0x24, android: 122, weight: 98, special: true),
            k("end", "End", vk: 0x23, android: 123, weight: 98, special: true),
            k("pgup", "PgUp", vk: 0x21, android: 92, weight: 98, special: true),
            k("pgdn", "PgDn", vk: 0x22, android: 93, weight: 98, special: true),
            k("left", "\u{2190}", vk: 0x25, android: 21, special: true),
            k("down", "\u{2193}", vk: 0x28, android: 20, special: true),
            k("right", "\u{2192}", vk: 0x27, android: 22, special: true),
        ],
    ].enumerated().map { rowIndex, row in row.map { $0.placed(inRow: rowIndex) } })

    /// Builds one key. `special` marks Android's "special" keys, which get no popup (modifiers
    /// always count as special). Row numbers are filled in afterwards.
    private static func k(_ id: String, _ label: String, shifted: String? = nil, vk: Int, android: Int,
                          weight: Int = 100, kind: FullKeyboardKeyKind = .normal, mask: Int = 0,
                          special: Bool = false, before: Int = 0, after: Int = 0) -> FullKeyboardKey {
        FullKeyboardKey(id: id, label: label, shiftedLabel: shifted, virtualKey: vk, androidKeyCode: android,
                        weight: weight, kind: kind, row: 0, marginBefore: before, marginAfter: after,
                        modifierMask: mask, isSpecial: special || kind == .modifier)
    }
}

private extension FullKeyboardKey {
    func placed(inRow row: Int) -> FullKeyboardKey {
        FullKeyboardKey(id: id, label: label, shiftedLabel: shiftedLabel, virtualKey: virtualKey,
                        androidKeyCode: androidKeyCode, weight: weight, kind: kind, row: row,
                        marginBefore: marginBefore, marginAfter: marginAfter, modifierMask: modifierMask,
                        isSpecial: isSpecial)
    }
}
