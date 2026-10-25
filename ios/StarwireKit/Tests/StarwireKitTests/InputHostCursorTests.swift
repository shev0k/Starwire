import XCTest
@testable import StarwireKit

// "Hide PC cursor" against Starwire for Android's HostCursorController and HostCursorLedger
// (HostCursorControllerTest.java, HostCursorLedgerTest.java).

private func down(_ code: Int, _ modifiers: Int = 0) -> InputEvent { .key(code: code, down: true, modifiers: modifiers) }
private func up(_ code: Int, _ modifiers: Int = 0) -> InputEvent { .key(code: code, down: false, modifiers: modifiers) }

/// Ctrl+Alt+Shift+N, pressed and released in one go
private let toggleKeys: [InputEvent] = [
    down(0xA2), down(0xA4, 0x02), down(0xA0, 0x06), down(0x4E, 0x07),
    up(0x4E, 0x07), up(0xA0, 0x06), up(0xA4, 0x02), up(0xA2, 0x00),
]

private let fixedTime: Int64 = 1_761_200_000_000

/// Counts toggles, and notes whether the record said "hidden" at the moment each one went out.
private final class FakeToggle: HostCursorToggle {
    var linkUp = true
    var recordedAtSend: [Bool] = []
    let ledger: HostCursorLedger

    init(ledger: HostCursorLedger) {
        self.ledger = ledger
    }

    var isLinkUp: Bool { linkUp }
    var sends: Int { recordedAtSend.count }

    func send() {
        XCTAssertTrue(linkUp, "toggle sent without a link")
        recordedAtSend.append(ledger.read() != nil)
    }
}

final class InputHostCursorLedgerTests: XCTestCase {
    private let host = "0F1E2D3C-host-a"
    private var store = MemoryHostCursorLedgerStore()

    override func setUp() {
        store = MemoryHostCursorLedgerStore()
    }

    private func ledger(_ key: String? = nil) -> HostCursorLedger {
        HostCursorLedger(store: store, hostKey: key ?? host, nowMilliseconds: { fixedTime })
    }

    func testNoRecordMeansNothingToFix() {
        XCTAssertNil(ledger().read())
    }

    func testANewInstanceSeesTheRecord() {
        ledger().markHidden(appID: 7, reason: "always")

        // A fresh object on the same store stands in for the app being killed and started again
        XCTAssertEqual(ledger().read(), HostCursorDebt(hiddenAtMilliseconds: fixedTime, appID: 7, reason: "always"))
    }

    func testTheRecordIsAndroidsText() {
        ledger().markHidden(appID: 7, reason: "always")
        XCTAssertEqual(store.values, ["host_cursor." + host: "v1 hidden 1761200000000 7 always"])
    }

    // The format a record is saved in, so records written by Android's code still read
    func testReadsTheSavedFormat() {
        store.setString("v1 hidden 1761200000000 42 terminated:-1\n", forKey: "host_cursor." + host)
        let debt = ledger().read()
        XCTAssertEqual(debt?.hiddenAtMilliseconds, 1_761_200_000_000)
        XCTAssertEqual(debt?.appID, 42)
        XCTAssertEqual(debt?.reason, "terminated:-1")
        XCTAssertEqual(debt?.description, "hidden at 1761200000000 (app 42, terminated:-1)")
    }

    func testMarkShownRemovesTheRecord() {
        let ledger = ledger()
        ledger.markHidden(appID: 7, reason: "touch")
        XCTAssertEqual(store.values.count, 1)

        ledger.markShown()
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertNil(self.ledger().read())

        // Showing twice is harmless
        ledger.markShown()
        XCTAssertNil(ledger.read())
    }

    func testADamagedRecordReadsAsNothing() {
        for damaged in ["not a cursor record", "v1 hidden soon 7 always", "v2 hidden 1 7 always", "v1 hidden notanumber",
                        "v1 shown 1 7 always", "v1 hidden 1 seven always", ""] {
            store.setString(damaged, forKey: "host_cursor." + host)
            XCTAssertNil(ledger().read(), damaged)
        }
    }

    func testSetReasonKeepsTheRecordAndItsApp() {
        let ledger = ledger()
        ledger.markHidden(appID: 42, reason: "always")
        ledger.setReason("terminated:-1")

        let debt = self.ledger().read()
        XCTAssertEqual(debt?.appID, 42)
        XCTAssertEqual(debt?.reason, "terminated:-1")
    }

