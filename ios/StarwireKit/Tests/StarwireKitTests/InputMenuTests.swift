import XCTest
@testable import StarwireKit

final class InputMenuTests: XCTestCase {
    private func pad(_ buttons: Int, number: Int = 0) -> ControllerState {
        ControllerState(number: number, activeMask: 1, buttons: buttons)
    }

    private func sent(_ outcomes: [MenuTrigger.Outcome]) -> [Int] {
        outcomes.compactMap { if case .send(let s) = $0 { return s.buttons } else { return nil } }
    }

    func testHoldingSelectOpensTheMenuWithoutSendingSelect() {
        let trigger = MenuTrigger(button: .select, holdMilliseconds: 1500)
        XCTAssertEqual(sent(trigger.update(pad(GamepadButton.back), now: 0)), [0], "Select is held back")
        XCTAssertEqual(trigger.nextDeadline, 1.5)
        XCTAssertEqual(trigger.tick(now: 1.49), [])
        XCTAssertEqual(trigger.tick(now: 1.5), [.send(ControllerState(number: 0, activeMask: 1)), .openMenu])
        // Letting go after the menu opened sends nothing new for Select
        XCTAssertEqual(sent(trigger.update(pad(GamepadButton.back | GamepadButton.a), now: 2)), [GamepadButton.a])
        XCTAssertEqual(sent(trigger.update(pad(0), now: 2.1)), [0])
        XCTAssertNil(trigger.nextDeadline)
    }

    func testTappingSelectSendsAShortPressOnRelease() {
        let trigger = MenuTrigger(button: .select)
        XCTAssertEqual(sent(trigger.update(pad(GamepadButton.back), now: 0)), [0])
        XCTAssertEqual(sent(trigger.update(pad(0), now: 0.3)), [GamepadButton.back])
        XCTAssertEqual(trigger.nextDeadline!, 0.325, accuracy: 1e-9)
        XCTAssertEqual(sent(trigger.tick(now: 0.325)), [0])
        XCTAssertEqual(trigger.tick(now: 5), [], "no menu after a tap")
    }

    func testSelectWithAnotherButtonIsACombo() {
        let trigger = MenuTrigger(button: .select)
        _ = trigger.update(pad(GamepadButton.back), now: 0)
        XCTAssertEqual(sent(trigger.update(pad(GamepadButton.back | GamepadButton.a), now: 0.2)), [GamepadButton.back | GamepadButton.a])
        XCTAssertEqual(trigger.tick(now: 5), [])
        XCTAssertEqual(sent(trigger.update(pad(GamepadButton.a), now: 5)), [GamepadButton.a])
    }

    func testBumpersReachThePCWhileTiming() {
        let trigger = MenuTrigger(button: .lbRb, holdMilliseconds: 500)
        XCTAssertEqual(sent(trigger.update(pad(GamepadButton.leftBumper), now: 0)), [GamepadButton.leftBumper])
        XCTAssertNil(trigger.nextDeadline)
        let both = GamepadButton.leftBumper | GamepadButton.rightBumper
        XCTAssertEqual(sent(trigger.update(pad(both), now: 0.1)), [both])
        XCTAssertEqual(trigger.nextDeadline!, 0.6, accuracy: 1e-9)
        XCTAssertEqual(trigger.tick(now: 0.6), [.send(ControllerState(number: 0, activeMask: 1)), .openMenu])
        XCTAssertEqual(sent(trigger.update(pad(both), now: 0.7)), [0], "the held bumpers stay away from the PC")
    }

    func testReleasingABumperEarlyCancels() {
        let trigger = MenuTrigger(button: .lbRb, holdMilliseconds: 500)
        _ = trigger.update(pad(GamepadButton.leftBumper | GamepadButton.rightBumper), now: 0)
        _ = trigger.update(pad(GamepadButton.leftBumper), now: 0.2)
        XCTAssertEqual(trigger.tick(now: 1), [])
    }

