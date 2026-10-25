import XCTest
@testable import StarwireKit

/// The VBAN packetizer: the packet checks of Android's VbanSenderTest, and the packet in the SWMC
/// test vectors file, byte for byte. (Sockets, the home-network filter and closing mid-write are
/// the sender's, not the packetizer's, and stay in the Android test.)
final class VbanPacketizerTests: XCTestCase {
    private func ramp(_ samples: Int) -> [Int16] {
        (0..<samples).map { Int16(truncatingIfNeeded: $0 * 37 - 16000) }
    }

    private func frameNumber(_ packet: [UInt8]) -> UInt32 {
        UInt32(packet[24]) | UInt32(packet[25]) << 8 | UInt32(packet[26]) << 16 | UInt32(packet[27]) << 24
    }

    private func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// The checks a VBAN receiver makes before playing a packet (quiniouben/vban packet_check).
    private func assertValidVbanAudio(_ packet: [UInt8], streamName: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(packet.count, VbanPacketizer.headerSize, "packet too small", file: file, line: line)
        XCTAssertEqual(ascii(packet[0..<4]), "VBAN", file: file, line: line)
        XCTAssertEqual(Array(packet[8..<24]), VbanPacketizer.streamNameBytes(streamName), "stream name", file: file, line: line)
        XCTAssertEqual(packet[7] & 0x08, 0, "reserved bit", file: file, line: line)
        XCTAssertEqual(packet[4] & 0xE0, 0, "audio protocol", file: file, line: line)
        XCTAssertEqual(packet[7] & 0xF0, 0, "PCM codec", file: file, line: line)
        XCTAssertEqual(packet[4] & 0x1F, 3, "48000 Hz", file: file, line: line)
        XCTAssertEqual(packet[7] & 0x07, 1, "16-bit samples", file: file, line: line)
        let samples = Int(packet[5]) + 1
        let channels = Int(packet[6]) + 1
        XCTAssertEqual(channels, 1, "mono", file: file, line: line)
        XCTAssertEqual(samples * channels * 2, packet.count - VbanPacketizer.headerSize, "payload size", file: file, line: line)
    }

