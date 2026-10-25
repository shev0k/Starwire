import XCTest
@testable import StarwireKit

final class InputHapticsTests: XCTestCase {
    /// `frames` stereo frames with a sine on each side (0 amplitude for silence).
    private func sine(frames: Int, leftHz: Double, leftAmplitude: Double, rightHz: Double = 0, rightAmplitude: Double = 0,
                      startFrame: Int = 0) -> [Int16] {
        var out: [Int16] = []
        for n in startFrame..<startFrame + frames {
            let t = Double(n) / 48_000
            out.append(Int16(leftAmplitude * 32767 * sin(2 * .pi * leftHz * t)))
            out.append(Int16(rightAmplitude * 32767 * sin(2 * .pi * rightHz * t)))
        }
        return out
    }

    func testSilenceMakesSilentFrames() {
        let converter = DualSenseHapticsConverter()
        let result = converter.process(sequence: 1, samples: [Int16](repeating: 0, count: 480 * 2))
        XCTAssertFalse(result.discontinuity)
        XCTAssertEqual(result.frames.count, 1)
        XCTAssertTrue(result.frames[0].isSilent)
    }

    func testHalfWindowPacketsMakeOneFramePerTwoPackets() {
        let converter = DualSenseHapticsConverter()
        let first = converter.process(sequence: 7, samples: sine(frames: 240, leftHz: 80, leftAmplitude: 0.5))
        XCTAssertEqual(first.frames.count, 0)
        let second = converter.process(sequence: 8, samples: sine(frames: 240, leftHz: 80, leftAmplitude: 0.5, startFrame: 240))
        XCTAssertEqual(second.frames.count, 1)
        // The window began 5 ms before this packet's first sample
        XCTAssertEqual(second.frames[0].offset, -0.005, accuracy: 1e-9)
        XCTAssertGreaterThan(second.frames[0].left.intensity, 0.5)
        XCTAssertEqual(second.frames[0].right, .silent)
    }

    func testLowFrequencyIsDullAndHighFrequencyIsSharp() {
        let low = DualSenseHapticsConverter().process(sequence: 0, samples: sine(frames: 960, leftHz: 50, leftAmplitude: 0.6))
        let high = DualSenseHapticsConverter().process(sequence: 0, samples: sine(frames: 960, leftHz: 320, leftAmplitude: 0.6))
        let lowSharpness = low.frames[1].left.sharpness
        let highSharpness = high.frames[1].left.sharpness
        XCTAssertLessThan(lowSharpness, 0.3)
        XCTAssertGreaterThan(highSharpness, 0.6)
    }

    func testIntensityFollowsTheSquareRootOfRMS() {
        let frames = DualSenseHapticsConverter().process(sequence: 0, samples: sine(frames: 480, leftHz: 100, leftAmplitude: 0.5)).frames
        // A sine's RMS is amplitude / sqrt(2)
        let expected = min(Float((0.5 / 2.0.squareRoot()).squareRoot()) * 1.15, 1)
        XCTAssertEqual(frames[0].left.intensity, expected, accuracy: 0.01)
    }

    func testGainScalesIntensity() {
        let samples = sine(frames: 480, leftHz: 100, leftAmplitude: 0.2)
        let full = DualSenseHapticsConverter(gain: 1).process(sequence: 0, samples: samples).frames[0].left.intensity
        let half = DualSenseHapticsConverter(gain: 0.5).process(sequence: 0, samples: samples).frames[0].left.intensity
        XCTAssertEqual(half, full / 2, accuracy: 0.001)
    }

    func testAnOnsetIsATransient() {
        let converter = DualSenseHapticsConverter()
        let quiet = converter.process(sequence: 0, samples: [Int16](repeating: 0, count: 960)).frames
        XCTAssertEqual(quiet[0].left.transient, 0)
        let hit = converter.process(sequence: 1, samples: sine(frames: 480, leftHz: 150, leftAmplitude: 0.8)).frames
        XCTAssertGreaterThan(hit[0].left.transient, 0.9)
        let held = converter.process(sequence: 2, samples: sine(frames: 480, leftHz: 150, leftAmplitude: 0.8, startFrame: 480)).frames
        XCTAssertEqual(held[0].left.transient, 0, "a steady buzz is not a new transient")
    }

    func testIntensityFadesAfterTheSoundStops() {
        let converter = DualSenseHapticsConverter()
        let loud = converter.process(sequence: 0, samples: sine(frames: 480, leftHz: 100, leftAmplitude: 0.8)).frames[0].left.intensity
        var level = loud
        var sequence: UInt32 = 1
        var windows = 0
        while level > 0 {
            let next = converter.process(sequence: sequence, samples: [Int16](repeating: 0, count: 960)).frames[0].left.intensity
            XCTAssertEqual(next, level * DualSenseHapticsConverter.releasePerWindow < 0.02 ? 0 : level * DualSenseHapticsConverter.releasePerWindow,
                           accuracy: 1e-6)
            level = next
            sequence += 1
            windows += 1
        }
        XCTAssertEqual(windows, 12, "about 120 ms from full to nothing")
    }

    func testAMissedPacketStartsFresh() {
        let converter = DualSenseHapticsConverter()
        _ = converter.process(sequence: 10, samples: sine(frames: 240, leftHz: 100, leftAmplitude: 0.5))
        let skipped = converter.process(sequence: 12, samples: sine(frames: 240, leftHz: 100, leftAmplitude: 0.5))
        XCTAssertTrue(skipped.discontinuity)
        XCTAssertEqual(skipped.frames.count, 0, "the half window before the gap is dropped")
        let wrapped = DualSenseHapticsConverter()
        _ = wrapped.process(sequence: UInt32.max, samples: [])
        XCTAssertFalse(wrapped.process(sequence: 0, samples: []).discontinuity)
    }

    func testLittleEndianSamples() {
        XCTAssertEqual(DualSenseHapticsConverter.samples(fromLittleEndian: [0x01, 0x00, 0xFF, 0xFF, 0x00, 0x80]), [1, -1, -32768])
    }
}
