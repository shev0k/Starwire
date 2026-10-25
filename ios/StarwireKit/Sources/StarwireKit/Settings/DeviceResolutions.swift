import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// The stream sizes that match this device's own screen, for the resolution list: the whole
// screen, and the part inside the safe area (clear of the home indicator, the camera housing and
// rounded corners). The old moonlight-ios settings screen had both; VoidLink offers the same pair.
// They are saved as plain "WxH", like any other resolution, so a settings file still reads on
// Android.
public enum DeviceResolutions {
    public struct Choices: Equatable, Sendable {
        public var fullScreen: String
        public var safeArea: String
    }

    /// Landscape sizes in pixels, rounded down to even numbers (video encoders want even sizes).
    /// `screen` and `insets` are in points, as the device is held; `scale` is pixels per point.
    public static func choices(screen: CGSize, insets: (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat),
                               scale: CGFloat) -> Choices {
        func size(_ width: CGFloat, _ height: CGFloat) -> String {
            let w = Int((width * scale).rounded(.down)) / 2 * 2
            let h = Int((height * scale).rounded(.down)) / 2 * 2
            return "\(max(w, h))x\(min(w, h))"
        }
        return Choices(fullScreen: size(screen.width, screen.height),
                       safeArea: size(screen.width - insets.left - insets.right, screen.height - insets.top - insets.bottom))
    }
}
