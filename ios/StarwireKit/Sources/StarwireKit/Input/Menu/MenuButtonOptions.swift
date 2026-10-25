import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// The floating menu button's look and behaviour beyond Android's (which has on or off and a
// position): its size, how see-through it is at rest, docking to the side of the screen as a
// slim tab, and docking by itself after a while untouched. The docked tab follows VoidLink's
// auto-docking widgets and Artemis's fading control bar (both GPL-3.0); only the ideas are taken.

public struct MenuButtonOptions: Equatable, Sendable {
    public enum Style: String, CaseIterable, Sendable {
        /// A round button that sits where it was dragged
        case floating
        /// A slim tab on the left or right edge
        case edge
    }

    public enum Size: String, CaseIterable, Sendable {
        case small, medium, large

        public var points: CGFloat {
            switch self {
            case .small: return 36
            case .medium: return 44
            case .large: return 56
            }
        }
    }

    public static let styleKey = "list_menu_button_style"
    public static let sizeKey = "list_menu_button_size"
    public static let opacityKey = "seekbar_menu_button_opacity"
    public static let autoHideKey = "list_menu_button_auto_hide"
    /// Seconds before the floating button docks by itself; "off" never
    public static let autoHideChoices = ["off", "3", "5", "10"]

    public var style: Style = .floating
    public var size: Size = .medium
    /// Opacity at rest, 0.2 to 1 (Android's 0.55 is close to the default)
    public var idleOpacity: CGFloat = 0.6
    /// Seconds untouched before a floating button docks; nil never
    public var autoHide: TimeInterval?

    public init(style: Style = .floating, size: Size = .medium, idleOpacity: CGFloat = 0.6, autoHide: TimeInterval? = nil) {
        self.style = style
        self.size = size
        self.idleOpacity = idleOpacity
        self.autoHide = autoHide
    }

    public init(store: SettingsStore) {
        if case .string(let value)? = store.value(Self.styleKey), let style = Style(rawValue: value) { self.style = style }
        if case .string(let value)? = store.value(Self.sizeKey), let size = Size(rawValue: value) { self.size = size }
        if case .int(let value)? = store.value(Self.opacityKey) { idleOpacity = CGFloat(min(max(value, 20), 100)) / 100 }
        if case .string(let value)? = store.value(Self.autoHideKey), let seconds = Double(value) { autoHide = seconds }
    }
}

/// Where the docked tab sits. The tab hugs the left or right edge, inside the safe area's top and
/// bottom, at the height the button had.
public enum MenuButtonDock {
    public enum Edge: String, Sendable { case left, right }

    public static let tabWidth: CGFloat = 14
    public static let tabHeight: CGFloat = 64
    /// The tab is this much as opaque as the button at rest: it is thin, so it needs the contrast
    public static let tabOpacityFactor: CGFloat = 0.9
    /// A floating button let go this close to a side edge docks there
    public static let snapDistance: CGFloat = 24

    /// The side nearer to the button's centre.
    public static func nearestEdge(buttonFrame: CGRect, screen: CGSize) -> Edge {
        buttonFrame.midX < screen.width / 2 ? .left : .right
    }

    /// True when a button let go at `frame` is close enough to a side to dock.
    public static func snaps(buttonFrame: CGRect, screen: CGSize) -> Bool {
        buttonFrame.minX <= snapDistance || buttonFrame.maxX >= screen.width - snapDistance
    }

    /// The tab's frame on `edge`, centred on `centreY`, kept between the top and bottom insets.
    public static func tabFrame(edge: Edge, centreY: CGFloat, screen: CGSize, top: CGFloat = 0, bottom: CGFloat = 0) -> CGRect {
        let minY = top
        let maxY = max(screen.height - bottom - tabHeight, minY)
        let y = min(max(centreY - tabHeight / 2, minY), maxY)
        let x = edge == .left ? 0 : screen.width - tabWidth
        return CGRect(x: x, y: y, width: tabWidth, height: tabHeight)
    }

    /// The floating button that comes back out of a tab: beside the edge, at the tab's height.
    public static func buttonFrame(fromTab tab: CGRect, edge: Edge, size: CGFloat, screen: CGSize, margin: CGFloat = 8) -> CGRect {
        let x = edge == .left ? margin : screen.width - size - margin
        let y = min(max(tab.midY - size / 2, 0), max(screen.height - size, 0))
        return CGRect(x: x, y: y, width: size, height: size)
    }
}
