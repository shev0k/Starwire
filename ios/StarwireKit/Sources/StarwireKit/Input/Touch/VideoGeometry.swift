import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where the stream's picture is on the screen, and how screen points map to the PC's pixels.
/// Every input path (touch, Pencil, mouse, pointer lock) uses this one function, so they agree
/// with each other and with what the video layer shows.
///
/// The picture is fitted into the view keeping its aspect ratio (as `resizeAspect` does), or
/// stretched to fill it, then zoomed about the view's centre and panned (pinch to zoom and pan
/// and zoom mode).
public struct VideoGeometry: Equatable, Sendable {
    /// The view the picture is drawn in, in points.
    public var viewSize: CGSize
    /// The stream's resolution, in pixels.
    public var streamSize: CGSize
    public var stretch: Bool
    /// 1 shows the whole picture; 2 shows it twice as large.
    public var zoom: CGFloat
    /// How far the zoomed picture is moved, in view points.
    public var pan: CGPoint

    public init(viewSize: CGSize, streamSize: CGSize, stretch: Bool = false, zoom: CGFloat = 1, pan: CGPoint = .zero) {
        self.viewSize = viewSize
        self.streamSize = streamSize
        self.stretch = stretch
        self.zoom = zoom
        self.pan = pan
    }

    /// The picture's rectangle before zoom and pan.
    public var fittedRect: CGRect {
        guard viewSize.width > 0, viewSize.height > 0, streamSize.width > 0, streamSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        if stretch {
            return CGRect(origin: .zero, size: viewSize)
        }
        let aspect = streamSize.width / streamSize.height
        let size: CGSize
        if viewSize.width > viewSize.height * aspect {
            size = CGSize(width: viewSize.height * aspect, height: viewSize.height)
        } else {
            size = CGSize(width: viewSize.width, height: viewSize.width / aspect)
        }
        return CGRect(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The picture's rectangle on screen, after zoom and pan.
    public var videoRect: CGRect {
        let fitted = fittedRect
        let centre = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        return CGRect(x: centre.x + (fitted.minX - centre.x) * zoom + pan.x,
                      y: centre.y + (fitted.minY - centre.y) * zoom + pan.y,
                      width: fitted.width * zoom, height: fitted.height * zoom)
    }

    /// A view point as a fraction of the picture, from 0 to 1 on each side. Points outside the
    /// picture are clamped to its edge, so a drag that leaves it still reaches the edge (for
    /// Aero Snap and the like).
    public func normalized(_ point: CGPoint) -> CGPoint {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: min(max((point.x - rect.minX) / rect.width, 0), 1),
                       y: min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    /// A view point in the stream's pixels, clamped to the picture.
    public func streamPoint(_ point: CGPoint) -> (x: Int, y: Int) {
        let n = normalized(point)
        let width = max(Int(streamSize.width), 1)
        let height = max(Int(streamSize.height), 1)
        return (min(Int((n.x * CGFloat(width)).rounded(.down)), width - 1),
                min(Int((n.y * CGFloat(height)).rounded(.down)), height - 1))
    }

    /// An absolute mouse position for this view point (`LiSendMousePositionEvent`).
    public func mousePosition(_ point: CGPoint) -> InputEvent {
        let p = streamPoint(point)
        return .mousePosition(x: p.x, y: p.y, width: Int(streamSize.width), height: Int(streamSize.height))
    }

    public func contains(_ point: CGPoint) -> Bool {
        videoRect.contains(point)
    }

    /// Stream pixels per view point, for turning finger movement into mouse movement.
    public var pixelsPerPoint: CGFloat {
        let rect = videoRect
        guard rect.width > 0 else { return 1 }
        return streamSize.width / rect.width
    }

    /// Keeps the zoomed picture covering the view: no zoom below 1, and no pan that shows an
    /// edge of the view beyond the picture's edge.
    public func clamped(maxZoom: CGFloat = 4) -> VideoGeometry {
        var copy = self
        copy.zoom = min(max(zoom, 1), maxZoom)
        let fitted = copy.fittedRect
        // How far the zoomed picture may move before an edge comes in
        let spareX = max((fitted.width * copy.zoom - viewSize.width) / 2, 0)
        let spareY = max((fitted.height * copy.zoom - viewSize.height) / 2, 0)
        copy.pan = CGPoint(x: min(max(pan.x, -spareX), spareX), y: min(max(pan.y, -spareY), spareY))
        return copy
    }
}

/// Keeps the fractions of a pixel that integer mouse moves would lose, so slow finger movement
/// still moves the cursor and nothing drifts. One per input source.
public struct MouseAccumulator: Equatable, Sendable {
    private var x: Double = 0
    private var y: Double = 0

    public init() {}

    /// Adds a movement and returns the whole pixels to send now (nil when there are none).
    public mutating func add(dx: Double, dy: Double) -> InputEvent? {
        x += dx
        y += dy
        let wholeX = x.rounded(.towardZero)
        let wholeY = y.rounded(.towardZero)
        x -= wholeX
        y -= wholeY
        guard wholeX != 0 || wholeY != 0 else { return nil }
        return .mouseMove(dx: Int(wholeX), dy: Int(wholeY))
    }

    public mutating func reset() {
        x = 0
        y = 0
    }

    /// The fraction kept for the next movement.
    public var remainder: (x: Double, y: Double) { (x, y) }
}
