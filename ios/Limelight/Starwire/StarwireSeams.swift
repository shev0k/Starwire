//
//  StarwireSeams.swift
//  Starwire
//
//  The real versions of StarwireKit's seams, over the ObjC core (StarwireCoreFacade). The fakes
//  and the demo mode are in StarwireKit. HostService's real version is StarwireKit's
//  VibeshineClient over PinnedHostTransport, and Clock's is SystemClock.
//

import AVFoundation
import CoreMedia
import Foundation
import StarwireKit
import UIKit

/// Pairing through moonlight-ios's PairManager.
final class LivePairingService: PairingService {
    let httpsPort: UInt16

    init(httpsPort: UInt16 = 47984) {
        self.httpsPort = httpsPort
    }

    func pair(address: String, showPIN: @escaping (String) -> Void) async throws -> PairingResult {
        try await withCheckedThrowingContinuation { continuation in
            StarwirePairingFacade.pair(withAddress: address, httpsPort: httpsPort, showPIN: showPIN) { certificate, alreadyPaired, error in
                if let certificate {
                    continuation.resume(returning: .paired(serverCertificate: certificate))
                } else if alreadyPaired {
                    continuation.resume(returning: .alreadyPaired)
                } else {
                    continuation.resume(throwing: PairingError.failed(error ?? "Pairing failed"))
                }
            }
        }
    }
}

/// A stream through moonlight-ios's StreamManager, into `renderView`. `configuration` is the
/// StreamConfiguration the app built for it.
final class LiveStreamSession: StreamSession {
    private(set) var state: StreamState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((StreamState) -> Void)?
    private let facade: StarwireStreamFacade

    init(configuration: NSObject, renderView: UIView) {
        facade = StarwireStreamFacade(configuration: configuration, renderView: renderView)
        facade.onStage = { [weak self] stage in self?.state = .starting(stage: stage) }
        facade.onStarted = { [weak self] in self?.state = .streaming }
        facade.onEnded = { [weak self] error in self?.state = .ended(error: error) }
    }

    func start() {
        guard state == .idle || state.isEnded else { return }
        state = .starting(stage: "launch")
        facade.start()
    }

    func stop() {
        facade.stop()
        if !state.isEnded {
            state = .ended(error: nil)
        }
    }
}

/// Input to the PC through moonlight-common-c: each InputEvent is one library call.
final class LiveInputSink: InputSink {
    func send(_ event: InputEvent) {
        switch event {
        case .mouseMove(let dx, let dy):
            StarwireInputFacade.mouseMoveX(Int16(clamping: dx), y: Int16(clamping: dy))
        case .mousePosition(let x, let y, let width, let height):
            StarwireInputFacade.mousePositionX(Int16(clamping: x), y: Int16(clamping: y), width: Int16(clamping: width),
                                               height: Int16(clamping: height))
        case .mouseMoveAsPosition(let dx, let dy, let width, let height):
            StarwireInputFacade.mouseMoveAsPositionX(Int16(clamping: dx), y: Int16(clamping: dy), width: Int16(clamping: width),
                                                     height: Int16(clamping: height))
        case .mouseButton(let button, let down):
            StarwireInputFacade.mouseButton(Int32(button), down: down)
        case .scroll(let amount):
            StarwireInputFacade.scroll(Int16(clamping: amount))
        case .hScroll(let amount):
            StarwireInputFacade.hScroll(Int16(clamping: amount))
        case .key(let code, let down, let modifiers, let flags):
            StarwireInputFacade.key(Int16(clamping: code), down: down, modifiers: CChar(truncatingIfNeeded: modifiers),
                                    flags: CChar(truncatingIfNeeded: flags))
        case .text(let text):
            StarwireInputFacade.text(text)
        case .touch(let id, let phase, let x, let y, let pressure, let major, let minor, let rotation):
            StarwireInputFacade.touchType(UInt8(phase.rawValue), pointerID: UInt32(truncatingIfNeeded: id), x: Float(x), y: Float(y),
                                          pressure: Float(pressure), contactMajor: Float(major), contactMinor: Float(minor),
                                          rotation: UInt16(truncatingIfNeeded: rotation))
        case .pen(let phase, let tool, let buttons, let x, let y, let pressure, let rotation, let tilt):
            StarwireInputFacade.penType(UInt8(phase.rawValue), tool: UInt8(tool.rawValue), buttons: UInt8(truncatingIfNeeded: buttons),
                                        x: Float(x), y: Float(y), pressure: Float(pressure),
                                        rotation: UInt16(truncatingIfNeeded: rotation), tilt: UInt8(truncatingIfNeeded: tilt))
        case .controller(let state):
            StarwireInputFacade.controller(Int16(truncatingIfNeeded: state.number), activeMask: Int16(truncatingIfNeeded: state.activeMask),
                                           buttons: Int32(truncatingIfNeeded: state.buttons),
                                           leftTrigger: UInt8(clamping: state.leftTrigger), rightTrigger: UInt8(clamping: state.rightTrigger),
                                           leftX: Int16(clamping: state.leftX), leftY: Int16(clamping: state.leftY),
                                           rightX: Int16(clamping: state.rightX), rightY: Int16(clamping: state.rightY))
        case .controllerArrival(let number, let mask, let type, let buttons, let capabilities):
            StarwireInputFacade.controllerArrival(UInt8(truncatingIfNeeded: number), activeMask: UInt16(truncatingIfNeeded: mask),
                                                  type: UInt8(type.rawValue), buttons: UInt32(truncatingIfNeeded: buttons),
                                                  capabilities: UInt16(truncatingIfNeeded: capabilities))
        case .controllerMotion(let number, let sensor, let x, let y, let z):
            StarwireInputFacade.controllerMotion(UInt8(truncatingIfNeeded: number), sensor: UInt8(sensor.rawValue), x: x, y: y, z: z)
        case .controllerBattery(let number, let state, let percent):
            StarwireInputFacade.controllerBattery(UInt8(truncatingIfNeeded: number), state: UInt8(state.rawValue),
                                                  percent: UInt8(clamping: percent))
        case .controllerTouch(let number, let phase, let id, let x, let y, let pressure):
            StarwireInputFacade.controllerTouch(UInt8(truncatingIfNeeded: number), type: UInt8(phase.rawValue),
                                                pointerID: UInt32(truncatingIfNeeded: id), x: Float(x), y: Float(y), pressure: Float(pressure))
        }
    }
}

/// Frames on a system video layer (AVSampleBufferDisplayLayer), as the system presenter shows
/// streams. Decoded frames come as CMSampleBuffers in `payload`; generated ones as BGRA.
final class SampleBufferVideoSink: VideoSink {
    let layer: AVSampleBufferDisplayLayer

    init(layer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()) {
        self.layer = layer
        layer.videoGravity = .resizeAspect
    }

    func display(_ frame: VideoFrame) {
        let sample: CMSampleBuffer?
        if let payload = frame.payload, CFGetTypeID(payload) == CMSampleBufferGetTypeID() {
            sample = (payload as! CMSampleBuffer)
        } else if let bgra = frame.bgra {
            sample = Self.sampleBuffer(bgra: bgra, width: frame.width, height: frame.height)
        } else {
            sample = nil
        }
        guard let sample else { return }
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sample)
    }

    func flush() {
        layer.flushAndRemoveImage()
    }

    /// A sample buffer shown as soon as it's enqueued.
    static func sampleBuffer(bgra: [UInt8], width: Int, height: Int) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            bgra.withUnsafeBytes { source in
                for row in 0..<height {
                    memcpy(base + row * rowBytes, source.baseAddress! + row * width * 4, width * 4)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        if let sample, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
