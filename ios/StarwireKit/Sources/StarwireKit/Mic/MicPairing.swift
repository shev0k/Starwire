import Crypto
import Foundation

// Ported from Starwire for Android's MicPairing.java and MicPairingClient.java (GPL-3.0), without
// the socket and the clock (docs/dev/mic-protocol.md, "Pairing").

/// Starwire paired with one PC's microphone receiver: the device id it uses with that PC, the
/// 32-byte pairing key they agreed, and who the PC is. The app keeps it in the Keychain; it is
/// never exported with the settings.
public struct MicPairing: Codable, Equatable, Sendable {
    /// Starwire's id for the PC (its uuid from serverinfo).
    public var computerUUID: String
    /// Starwire's name for the PC when it was paired.
    public var computerName: String
    public var deviceId: [UInt8]
    public var key: [UInt8]
    public var receiverId: [UInt8]
    /// What the receiver called itself, cleaned for showing.
    public var receiverName: String
    /// Seconds since 1970, from the app's clock.
    public var pairedAt: TimeInterval

    public init(computerUUID: String, computerName: String, deviceId: [UInt8], key: [UInt8], receiverId: [UInt8],
                receiverName: String, pairedAt: TimeInterval) {
        self.computerUUID = computerUUID
        self.computerName = computerName
        self.deviceId = deviceId
        self.key = key
        self.receiverId = receiverId
        self.receiverName = receiverName
        self.pairedAt = pairedAt
    }

    /// True if the ids and key have the protocol's sizes (a damaged saved pairing doesn't).
    public var isValid: Bool {
        deviceId.count == SwmcCodec.idLength && key.count == SwmcCodec.keyLength
            && receiverId.count == SwmcCodec.idLength && !computerUUID.isEmpty
    }

    /// The PC's name to show: Starwire's name for it, else the receiver's.
    public var displayName: String {
        computerName.isEmpty ? receiverName : computerName
    }
}

/// Starwire's side of pairing with the PC's microphone receiver: a PAIR_REQUEST made with the
/// typed code goes to each of the PC's addresses every 500 ms for 6 s, and the first PAIR_ACCEPT
/// that checks out wins. Anyone can send a PAIR_REJECT, so one is only believed if no real
/// PAIR_ACCEPT follows within 500 ms.
///
/// The app sends what `poll` returns to every address, passes each datagram to `receive`, and
/// stops at the first outcome.
public final class MicPairingClient {
    public enum Outcome: Equatable, Sendable {
        case paired(MicPairing)
        case wrongCode
        /// The receiver isn't waiting to pair.
        case notPairing
        /// The code expired, was used up by wrong codes, or was used twice.
        case expired
        case noAnswer
        /// The receiver answered with the right code but a different key: try again.
        case failed
    }

    public enum StartError: Error, Equatable {
        /// The code isn't 16 letters and numbers.
        case badCode
    }

    static let resendMs: Int64 = 500
    static let giveUpMs: Int64 = 6000
    static let rejectWaitMs: Int64 = 500

    private let codeKey: [UInt8]
    private let deviceId: [UInt8]
    private let nonce: [UInt8]
    private let mine: P256.KeyAgreement.PrivateKey
    private let phonePoint: [UInt8]
    private let computerUUID: String
    private let computerName: String
    private let pairedAt: TimeInterval
    /// The same bytes every time, so the receiver knows it's the same request
    public let request: [UInt8]

    private var start: Int64?
    private var nextSend: Int64 = 0
    private var rejectReason: UInt8?
    private var rejectDecideAt: Int64 = 0

    /// `knownDeviceId` is the id Starwire already uses with this PC, or nil for a new one.
    /// `oneTimeKey` is a new P-256 key, from the tests or `P256.KeyAgreement.PrivateKey()`.
    public init(typedCode: String, deviceName: String, knownDeviceId: [UInt8]?, computerUUID: String,
                computerName: String, pairedAt: TimeInterval, random: RandomBytes = SystemRandomBytes(),
                oneTimeKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey()) throws {
        guard let code = PairingCode.decode(typedCode) else {
            throw StartError.badCode
        }
        if let knownDeviceId, knownDeviceId.count == SwmcCodec.idLength {
            deviceId = knownDeviceId
        } else {
            deviceId = random.bytes(SwmcCodec.idLength)
        }
        nonce = random.bytes(SwmcCodec.idLength)
        mine = oneTimeKey
        phonePoint = SwmcCodec.encodePoint(oneTimeKey.publicKey)
        codeKey = SwmcCodec.codeKey(code)
        self.computerUUID = computerUUID
        self.computerName = computerName
        self.pairedAt = pairedAt
        request = SwmcCodec.pairRequest(codeKey: codeKey, deviceId: deviceId, pairNonce: nonce, phonePoint: phonePoint,
                                        name: deviceName)
    }

