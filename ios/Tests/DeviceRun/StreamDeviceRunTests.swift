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
//    TEST_RUNNER_STARWIRE_CODEC           av1, hevc, h264 or auto instead of the app's setting
//    TEST_RUNNER_STARWIRE_COLORSPACE      "601" or "709": the colour space asked of the host
//    TEST_RUNNER_STARWIRE_AVSB            "1" shows the system's video layer instead of Metal
//    TEST_RUNNER_STARWIRE_RESOLUTION      WIDTHxHEIGHT instead of the app's setting
//    TEST_RUNNER_STARWIRE_HDR             "1" or "0" for the app's HDR setting
//    TEST_RUNNER_STARWIRE_YUV444          "1" or "0" for the app's 4:4:4 setting
//    TEST_RUNNER_STARWIRE_PC_AUDIO        "0" to move the PC's sound to the stream; by default it
//                                         stays on the PC
//    TEST_RUNNER_STARWIRE_VIRTUAL_DISPLAY "1" for a Vibeshine virtual display, "0" for the PC's monitor
//    TEST_RUNNER_STARWIRE_DISPLAY_MODE    "host", "virtual" or "primary" (Display on the PC)
//    TEST_RUNNER_STARWIRE_SCALE           the virtual display's scale in percent, like 150
//    TEST_RUNNER_STARWIRE_EXACT_FPS       an exact rate for mode, like 119.88
//    TEST_RUNNER_STARWIRE_VRR             "1" to ask for a variable refresh rate virtual display
//    TEST_RUNNER_STARWIRE_DEMO            "1" for the demo mode (testDemoMode sets it)
//    TEST_RUNNER_STARWIRE_BITRATES        Mbps to switch to in testBitrateChange (default "20,70")
//  They become the app's launch arguments, which the app reads as user defaults. The app has no
//  code for tests.
//
//  The statistics overlay is turned on for the tests' launches (-StarwireStatsOverlay YES): the
//  overlay text is what's sampled.
//

import XCTest

