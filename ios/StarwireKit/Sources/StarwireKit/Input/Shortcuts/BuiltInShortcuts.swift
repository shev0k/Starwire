import Foundation

// Ported from Starwire for Android (GPL-3.0): OverlayMenuView.java (SHORTCUTS, TASK_MANAGER_KEYS)
// and the overlay_menu_send_* and overlay_menu_task_manager strings in strings.xml.

/// The shortcuts on the stream menu's Shortcuts page, in Android's order, plus Task Manager,
/// which Android puts on the main page.
public enum BuiltInShortcuts {
    // Windows virtual-key codes, as OverlayMenuView.java names them
    static let tab = 0x09
    static let enter = 0x0D
    static let escape = 0x1B
    static let left = 0x25
    static let b = 0x42
    static let d = 0x44
    static let g = 0x47
    static let v = 0x56
    static let lwin = 0x5B
    static let f1 = 0x70
    static let f4 = 0x73
    static let f11 = 0x7A
    static let f12 = 0x7B
    static let lshift = 0xA0
    static let lcontrol = 0xA2
    static let lmenu = 0xA4

    /// The 14 shortcuts of the Shortcuts page. Imported shortcuts follow them on that page.
    public static let all: [Shortcut] = [
        Shortcut(id: "esc", name: "Esc", keys: [escape]),
        Shortcut(id: "f11", name: "F11", keys: [f11]),
        Shortcut(id: "alt-f4", name: "Alt+F4", keys: [lmenu, f4]),
        Shortcut(id: "alt-enter", name: "Alt+Enter", keys: [lmenu, enter]),
        Shortcut(id: "ctrl-v", name: "Ctrl+V", keys: [lcontrol, v]),
        Shortcut(id: "win", name: "Win", keys: [lwin]),
        Shortcut(id: "win-d", name: "Win+D", keys: [lwin, d]),
        Shortcut(id: "win-g", name: "Win+G", keys: [lwin, g]),
        Shortcut(id: "ctrl-alt-tab", name: "Ctrl+Alt+Tab", keys: [lcontrol, lmenu, tab]),
        Shortcut(id: "shift-tab", name: "Shift+Tab", keys: [lshift, tab]),
        Shortcut(id: "win-shift-left", name: "Win+Shift+Left", keys: [lwin, lshift, left]),
        Shortcut(id: "ctrl-alt-shift-f1", name: "Ctrl+Alt+Shift+F1", keys: [lcontrol, lmenu, lshift, f1]),
        Shortcut(id: "ctrl-alt-shift-f12", name: "Ctrl+Alt+Shift+F12", keys: [lcontrol, lmenu, lshift, f12]),
        Shortcut(id: "win-alt-b", name: "Win+Alt+B", keys: [lwin, lmenu, b]),
    ]

    /// Ctrl+Shift+Esc. Android has it as the "Task Manager" tile on the main page, not on the
    /// Shortcuts page.
    public static let taskManager = Shortcut(id: "task-manager", name: "Task Manager", keys: [lcontrol, lshift, escape])
}
