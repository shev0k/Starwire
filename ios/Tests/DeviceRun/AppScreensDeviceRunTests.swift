//
//  AppScreensDeviceRunTests.swift
//  Starwire
//
//  The SwiftUI app's screens on the iPad (phase 3): every screen is opened, photographed and run
//  through Xcode's accessibility audit (labels, Dynamic Type clipping, contrast, hit areas). The
//  audit's findings are recorded for the report rather than failing the run, so one run lists
//  them all; a screen that doesn't open fails it.
//
//    test AppScreensDeviceRunTests/testScreens               default text size
//    test AppScreensDeviceRunTests/testScreensAtLargestText  Accessibility XXXL text
//    test AppScreensDeviceRunTests/testDemoScreens           the demo PC, no real PC needed
//
//  It never starts a stream, so the PC is only asked for its apps.
//

import XCTest

final class AppScreensDeviceRunTests: XCTestCase {
    private var app: XCUIApplication!
    private var auditFindings: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    func testScreens() throws {
        launch()
        try tour(label: "default text")
    }

    func testScreensAtLargestText() throws {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        try tour(label: "largest text")
    }

    func testDemoScreens() throws {
        launch(["-StarwireDemoMode", "YES"])
        try tour(label: "demo")
    }

    private func tour(label: String) throws {
        // One PC: its games open by themselves
        let back = app.buttons["Back to your PCs"]
        XCTAssertTrue(back.waitForExistence(timeout: 30), "the game screen didn't open")
        sleep(3)
        shot("game screen (\(label))")
        audit("game screen")

        // A tile's menu, then its settings
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "no tiles")
        tile.press(forDuration: 0.8)
        let gameSettings = app.buttons["panel-Settings for this game"]
        XCTAssertTrue(gameSettings.waitForExistence(timeout: 5), "the app menu didn't open")
        shot("app menu (\(label))")
        audit("app menu")
        gameSettings.tap()
        XCTAssertTrue(app.staticTexts["Settings for this game"].waitForExistence(timeout: 5), "no game settings screen")
        shot("game settings (\(label))")
        audit("game settings")
        tapBack()

        // The PC list
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let settings = app.buttons["pcs-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "the PC list didn't open")
        shot("PC list (\(label))")
        audit("PC list")

        // Every settings section
        settings.tap()
        for section in ["stream", "sound", "controllers", "menu", "touch", "onscreen", "pc", "app", "advanced", "about"] {
            let pill = app.buttons["pill-\(section)"]
            XCTAssertTrue(pill.waitForExistence(timeout: 5), "no \(section) pill")
            pill.tap()
            sleep(1)
            shot("settings \(section) (\(label))")
            audit("settings \(section)")
        }
        tapBack()

        // About and the licences
        let about = app.buttons["pcs-about"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        sleep(1)
        shot("about (\(label))")
        audit("about")
        let licences = app.buttons["Open-source licences"].exists ? app.buttons["Open-source licences"]
            : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "licen")).firstMatch
        if licences.waitForExistence(timeout: 3) {
            licences.tap()
            sleep(1)
            shot("licences (\(label))")
            audit("licences")
            tapBack()
        } else {
            record("no licences button found")
        }
        tapBack()

        // The add-a-PC panel, then cancel
        app.buttons["pcs-add"].tap()
        XCTAssertTrue(app.buttons["pcs-add-confirm"].waitForExistence(timeout: 5), "the add panel didn't open")
        shot("add a PC (\(label))")
        audit("add a PC")
        app.buttons["panel-Cancel"].tap()

        record("audit findings (\(label)): \(auditFindings.count)\n" + auditFindings.joined(separator: "\n"))
    }

    private func tapBack() {
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no Back button")
        back.tap()
        sleep(1)
    }

    /// Xcode's accessibility audit; findings are recorded, not failed on.
    private func audit(_ screen: String) {
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.identifier)" } ?? "-"
                self.auditFindings.append("\(screen): \(issue.auditType.rawValue) \(issue.compactDescription) [\(element)]")
                return true
            }
        } catch {
            auditFindings.append("\(screen): audit didn't run: \(error)")
        }
    }

    private func record(_ text: String) {
        print("[device-run] \(text)")
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
