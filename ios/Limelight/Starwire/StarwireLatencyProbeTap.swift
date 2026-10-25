//
//  StarwireLatencyProbeTap.swift
//  Starwire
//
//  Reads the two squares of ios/scripts/input-latency.html from each decoded frame for
//  StarwireKit's InputLatencyProbe, when a test starts the app with -StarwireLatencyProbe YES.
//  Off otherwise: one check of a static, nothing read.
//

import CoreVideo
import Foundation
import StarwireKit

@objc(StarwireLatencyProbeTap)
final class StarwireLatencyProbeTap: NSObject {
    /// Turns the probe on for this stream (the launch argument), or off.
    @objc static func streamStarted() {
        LiveInputSink.probe = UserDefaults.standard.bool(forKey: "StarwireLatencyProbe") ? InputLatencyProbe() : nil
        if LiveInputSink.probe != nil {
            StarwireLog.info("Input: latency probe on")
        }
    }

    /// From the decoder's queue, for every decoded frame.
    @objc static func noteFrame(_ pixelBuffer: CVPixelBuffer, at time: CFTimeInterval) {
        guard let probe = LiveInputSink.probe else { return }
        let input = luma(pixelBuffer, x: InputLatencyProbe.inputSquare.x, y: InputLatencyProbe.inputSquare.y)
        let scroll = luma(pixelBuffer, x: InputLatencyProbe.scrollSquare.x, y: InputLatencyProbe.scrollSquare.y)
        guard let input, let scroll else { return }
        probe.frame(at: time, input: input, scroll: scroll)
    }

    /// The probe's line for the statistics overlay, or empty when it is off
    @objc static var summary: String { LiveInputSink.probe?.result.line ?? "" }

    /// The mean brightness of a 4x4 patch of the luma plane around a point given as fractions of
    /// the picture, from 0 to 1. 8-bit and 10-bit (high bits) planes; nil for other formats.
    static func luma(_ buffer: CVPixelBuffer, x: Double, y: Double) -> Double? {
        guard CVPixelBufferIsPlanar(buffer), CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let bytesPerSample = stride >= width * 2 && is16Bit(CVPixelBufferGetPixelFormatType(buffer)) ? 2 : 1
        let cx = min(max(Int(Double(width) * x), 2), width - 3)
        let cy = min(max(Int(Double(height) * y), 2), height - 3)
        var sum = 0.0
        for row in (cy - 2)..<(cy + 2) {
            let line = base.advanced(by: row * stride)
            for column in (cx - 2)..<(cx + 2) {
                if bytesPerSample == 2 {
                    sum += Double(line.load(fromByteOffset: column * 2, as: UInt16.self)) / 65535
                } else {
                    sum += Double(line.load(fromByteOffset: column, as: UInt8.self)) / 255
                }
            }
        }
        return sum / 16
    }

    private static func is16Bit(_ format: OSType) -> Bool {
        [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
         kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
         kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr10BiPlanarFullRange].contains(format)
    }
}
