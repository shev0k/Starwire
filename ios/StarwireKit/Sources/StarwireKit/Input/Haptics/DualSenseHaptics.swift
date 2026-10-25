import Foundation

// Vibeshine's DualSense haptics (control packet 0x5601, Nonary's moonlight-common-c
// ControllerHaptics.h) carry the game's haptic audio: 48 kHz, 16-bit, stereo, one channel per
// actuator (left grip, right grip), up to 240 frames a packet. iOS can't play raw waveforms on
// the DualSense's actuators, so this turns them into what Core Haptics can play: for every 10 ms
// of audio, an intensity, a sharpness and a transient strength per side. The app feeds those to
// a continuous Core Haptics player on each grip.
//
// The idea (an envelope of loudness, low-band share for sharpness, and onsets as transients)
// follows VoidLink's DualSense haptics (ControllerUtil.swift, GPL-3.0, The-Fried-Fish), which
// does the same with its own analysis library. The analysis here is written for Starwire.

/// What Core Haptics should play on one actuator for one window. All values from 0 to 1.
public struct HapticLane: Equatable, Sendable {
    public var intensity: Float
    public var sharpness: Float
    /// A sudden rise: play a transient event this strong (0 means none).
    public var transient: Float

    public init(intensity: Float, sharpness: Float, transient: Float) {
        self.intensity = intensity
        self.sharpness = sharpness
        self.transient = transient
    }

    public static let silent = HapticLane(intensity: 0, sharpness: 0, transient: 0)

    public var isSilent: Bool { intensity == 0 && transient == 0 }
}

/// One window of haptics for both grips.
public struct HapticFrame: Equatable, Sendable {
    /// Where the window starts, in seconds after the first sample of the packet that finished
    /// it. Negative when the window began in an earlier packet.
    public var offset: TimeInterval
    public var left: HapticLane
    public var right: HapticLane

    public var isSilent: Bool { left.isSilent && right.isSilent }
}

/// Turns 0x5601 PCM into `HapticFrame`s. One per controller. Not thread safe: call it from one
/// queue.
public final class DualSenseHapticsConverter {
    public static let sampleRate = 48_000
    /// 10 ms windows
    public static let windowFrames = 480
    /// Below this RMS (about -48 dBFS) a window counts as silence.
    public static let noiseGate: Float = 0.004
    /// Energy below this frequency counts as low band (soft, rumbly); above it as sharp.
    public static let lowBandHz: Float = 120
    /// How fast the intensity may fall: about 30 ms to drop by two thirds, so a buzz doesn't chatter.
    public static let releasePerWindow: Float = 0.72

    /// Scales intensity, from Starwire's haptics strength setting (1 is 100%).
    public var gain: Float

    private var pending: [Int16] = []
    private var lastSequence: UInt32?
    private var lanes = [LaneState(), LaneState()]

    public init(gain: Float = 1) {
        self.gain = gain
    }

    /// Forgets the stream so far: the next packet starts fresh.
    public func reset() {
        pending.removeAll()
        lastSequence = nil
        lanes = [LaneState(), LaneState()]
    }

    /// Takes one packet: its sequence number and `frames` interleaved left/right samples.
    /// Returns whether packets were missed before it (the frames then start fresh) and the
    /// windows it completed.
    public func process(sequence: UInt32, samples: [Int16]) -> (discontinuity: Bool, frames: [HapticFrame]) {
        var discontinuity = false
        if let last = lastSequence, sequence != last &+ 1 {
            discontinuity = true
            pending.removeAll()
            lanes = [LaneState(), LaneState()]
        }
        lastSequence = sequence

        let carried = pending.count / 2
        pending.append(contentsOf: samples.prefix(samples.count & ~1))
        var frames: [HapticFrame] = []
        var start = 0
        let window = Self.windowFrames * 2
        while pending.count - start >= window {
            let slice = pending[start..<start + window]
            let left = lanes[0].analyse(slice, channel: 0, gain: gain)
            let right = lanes[1].analyse(slice, channel: 1, gain: gain)
            let offset = Double(start / 2 - carried) / Double(Self.sampleRate)
            frames.append(HapticFrame(offset: offset, left: left, right: right))
            start += window
        }
        pending.removeFirst(start)
        return (discontinuity, frames)
    }

    /// Reads a 0x5601 payload's samples (little-endian 16-bit) from raw bytes.
    public static func samples(fromLittleEndian bytes: [UInt8]) -> [Int16] {
        var out = [Int16](repeating: 0, count: bytes.count / 2)
        for i in 0..<out.count {
            out[i] = Int16(bitPattern: UInt16(bytes[2 * i]) | UInt16(bytes[2 * i + 1]) << 8)
        }
        return out
    }

    private struct LaneState {
        var lowPass: Float = 0
        var lastRMS: Float = 0
        var lastIntensity: Float = 0

        mutating func analyse(_ slice: ArraySlice<Int16>, channel: Int, gain: Float) -> HapticLane {
            let alpha = 1 - exp(-2 * Float.pi * DualSenseHapticsConverter.lowBandHz / Float(DualSenseHapticsConverter.sampleRate))
            var energy: Float = 0
            var lowEnergy: Float = 0
            var crossings = 0
            var previous: Float = 0
            var count = 0
            var index = slice.startIndex + channel
            while index < slice.endIndex {
                let x = Float(slice[index]) / 32768
                lowPass += alpha * (x - lowPass)
                energy += x * x
                lowEnergy += lowPass * lowPass
                if count > 0 && (x >= 0) != (previous >= 0) {
                    crossings += 1
                }
                previous = x
                count += 1
                index += 2
            }
            guard count > 0 else { return .silent }
            let rms = (energy / Float(count)).squareRoot()
            defer { lastRMS = rms }
            guard rms >= DualSenseHapticsConverter.noiseGate else {
                lastIntensity *= DualSenseHapticsConverter.releasePerWindow
                if lastIntensity < 0.02 { lastIntensity = 0 }
                return HapticLane(intensity: lastIntensity, sharpness: 0, transient: 0)
            }

            // Loudness feels roughly like the square root of the signal's RMS.
            let target = min(rms.squareRoot() * 1.15 * gain, 1)
            let intensity = max(target, lastIntensity * DualSenseHapticsConverter.releasePerWindow)
            lastIntensity = intensity

            // Sharpness: how much of the energy is above the low band, and how fast the wave
            // crosses zero (40 Hz is dull, 400 Hz is crisp).
            let highShare = energy > 0 ? max(0, 1 - lowEnergy / energy) : 0
            let crossingHz = Float(crossings) / 2 / (Float(count) / Float(DualSenseHapticsConverter.sampleRate))
            let crisp = min(max((crossingHz - 40) / 360, 0), 1)
            let sharpness = min(max(0.6 * highShare + 0.4 * crisp, 0), 1)

            // A transient when the RMS jumps well above the last window's.
            let rise = rms - lastRMS * 1.6
            let transient: Float = rise > 0.02 ? min(rise / 0.25 * gain, 1) : 0
            return HapticLane(intensity: intensity, sharpness: sharpness, transient: transient)
        }
    }
}
