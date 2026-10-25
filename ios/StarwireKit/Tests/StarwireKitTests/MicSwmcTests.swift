import Crypto
import XCTest
@testable import StarwireKit

// Ported from Starwire for Android's SwmcCodecTest, MicPairingClientTest and SecureVbanSenderTest
// (GPL-3.0). The vectors file is the shared one: Android and the Windows receiver test the same bytes.

/// app/src/test/resources/swmc-v1-vectors.txt and the fixed inputs it was made from
/// (docs/dev/mic-protocol.md, "Test vectors").
enum SwmcVectors {
    static let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("app/src/test/resources/swmc-v1-vectors.txt")
    static let sha256 = "bc79b6d1e099e89bbfc93125a987afb96a02bd5bfe8f4480ced36b369bfd810a"

    static let pairKey = hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    static let deviceId = hex("a0a1a2a3a4a5a6a7")
    static let clientRandom = hex("c0c1c2c3c4c5c6c7")
    static let serverRandom = hex("5051525354555657")
    static let code = hex("11121314151617181920")
    static let pairNonce = hex("7071727374757677")
    static let receiverId = hex("b0b1b2b3b4b5b6b7")
    static let phoneName = "Test phone"
    static let pcName = "TEST-PC"
    // RFC 5903 section 8.1 (256-bit random ECP group): i is the phone, r the receiver
    static let ecdhI = hex("C88F01F510D9AC3F70A292DAA2316DE544E9AAB8AFE84049C62A9C57862D1433")
    static let ecdhGIX = hex("DAD0B65394221CF9B051E1FECA5787D098DFE637FC90B9EF945D0C3772581180")
    static let ecdhGIY = hex("5271A0461CDB8252D61F1C456FA3E59AB1F45B33ACCF5F58389E0577B8990BB3")
    static let ecdhR = hex("C6EF9C5D78AE012A011164ACB397CE2088685D8F06BF9BE0B283AB46476BEE53")
    static let ecdhGRX = hex("D12DFB5289C8D4F81208B70270398C342296970A0BCCB74C736FC7554494BF63")
    static let ecdhGRY = hex("56FBF3CA366CC23E8157854C13C58D6AAC23F046ADA30F8353E74F33039872AB")
    static let ecdhGIRX = hex("D6840F6B42F6EDAFD13116E0E12565202FEF8E9ECE7DCE03812464D04B9442DE")

    static var phonePoint: [UInt8] { [4] + ecdhGIX + ecdhGIY }
    static var receiverPoint: [UInt8] { [4] + ecdhGRX + ecdhGRY }

