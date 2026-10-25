//
//  CoverPalette+UIImage.swift
//  Starwire
//
//  Takes a cover's colours from a UIImage: draws it into a 24 by 32 RGBA8 buffer, as Starwire for
//  Android's CoverGlow.tintFromBitmap scales a cover down first (GPL-3.0), and hands the bytes to
//  StarwireKit's CoverPalette. A picture that can't be read gives the fallback violet, since the
//  colour is decoration and must never stop a cover from showing.
//

import CoreGraphics
import StarwireKit
import UIKit

extension CoverPalette {
    static func from(image: UIImage) -> CoverPalette {
        let width = CoverPalette.sampleWidth
        let height = CoverPalette.sampleHeight
        guard let cgImage = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              // Opaque, red then green then blue then an unused byte: no premultiplied colours
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data
        else {
            return .fallback
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        return CoverPalette.from(width: width, height: height, rgba: bytes)
    }
}
