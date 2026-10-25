import Foundation

// Audio haptics: the bass in the game's audio drives the phone's Taptic Engine and/or a
// controller's rumble, so explosions and engines can be felt.
//
// Ported from Starwire for Android's AudioHaptics.java (GPL-3.0), with the same maths: the audio is
// mixed to mono, a one-pole low-pass filter keeps what is below about 120 Hz, an envelope follows
// the loudness of that bass (instant attack, 80 ms release), and a noise gate, a gain of 4 and the
// strength setting turn the envelope into a level from 0 to 1.
//
// Android reads the level every 30 ms from a timer thread. Here the time comes from the samples:
// one tick for every 30 ms of audio fed in, so the same audio always gives the same output and
// nothing here reads a clock. The settings are `list_audio_haptics` (off, device, controller or
// both; the app decides which outputs to drive) and `seekbar_audio_haptics_intensity` (25 to 200
// percent, 100 is normal).

/// What one tick asks the motors to do. `level` is 0 to 1; the rest are what Android sends for it.
public struct AudioHapticsOutput: Equatable, Sendable {
    /// Vibration strength 0...1 after the noise gate and the strength setting.
    public var level: Float
    /// Controller heavy motor, 0...65535 (Android: `round(level * 0xFFFF)`).
    public var lowFrequencyMotor: UInt16
    /// Controller light motor. Audio haptics never uses it, as on Android.
    public var highFrequencyMotor: UInt16
    /// Android's amplitude for a vibrator with strength control: 1...255, or 0 when silent.
    public var deviceAmplitude: UInt8

    public static let silent = AudioHapticsOutput(level: 0)

    public init(level: Float) {
        self.level = level
        if level > 0 {
            lowFrequencyMotor = UInt16(min(65535, max(0, (level * 65535).rounded(.toNearestOrAwayFromZero))))
            deviceAmplitude = UInt8(min(255, max(1, (level * 255).rounded(.toNearestOrAwayFromZero))))
        }
        else {
            lowFrequencyMotor = 0
            deviceAmplitude = 0
        }
        highFrequencyMotor = 0
    }

    public var isSilent: Bool { level <= 0 }
}

/// What to play on the iPhone's Core Haptics engine. Both values are 0 to 1.
public struct CoreHapticsLevel: Equatable, Sendable {
    public var intensity: Float
    public var sharpness: Float
}

public struct AudioHaptics: Sendable {
    /// Android's lowest and highest strength setting, in percent.
    public static let strengthRange = 25...200
    /// Android's `TICK_MS`: how often the level is read.
    public static let tickSeconds = 0.030

    static let cutoffHz = 120.0
    static let releaseSeconds: Float = 0.08
    // Bass quieter than this (fraction of full scale) is ignored, so music and speech stay still
    static let noiseGate: Float = 0.02
    // Loud game bass sits around a quarter of full scale; this brings it near full strength
    static let gain: Float = 4

    public let sampleRate: Int
    public let channelCount: Int
    /// The strength setting as a factor: 1 is 100 percent.
    public let intensity: Float
    /// Frames of audio per tick (1440 at 48 kHz).
    public let framesPerTick: Int

    private let lowPassAlpha: Float
    private let releasePerSample: Float
    private var lowPassState: Float = 0
    private var envelope: Float = 0
    private var framesSinceTick = 0

    /// The most recent tick's output (silent before the first tick).
    public private(set) var latest = AudioHapticsOutput.silent

    /// - Parameters:
    ///   - sampleRate: the audio's rate in Hz, for example 48000.
    ///   - channelCount: channels in the interleaved audio (1 or more).
    ///   - strengthPercent: the strength setting; 25 to 200, anything else is brought into range.
    public init(sampleRate: Int, channelCount: Int, strengthPercent: Int = 100) {
        let rate = max(1, sampleRate)
        self.sampleRate = rate
        self.channelCount = max(1, channelCount)
        let percent = min(Self.strengthRange.upperBound, max(Self.strengthRange.lowerBound, strengthPercent))
        intensity = Float(percent) / 100
        framesPerTick = max(1, Int((Double(rate) * Self.tickSeconds).rounded()))
        // One-pole low-pass filter and envelope release, per sample (the same sums as Android)
        lowPassAlpha = Float(1 - exp(-2 * Double.pi * Self.cutoffHz / Double(rate)))
        releasePerSample = Float(exp(-1.0 / Double(Self.releaseSeconds * Float(rate))))
    }

