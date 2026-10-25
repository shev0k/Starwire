//
//  InputDeviceRunTests.swift
//  Starwire
//
//  Batch 3's device checks for input, on the iPad against the PC (docs/ios/mac-runbook.md): the
//  touch modes, the stream menu, the on-screen controller and its editor, the full keyboard, the
//  system keyboard and the shortcuts. What reached the PC is read from the statistics overlay's
//  "Input:" line (StarwireKit's InputTally), which counts every packet by kind and shows the
//  last one; the exact packets for each gesture are asserted by StarwireKit's unit tests.
//
//  Nothing here presses keys that change the PC (no Windows key, no Task Manager, no monitor
//  switching): the test pattern is a browser page on its own virtual display, and the owner may
//  be using the PC.
//
//  Settings, as in StreamDeviceRunTests: TEST_RUNNER_STARWIRE_APP (default "Starwire test
//  pattern"), TEST_RUNNER_STARWIRE_FPS, TEST_RUNNER_STARWIRE_CODEC, TEST_RUNNER_STARWIRE_RESOLUTION.
//

import UIKit
import XCTest

final class InputDeviceRunTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!
    private var overlay: XCUIElement!

    private var appName: String { env["STARWIRE_APP"] ?? "Starwire test pattern" }
    private let quittableApps = ["Starwire test pattern", "Starwire colour bars", "Desktop"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-StarwireStatsOverlay", "YES", "-StarwirePlayAudioOnPC", "YES"]
        if let v = env["STARWIRE_FPS"] { args += ["-StarwireFrameRate", v] }
        if let v = env["STARWIRE_CODEC"] { args += ["-StarwireCodec", v] }
        if let v = env["STARWIRE_RESOLUTION"] { args += ["-StarwireResolution", v] }
        app.launchArguments = args
        app.launch()
        record("launch arguments: \(args.joined(separator: " "))")
    }

    // MARK: Touch modes

    func testTouchModes() throws {
        try startStream()
        let screen = streamScreen
        let centre = screen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))

        // The stream starts in the gaming trackpad (checkbox_touchscreen_trackpad, on by default)
        XCTAssertTrue(waitFor("Touch: Trackpad (gaming)"), "not in the gaming trackpad at the start")
        var before = counts()
        centre.tap()
        XCTAssertTrue(waitForCount(.buttons, atLeast: before.buttons + 2), "a tap didn't click")
        XCTAssertTrue(waitFor("last button 1 up"))
        before = counts()
        centre.press(forDuration: 0.05, thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)))
        XCTAssertTrue(waitForCount(.mouse, atLeast: before.mouse + 3), "a drag didn't move the mouse")
        record("gaming trackpad: \(inputLine())")

        // Two-finger tap: right click
        before = counts()
        screen.twoFingerTap()
        XCTAssertTrue(waitForCount(.buttons, atLeast: before.buttons + 2), "a two-finger tap didn't click")
        XCTAssertTrue(waitFor("last button 3 up"), "a two-finger tap wasn't a right click")

        // Natural trackpad, from the menu
        chooseTouchMode("Trackpad (natural)")
        before = counts()
        centre.tap()
        XCTAssertTrue(waitForCount(.buttons, atLeast: before.buttons + 2), "natural trackpad: a tap didn't click")
        before = counts()
        centre.press(forDuration: 0.05, thenDragTo: screen.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)))
        XCTAssertTrue(waitForCount(.mouse, atLeast: before.mouse + 3), "natural trackpad: a drag didn't move the mouse")
        record("natural trackpad: \(inputLine())")

        // Direct touch: the cursor goes under the finger
        chooseTouchMode("Direct touch")
        before = counts()
        centre.tap()
        XCTAssertTrue(waitForCount(.buttons, atLeast: before.buttons + 2), "direct touch: a tap didn't click")
        XCTAssertGreaterThan(counts().mouse, before.mouse, "direct touch: no position before the click")
        before = counts()
        centre.press(forDuration: 1.2)
        XCTAssertTrue(waitFor("last button 3 up"), "direct touch: a long press wasn't a right click")
        record("direct touch: \(inputLine())")

        // Swapped clicks: a tap is the right button
        chooseTouchMode("Direct touch, swapped clicks")
        centre.tap()
        XCTAssertTrue(waitFor("last button 3 up"), "swapped clicks: a tap wasn't a right click")

        // The three-finger tap opens the menu in the trackpad and direct modes, without a click
        before = counts()
        openMenuWithThreeFingers()
        closeMenu()
        XCTAssertEqual(counts().buttons, before.buttons, "the three-finger tap clicked")

        // Multi-touch: fingers go to the PC as touches (Vibeshine takes them), three of them too
        chooseTouchMode("Multi-touch")
        before = counts()
        centre.tap()
        XCTAssertTrue(waitForCount(.touch, atLeast: before.touch + 2), "multi-touch: a tap wasn't sent as a touch")
        before = counts()
        screen.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        XCTAssertTrue(waitForCount(.touch, atLeast: before.touch + 6), "multi-touch: three fingers weren't sent as touches")
        XCTAssertFalse(app.descendants(matching: .any)["StreamMenu"].exists, "multi-touch: three fingers opened the menu")
        record("multi-touch: \(inputLine())")

        // Touch disabled: nothing reaches the PC
        chooseTouchMode("Touch disabled")
        before = counts()
        centre.tap()
        sleep(2)
        XCTAssertEqual(counts().total, before.total, "touch disabled still sent input")
        // With touch disabled, three fingers open the menu as they land
        openMenuWithThreeFingers()
        closeMenu()

        // Back to direct touch; pinch to zoom must not click
        chooseTouchMode("Direct touch")
        before = counts()
        screen.pinch(withScale: 2.0, velocity: 1.0)
        sleep(2)
        XCTAssertEqual(counts().buttons, before.buttons, "a pinch clicked")
        screenshot("after pinch to zoom")
        // Pan and zoom mode: a double tap resets the zoom, nothing reaches the PC
        openMenuWithThreeFingers()
        tapMenu("menu_pan_zoom")
        closeMenu()
        XCTAssertTrue(waitFor("pan and zoom"), "pan and zoom mode didn't come on")
        before = counts()
        centre.doubleTap()
        sleep(2)
        XCTAssertEqual(counts().total, before.total, "pan and zoom mode sent input")
        screenshot("after the zoom reset")
        openMenuWithThreeFingers()
        tapMenu("menu_pan_zoom")
        closeMenu()

        stopStream()
    }

    // MARK: Menu

    func testStreamMenu() throws {
        try startStream()
        // The floating button opens and closes it
        let button = app.buttons["StreamMenuButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no floating menu button")
        button.tap()
        XCTAssertTrue(app.descendants(matching: .any)["StreamMenu"].waitForExistence(timeout: 5), "the floating button didn't open the menu")
        screenshot("stream menu")
        for id in ["menu_keyboard", "menu_full_keyboard", "menu_mouse_emulation", "menu_stats", "menu_guide", "menu_shortcuts",
                   "menu_monitors", "menu_bitrate", "menu_touch_mode", "menu_pan_zoom", "menu_sensitivity", "menu_task_manager",
                   "menu_onscreen_controls", "menu_edit_controls", "menu_floating_button", "menu_close", "menu_quit", "menu_disconnect"] {
            XCTAssertTrue(app.buttons[id].exists, "no \(id) in the menu")
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Clipboard")).firstMatch.exists)
        button.tap()
        XCTAssertTrue(waitForGone(app.descendants(matching: .any)["StreamMenu"]), "the floating button didn't close the menu")

        // Dragging the button moves it and doesn't open the menu
        let start = button.frame
        // To the other side from where an earlier run left it
        let screen = app.frame
        let target = CGVector(dx: start.midX > screen.midX ? 0.1 : 0.9, dy: start.midY > screen.midY ? 0.2 : 0.7)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: target))
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["StreamMenu"].exists, "dragging the button opened the menu")
        XCTAssertNotEqual(button.frame.origin, start.origin, "the button didn't move")
        record("floating button moved from \(start.origin) to \(button.frame.origin)")

        // The Shortcuts page: Esc reaches the PC
        openMenuWithThreeFingers()
        tapMenu("menu_shortcuts")
        let esc = app.buttons.matching(NSPredicate(format: "label == %@", "Esc")).firstMatch
        XCTAssertTrue(esc.waitForExistence(timeout: 5), "no Esc on the Shortcuts page")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Win+Alt+B")).firstMatch.exists)
        let before = counts()
        esc.tap()
        XCTAssertTrue(waitForCount(.keys, atLeast: before.keys + 2), "Esc didn't reach the PC")
        XCTAssertTrue(waitFor("last key 0x1B up"))

        // Manage on the Shortcuts page: the custom commands editor and the shortcut file import
        openMenuWithThreeFingers()
        tapMenu("menu_shortcuts")
        tapMenu("menu_manage_shortcuts")
        XCTAssertTrue(app.buttons["AddCommand"].waitForExistence(timeout: 5), "no Add command in Manage")
        XCTAssertTrue(app.buttons["ImportShortcuts"].exists, "no Import from Files in Manage")
        screenshot("shortcuts and commands")
        app.buttons["ShortcutsManagerDone"].tap()
        XCTAssertTrue(waitForGone(app.buttons["AddCommand"]), "Done didn't close Manage")

        // The Monitors page lists six (not pressed: it would switch the PC's display)
        openMenuWithThreeFingers()
        tapMenu("menu_monitors")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Monitor 6")).firstMatch.waitForExistence(timeout: 5))
        tapMenu("menu_back")
        XCTAssertTrue(app.buttons["menu_keyboard"].waitForExistence(timeout: 5), "Back didn't return to the main page")

        // The Stats switch hides and shows the overlay
        tapMenu("menu_stats")
        XCTAssertTrue(waitForGone(overlay), "the Stats switch didn't hide the overlay")
        tapMenu("menu_stats")
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "the Stats switch didn't show the overlay")
        closeMenu()

        stopStream()
    }

    // MARK: On-screen controller

    func testOnScreenControls() throws {
        try startStream()
        // The controls may already show (the setting, or moonlight-ios's old one): the menu's
        // switch turns them off, then on again
        if control("A button").waitForExistence(timeout: 3) {
            openMenuWithThreeFingers()
            tapMenu("menu_onscreen_controls")
            XCTAssertEqual(app.buttons["menu_onscreen_controls"].value as? String, "Off")
            closeMenu()
            XCTAssertTrue(waitForGone(control("A button")), "the switch didn't hide the on-screen controller")
        }
        openMenuWithThreeFingers()
        tapMenu("menu_onscreen_controls")
        XCTAssertEqual(app.buttons["menu_onscreen_controls"].value as? String, "On")
        closeMenu()
        let a = control("A button")
        if !a.waitForExistence(timeout: 5) {
            record(app.debugDescription)
            screenshot("no on-screen controller")
            XCTFail("the on-screen controller didn't appear")
        }
        screenshot("on-screen controls")
        var before = counts()
        a.tap()
        XCTAssertTrue(waitForCount(.controller, atLeast: before.controller + 2), "A didn't reach the PC")
        record("A: \(inputLine())")
        before = counts()
        let stick = control("Left stick")
        stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: stick.coordinate(withNormalizedOffset: CGVector(dx: 1.5, dy: 0.5)))
        XCTAssertTrue(waitForCount(.controller, atLeast: before.controller + 2), "the left stick didn't reach the PC")
        XCTAssertTrue(waitFor("buttons 0x0"), "the controller wasn't left idle after the stick")

        // The editor: move A, save, then put the defaults back
        openMenuWithThreeFingers()
        tapMenu("menu_edit_controls")
        let done = app.buttons["OnScreenEditorDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the layout editor didn't open")
        let from = control("A button").frame
        before = counts()
        control("A button").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.2,
                                  thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)))
        screenshot("layout editor")
        done.tap()
        XCTAssertTrue(waitForGone(done))
        XCTAssertEqual(counts().controller, before.controller, "editing sent controller input")
        XCTAssertNotEqual(control("A button").frame.origin, from.origin, "A didn't move")
        record("A moved from \(from.origin) to \(control("A button").frame.origin)")
        openMenuWithThreeFingers()
        tapMenu("menu_edit_controls")
        XCTAssertTrue(app.buttons["OnScreenEditorReset"].waitForExistence(timeout: 5))
        app.buttons["OnScreenEditorReset"].tap()
        app.buttons["OnScreenEditorDone"].tap()
        XCTAssertEqual(control("A button").frame.origin, from.origin, "Reset didn't put A back")

        openMenuWithThreeFingers()
        tapMenu("menu_onscreen_controls")
        closeMenu()
        XCTAssertTrue(waitForGone(control("A button")), "the on-screen controller didn't hide")
        stopStream()
    }

    // MARK: Keyboards

    func testKeyboards() throws {
        try startStream()
        // The full keyboard
        openMenuWithThreeFingers()
        tapMenu("menu_full_keyboard")
        closeMenu()
        XCTAssertTrue(app.otherElements["FullKeyboard"].waitForExistence(timeout: 5) || key("a").waitForExistence(timeout: 5),
                      "the full keyboard didn't appear")
        screenshot("full keyboard")
        var before = counts()
        key("a").tap()
        XCTAssertTrue(waitForCount(.keys, atLeast: before.keys + 2), "A on the full keyboard didn't reach the PC")
        XCTAssertTrue(waitFor("last key 0x41 up"))
        // A quick tap on Shift is a plain press; Shift held, then A, carries the Shift flag
        before = counts()
        key("shift").press(forDuration: 0.6)
        key("a").tap()
        XCTAssertTrue(waitFor("last key 0x41 up mods 1"), "A after a held Shift didn't carry Shift")
        key("shift").tap()
        record("full keyboard: \(inputLine())")
        // Hide
        key("hide").tap()
        XCTAssertTrue(waitForGone(key("a")), "Hide didn't hide the full keyboard")

        // The system keyboard: text goes as UTF-8, Return as Enter
        openMenuWithThreeFingers()
        tapMenu("menu_keyboard")
        // The text field is hidden, so XCUITest can't type into it: press the keyboard's keys
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "the system keyboard didn't come up")
        screenshot("system keyboard")
        before = counts()
        for letter in ["h", "i"] {
            let key = keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch
            XCTAssertTrue(key.exists, "no \(letter) key on the keyboard")
            key.tap()
        }
        XCTAssertTrue(waitForCount(.text, atLeast: before.text + 2), "typed text didn't reach the PC")
        let enter = keyboard.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "return", "Return")).firstMatch
        let enterKey = enter.exists ? enter : keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", "return")).firstMatch
        XCTAssertTrue(enterKey.exists, "no Return key on the keyboard")
        enterKey.tap()
        XCTAssertTrue(waitFor("last key 0x0D up"), "Return didn't send Enter")
        record("system keyboard: \(inputLine())")
        stopStream()
    }

    // MARK: Helpers

    private struct Counts {
        var touch = 0, pen = 0, mouse = 0, buttons = 0, scroll = 0, keys = 0, text = 0, controller = 0, motion = 0
        var total: Int { touch + pen + mouse + buttons + scroll + keys + text + controller + motion }
    }

    private enum Kind: String { case touch, pen, mouse, buttons, scroll, keys, text, controller, motion }

    // MARK: Scrolling (batch 4.5)

    /// Scrolls in each touch mode with real finger drags and records the overlay's "Touch rate:"
    /// line (touch deliveries, coalesced samples, delivery delay, packets per second) and, on the
    /// "Starwire input latency" app, the "Latency probe:" line. TEST_RUNNER_STARWIRE_MODES picks
    /// the modes (list_touch_mode values, comma separated); TEST_RUNNER_STARWIRE_DRAGS the drags.
    func testScrollSmoothness() throws {
        let modes = (env["STARWIRE_MODES"] ?? "gaming_trackpad,natural_trackpad,direct,multi_touch").split(separator: ",").map(String.init)
        let drags = Int(env["STARWIRE_DRAGS"] ?? "") ?? 8
        for mode in modes {
            app.terminate()
            var args = ["-StarwireStatsOverlay", "YES", "-StarwirePlayAudioOnPC", "YES", "-list_touch_mode", mode,
                        "-StarwireLatencyProbe", "YES"]
            if let v = env["STARWIRE_FPS"] { args += ["-StarwireFrameRate", v] }
            // TOUCH_LINK=NO: without the low-latency touch delivery, to compare
            if let v = env["STARWIRE_TOUCH_LINK"] { args += ["-StarwireTouchUpdateLink", v] }
            app.launchArguments = args
            app.launch()
            try startStream()
            let frame = streamScreen.frame
            let screen = XCUIScreen.main.screenshot().image.size
            if frame.width * frame.height < screen.width * screen.height * 0.9 {
                record("scroll \(mode): the app is in a window (\(frame.size)), not full screen")
            }
            // Multi-touch scrolls with one finger, as on a touchscreen; the other modes with two
            let fingers = mode == "multi_touch" ? 1 : 2
            for drag in 0..<drags {
                // Up then down, so the page's list never reaches an end
                let up = drag % 2 == 0
                let x = frame.midX, y = frame.midY + (up ? 150 : -150)
                let starts = (0..<fingers).map { NSValue(cgPoint: CGPoint(x: x + CGFloat($0) * 90, y: y)) }
                try StarwireMultiTouch.dragFingers(starts, by: CGVector(dx: 0, dy: up ? -300 : 300), duration: 0.8, steps: 96,
                                                   orientation: interfaceOrientation)
                usleep(700_000)
            }
            sleep(2)
            screenshot("scroll \(mode)")
            record("scroll \(mode): \(overlayLine("Touch: "))")
            record("scroll \(mode): \(overlayLine("Touch rate:"))")
            record("scroll \(mode): \(overlayLine("Latency probe:"))")
            record("scroll \(mode): \(inputLine())")
            screenshot("scroll \(mode)")
            stopStream()
        }
    }

    /// The screen's orientation as the event synthesiser wants it
    private var interfaceOrientation: UIInterfaceOrientation {
        switch XCUIDevice.shared.orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default:
            let frame = streamScreen.frame
            return frame.width > frame.height ? .landscapeRight : .portrait
        }
    }

    private func overlayLine(_ prefix: String) -> String {
        guard overlay.exists else { return "(no statistics overlay)" }
        let text = overlay.label
        guard let range = text.range(of: prefix) else { return "(no \(prefix) line)" }
        return String(text[range.lowerBound...].prefix { $0 != "\n" })
    }

    private func inputLine() -> String {
        let text = overlay.label
        guard let range = text.range(of: "Input: ") else { return "(no input line)" }
        return String(text[range.lowerBound...].prefix { $0 != "\n" })
    }

    private func counts() -> Counts {
        let line = inputLine()
        func value(_ name: String) -> Int {
            guard let range = line.range(of: "\(name) ") else { return 0 }
            return Int(line[range.upperBound...].prefix { $0.isNumber }) ?? 0
        }
        return Counts(touch: value("touch"), pen: value("pen"), mouse: value("mouse"), buttons: value("buttons"),
                      scroll: value("scroll"), keys: value("keys"), text: value("text"), controller: value("controller"),
                      motion: value("motion"))
    }

    /// The overlay refreshes once a second
    private func waitForCount(_ kind: Kind, atLeast target: Int, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let c = counts()
            let now: Int
            switch kind {
            case .touch: now = c.touch
            case .pen: now = c.pen
            case .mouse: now = c.mouse
            case .buttons: now = c.buttons
            case .scroll: now = c.scroll
            case .keys: now = c.keys
            case .text: now = c.text
            case .controller: now = c.controller
            case .motion: now = c.motion
            }
            if now >= target { return true }
            usleep(250_000)
        }
        record("waited for \(kind.rawValue) >= \(target): \(inputLine())")
        return false
    }

    private func waitFor(_ text: String, timeout: TimeInterval = 6) -> Bool {
        let found = overlay.waitForLabel(containing: text, timeout: timeout)
        if !found { record("waited for \"\(text)\" in the overlay: \(inputLine())") }
        return found
    }

    private func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func control(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func key(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)["key_\(id)"]
    }

    /// The stream screen (StreamFrameViewController's view), for gestures over the picture
    private var streamScreen: XCUIElement {
        app.otherElements["StreamScreen"]
    }

    private func openMenuWithThreeFingers() {
        if app.descendants(matching: .any)["StreamMenu"].exists { return }
        streamScreen.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        XCTAssertTrue(app.descendants(matching: .any)["StreamMenu"].waitForExistence(timeout: 5), "a three-finger tap didn't open the menu")
    }

    /// From the floating button: in multi-touch mode three fingers go to the PC instead
    private func openMenuWithButton() {
        if app.descendants(matching: .any)["StreamMenu"].exists { return }
        app.buttons["StreamMenuButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["StreamMenu"].waitForExistence(timeout: 5), "the floating button didn't open the menu")
    }

    private func tapMenu(_ id: String) {
        let item = app.buttons[id]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no \(id) in the menu")
        item.tap()
    }

    private func closeMenu() {
        if app.buttons["menu_close"].exists {
            app.buttons["menu_close"].tap()
        }
        XCTAssertTrue(waitForGone(app.descendants(matching: .any)["StreamMenu"]), "the menu didn't close")
    }

    private func chooseTouchMode(_ name: String) {
        openMenuWithButton()
        tapMenu("menu_touch_mode")
        let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "no \(name) in the touch modes")
        // "Direct touch" is also the start of "Direct touch, swapped clicks"
        let exact = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", name, "\(name) (now)")).firstMatch
        (exact.exists ? exact : choice).tap()
        XCTAssertTrue(waitFor("Touch: \(name)"), "the touch mode didn't change to \(name)")
    }

    private func startStream() throws {
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", appName)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no \"\(appName)\" tile: is the PC paired, awake and showing its app list?")
        tile.tap()
        let resume = app.buttons["panel-Resume Session"]
        let quitOther = app.buttons["panel-Quit Current Game and Start"]
        if quitOther.waitForExistence(timeout: 3) {
            let running = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " is running on the PC.")).firstMatch.label
            let name = running.replacingOccurrences(of: " is running on the PC.", with: "")
            XCTAssertTrue(quittableApps.contains(name), "\(running) on the PC; the test won't quit it")
            quitOther.tap()
        } else if resume.exists {
            resume.tap()
        }
        overlay = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Video stream:")).firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 60), "the statistics overlay didn't appear")
        XCTAssertTrue(waitFor("Input: "), "no Input line in the overlay")
        sleep(3)
    }

    // High on the screen: the system keyboard may cover the lower half
    private func stopStream() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.3)))
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", appName)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "the app list didn't come back")
        XCTAssertFalse(app.alerts.firstMatch.exists, "an alert is showing")
    }

    private func record(_ text: String) {
        print("[device-run] \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [found], timeout: timeout) == .completed
    }
}