    static func read() throws -> [String: String] {
        var lines: [String: String] = [:]
        for line in try String(contentsOf: file, encoding: .ascii).split(separator: "\n") {
            if let eq = line.firstIndex(of: "="), eq != line.startIndex {
                lines[String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        return lines
    }

    static func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            out.append(UInt8(s[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// The same bytes over and over, for keys and nonces the test can predict.
final class FixedRandomBytes: RandomBytes {
    private var queue: [[UInt8]]
    private var counter: UInt8 = 0

    init(_ queue: [[UInt8]] = []) {
        self.queue = queue
    }

    func bytes(_ count: Int) -> [UInt8] {
        if !queue.isEmpty {
            let next = queue.removeFirst()
            precondition(next.count == count)
            return next
        }
        counter &+= 1
        return [UInt8](repeating: counter, count: count)
    }
}

final class SwmcCodecTests: XCTestCase {
    typealias V = SwmcVectors

    func testTheVectorsFileIsTheSharedOneByteForByte() throws {
        let ours = try Data(contentsOf: V.file)
        XCTAssertEqual(V.hex(Array(SHA256.hash(data: ours))), V.sha256)
        let receivers = try Data(contentsOf: V.file.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("windows/tests/vectors/swmc-v1-vectors.txt"))
        XCTAssertEqual(receivers, ours, "the app's and the receiver's vectors differ")
        XCTAssertEqual(try V.read().count, 16)
    }

    func testStandardsKnownAnswers() throws {
        // GCM spec test case 16 (AES-256, 60 bytes, 20 bytes of additional data)
        let box = try AES.GCM.seal(
            V.hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"),
            using: SymmetricKey(data: V.hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308")),
            nonce: try AES.GCM.Nonce(data: V.hex("cafebabefacedbaddecaf888")),
            authenticating: V.hex("feedfacedeadbeeffeedfacedeadbeefabaddad2"))
        XCTAssertEqual(V.hex(Array(box.ciphertext) + Array(box.tag)), try V.read()["kat.gcm_tc16"])

        // HKDF, RFC 5869 test case 1
        XCTAssertEqual(V.hex(SwmcCodec.hkdf(salt: V.hex("000102030405060708090a0b0c"),
                                            ikm: V.hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
                                            info: V.hex("f0f1f2f3f4f5f6f7f8f9"), length: 42)),
                       "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")

        // ECDH P-256, RFC 5903 section 8.1, both directions, through the point checks
        let gi = try XCTUnwrap(SwmcCodec.decodePoint(V.phonePoint))
        let gr = try XCTUnwrap(SwmcCodec.decodePoint(V.receiverPoint))
        let want = Array(SHA256.hash(data: V.ecdhGIRX))
        XCTAssertEqual(try SwmcCodec.ecdhHash(mine: P256.KeyAgreement.PrivateKey(rawRepresentation: V.ecdhI), theirs: gr), want)
        XCTAssertEqual(try SwmcCodec.ecdhHash(mine: P256.KeyAgreement.PrivateKey(rawRepresentation: V.ecdhR), theirs: gi), want)
        XCTAssertEqual(SwmcCodec.encodePoint(gi), V.phonePoint)
    }

    // Each line made here from the fixed inputs, compared with the file; and no line goes unchecked
    // (vban.frame7 is also made by VbanPacketizerTests)
    func testEveryVectorLineIsReproduced() throws {
        let want = try V.read()
        var checked = Set<String>()
        func same(_ name: String, _ got: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(got, want[name], name, file: file, line: line)
            checked.insert(name)
        }

        let box = try AES.GCM.seal(
            V.hex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"),
            using: SymmetricKey(data: V.hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308")),
            nonce: try AES.GCM.Nonce(data: V.hex("cafebabefacedbaddecaf888")),
            authenticating: V.hex("feedfacedeadbeeffeedfacedeadbeefabaddad2"))
        same("kat.gcm_tc16", V.hex(Array(box.ciphertext) + Array(box.tag)))
        same("kat.hkdf_rfc5869_1", V.hex(SwmcCodec.hkdf(salt: V.hex("000102030405060708090a0b0c"),
                                                        ikm: V.hex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
                                                        info: V.hex("f0f1f2f3f4f5f6f7f8f9"), length: 42)))
        let z = try SwmcCodec.ecdhHash(mine: P256.KeyAgreement.PrivateKey(rawRepresentation: V.ecdhI),
                                       theirs: XCTUnwrap(SwmcCodec.decodePoint(V.receiverPoint)))
        same("kat.ecdh_rfc5903_sha256", V.hex(z))

        let kAuth = SwmcCodec.authKey(pairKey: V.pairKey, deviceId: V.deviceId)
        let kAudio = SwmcCodec.audioKey(pairKey: V.pairKey, deviceId: V.deviceId, clientRandom: V.clientRandom,
                                        serverRandom: V.serverRandom)
        same("key.auth", V.hex(kAuth))
        same("key.audio", V.hex(kAudio))
        same("pkt.hello", V.hex(SwmcCodec.hello(authKey: kAuth, deviceId: V.deviceId, clientRandom: V.clientRandom)))
        same("pkt.hello_ack", V.hex(SwmcCodec.helloAck(authKey: kAuth, deviceId: V.deviceId, clientRandom: V.clientRandom,
                                                       serverRandom: V.serverRandom, status: SwmcCodec.statusReady)))
        same("pkt.rehello", V.hex(SwmcCodec.rehello(authKey: kAuth, deviceId: V.deviceId, sessionId: V.serverRandom)))
        let vban = V.hex(try XCTUnwrap(want["vban.frame7"]))
        checked.insert("vban.frame7")
        XCTAssertEqual(vban.count, 540)
        let audio7 = try SwmcCodec.audio(key: SymmetricKey(data: kAudio), deviceId: V.deviceId, sessionId: V.serverRandom,
                                         counter: 7, vban: vban)
        XCTAssertEqual(audio7.count, 584)
        same("pkt.audio7", V.hex(audio7))
        same("pkt.audio_last", V.hex(try SwmcCodec.audio(key: SymmetricKey(data: kAudio), deviceId: V.deviceId,
                                                         sessionId: V.serverRandom, counter: SwmcCodec.maxCounter, vban: vban)))

        same("pair.code", PairingCode.encode(V.code))
        let kCode = SwmcCodec.codeKey(V.code)
        same("pair.code_key", V.hex(kCode))
        same("pkt.pair_request", V.hex(SwmcCodec.pairRequest(codeKey: kCode, deviceId: V.deviceId, pairNonce: V.pairNonce,
                                                             phonePoint: V.phonePoint, name: V.phoneName)))
        let kPair = SwmcCodec.pairKey(codeKey: kCode, zHash: z, deviceId: V.deviceId, pairNonce: V.pairNonce,
                                      phonePoint: V.phonePoint, receiverPoint: V.receiverPoint)
        same("pair.key", V.hex(kPair))
        same("pkt.pair_accept", V.hex(SwmcCodec.pairAccept(codeKey: kCode, pairKey: kPair, deviceId: V.deviceId,
                                                           pairNonce: V.pairNonce, receiverPoint: V.receiverPoint,
                                                           receiverId: V.receiverId, name: V.pcName)))

        XCTAssertEqual(Set(want.keys), checked, "vector lines nobody checked")
    }

    func testTheVectorsPacketsParse() throws {
        let v = try V.read()
        let kAuth = SwmcCodec.authKey(pairKey: V.pairKey, deviceId: V.deviceId)
        let ack = V.hex(v["pkt.hello_ack"]!)
        XCTAssertEqual(SwmcCodec.typeOf(ack), SwmcCodec.typeHelloAck)
        XCTAssertEqual(ack.count, SwmcCodec.ackLength)
        XCTAssertTrue(SwmcCodec.macOK(key: kAuth, ack))
        XCTAssertTrue(SwmcCodec.isFor(ack, deviceId: V.deviceId))
        XCTAssertTrue(SwmcCodec.contextIs(ack, V.clientRandom))
        XCTAssertEqual(Array(ack[24..<32]), V.serverRandom)

        let kAudio = SwmcCodec.audioKey(pairKey: V.pairKey, deviceId: V.deviceId, clientRandom: V.clientRandom,
                                        serverRandom: V.serverRandom)
        let opened = SwmcCodec.openAudio(key: SymmetricKey(data: kAudio), V.hex(v["pkt.audio7"]!))
        XCTAssertEqual(opened, V.hex(v["vban.frame7"]!))
        XCTAssertEqual(SwmcCodec.getU32(V.hex(v["pkt.audio_last"]!), at: SwmcCodec.counterAt), SwmcCodec.maxCounter)

        let accept = V.hex(v["pkt.pair_accept"]!)
        XCTAssertEqual(SwmcCodec.pairAcceptNameLength(accept), V.pcName.utf8.count)
        XCTAssertTrue(SwmcCodec.macOK(key: V.hex(v["pair.code_key"]!), accept))
    }

    func testEveryFlippedBitAndEveryTruncationIsRefused() throws {
        let v = try V.read()
        let kAuth = SwmcCodec.authKey(pairKey: V.pairKey, deviceId: V.deviceId)
        let kAudio = SymmetricKey(data: SwmcCodec.audioKey(pairKey: V.pairKey, deviceId: V.deviceId,
                                                           clientRandom: V.clientRandom, serverRandom: V.serverRandom))
        let ack = V.hex(v["pkt.hello_ack"]!)
        let audio = V.hex(v["pkt.audio7"]!)
        for bit in 0..<(ack.count * 8) {
            var bad = ack
            bad[bit / 8] ^= 1 << (bit % 8)
            XCTAssertFalse(SwmcCodec.typeOf(bad) == SwmcCodec.typeHelloAck && SwmcCodec.macOK(key: kAuth, bad)
                           && SwmcCodec.isFor(bad, deviceId: V.deviceId), "ACK bit \(bit)")
        }
        for bit in stride(from: 0, to: audio.count * 8, by: 7) {
            var bad = audio
            bad[bit / 8] ^= 1 << (bit % 8)
            XCTAssertNil(SwmcCodec.openAudio(key: kAudio, bad), "AUDIO bit \(bit)")
        }
        for length in 0..<audio.count {
            XCTAssertNil(SwmcCodec.openAudio(key: kAudio, Array(audio.prefix(length))), "AUDIO cut to \(length)")
        }
        for length in 0..<ack.count {
            let cut = Array(ack.prefix(length))
            XCTAssertFalse(cut.count == SwmcCodec.ackLength && SwmcCodec.macOK(key: kAuth, cut))
        }
    }

    func testTypesVersionsAndPlainVbanAreTold() throws {
        let hello = SwmcCodec.hello(authKey: [UInt8](repeating: 1, count: 32), deviceId: V.deviceId,
                                    clientRandom: V.clientRandom)
        XCTAssertEqual(SwmcCodec.typeOf(hello), SwmcCodec.typeHello)
        var badVersion = hello
        badVersion[4] = 2
        XCTAssertNil(SwmcCodec.typeOf(badVersion))
        var reserved = hello
        reserved[7] = 1
        XCTAssertNil(SwmcCodec.typeOf(reserved))
        XCTAssertNil(SwmcCodec.typeOf(Array("VBAN".utf8) + [UInt8](repeating: 0, count: 40)))
        XCTAssertNil(SwmcCodec.typeOf(Array(hello.prefix(23))))
    }

    func testTheCounterStopsAt0xFFFFFFFF() {
        let key = SymmetricKey(data: [UInt8](repeating: 2, count: 32))
        XCTAssertThrowsError(try SwmcCodec.audio(key: key, deviceId: V.deviceId, sessionId: V.serverRandom,
                                                 counter: SwmcCodec.maxCounter + 1, vban: [1, 2, 3]))
        XCTAssertThrowsError(try SwmcCodec.audio(key: key, deviceId: V.deviceId, sessionId: V.serverRandom,
                                                 counter: 0, vban: []))
        XCTAssertThrowsError(try SwmcCodec.audio(key: key, deviceId: V.deviceId, sessionId: V.serverRandom,
                                                 counter: 0, vban: [UInt8](repeating: 0, count: 1025)))
    }

    func testPairingCodesAreReadLikePeopleTypeThem() {
        XCTAssertEqual(PairingCode.decode("2491-650N-2RBH-G690"), V.code)
        XCTAssertEqual(PairingCode.decode("2491 650n 2rbh g690"), V.code)
        XCTAssertEqual(PairingCode.decode("2491650N2RBHG690"), V.code)
        XCTAssertEqual(PairingCode.decode("249I-65ON-2RBH-G69O"), PairingCode.decode("2491-650N-2RBH-G690"))
        XCTAssertEqual(PairingCode.decode("249L-650N-2RBH-G690"), V.code)
        XCTAssertNil(PairingCode.decode("2491-650N-2RBH-G69U"))
        XCTAssertNil(PairingCode.decode("2491-650N-2RBH-G69"))
        XCTAssertNil(PairingCode.decode("2491-650N-2RBH-G6900"))
        XCTAssertNil(PairingCode.decode(""))
        XCTAssertEqual(PairingCode.format("2491650n2rb"), "2491-650N-2RB")
        XCTAssertEqual(PairingCode.format("2491-650N 2RBH"), "2491-650N-2RBH")
        XCTAssertEqual(PairingCode.format("24U1"), "24U1")
    }

    func testOnlyPointsOnP256AreTaken() {
        XCTAssertNotNil(SwmcCodec.decodePoint(V.receiverPoint))
        var offCurve = V.receiverPoint
        offCurve[64] ^= 1
        XCTAssertNil(SwmcCodec.decodePoint(offCurve))
        var compressed = V.receiverPoint
        compressed[0] = 2
        XCTAssertNil(SwmcCodec.decodePoint(compressed))
        XCTAssertNil(SwmcCodec.decodePoint([4] + [UInt8](repeating: 0xFF, count: 64)))
        XCTAssertNil(SwmcCodec.decodePoint([4] + [UInt8](repeating: 0, count: 64)))
        XCTAssertNil(SwmcCodec.decodePoint(Array(V.receiverPoint.prefix(64))))
    }

    func testNamesAreCutAndCleaned() {
        XCTAssertEqual(SwmcCodec.nameBytes("Test phone"), Array("Test phone".utf8))
        let pads = String(repeating: "\u{1F3AE}", count: 40)   // a 4-byte character
        let cut = SwmcCodec.nameBytes(pads)
        XCTAssertEqual(cut.count, 64)
        XCTAssertEqual(String(decoding: cut, as: UTF8.self).unicodeScalars.count, 16)
        XCTAssertEqual(SwmcCodec.nameBytes("x" + pads).count, 61, "cut before a character, not inside it")

        XCTAssertEqual(SwmcCodec.cleanName("Desk\r\nPC", fallback: "?"), "Desk PC")
        XCTAssertEqual(SwmcCodec.cleanName("  Desk \u{202E}  PC\u{0007} ", fallback: "?"), "Desk PC")
        XCTAssertEqual(SwmcCodec.cleanName("\u{0000}\u{200B}\t", fallback: "fallback"), "fallback")
        XCTAssertEqual(SwmcCodec.cleanName("Caf\u{E9} \u{1F3AE}", fallback: "?"), "Caf\u{E9} \u{1F3AE}")
    }

    func testRandomJunkIsNeverTaken() {
        let kAuth = SwmcCodec.authKey(pairKey: V.pairKey, deviceId: V.deviceId)
        var generator = SplitMix64(seed: 42)
        for length in [0, 1, 23, 24, 40, 52, 584, 2000] {
            for _ in 0..<50 {
                var junk = (0..<length).map { _ in UInt8(truncatingIfNeeded: generator.next()) }
                if length >= 8 {
                    junk.replaceSubrange(0..<8, with: [0x53, 0x57, 0x4D, 0x43, 1, UInt8(generator.next() % 8), 0, 0])
                }
                XCTAssertFalse(SwmcCodec.macOK(key: kAuth, junk))
                XCTAssertNil(SwmcCodec.pairAcceptNameLength(junk).flatMap { _ in SwmcCodec.macOK(key: kAuth, junk) ? 1 : nil })
            }
        }
    }

    // The ranges are built from their parts, so no private address is written out in the repo
    // (check-publish.sh looks for them)
    func testHomeNetworkAddresses() {
        func v4(_ parts: Int...) -> String { parts.map(String.init).joined(separator: ".") }
        let inside = [v4(192, 168, 200, 7), v4(10, 0, 0, 1), v4(172, 16, 0, 1), v4(172, 31, 255, 255),
                      v4(169, 254, 1, 1), v4(127, 0, 0, 1), v4(100, 64, 0, 1), v4(100, 127, 255, 255),
                      "fe80::1", "fe80::1%en0", "fd12:3456::1", "::1", "fec0::1", "::ffff:" + v4(192, 168, 0, 1)]
        for address in inside {
            XCTAssertTrue(HomeNetwork.contains(address), address)
        }
        let outside = [v4(8, 8, 8, 8), v4(172, 32, 0, 1), v4(100, 128, 0, 1), v4(192, 169, 0, 1), "2001:db8::1",
                       "::ffff:" + v4(8, 8, 8, 8), "not an address", "1.2.3", "300.1.1.1"]
        for address in outside {
            XCTAssertFalse(HomeNetwork.contains(address), address)
        }
        XCTAssertTrue(HomeNetwork.contains([10, 1, 2, 3]))
        XCTAssertFalse(HomeNetwork.contains([1, 2, 3]))
    }
}

/// A tiny seeded generator for junk input.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class SwmcSenderTests: XCTestCase {
    typealias V = SwmcVectors

    private var statuses: [SwmcSender.Status] = []

    private func sender(randoms: [[UInt8]] = [V.clientRandom]) -> SwmcSender {
        let sender = SwmcSender(deviceId: V.deviceId, pairKey: V.pairKey, random: FixedRandomBytes(randoms))
        sender.onStatus = { [unowned self] in statuses.append($0) }
        return sender
    }

    private var authKey: [UInt8] { SwmcCodec.authKey(pairKey: V.pairKey, deviceId: V.deviceId) }

    private func ack(_ clientRandom: [UInt8] = V.clientRandom, server: [UInt8] = V.serverRandom,
                     status: UInt8 = SwmcCodec.statusReady) -> [UInt8] {
        SwmcCodec.helloAck(authKey: authKey, deviceId: V.deviceId, clientRandom: clientRandom, serverRandom: server,
                           status: status)
    }

    /// The times at which HELLOs went out between `from` and `to`, polling every 10 ms.
    private func helloTimes(_ s: SwmcSender, from: Int, to: Int) -> [Int] {
        var times: [Int] = []
        for ms in stride(from: from, through: to, by: 10) {
            let (packets, _) = s.poll(now: TimeInterval(ms) / 1000)
            for p in packets where SwmcCodec.typeOf(p) == SwmcCodec.typeHello {
                times.append(ms)
            }
        }
        return times
    }

    func testHellosGoOutEvery250MsFor2SThenEvery2S() {
        let s = sender()
        s.start(now: 0)
        XCTAssertEqual(helloTimes(s, from: 0, to: 6000), [0, 250, 500, 750, 1000, 1250, 1500, 1750, 2000, 4000, 6000])
        XCTAssertEqual(statuses, [.connecting, .noAnswer])
    }

    func testTheFirstHelloIsTheVectorsOne() throws {
        let s = sender()
        s.start(now: 0)
        let (packets, _) = s.poll(now: 0)
        XCTAssertEqual(packets.map(V.hex), [try V.read()["pkt.hello"]!])
    }

    func testAudioBeforeTheAckIsDroppedThenSealedFromCounter0() throws {
        let s = sender()
        s.start(now: 0)
        _ = s.poll(now: 0)
        let vban = V.hex(try V.read()["vban.frame7"]!)
        XCTAssertNil(s.seal(vban: vban))
        s.receive(ack(), now: 0.1)
        XCTAssertEqual(statuses, [.connecting, .sending])
        let key = SymmetricKey(data: SwmcCodec.audioKey(pairKey: V.pairKey, deviceId: V.deviceId,
                                                        clientRandom: V.clientRandom, serverRandom: V.serverRandom))
        for counter in 0..<3 {
            let packet = try XCTUnwrap(s.seal(vban: vban))
            XCTAssertEqual(SwmcCodec.getU32(packet, at: SwmcCodec.counterAt), UInt64(counter))
            XCTAssertEqual(SwmcCodec.openAudio(key: key, packet), vban)
        }
        XCTAssertEqual(s.dropped, 1)
        XCTAssertEqual(s.sent, 3)
        // Once answered, no more HELLOs
        XCTAssertEqual(helloTimes(s, from: 200, to: 5000), [])
    }

    func testAnswersThatDontCheckOutAreIgnored() {
        let s = sender()
        s.start(now: 0)
        _ = s.poll(now: 0)
        var forged = ack()
        forged[40] ^= 1
        s.receive(forged, now: 0.1)
        s.receive(ack(hex8(9)), now: 0.1)   // another HELLO's
        s.receive(SwmcCodec.helloAck(authKey: [UInt8](repeating: 7, count: 32), deviceId: V.deviceId,
                                     clientRandom: V.clientRandom, serverRandom: V.serverRandom, status: 0), now: 0.1)
        XCTAssertNil(s.seal(vban: [1]))
        XCTAssertEqual(statuses, [.connecting])
    }

    func testBusyAndNoOutputAskAgainEvery2SWithTheSameHello() {
        let s = sender()
        s.start(now: 0)
        let first = s.poll(now: 0).packets
        s.receive(ack(status: SwmcCodec.statusBusy), now: 0.1)
        XCTAssertEqual(statuses, [.connecting, .busy])
        var repeats: [[UInt8]] = []
        for ms in stride(from: 100, through: 4200, by: 10) {
            repeats += s.poll(now: TimeInterval(ms) / 1000).packets
        }
        XCTAssertEqual(repeats, [first[0], first[0]])
        // The session works meanwhile; audio is checked, not played, by the receiver
        XCTAssertNotNil(s.seal(vban: [1, 2]))
        s.receive(ack(status: SwmcCodec.statusReady), now: 4.3)
        XCTAssertEqual(statuses, [.connecting, .busy, .sending])
        s.receive(ack(status: SwmcCodec.statusNoOutput), now: 4.4)
        XCTAssertEqual(statuses.last, .noOutput)
    }

    func testAnotherSessionForTheSameHelloStartsANewHelloAndKeepsTheOldSession() throws {
        let second = hex8(0x22)
        let s = sender(randoms: [V.clientRandom, second])
        s.start(now: 0)
        _ = s.poll(now: 0)
        s.receive(ack(), now: 0.1)
        XCTAssertNotNil(s.seal(vban: [1]))
        // The receiver restarted and answers the old HELLO with a new session
        s.receive(ack(server: hex8(0x77)), now: 0.2)
        let next = s.poll(now: 0.2).packets
        XCTAssertEqual(next.count, 1)
        XCTAssertTrue(SwmcCodec.contextIs(next[0], second))
        // Audio goes on in the old session, counter 1
        let packet = try XCTUnwrap(s.seal(vban: [1]))
        XCTAssertTrue(SwmcCodec.contextIs(packet, V.serverRandom))
        XCTAssertEqual(SwmcCodec.getU32(packet, at: SwmcCodec.counterAt), 1)
        // The new HELLO's answer makes a new session from counter 0
        s.receive(ack(second, server: hex8(0x88)), now: 0.3)
        let fresh = try XCTUnwrap(s.seal(vban: [1]))
        XCTAssertTrue(SwmcCodec.contextIs(fresh, hex8(0x88)))
        XCTAssertEqual(SwmcCodec.getU32(fresh, at: SwmcCodec.counterAt), 0)
    }

    func testRehelloForTheCurrentSessionStartsANewHelloAtMostEvery2S() {
        let s = sender(randoms: [V.clientRandom, hex8(0x31), hex8(0x32)])
        s.start(now: 0)
        _ = s.poll(now: 0)
        s.receive(ack(), now: 0.1)
        let rehello = SwmcCodec.rehello(authKey: authKey, deviceId: V.deviceId, sessionId: V.serverRandom)
        // For another session: ignored
        s.receive(SwmcCodec.rehello(authKey: authKey, deviceId: V.deviceId, sessionId: hex8(1)), now: 1)
        XCTAssertEqual(s.poll(now: 1).packets, [])
        s.receive(rehello, now: 1)
        let hellos = s.poll(now: 1).packets
        XCTAssertEqual(hellos.count, 1)
        XCTAssertTrue(SwmcCodec.contextIs(hellos[0], hex8(0x31)))
        // While that HELLO waits, more REHELLOs are ignored
        s.receive(ack(hex8(0x31), server: hex8(0x41)), now: 1.1)
        s.receive(SwmcCodec.rehello(authKey: authKey, deviceId: V.deviceId, sessionId: hex8(0x41)), now: 2.0)
        XCTAssertEqual(s.poll(now: 2.0).packets, [], "within 2 s of the last REHELLO")
        s.receive(SwmcCodec.rehello(authKey: authKey, deviceId: V.deviceId, sessionId: hex8(0x41)), now: 3.1)
        XCTAssertEqual(s.poll(now: 3.1).packets.count, 1)
    }

    func testAUsedUpCounterStartsANewSessionInsteadOfWrapping() throws {
        let s = sender(randoms: [V.clientRandom, hex8(0x55)])
        s.firstCounter = SwmcCodec.maxCounter
        s.start(now: 0)
        _ = s.poll(now: 0)
        s.receive(ack(), now: 0.1)
        let last = try XCTUnwrap(s.seal(vban: [1]))
        XCTAssertEqual(SwmcCodec.getU32(last, at: SwmcCodec.counterAt), SwmcCodec.maxCounter)
        XCTAssertNil(s.seal(vban: [1]))
        let hello = s.poll(now: 0.2).packets
        XCTAssertEqual(hello.count, 1)
        XCTAssertTrue(SwmcCodec.contextIs(hello[0], hex8(0x55)))
    }

    private func hex8(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: 8)
    }
}

final class MicPairingClientTests: XCTestCase {
    typealias V = SwmcVectors

    private func client(code: String = "2491-650N-2RBH-G690") throws -> MicPairingClient {
        try MicPairingClient(typedCode: code, deviceName: V.phoneName, knownDeviceId: V.deviceId,
                             computerUUID: "PC-UUID", computerName: "Gaming PC", pairedAt: 1000,
                             random: FixedRandomBytes([V.pairNonce]),
                             oneTimeKey: P256.KeyAgreement.PrivateKey(rawRepresentation: V.ecdhI))
    }

    func testTheRequestIsTheVectorsOne() throws {
        XCTAssertEqual(V.hex(try client().request), try V.read()["pkt.pair_request"])
    }

    func testABadCodeDoesntStart() {
        XCTAssertThrowsError(try client(code: "2491-650N")) { error in
            XCTAssertEqual(error as? MicPairingClient.StartError, .badCode)
        }
    }

    func testTheVectorsAcceptPairs() throws {
        let c = try client()
        XCTAssertTrue(c.poll(now: 0).send)
        let accept = V.hex(try V.read()["pkt.pair_accept"]!)
        guard case .paired(let pairing)? = c.receive(accept, now: 0.2) else {
            return XCTFail("not paired")
        }
        XCTAssertEqual(V.hex(pairing.key), try V.read()["pair.key"])
        XCTAssertEqual(pairing.deviceId, V.deviceId)
        XCTAssertEqual(pairing.receiverId, V.receiverId)
        XCTAssertEqual(pairing.receiverName, V.pcName)
        XCTAssertEqual(pairing.computerUUID, "PC-UUID")
        XCTAssertEqual(pairing.displayName, "Gaming PC")
        XCTAssertTrue(pairing.isValid)
    }

    func testTheRequestGoesOutEvery500MsFor6SThenNoAnswer() throws {
        let c = try client()
        var sends: [Int] = []
        var outcome: MicPairingClient.Outcome?
        for ms in stride(from: 0, through: 7000, by: 10) where outcome == nil {
            let result = c.poll(now: TimeInterval(ms) / 1000)
            if result.send { sends.append(ms) }
            outcome = result.outcome
        }
        XCTAssertEqual(sends, Array(stride(from: 0, to: 6000, by: 500)))
        XCTAssertEqual(outcome, .noAnswer)
    }

    func testARejectIsBelievedOnlyAfter500MsWithoutAnAccept() throws {
        let c = try client()
        _ = c.poll(now: 0)
        let reject = SwmcCodec.pairReject(request: c.request, reason: SwmcCodec.rejectWrongCode)
        XCTAssertNil(c.receive(reject, now: 1.0))
        XCTAssertNil(c.poll(now: 1.4).outcome)
        XCTAssertEqual(c.poll(now: 1.5).outcome, .wrongCode)

        // A real accept within the 500 ms wins
        let d = try client()
        _ = d.poll(now: 0)
        XCTAssertNil(d.receive(reject, now: 1.0))
        let accept = V.hex(try V.read()["pkt.pair_accept"]!)
        guard case .paired? = d.receive(accept, now: 1.2) else { return XCTFail("the accept didn't win") }
    }

    func testRejectsForAnotherRequestAreIgnored() throws {
        let c = try client()
        _ = c.poll(now: 0)
        var other = SwmcCodec.pairReject(request: c.request, reason: SwmcCodec.rejectExpired)
        other[16] ^= 1
        XCTAssertNil(c.receive(other, now: 1))
        XCTAssertNil(c.poll(now: 2).outcome)
        let mapping: [(UInt8, MicPairingClient.Outcome)] = [(1, .notPairing), (2, .wrongCode), (3, .expired), (9, .failed)]
        for (reason, outcome) in mapping {
            let d = try client()
            _ = d.poll(now: 0)
            _ = d.receive(SwmcCodec.pairReject(request: d.request, reason: reason), now: 0)
            XCTAssertEqual(d.poll(now: 0.5).outcome, outcome)
        }
    }

    func testAnAcceptWithAWrongConfirmFails() throws {
        let c = try client()
        _ = c.poll(now: 0)
        let kCode = SwmcCodec.codeKey(V.code)
        let wrong = SwmcCodec.pairAccept(codeKey: kCode, pairKey: [UInt8](repeating: 9, count: 32), deviceId: V.deviceId,
                                         pairNonce: V.pairNonce, receiverPoint: V.receiverPoint, receiverId: V.receiverId,
                                         name: V.pcName)
        XCTAssertEqual(c.receive(wrong, now: 0.1), .failed)
        // Made with another code: not even looked at
        let d = try client()
        _ = d.poll(now: 0)
        let otherCode = SwmcCodec.pairAccept(codeKey: SwmcCodec.codeKey([UInt8](repeating: 1, count: 10)),
                                             pairKey: V.pairKey, deviceId: V.deviceId, pairNonce: V.pairNonce,
                                             receiverPoint: V.receiverPoint, receiverId: V.receiverId, name: V.pcName)
        XCTAssertNil(d.receive(otherCode, now: 0.1))
    }
}
