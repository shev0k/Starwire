//
//  StarwireGamepads.swift
//  Starwire
//
//  What happens to a controller's state between moonlight-ios's ControllerSupport and the PC:
//  Android's deadzone, flipped face buttons, mouse emulation and analog scrolling
//  (GamepadProcessor), opening the stream menu by holding a button (MenuTrigger), the DualSense
//  touchpad as a mouse, Vibeshine's DualSense haptics as Core Haptics, adaptive triggers, and
//  the device's motion sensors for a controller without its own. The rules are in StarwireKit
//  and tested there; this file runs them on the main queue and talks to GameController and
//  Core Haptics.
//

import CoreHaptics
import CoreMotion
import Foundation
import GameController
import StarwireKit
import UIKit

@objc(StarwireGamepads)
final class StarwireGamepads: NSObject {
    @objc static let shared = StarwireGamepads()

    private let sink = LiveInputSink()
    private var options = GamepadOptions()
    private var processors: [Int: GamepadProcessor] = [:]
    private var trigger = MenuTrigger()
    private var touchpads: [Int: GamepadTouchpad] = [:]
    private var timer: Timer?
    private var lastButtons: [Int: Int] = [:]

    /// The stream menu is showing: controllers drive it, not the PC
    @objc var menuOpen = false
    /// The controller keyboard is showing: controllers type on it, not on the PC
    @objc var keyboardOpen = false
    /// While the controller keyboard is open: each controller state, face buttons already flipped
    var onKeyboardState: ((ControllerState) -> Void)?
    /// When a controller was last used (systemUptime), to pick the keyboard that suits
    private(set) var lastActivity: TimeInterval = -.infinity

    /// Buttons down on any controller now
    var heldButtons: Int { lastButtons.values.reduce(0, |) }

    /// A controller is connected
    var hasController: Bool { !GCController.controllers().isEmpty }
    /// Hold to open: called on the main queue
    @objc var onOpenMenu: (() -> Void)?
    /// While the menu is open: buttons newly pressed (GamepadButton flags), on the main queue
    @objc var onMenuButtons: ((Int) -> Void)?
    /// A short message for a toast
    @objc var onNotice: ((String) -> Void)?
    /// The GCController behind a controller number (from ControllerSupport)
    @objc var controllerForNumber: ((Int) -> GCController?)?

    /// Reads the settings again; call when a stream starts.
    @objc func streamStarted() {
        let store = StarwireSettings.store
        options = GamepadOptions(store: store)
        trigger = MenuTrigger(setting: store.string("overlay_trigger_button"), holdSetting: store.string("overlay_hold_duration"))
        processors.removeAll()
        touchpads.removeAll()
        lastButtons.removeAll()
        menuOpen = false
        keyboardOpen = false
        StarwireLog.info("Gamepads: deadzone \(options.deadzonePercent)%, flip \(options.flipFaceButtons), scrolling \(options.analogScrolling.rawValue), touchpad as mouse \(options.touchpadAsMouse), menu \(trigger.button.title) for \(Int(trigger.holdDuration * 1000)) ms")
    }

    @objc func streamEnded() {
        timer?.invalidate()
        timer = nil
        stopMotionFallback()
        haptics.values.forEach { $0.stop() }
        haptics.removeAll()
        converters.removeAll()
    }

    @objc var menuTriggerTitle: String { trigger.button.title }

    /// `checkbox_mouse_nav_buttons`: a mouse's back and forward buttons go to the PC
    @objc func mouseNavigationButtons() -> Bool {
        StarwireSettings.store.bool("checkbox_mouse_nav_buttons")
    }

    // MARK: Controller state