    func testSetReasonWithoutARecordAddsNone() {
        let ledger = ledger()
        ledger.setReason("terminated:-1")
        XCTAssertNil(ledger.read())
        XCTAssertTrue(store.values.isEmpty)
    }

    func testReasonsWithSpacesSurviveAndNewLinesAreFlattened() {
        ledger().markHidden(appID: 1, reason: "stopped without a link")
        XCTAssertEqual(ledger().read()?.reason, "stopped without a link")
        ledger().markHidden(appID: 1, reason: "two\nlines")
        XCTAssertEqual(ledger().read()?.reason, "two lines")
        ledger().markHidden(appID: 1, reason: "")
        XCTAssertEqual(ledger().read()?.reason, "-")
    }

    func testEachPCHasItsOwnRecord() {
        let byAddress = HostCursorLedger.hostKey(pcUUID: nil, host: "192.168.1.20")
        XCTAssertEqual(byAddress, "addr:192.168.1.20")
        XCTAssertEqual(HostCursorLedger.hostKey(pcUUID: host, host: "192.168.1.20"), host)

        ledger().markHidden(appID: 1, reason: "always")
        XCTAssertNil(ledger(byAddress).read())
        ledger(byAddress).markShown()
        XCTAssertNotNil(ledger().read())
    }

    func testTheUserDefaultsStoreKeepsAString() {
        let name = "StarwireKitTests.HostCursor"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsHostCursorLedgerStore(defaults: defaults)
        XCTAssertNil(store.string(forKey: "k"))
        store.setString("v", forKey: "k")
        XCTAssertEqual(store.string(forKey: "k"), "v")
        store.removeString(forKey: "k")
        XCTAssertNil(store.string(forKey: "k"))
    }
}

final class InputHostCursorControllerTests: XCTestCase {
    private var store = MemoryHostCursorLedgerStore()
    private var ledger: HostCursorLedger!
    private var toggle: FakeToggle!

    override func setUp() {
        store = MemoryHostCursorLedgerStore()
        ledger = HostCursorLedger(store: store, hostKey: "pc-a", nowMilliseconds: { fixedTime })
        toggle = FakeToggle(ledger: ledger)
    }

    private func controller(_ mode: HideCursorMode) -> HostCursorController {
        HostCursorController(mode: mode, ledger: ledger, toggle: toggle, appID: 7)
    }

    // What an earlier Starwire process left behind when it was killed with the cursor hidden
    private func leftHiddenEarlier() {
        HostCursorLedger(store: store, hostKey: "pc-a", nowMilliseconds: { fixedTime }).markHidden(appID: 7, reason: "always")
    }

    // MARK: What is sent

    func testTheToggleIsCtrlAltShiftNPressedAndReleasedInOrder() {
        XCTAssertEqual(HostCursorController.toggleEvents, toggleKeys)
    }

    func testTheKeyToggleSendsThoseEventsOnTheSink() {
        let sink = RecordingInputSink()
        var linkUp = false
        let keys = KeyHostCursorToggle(sink: sink, isLinkUp: { linkUp })
        XCTAssertFalse(keys.isLinkUp)
        linkUp = true
        XCTAssertTrue(keys.isLinkUp)
        keys.send()
        XCTAssertEqual(sink.events, toggleKeys)
    }

    func testTheSettingValuesAreAndroids() {
        XCTAssertEqual(HideCursorMode(settingValue: "never"), .never)
        XCTAssertEqual(HideCursorMode(settingValue: "touching"), .touching)
        XCTAssertEqual(HideCursorMode(settingValue: "always"), .always)
        XCTAssertEqual(HideCursorMode(settingValue: "something else"), .never)
        XCTAssertEqual(HideCursorMode.allCases.map(\.rawValue), SettingsCatalog.definition("hide_cursor_mode")?.allowedValues)
    }

    // MARK: Hiding

