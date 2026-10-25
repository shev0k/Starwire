import XCTest
@testable import StarwireKit

/// A recorded or source-based host answer from Fixtures/ (see Fixtures/README.md).
enum FixtureFile {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appendingPathComponent(name))
    }

    static func response(_ name: String, status: Int = 200) throws -> HostResponse {
        HostResponse(status: status, body: try data(name))
    }
}

final class ServerInfoTests: XCTestCase {
    func testThePairedViewHasEverythingVibeshineAdds() throws {
        let info = try ServerInfo.parse(FixtureFile.data("vibeshine-serverinfo-paired.xml"))
        XCTAssertTrue(info.xml.isOK)
        XCTAssertEqual(info.hostName, "Gaming PC")
        XCTAssertEqual(info.uuid, "6B1C3A4E-0000-4000-8000-00000000F1C5")
        XCTAssertEqual(info.pairState, .paired)
        XCTAssertEqual(info.macAddress, "00:00:5E:00:53:01")
        XCTAssertEqual(info.httpsPort, 47984)
        XCTAssertTrue(info.isVibeshine)
        XCTAssertTrue(info.virtualDisplayCapable)
        XCTAssertTrue(info.virtualDisplayDriverReady)
        XCTAssertTrue(info.virtualDisplayHDRCapable)
        XCTAssertTrue(info.frameLimiterSupported)
        XCTAssertEqual(info.frameLimiterFpsLimitMilliHz, 0)
        XCTAssertEqual(info.codecModeSupport, 127_861_505)
        XCTAssertTrue(info.supportsPyroWave)
        XCTAssertEqual(info.pyroWaveHostLinkMbps, 10000)
        XCTAssertEqual(info.pyroWaveBandwidthProbeBytes, 33_554_432)
        XCTAssertEqual(info.pyroWaveCriticalFecPercentage, 20)
        XCTAssertEqual(info.pyroWaveMinParityShards, 2)
        XCTAssertTrue(info.isBusy)
        XCTAssertEqual(info.currentGameID, 170_526_778)
        XCTAssertEqual(info.currentGameUUID, "2E51601D-09B0-E104-DE0B-CE75F872F729")
        // Vibeshine 2.0.1 has neither yet: the app must not offer them
        XCTAssertEqual(info.hardwareMetricsVersion, 0)
        XCTAssertEqual(info.powerActionVersion, 0)
        XCTAssertFalse(info.sleepSupported)
        XCTAssertFalse(info.hasServerCommands)
    }

    func testThePlainHTTPViewHidesThePairedFields() throws {
        let info = try ServerInfo.parse(FixtureFile.data("vibeshine-serverinfo-http.xml"))
        XCTAssertEqual(info.pairState, .unpaired)
        XCTAssertNil(info.macAddress, "all zeros means unknown")
        XCTAssertFalse(info.isBusy)
        XCTAssertEqual(info.currentGameID, 0)
        XCTAssertNil(info.currentGameUUID)
        XCTAssertEqual(info.pyroWaveHostLinkMbps, 0)
        XCTAssertTrue(info.supportsPyroWave, "the codec bits are in both views")
    }

    func testSleepAndMetricsFieldsAreReadWhenAHostHasThem() throws {
        let xml = try HostXML.parse(Data("""
        <?xml version="1.0"?><root status_code="200"><HardwareMetricsVersion>1</HardwareMetricsVersion>\
        <PowerActionVersion>1</PowerActionVersion><SleepSupported>1</SleepSupported><SleepAllowed>0</SleepAllowed></root>
        """.utf8))
        let info = ServerInfo(xml: xml)
        XCTAssertEqual(info.hardwareMetricsVersion, 1)
        XCTAssertEqual(info.powerActionVersion, 1)
        XCTAssertTrue(info.sleepSupported)
        XCTAssertFalse(info.sleepAllowed)
    }

