import XCTest
@testable import StarwireKit

/// Audio haptics: the same maths as Android's AudioHaptics.java (its AudioHapticsLevelTest cases
/// come first), then the filter, the 30 ms ticks and the strength setting on generated audio.
final class AudioHapticsTests: XCTestCase {
    private let rate = 48_000

    /// `frames` interleaved frames of a sine, the same on every channel.
    private func sine(hz: Double, amplitude: Double, frames: Int, channels: Int = 2, startFrame: Int = 0) -> [Int16] {
        var out: [Int16] = []
        out.reserveCapacity(frames * channels)
        for n in startFrame..<startFrame + frames {
            let value = Int16((amplitude * 32767 * sin(2 * .pi * hz * Double(n) / Double(rate))).rounded())
            for _ in 0..<channels {
                out.append(value)
            }
        }
        return out
    }

    private func outputs(_ haptics: inout AudioHaptics, _ pcm: [Int16]) -> [AudioHapticsOutput] {
        var result: [AudioHapticsOutput] = []
        haptics.process(pcm) { result.append($0) }
        return result
    }

    /// The level after `seconds` of a sine, the last tick.
    private func settledLevel(hz: Double, amplitude: Double, percent: Int = 100, seconds: Double = 1.0) -> Float {
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2, strengthPercent: percent)
        let result = outputs(&haptics, sine(hz: hz, amplitude: amplitude, frames: Int(Double(rate) * seconds)))
        return result.last?.level ?? -1
    }

    // MARK: Ported from AudioHapticsLevelTest

    func testLevelIsZeroBelowTheNoiseGateAndCappedAtOne() {
        XCTAssertEqual(AudioHaptics.level(forEnvelope: 0, intensity: 1), 0)
        XCTAssertEqual(AudioHaptics.level(forEnvelope: 0.004, intensity: 1), 0)
        XCTAssertEqual(AudioHaptics.level(forEnvelope: 0.9, intensity: 1), 1)
        XCTAssertEqual(AudioHaptics.level(forEnvelope: 1, intensity: 1), 1)
        XCTAssertGreaterThan(AudioHaptics.level(forEnvelope: 0.1, intensity: 2), AudioHaptics.level(forEnvelope: 0.1, intensity: 1))
    }

    func testLevelRisesWithTheBassAndTheIntensity() {
        var previous: Float = 0
        for i in 1...100 {
            let level = AudioHaptics.level(forEnvelope: Float(i) / 100, intensity: 1)
            XCTAssertGreaterThanOrEqual(level, previous, "at \(i)")
            previous = level
        }
        XCTAssertEqual(AudioHaptics.level(forEnvelope: 0.1, intensity: 0), 0)
    }

    // MARK: The audio path

    func testSilenceGivesZero() {
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2)
        let result = outputs(&haptics, [Int16](repeating: 0, count: rate * 2))
        XCTAssertEqual(result.count, 33)
        XCTAssertTrue(result.allSatisfy { $0 == .silent })
        XCTAssertEqual(haptics.latest, .silent)
    }

    func testA60HzSineGivesMotorOutput() {
        let level = settledLevel(hz: 60, amplitude: 0.1)
        // About 0.1 of full scale, less the filter's loss at 60 Hz, times 4, minus the gate
        XCTAssertEqual(level, 0.345, accuracy: 0.03)
        let output = AudioHapticsOutput(level: level)
        XCTAssertEqual(output.lowFrequencyMotor, UInt16((level * 65535).rounded()))
        XCTAssertEqual(output.highFrequencyMotor, 0)
        XCTAssertEqual(output.deviceAmplitude, UInt8((level * 255).rounded()))
    }

    func testA1kHzSineGivesNone() {
        // At the same quiet volume the 60 Hz sine is felt and the 1 kHz one is not
        XCTAssertGreaterThan(settledLevel(hz: 60, amplitude: 0.02), 0.03)
        XCTAssertEqual(settledLevel(hz: 1000, amplitude: 0.02), 0)
        // Android's filter is a gentle one-pole, so a very loud high tone does leak a little
        // through; it stays well under what a bass of that volume gives (which is full strength)
        XCTAssertEqual(settledLevel(hz: 60, amplitude: 0.5), 1)
        XCTAssertLessThan(settledLevel(hz: 1000, amplitude: 0.5), 0.3)
    }

    func testStrengthScalesTheLevel() {
        let at100 = settledLevel(hz: 60, amplitude: 0.1, percent: 100)
        let at50 = settledLevel(hz: 60, amplitude: 0.1, percent: 50)
        let at25 = settledLevel(hz: 60, amplitude: 0.1, percent: 25)
        let at200 = settledLevel(hz: 60, amplitude: 0.1, percent: 200)
        XCTAssertEqual(at50, at100 * 0.5, accuracy: 0.002)
        XCTAssertEqual(at25, at100 * 0.25, accuracy: 0.002)
        XCTAssertEqual(at200, at100 * 2, accuracy: 0.004)
    }

    func testStrengthIsClampedTo25To200Percent() {
        XCTAssertEqual(AudioHaptics(sampleRate: rate, channelCount: 2, strengthPercent: 25).intensity, 0.25)
        XCTAssertEqual(AudioHaptics(sampleRate: rate, channelCount: 2, strengthPercent: 200).intensity, 2)
        XCTAssertEqual(AudioHaptics(sampleRate: rate, channelCount: 2, strengthPercent: 0).intensity, 0.25)
        XCTAssertEqual(AudioHaptics(sampleRate: rate, channelCount: 2, strengthPercent: -50).intensity, 0.25)
        XCTAssertEqual(AudioHaptics(sampleRate: rate, channelCount: 2, strengthPercent: 1000).intensity, 2)
        XCTAssertEqual(settledLevel(hz: 60, amplitude: 0.1, percent: 5), settledLevel(hz: 60, amplitude: 0.1, percent: 25))
        // At 200 percent a moderate bass reaches full strength, and no setting goes past 1
        XCTAssertEqual(settledLevel(hz: 60, amplitude: 0.2, percent: 200), 1)
        XCTAssertEqual(settledLevel(hz: 60, amplitude: 0.2, percent: 1000), 1)
        XCTAssertEqual(AudioHaptics.strengthRange, 25...200)
    }

    func testOneTickForEvery30MillisecondsOfAudio() {
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2)
        XCTAssertEqual(haptics.framesPerTick, 1440)
        XCTAssertEqual(outputs(&haptics, sine(hz: 60, amplitude: 0.3, frames: 1439)).count, 0)
        XCTAssertEqual(outputs(&haptics, sine(hz: 60, amplitude: 0.3, frames: 1, startFrame: 1439)).count, 1)
        // Two seconds in total make 66 ticks, however the audio is cut into blocks
        let rest = outputs(&haptics, sine(hz: 60, amplitude: 0.3, frames: rate * 2 - 1440, startFrame: 1440)).count
        XCTAssertEqual(1 + rest, 66)

        var all = 0
        var chopped = AudioHaptics(sampleRate: rate, channelCount: 2)
        let audio = sine(hz: 60, amplitude: 0.3, frames: rate * 2)
        var offset = 0
        while offset < audio.count {
            let size = min([480, 7, 960, 1, 1234][(offset / 2) % 5] * 2, audio.count - offset)
            all += outputs(&chopped, Array(audio[offset..<offset + size])).count
            offset += size
        }
        XCTAssertEqual(all, 66)
    }

    func testTheOutputDoesNotDependOnHowTheAudioIsCutIntoBlocks() {
        let audio = sine(hz: 70, amplitude: 0.15, frames: rate)
        var whole = AudioHaptics(sampleRate: rate, channelCount: 2)
        let expected = outputs(&whole, audio)

        var pieces = AudioHaptics(sampleRate: rate, channelCount: 2)
        var got: [AudioHapticsOutput] = []
        var offset = 0
        var size = 2
        while offset < audio.count {
            let end = min(audio.count, offset + size)
            got += outputs(&pieces, Array(audio[offset..<end]))
            offset = end
            size = (size * 3 + 4) % 2000 + 2
            size -= size % 2
        }
        XCTAssertEqual(got, expected)
    }

    func testFloatAudioGivesTheSameLevelsAsSixteenBit() {
        let int16 = sine(hz: 60, amplitude: 0.1, frames: rate)
        let floats = int16.map { Float($0) / 32768 }
        var a = AudioHaptics(sampleRate: rate, channelCount: 2)
        var b = AudioHaptics(sampleRate: rate, channelCount: 2)
        let fromInt = outputs(&a, int16)
        var fromFloat: [AudioHapticsOutput] = []
        b.process(floats) { fromFloat.append($0) }
        XCTAssertEqual(fromInt.count, fromFloat.count)
        for (x, y) in zip(fromInt, fromFloat) {
            XCTAssertEqual(x.level, y.level, accuracy: 0.0005)
        }
    }

    func testChannelsAreMixedToMono() {
        // The same bass on both channels, but opposite signs, cancels out
        var opposite: [Int16] = []
        for n in 0..<rate {
            let value = Int16(0.3 * 32767 * sin(2 * .pi * 60 * Double(n) / Double(rate)))
            opposite += [value, -value]
        }
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2)
        XCTAssertTrue(outputs(&haptics, opposite).allSatisfy { $0.isSilent })

        // Bass on one channel only is felt at half the level of the same bass on both
        var left: [Int16] = []
        for n in 0..<rate {
            left += [Int16(0.2 * 32767 * sin(2 * .pi * 60 * Double(n) / Double(rate))), 0]
        }
        var oneSide = AudioHaptics(sampleRate: rate, channelCount: 2)
        var both = AudioHaptics(sampleRate: rate, channelCount: 2)
        let single = outputs(&oneSide, left).last!.level
        let double = outputs(&both, sine(hz: 60, amplitude: 0.2, frames: rate)).last!.level
        XCTAssertLessThan(single, double)
        XCTAssertGreaterThan(single, 0)
    }

    func testMonoAndSurroundAudioWork() {
        var mono = AudioHaptics(sampleRate: rate, channelCount: 1)
        XCTAssertEqual(outputs(&mono, sine(hz: 60, amplitude: 0.1, frames: rate, channels: 1)).last!.level, 0.345, accuracy: 0.03)
        var surround = AudioHaptics(sampleRate: rate, channelCount: 6)
        XCTAssertEqual(outputs(&surround, sine(hz: 60, amplitude: 0.1, frames: rate, channels: 6)).last!.level, 0.345, accuracy: 0.03)
        // A zero or negative channel count is treated as one, as on Android
        XCTAssertEqual(AudioHaptics(sampleRate: rate, channelCount: 0).channelCount, 1)
    }

    func testAPartialFrameAtTheEndOfABlockIsIgnored() {
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2)
        // Three samples are one whole stereo frame and half of another; no tick, no crash
        XCTAssertTrue(outputs(&haptics, [Int16](repeating: 20_000, count: 3)).isEmpty)
        XCTAssertTrue(outputs(&haptics, []).isEmpty)
    }

    func testTheLevelFallsAwayWhenTheBassStops() {
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2)
        let loud = outputs(&haptics, sine(hz: 60, amplitude: 0.5, frames: rate / 2))
        XCTAssertEqual(loud.last?.level, 1)
        // The envelope releases over about 80 ms, so after half a second of silence nothing is left
        let quiet = outputs(&haptics, [Int16](repeating: 0, count: rate))
        XCTAssertEqual(quiet.last, .silent)
        // And it is falling, not switching off: the first tick after the bass stops is still felt
        XCTAssertFalse(quiet.first!.isSilent)
        var previous: Float = 1
        for output in quiet {
            XCTAssertLessThanOrEqual(output.level, previous)
            previous = output.level
        }
    }

    func testResetStartsAFreshStream() {
        var haptics = AudioHaptics(sampleRate: rate, channelCount: 2)
        _ = outputs(&haptics, sine(hz: 60, amplitude: 0.5, frames: rate / 2))
        XCTAssertFalse(haptics.latest.isSilent)
        haptics.reset()
        XCTAssertEqual(haptics.latest, .silent)
        XCTAssertTrue(outputs(&haptics, [Int16](repeating: 0, count: rate)).allSatisfy { $0.isSilent })
    }

    func testOtherSampleRatesKeepThirtyMillisecondTicks() {
        XCTAssertEqual(AudioHaptics(sampleRate: 44_100, channelCount: 2).framesPerTick, 1323)
        XCTAssertEqual(AudioHaptics(sampleRate: 16_000, channelCount: 1).framesPerTick, 480)
        // The bass cut-off is in hertz, so a 60 Hz tone gives about the same level at any rate
        var low = AudioHaptics(sampleRate: 16_000, channelCount: 1)
        var pcm: [Int16] = []
        for n in 0..<16_000 {
            pcm.append(Int16(0.1 * 32767 * sin(2 * .pi * 60 * Double(n) / 16_000)))
        }
        XCTAssertEqual(outputs(&low, pcm).last!.level, 0.345, accuracy: 0.03)
    }

    // MARK: What the motors are told

    func testMotorValuesFollowAndroid() {
        let full = AudioHapticsOutput(level: 1)
        XCTAssertEqual(full.lowFrequencyMotor, 65535)
        XCTAssertEqual(full.highFrequencyMotor, 0)
        XCTAssertEqual(full.deviceAmplitude, 255)

        let half = AudioHapticsOutput(level: 0.5)
        XCTAssertEqual(half.lowFrequencyMotor, 32768)
        XCTAssertEqual(half.deviceAmplitude, 128)

        // Never below 1 while there is any level, so the vibrator doesn't switch off early
        let faint = AudioHapticsOutput(level: 0.0005)
        XCTAssertEqual(faint.deviceAmplitude, 1)
        XCTAssertEqual(faint.lowFrequencyMotor, 33)

        let none = AudioHapticsOutput(level: 0)
        XCTAssertEqual(none.lowFrequencyMotor, 0)
        XCTAssertEqual(none.deviceAmplitude, 0)
        XCTAssertTrue(none.isSilent)
    }

    // MARK: Core Haptics

    func testCoreHapticsMappingStaysInRangeAndRisesWithTheLevel() {
        let off = AudioHaptics.coreHaptics(forLevel: 0)
        XCTAssertEqual(off, CoreHapticsLevel(intensity: 0, sharpness: 0))
        XCTAssertEqual(AudioHaptics.coreHaptics(forLevel: -1), off)

        var previous = AudioHaptics.coreHaptics(forLevel: 0.001)
        XCTAssertGreaterThan(previous.intensity, 0.1)
        for i in 2...100 {
            let now = AudioHaptics.coreHaptics(forLevel: Float(i) / 100)
            XCTAssertGreaterThanOrEqual(now.intensity, previous.intensity, "at \(i)")
            XCTAssertGreaterThanOrEqual(now.sharpness, previous.sharpness, "at \(i)")
            XCTAssertTrue((0...1).contains(now.intensity) && (0...1).contains(now.sharpness), "at \(i)")
            previous = now
        }
        let full = AudioHaptics.coreHaptics(forLevel: 1)
        XCTAssertEqual(full.intensity, 1, accuracy: 0.0001)
        XCTAssertEqual(AudioHaptics.coreHaptics(forLevel: 7), full)
        // Bass stays on the soft side
        XCTAssertLessThanOrEqual(full.sharpness, 0.5)
    }
}
