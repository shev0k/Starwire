import XCTest
@testable import StarwireKit

final class PairStateCheckTests: XCTestCase {
    private let clock = FakeClock()
    private var check: PairStateCheck { PairStateCheck(clock: clock) }

    private func neverAsked() -> HostPairState? {
        XCTFail("asked again when it shouldn't")
        return nil
    }

    func testAnUnpinnedHostIsTakenAtItsWord() {
        var known = KnownPairing(pairState: .unknown, hasPinnedCertificate: false)
        let verdict = check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: false), known: &known, askAgain: neverAsked)
        XCTAssertEqual(verdict, .accept(.unpaired))
        XCTAssertNil(known.refusedSince)
    }

    func testAPinnedHostRefusingIsIgnoredDuringTheGrace() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true)
        let refusal = PairPollAnswer(pairState: .unpaired, authenticated: false)

        XCTAssertEqual(check.evaluate(refusal, known: &known, askAgain: neverAsked), .ignore)
        XCTAssertEqual(known.refusedSince, clock.now)

        clock.advance(by: PairStateCheck.refusalGrace - 1)
        XCTAssertEqual(check.evaluate(refusal, known: &known, askAgain: neverAsked), .ignore)
    }

    func testAPinnedHostRefusingPastTheGraceIsUnpaired() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true)
        let refusal = PairPollAnswer(pairState: .unpaired, authenticated: false)
        _ = check.evaluate(refusal, known: &known, askAgain: neverAsked)

        clock.advance(by: PairStateCheck.refusalGrace)
        XCTAssertEqual(check.evaluate(refusal, known: &known, askAgain: neverAsked), .accept(.unpaired))
    }

    func testAnAuthenticatedAnswerEndsTheGrace() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true)
        _ = check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: false), known: &known, askAgain: neverAsked)
        clock.advance(by: 20)

        XCTAssertEqual(check.evaluate(PairPollAnswer(pairState: .paired, authenticated: true), known: &known, askAgain: neverAsked), .accept(.paired))
        XCTAssertNil(known.refusedSince)

        // A new refusal gets the whole grace again
        clock.advance(by: 20)
        XCTAssertEqual(check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: false), known: &known, askAgain: neverAsked), .ignore)
    }

    func testNoAnswerAtAllRestartsTheGrace() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true, refusedSince: clock.now)
        check.noAnswer(known: &known, refused: false)
        XCTAssertNil(known.refusedSince)

        known.refusedSince = clock.now
        check.noAnswer(known: &known, refused: true)
        XCTAssertEqual(known.refusedSince, clock.now)
    }

    func testAPairedHostSayingUnpairedIsAskedAgain() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true)
        var asked = 0
        let verdict = check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: true), known: &known) {
            asked += 1
            return .paired
        }
        XCTAssertEqual(verdict, .accept(.paired))
        XCTAssertEqual(asked, 1)
    }

    func testAPairedHostSayingUnpairedTwiceIsUnpaired() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true)
        let verdict = check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: true), known: &known) { .unpaired }
        XCTAssertEqual(verdict, .accept(.unpaired))
    }

    func testAPairedHostThatDoesntAnswerAgainStaysPaired() {
        var known = KnownPairing(pairState: .paired, hasPinnedCertificate: true)
        let verdict = check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: true), known: &known) { nil }
        XCTAssertEqual(verdict, .accept(.paired))
    }

    func testTheFirstPollAfterLaunchCountsAPinnedHostAsPaired() {
        // Not polled yet since the app started, but it has the PC's certificate
        var known = KnownPairing(pairState: .unknown, hasPinnedCertificate: true)
        var asked = false
        _ = check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: true), known: &known) {
            asked = true
            return .paired
        }
        XCTAssertTrue(asked)
    }

    func testAnUnpairedHostIsNotAskedAgain() {
        var known = KnownPairing(pairState: .unpaired, hasPinnedCertificate: true)
        XCTAssertEqual(check.evaluate(PairPollAnswer(pairState: .unpaired, authenticated: true), known: &known, askAgain: neverAsked), .accept(.unpaired))
    }
}

final class MacAddressTests: XCTestCase {
    func testAZeroAddressNeverReplacesAKnownOne() {
        XCTAssertEqual(MacAddress.merge(saved: "AA:BB:CC:DD:EE:FF", polled: "00:00:00:00:00:00"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(MacAddress.merge(saved: "AA:BB:CC:DD:EE:FF", polled: nil), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(MacAddress.merge(saved: "AA:BB:CC:DD:EE:FF", polled: "  "), "AA:BB:CC:DD:EE:FF")
    }

    func testANewAddressReplacesTheOldOne() {
        XCTAssertEqual(MacAddress.merge(saved: "AA:BB:CC:DD:EE:FF", polled: "11:22:33:44:55:66"), "11:22:33:44:55:66")
    }

    func testAddressesAreNormalized() {
        XCTAssertEqual(MacAddress.merge(saved: nil, polled: "aa-bb-cc-dd-ee-ff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertNil(MacAddress.merge(saved: "00:00:00:00:00:00", polled: nil))
    }
}