    func testUTF16DeclarationsAreRead() throws {
        let xml = try HostXML.parse(Data(#"<?xml version="1.0" encoding="UTF-16"?><root status_code="200"><hostname>PC</hostname></root>"#.utf8))
        XCTAssertEqual(xml["hostname"], "PC")
    }

    func testNotXMLIsAnError() {
        XCTAssertThrowsError(try HostXML.parse(Data("{}".utf8)))
    }
}

final class AppListTests: XCTestCase {
    func testControlTilesAreToldApartFromGames() throws {
        let (xml, apps) = try HostAppList.parse(FixtureFile.data("vibeshine-applist.xml"))
        XCTAssertTrue(xml.isOK)
        XCTAssertEqual(apps.map(\.name), ["Desktop", "Steam Big Picture", "Starwire test pattern", "Starwire colour bars",
                                          "Remote Input", "Remote Monitor"])
        XCTAssertEqual(apps.map(\.kind), [.game, .game, .game, .game, .remoteInput, .remoteMonitor])
        XCTAssertEqual(apps[0].id, "170526778")
        XCTAssertEqual(apps[0].uuid, "2E51601D-09B0-E104-DE0B-CE75F872F729")
        XCTAssertTrue(apps[0].hdrSupported)
    }

    func testASecondClientSeesTerminateAndTheRunningGame() throws {
        let body = """
        <?xml version="1.0"?><root status_code="200">\
        <App><IsHdrSupported>0</IsHdrSupported><AppTitle>     Desktop</AppTitle><UUID>9a1c5a25-58fe-40e0-b9aa-7d3f00000007</UUID><ID>1244042426</ID></App>\
        <App><IsHdrSupported>0</IsHdrSupported><AppTitle>  Resume</AppTitle><UUID>9a1c5a25-58fe-40e0-b9aa-7d3f00000001</UUID><ID>2147483511</ID></App>\
        <App><IsHdrSupported>0</IsHdrSupported><AppTitle> Terminate</AppTitle><UUID>9a1c5a25-58fe-40e0-b9aa-7d3f00000004</UUID><ID>2147483514</ID></App>\
        <App><IsHdrSupported>0</IsHdrSupported><AppTitle>Disconnect Monitor</AppTitle><ID>2147483502</ID></App>\
        </root>
        """
        let apps = try HostAppList.parse(Data(body.utf8)).apps
        XCTAssertEqual(apps.map(\.kind), [.runningGame, .resume, .terminate, .disconnectMonitor])
        XCTAssertEqual(apps.map(\.name), ["Desktop", "Resume", "Terminate", "Disconnect Monitor"])
        XCTAssertTrue(apps[2].mayAskToConfirm)
        XCTAssertFalse(apps[3].mayAskToConfirm)
    }

    func testPlainHTTPHasNoAppList() throws {
        XCTAssertEqual(try HostXML.parse(FixtureFile.data("vibeshine-2.0.1-power-actions-404.xml")).statusCode, 404)
    }
}

final class LaunchOptionsTests: XCTestCase {
    func testTheVirtualDisplayChoiceMapsToThreeRequests() {
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 60, virtualDisplay: .host).extraQueryString, "")
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 60, virtualDisplay: .virtual).extraQueryString, "&virtualDisplay=1")
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 60, virtualDisplay: .primary).extraQueryString, "&virtualDisplay=0")
    }

    func testEveryOptionTogether() {
        let options = LaunchOptions(width: 2420, height: 1668, refreshRate: 120, virtualDisplay: .virtual,
                                    scalePercent: 150, requestVRR: true, clientName: "Shev's iPad Pro")
        XCTAssertEqual(options.mode, "2420x1668x120")
        XCTAssertEqual(options.extraQueryString,
                       "&virtualDisplay=1&scaleFactor=150&clientVrrRequested=1&clientName=Shev%27s%20iPad%20Pro")
    }

    func testAScaleOf100OrNoneIsLeftOut() {
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 60, scalePercent: 100).extraQueryString, "")
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 60, scalePercent: 0).extraQueryString, "")
    }

    func testFractionalRatesAreSentAsVibeshineParsesThem() {
        XCTAssertEqual(LaunchOptions.formatRate(119.88), "119.88")
        XCTAssertEqual(LaunchOptions.formatRate(59.94), "59.94")
        XCTAssertEqual(LaunchOptions.formatRate(23.976), "23.976")
        XCTAssertEqual(LaunchOptions.formatRate(120), "120")
        XCTAssertEqual(LaunchOptions.formatRate(47.952), "47.952")
        XCTAssertEqual(LaunchOptions(width: 2420, height: 1668, refreshRate: 119.88).mode, "2420x1668x119.88")
    }

    func testTheStreamRunsAtTheRoundedRate() {
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 119.88).streamFrameRate, 120)
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 59.94).streamFrameRate, 60)
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 23.976).streamFrameRate, 24)
        XCTAssertEqual(LaunchOptions(width: 1, height: 1, refreshRate: 90).streamFrameRate, 90)
    }

    func testRatesOutsideWhatVibeshineTakesAreRefused() {
        XCTAssertNil(LaunchOptions.parseRate("5"))
        XCTAssertNil(LaunchOptions.parseRate("1001"))
        XCTAssertNil(LaunchOptions.parseRate("fast"))
        XCTAssertEqual(LaunchOptions.parseRate(" 119.88 "), 119.88)
    }

    func testOptionsComeFromTheSettings() {
        let store = SettingsStore(storage: MemorySettingsStorage())
        store[.frameRate] = "119.88"
        store[.virtualDisplayMode] = .virtual
        store[.vrrRequest] = true
        let options = LaunchOptions(settings: store, width: 2420, height: 1668, deviceName: "iPad")
        XCTAssertEqual(options.mode, "2420x1668x119.88")
        XCTAssertEqual(options.extraQueryString, "&virtualDisplay=1&clientVrrRequested=1&clientName=iPad")

        store[.clientName] = "Living room iPad"
        XCTAssertEqual(LaunchOptions(settings: store, width: 1, height: 1, deviceName: "iPad").clientName, "Living room iPad")
    }
}

