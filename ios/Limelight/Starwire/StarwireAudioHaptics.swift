//
//  StarwireAudioHaptics.swift
//  Starwire
//
//  Audio haptics (Starwire for Android's AudioHaptics): the game's bass below 120 Hz becomes
//  vibration, to the controller's motors and, on iPhone, the Taptic Engine. iPads have no
//  vibration motor, so there only controllers get it. StarwireKit's AudioHaptics does the maths
//  on the decoded stream audio; this class reads the settings and drives the outputs.
//

import CoreHaptics
import Foundation
import StarwireKit

@objc(StarwireAudioHaptics)
final class StarwireAudioHaptics: NSObject {
    @objc static let shared = StarwireAudioHaptics()

    private let lock = NSLock()
    private var haptics: AudioHaptics?
    private var toController = false
    private var toDevice = false
    private var lastMotor: UInt16 = 0
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    /// Sends a level to controller 0's motors (low and high frequency). Set by the stream screen.
    @objc var rumble: ((UInt16, UInt16) -> Void)?

    /// A stream's audio started (or restarted) with this format: read the settings.
    @objc func start(sampleRate: Int, channels: Int) {
        let store = StarwireSettings.store
        let mode: String = { if case .string(let v)? = store.value("list_audio_haptics") { return v } else { return "off" } }()
        let strength: Int = { if case .int(let v)? = store.value("seekbar_audio_haptics_intensity") { return v } else { return 100 } }()
        lock.lock()
        defer { lock.unlock() }
        toController = mode == "controller" || mode == "both"
        toDevice = (mode == "device" || mode == "both") && CHHapticEngine.capabilitiesForHardware().supportsHaptics
        haptics = (toController || toDevice)
            ? AudioHaptics(sampleRate: sampleRate, channelCount: channels, strengthPercent: strength) : nil
        lastMotor = 0
        if haptics != nil {
            StarwireLog.info("Audio haptics: \(mode) at \(strength)%\(toDevice ? "" : (mode == "device" || mode == "both") ? " (this device has no vibration motor)" : "")")
        }
        if toDevice && engine == nil {
            startDeviceEngine()
        }
    }

    /// Decoded audio, interleaved Float32, from the audio thread.
    @objc func process(_ samples: UnsafePointer<Float>, frames: Int, channels: Int) {
        lock.lock()
        guard var current = haptics else {
            lock.unlock()
            return
        }
        var ticks: [AudioHapticsOutput] = []
        current.process(UnsafeBufferPointer(start: samples, count: frames * channels)) { ticks.append($0) }
        haptics = current
        let controller = toController
        let device = toDevice
        lock.unlock()
        for tick in ticks {
            if controller {
                // Only changes go out, so a silent stretch leaves the game's own rumble alone
                if tick.lowFrequencyMotor != lastMotor {
                    lastMotor = tick.lowFrequencyMotor
                    let low = tick.lowFrequencyMotor
                    let high = tick.highFrequencyMotor
                    DispatchQueue.main.async { self.rumble?(low, high) }
                }
            }
            if device {
                play(AudioHaptics.coreHaptics(forLevel: tick.level))
            }
        }
    }

    @objc func stop() {
        lock.lock()
        haptics = nil
        let wasRumbling = lastMotor != 0
        lastMotor = 0
        lock.unlock()
        if wasRumbling {
            DispatchQueue.main.async { self.rumble?(0, 0) }
        }
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        engine?.stop()
        engine = nil
    }

    // MARK: - The Taptic Engine

    private func startDeviceEngine() {
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true
            try engine.start()
            // One long continuous event whose strength follows the bass
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ], relativeTime: 0, duration: 3600)
            let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)],
                                      atTime: CHHapticTimeImmediate)
            self.engine = engine
            self.player = player
        } catch {
            StarwireLog.info("Audio haptics: the Taptic Engine didn't start: \(error)")
        }
    }

    private func play(_ level: CoreHapticsLevel) {
        try? player?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: level.intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: level.sharpness, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }
}
