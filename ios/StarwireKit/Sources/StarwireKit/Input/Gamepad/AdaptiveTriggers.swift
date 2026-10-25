import Foundation

// DualSense adaptive trigger effects from the host (moonlight-common-c's setAdaptiveTriggers:
// an effect type and 10 bytes per trigger, as games write them to the controller), decoded into
// what iOS's GCDualSenseAdaptiveTrigger can do. Ported from VoidLink's ControllerUtil.swift
// (GPL-3.0, The-Fried-Fish), unchanged in its maths.

public struct AdaptiveTriggerEffect: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case off, feedback, positionalFeedback, weapon, slopeFeedback, vibration, positionalVibration
    }

    public var mode: Mode = .off
    public var startPosition: Float = 0
    public var endPosition: Float = 0
    public var startStrength: Float = 0
    public var endStrength: Float = 0
    public var frequency: Float = 0
    /// Per zone (10 zones), for the positional modes
    public var positionalStrength = [Float](repeating: 0, count: 10)

    public init(mode: Mode = .off) {
        self.mode = mode
    }

    /// `moonlight-common-c`'s DS_EFFECT_* flags in setAdaptiveTriggers' `eventFlags`
    public static let rightTriggerFlag: UInt8 = 0x04
    public static let leftTriggerFlag: UInt8 = 0x08

    /// Decodes one trigger's effect. Fewer than 10 bytes turns the trigger off.
    public static func decode(type: UInt8, bytes: [UInt8]) -> AdaptiveTriggerEffect {
        guard bytes.count >= 10 else { return AdaptiveTriggerEffect() }
        var effect = AdaptiveTriggerEffect()
        switch type {
        case 0x00, 0x05:
            effect.mode = .off
        case 0x01, 0x11:
            effect.mode = .feedback
            effect.startPosition = byteScale(bytes[0])
            effect.startStrength = type == 0x01 ? byteScale(bytes[1]) : clamp01(Float(bytes[1]) / 10)
        case 0x02, 0x12:
            effect.mode = .weapon
            setSpan(&effect, first: Int(bytes[0]), last: Int(bytes[1]), count: 256)
            effect.startStrength = type == 0x02 ? byteScale(bytes[2]) : clamp01(Float(bytes[2]) / 10)
        case 0x06:
            effect.mode = .vibration
            effect.frequency = clamp01(Float(bytes[0]) / 255)
            effect.startStrength = byteScale(bytes[1])
            effect.startPosition = byteScale(bytes[2])
        case 0x21:
            effect = decodeZoned(bytes, mode: .positionalFeedback)
        case 0x26:
            effect = decodeZoned(bytes, mode: .positionalVibration)
            effect.frequency = clamp01(Float(bytes[8]) / 255)
        case 0x25:
            effect.mode = .weapon
            setSpan(&effect, first: firstZone(zoneMask(bytes)), last: lastZone(zoneMask(bytes)), count: 10)
            effect.startStrength = Float((bytes[2] & 7) + 1) / 8
        case 0x22:
            effect.mode = .slopeFeedback
            setSpan(&effect, first: firstZone(zoneMask(bytes)), last: lastZone(zoneMask(bytes)), count: 10)
            effect.startStrength = Float((bytes[2] & 7) + 1) / 8
            effect.endStrength = Float(((bytes[2] >> 3) & 7) + 1) / 8
        case 0x23, 0x27:
            effect.mode = .vibration
            effect.startPosition = zonePosition(firstZone(zoneMask(bytes)) ?? 0)
            effect.startStrength = type == 0x23 ? 0.5 : clamp01(Float(max(bytes[2] & 7, (bytes[2] >> 3) & 7)) / 7)
            effect.frequency = clamp01(Float(bytes[3]) / 255)
        default:
            effect.mode = .off
        }

        switch effect.mode {
        case .vibration, .positionalVibration:
            if effect.frequency <= 0 || max(effect.startStrength, effect.endStrength) <= 0 { effect.mode = .off }
        case .feedback, .positionalFeedback, .weapon, .slopeFeedback:
            if max(effect.startStrength, effect.endStrength) <= 0 { effect.mode = .off }
        case .off:
            break
        }
        return effect
    }

    /// Before iOS 15.4 there are no positional or slope modes: use the nearest simple one.
    public func withoutPositionalModes() -> AdaptiveTriggerEffect {
        var copy = self
        switch mode {
        case .positionalFeedback: copy.mode = .feedback
        case .positionalVibration: copy.mode = .vibration
        case .slopeFeedback:
            copy.startStrength = max(startStrength, endStrength)
            copy.mode = .weapon
        default: break
        }
        return copy
    }

    private static func clamp01(_ value: Float) -> Float { max(0, min(1, value)) }
    private static func stepPosition(_ step: Int, count: Int) -> Float { clamp01(Float(step) / Float(count - 1)) }
    private static func byteScale(_ value: UInt8) -> Float { stepPosition(Int(value), count: 256) }
    private static func zonePosition(_ zone: Int) -> Float { stepPosition(zone, count: 10) }
    private static func zoneMask(_ bytes: [UInt8]) -> UInt16 { (UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)) & 0x03ff }
    private static func firstZone(_ mask: UInt16) -> Int? { mask == 0 ? nil : mask.trailingZeroBitCount }
    private static func lastZone(_ mask: UInt16) -> Int? { mask == 0 ? nil : 15 - mask.leadingZeroBitCount }

    private static func setSpan(_ effect: inout AdaptiveTriggerEffect, first: Int?, last: Int?, count: Int) {
        let start = max(0, min(first ?? 0, count - 2))
        let end = max(start + 1, min(last ?? (start + 1), count - 1))
        effect.startPosition = stepPosition(start, count: count)
        effect.endPosition = stepPosition(end, count: count)
    }

    private static func decodeZoned(_ bytes: [UInt8], mode: Mode) -> AdaptiveTriggerEffect {
        var effect = AdaptiveTriggerEffect(mode: mode)
        let mask = zoneMask(bytes)
        let packed = UInt32(bytes[2]) | (UInt32(bytes[3]) << 8) | (UInt32(bytes[4]) << 16) | (UInt32(bytes[5]) << 24)
        for zone in 0..<10 where mask & (1 << zone) != 0 {
            let strength = clamp01(Float(((packed >> (3 * UInt32(zone))) & 7) + 1) / 8)
            effect.positionalStrength[zone] = strength
            effect.startStrength = max(effect.startStrength, strength)
        }
        effect.startPosition = zonePosition(firstZone(mask) ?? 0)
        return effect
    }
}
