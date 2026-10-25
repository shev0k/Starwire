import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// The stream menu's pages and items, from Starwire for Android's OverlayMenuView (GPL-3.0), with
// what Vibeshine lacks left out: Send Clipboard, Get Clipboard and PC Commands (no
// /actions/clipboard or server commands), and Rotate (Android only). The app draws the panel; this
// says what is on it, in Android's order, and what each item does.

public enum StreamMenuPage: Equatable, Sendable {
    case main, shortcuts, monitors
}

/// What an item does when chosen.
public enum StreamMenuAction: Equatable, Sendable {
    /// The system keyboard, for typing text
    case systemKeyboard
    case toggleFullKeyboard
    case toggleMouseEmulation
    case toggleStats
    /// Presses the controller's Guide button for 100 ms
    case guide
    case openPage(StreamMenuPage)
    case bitrate
    case touchMode
    case fixHostCursor
    case togglePanZoom
    case toggleSensitivity
    case keys(Shortcut)
    case toggleOnScreenControls
    case editOnScreenControls
    case toggleFloatingButton
    case customCommand(CustomCommand)
    case back
    case close
    case quit
    case disconnect
}

public struct StreamMenuItem: Equatable, Sendable {
    public var id: String
    public var title: String
    /// An SF Symbol name for the app to draw
    public var symbol: String
    public var action: StreamMenuAction
    /// On or off for a switch tile; nil for a plain tile
    public var isOn: Bool?
    /// Whether choosing it closes the menu (Android's behaviour per item)
    public var closesMenu: Bool
}

/// The state the menu shows, from the stream.
public struct StreamMenuState: Equatable, Sendable {
    public var fullKeyboardShown = false
    public var mouseEmulation = false
    public var statsShown = false
    public var panZoom = false
    /// Custom trackpad sensitivity in use (`seekbar_touch_sensitivity`, when not 100)
    public var sensitivityOn = false
    public var sensitivityPercent = 100
    public var onScreenControlsShown = false
    public var floatingButtonShown = true
    /// Android shows Fix PC Cursor when hiding the cursor is set up, or the cursor was found hidden
    public var showFixHostCursor = false
    public var customCommands: [CustomCommand] = []
    public var importedShortcuts: [Shortcut] = []
    /// The stream's height and frame rate for the header ("1080p · 60 FPS")
    public var streamHeight = 0
    public var fps = 0

    public init() {}
}

public enum StreamMenu {
    public static let title = "Stream menu"

    /// The header's detail line, as Android's `cg_chip_resolution`.
    public static func detail(height: Int, fps: Int) -> String {
        height > 0 ? "\(height)p · \(fps) FPS" : ""
    }

    public static func items(on page: StreamMenuPage, state: StreamMenuState) -> [StreamMenuItem] {
        switch page {
        case .main:
            var items = [
                StreamMenuItem(id: "keyboard", title: "Keyboard (Y)", symbol: "keyboard", action: .systemKeyboard, isOn: nil,
                               closesMenu: true),
                StreamMenuItem(id: "full_keyboard", title: "Full Keyboard", symbol: "keyboard.badge.ellipsis",
                               action: .toggleFullKeyboard, isOn: state.fullKeyboardShown, closesMenu: false),
                StreamMenuItem(id: "mouse_emulation", title: "Mouse (X)", symbol: "computermouse", action: .toggleMouseEmulation,
                               isOn: state.mouseEmulation, closesMenu: false),
                StreamMenuItem(id: "stats", title: "Stats (RB)", symbol: "speedometer", action: .toggleStats, isOn: state.statsShown,
                               closesMenu: false),
                StreamMenuItem(id: "guide", title: "Guide (▶)", symbol: "house.circle", action: .guide, isOn: nil, closesMenu: true),
                StreamMenuItem(id: "shortcuts", title: "Shortcuts", symbol: "command", action: .openPage(.shortcuts), isOn: nil,
                               closesMenu: false),
                StreamMenuItem(id: "monitors", title: "Monitors", symbol: "display.2", action: .openPage(.monitors), isOn: nil,
                               closesMenu: false),
                StreamMenuItem(id: "bitrate", title: "Bitrate", symbol: "bolt", action: .bitrate, isOn: nil, closesMenu: true),
                StreamMenuItem(id: "touch_mode", title: "Touch Mode", symbol: "hand.tap", action: .touchMode, isOn: nil,
                               closesMenu: true),
            ]
            if state.showFixHostCursor {
                items.append(StreamMenuItem(id: "fix_host_cursor", title: "Fix PC Cursor", symbol: "cursorarrow.rays",
                                            action: .fixHostCursor, isOn: nil, closesMenu: false))
            }
            items += [
                StreamMenuItem(id: "pan_zoom", title: "Pan/Zoom", symbol: "arrow.up.left.and.arrow.down.right",
                               action: .togglePanZoom, isOn: state.panZoom, closesMenu: false),
                StreamMenuItem(id: "sensitivity", title: "Sensitivity", symbol: "slider.horizontal.3", action: .toggleSensitivity,
                               isOn: state.sensitivityOn, closesMenu: false),
                StreamMenuItem(id: "task_manager", title: "Task Manager", symbol: "list.bullet.rectangle",
                               action: .keys(BuiltInShortcuts.taskManager), isOn: nil, closesMenu: true),
                StreamMenuItem(id: "onscreen_controls", title: "On-screen Controls", symbol: "gamecontroller",
                               action: .toggleOnScreenControls, isOn: state.onScreenControlsShown, closesMenu: false),
                StreamMenuItem(id: "edit_controls", title: "Edit Controls", symbol: "square.and.pencil",
                               action: .editOnScreenControls, isOn: nil, closesMenu: true),
                StreamMenuItem(id: "floating_button", title: "Menu Button", symbol: "circle.grid.2x2",
                               action: .toggleFloatingButton, isOn: state.floatingButtonShown, closesMenu: false),
            ]
            for command in state.customCommands {
                items.append(StreamMenuItem(id: "command_\(command.id)", title: command.displayName, symbol: "keyboard",
                                            action: .customCommand(command), isOn: nil,
                                            closesMenu: command.after == .closeMenu))
            }
            return items
        case .shortcuts:
            let all = BuiltInShortcuts.all + state.importedShortcuts
            return all.enumerated().map { index, shortcut in
                StreamMenuItem(id: "shortcut_\(index)", title: shortcut.name, symbol: "", action: .keys(shortcut), isOn: nil,
                               closesMenu: true)
            } + [backItem]
        case .monitors:
            return (1...6).map { n in
                StreamMenuItem(id: "monitor_\(n)", title: "Monitor \(n)", symbol: "display", action: .keys(MonitorSwitch.shortcut(monitor: n)!),
                               isOn: nil, closesMenu: true)
            } + [backItem]
        }
    }