    /// One controller's whole state from ControllerSupport (sticks -32766...32766, triggers
    /// 0...255, moonlight-common-c's button flags). Any queue.
    @objc func send(number: Int, activeMask: Int, buttons: Int, leftTrigger: Int, rightTrigger: Int,
                    leftX: Int, leftY: Int, rightX: Int, rightY: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.send(number: number, activeMask: activeMask, buttons: buttons, leftTrigger: leftTrigger, rightTrigger: rightTrigger,
                          leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY)
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var raw = buttons
        if options.touchpadAsMouse {
            // The pad's click is a left click, not the controller's touchpad button
            let click = raw & GamepadButton.touchpad
            if click != (lastButtons[number] ?? 0) & GamepadButton.touchpad {
                touchpad(number).click(down: click != 0).forEach(sink.send)
            }
            raw &= ~GamepadButton.touchpad
        }
        let previous = lastButtons[number] ?? 0
        lastButtons[number] = buttons
        if buttons != previous {
            StarwireLog.debug(String(format: "Gamepads: controller %d buttons 0x%X, triggers %d/%d, sticks %d,%d %d,%d",
                                     number, buttons, leftTrigger, rightTrigger, leftX, leftY, rightX, rightY))
        }
        if buttons != previous || max(abs(leftX), abs(leftY), abs(rightX), abs(rightY)) > 0x2000
            || leftTrigger > 64 || rightTrigger > 64 {
            lastActivity = now
        }
        if keyboardOpen {
            let flipped = options.flipFaceButtons ? GamepadMath.flipFaceButtons(buttons) : buttons
            onKeyboardState?(ControllerState(number: number, activeMask: activeMask, buttons: flipped, leftTrigger: leftTrigger,
                                             rightTrigger: rightTrigger, leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY))
            return
        }
        if menuOpen {
            let pressed = buttons & ~previous
            if pressed != 0 {
                onMenuButtons?(options.flipFaceButtons ? GamepadMath.flipFaceButtons(pressed) : pressed)
            }
            return
        }
        let processor = processor(number, activeMask: activeMask)
        let scale: Float = 0x7FFE
        let events = processor.update(buttons: raw,
                                      leftStick: (Float(leftX) / scale, Float(leftY) / scale),
                                      rightStick: (Float(rightX) / scale, Float(rightY) / scale),
                                      leftTrigger: Float(leftTrigger) / 255, rightTrigger: Float(rightTrigger) / 255)
        for event in events {
            if case .controller(let state) = event {
                handle(trigger.update(state, now: now))
            } else {
                sink.send(event)
            }
        }
        scheduleTimer()
    }

    private func processor(_ number: Int, activeMask: Int) -> GamepadProcessor {
        if let existing = processors[number] {
            existing.activeMask = activeMask
            return existing
        }
        let created = GamepadProcessor(options: options, controllerNumber: number, activeMask: activeMask)
        // The trigger deadzone is applied by GameController already
        created.triggerDeadzone = 0
        processors[number] = created
        return created
    }

    private func handle(_ outcomes: [MenuTrigger.Outcome]) {
        for outcome in outcomes {
            switch outcome {
            case .send(let state):
                sink.send(.controller(state))
            case .openMenu:
                StarwireLog.info("Gamepads: \(trigger.button.title) held, opening the menu")
                onOpenMenu?()
            }
        }
    }

    // MARK: Mouse emulation

    @objc var mouseEmulationOn: Bool {
        processors[0]?.mouseEmulationActive ?? false
    }

    /// The menu's Mouse switch: controller 0, as on Android.
    @objc func toggleMouseEmulation() {
        let processor = processor(0, activeMask: processors[0]?.activeMask ?? 1)
        processor.toggleMouseEmulation(now: ProcessInfo.processInfo.systemUptime)
        onNotice?(StreamMenu.mouseEmulationNotice(on: processor.mouseEmulationActive))
        if processor.mouseEmulationActive {
            // The PC sees an idle controller meanwhile
            sink.send(.controller(ControllerState(number: 0, activeMask: processor.activeMask)))
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        let deadlines = processors.values.compactMap(\.nextDeadline) + [trigger.nextDeadline].compactMap { $0 }
        guard let next = deadlines.min() else {
            timer?.invalidate()
            timer = nil
            return
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(next - ProcessInfo.processInfo.systemUptime, 0), repeats: false) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for processor in self.processors.values {
                processor.tick(now: now).forEach(self.sink.send)
            }
            self.handle(self.trigger.tick(now: now))
            self.scheduleTimer()
        }
    }

    // MARK: Touchpad

    private func touchpad(_ number: Int) -> GamepadTouchpad {
        touchpads[number] ?? GamepadTouchpad(controllerNumber: number, asMouse: options.touchpadAsMouse)
    }

    /// Whether ControllerSupport should leave the touchpad to `touchpad(...)`.
    @objc var touchpadAsMouse: Bool { options.touchpadAsMouse }

    /// A touchpad finger (phase: LI_TOUCH_EVENT_*), with x and y from 0 to 1.
    @objc func touchpad(number: Int, finger: Int, phase: Int, x: Double, y: Double) {
        DispatchQueue.main.async {
            guard let phase = TouchPhase(rawValue: phase) else { return }
            var pad = self.touchpad(number)
            pad.touch(id: finger, phase: phase, x: x, y: y).forEach(self.sink.send)
            self.touchpads[number] = pad
        }
    }

    // MARK: DualSense haptics (Vibeshine 0x5601)

    private let hapticsQueue = DispatchQueue(label: "io.github.shev0k.starwire.haptics", qos: .userInteractive)
    private var converters: [Int: DualSenseHapticsConverter] = [:]
    private var haptics: [Int: DualSenseHapticsPlayer] = [:]

