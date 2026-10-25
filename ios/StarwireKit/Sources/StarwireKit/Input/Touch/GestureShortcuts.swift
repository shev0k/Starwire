import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Taps with four or five fingers as shortcuts (open the keyboard, the menu and so on), in every
// touch mode, including multi-touch passthrough. New for the iOS client. VoidLink opens its
// keyboard with a three, four or five-finger tap (its CustomTapGestureRecognizer, GPL-3.0); only
// the idea is taken.
//
// In multi-touch the fingers go to the PC as they land, so a shortcut can't wait to be sure. When
// the fourth finger lands soon after the first, the gesture is claimed: every touch on the PC is
// cancelled (Windows makes no click from a cancelled touch) and nothing more goes until all
// fingers are up. If they lift quickly without moving much, the shortcut runs. A slow or moving
// four-finger gesture is still kept from the PC, which only loses four-finger touch gestures.
//
// iPadOS uses four and five-finger swipes and pinches for its own gestures when "Multitasking
// and gestures" is on, so the shortcuts are taps only.

/// What a gesture does. Saved by raw value.
public enum GestureAction: String, CaseIterable, Sendable {
    case none
    case menu
    case fullKeyboard = "full_keyboard"
    case systemKeyboard = "system_keyboard"
    case onScreenControls = "onscreen_controls"
    case stats
    case panZoom = "pan_zoom"
    case menuButton = "menu_button"

    public var title: String {
        switch self {
        case .none: return "Nothing"
        case .menu: return "Open the stream menu"
        case .fullKeyboard: return "Show or hide the full keyboard"
        case .systemKeyboard: return "Open the system keyboard"
        case .onScreenControls: return "Show or hide the on-screen controls"
        case .stats: return "Show or hide the statistics"
        case .panZoom: return "Turn pan and zoom on or off"
        case .menuButton: return "Show or hide the menu button"
        }
    }
}

public struct GestureSettings: Equatable, Sendable {
    public static let threeFingerKey = "list_gesture_three_finger_tap"
    public static let fourFingerKey = "list_gesture_four_finger_tap"
    public static let fiveFingerKey = "list_gesture_five_finger_tap"

    /// Outside multi-touch only: there three fingers belong to the PC (Android's menu tap)
    public var threeFingerTap: GestureAction = .menu
    public var fourFingerTap: GestureAction = .fullKeyboard
    public var fiveFingerTap: GestureAction = .menu

    public init(threeFingerTap: GestureAction = .menu, fourFingerTap: GestureAction = .fullKeyboard,
                fiveFingerTap: GestureAction = .menu) {
        self.threeFingerTap = threeFingerTap
        self.fourFingerTap = fourFingerTap
        self.fiveFingerTap = fiveFingerTap
    }

    public init(store: SettingsStore) {
        func read(_ key: String, _ fallback: GestureAction) -> GestureAction {
            if case .string(let value)? = store.value(key), let action = GestureAction(rawValue: value) { return action }
            return fallback
        }
        threeFingerTap = read(Self.threeFingerKey, .menu)
        fourFingerTap = read(Self.fourFingerKey, .fullKeyboard)
        fiveFingerTap = read(Self.fiveFingerKey, .menu)
    }

    public func action(fingers: Int) -> GestureAction {
        switch fingers {
        case 3: return threeFingerTap
        case 4: return fourFingerTap
        case 5...: return fiveFingerTap
        default: return .none
        }
    }
}

/// Watches the fingers for four and five-finger taps.
public final class GestureShortcuts {
    /// The fourth finger must land this soon after the first
    public static let landWindow: TimeInterval = 0.25
    /// All fingers must be up this soon after the first landed
    public static let tapTime: TimeInterval = 0.4
    /// A finger moving further than this (points) makes it not a tap
    public static let maxMove: CGFloat = 30

    public enum Outcome: Equatable, Sendable {
        /// Nothing to do: pass the touch on
        case pass
        /// The gesture was just claimed: cancel what the fingers did on the PC, then drop touches
        case claim
        /// Claimed: drop this touch
        case swallow
        /// The tap is complete: run this, and drop the touch
        case fire(GestureAction)
    }

    public var settings: GestureSettings
    private var firstDown: TimeInterval?
    private var starts: [Int: CGPoint] = [:]
    private var most = 0
    private var claimed = false
    private var spoiled = false

    public init(settings: GestureSettings = GestureSettings()) {
        self.settings = settings
    }

    /// True while a claimed gesture's fingers are down
    public var isClaimed: Bool { claimed }

    public func handle(_ action: TouchAction, at time: TimeInterval) -> Outcome {
        switch action {
        case .down(let index, let pointers):
            if pointers.count == 1 {
                reset()
                firstDown = time
            }
            starts[pointers[index].id] = pointers[index].point
            most = max(most, pointers.count)
            if !claimed, pointers.count >= 4, let first = firstDown, time - first <= Self.landWindow,
               settings.action(fingers: 4) != .none || settings.action(fingers: 5) != .none {
                claimed = true
                return .claim
            }
            return claimed ? .swallow : .pass
        case .move(let pointers):
            for pointer in pointers {
                if let start = starts[pointer.id], hypot(pointer.point.x - start.x, pointer.point.y - start.y) > Self.maxMove {
                    spoiled = true
                }
            }
            return claimed ? .swallow : .pass
        case .up(_, let pointers):
            guard claimed else {
                if pointers.count == 1 { reset() }
                return .pass
            }
            if pointers.count == 1 {
                let quick = firstDown.map { time - $0 <= Self.tapTime } ?? false
                let action = quick && !spoiled ? settings.action(fingers: most) : .none
                reset()
                return action == .none ? .swallow : .fire(action)
            }
            return .swallow
        case .cancel:
            let wasClaimed = claimed
            reset()
            return wasClaimed ? .swallow : .pass
        }
    }

    private func reset() {
        firstDown = nil
        starts.removeAll()
        most = 0
        claimed = false
        spoiled = false
    }
}
