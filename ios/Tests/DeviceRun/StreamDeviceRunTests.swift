//
//  StreamDeviceRunTests.swift
//  Starwire
//
//  The Mac's device checks (docs/ios/mac-runbook.md), run on the iPad against the PC. These need
//  a paired PC that is awake, so they never run on CI; CI only builds them.
//
//  Settings come from the environment of xcodebuild, with a TEST_RUNNER_ prefix:
//    TEST_RUNNER_STARWIRE_APP             app tile to start (default "Desktop")
//    TEST_RUNNER_STARWIRE_SECONDS         stream length for testStreamAndSample (default 300)
//    TEST_RUNNER_STARWIRE_STREAMS         streams for testStreamsInARow (default 10)
//    TEST_RUNNER_STARWIRE_PRESENT_TIMING  "nearest" or "frame"
//    TEST_RUNNER_STARWIRE_DROP_POLICY     "alternate" or "newest"
//    TEST_RUNNER_STARWIRE_BUFFER          frames to buffer, 1 to 3
//    TEST_RUNNER_STARWIRE_VIRTUAL_DISPLAY "1" to stream a Vibeshine virtual display
//  They become the app's launch arguments, which the app reads as user defaults. The app has no
//  code for tests.
//
//  The statistics overlay must be on in the app's settings: the overlay text is what's sampled.
//

import XCTest

final class StreamDeviceRunTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!

    private var appName: String { env["STARWIRE_APP"] ?? "Desktop" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args: [String] = []
        if let v = env["STARWIRE_PRESENT_TIMING"] { args += ["-StarwirePresentTiming", v] }
        if let v = env["STARWIRE_DROP_POLICY"] { args += ["-StarwireDropPolicy", v] }
        if let v = env["STARWIRE_BUFFER"] { args += ["-StarwireFramesToBuffer", v] }
        if let v = env["STARWIRE_VIRTUAL_DISPLAY"] { args += ["-StarwireVirtualDisplay", v == "1" ? "YES" : "NO"] }
        app.launchArguments = args
        app.launch()
        record("launch arguments: \(args.joined(separator: " "))")
    }

    // One stream: sample the overlay every 15 seconds, then stop it with an edge swipe.
    func testStreamAndSample() throws {
        let seconds = Int(env["STARWIRE_SECONDS"] ?? "") ?? 300
        try startStream()
        let overlay = try waitForOverlay()
        screenshot("stream start")

        var elapsed = 0
        while elapsed < seconds {
            record("sample at \(elapsed) s:\n\(overlay.label)")
            sleep(15)
            elapsed += 15
        }
        record("sample at \(elapsed) s:\n\(overlay.label)")
        screenshot("stream end")

        stopStreamWithEdgeSwipe()
        try assertBackAtAppList()
    }

    // Background during a stream by switching to the Settings app, then come back. The stream
    // ends on purpose when the app goes to the background, so the app list should be showing.
    func testBackgroundAndResume() throws {
        try startStream()
        _ = try waitForOverlay()
        sleep(5)

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        sleep(10)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try assertBackAtAppList()

        // And a stream starts again afterwards
        try startStream()
        _ = try waitForOverlay()
        stopStreamWithEdgeSwipe()
        try assertBackAtAppList()
    }

    // Start and stop in a row with no crash, no stuck session and no alert.
    func testStreamsInARow() throws {
        let count = Int(env["STARWIRE_STREAMS"] ?? "") ?? 10
        for i in 1...count {
            try startStream()
            let overlay = try waitForOverlay()
            sleep(10)
            record("stream \(i) of \(count):\n\(overlay.label)")
            stopStreamWithEdgeSwipe()
            try assertBackAtAppList()
            XCTAssertEqual(app.state, .runningForeground, "the app is still running after stream \(i)")
        }
    }

    // MARK: - Helpers

    private func startStream() throws {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", appName)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no \"\(appName)\" tile: is the PC paired, awake and showing its app list?")
        tile.tap()

        // When the app is already running on the PC, a Resume / Quit menu comes up first
        let resume = app.buttons["Resume App"]
        if resume.waitForExistence(timeout: 3) {
            resume.tap()
        }
    }

    // The overlay is a plain label whose text starts with "Video stream:"
    private func waitForOverlay() throws -> XCUIElement {
        let overlay = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Video stream:")).firstMatch
        if !overlay.waitForExistence(timeout: 60) {
            screenshot("no overlay")
            assertNoAlert()
            XCTFail("the statistics overlay didn't appear within 60 s: is Statistics Overlay on in the app's settings?")
        }
        assertNoAlert()
        return overlay
    }

    private func stopStreamWithEdgeSwipe() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func assertBackAtAppList() throws {
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", appName)).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "the app list didn't come back")
        assertNoAlert()
    }

    private func assertNoAlert() {
        let alert = app.alerts.firstMatch
        if alert.exists {
            screenshot("alert")
            XCTFail("an alert is showing: \(alert.label)")
        }
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