    func testAlwaysHidesAtStartAfterWritingTheRecord() {
        let c = controller(.always)
        XCTAssertEqual(c.onStreamStarted(resumedSession: false), .nothing)
        XCTAssertEqual(toggle.sends, 1)
        XCTAssertEqual(toggle.recordedAtSend, [true], "record written before the toggle")
        XCTAssertTrue(c.isBelievedHidden)
        XCTAssertEqual(ledger.read(), HostCursorDebt(hiddenAtMilliseconds: fixedTime, appID: 7, reason: "always"))
    }

    func testNeverAndTouchingSendNothingAtStart() {
        XCTAssertEqual(controller(.never).onStreamStarted(resumedSession: false), .nothing)
        XCTAssertEqual(controller(.touching).onStreamStarted(resumedSession: false), .nothing)
        XCTAssertEqual(toggle.sends, 0)
        XCTAssertNil(ledger.read())
    }

    func testNoLinkMeansNoToggleAndNoRecord() {
        toggle.linkUp = false
        let c = controller(.always)
        c.onStreamStarted(resumedSession: false)
        XCTAssertEqual(toggle.sends, 0)
        XCTAssertFalse(c.isBelievedHidden)
        XCTAssertNil(ledger.read())
    }

    // MARK: Ending

    func testACleanStopShowsItAndClearsTheRecordAfterTheFlush() {
        let c = controller(.always)
        c.onStreamStarted(resumedSession: false)

        XCTAssertTrue(c.onStopping(), "the caller should wait before stopping")
        XCTAssertEqual(toggle.sends, 2)
        XCTAssertFalse(c.isBelievedHidden)
        XCTAssertNotNil(ledger.read(), "kept until the toggle has had time to arrive")

        c.onShowFlushed()
        XCTAssertNil(ledger.read())
        XCTAssertTrue(store.values.isEmpty)

        // Stopping again does nothing
        XCTAssertFalse(c.onStopping())
        XCTAssertEqual(toggle.sends, 2)
    }

    func testStopWithTheCursorShowingNeedsNoFlush() {
        let c = controller(.never)
        c.onStreamStarted(resumedSession: false)
        XCTAssertFalse(c.onStopping())
        XCTAssertEqual(toggle.sends, 0)
    }

    func testALostConnectionKeepsTheRecord() {
        let c = controller(.always)
        c.onStreamStarted(resumedSession: false)

        c.onConnectionLost(errorCode: -1)
        XCTAssertEqual(toggle.sends, 1)
        XCTAssertFalse(c.isBelievedHidden)
        XCTAssertEqual(ledger.read()?.reason, "terminated:-1")

        // The stop that follows sends nothing on the dead link
        XCTAssertFalse(c.onStopping())
        XCTAssertEqual(toggle.sends, 1)
        XCTAssertNotNil(ledger.read())
    }

    func testStopWithoutALinkKeepsTheRecord() {
        let c = controller(.always)
        c.onStreamStarted(resumedSession: false)
        toggle.linkUp = false

        XCTAssertFalse(c.onStopping())
        XCTAssertEqual(toggle.sends, 1)
        XCTAssertEqual(ledger.read()?.reason, "stopped without a link")
    }

    // MARK: Crash and recovery

    func testHideThenCrashThenRecoverySendsTheShowSequence() {
        let sink = RecordingInputSink()
        let firstLedger = HostCursorLedger(store: store, hostKey: "pc-a", nowMilliseconds: { fixedTime })
        let first = HostCursorController(mode: .always, ledger: firstLedger,
                                         toggle: KeyHostCursorToggle(sink: sink, isLinkUp: { true }), appID: 7)
        first.onStreamStarted(resumedSession: false)
        XCTAssertEqual(sink.events, toggleKeys, "the hide")
        XCTAssertEqual(store.values["host_cursor.pc-a"], "v1 hidden 1761200000000 7 always")
        // The app is killed here: no stop, no callbacks

        let secondLedger = HostCursorLedger(store: store, hostKey: "pc-a", nowMilliseconds: { fixedTime + 60_000 })
        let second = HostCursorController(mode: .never, ledger: secondLedger,
                                          toggle: KeyHostCursorToggle(sink: sink, isLinkUp: { true }), appID: 8)
        XCTAssertEqual(second.onStreamStarted(resumedSession: false), .shown)
        XCTAssertEqual(sink.events, toggleKeys + toggleKeys, "the show is the same keys again")
        XCTAssertTrue(second.reconciledThisStream)
        XCTAssertFalse(second.isBelievedHidden)
        XCTAssertNil(secondLedger.read())
        XCTAssertTrue(store.values.isEmpty)

        // Nothing more to send at the end
        XCTAssertFalse(second.onStopping())
        XCTAssertEqual(sink.events.count, 16)
    }

