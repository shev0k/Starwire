import Foundation

// Opening the stream menu by holding a controller button, as Starwire for Android's
// ControllerHandler does it (GPL-3.0, checkOverlayTrigger and the overlay trigger hold-back):
//
// - Select, Start or Guide: the press is held back from the PC while the timer runs. Released
//   early (a tap), the PC gets a 25 ms press at the moment of release. Pressed together with
//   another button, the held press joins that button's packet and the timer stops.
// - LB+RB: both bumpers reach the PC normally; the timer starts when the second goes down.
// - When the hold time is reached, every controller is sent as released and the menu opens.
//   The trigger buttons stay held back until they are let go.

public enum MenuTriggerButton: String, CaseIterable, Sendable {
    case select, start, guide, lbRb = "lb_rb"

    /// The `GamepadButton` flags that make up the trigger
    public var flags: Int {
        switch self {
        case .select: return GamepadButton.back
        case .start: return GamepadButton.start
        case .guide: return GamepadButton.guide
        case .lbRb: return GamepadButton.leftBumper | GamepadButton.rightBumper
        }
    }

    /// Android's names in the settings list and the "Hold ... to open menu" hint
    public var title: String {
        switch self {
        case .select: return "Select"
        case .start: return "Start"
        case .guide: return "Guide"
        case .lbRb: return "LB + RB"
        }
    }

    var holdsBack: Bool { self != .lbRb }
}

public final class MenuTrigger {
    public static let tapReleaseDelay: TimeInterval = 0.025
    /// `overlay_hold_duration` choices, in milliseconds
    public static let holdChoicesMilliseconds = [500, 1000, 1500, 2000, 2500, 3000]
    public static let defaultHoldMilliseconds = 1500

    public enum Outcome: Equatable, Sendable {
        /// Send this controller's state to the PC
        case send(ControllerState)
        /// Open the menu (every controller has just been sent as released)
        case openMenu
    }

    public var button: MenuTriggerButton
    public var holdDuration: TimeInterval

    private var deadline: TimeInterval?
    /// The controller whose trigger is running
    private var timingController: Int?
    /// Per controller: the trigger press held back from the PC
    private var heldBack: [Int: Bool] = [:]
    /// Per controller: trigger buttons kept from the PC after the menu opened, until let go
    private var suppressed: [Int: Int] = [:]
    /// Per controller: the last state as the controller reported it, and as the PC got it
    private var lastRaw: [Int: ControllerState] = [:]
    private var tapRelease: [Int: (time: TimeInterval, state: ControllerState)] = [:]

    public init(button: MenuTriggerButton = .select, holdMilliseconds: Int = MenuTrigger.defaultHoldMilliseconds) {
        self.button = button
        holdDuration = TimeInterval(holdMilliseconds) / 1000
    }

    /// Settings values to a trigger; unknown values fall back to Select, as on Android.
    public convenience init(setting: String?, holdSetting: String?) {
        let hold = Int(holdSetting ?? "") ?? MenuTrigger.defaultHoldMilliseconds
        self.init(button: MenuTriggerButton(rawValue: setting ?? "") ?? .select,
                  holdMilliseconds: MenuTrigger.holdChoicesMilliseconds.contains(hold) ? hold : MenuTrigger.defaultHoldMilliseconds)
    }

    public var nextDeadline: TimeInterval? {
        ([deadline].compactMap { $0 } + tapRelease.values.map(\.time)).min()
    }

    /// Takes a controller's state as it reports it, and returns what to do.
    public func update(_ raw: ControllerState, now: TimeInterval) -> [Outcome] {
        var out = tick(now: now)
        let number = raw.number
        let previous = lastRaw[number]?.buttons ?? 0
        lastRaw[number] = raw
        let trigger = button.flags
        let pressed = raw.buttons & ~previous
        var state = raw

        // After the menu opened, the trigger buttons stay away from the PC until let go
        if var kept = suppressed[number] {
            kept &= raw.buttons
            suppressed[number] = kept == 0 ? nil : kept
            state.buttons &= ~kept
            out.append(.send(state))
            return out
        }

        if button.holdsBack {
            if heldBack[number] == true {
                if raw.buttons & trigger == 0 {
                    // A tap: the press now, the release 25 ms later
                    heldBack[number] = nil
                    cancelTimer(for: number)
                    var press = state
                    press.buttons |= trigger
                    out.append(.send(press))
                    tapRelease[number] = (now + Self.tapReleaseDelay, state)
                    return out
                }
                if pressed & ~trigger != 0 {
                    // Another button joined: the trigger is part of a combo, not the menu
                    heldBack[number] = nil
                    cancelTimer(for: number)
                    out.append(.send(state))
                    return out
                }
                state.buttons &= ~trigger
                out.append(.send(state))
                return out
            }
            if pressed & trigger != 0 && raw.buttons & trigger == trigger {
                heldBack[number] = true
                startTimer(for: number, now: now)
                state.buttons &= ~trigger
                out.append(.send(state))
                return out
            }
        } else {
            if raw.buttons & trigger == trigger {
                if pressed & trigger != 0 && deadline == nil {
                    startTimer(for: number, now: now)
                }
            } else if timingController == number {
                cancelTimer(for: number)
            }
        }
        out.append(.send(state))
        return out
    }

    private func startTimer(for number: Int, now: TimeInterval) {
        deadline = now + holdDuration
        timingController = number
    }

    private func cancelTimer(for number: Int) {
        if timingController == number {
            deadline = nil
            timingController = nil
        }
    }

    /// Fires what is due: tap releases and the menu.
    public func tick(now: TimeInterval) -> [Outcome] {
        var out: [Outcome] = []
        for (number, release) in tapRelease.sorted(by: { $0.key < $1.key }) where release.time <= now {
            tapRelease[number] = nil
            var state = lastRaw[number] ?? release.state
            state.buttons &= ~button.flags
            out.append(.send(state))
        }
        if let deadline, deadline <= now {
            self.deadline = nil
            timingController = nil
            heldBack.removeAll()
            // Everything released on the PC before the menu shows
            for number in lastRaw.keys.sorted() {
                guard let raw = lastRaw[number] else { continue }
                if raw.buttons & button.flags != 0 {
                    suppressed[number] = raw.buttons & button.flags
                }
                out.append(.send(ControllerState(number: number, activeMask: raw.activeMask)))
            }
            out.append(.openMenu)
        }
        return out
    }

    /// Forgets a controller that went away.
    public func remove(controller number: Int) {
        lastRaw[number] = nil
        heldBack[number] = nil
        suppressed[number] = nil
        tapRelease[number] = nil
        cancelTimer(for: number)
    }
}
