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
