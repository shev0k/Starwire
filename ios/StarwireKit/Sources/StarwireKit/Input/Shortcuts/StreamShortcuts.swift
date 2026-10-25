import Foundation

// Hardware keyboard shortcuts for the stream itself, not the PC: Ctrl+Alt+Shift with M for the
// menu, S for the statistics and D to disconnect. New for the iOS client; VoidLink has the same
// idea with Ctrl+Alt+Shift (GPL-3.0), only the idea is taken. The letter never reaches the PC;
// the three modifiers do, as they are pressed, which Windows ignores on their own.

public enum StreamShortcut: String, CaseIterable, Sendable {
    case menu, stats, disconnect
}

public enum StreamShortcuts {
    /// Ctrl, Alt and Shift, and nothing else
    public static let modifiers = KeyModifier.ctrl | KeyModifier.alt | KeyModifier.shift

    /// HID usages of the letters (USB HID usage table, keyboard page)
    static let letters: [Int: StreamShortcut] = [0x10: .menu, 0x16: .stats, 0x07: .disconnect]

    /// The shortcut for a key pressed with these modifiers (`KeyModifier` flags), if any.
    public static func shortcut(hidUsage: Int, modifiers: Int) -> StreamShortcut? {
        guard modifiers == Self.modifiers else { return nil }
        return letters[hidUsage]
    }

    /// The keys, for the menu's hint: "Ctrl+Alt+Shift+M"
    public static func title(_ shortcut: StreamShortcut) -> String {
        let letter: String
        switch shortcut {
        case .menu: letter = "M"
        case .stats: letter = "S"
        case .disconnect: letter = "D"
        }
        return "Ctrl+Alt+Shift+" + letter
    }
}
