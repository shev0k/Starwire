import Crypto
import Foundation

// Ported from Starwire for Android's SecureVbanSender.java (GPL-3.0): the same timings and rules
// (docs/dev/mic-protocol.md, "Rules for Starwire"), without the socket and the thread, so the
// tests drive it with injected time.

/// Random bytes for keys, nonces and HELLOs. The app's comes from the system's secure generator;
/// tests pass a fixed sequence.
public protocol RandomBytes: AnyObject {
    func bytes(_ count: Int) -> [UInt8]
}

/// The system's cryptographically secure generator (SystemRandomNumberGenerator).
public final class SystemRandomBytes: RandomBytes {
    public init() {}

    public func bytes(_ count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }
}

/// Starwire's side of an encrypted microphone session with the PC's receiver.
///
/// The app owns the UDP socket. It calls `poll` when the last `wait` has passed (and after each
/// datagram), sends what `poll` returns, passes every datagram from the PC to `receive`, and
/// seals each VBAN packet with `seal` on the capture thread. A lock makes those safe to call from
/// two threads, as Android's sender does from its capture and receive threads.
public final class SwmcSender {
    public enum Status: Equatable, Sendable {
        case connecting
        case sending
        /// No HELLO_ACK within 3 s. It keeps trying.
        case noAnswer
        /// Another device has the PC's microphone.
        case busy
        /// The receiver has no audio output (VB-Cable missing).
        case noOutput
    }

    static let fastRetryMs: Int64 = 250
    static let fastRetriesForMs: Int64 = 2000
    static let slowRetryMs: Int64 = 2000
    static let noAnswerMs: Int64 = 3000
    static let rehelloGapMs: Int64 = 2000
    /// The longest `poll` asks to wait, so a used-up counter gets a new HELLO quickly
    static let maxWaitMs: Int64 = 50

    private struct Session {
        let key: SymmetricKey
        let id: [UInt8]
        var next: UInt64
    }

    private let lock = NSLock()
    private let random: RandomBytes
    private let deviceId: [UInt8]
    private let pairKey: [UInt8]
    private let authKey: [UInt8]

    /// Told when the status changes, on the thread that changed it.
    public var onStatus: ((Status) -> Void)?

    private var session: Session?
    private var needNewSession = false
    /// Sessions start their counter here: 0, except in tests of the counter running out.
    var firstCounter: UInt64 = 0
    public private(set) var dropped = 0
    public private(set) var sent = 0

    private var clientRandom: [UInt8] = []
    private var hello: [UInt8] = []
    /// The session the receiver first answered this HELLO with; nil until then
    private var helloSession: [UInt8]?
    private var helloStart: Int64 = 0
    private var hellosSent: Int64 = 0
    private var acked = false
    private var ackStatus = SwmcCodec.statusReady
    private var lastHelloAt: Int64 = 0
    private var lastRehelloAt = Int64.min / 2
    public private(set) var status: Status?

    public init(deviceId: [UInt8], pairKey: [UInt8], random: RandomBytes = SystemRandomBytes()) {
        precondition(deviceId.count == SwmcCodec.idLength && pairKey.count == SwmcCodec.keyLength)
        self.deviceId = deviceId
        self.pairKey = pairKey
        self.random = random
        self.authKey = SwmcCodec.authKey(pairKey: pairKey, deviceId: deviceId)
    }

    /// Starts the first handshake. `poll` sends its HELLO.
    public func start(now: TimeInterval) {
        var changed: Status?
        lock.lock()
        session = nil
        needNewSession = false
        changed = startHandshake(milliseconds(now))
        lock.unlock()
        report(changed)
    }

    // MARK: - The handshake

