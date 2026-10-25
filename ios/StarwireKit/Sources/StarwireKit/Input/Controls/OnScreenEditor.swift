import Foundation

// Ported from Starwire for Android's VirtualControllerElement.java (moveElement, resizeElement) and
// VirtualController.java (the Move and Resize modes) (GPL-3.0; Moonlight for Android, Karim
// Mreisi and contributors).
//
// Android's editing, as it is:
//   - Move: the control follows the finger. Its left and top edges stop at 0. Nothing stops its
//     right and bottom edges, so a control can be dragged off the screen. This port keeps the
//     whole control on the screen.
//   - Resize: the bottom right corner follows the finger, the top left corner stays put. The
//     width and the height change on their own (the shape is not kept) and neither goes under
//     20 pixels. Nothing limits the other end. This port also keeps the control on the screen.
//   - There is no snapping to a grid and no undo. Undo here is new.
//   - The edit is saved when the player leaves Resize mode.

/// Moves and resizes the controls and keeps the result.
public struct OnScreenEditor {
    public enum Mode: Equatable, Sendable {
        case move
        case resize
    }

    /// Android's smallest width or height (`resizeElement`: 20). It is in pixels on Android and
    /// in points here.
    public static let minimumSize: Double = 20

    public let screen: OnScreenSize
    public private(set) var layout: OnScreenLayout

    private var undoStack: [[OnScreenElementID: OnScreenFrame]] = []
    private var activeDrag: Drag?

    private struct Drag {
        var id: OnScreenElementID
        var mode: Mode
        var start: OnScreenPoint
        var startRect: OnScreenRect
        var before: [OnScreenElementID: OnScreenFrame]
    }

    public init(layout: OnScreenLayout, screen: OnScreenSize) {
        self.layout = layout
        self.screen = screen
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    /// The frames to save.
    public var frames: [OnScreenElementID: OnScreenFrame] { layout.frames }

    public func rect(of id: OnScreenElementID) -> OnScreenRect? {
        layout.rect(of: id, in: screen)
    }

    /// The control on top at a point, or nil. In editing every control takes touches over its
    /// whole rectangle, the sticks too.
    public func hitTest(_ point: OnScreenPoint) -> OnScreenElementID? {
        for entry in layout.resolved(in: screen).reversed() where entry.rect.contains(point) {
            return entry.element.id
        }
        return nil
    }

    // MARK: - A drag

    /// A finger goes down. Returns the control it picked up, or nil if it missed them all.
    @discardableResult
    public mutating func beginDrag(at point: OnScreenPoint, mode: Mode) -> OnScreenElementID? {
        guard let id = hitTest(point), let rect = rect(of: id) else { return nil }
        activeDrag = Drag(id: id, mode: mode, start: point, startRect: rect, before: layout.frames)
        return id
    }

    /// The finger moves. The control is placed from where the drag began, so it doesn't drift.
    public mutating func drag(to point: OnScreenPoint) {
        guard let drag = activeDrag else { return }
        let dx = point.x - drag.start.x
        let dy = point.y - drag.start.y
        apply(drag.mode, to: drag.id, from: drag.startRect, dx: dx, dy: dy)
    }

    /// The finger lifts. A drag that changed something is one step of undo.
    public mutating func endDrag() {
        guard let drag = activeDrag else { return }
        activeDrag = nil
        if layout.frames != drag.before {
            undoStack.append(drag.before)
        }
    }

    // MARK: - One step

    /// Moves a control by a distance, in points, and keeps it on the screen.
    public mutating func move(_ id: OnScreenElementID, dx: Double, dy: Double) {
        step(id, mode: .move, dx: dx, dy: dy)
    }

    /// Grows (or shrinks) a control's bottom right corner by a distance, in points. Width and
    /// height change on their own. Neither goes under `minimumSize`, and the control stays on
    /// the screen.
    public mutating func resize(_ id: OnScreenElementID, dx: Double, dy: Double) {
        step(id, mode: .resize, dx: dx, dy: dy)
    }

    private mutating func step(_ id: OnScreenElementID, mode: Mode, dx: Double, dy: Double) {
        guard let rect = rect(of: id) else { return }
        let before = layout.frames
        apply(mode, to: id, from: rect, dx: dx, dy: dy)
        if layout.frames != before {
            undoStack.append(before)
        }
    }

    private mutating func apply(_ mode: Mode, to id: OnScreenElementID, from start: OnScreenRect, dx: Double, dy: Double) {
        var rect = start
        switch mode {
        case .move:
            rect.x = Self.clamp(start.x + dx, low: 0, high: screen.width - start.width)
            rect.y = Self.clamp(start.y + dy, low: 0, high: screen.height - start.height)
        case .resize:
            rect.width = Self.clamp(start.width + dx, low: Self.minimumSize, high: screen.width - start.x)
            rect.height = Self.clamp(start.height + dy, low: Self.minimumSize, high: screen.height - start.y)
        }
        layout.frames[id] = OnScreenFrame(rect: rect, in: screen)
    }

    /// Clamps to a range; when the room is smaller than the low end, the low end wins.
    private static func clamp(_ value: Double, low: Double, high: Double) -> Double {
        max(low, min(value, high))
    }

    // MARK: - Undo and reset

    /// Takes back the last change. Returns false if there is nothing to take back.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        layout.frames = previous
        return true
    }

    /// Puts every control back where Android's default layout has it (the saved layout is not
    /// touched until `save`). This is one step of undo.
    public mutating func resetToDefaults() {
        let defaults = OnScreenLayout.defaultFrames(options: layout.options, screen: screen)
        var frames = layout.frames
        for element in layout.elements {
            frames[element.id] = defaults[element.id]
        }
        if frames != layout.frames {
            undoStack.append(layout.frames)
            layout.frames = frames
        }
    }

    /// Saves the layout the way Android does when the player leaves Resize mode: every control
    /// shown, with the frame it has now.
    public func save(to layoutStore: OnScreenLayoutStore) {
        var shown: [OnScreenElementID: OnScreenFrame] = [:]
        for element in layout.elements {
            shown[element.id] = layout.frames[element.id]
        }
        layoutStore.save(shown)
    }
}
