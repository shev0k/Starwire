//
//  DesignDeviceRunTests.swift
//  Starwire
//
//  Batch 4.5's screens on the iPad with a real stream behind them (docs/ios/ux-overhaul.md):
//  the stream menu and its pages, the menu button floating and as a tab, the full keyboard
//  docked and floating, the controller keyboard and the settings screen. Each is photographed
//  for a person to look at; the checks are only that each one opens. The stream is the "Starwire
//  test pattern" app on its own virtual display, with the PC's sound kept on the PC.
//

import XCTest

final class DesignDeviceRunTests: XCTestCase {
    private var app: XCUIApplication!
    private let appName = ProcessInfo.processInfo.environment["STARWIRE_APP"] ?? "Starwire test pattern"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-StarwirePlayAudioOnPC", "YES"] + extra
        app.launch()
    }

    func testStreamScreens() throws {
        launch()
        try startStream()
        shot("1 stream with the menu button")

        let button = app.otherElements["StreamMenuButton"].exists ? app.otherElements["StreamMenuButton"] : app.buttons["StreamMenuButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no menu button")
        button.tap()
        XCTAssertTrue(app.descendants(matching: .any)["StreamMenu"].waitForExistence(timeout: 5), "the menu didn't open")
        sleep(1)
        shot("2 stream menu")

        tap("menu-touch_mode")
        sleep(1)
        shot("3 stream menu, touch mode page")
        tap("menu-back")
        tap("menu-bitrate")
        sleep(1)
        shot("4 stream menu, bitrate page")
        tap("menu-back")

        tap("menu-full_keyboard")
        tap("menu-close")
        sleep(1)
        shot("5 full keyboard, docked")
        stopStream()
    }

    func testOtherPlacements() throws {
        launch(["-list_keyboard_placement", "floating", "-seekbar_keyboard_size", "80", "-list_menu_button_style", "edge",
                "-StarwireOpenControllerKeyboard", "YES"])
        try startStream()
        sleep(1)
        shot("6 controller keyboard, menu button as a tab")

        app.buttons["Close"].firstMatch.tap()
        let tab = app.otherElements["StreamMenuButton"].exists ? app.otherElements["StreamMenuButton"] : app.buttons["StreamMenuButton"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "no menu tab")
        tab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["StreamMenu"].waitForExistence(timeout: 5), "the tab didn't open the menu")
        tap("menu-full_keyboard")
        tap("menu-close")
        sleep(1)
        shot("7 full keyboard, floating at 80%")
        stopStream()
    }

    func testSettings() throws {
        launch()
        let back = app.buttons["Back to your PCs"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "the game screen didn't open")
        back.tap()
        let settings = app.buttons["pcs-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "the PC list didn't open")
        settings.tap()
        for (index, section) in ["stream", "touch", "keyboard", "menu"].enumerated() {
            let pill = app.buttons["pill-\(section)"]
            XCTAssertTrue(pill.waitForExistence(timeout: 5), "no \(section) section")
            pill.tap()
            sleep(1)
            shot("\(8 + index) settings, \(section)")
        }
        let search = app.textFields["settings-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search field")
        search.tap()
        search.typeText("keyboard")
        sleep(1)
        shot("12 settings, search")
    }

    /// iPadOS windowing can leave the app in a window smaller than the screen: move the window to
    /// the top-left corner and drag its resize corner to the bottom right, so it fills the screen.
    func testFillTheScreen() throws {
        launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let screen = springboard.frame
        let window = app.windows.allElementsBoundByIndex.map(\.frame).max { $0.width * $0.height < $1.width * $1.height } ?? .zero
        print("[device-run] screen \(screen.size), window \(window)")
        guard window.width > 0, window.width * window.height < screen.width * screen.height * 0.95 else {
            // Already as big as the screen
            print("[device-run] the app already fills the screen")
            return
        }
        // The window's controls (iPadOS's three dots at its top left): open them, then Fill
        let controlsLabel = NSPredicate(format: "label CONTAINS[c] 'window' OR label CONTAINS[c] 'fill' OR label CONTAINS[c] 'full screen' OR label CONTAINS[c] 'zoom' OR label CONTAINS[c] 'maximi'")
        for source in [app!, springboard] {
            for button in source.buttons.matching(controlsLabel).allElementsBoundByIndex {
                print("[device-run] control \(button.label) \(button.identifier) \(button.frame)")
            }
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 42, dy: 17)).tap()
        sleep(1)
        for source in [app!, springboard] {
            for button in source.buttons.matching(controlsLabel).allElementsBoundByIndex {
                print("[device-run] control after tap \(button.label) \(button.identifier) \(button.frame)")
            }
        }
        shot("window controls")
        let fill = [app!, springboard].lazy.map { $0.buttons.matching(NSPredicate(format: "identifier == 'Zoom-button' OR label CONTAINS[c] 'fill' OR label CONTAINS[c] 'full screen'")).firstMatch }
            .first { $0.exists }
        if let fill {
            print("[device-run] tapping \(fill.label)")
            fill.tap()
            sleep(1)
            let filled = app.windows.allElementsBoundByIndex.map(\.frame).max { $0.width * $0.height < $1.width * $1.height } ?? .zero
            print("[device-run] window after Fill: \(filled)")
            shot("after fill")
            return
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        }
        // The window's top bar, then its bottom-right resize corner
        point(window.midX, window.minY + 12).press(forDuration: 0.4, thenDragTo: point(window.width / 2 + 2, 12))
        sleep(1)
        let moved = app.windows.allElementsBoundByIndex.map(\.frame).max { $0.width * $0.height < $1.width * $1.height } ?? .zero
        // The screen's size comes as the panel is mounted (portrait); the window's in the app's terms
        let wide = CGSize(width: max(screen.width, screen.height), height: min(screen.width, screen.height))
        let target = window.width > window.height ? wide : CGSize(width: wide.height, height: wide.width)
        point(moved.maxX - 6, moved.maxY - 6).press(forDuration: 0.4, thenDragTo: point(target.width - 1, target.height - 1))
        sleep(1)
        let after = app.windows.allElementsBoundByIndex.map(\.frame).max { $0.width * $0.height < $1.width * $1.height } ?? .zero
        print("[device-run] window after: \(after)")
        shot("fill the screen")
    }

    // MARK: Helpers

    private func tap(_ identifier: String) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "no \(identifier)")
        element.tap()
    }

    private func startStream() throws {
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", appName)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no \"\(appName)\" tile: is the PC paired, awake and showing its app list?")
        tile.tap()
        let resume = app.buttons["panel-Resume Session"]
        let quitOther = app.buttons["panel-Quit Current Game and Start"]
        if quitOther.waitForExistence(timeout: 3) {
            quitOther.tap()
        } else if resume.exists {
            resume.tap()
        }
        XCTAssertTrue(app.otherElements["StreamScreen"].waitForExistence(timeout: 60), "the stream didn't start")
        // The picture and the first toast settle
        sleep(6)
    }

    private func stopStream() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.3)))
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", appName)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "the app list didn't come back")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[device-run] screenshot \(name)")
    }
}