    /// From moonlight-common-c's control thread: copy and return at once.
    @objc func hapticsPCM(number: Int, sequence: UInt32, pcm: Data) {
        let samples = DualSenseHapticsConverter.samples(fromLittleEndian: [UInt8](pcm))
        hapticsQueue.async {
            if self.converters[number] == nil {
                StarwireLog.info("Gamepads: DualSense haptics from the PC for controller \(number), \(samples.count / 2) frames a packet")
            }
            let converter = self.converters[number] ?? DualSenseHapticsConverter()
            self.converters[number] = converter
            let result = converter.process(sequence: sequence, samples: samples)
            guard !result.frames.isEmpty else { return }
            DispatchQueue.main.async {
                guard let player = self.hapticsPlayer(number) else { return }
                result.frames.forEach(player.play)
            }
        }
    }

    private func hapticsPlayer(_ number: Int) -> DualSenseHapticsPlayer? {
        if let existing = haptics[number] {
            return existing
        }
        guard let controller = controllerForNumber?(number), let player = DualSenseHapticsPlayer(controller: controller) else {
            return nil
        }
        haptics[number] = player
        StarwireLog.info("Gamepads: DualSense haptics started for controller \(number)")
        return player
    }

    // MARK: Adaptive triggers

    @objc func adaptiveTriggers(number: Int, flags: UInt8, typeLeft: UInt8, typeRight: UInt8, left: Data, right: Data) {
        DispatchQueue.main.async {
            guard #available(iOS 14.5, *),
                  let dualSense = self.controllerForNumber?(number)?.extendedGamepad as? GCDualSenseGamepad else { return }
            StarwireLog.info(String(format: "Gamepads: adaptive triggers for controller %d: flags 0x%X, left 0x%02X, right 0x%02X",
                                    number, flags, typeLeft, typeRight))
            if flags & AdaptiveTriggerEffect.leftTriggerFlag != 0 {
                Self.apply(AdaptiveTriggerEffect.decode(type: typeLeft, bytes: [UInt8](left)), to: dualSense.leftTrigger)
            }
            if flags & AdaptiveTriggerEffect.rightTriggerFlag != 0 {
                Self.apply(AdaptiveTriggerEffect.decode(type: typeRight, bytes: [UInt8](right)), to: dualSense.rightTrigger)
            }
        }
    }

