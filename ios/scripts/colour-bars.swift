import Foundation
import CoreGraphics
import ImageIO
// Samples ten bars along the long side of a screenshot, at three places across the short side,
// in sRGB, and prints the median of each bar
for path in CommandLine.arguments.dropFirst() {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let long = max(w, h), short = min(w, h)
    var out = [String]()
    for bar in 0..<10 {
        let l = Int((Double(bar) + 0.5) / 10 * Double(long))
        var samples = [[Int]]()
        for f in [0.45, 0.55, 0.65] {
            let s = Int(f * Double(short))
            let (x, y) = h > w ? (s, l) : (l, s)
            let i = (y * w + x) * 4
            samples.append([Int(px[i]), Int(px[i+1]), Int(px[i+2])])
        }
        let m = samples.sorted { $0[0] + $0[1] + $0[2] < $1[0] + $1[1] + $1[2] }[1]
        out.append("\(m[0]),\(m[1]),\(m[2])")
    }
    print((path as NSString).lastPathComponent.prefix(12), out.joined(separator: "  "))
}
