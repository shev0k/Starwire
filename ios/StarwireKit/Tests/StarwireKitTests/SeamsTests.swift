import XCTest
@testable import StarwireKit

final class LaunchRequestTests: XCTestCase {
    func testTheRealHostServiceSendsTheFullLaunch() async throws {
        let transport = FakeHostTransport()
        transport.answer("/launch", try FixtureFile.response("source-launch-replace-ask.xml"),
                         try FixtureFile.response("source-launch-started.xml"))
        let host: HostService = VibeshineClient(transport: transport)
        let request = LaunchRequest(appID: "707688810",
                                    options: LaunchOptions(width: 2420, height: 1668, refreshRate: 120, virtualDisplay: .virtual,
                                                           requestVRR: true, clientName: "iPad"),
                                    inputKey: Data([0xAB, 0x01]), inputKeyID: 7, hdr: true)

        var flow = ConfirmedLaunch()
        let first = try await host.launch(request)
        guard case .ask = flow.next(first) else { return XCTFail("expected a question") }
        let second = try await host.launch(request)
        XCTAssertEqual(flow.next(second), .start(sessionURL: "rtsp://192.0.2.10:48010"))

        let sent = transport.requests.last!
        XCTAssertEqual(sent.path, "/launch")
        XCTAssertEqual(sent.pathAndQuery,
                       "/launch?uniqueid=0123456789ABCDEF&appid=707688810&mode=2420x1668x120&additionalStates=1&sops=1"
                       + "&rikey=AB01&rikeyid=7&localAudioPlayMode=0&surroundAudioInfo=196610&remoteControllersBitmap=0&gcmap=0"
                       + "&hdrMode=1&virtualDisplay=1&clientVrrRequested=1&clientName=iPad")
        XCTAssertEqual(transport.requests.count, 2, "the confirmation is the same request again")
        XCTAssertEqual(transport.requests[0], transport.requests[1])
    }

    func testResumeUsesItsOwnPath() {
        let request = LaunchRequest(appID: "1", options: LaunchOptions(width: 1, height: 1, refreshRate: 60),
                                    inputKey: Data(), inputKeyID: 0, resume: true)
        XCTAssertEqual(request.hostRequest.path, "/resume")
    }
}

final class FakeSeamTests: XCTestCase {
    func testTheFakeHostClampsBitrateAndRecordsIt() async throws {
        let host = DemoMode.hostService()
        let first = try await host.setBitrate(kbps: 50000)
        let second = try await host.setBitrate(kbps: 900_000)
        XCTAssertEqual(first, 50000)
        XCTAssertEqual(second, 150_000)
        XCTAssertEqual(host.bitrates, [50000, 150_000])
    }

    func testTheFakeHostRefusesSleepWhenNotAllowed() async throws {
        let host = DemoMode.hostService()
        try await host.sleep()
        XCTAssertEqual(host.sleeps, 1)

        var info = DemoMode.serverInfo().xml
        info.fields["SleepAllowed"] = "0"
        host.info = ServerInfo(xml: info)
        do {
            try await host.sleep()
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(host.sleeps, 1)
    }

    func testTheFakePairingShowsThePIN() async throws {
        let pairing = FakePairingService()
        var shown: String?
        let result = try await pairing.pair(address: "192.0.2.10") { shown = $0 }
        XCTAssertEqual(shown, "1234")
        XCTAssertEqual(result, .paired(serverCertificate: Data("demo certificate".utf8)))

        pairing.result = .failure(.failed("Wrong PIN"))
        do {
            _ = try await pairing.pair(address: "192.0.2.10") { _ in }
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PairingError, .failed("Wrong PIN"))
        }
    }

    func testRecordingInputKeepsTheOrder() {
        let input = RecordingInputSink()
        input.send(.mouseMove(dx: 3, dy: -1))
        input.send(.mouseButton(button: 1, down: true))
        input.send(.mouseButton(button: 1, down: false))
        XCTAssertEqual(input.events, [.mouseMove(dx: 3, dy: -1), .mouseButton(button: 1, down: true), .mouseButton(button: 1, down: false)])
    }
}

final class DemoModeTests: XCTestCase {
    func testTheDemoPCIsAPairedVibeshineHostWithTiles() async throws {
        let host: HostService = DemoMode.hostService()
        let info = try await host.serverInfo()
        XCTAssertEqual(info.hostName, "Demo PC")
        XCTAssertEqual(info.pairState, .paired)
        XCTAssertTrue(info.isVibeshine)
        XCTAssertTrue(info.sleepAllowed)
        let apps = try await host.appList()
        XCTAssertEqual(apps.filter(\.isControl).map(\.kind), [.remoteInput, .remoteMonitor])
        let metrics = try await host.hardwareMetrics()
        XCTAssertEqual(metrics.overlayText, "Host CPU 9%, GPU 41% (encoder 22%), 55 °C")
    }

    func testADemoStreamGoesThroughTheStagesThenShowsFramesOnTime() {
        let clock = FakeClock()
        let video = CountingVideoSink()
        let session = DemoStreamSession(video: video, input: RecordingInputSink(), clock: clock, width: 64, height: 36, fps: 60)
        var states: [StreamState] = []
        session.onStateChange = { states.append($0) }

        session.start()
        XCTAssertEqual(states, DemoStreamSession.stages.map { .starting(stage: $0) } + [.streaming])

        XCTAssertEqual(session.tick(), 1, "the first frame right away")
        clock.advance(by: 0.5)
        XCTAssertEqual(session.tick(), 30)
        XCTAssertEqual(video.framesShown, 31)
        XCTAssertEqual(video.lastFrame?.index, 30)
        XCTAssertEqual(video.lastFrame?.bgra?.count, 64 * 36 * 4)

        session.stop()
        XCTAssertEqual(session.state, .ended(error: nil))
        XCTAssertEqual(video.flushes, 1)
        clock.advance(by: 1)
        XCTAssertEqual(session.tick(), 0, "no frames after the end")
    }

    func testTheDemoPictureMoves() {
        let a = DemoMode.frame(index: 0, width: 64, height: 32, fps: 60)
        let b = DemoMode.frame(index: 30, width: 64, height: 32, fps: 60)
        XCTAssertNotEqual(a.bgra, b.bgra)
        // The left edge of the middle row is the white bar or the block: white either way
        let row = 16 * 64 * 4
        XCTAssertEqual(Array(a.bgra![row..<(row + 4)]), [255, 255, 255, 255])
        // The last bar is black, away from the block's path at the start
        let lastBar = (2 * 64 + 63) * 4
        XCTAssertEqual(Array(a.bgra![lastBar..<(lastBar + 3)]), [0, 0, 0])
    }
}