    private func milliseconds(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1000).rounded())
    }

    /// A new HELLO with a new client random. Returns the status to report, if it changed.
    private func startHandshake(_ now: Int64) -> Status? {
        clientRandom = random.bytes(SwmcCodec.idLength)
        hello = SwmcCodec.hello(authKey: authKey, deviceId: deviceId, clientRandom: clientRandom)
        helloStart = now
        hellosSent = 0
        acked = false
        helloSession = nil
        return setStatus(.connecting)
    }

    /// When the HELLO after the first n is due: every 250 ms for 2 s, then every 2 s.
    private func helloDue(_ n: Int64) -> Int64 {
        if n * Self.fastRetryMs <= Self.fastRetriesForMs {
            return helloStart + n * Self.fastRetryMs
        }
        let fast = Self.fastRetriesForMs / Self.fastRetryMs + 1
        return helloStart + Self.fastRetriesForMs + (n - fast + 1) * Self.slowRetryMs
    }

    /// What is due now, and how long until something else is (at most 50 ms).
    public func poll(now: TimeInterval) -> (packets: [[UInt8]], wait: TimeInterval) {
        let now = milliseconds(now)
        var packets: [[UInt8]] = []
        var changes: [Status] = []
        lock.lock()
        if needNewSession {
            needNewSession = false
            if let change = startHandshake(now) { changes.append(change) }
        }
        var next: Int64
        if !acked {
            if now >= helloDue(hellosSent) {
                lastHelloAt = now
                packets.append(hello)
                hellosSent += 1
                // After a long pause, don't send the ones that were missed all at once
                while helloDue(hellosSent) <= now {
                    hellosSent += 1
                }
            }
            next = helloDue(hellosSent)
            if now - helloStart >= Self.noAnswerMs {
                if let change = setStatus(.noAnswer) { changes.append(change) }
            } else {
                next = min(next, helloStart + Self.noAnswerMs)
            }
        } else if ackStatus != SwmcCodec.statusReady {
            // Busy or no output: ask again (same HELLO, same session) to see when it's ready
            if now - lastHelloAt >= Self.slowRetryMs {
                lastHelloAt = now
                packets.append(hello)
            }
            next = lastHelloAt + Self.slowRetryMs
        } else {
            next = now + Self.maxWaitMs
        }
        lock.unlock()
        changes.forEach { report($0) }
        let wait = max(0, min(next - now, Self.maxWaitMs))
        return (packets, TimeInterval(wait) / 1000)
    }

    /// Takes one datagram from the receiver. Anything that isn't an authentic answer to this
    /// device is ignored.
    public func receive(_ p: [UInt8], now: TimeInterval) {
        var change: Status?
        lock.lock()
        switch SwmcCodec.typeOf(p) {
        case SwmcCodec.typeHelloAck:
            change = onAck(p, now: milliseconds(now))
        case SwmcCodec.typeRehello:
            change = onRehello(p, now: milliseconds(now))
        default:
            break
        }
        lock.unlock()
        report(change)
    }

    private func onAck(_ p: [UInt8], now: Int64) -> Status? {
        guard p.count == SwmcCodec.ackLength, SwmcCodec.isFor(p, deviceId: deviceId),
              SwmcCodec.contextIs(p, clientRandom), SwmcCodec.macOK(key: authKey, p) else {
            return nil
        }
        let serverRandom = Array(p[SwmcCodec.header..<(SwmcCodec.header + SwmcCodec.idLength)])
        if let helloSession, helloSession != serverRandom {
            // Another session for the same HELLO: the receiver restarted, or someone sent an older
            // answer again, whose key may already have sealed audio from counter 0. A HELLO only
            // ever gets one session, so ask with a new one; until it's answered, audio goes on in
            // the current session
            return startHandshake(now)
        }
        if helloSession == nil {
            // The first answer to this HELLO, and the only one it ever gets a session from
            let key = SwmcCodec.audioKey(pairKey: pairKey, deviceId: deviceId, clientRandom: clientRandom,
                                         serverRandom: serverRandom)
            session = Session(key: SymmetricKey(data: key), id: serverRandom, next: firstCounter)
            helloSession = serverRandom
        }
        acked = true
        ackStatus = p[SwmcCodec.ackStatusAt]
        switch ackStatus {
        case SwmcCodec.statusBusy:
            return setStatus(.busy)
        case SwmcCodec.statusNoOutput:
            return setStatus(.noOutput)
        default:
            // Ready, or a status a newer receiver added: the session works either way
            ackStatus = SwmcCodec.statusReady
            return setStatus(.sending)
        }
    }

    private func onRehello(_ p: [UInt8], now: Int64) -> Status? {
        guard p.count == SwmcCodec.helloLength, SwmcCodec.isFor(p, deviceId: deviceId),
              SwmcCodec.macOK(key: authKey, p) else {
            return nil
        }
        // Only for the session audio goes out on, and not while a new one is on its way
        guard let current = session?.id, acked, SwmcCodec.contextIs(p, current),
              now - lastRehelloAt >= Self.rehelloGapMs else {
            return nil
        }
        lastRehelloAt = now
        // The old session keeps sending until the new one is answered
        return startHandshake(now)
    }

    private func setStatus(_ new: Status) -> Status? {
        guard new != status else { return nil }
        status = new
        return new
    }

    private func report(_ change: Status?) {
        if let change {
            onStatus?(change)
        }
    }

    // MARK: - Audio

    /// The VBAN packet sealed for the current session, or nil when it's dropped: before the
    /// first HELLO_ACK, or when the counter has run out (a new HELLO follows on the next poll).
    public func seal(vban: [UInt8]) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        guard var current = session else {
            dropped += 1
            return nil
        }
        if current.next > SwmcCodec.maxCounter {
            // Never wrap on the same key: a new session first
            session = nil
            needNewSession = true
            dropped += 1
            return nil
        }
        guard let packet = try? SwmcCodec.audio(key: current.key, deviceId: deviceId, sessionId: current.id,
                                                counter: current.next, vban: vban) else {
            dropped += 1
            return nil
        }
        current.next += 1
        session = current
        sent += 1
        return packet
    }
}