final class StreamDeviceRunTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var app: XCUIApplication!

    private var appName: String { env["STARWIRE_APP"] ?? "Starwire test pattern" }
    // Apps the tests may quit on the PC to start theirs: never someone's game
    private let quittableApps = ["Starwire test pattern", "Starwire colour bars", "Desktop"]

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
        if let v = env["STARWIRE_CODEC"] { args += ["-StarwireCodec", v] }
        if let v = env["STARWIRE_COLORSPACE"] { args += ["-StarwireColorSpace", v] }
        if let v = env["STARWIRE_AVSB"] { args += ["-StarwireShowSampleBufferLayer", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_RESOLUTION"] { args += ["-StarwireResolution", v] }
        if let v = env["STARWIRE_HDR"] { args += ["-StarwireHDR", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_YUV444"] { args += ["-StarwireYUV444", v == "1" ? "YES" : "NO"] }
        // The tests read the statistics overlay, whatever the app's own setting is
        args += ["-StarwireStatsOverlay", "YES"]
        // The PC's sound stays on the PC unless a run asks otherwise: the owner may be using it
        args += ["-StarwirePlayAudioOnPC", env["STARWIRE_PC_AUDIO"] == "0" ? "NO" : "YES"]
        if let v = env["STARWIRE_VIRTUAL_DISPLAY"] { args += ["-StarwireVirtualDisplayMode", v == "1" ? "virtual" : "primary"] }
        if let v = env["STARWIRE_DISPLAY_MODE"] { args += ["-StarwireVirtualDisplayMode", v] }
        if let v = env["STARWIRE_SCALE"] { args += ["-StarwireScaleFactor", v] }
        if let v = env["STARWIRE_EXACT_FPS"] { args += ["-StarwireExactFrameRate", v] }
        if let v = env["STARWIRE_VRR"] { args += ["-StarwireRequestVRR", v == "1" ? "YES" : "NO"] }
        if let v = env["STARWIRE_DEMO"] { args += ["-StarwireDemoMode", v == "1" ? "YES" : "NO"] }
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
        // Nothing left over the picture once it's streaming (the loading spinner stayed up with
        // the system presenter before it was fixed)
        sleep(3)
        XCTAssertFalse(app.activityIndicators.firstMatch.exists, "a loading spinner is still showing over the stream")

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

        try sendAppToBackground()
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

        // XCUITest's app state isn't reliable here (with picture in picture showing it stayed
        // "foreground"), so the app's own summary line says whether picture in picture started
        XCUIDevice.shared.press(.home)
        sleep(10)
        record("after Home: app state \(app.state.rawValue) (4 = foreground, 3 = background, 2 = suspended)")
        screenshot("picture in picture")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let overlay = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Video stream:")).firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 10), "the stream ended in the background")
        sleep(6)
        let summary = summaryLine(in: overlay.label)
        record("summary: \(summary)")
        // Started while away, and closed again on the way back
        XCTAssertTrue(summary.contains("picture in picture closed, started"), "picture in picture: \(summary)")
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

    // Vibeshine's /bitrate during a stream: the stream menu button, a bitrate, the PC's answer.
    // The overlay is sampled before and after each change, so the report shows the bandwidth.
    func testBitrateChange() throws {
        let steps = (env["STARWIRE_BITRATES"] ?? "20,70").split(separator: ",").map(String.init)
        try startStream()
        let overlay = try waitForOverlay()
        sleep(10)
        record("before:\n\(overlay.label)")
        for mbps in steps {
            let button = app.buttons["StreamMenuButton"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "no stream menu button")
            button.tap()
            let choice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(mbps) Mbps")).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "no \(mbps) Mbps in the bitrate menu")
            choice.tap()
            // The button's value is the bitrate the PC applied
            let applied = NSPredicate(format: "value == %@", "\(mbps) Mbps")
            let answered = expectation(for: applied, evaluatedWith: button)
            let result = XCTWaiter.wait(for: [answered], timeout: 10)
            record("asked \(mbps) Mbps: the PC applied \(button.value as? String ?? "?")")
            XCTAssertEqual(result, .completed, "the PC didn't apply \(mbps) Mbps")
            sleep(15)
            record("15 s after \(mbps) Mbps:\n\(overlay.label)")
        }
        screenshot("after the bitrate changes")
        stopStreamWithEdgeSwipe()
        try assertBackAtAppList()
    }

    // Vibeshine's Remote Input tile: a stream with input only, next to whatever runs on the PC.
    // It sends no picture, so the statistics overlay never shows; the stream's menu button, added
    // when the connection starts, says it's up.
    func testRemoteInput() throws {
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", "Remote Input")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no Remote Input tile")
        tile.tap()
        XCTAssertTrue(app.buttons["StreamMenuButton"].waitForExistence(timeout: 60), "Remote Input didn't connect")
        assertNoAlert()
        sleep(10)
        assertNoAlert()
        record("Remote Input connected; app state \(app.state.rawValue)")
        screenshot("remote input")
        stopStreamWithEdgeSwipe()
        try assertBackAtAppList()
    }

    // Vibeshine's Remote Monitor tile: this device's own virtual display, kept after the stream
    // until Disconnect Monitor, whose answer (HTTP 410) the app shows as a message
    func testRemoteMonitor() throws {
        // It shares this device's virtual display with a game this device runs, so the test
        // pattern is quit first if it's running
        try quitTestAppIfRunning()
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", "Remote Monitor")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no Remote Monitor tile")
        tile.tap()
        let overlay = try waitForOverlay()
        sleep(10)
        record("Remote Monitor:\n\(overlay.label)")
        screenshot("remote monitor")
        stopStreamWithEdgeSwipe()

        let disconnect = app.buttons.matching(NSPredicate(format: "label == %@", "Disconnect Monitor")).firstMatch
        XCTAssertTrue(disconnect.waitForExistence(timeout: 30), "no Disconnect Monitor tile after the stream")
        disconnect.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 30), "no message after Disconnect Monitor")
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        record("Disconnect Monitor: \(message)")
        screenshot("disconnect monitor")
        XCTAssertTrue(message.contains("disconnected"), message)
        alert.buttons["OK"].tap()
        try assertBackAtAppList()
    }

    // The demo mode: a made-up PC, a stream of a generated picture, and touches counted
    func testDemoMode() throws {
        app.terminate()
        app.launchArguments += ["-StarwireDemoMode", "YES"]
        app.launch()
        let host = app.descendants(matching: .any).matching(identifier: "DemoHost").firstMatch
        XCTAssertTrue(host.waitForExistence(timeout: 10), "no demo PC")
        host.tap()
        let desktop = app.descendants(matching: .any).matching(identifier: "DemoApp-Desktop").firstMatch
        XCTAssertTrue(desktop.waitForExistence(timeout: 10), "no demo apps")
        desktop.tap()
        let streaming = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Streaming the demo picture")).firstMatch
        XCTAssertTrue(streaming.waitForExistence(timeout: 10), "the demo stream didn't start")
        let video = app.descendants(matching: .any).matching(identifier: "DemoVideo").firstMatch
        for _ in 0..<3 {
            video.tap()
        }
        sleep(2)
        let counts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "input events")).firstMatch.label
        record("demo: \(counts)")
        screenshot("demo stream")
        let numbers = counts.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertGreaterThan(numbers.first ?? 0, 60, "too few frames: \(counts)")
        XCTAssertGreaterThanOrEqual(numbers.last ?? 0, 6, "the taps weren't recorded: \(counts)")
    }

    // MARK: - Helpers

    // Quits the test's app on the PC when it's running: its tile then shows a menu
    private func quitTestAppIfRunning() throws {
        let tile = appTile
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "no \"\(appName)\" tile")
        tile.tap()
        let quit = app.buttons["Quit App"]
        if quit.waitForExistence(timeout: 3) {
            record("quitting \(appName) on the PC first")
            quit.tap()
            XCTAssertTrue(tile.waitForExistence(timeout: 30), "the app list didn't come back after quitting")
            sleep(3)
        } else {
            // Nothing was running, so the tap started a stream: stop it again
            _ = try waitForOverlay()
            stopStreamWithEdgeSwipe()
            try assertBackAtAppList()
            tile.tap()
            if quit.waitForExistence(timeout: 5) {
                quit.tap()
                XCTAssertTrue(tile.waitForExistence(timeout: 30))
                sleep(3)
            }
        }
    }

    // Leaves the app: the Home button first, then the Settings app. On iPadOS 27 with windowed
    // apps, opening Settings can leave Starwire in the foreground beside it, so the test checks
    // the app really left and skips (rather than passes) when nothing worked.
    private func sendAppToBackground() throws {
        XCUIDevice.shared.press(.home)
        if waitUntilNotForeground(timeout: 5) {
            record("left the app with the Home button")
            return
        }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        _ = settings.wait(for: .runningForeground, timeout: 10)
        if waitUntilNotForeground(timeout: 5) {
            record("left the app by opening Settings")
            return
        }
        throw XCTSkip("couldn't send the app to the background (state \(app.state.rawValue))")
    }

    private func waitUntilNotForeground(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.state != .runningForeground {
                return true
            }
            usleep(200_000)
        }
        return false
    }

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
