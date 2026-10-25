//
//  StreamDeviceRunTests.swift
//  Starwire
//
//  The Mac's device checks (docs/ios/mac-runbook.md), run on the iPad against the PC. These need
//  a paired PC that is awake, so they never run on CI; CI only builds them.
//
//  Settings come from the environment of xcodebuild, with a TEST_RUNNER_ prefix:
//    TEST_RUNNER_STARWIRE_APP             app tile to start (default "Starwire test pattern", a
//                                         Vibeshine app that shows testufo.com full screen, so
//                                         frames keep coming with nobody at the PC)
//    TEST_RUNNER_STARWIRE_FRESH           "1" to quit the app on the PC first if it's running, so
//                                         the stream starts with this run's settings
//    TEST_RUNNER_STARWIRE_SECONDS         stream length for testStreamAndSample (default 300)
//    TEST_RUNNER_STARWIRE_STREAMS         streams for testStreamsInARow (default 10)
//    TEST_RUNNER_STARWIRE_PRESENTER       "loop" (render loop) or "display" (CAMetalDisplayLink)
//    TEST_RUNNER_STARWIRE_PRESENT_TIMING  "nearest" or "frame"
//    TEST_RUNNER_STARWIRE_DROP_POLICY     "alternate" or "newest"
//    TEST_RUNNER_STARWIRE_BUFFER          frames to buffer, 1 to 3
//    TEST_RUNNER_STARWIRE_JITTER_BUFFER   "lowest-latency", "low-latency", "balanced" or "smooth"
//                                         (display presenter only)
//    TEST_RUNNER_STARWIRE_PIP             "1" for picture in picture (testPictureInPicture sets it)
//    TEST_RUNNER_STARWIRE_OVERLAY         "full" or "lite"
//    TEST_RUNNER_STARWIRE_FULL_RANGE      "1" to ask for full range video
//    TEST_RUNNER_STARWIRE_REDUCE_REFRESH  "1" to allow refresh rate reduction
//    TEST_RUNNER_STARWIRE_INTERPOLATION   "1" for frame interpolation (iOS 26 or later)
//    TEST_RUNNER_STARWIRE_FPS             a frame rate instead of the app's setting, like 60
//    TEST_RUNNER_STARWIRE_PC_AUDIO        "0" to move the PC's sound to the stream; by default it
//                                         stays on the PC
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

    private var appName: String { env["STARWIRE_APP"] ?? "Starwire test pattern" }
    // Apps the tests may quit on the PC to start theirs: never someone's game
    private let quittableApps = ["Starwire test pattern", "Desktop"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args: [String] = []
        if let v = env["STARWIRE_PRESENTER"] { args += ["-StarwirePresenter", v] }
        if let v = env["STARWIRE_PRESENT_TIMING"] { args += ["-StarwirePresentTiming", v] }
        if let v = env["STARWIRE_DROP_POLICY"] { args += ["-StarwireDropPolicy", v] }
        if let v = env["STARWIRE_BUFFER"] { args += ["-StarwireFramesToBuffer", v] }
        if let v = env["STARWIRE_JITTER_BUFFER"] { args += ["-StarwireJitterBuffer", v] }
        if let v = env["STARWIRE_PIP"] { args += ["-StarwirePictureInPicture", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_OVERLAY"] { args += ["-StarwireOverlay", v] }
        if let v = env["STARWIRE_FULL_RANGE"] { args += ["-StarwireFullRange", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_REDUCE_REFRESH"] { args += ["-StarwireReduceRefreshRate", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_INTERPOLATION"] { args += ["-StarwireFrameInterpolation", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_FPS"] { args += ["-StarwireFrameRate", v] }
        // The PC's sound stays on the PC unless a run asks otherwise: the owner may be using it
        args += ["-StarwirePlayAudioOnPC", env["STARWIRE_PC_AUDIO"] == "0" ? "NO" : "YES"]
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
        let last = overlay.label
        record("sample at \(elapsed) s:\n\(last)")
        // The whole-stream pacing totals, on one line for the report
        record("summary: \(summaryLine(in: last))")
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

    // With picture in picture on, leaving the app keeps the stream: switch to the Settings app,
    // come back, and the stream (not the app list) is still there.
    func testPictureInPicture() throws {
        app.terminate()
        app.launchArguments += ["-StarwirePictureInPicture", "YES"]
        app.launch()
        try startStream()
        _ = try waitForOverlay()
        sleep(5)

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        sleep(10)
        record("in the background: app state \(app.state.rawValue) (4 = foreground, 3 = background)")
        screenshot("picture in picture")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let overlay = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Video stream:")).firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 10), "the stream ended in the background")
        record("after coming back:\n\(overlay.label)")
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

    // App tiles are buttons labelled with the app's name (UIAppView)
    private var appTile: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", appName)).firstMatch
    }

    // From "Pacing summary" to the end of its line. The label may come back with its line
    // breaks or without them, so this doesn't rely on a line starting with it.
    private func summaryLine(in overlayText: String) -> String {
        guard let start = overlayText.range(of: "Pacing summary") else { return "(no summary line)" }
        let rest = overlayText[start.lowerBound...]
        return String(rest.prefix { $0 != "\n" })
    }

    private func startStream() throws {
        let tile = appTile
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no \"\(appName)\" tile: is the PC paired, awake and showing its app list?")
        tile.tap()

        // When an app is already running on the PC, a menu comes up first (MainFrameViewController)
        let resume = app.buttons["Resume App"]
        let quitOther = app.buttons["Quit Running App and Start"]
        if quitOther.waitForExistence(timeout: 3) {
            let running = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " is currently running")).firstMatch.label
            let name = running.replacingOccurrences(of: " is currently running", with: "")
            XCTAssertTrue(quittableApps.contains(name), "\(running) on the PC; the test won't quit it")
            record("quitting \(name) on the PC to start \(appName)")
            quitOther.tap()
        } else if resume.exists {
            if env["STARWIRE_FRESH"] == "1" {
                record("quitting \(appName) on the PC for a fresh start")
                app.buttons["Quit App"].tap()
                XCTAssertTrue(tile.waitForExistence(timeout: 30), "the app list didn't come back after quitting")
                sleep(3)
                tile.tap()
            } else {
                resume.tap()
            }
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
        XCTAssertTrue(appTile.waitForExistence(timeout: 20), "the app list didn't come back")
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
