import Foundation

/// Whether this client is paired with a PC, as the app knows it. The raw values match the ObjC
/// `PairState` enum in Utils.h, so the two can be passed across as integers.
public enum HostPairState: Int, Sendable {
    case unknown = 0
    case unpaired = 1
    case paired = 2
}

/// One serverinfo answer, reduced to what the pair-state rules need.
public struct PairPollAnswer: Equatable, Sendable {
    /// What the answer's `PairStatus` says.
    public var pairState: HostPairState
    /// True when the answer came over HTTPS with the PC's pinned certificate and this client's
    /// certificate. A plain HTTP answer, such as the fallback after a 401, is never
    /// authenticated, and the host always says "not paired" there.
    public var authenticated: Bool

    public init(pairState: HostPairState, authenticated: Bool) {
        self.pairState = pairState
        self.authenticated = authenticated
    }
}

/// What the app knew about a PC before the poll.
public struct KnownPairing: Equatable, Sendable {
    public var pairState: HostPairState
    /// True when the app keeps the PC's certificate from the day it paired.
    public var hasPinnedCertificate: Bool
    /// When the PC started answering only without authenticating, on `Clock.now`. Nil when it
    /// isn't doing that.
    public var refusedSince: TimeInterval?

    public init(pairState: HostPairState, hasPinnedCertificate: Bool, refusedSince: TimeInterval? = nil) {
        self.pairState = pairState
        self.hasPinnedCertificate = hasPinnedCertificate
        self.refusedSince = refusedSince
    }
}

/// What to do with a poll's answer.
public enum PairPollVerdict: Equatable, Sendable {
    /// Use the answer, with this pair state.
    case accept(HostPairState)
    /// Leave the PC as it was: the answer may be a passing refusal (see `PairStateCheck`).
    case ignore
}

/// Folds a poll's answer into what's known about a PC, so one odd answer can't unpair it.
///
/// Two rules, from two clients that met the same problem:
///
/// - **Refusal grace** (daniel-zn's Artemis iOS, DiscoveryWorker): a PC whose certificate is
///   pinned sometimes answers HTTPS with 401 for a moment, for example while it restarts or
///   reloads its paired clients. The app then asks over plain HTTP, where the host always says
///   "not paired". Such answers are ignored for `refusalGrace` seconds; only a PC that keeps
///   refusing for longer is taken as unpaired.
/// - **Ask again** (Starwire for Android, PairStateCheck): a PC that was paired and now says
///   over HTTPS that it isn't is asked once more on its own. Only a second "not paired" counts.
///   Vibepollo answered about a third of simultaneous requests that way.
///
/// The clock is injected, so tests move time by hand.
public struct PairStateCheck: Sendable {
    /// How long a pinned PC may refuse this client before the app believes it.
    public static let refusalGrace: TimeInterval = 30

    public let clock: Clock

    public init(clock: Clock) {
        self.clock = clock
    }

    /// Decides what a poll's answer means. `known.refusedSince` is updated in place.
    /// `askAgain` runs only when the answer would turn a paired PC into an unpaired one; it
    /// returns the pair state from one more authenticated serverinfo request, or nil if that
    /// request failed.
    public func evaluate(_ answer: PairPollAnswer, known: inout KnownPairing,
                         askAgain: () -> HostPairState?) -> PairPollVerdict {
        if known.hasPinnedCertificate && !answer.authenticated {
            let since = known.refusedSince ?? clock.now
            known.refusedSince = since
            if clock.now - since < Self.refusalGrace {
                return .ignore
            }
            return .accept(answer.pairState)
        }

        if answer.authenticated {
            known.refusedSince = nil
        }
        if Self.wasPaired(known) && answer.pairState == .unpaired {
            // Nothing to confirm it with: it stays paired, and the next poll asks again
            return .accept(askAgain() ?? .paired)
        }
        return .accept(answer.pairState)
    }

    /// Call when a poll got no answer from any address. A PC that stops answering isn't
    /// refusing, so the grace starts again the next time it refuses.
    public func noAnswer(known: inout KnownPairing, refused: Bool) {
        if !refused {
            known.refusedSince = nil
        }
    }

    // Paired at its last poll, or not polled yet since the app started and paired before: the
    // app keeps a PC's certificate from the day it paired.
    static func wasPaired(_ known: KnownPairing) -> Bool {
        known.pairState == .paired || (known.pairState == .unknown && known.hasPinnedCertificate)
    }
}
