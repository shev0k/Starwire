import Foundation

// Ported from Starwire for Android (GPL-3.0): OverlayMenuView.java (MONITOR_COUNT, and the tile
// that sends Ctrl+Alt+Shift+F1 plus the monitor number) and the overlay_menu_monitor_n string.
// The idea is from Moonlit Artemis (see CoverGlowSettings.CREDITS).

/// The Monitors page: "Monitor 1" to "Monitor 6" send Ctrl+Alt+Shift+F1 to F6. The host decides
/// what those keys do; Starwire doesn't know whether it has switched.
public enum MonitorSwitch {
    public static let count = 6

    /// Windows virtual-key code of F1. Monitor n adds n - 1.
    static let f1 = 0x70

    /// The shortcut for monitor `number` (1 to 6), or nil for any other number.
    public static func shortcut(monitor number: Int) -> Shortcut? {
        guard (1...count).contains(number) else { return nil }
        return Shortcut(id: "monitor-\(number)", name: "Monitor \(number)",
                        keys: [BuiltInShortcuts.lcontrol, BuiltInShortcuts.lmenu, BuiltInShortcuts.lshift, f1 + number - 1])
    }

    /// Monitors 1 to 6, in the order of the page.
    public static var all: [Shortcut] {
        (1...count).compactMap { shortcut(monitor: $0) }
    }
}