    /// Bass envelope (fraction of full scale) to vibration strength 0...1, after the noise gate.
    public static func level(forEnvelope envelope: Float, intensity: Float) -> Float {
        let gated = (envelope * gain - noiseGate) / (1 - noiseGate)
        if gated <= 0 {
            return 0
        }
        return min(1, gated * intensity)
    }

    /// Feeds interleaved 16-bit audio, as the decoder produces it (Android's input). `onTick` is
    /// called once for every 30 ms of audio. Does not allocate.
    public mutating func process(_ pcm: UnsafeBufferPointer<Int16>, onTick: (AudioHapticsOutput) -> Void) {
        let channels = channelCount
        let divisor = Float(channels)
        var index = 0
        while index + channels <= pcm.count {
            var sum = 0
            for c in 0..<channels {
                sum += Int(pcm[index + c])
            }
            index += channels
            advance((Float(sum) / divisor) / 32768, onTick)
        }
    }

    /// Feeds interleaved 32-bit float audio (-1...1), the form iOS audio callbacks usually give.
    /// Same maths as the 16-bit form. Does not allocate.
    public mutating func process(_ pcm: UnsafeBufferPointer<Float>, onTick: (AudioHapticsOutput) -> Void) {
        let channels = channelCount
        let divisor = Float(channels)
        var index = 0
        while index + channels <= pcm.count {
            var sum: Float = 0
            for c in 0..<channels {
                sum += pcm[index + c]
            }
            index += channels
            advance(sum / divisor, onTick)
        }
    }

    /// Array forms of `process`, for tests and for callers that hold an array.
    public mutating func process(_ pcm: [Int16], onTick: (AudioHapticsOutput) -> Void) {
        pcm.withUnsafeBufferPointer { process($0, onTick: onTick) }
    }

    public mutating func process(_ pcm: [Float], onTick: (AudioHapticsOutput) -> Void) {
        pcm.withUnsafeBufferPointer { process($0, onTick: onTick) }
    }

    /// Forgets the filter, the envelope and the tick position (a new stream).
    public mutating func reset() {
        lowPassState = 0
        envelope = 0
        framesSinceTick = 0
        latest = .silent
    }

    // One frame: filter step, envelope step, and a tick when 30 ms of audio has gone by
    @inline(__always)
    private mutating func advance(_ mono: Float, _ onTick: (AudioHapticsOutput) -> Void) {
        lowPassState += lowPassAlpha * (mono - lowPassState)
        let magnitude = abs(lowPassState)
        envelope = magnitude > envelope ? magnitude : envelope * releasePerSample

        framesSinceTick += 1
        if framesSinceTick >= framesPerTick {
            framesSinceTick = 0
            latest = AudioHapticsOutput(level: Self.level(forEnvelope: envelope, intensity: intensity))
            onTick(latest)
        }
    }

    /// Maps a level to the iPhone's Core Haptics: a continuous event whose intensity and
    /// sharpness are both 0...1. A level of 0 gives (0, 0), which means "stop the player".
    ///
    /// The mapping is a design choice, not something measured on a device yet:
    /// - Intensity runs from 0.15 to 1 over the level range. The Taptic Engine is assumed to
    ///   give little you can feel at very low intensities, so a quiet but real bass level (just
    ///   past the noise gate) still produces a faint buzz instead of nothing, and the rest is a
    ///   straight line so the strength setting still scales smoothly.
    /// - Sharpness runs from 0.15 to 0.5. Bass is a dull, heavy rumble, so it stays at the soft
    ///   end, and gets a little crisper for hard hits so a big explosion has more bite than an
    ///   engine idling.
    public static func coreHaptics(forLevel level: Float) -> CoreHapticsLevel {
        guard level > 0 else { return CoreHapticsLevel(intensity: 0, sharpness: 0) }
        let clamped = min(1, level)
        return CoreHapticsLevel(intensity: 0.15 + 0.85 * clamped, sharpness: 0.15 + 0.35 * clamped)
    }
}
