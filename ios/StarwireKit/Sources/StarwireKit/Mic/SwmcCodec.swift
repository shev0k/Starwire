import Crypto
import Foundation

// Ported from Starwire for Android's SwmcCodec.java (GPL-3.0). The format is the contract in
// docs/dev/mic-protocol.md, and app/src/test/resources/swmc-v1-vectors.txt is its test: Android, the
// Windows receiver and this file all reproduce it byte for byte.

/// Starwire's encrypted microphone format, "SWMC" version 1: the bytes of every message and the
/// keys. swift-crypto has CryptoKit's API (HMAC-SHA256, HKDF, AES-GCM, ECDH on P-256) on every
/// platform, so the same code runs in the app and in the Windows tests.
///
/// Parsing never throws on what arrives from the network: it returns nil, false or -1 instead.
public enum SwmcCodec {
    public static let version: UInt8 = 1
    public static let typeHello: UInt8 = 1
    public static let typeHelloAck: UInt8 = 2
    public static let typeAudio: UInt8 = 3
    public static let typeRehello: UInt8 = 4
    public static let typePairRequest: UInt8 = 5
    public static let typePairAccept: UInt8 = 6
    public static let typePairReject: UInt8 = 7

    // Magic 4, version 1, type 1, reserved 2, deviceId 8, context 8
    public static let header = 24
    public static let idLength = 8
    public static let macLength = 16
    public static let tagLength = 16
    public static let keyLength = 32
    public static let pointLength = 65
    public static let maxNameBytes = 64
    /// HELLO and REHELLO
    public static let helloLength = header + macLength
    public static let ackLength = header + 8 + 1 + 3 + macLength
    public static let ackStatusAt = header + 8
    public static let rejectLength = header + 1
    /// Plus the name
    public static let pairRequestLength = header + pointLength + 1 + macLength
    /// Plus the name
    public static let pairAcceptLength = header + pointLength + 8 + 1 + macLength + macLength
    public static let acceptPointAt = header
    public static let acceptReceiverIdAt = header + pointLength
    public static let acceptNameLengthAt = acceptReceiverIdAt + idLength
    public static let acceptNameAt = acceptNameLengthAt + 1
    /// AUDIO: the u32 counter after the header; the header and counter are authenticated in the clear
    public static let counterAt = header
    public static let audioAAD = header + 4
    public static let nonceAt = 16
    /// The VBAN packet inside (Starwire sends 540)
    public static let maxAudioPlaintext = 1024
    public static let maxAudioLength = audioAAD + maxAudioPlaintext + tagLength
    public static let maxCounter: UInt64 = 0xFFFF_FFFF

    public static let statusReady: UInt8 = 0
    public static let statusNoOutput: UInt8 = 1
    public static let statusBusy: UInt8 = 2
    public static let rejectNotPairing: UInt8 = 1
    public static let rejectWrongCode: UInt8 = 2
    public static let rejectExpired: UInt8 = 3

    static let labelAuth = Array("starwire-mic/1 auth".utf8)
    static let labelAudio = Array("starwire-mic/1 audio".utf8)
    static let labelPairingSalt = Array("starwire-mic/1 pairing".utf8)
    static let labelCode = Array("code".utf8)
    static let labelPair = Array("starwire-mic/1 pair".utf8)
    static let labelConfirm = Array("starwire-mic/1 confirm".utf8)

    // MARK: - Bytes

