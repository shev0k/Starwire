import Foundation

// Packs microphone audio into VBAN packets: 48 kHz, 16-bit, mono, 256 samples a packet.
//
// Ported from Starwire for Android's VbanPacketizer.java and VbanSender.java (GPL-3.0). A packet is
// a 28-byte header ("VBAN", sample rate index, samples - 1, channels - 1, sample format, a
// 16-byte stream name, a little-endian frame counter) and 256 little-endian samples: 540 bytes.
// See docs/dev/mic-protocol.md and VB-Audio's VBAN protocol specification. Plain VBAN is not
// encrypted; Starwire's own receiver gets these same packets sealed inside its SWMC envelope.

public struct VbanPacketizer: Sendable {
    public static let headerSize = 28
    public static let samplesPerPacket = 256
    public static let streamNameSize = 16
    public static let packetSize = headerSize + samplesPerPacket * 2
    public static let defaultStreamName = "Stream1"

    // Index of 48000 Hz in VBAN's sample rate list; the protocol bits (audio = 0) are zero
    static let sampleRate48000: UInt8 = 3
    // 16-bit signed integer samples; the codec bits (PCM = 0) are zero
    static let formatInt16: UInt8 = 1

    private let streamName: [UInt8]
    private var buffer: [UInt8]
    private var samplesInPacket = 0
    /// The frame number the next packet gets. It wraps to 0 after 0xFFFFFFFF, as receivers expect.
    public var frameNumber: UInt32 = 0

    public init(streamName: String?) {
        self.streamName = Self.streamNameBytes(streamName)
        buffer = [UInt8](repeating: 0, count: Self.packetSize)
    }

    /// Starts again from frame 0 with nothing waiting (a new stream).
    public mutating func reset() {
        samplesInPacket = 0
        frameNumber = 0
    }

    /// Adds samples; each packet that fills goes to `onPacket` with the next frame number. The
    /// bytes are only valid during the call: the buffer is reused for the next packet. Does not
    /// allocate.
    public mutating func write(_ samples: UnsafeBufferPointer<Int16>, onPacket: (UnsafeBufferPointer<UInt8>) -> Void) {
        for sample in samples {
            let at = Self.headerSize + samplesInPacket * 2
            let bits = UInt16(bitPattern: sample)
            buffer[at] = UInt8(truncatingIfNeeded: bits)
            buffer[at + 1] = UInt8(truncatingIfNeeded: bits >> 8)
            samplesInPacket += 1
            if samplesInPacket == Self.samplesPerPacket {
                Self.writeHeader(&buffer, samples: Self.samplesPerPacket, frameNumber: frameNumber, streamName: streamName)
                frameNumber &+= 1
                samplesInPacket = 0
                buffer.withUnsafeBufferPointer { onPacket($0) }
            }
        }
    }

    /// Adds samples and returns the packets that filled (copies; for tests and for callers that
    /// don't mind an allocation per packet).
    public mutating func write(_ samples: [Int16]) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        samples.withUnsafeBufferPointer { pointer in
            write(pointer) { packets.append(Array($0)) }
        }
        return packets
    }

    /// Writes a VBAN audio header for 48 kHz mono 16-bit PCM into the start of `buffer`.
    static func writeHeader(_ buffer: inout [UInt8], samples: Int, frameNumber: UInt32, streamName: [UInt8]) {
        buffer[0] = 0x56 // V
        buffer[1] = 0x42 // B
        buffer[2] = 0x41 // A
        buffer[3] = 0x4E // N
        buffer[4] = sampleRate48000
        buffer[5] = UInt8(truncatingIfNeeded: samples - 1)
        buffer[6] = 0 // channels - 1
        buffer[7] = formatInt16
        for i in 0..<streamNameSize {
            buffer[8 + i] = streamName[i]
        }
        buffer[24] = UInt8(truncatingIfNeeded: frameNumber)
        buffer[25] = UInt8(truncatingIfNeeded: frameNumber >> 8)
        buffer[26] = UInt8(truncatingIfNeeded: frameNumber >> 16)
        buffer[27] = UInt8(truncatingIfNeeded: frameNumber >> 24)
    }

    /// The stream name as VBAN sends it: ASCII, cut or padded with zeros to 16 bytes. Empty or
    /// blank falls back to "Stream1", spaces around a name are dropped, and any letter outside
    /// ASCII becomes '?'.
    public static func streamNameBytes(_ name: String?) -> [UInt8] {
        var scalars = Array((name ?? "").unicodeScalars)
        // Java's trim(): drops everything up to and including the space
        while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
        while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
        if scalars.isEmpty {
            scalars = Array(defaultStreamName.unicodeScalars)
        }
        var out = [UInt8](repeating: 0, count: streamNameSize)
        for (i, scalar) in scalars.prefix(streamNameSize).enumerated() {
            out[i] = scalar.value < 0x80 ? UInt8(scalar.value) : 0x3F
        }
        return out
    }

    /// Float samples (-1...1, as iOS audio gives them) to 16-bit: scaled by 32767, rounded and
    /// kept inside the 16-bit range. Android's microphone already delivers 16-bit, so this has no
    /// Android counterpart.
    public static func int16(fromFloat sample: Float) -> Int16 {
        guard !sample.isNaN else { return 0 }
        let scaled = (min(1, max(-1, sample)) * 32767).rounded(.toNearestOrAwayFromZero)
        return Int16(scaled)
    }
}