    func testOpeningReleasesEveryController() {
        let trigger = MenuTrigger(button: .start, holdMilliseconds: 1000)
        _ = trigger.update(ControllerState(number: 1, activeMask: 3, buttons: GamepadButton.a, leftX: 9000), now: 0)
        _ = trigger.update(ControllerState(number: 0, activeMask: 3, buttons: GamepadButton.start), now: 0.1)
        XCTAssertEqual(trigger.tick(now: 1.1), [.send(ControllerState(number: 0, activeMask: 3)),
                                                 .send(ControllerState(number: 1, activeMask: 3)), .openMenu])
    }

    func testSettingsValues() {
        let fromSettings = MenuTrigger(setting: "guide", holdSetting: "3000")
        XCTAssertEqual(fromSettings.button, .guide)
        XCTAssertEqual(fromSettings.holdDuration, 3)
        let fallback = MenuTrigger(setting: "nonsense", holdSetting: "7")
        XCTAssertEqual(fallback.button, .select)
        XCTAssertEqual(fallback.holdDuration, 1.5)
        XCTAssertEqual(MenuTriggerButton.lbRb.title, "LB + RB")
    }

    func testMainPageInAndroidsOrderWithoutWhatVibeshineLacks() {
        var state = StreamMenuState()
        let ids = StreamMenu.items(on: .main, state: state).map(\.id)
        XCTAssertEqual(ids, ["keyboard", "full_keyboard", "mouse_emulation", "stats", "guide", "shortcuts", "monitors", "bitrate",
                             "touch_mode", "pan_zoom", "sensitivity", "task_manager", "onscreen_controls", "edit_controls",
                             "floating_button"])
        state.showFixHostCursor = true
        state.statsShown = true
        let items = StreamMenu.items(on: .main, state: state)
        XCTAssertEqual(items[9].id, "fix_host_cursor")
        XCTAssertEqual(items.first { $0.id == "stats" }?.isOn, true)
        XCTAssertNil(items.first { $0.title.contains("Clipboard") })
    }

    func testCustomCommandsFollowTheTiles() {
        var state = StreamMenuState()
        state.customCommands = [CustomCommand(id: "c1", name: "Save", iconName: "Save",
                                              keys: KeyCombination(ctrl: true, androidKeyCode: 47), after: .closeMenu)]
        let last = StreamMenu.items(on: .main, state: state).last!
        XCTAssertEqual(last.id, "command_c1")
        XCTAssertTrue(last.closesMenu)
    }

    func testShortcutAndMonitorPages() {
        let shortcuts = StreamMenu.items(on: .shortcuts, state: StreamMenuState())
        XCTAssertEqual(shortcuts.count, 15)
        XCTAssertEqual(shortcuts.first?.title, "Esc")
        XCTAssertEqual(shortcuts.last?.action, .back)
        let monitors = StreamMenu.items(on: .monitors, state: StreamMenuState())
        XCTAssertEqual(monitors.map(\.title), ["Monitor 1", "Monitor 2", "Monitor 3", "Monitor 4", "Monitor 5", "Monitor 6", "Back"])
        XCTAssertEqual(StreamMenu.bar.map(\.title), ["Close (B)", "Quit Session", "Disconnect"])
        XCTAssertEqual(StreamMenu.detail(height: 1640, fps: 60), "1640p · 60 FPS")
    }

    func testFloatingButtonPlacement() {
        let landscape = CGSize(width: 1180, height: 820)
        XCTAssertFalse(FloatingButtonPlacement.isPortrait(landscape))
        XCTAssertTrue(FloatingButtonPlacement.isPortrait(CGSize(width: 820, height: 1180)))
        XCTAssertEqual(FloatingButtonPlacement.origin(fraction: nil, screen: landscape), CGPoint(x: 16, y: 24))
        let fraction = FloatingButtonPlacement.fraction(origin: CGPoint(x: 570, y: 780), screen: landscape)
        XCTAssertEqual(fraction, CGPoint(x: 0.5, y: 1))
        XCTAssertEqual(FloatingButtonPlacement.origin(fraction: fraction, screen: landscape), CGPoint(x: 570, y: 780))
        // Off screen is clamped
        XCTAssertEqual(FloatingButtonPlacement.fraction(origin: CGPoint(x: -50, y: 5000), screen: landscape), CGPoint(x: 0, y: 1))
        XCTAssertEqual(FloatingButtonPlacement.keys(portrait: true).x, "floating_button_portrait_x")
    }
}