final class LaunchResponseTests: XCTestCase {
    private func outcome(_ name: String) throws -> LaunchOutcome {
        LaunchOutcome.classify(try HostXML.parse(FixtureFile.data(name)))
    }

    func testAStartedStream() throws {
        XCTAssertEqual(try outcome("source-launch-started.xml"),
                       .started(sessionURL: "rtsp://192.0.2.10:48010", virtualDisplayDriverReady: true, warning: nil))
    }

    func testTerminateAsksFirst() throws {
        guard case .needsConfirmation(let message) = try outcome("source-launch-terminate-ask.xml") else {
            return XCTFail("expected a question")
        }
        XCTAssertTrue(message.hasPrefix("This will close the active stream"))
        XCTAssertEqual(try outcome("source-launch-replace-ask.xml"),
                       .needsConfirmation(message: "An app is already running. Launch this app again within 60 seconds to confirm that you want to close it."))
    }

    func testResultsAreNotQuestions() throws {
        XCTAssertEqual(try outcome("source-launch-terminate-done.xml"),
                       .done(message: "Active stream terminated. Remote Monitor and Remote Input remain connected."))
        XCTAssertEqual(try outcome("source-launch-disconnect-monitor.xml"), .done(message: "Remote Monitor disconnected successfully."))
    }

    func testErrorsStayErrors() throws {
        XCTAssertEqual(try outcome("vibeshine-launch-missing-params.xml"), .failed(code: 400, message: "Missing a required launch parameter"))
    }

    func testTheConfirmationStepAsksOnceThenSendsAgain() throws {
        var flow = ConfirmedLaunch()
        XCTAssertEqual(flow.next(try outcome("source-launch-terminate-ask.xml")),
                       .ask("This will close the active stream but leave Remote Monitor and Remote Input connected. Launch Terminate again within 60 seconds to confirm this was intentional."))
        XCTAssertTrue(flow.asked)
        XCTAssertEqual(flow.next(try outcome("source-launch-terminate-done.xml")),
                       .finished("Active stream terminated. Remote Monitor and Remote Input remain connected."))
    }

    func testReplacingAGameAsksThenStarts() throws {
        var flow = ConfirmedLaunch()
        guard case .ask = flow.next(try outcome("source-launch-replace-ask.xml")) else { return XCTFail("expected a question") }
        XCTAssertEqual(flow.next(try outcome("source-launch-started.xml")), .start(sessionURL: "rtsp://192.0.2.10:48010"))
    }

    func testASecondQuestionEndsTheFlow() throws {
        var flow = ConfirmedLaunch()
        _ = flow.next(try outcome("source-launch-replace-ask.xml"))
        guard case .finished = flow.next(try outcome("source-launch-replace-ask.xml")) else {
            return XCTFail("a second question must not loop")
        }
    }

    func testTheObjCFormClassifiesTheSame() {
        XCTAssertEqual(LaunchOutcome.classify(statusCode: 410, message: "Remote Input disconnected successfully."),
                       .done(message: "Remote Input disconnected successfully."))
    }
}

