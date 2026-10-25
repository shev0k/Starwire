//
//  StarwirePairState.swift
//  Starwire
//
//  StarwireKit's pair-state rules (PairStateCheck: the refusal grace and asking again) and its
//  MAC rule, for the ObjC discovery code.
//

import Foundation
import StarwireKit

@objc(StarwirePairState)
final class StarwirePairState: NSObject {
    /// The clock for the refusal grace. The unit tests replace it with a FakeClock.
    static var clock: Clock = SystemClock.shared

    /// What a poll's answer means. Returns the pair state to take (the ObjC PairState values),
    /// or -1 to ignore the answer and leave the PC as it was. `refusedSince` is the PC's (nil or a
    /// time on the same clock) and is updated in place. `askAgain` runs at most once, when a
    /// paired PC says it isn't; it returns a PairState, or -1 if that request failed too.
    @objc static func evaluate(answerState: Int, authenticated: Bool, knownState: Int, pinned: Bool,
                               refusedSince: UnsafeMutablePointer<NSNumber?>,
                               askAgain: () -> Int) -> Int {
        var known = KnownPairing(pairState: HostPairState(rawValue: knownState) ?? .unknown,
                                 hasPinnedCertificate: pinned, refusedSince: refusedSince.pointee?.doubleValue)
        let answer = PairPollAnswer(pairState: HostPairState(rawValue: answerState) ?? .unknown, authenticated: authenticated)
        let verdict = PairStateCheck(clock: clock).evaluate(answer, known: &known) {
            let again = askAgain()
            return again < 0 ? nil : HostPairState(rawValue: again)
        }
        refusedSince.pointee = known.refusedSince.map { NSNumber(value: $0) }
        switch verdict {
        case .accept(let state):
            return state.rawValue
        case .ignore:
            return -1
        }
    }

    /// Call when no address answered. A PC that answers nothing isn't refusing.
    @objc static func noAnswer(refused: Bool, refusedSince: UnsafeMutablePointer<NSNumber?>) {
        var known = KnownPairing(pairState: .unknown, hasPinnedCertificate: true, refusedSince: refusedSince.pointee?.doubleValue)
        PairStateCheck(clock: clock).noAnswer(known: &known, refused: refused)
        refusedSince.pointee = known.refusedSince.map { NSNumber(value: $0) }
    }

    /// The MAC to keep: a poll that sends none or all zeros never replaces a known one.
    @objc static func mergeMac(saved: String?, polled: String?) -> String? {
        MacAddress.merge(saved: saved, polled: polled)
    }

    /// For the unit tests: a clock that only moves when told to.
    @objc static func useFakeClock() {
        clock = FakeClock()
    }

    @objc static func advanceFakeClock(_ seconds: Double) {
        (clock as? FakeClock)?.advance(by: seconds)
    }

    @objc static func useSystemClock() {
        clock = SystemClock.shared
    }
}