    func testLeftHiddenIsShownForNeverAndTouching() {
        for mode in [HideCursorMode.never, .touching] {
            leftHiddenEarlier()
            let before = toggle.sends
            let c = controller(mode)

            XCTAssertEqual(c.onStreamStarted(resumedSession: false), .shown)
            XCTAssertEqual(toggle.sends, before + 1)
            XCTAssertFalse(c.isBelievedHidden)
            XCTAssertTrue(c.reconciledThisStream)
            XCTAssertNil(ledger.read())

            XCTAssertFalse(c.onStopping())
            XCTAssertEqual(toggle.sends, before + 1)
        }
    }

    func testLeftHiddenIsKeptForAlwaysWithoutSendingAnything() {
        leftHiddenEarlier()
        let c = controller(.always)

        XCTAssertEqual(c.onStreamStarted(resumedSession: true), .adopted)
        XCTAssertEqual(toggle.sends, 0)
        XCTAssertTrue(c.isBelievedHidden)
        XCTAssertFalse(c.reconciledThisStream)
        XCTAssertEqual(ledger.read()?.reason, "adopted")

        // And it is shown at the end as usual
        XCTAssertTrue(c.onStopping())
        XCTAssertEqual(toggle.sends, 1)
        c.onShowFlushed()
        XCTAssertNil(ledger.read())
    }

    func testLeftHiddenWithoutALinkStaysRecorded() {
        leftHiddenEarlier()
        toggle.linkUp = false
        XCTAssertEqual(controller(.never).onStreamStarted(resumedSession: false), .failed)
        XCTAssertEqual(toggle.sends, 0)
        XCTAssertNotNil(ledger.read())
    }

    func testKilledWithAFingerDownIsPutRightNextTime() {
        let first = controller(.touching)
        first.onStreamStarted(resumedSession: false)
        first.onFingerDown(now: 10)
        // The app is killed here

        let next = HostCursorController(mode: .never,
                                        ledger: HostCursorLedger(store: store, hostKey: "pc-a", nowMilliseconds: { fixedTime }),
                                        toggle: toggle, appID: 7)
        XCTAssertEqual(next.onStreamStarted(resumedSession: false), .shown)
        XCTAssertEqual(toggle.sends, 2)
        XCTAssertNil(ledger.read())
    }

    func testKilledAfterTheFingerLiftedLeavesNothingToFix() {
        let first = controller(.touching)
        first.onStreamStarted(resumedSession: false)
        first.onFingerDown(now: 10)
        first.onFingersUp(now: 10.1)
        first.tick(now: 10.4)

        XCTAssertEqual(controller(.never).onStreamStarted(resumedSession: false), .nothing)
        XCTAssertEqual(toggle.sends, 2)
    }

    func testEachPCIsSeparate() {
        leftHiddenEarlier()
        let other = HostCursorController(mode: .never, ledger: HostCursorLedger(store: store, hostKey: "pc-b"),
                                         toggle: toggle, appID: 7)
        XCTAssertEqual(other.onStreamStarted(resumedSession: false), .nothing)
        XCTAssertEqual(toggle.sends, 0)
        XCTAssertNotNil(ledger.read(), "pc-a still needs its cursor back")
    }

    func testNothingHappensIfTheStreamStartsAfterAStop() {
        let c = controller(.always)
        _ = c.onStopping()
        XCTAssertEqual(c.onStreamStarted(resumedSession: false), .nothing)
        XCTAssertEqual(toggle.sends, 0)
        XCTAssertNil(ledger.read())
    }

    // MARK: Touch