    public static func putU32(_ bytes: inout [UInt8], at: Int, _ value: UInt64) {
        bytes[at] = UInt8(truncatingIfNeeded: value)
        bytes[at + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[at + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[at + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    public static func getU32(_ bytes: [UInt8], at: Int) -> UInt64 {
        UInt64(bytes[at]) | UInt64(bytes[at + 1]) << 8 | UInt64(bytes[at + 2]) << 16 | UInt64(bytes[at + 3]) << 24
    }

    /// Compares without stopping at the first difference, so the time taken says nothing.
    public static func constantTimeEquals(_ a: [UInt8], _ aAt: Int, _ b: [UInt8], _ bAt: Int, _ length: Int) -> Bool {
        guard aAt >= 0, bAt >= 0, a.count - aAt >= length, b.count - bAt >= length else { return false }
        var diff: UInt8 = 0
        for i in 0..<length {
            diff |= a[aAt + i] ^ b[bAt + i]
        }
        return diff == 0
    }

    // MARK: - HMAC and HKDF (RFC 5869)

    static func hmac<D: DataProtocol>(_ key: [UInt8], _ data: D) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    /// The first 16 bytes of HMAC-SHA256.
    public static func mac16(_ key: [UInt8], _ data: [UInt8], _ at: Int = 0, _ length: Int? = nil) -> [UInt8] {
        let end = at + (length ?? data.count - at)
        return Array(hmac(key, data[at..<end]).prefix(macLength))
    }

    /// HKDF-SHA256. No salt (nil or empty) means 32 zero bytes, as RFC 5869 says. Written out
    /// rather than through swift-crypto's HKDF so the empty-salt rule is visible here.
    public static func hkdf(salt: [UInt8]?, ikm: [UInt8], info: [UInt8], length: Int = 32) -> [UInt8] {
        let prk = hmac(salt.flatMap { $0.isEmpty ? nil : $0 } ?? [UInt8](repeating: 0, count: 32), ikm)
        var okm: [UInt8] = []
        var t: [UInt8] = []
        var i: UInt8 = 1
        while okm.count < length {
            t = hmac(prk, t + info + [i])
            okm += t.prefix(length - okm.count)
            i += 1
        }
        return okm
    }

    // MARK: - Keys

    public static func authKey(pairKey: [UInt8], deviceId: [UInt8]) -> [UInt8] {
        hkdf(salt: nil, ikm: pairKey, info: labelAuth + deviceId)
    }

    public static func audioKey(pairKey: [UInt8], deviceId: [UInt8], clientRandom: [UInt8], serverRandom: [UInt8]) -> [UInt8] {
        hkdf(salt: clientRandom + serverRandom, ikm: pairKey, info: labelAudio + deviceId)
    }

    public static func codeKey(_ code: [UInt8]) -> [UInt8] {
        hkdf(salt: labelPairingSalt, ikm: code, info: labelCode)
    }

    public static func pairKey(codeKey: [UInt8], zHash: [UInt8], deviceId: [UInt8], pairNonce: [UInt8],
                               phonePoint: [UInt8], receiverPoint: [UInt8]) -> [UInt8] {
        hkdf(salt: codeKey, ikm: zHash, info: labelPair + deviceId + pairNonce + phonePoint + receiverPoint)
    }

    public static func confirm(pairKey: [UInt8]) -> [UInt8] {
        mac16(pairKey, labelConfirm)
    }

    // MARK: - The header

    static func header(type: UInt8, deviceId: [UInt8], context: [UInt8], length: Int) -> [UInt8] {
        precondition(deviceId.count == idLength && context.count == idLength)
        var p = [UInt8](repeating: 0, count: length)
        p[0] = 0x53; p[1] = 0x57; p[2] = 0x4D; p[3] = 0x43   // "SWMC"
        p[4] = version
        p[5] = type
        p.replaceSubrange(8..<16, with: deviceId)
        p.replaceSubrange(16..<24, with: context)
        return p
    }

    /// The packet's type if it has SWMC v1's header (magic, version, zero reserved bytes), else nil.
    /// Everything else is up to the MAC or the tag.
    public static func typeOf(_ p: [UInt8]) -> UInt8? {
        guard p.count >= header, p[0] == 0x53, p[1] == 0x57, p[2] == 0x4D, p[3] == 0x43,
              p[4] == version, p[6] == 0, p[7] == 0 else {
            return nil
        }
        return p[5]
    }

    /// Whether the packet's device id is this one.
    public static func isFor(_ p: [UInt8], deviceId: [UInt8]) -> Bool {
        constantTimeEquals(p, 8, deviceId, 0, idLength)
    }

    /// Whether the packet's context is these 8 bytes.
    public static func contextIs(_ p: [UInt8], _ context: [UInt8]) -> Bool {
        constantTimeEquals(p, 16, context, 0, idLength)
    }

    /// The last 16 bytes are the MAC of everything before them.
    public static func macOK(key: [UInt8], _ p: [UInt8]) -> Bool {
        guard p.count >= header + macLength else { return false }
        let expected = mac16(key, p, 0, p.count - macLength)
        return constantTimeEquals(expected, 0, p, p.count - macLength, macLength)
    }

    private static func signed(_ p: [UInt8], key: [UInt8]) -> [UInt8] {
        var p = p
        p.replaceSubrange((p.count - macLength)..., with: mac16(key, p, 0, p.count - macLength))
        return p
    }

    // MARK: - Sessions

    /// HELLO: asks for a session; the context is Starwire's random number.
    public static func hello(authKey: [UInt8], deviceId: [UInt8], clientRandom: [UInt8]) -> [UInt8] {
        signed(header(type: typeHello, deviceId: deviceId, context: clientRandom, length: helloLength), key: authKey)
    }

    /// HELLO_ACK: echoes the client random, then the receiver's (the session id) and a status.
    public static func helloAck(authKey: [UInt8], deviceId: [UInt8], clientRandom: [UInt8], serverRandom: [UInt8],
                                status: UInt8) -> [UInt8] {
        var p = header(type: typeHelloAck, deviceId: deviceId, context: clientRandom, length: ackLength)
        p.replaceSubrange(header..<(header + idLength), with: serverRandom)
        p[ackStatusAt] = status
        return signed(p, key: authKey)
    }

    /// REHELLO: the receiver doesn't know the session named in the context.
    public static func rehello(authKey: [UInt8], deviceId: [UInt8], sessionId: [UInt8]) -> [UInt8] {
        signed(header(type: typeRehello, deviceId: deviceId, context: sessionId, length: helloLength), key: authKey)
    }

    /// AUDIO: the header (context: the session id), the counter, then the VBAN packet encrypted and
    /// its tag. The nonce is bytes 16..<28 and bytes 0..<28 are authenticated.
    public static func audio(key: SymmetricKey, deviceId: [UInt8], sessionId: [UInt8], counter: UInt64,
                             vban: [UInt8]) throws -> [UInt8] {
        guard (1...maxAudioPlaintext).contains(vban.count), counter <= maxCounter else {
            throw SwmcError.cantSeal
        }
        var p = header(type: typeAudio, deviceId: deviceId, context: sessionId, length: audioAAD)
        putU32(&p, at: counterAt, counter)
        let nonce = try AES.GCM.Nonce(data: p[nonceAt..<audioAAD])
        let box = try AES.GCM.seal(vban, using: key, nonce: nonce, authenticating: p)
        return p + Array(box.ciphertext) + Array(box.tag)
    }

    /// The VBAN packet inside an AUDIO packet, or nil if it's malformed or not authentic.
    public static func openAudio(key: SymmetricKey, _ p: [UInt8]) -> [UInt8]? {
        guard typeOf(p) == typeAudio, p.count >= audioAAD + 1 + tagLength, p.count <= maxAudioLength,
              let nonce = try? AES.GCM.Nonce(data: p[nonceAt..<audioAAD]),
              let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: p[audioAAD..<(p.count - tagLength)],
                                               tag: p[(p.count - tagLength)...]),
              let plain = try? AES.GCM.open(box, using: key, authenticating: p[0..<audioAAD]) else {
            return nil
        }
        return Array(plain)
    }

    // MARK: - Pairing

    /// PAIR_REQUEST: the header (context: the pairing nonce), Starwire's one-time public key, its
    /// name, and a MAC with the code's key.
    public static func pairRequest(codeKey: [UInt8], deviceId: [UInt8], pairNonce: [UInt8], phonePoint: [UInt8],
                                   name: String) -> [UInt8] {
        let n = nameBytes(name)
        var p = header(type: typePairRequest, deviceId: deviceId, context: pairNonce, length: pairRequestLength + n.count)
        p.replaceSubrange(header..<(header + pointLength), with: phonePoint)
        p[header + pointLength] = UInt8(n.count)
        p.replaceSubrange((header + pointLength + 1)..<(header + pointLength + 1 + n.count), with: n)
        return signed(p, key: codeKey)
    }

    /// PAIR_ACCEPT: the header (the request's device id and nonce), the receiver's one-time public
    /// key, its id, its name, the confirmation made with the new pairing key, and a MAC with the
    /// code's key. Starwire only reads these; the tests make them, as the receiver does.
    public static func pairAccept(codeKey: [UInt8], pairKey: [UInt8], deviceId: [UInt8], pairNonce: [UInt8],
                                  receiverPoint: [UInt8], receiverId: [UInt8], name: String) -> [UInt8] {
        let n = nameBytes(name)
        let body = receiverPoint + receiverId + [UInt8(n.count)] + n + confirm(pairKey: pairKey)
        var p = header(type: typePairAccept, deviceId: deviceId, context: pairNonce, length: pairAcceptLength + n.count)
        p.replaceSubrange(header..<(header + body.count), with: body)
        return signed(p, key: codeKey)
    }

    /// A PAIR_ACCEPT's name length if it's shaped like one, else nil.
    public static func pairAcceptNameLength(_ p: [UInt8]) -> Int? {
        guard typeOf(p) == typePairAccept, p.count >= pairAcceptLength, p[header] == 4 else { return nil }
        let nameLength = Int(p[acceptNameLengthAt])
        return nameLength <= maxNameBytes && p.count == pairAcceptLength + nameLength ? nameLength : nil
    }

    /// PAIR_REJECT: the request's header with type 7, then why. Not authenticated.
    public static func pairReject(request: [UInt8], reason: UInt8) -> [UInt8] {
        var p = Array(request.prefix(header)) + [reason]
        p[5] = typePairReject
        return p
    }

    /// The reason in a PAIR_REJECT, or nil if it isn't one.
    public static func pairRejectReason(_ p: [UInt8]) -> UInt8? {
        typeOf(p) == typePairReject && p.count == rejectLength ? p[header] : nil
    }

    /// A name as UTF-8, cut to 64 bytes without splitting a character.
    public static func nameBytes(_ name: String) -> [UInt8] {
        var scalars = Array(name.unicodeScalars)
        var bytes = Array(name.utf8)
        while bytes.count > maxNameBytes {
            scalars.removeLast()
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            bytes = Array(String(view).utf8)
        }
        return bytes
    }

    /// A name that came over the network, made safe to show and store: no control or formatting
    /// characters (which could break a line or reverse the text), runs of spaces made one.
    public static func cleanName(_ raw: String, fallback: String) -> String {
        var out = String.UnicodeScalarView()
        var space = false
        for scalar in raw.unicodeScalars {
            let category = scalar.properties.generalCategory
            switch category {
            case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator, .surrogate,
                 .unassigned, .privateUse:
                space = !out.isEmpty
                continue
            default:
                break
            }
            if scalar.properties.isWhitespace {
                space = !out.isEmpty
                continue
            }
            if space {
                out.append(" ")
                space = false
            }
            out.append(scalar)
        }
        return out.isEmpty ? fallback : String(out)
    }

    // MARK: - ECDH on P-256

    // P-256's field prime, big-endian
    private static let prime: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    ]

    private static func belowPrime(_ coordinate: ArraySlice<UInt8>) -> Bool {
        for (a, b) in zip(coordinate, prime) where a != b {
            return a < b
        }
        return false
    }

    /// 0x04, X, Y.
    public static func encodePoint(_ key: P256.KeyAgreement.PublicKey) -> [UInt8] {
        Array(key.x963Representation)
    }

    /// The public key in p[at..<at+65], or nil unless it's an uncompressed point on P-256 with
    /// both coordinates below the field prime. The coordinates are checked here, and the curve
    /// equation by swift-crypto (BoringSSL or CryptoKit), which refuses points not on the curve.
    public static func decodePoint(_ p: [UInt8], at: Int = 0) -> P256.KeyAgreement.PublicKey? {
        guard at >= 0, p.count - at >= pointLength, p[at] == 4,
              belowPrime(p[(at + 1)..<(at + 33)]), belowPrime(p[(at + 33)..<(at + 65)]) else {
            return nil
        }
        return try? P256.KeyAgreement.PublicKey(x963Representation: p[at..<(at + pointLength)])
    }

    /// SHA-256 of the shared X coordinate: what Windows' ECDiffieHellmanCng gives with its Hash KDF.
    public static func ecdhHash(mine: P256.KeyAgreement.PrivateKey, theirs: P256.KeyAgreement.PublicKey) throws -> [UInt8] {
        let shared = try mine.sharedSecretFromKeyAgreement(with: theirs)
        let x = shared.withUnsafeBytes { Array($0) }
        guard x.count == 32 else { throw SwmcError.badSharedSecret }
        return Array(SHA256.hash(data: x))
    }
}

public enum SwmcError: Error, Equatable {
    case cantSeal
    case badSharedSecret
}