    private func milliseconds(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1000).rounded())
    }

    /// Whether to send the request now, how long until the next poll, or the outcome.
    public func poll(now: TimeInterval) -> (send: Bool, wait: TimeInterval, outcome: Outcome?) {
        let now = milliseconds(now)
        let start = self.start ?? now
        if self.start == nil {
            self.start = now
            nextSend = now
        }
        if let rejectReason, now >= rejectDecideAt {
            return (false, 0, Self.outcome(rejectReason))
        }
        if rejectReason == nil && now - start >= Self.giveUpMs {
            return (false, 0, .noAnswer)
        }
        var send = false
        if now >= nextSend && now - start < Self.giveUpMs {
            send = true
            while nextSend <= now {
                nextSend += Self.resendMs
            }
        }
        var wake = min(start + Self.giveUpMs, nextSend)
        if rejectReason != nil {
            wake = now - start >= Self.giveUpMs ? rejectDecideAt : min(wake, rejectDecideAt)
        }
        return (send, TimeInterval(max(1, wake - now)) / 1000, nil)
    }

    /// Takes one datagram. Returns an outcome when it decides the pairing.
    public func receive(_ p: [UInt8], now: TimeInterval) -> Outcome? {
        switch SwmcCodec.typeOf(p) {
        case SwmcCodec.typePairAccept:
            return accept(p)
        case SwmcCodec.typePairReject:
            if rejectReason == nil, SwmcCodec.isFor(p, deviceId: deviceId), SwmcCodec.contextIs(p, nonce),
               let reason = SwmcCodec.pairRejectReason(p) {
                rejectReason = reason
                rejectDecideAt = milliseconds(now) + Self.rejectWaitMs
            }
            return nil
        default:
            return nil
        }
    }

    // The pairing a PAIR_ACCEPT makes, or nil if it isn't for this request or doesn't check out
    private func accept(_ p: [UInt8]) -> Outcome? {
        guard let nameLength = SwmcCodec.pairAcceptNameLength(p), SwmcCodec.isFor(p, deviceId: deviceId),
              SwmcCodec.contextIs(p, nonce), SwmcCodec.macOK(key: codeKey, p) else {
            return nil
        }
        // From here the receiver knew the code
        guard let receiverKey = SwmcCodec.decodePoint(p, at: SwmcCodec.acceptPointAt),
              let z = try? SwmcCodec.ecdhHash(mine: mine, theirs: receiverKey) else {
            return .failed
        }
        let receiverPoint = Array(p[SwmcCodec.acceptPointAt..<(SwmcCodec.acceptPointAt + SwmcCodec.pointLength)])
        let pairKey = SwmcCodec.pairKey(codeKey: codeKey, zHash: z, deviceId: deviceId, pairNonce: nonce,
                                        phonePoint: phonePoint, receiverPoint: receiverPoint)
        let confirmAt = SwmcCodec.acceptNameAt + nameLength
        guard SwmcCodec.constantTimeEquals(SwmcCodec.confirm(pairKey: pairKey), 0, p, confirmAt, SwmcCodec.macLength) else {
            return .failed
        }
        let receiverId = Array(p[SwmcCodec.acceptReceiverIdAt..<(SwmcCodec.acceptReceiverIdAt + SwmcCodec.idLength)])
        let rawName = String(decoding: p[SwmcCodec.acceptNameAt..<confirmAt], as: UTF8.self)
        return .paired(MicPairing(computerUUID: computerUUID, computerName: computerName, deviceId: deviceId,
                                  key: pairKey, receiverId: receiverId,
                                  receiverName: SwmcCodec.cleanName(rawName, fallback: ""), pairedAt: pairedAt))
    }

    private static func outcome(_ reason: UInt8) -> Outcome {
        switch reason {
        case SwmcCodec.rejectNotPairing: return .notPairing
        case SwmcCodec.rejectWrongCode: return .wrongCode
        case SwmcCodec.rejectExpired: return .expired
        default: return .failed
        }
    }
}