    func testTouchHidesAndShowsAgainAfterAPause() {
        let c = controller(.touching)
        c.onStreamStarted(resumedSession: false)
        XCTAssertNil(c.nextDeadline)

        c.onFingerDown(now: 5)
        XCTAssertEqual(toggle.sends, 1)
        XCTAssertEqual(toggle.recordedAtSend, [true])
        XCTAssertTrue(c.isBelievedHidden)

        c.onFingersUp(now: 6)
        XCTAssertEqual(toggle.sends, 1, "shown only after the pause")
        XCTAssertEqual(c.nextDeadline, 6.3)
        c.tick(now: 6.2)
        XCTAssertEqual(toggle.sends, 1)

        c.tick(now: 6.3)
        XCTAssertEqual(toggle.sends, 2)
        XCTAssertFalse(c.isBelievedHidden)
        XCTAssertNil(ledger.read())
        XCTAssertNil(c.nextDeadline)
    }

    func testQuickTapsDontSendTheToggleAgain() {
        let c = controller(.touching)
        c.onStreamStarted(resumedSession: false)

        c.onFingerDown(now: 1)
        c.onFingersUp(now: 1.05)
        c.onFingerDown(now: 1.1)
        c.onFingersUp(now: 1.15)
        c.onFingerDown(now: 1.2)
        XCTAssertEqual(toggle.sends, 1)
        XCTAssertNil(c.nextDeadline, "a finger down cancels the pending show")

        c.onFingersUp(now: 1.25)
        XCTAssertEqual(c.nextDeadline, 1.25 + 0.3)
        c.tick(now: 2)
        XCTAssertEqual(toggle.sends, 2)
    }

    func testTouchesDoNothingInTheOtherModes() {
        let never = controller(.never)
        never.onStreamStarted(resumedSession: false)
        never.onFingerDown(now: 1)
        never.onFingersUp(now: 2)

        let always = controller(.always)
        always.onStreamStarted(resumedSession: false)
        always.onFingerDown(now: 3)
        always.onFingersUp(now: 4)

        XCTAssertEqual(toggle.sends, 1)
        XCTAssertNil(never.nextDeadline)
        XCTAssertNil(always.nextDeadline)
    }

    func testStopDuringThePauseShowsItAtOnce() {
        let c = controller(.touching)
        c.onStreamStarted(resumedSession: false)
        c.onFingerDown(now: 1)
        c.onFingersUp(now: 2)

        XCTAssertTrue(c.onStopping())
        XCTAssertNil(c.nextDeadline, "the delayed show is cancelled")
        XCTAssertEqual(toggle.sends, 2)

        // Touches after the stop are ignored
        c.onFingerDown(now: 3)
        XCTAssertEqual(toggle.sends, 2)
    }

    // MARK: Fix PC cursor

    func testFixSendsOnceAndChangesNothingElse() {
        let c = controller(.always)
        c.onStreamStarted(resumedSession: false)

        XCTAssertTrue(c.onManualFix())
        XCTAssertEqual(toggle.sends, 2)
        XCTAssertTrue(c.isBelievedHidden)
        XCTAssertNotNil(ledger.read())

        let otherLedger = HostCursorLedger(store: store, hostKey: "pc-b")
        let never = HostCursorController(mode: .never, ledger: otherLedger, toggle: toggle, appID: 7)
        never.onStreamStarted(resumedSession: false)
        XCTAssertTrue(never.onManualFix())
        XCTAssertEqual(toggle.sends, 3)
        XCTAssertFalse(never.isBelievedHidden)
        XCTAssertNil(otherLedger.read())
    }

    func testFixDoesNothingAfterTheStreamEndsOrWithoutALink() {
        let c = controller(.never)
        c.onStreamStarted(resumedSession: false)
        toggle.linkUp = false
        XCTAssertFalse(c.onManualFix())
        toggle.linkUp = true
        _ = c.onStopping()
        XCTAssertFalse(c.onManualFix())
        XCTAssertEqual(toggle.sends, 0)
    }

    func testFixIsOfferedWhereHidingIsUsedOrAReconcileHappened() {
        XCTAssertFalse(controller(.never).isFixOffered(hostHasToggle: true))
        XCTAssertTrue(controller(.touching).isFixOffered(hostHasToggle: true))
        XCTAssertTrue(controller(.always).isFixOffered(hostHasToggle: true))
        XCTAssertFalse(controller(.always).isFixOffered(hostHasToggle: false))

        leftHiddenEarlier()
        let c = controller(.never)
        c.onStreamStarted(resumedSession: false)
        XCTAssertTrue(c.isFixOffered(hostHasToggle: true))
        XCTAssertFalse(c.isFixOffered(hostHasToggle: false))
    }
}