final class VibeshineClientTests: XCTestCase {
    private let transport = FakeHostTransport()
    private lazy var client = VibeshineClient(transport: transport)

    func testBitrateChangeReturnsWhatTheHostApplied() async throws {
        transport.answer("/bitrate", try FixtureFile.response("vibeshine-bitrate-applied.xml"))
        let applied = try await client.setBitrate(kbps: 20000)
        XCTAssertEqual(applied, 20000)
        XCTAssertEqual(transport.requests.last?.pathAndQuery, "/bitrate?bitrate=20000")
    }

    func testBitrateErrorsCarryTheHostsMessage() async throws {
        transport.answer("/bitrate", try FixtureFile.response("vibeshine-bitrate-invalid.xml"))
        do {
            _ = try await client.setBitrate(kbps: 0)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VibeshineError, .host(400, "Missing or invalid bitrate parameter"))
        }
    }

    func testTheHostWantsTheClientToChangeBitrate() async throws {
        transport.answer("/api/abr/capabilities", try FixtureFile.response("vibeshine-abr-capabilities.json"))
        let supported = try await client.supportsRuntimeBitrate()
        XCTAssertTrue(supported)
    }

    func testSleepAsksForATokenThenSendsIt() async throws {
        transport.answer("/power-actions/v1", try FixtureFile.response("source-power-actions-available.xml"))
        transport.answer("/power-actions/v1/sleep", try FixtureFile.response("source-power-sleep-accepted.xml", status: 202))
        try await client.sleep()
        XCTAssertEqual(transport.requests.map(\.method), [.get, .post])
        XCTAssertEqual(transport.requests.last?.pathAndQuery,
                       "/power-actions/v1/sleep?token=3f7a0c2d9e8b4a1f6c5d0e9b8a7f6e5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a99")
    }

    func testSleepNotAllowedSendsNothing() async throws {
        transport.answer("/power-actions/v1", try FixtureFile.response("source-power-actions-not-allowed.xml"))
        do {
            try await client.sleep()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? VibeshineError).map { if case .host(let code, _) = $0 { return code } else { return 0 } }, 403)
        }
        XCTAssertEqual(transport.requests.count, 1, "no sleep request without permission")
    }

    func testSleepOnAHostWithoutPowerActions() async throws {
        transport.answer("/power-actions/v1", try FixtureFile.response("vibeshine-2.0.1-power-actions-404.xml"))
        do {
            try await client.sleep()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VibeshineError, .host(404, ""))
        }
    }

    func testHardwareMetricsForTheOverlay() async throws {
        transport.answer("/api/hardware-metrics", try FixtureFile.response("source-hardware-metrics.json"))
        let metrics = try await client.hardwareMetrics()
        XCTAssertEqual(metrics.interval_ms, 1000)
        XCTAssertEqual(metrics.gpus?.first?.name, "NVIDIA GeForce RTX 5090")
        XCTAssertEqual(metrics.overlayText, "Host CPU 12%, GPU 64% (encoder 30%), 61 °C")
    }

    func testHardwareMetricsTurnedOffOnTheHost() async throws {
        transport.answer("/api/hardware-metrics", try FixtureFile.response("source-hardware-metrics-disabled.json", status: 403))
        do {
            _ = try await client.hardwareMetrics()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? VibeshineError, .host(403, "Hardware metrics are disabled"))
        }
    }

    func testMetricsWithMissingPartsLeaveThemOut() {
        let empty = HardwareMetrics(version: 1, sampled_at_unix_ms: nil, interval_ms: nil, cpu: nil, gpus: nil)
        XCTAssertEqual(empty.overlayText, "")
        let cpuOnly = HardwareMetrics(version: 1, sampled_at_unix_ms: nil, interval_ms: nil,
                                      cpu: .init(cpu_usage_percent: 7.5), gpus: [])
        XCTAssertEqual(cpuOnly.overlayText, "Host CPU 8%")
    }

    func testTheAppListThroughTheClient() async throws {
        transport.answer("/applist", try FixtureFile.response("vibeshine-applist.xml"))
        let apps = try await client.appList()
        XCTAssertEqual(apps.filter(\.isControl).map(\.kind), [.remoteInput, .remoteMonitor])
    }
}