    private func header(frame: UInt32, name: String, samples: Int = 256) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: VbanPacketizer.headerSize)
        VbanPacketizer.writeHeader(&buffer, samples: samples, frameNumber: frame,
                                   streamName: VbanPacketizer.streamNameBytes(name))
        return buffer
    }

    func testPacketSizeIs540() {
        XCTAssertEqual(VbanPacketizer.packetSize, 540)
        XCTAssertEqual(VbanPacketizer.headerSize, 4 + 4 + 16 + 4)
    }

    func testHeaderIsWhatReceiversExpect() {
        var packet = [UInt8](repeating: 0, count: VbanPacketizer.packetSize)
        VbanPacketizer.writeHeader(&packet, samples: 256, frameNumber: 0x0102_0304,
                                   streamName: VbanPacketizer.streamNameBytes("Stream1"))
        assertValidVbanAudio(packet, streamName: "Stream1")
        XCTAssertEqual(packet[5], 255)
        XCTAssertEqual(frameNumber(packet), 0x0102_0304)
    }

    func testHeaderBytesMatchTheVbanSpec() {
        let buf = header(frame: 0x0102_0304, name: "Mic")
        XCTAssertEqual(ascii(buf[0..<4]), "VBAN")
        XCTAssertEqual(buf[4], 3)       // 48 kHz index, audio protocol
        XCTAssertEqual(buf[5], 255)     // samples - 1
        XCTAssertEqual(buf[6], 0)       // mono
        XCTAssertEqual(buf[7], 1)       // INT16 PCM
        XCTAssertEqual(buf[8], UInt8(ascii: "M"))
        XCTAssertEqual(buf[11], 0)
        XCTAssertEqual(Array(buf[24...27]), [4, 3, 2, 1])
    }

    func testFrameCounterIsLittleEndianAcrossItsWholeRange() {
        XCTAssertEqual(Array(header(frame: 0xFFFF_FFFF, name: "Mic")[24...27]), [255, 255, 255, 255])
        XCTAssertEqual(Array(header(frame: 0x8000_0000, name: "Mic")[24...27]), [0, 0, 0, 0x80])
        let one = header(frame: 0, name: "Mic", samples: 1)
        XCTAssertEqual(frameNumber(one), 0)
        XCTAssertEqual(one[5], 0)
    }

    // After 2^32 packets (about 266 days of audio) the counter wraps to 0, as receivers expect
    func testFrameCounterWrapsAfter0xFFFFFFFF() {
        var packetizer = VbanPacketizer(streamName: "Mic")
        packetizer.frameNumber = 0xFFFF_FFFF
        let packets = packetizer.write(ramp(512))
        XCTAssertEqual(packets.map(frameNumber), [0xFFFF_FFFF, 0])
        for packet in packets {
            assertValidVbanAudio(packet, streamName: "Mic")
        }
    }

    func testStreamNamesArePaddedOrCutToSixteenBytes() {
        let padded = VbanPacketizer.streamNameBytes("Stream1")
        XCTAssertEqual(padded.count, 16)
        XCTAssertEqual(ascii(padded[0..<7]), "Stream1")
        XCTAssertEqual(Array(padded[7...]), [UInt8](repeating: 0, count: 9))
        XCTAssertEqual(ascii(VbanPacketizer.streamNameBytes("ABCDEFGHIJKLMNOPQRST")[...]), "ABCDEFGHIJKLMNOP")
        // Empty falls back to VBAN-Receptor's default, and spaces around a name are dropped
        XCTAssertEqual(VbanPacketizer.streamNameBytes(""), padded)
        XCTAssertEqual(VbanPacketizer.streamNameBytes("   "), padded)
        XCTAssertEqual(VbanPacketizer.streamNameBytes(nil), padded)
        XCTAssertEqual(VbanPacketizer.streamNameBytes("  Stream1 "), padded)
        // Letters outside ASCII become '?', one byte each, and the name is still 16 bytes
        let accented = VbanPacketizer.streamNameBytes("\u{DC}n\u{EF}c\u{F8}d\u{E9}-\u{DC}n\u{EF}c\u{F8}d\u{E9}-\u{DC}n\u{EF}c")
        XCTAssertEqual(accented.count, 16)
        XCTAssertEqual(ascii(accented[...]), "?n?c?d?-?n?c?d?-")
    }

    func testAudioArrivesInOrderedPacketsOf256Samples() {
        var packetizer = VbanPacketizer(streamName: "Mic")
        // A ramp in uneven chunks, as the microphone delivers it: 1000 samples make 3 full packets
        let ramp = self.ramp(1000)
        var packets: [[UInt8]] = []
        var done = 0
        while done < ramp.count {
            let n = min(300, ramp.count - done)
            packets += packetizer.write(Array(ramp[done..<done + n]))
            done += n
        }
        XCTAssertEqual(packets.count, 3)
        for (p, packet) in packets.enumerated() {
            assertValidVbanAudio(packet, streamName: "Mic")
            XCTAssertEqual(packet.count, 540)
            XCTAssertEqual(frameNumber(packet), UInt32(p))
            for s in 0..<256 {
                let at = VbanPacketizer.headerSize + s * 2
                let sample = Int16(bitPattern: UInt16(packet[at]) | UInt16(packet[at + 1]) << 8)
                XCTAssertEqual(sample, ramp[p * 256 + s], "sample \(p * 256 + s)")
            }
        }
        // The last 232 samples wait for the next packet; 24 more complete it
        XCTAssertEqual(packetizer.write(self.ramp(23)).count, 0)
        let fourth = packetizer.write(self.ramp(1))
        XCTAssertEqual(fourth.count, 1)
        XCTAssertEqual(frameNumber(fourth[0]), 3)
    }

    func testTheCallbackFormGivesTheSamePacketsWithoutCopying() {
        var a = VbanPacketizer(streamName: "Mic")
        var b = VbanPacketizer(streamName: "Mic")
        let samples = ramp(800)
        var viaCallback: [[UInt8]] = []
        samples.withUnsafeBufferPointer { pointer in
            a.write(pointer) { viaCallback.append(Array($0)) }
        }
        XCTAssertEqual(viaCallback, b.write(samples))
        XCTAssertEqual(viaCallback.count, 3)
    }

    // Opening again after a close (the next stream) starts a fresh count
    func testResetStartsAgainFromFrameZero() {
        var packetizer = VbanPacketizer(streamName: "Mic")
        XCTAssertEqual(packetizer.write(ramp(300)).map(frameNumber), [0])
        packetizer.reset()
        // The 44 samples that were waiting are dropped too
        XCTAssertEqual(packetizer.write(ramp(300)).map(frameNumber), [0])
        XCTAssertEqual(packetizer.write(ramp(212)).map(frameNumber), [1])
        packetizer.reset()
        XCTAssertEqual(packetizer.write(ramp(256)).map(frameNumber), [0])
    }

    func testFloatSamplesBecomeSixteenBitTheSameWayAtBothEnds() {
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: 0), 0)
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: 1), 32767)
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: -1), -32767)
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: 0.5), 16384)
        // Louder than full scale is cut, not wrapped
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: 3), 32767)
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: -3), -32767)
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: .nan), 0)
        XCTAssertEqual(VbanPacketizer.int16(fromFloat: .infinity), 32767)
    }

    // MARK: The test vectors file

    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func vector(_ name: String) throws -> [UInt8] {
        let url = Self.repo.appendingPathComponent("app/src/test/resources/swmc-v1-vectors.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let line = try XCTUnwrap(text.split(whereSeparator: \.isNewline).first { $0.hasPrefix(name + "=") }, name)
        let hex = Array(line.dropFirst(name.count + 1).utf8)
        XCTAssertEqual(hex.count % 2, 0)
        func nibble(_ c: UInt8) -> UInt8 { c <= 57 ? c - 48 : c - 87 }
        return stride(from: 0, to: hex.count, by: 2).map { nibble(hex[$0]) << 4 | nibble(hex[$0 + 1]) }
    }

    func testThePacketInTheVectorsFileComesOutByteForByte() throws {
        let expected = try vector("vban.frame7")
        XCTAssertEqual(expected.count, 540)

        // Frame 7, stream Stream1, 256 samples of (i * 37 - 16000)
        var packetizer = VbanPacketizer(streamName: "Stream1")
        packetizer.frameNumber = 7
        let packets = packetizer.write(ramp(256))
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets.first, expected)
        XCTAssertEqual(packetizer.frameNumber, 8)
    }
}