    static let backItem = StreamMenuItem(id: "back", title: "Back", symbol: "chevron.left", action: .back, isOn: nil, closesMenu: false)

    /// The bar under the tiles.
    public static let bar = [
        StreamMenuItem(id: "close", title: "Close (B)", symbol: "xmark", action: .close, isOn: nil, closesMenu: true),
        StreamMenuItem(id: "quit", title: "Quit Session", symbol: "power", action: .quit, isOn: nil, closesMenu: true),
        StreamMenuItem(id: "disconnect", title: "Disconnect", symbol: "rectangle.portrait.and.arrow.right", action: .disconnect,
                       isOn: nil, closesMenu: true),
    ]

    /// Android's bitrate choices in the picker, in Mbps.
    public static let bitrateChoicesMbps = [5, 10, 20, 30, 50, 80, 100, 150, 200, 300, 500]

    /// Toasts, in Android's words.
    public static func panZoomNotice(on: Bool) -> String {
        on ? "Pan/Zoom on: pinch to zoom, drag to pan, double-tap to reset" : "Pan/Zoom off"
    }

    public static func sensitivityNotice(on: Bool, percent: Int) -> String {
        on ? "Touch sensitivity: \(percent)%" : "Touch sensitivity: default (100%)"
    }

    public static func mouseEmulationNotice(on: Bool) -> String {
        "Mouse emulation is: \(on ? "ON" : "OFF")"
    }

    public static let hostCursorFixNotice = "Switched the PC cursor. If it's still wrong, tap Fix PC Cursor again."
}

/// Where the floating menu button sits, saved per orientation as a fraction (0 to 1) of the
/// room it can move in, as Android's FloatingButton does.
public struct FloatingButtonPlacement: Equatable, Sendable {
    public static let size: CGFloat = 40
    public static let idleAlpha: CGFloat = 0.55
    /// Pixels the finger must move before a touch is a drag, not a tap
    public static let dragThresholdPixels: CGFloat = 10
    public static let landscapeXKey = "floating_button_landscape_x"
    public static let landscapeYKey = "floating_button_landscape_y"
    public static let portraitXKey = "floating_button_portrait_x"
    public static let portraitYKey = "floating_button_portrait_y"
    /// The spot before anything is saved: 16 points from the leading edge, 24 from the top
    public static let defaultOrigin = CGPoint(x: 16, y: 24)

    public static func isPortrait(_ screen: CGSize) -> Bool {
        screen.height > screen.width
    }

    /// The button's top-left corner for a saved fraction, or the default spot.
    public static func origin(fraction: CGPoint?, screen: CGSize) -> CGPoint {
        guard let fraction, fraction.x.isFinite, fraction.y.isFinite else { return defaultOrigin }
        let room = CGSize(width: max(screen.width - size, 0), height: max(screen.height - size, 0))
        return CGPoint(x: min(max(fraction.x, 0), 1) * room.width, y: min(max(fraction.y, 0), 1) * room.height)
    }

    /// The fraction to save for a button dragged to `origin`, clamped to the screen.
    public static func fraction(origin: CGPoint, screen: CGSize) -> CGPoint {
        let room = CGSize(width: max(screen.width - size, 1), height: max(screen.height - size, 1))
        return CGPoint(x: min(max(origin.x / room.width, 0), 1), y: min(max(origin.y / room.height, 0), 1))
    }

    public static func keys(portrait: Bool) -> (x: String, y: String) {
        portrait ? (portraitXKey, portraitYKey) : (landscapeXKey, landscapeYKey)
    }
}