    @available(iOS 14.5, *)
    private static func apply(_ decoded: AdaptiveTriggerEffect, to trigger: GCDualSenseAdaptiveTrigger) {
        var effect = decoded
        if #unavailable(iOS 15.4) {
            effect = effect.withoutPositionalModes()
        }
        switch effect.mode {
        case .off:
            trigger.setModeOff()
        case .feedback:
            trigger.setModeFeedbackWithStartPosition(effect.startPosition, resistiveStrength: effect.startStrength)
        case .weapon:
            trigger.setModeWeaponWithStartPosition(effect.startPosition, endPosition: effect.endPosition,
                                                   resistiveStrength: effect.startStrength)
        case .vibration:
            trigger.setModeVibrationWithStartPosition(effect.startPosition, amplitude: effect.startStrength, frequency: effect.frequency)
        case .positionalFeedback:
            if #available(iOS 15.4, *) {
                let s = effect.positionalStrength
                trigger.setModeFeedback(resistiveStrengths: .init(values: (s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9])))
            }
        case .positionalVibration:
            if #available(iOS 15.4, *) {
                let s = effect.positionalStrength
                trigger.setModeVibration(amplitudes: .init(values: (s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9])),
                                         frequency: effect.frequency)
            }
        case .slopeFeedback:
            if #available(iOS 15.4, *) {
                trigger.setModeSlopeFeedback(startPosition: effect.startPosition, endPosition: effect.endPosition,
                                             startStrength: effect.startStrength, endStrength: effect.endStrength)
            }
        }
    }

    // MARK: Motion fallback

    private let motion = CMMotionManager()
    private var motionNumber = 0
    private var motionRates: [MotionSensor: Int] = [:]

    /// Whether the device's sensors stand in for controller `number`'s: the setting is on, it is
    /// the first controller, and it has no motion sensors of its own.
    @objc func usesMotionFallback(number: Int, controllerHasMotion: Bool) -> Bool {
        number == 0 && !controllerHasMotion && StarwireSettings.store.bool("checkbox_gamepad_motion_fallback")
            && (motion.isGyroAvailable || motion.isAccelerometerAvailable)
    }

    /// The host asks for motion reports (rate 0 stops them).
    @objc func setMotionFallback(number: Int, sensor: Int, rateHz: Int) {
        DispatchQueue.main.async {
            guard let type = MotionSensor(rawValue: sensor) else { return }
            self.motionNumber = number
            self.motionRates[type] = MotionFallback.rate(requested: rateHz)
            self.updateMotion()
        }
    }

    private func rotation() -> MotionFallback.Rotation {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeRight: return .r90
        case .portraitUpsideDown: return .r180
        case .landscapeLeft: return .r270
        default: return .r0
        }
    }

    private func updateMotion() {
        let number = motionNumber
        if let gyroRate = motionRates[.gyroscope], gyroRate > 0, motion.isGyroAvailable {
            motion.gyroUpdateInterval = 1 / Double(gyroRate)
            if !motion.isGyroActive {
                motion.startGyroUpdates(to: .main) { [weak self] data, _ in
                    guard let self, let r = data?.rotationRate else { return }
                    self.sink.send(MotionFallback.gyroEvent(number: number, radiansPerSecond: (r.x, r.y, r.z), rotation: self.rotation()))
                }
            }
        } else if motion.isGyroActive {
            motion.stopGyroUpdates()
            // Leave the controller still on the PC
            sink.send(.controllerMotion(number: number, sensor: .gyroscope, x: 0, y: 0, z: 0))
        }
        if let accelRate = motionRates[.accelerometer], accelRate > 0, motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 1 / Double(accelRate)
            if !motion.isAccelerometerActive {
                motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                    guard let self, let a = data?.acceleration else { return }
                    self.sink.send(MotionFallback.accelerometerEvent(number: number, g: (a.x, a.y, a.z), rotation: self.rotation()))
                }
            }
        } else if motion.isAccelerometerActive {
            motion.stopAccelerometerUpdates()
        }
    }

    private func stopMotionFallback() {
        motion.stopGyroUpdates()
        motion.stopAccelerometerUpdates()
        motionRates.removeAll()
    }

    // MARK: Vibration fallback

    private var deviceEngine: CHHapticEngine?
    private var devicePlayer: CHHapticAdvancedPatternPlayer?

    /// "Emulate rumble support with vibration": rumble for a controller that can't, on a device
    /// with a vibration motor (iPhone; iPads have none). Motor values 0...65535.
    @objc func vibrationFallback(lowFrequency: Int, highFrequency: Int) {
        let store = StarwireSettings.store
        guard store.bool("checkbox_vibrate_fallback"), CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        DispatchQueue.main.async {
            do {
                if self.deviceEngine == nil {
                    let engine = try CHHapticEngine()
                    try engine.start()
                    let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                    ], relativeTime: 0, duration: 30)
                    let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                    player.loopEnabled = true
                    self.deviceEngine = engine
                    self.devicePlayer = player
                }
                let strength = Float(store.int("seekbar_vibrate_fallback_strength")) / 100
                let level = min(Float(max(lowFrequency, highFrequency)) / 65535 * strength, 1)
                if level <= 0 {
                    try self.devicePlayer?.stop(atTime: CHHapticTimeImmediate)
                } else {
                    try self.devicePlayer?.start(atTime: CHHapticTimeImmediate)
                    try self.devicePlayer?.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: level,
                                                                                    relativeTime: 0)], atTime: CHHapticTimeImmediate)
                }
            } catch {
                StarwireLog.info("Gamepads: vibration fallback failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Plays `HapticFrame`s on a DualSense's two grips: a continuous event on each, whose intensity
/// and sharpness follow the frames, plus a short transient on each onset.
final class DualSenseHapticsPlayer {
    private var engines: [CHHapticEngine] = []
    private var players: [CHHapticAdvancedPatternPlayer] = []
    private static let baseSharpness: Float = 0.5

    init?(controller: GCController) {
        guard let haptics = controller.haptics else { return nil }
        for locality in [GCHapticsLocality.leftHandle, .rightHandle] {
            guard haptics.supportedLocalities.contains(locality), let engine = haptics.createEngine(withLocality: locality) else {
                return nil
            }
            do {
                try engine.start()
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Self.baseSharpness),
                ], relativeTime: 0, duration: 30)
                let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                player.loopEnabled = true
                try player.start(atTime: CHHapticTimeImmediate)
                try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)],
                                          atTime: CHHapticTimeImmediate)
                engines.append(engine)
                players.append(player)
            } catch {
                StarwireLog.info("Gamepads: DualSense haptics engine failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    func play(_ frame: HapticFrame) {
        for (index, lane) in [frame.left, frame.right].enumerated() where index < players.count {
            let player = players[index]
            try? player.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: lane.intensity, relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: lane.sharpness - Self.baseSharpness, relativeTime: 0),
            ], atTime: CHHapticTimeImmediate)
            if lane.transient > 0 {
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: lane.transient),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: max(lane.sharpness, 0.6)),
                ], relativeTime: 0)
                if let pattern = try? CHHapticPattern(events: [event], parameters: []),
                   let transient = try? engines[index].makePlayer(with: pattern) {
                    try? transient.start(atTime: CHHapticTimeImmediate)
                }
            }
        }
    }

    func stop() {
        for player in players {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        engines.forEach { $0.stop() }
    }
}
