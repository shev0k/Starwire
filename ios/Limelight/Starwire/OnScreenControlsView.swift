//
//  OnScreenControlsView.swift
//  Starwire
//
//  The on-screen controller: the buttons, d-pad and sticks drawn over the stream, and the editor
//  for moving and resizing them. The logic is in StarwireKit (Input/Controls: OnScreenLayout,
//  OnScreenEditor, OnScreenController), tested there; this file only draws it, turns UITouches
//  into its calls, runs its timer and passes what comes back to `send`.
//
//  Drawing and editing ideas from Starwire for Android's VirtualController (GPL-3.0; Moonlight
//  for Android, Karim Mreisi and contributors).
//
//  Touches that miss every control pass through to the view underneath (the stream view), because
//  `point(inside:with:)` is only true over a control, or anywhere while editing.
//

import StarwireKit
import UIKit

@objc(StarwireOnScreenControlsView)
final class OnScreenControlsView: UIView {
    private let send: (InputEvent) -> Void
    private let store = StarwireSettings.store

    private var layout: OnScreenLayout?
    private var controller: OnScreenController?
    private var editor: OnScreenEditor?
    private var builtSize = CGSize.zero
    private var opacityPercent = 90
    private var openingOpacity = 90

    private var touchIDs: [ObjectIdentifier: Int] = [:]
    private var nextTouchID = 1
    private var timer: Timer?
    private var drawAlpha: CGFloat = 1

    // Editing
    private var dragOrigin: CGPoint?
    private var pinchOrigin: CGPoint?
    private var pinchSize = CGSize.zero
    private var pinchActive = false
    private let toolbar = UIView()
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let opacitySlider = UISlider()
    private lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

    private static let handleRadius: CGFloat = 9
    private static let handleTouchRadius: CGFloat = 24

    /// True between `beginEditing` and `endEditing`. Nothing is sent to the PC meanwhile.
    @objc private(set) var isEditing = false
    /// Called after the editor is closed, by Done, Cancel or `endEditing`.
    @objc var onEditingFinished: (() -> Void)?

    init(frame: CGRect, send: @escaping (InputEvent) -> Void) {
        self.send = send
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isMultipleTouchEnabled = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        accessibilityIdentifier = "OnScreenControls"
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        setUpToolbar()
        setUpRecognizers()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        ensureBuilt()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Model

    private var screen: OnScreenSize {
        OnScreenSize(width: Double(bounds.width), height: Double(bounds.height))
    }

    private var activeLayout: OnScreenLayout? {
        editor?.layout ?? layout
    }

    /// Builds the layout and the controller once the view has a size, and again when the size
    /// changes (the frames are fractions of the screen, so they follow a rotation).
    private func ensureBuilt() {
        let size = bounds.size
        guard size.width > 0, size.height > 0, size != builtSize else { return }
        releaseTouches()
        builtSize = size
        if let current = editor {
            // Keep what is being edited. The undo steps are lost.
            let moved = OnScreenLayout(options: current.layout.options, screen: screen, saved: current.frames)
            editor = OnScreenEditor(layout: moved, screen: screen)
        } else {
            loadLayout()
        }
        refresh()
    }

    /// The layout the settings and the saved layout describe, with a controller for it.
    private func loadLayout() {
        guard builtSize.width > 0, builtSize.height > 0 else { return }
        let fresh = OnScreenLayout(store: store, screen: screen)
        layout = fresh
        opacityPercent = min(max(fresh.options.opacityPercent, 0), 100)
        controller = OnScreenController(layout: fresh, screen: screen)
    }

    private func refresh() {
        rebuildAccessibility()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureBuilt()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            releaseTouches()
            timer?.invalidate()
            timer = nil
        }
    }

    @objc private func appWillResign() {
        releaseTouches()
    }

    /// Lets go of every control that is held, so nothing stays pressed on the PC.
    private func releaseTouches() {
        timer?.invalidate()
        timer = nil
        if let controller {
            deliver(controller.cancelAll(now: ProcessInfo.processInfo.systemUptime))
        }
        touchIDs.removeAll()
        setNeedsDisplay()
    }

    private func deliver(_ events: [InputEvent]) {
        for event in events {
            send(event)
        }
    }

    /// The PC rumbled the on-screen controller: buzz the device if "vibrate" is on. iPads have no
    /// motor, so there it does nothing.
    @objc func hostRumbled() {
        guard layout?.options.vibrateOnHostRumble ?? false, !isEditing else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Hit testing

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, alpha > 0.01 else { return false }
        if isEditing {
            return bounds.contains(point)
        }
        return controlHit(at: point)
    }

    /// True over a visible control. A stick only takes a touch inside its circle, as the
    /// controller does, so a touch in its corner goes to the stream.
    private func controlHit(at point: CGPoint) -> Bool {
        guard let layout else { return false }
        let at = OnScreenPoint(x: Double(point.x), y: Double(point.y))
        for entry in layout.resolved(in: screen).reversed() where entry.rect.contains(at) {
            if case .stick = entry.element.kind {
                let frame = entry.rect.cgRect
                let radius = min(frame.width, frame.height) / 2
                if hypot(point.x - frame.midX, point.y - frame.midY) > radius {
                    continue
                }
            }
            return true
        }
        return false
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, controller != nil else { return }
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            let id = nextTouchID
            nextTouchID = nextTouchID % 0xFFFF + 1
            touchIDs[ObjectIdentifier(touch)] = id
            if !handle(touch, id: id, phase: .began) {
                touchIDs[ObjectIdentifier(touch)] = nil
            }
        }
        finishTouchEvent()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing else { return }
        for touch in touches {
            if let id = touchIDs[ObjectIdentifier(touch)] {
                handle(touch, id: id, phase: .moved)
            }
        }
        finishTouchEvent()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches, phase: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches, phase: .cancelled)
    }

    private func endTouches(_ touches: Set<UITouch>, phase: OnScreenTouchPhase) {
        guard !isEditing else { return }
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let id = touchIDs.removeValue(forKey: ObjectIdentifier(touch)) {
                handle(touch, id: id, phase: phase)
            }
        }
        finishTouchEvent()
    }

    /// Passes one touch to the controller. Returns true if a control has it.
    @discardableResult
    private func handle(_ touch: UITouch, id: Int, phase: OnScreenTouchPhase) -> Bool {
        guard let controller else { return false }
        let location = touch.location(in: self)
        let response = controller.touch(id: id, at: location.onScreen, phase: phase, now: touch.timestamp)
        deliver(response.events)
        return response.captured
    }

    private func finishTouchEvent() {
        setNeedsDisplay()
        scheduleTimer()
    }

    /// The controller's retransmit timer (only in the "like Android" mode; otherwise it has no
    /// deadline).
    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil
        guard let controller, let next = controller.nextDeadline else { return }
        let delay = max(next - ProcessInfo.processInfo.systemUptime, 0)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, let controller = self.controller else { return }
            self.deliver(controller.tick(now: ProcessInfo.processInfo.systemUptime))
            self.scheduleTimer()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Editing

    /// Opens the editor: every control gets a dashed outline, a drag moves it, a pinch or the
    /// corner handle resizes it.
    @objc func beginEditing() {
        guard !isEditing else { return }
        ensureBuilt()
        guard let layout else { return }
        releaseTouches()
        openingOpacity = opacityPercent
        editor = OnScreenEditor(layout: layout, screen: screen)
        isEditing = true
        opacitySlider.value = Float(opacityPercent)
        toolbar.isHidden = false
        panRecognizer.isEnabled = true
        pinchRecognizer.isEnabled = true
        refresh()
    }

    /// Closes the editor. With `save` the layout is saved; without it the saved layout comes back.
    @objc func endEditing(save: Bool) {
        guard isEditing else { return }
        if save, let editor {
            editor.save(to: OnScreenLayoutStore(store: store))
        } else if opacityPercent != openingOpacity {
            setOpacity(openingOpacity)
        }
        editor = nil
        dragOrigin = nil
        pinchOrigin = nil
        pinchActive = false
        isEditing = false
        toolbar.isHidden = true
        panRecognizer.isEnabled = false
        pinchRecognizer.isEnabled = false
        loadLayout()
        refresh()
        onEditingFinished?()
    }

    /// "Clear saved on-screen controls layout": forget the saved layout and use the defaults.
    /// While editing, the controls go back to the defaults, and Cancel can still take that back.
    @objc func resetLayout() {
        if isEditing {
            editor?.resetToDefaults()
        } else {
            OnScreenLayoutStore(store: store).reset()
            releaseTouches()
            loadLayout()
        }
        refresh()
    }

    private func setOpacity(_ percent: Int) {
        opacityPercent = min(max(percent, 0), 100)
        try? store.set(.int(opacityPercent), for: "seekbar_osc_opacity")
        setNeedsDisplay()
    }

    @objc private func doneTapped() { endEditing(save: true) }
    @objc private func cancelTapped() { endEditing(save: false) }
    @objc private func resetTapped() { resetLayout() }

    @objc private func opacityChanged() {
        setOpacity(Int(opacitySlider.value.rounded()))
    }

    private func setUpRecognizers() {
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.delegate = self
        pinchRecognizer.delegate = self
        panRecognizer.isEnabled = false
        pinchRecognizer.isEnabled = false
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
    }

    /// The control whose corner handle is under a point, topmost first.
    private func handleElement(at point: CGPoint) -> OnScreenElementID? {
        guard let entries = activeLayout?.resolved(in: screen) else { return nil }
        for entry in entries.reversed() {
            let frame = entry.rect.cgRect
            if hypot(point.x - frame.maxX, point.y - frame.maxY) <= Self.handleTouchRadius {
                return entry.element.id
            }
        }
        return nil
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEditing else { return }
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            let here = gesture.location(in: self)
            let start = CGPoint(x: here.x - translation.x, y: here.y - translation.y)
            beginEditDrag(at: start)
        case .changed:
            guard let origin = dragOrigin, !pinchActive else { return }
            editor?.drag(to: OnScreenPoint(x: Double(origin.x + translation.x), y: Double(origin.y + translation.y)))
            refresh()
        case .ended, .cancelled, .failed:
            editor?.endDrag()
            dragOrigin = nil
            refresh()
        default:
            break
        }
    }

    /// A finger went down at `start`: on a corner handle it resizes, anywhere else on a control
    /// it moves that control.
    private func beginEditDrag(at start: CGPoint) {
        guard !pinchActive else { return }
        if let id = handleElement(at: start), let rect = editor?.rect(of: id) {
            let inside = OnScreenPoint(x: rect.maxX - 1, y: rect.maxY - 1)
            if editor?.beginDrag(at: inside, mode: .resize) == id {
                dragOrigin = CGPoint(x: inside.x, y: inside.y)
                return
            }
            editor?.endDrag()
        }
        if editor?.beginDrag(at: start.onScreen, mode: .move) != nil {
            dragOrigin = start
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isEditing else { return }
        switch gesture.state {
        case .began:
            editor?.endDrag()
            dragOrigin = nil
            pinchActive = true
            pinchOrigin = nil
            var points = [gesture.location(in: self)]
            for index in 0..<gesture.numberOfTouches {
                points.insert(gesture.location(ofTouch: index, in: self), at: index)
            }
            for point in points {
                if let id = editor?.beginDrag(at: point.onScreen, mode: .resize), let rect = editor?.rect(of: id) {
                    pinchOrigin = point
                    pinchSize = CGSize(width: rect.width, height: rect.height)
                    break
                }
            }
        case .changed:
            guard let origin = pinchOrigin else { return }
            let growth = gesture.scale - 1
            editor?.drag(to: OnScreenPoint(x: Double(origin.x + growth * pinchSize.width),
                                           y: Double(origin.y + growth * pinchSize.height)))
            refresh()
        case .ended, .cancelled, .failed:
            editor?.endDrag()
            pinchOrigin = nil
            pinchActive = false
            refresh()
        default:
            break
        }
    }

    // MARK: - Toolbar

    private func setUpToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = UIColor(white: 0, alpha: 0.7)
        toolbar.layer.cornerRadius = 16
        toolbar.isHidden = true
        addSubview(toolbar)

        configure(cancelButton, title: "Cancel", symbol: "xmark", identifier: "OnScreenEditorCancel",
                  action: #selector(cancelTapped), prominent: false)
        configure(resetButton, title: "Reset", symbol: "arrow.counterclockwise", identifier: "OnScreenEditorReset",
                  action: #selector(resetTapped), prominent: false)
        configure(doneButton, title: "Done", symbol: "checkmark", identifier: "OnScreenEditorDone",
                  action: #selector(doneTapped), prominent: true)

        opacitySlider.minimumValue = 0
        opacitySlider.maximumValue = 100
        opacitySlider.minimumTrackTintColor = .white
        opacitySlider.accessibilityLabel = "On-screen controls opacity"
        opacitySlider.accessibilityIdentifier = "OnScreenEditorOpacity"
        opacitySlider.addTarget(self, action: #selector(opacityChanged), for: .valueChanged)
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "circle.lefthalf.filled"))
        icon.tintColor = .white
        icon.isAccessibilityElement = false

        let stack = UIStackView(arrangedSubviews: [cancelButton, resetButton, icon, opacitySlider, doneButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -6),
            opacitySlider.widthAnchor.constraint(equalToConstant: 120),
        ])
    }

    private func configure(_ button: UIButton, title: String, symbol: String, identifier: String, action: Selector,
                           prominent: Bool) {
        var configuration = prominent ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 4
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        if prominent {
            configuration.baseBackgroundColor = .systemBlue
        }
        button.configuration = configuration
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    // MARK: - Accessibility

    private static func name(of element: OnScreenElement) -> String {
        switch element.id {
        case .dpad: return "D-pad"
        case .leftStick: return "Left stick"
        case .rightStick: return "Right stick"
        case .leftTrigger: return "Left trigger"
        case .rightTrigger: return "Right trigger"
        case .leftBumper: return "Left bumper"
        case .rightBumper: return "Right bumper"
        case .back: return "Back button"
        case .start: return "Start button"
        case .guide: return "Guide button"
        case .leftStickButton: return "Left stick button"
        case .rightStickButton: return "Right stick button"
        case .a, .b, .x, .y: return "\(element.label) button"
        }
    }

    private func rebuildAccessibility() {
        var items: [Any] = []
        if let entries = activeLayout?.resolved(in: screen) {
            for entry in entries {
                let item = UIAccessibilityElement(accessibilityContainer: self)
                item.accessibilityLabel = Self.name(of: entry.element)
                item.accessibilityIdentifier = "OnScreenControl-\(entry.element.id)"
                item.accessibilityTraits = .button
                item.accessibilityFrameInContainerSpace = entry.rect.cgRect
                if isEditing {
                    item.accessibilityHint = "Drag to move. Pinch to resize."
                }
                items.append(item)
            }
        }
        if isEditing {
            items.append(contentsOf: [cancelButton, resetButton, opacitySlider, doneButton])
        }
        accessibilityElements = items
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let entries = activeLayout?.resolved(in: screen) else { return }
        let state = isEditing ? ControllerState() : (controller?.state ?? ControllerState())
        // The opacity is baked into the colours: UIBezierPath's fill and stroke would override a
        // context-wide alpha
        let alpha = CGFloat(opacityPercent) / 100
        drawAlpha = isEditing ? max(alpha, 0.35) : alpha
        let lineWidth = max(1.5, bounds.height * 0.004)

        for entry in entries {
            let frame = entry.rect.cgRect
            guard frame.width > 0, frame.height > 0 else { continue }
            switch entry.element.kind {
            case .button:
                drawPill(context, frame, entry.element.label, pressed: state.buttons & entry.element.flag != 0, lineWidth)
            case .trigger(let left):
                drawPill(context, frame, entry.element.label, pressed: (left ? state.leftTrigger : state.rightTrigger) > 0,
                         lineWidth)
            case .dpad:
                drawDpad(context, frame, buttons: state.buttons, lineWidth)
            case .stick(let left):
                let x = left ? state.leftX : state.rightX
                let y = left ? state.leftY : state.rightY
                let click = state.buttons & (left ? GamepadButton.leftStick : GamepadButton.rightStick) != 0
                drawStick(context, frame, x: x, y: y, clicked: click, lineWidth)
            }
        }

        if isEditing {
            for entry in entries {
                drawEditMarks(context, entry.rect.cgRect)
            }
        }
    }

    private func drawPill(_ context: CGContext, _ frame: CGRect, _ label: String, pressed: Bool, _ lineWidth: CGFloat) {
        let body = frame.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = UIBezierPath(roundedRect: body, cornerRadius: min(body.width, body.height) / 2)
        fill(path, pressed: pressed)
        stroke(path, lineWidth)
        drawLabel(label, in: body)
    }

    private func drawDpad(_ context: CGContext, _ frame: CGRect, buttons: Int, _ lineWidth: CGFloat) {
        let body = frame.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let w = body.width / 3
        let h = body.height / 3
        let x0 = body.minX, x1 = x0 + w, x2 = x1 + w, x3 = body.maxX
        let y0 = body.minY, y1 = y0 + h, y2 = y1 + h, y3 = body.maxY
        let cross = UIBezierPath()
        cross.move(to: CGPoint(x: x1, y: y0))
        for point in [(x2, y0), (x2, y1), (x3, y1), (x3, y2), (x2, y2), (x2, y3), (x1, y3), (x1, y2), (x0, y2), (x0, y1), (x1, y1)] {
            cross.addLine(to: CGPoint(x: point.0, y: point.1))
        }
        cross.close()
        cross.lineJoinStyle = .round
        fill(cross, pressed: false)

        let arms: [(flag: Int, rect: CGRect)] = [
            (GamepadButton.up, CGRect(x: x1, y: y0, width: w, height: h)),
            (GamepadButton.down, CGRect(x: x1, y: y2, width: w, height: h)),
            (GamepadButton.left, CGRect(x: x0, y: y1, width: w, height: h)),
            (GamepadButton.right, CGRect(x: x2, y: y1, width: w, height: h)),
        ]
        for arm in arms where buttons & arm.flag != 0 {
            tint(1, 0.45).setFill()
            UIBezierPath(rect: arm.rect).fill()
        }
        stroke(cross, lineWidth)
    }

    private func drawStick(_ context: CGContext, _ frame: CGRect, x: Int, y: Int, clicked: Bool, _ lineWidth: CGFloat) {
        let side = min(frame.width, frame.height)
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let half = side / 2
        let base = UIBezierPath(ovalIn: CGRect(x: centre.x - half + lineWidth / 2, y: centre.y - half + lineWidth / 2,
                                               width: side - lineWidth, height: side - lineWidth))
        fill(base, pressed: false)
        stroke(base, lineWidth)

        // The controller's thumb: a fifth of the radius, and it can travel to the edge less the thumb
        let thumbRadius = half * 0.2
        let reach = max(half - lineWidth * 2 - thumbRadius, 0)
        let scale = CGFloat(GamepadMath.stickScale)
        let dx = max(-1, min(1, CGFloat(x) / scale))
        let dy = max(-1, min(1, CGFloat(y) / scale))
        let thumbCentre = CGPoint(x: centre.x + dx * reach, y: centre.y - dy * reach)
        let thumb = UIBezierPath(ovalIn: CGRect(x: thumbCentre.x - thumbRadius, y: thumbCentre.y - thumbRadius,
                                                width: thumbRadius * 2, height: thumbRadius * 2))
        tint(1, (x != 0 || y != 0 || clicked) ? 0.6 : 0.3).setFill()
        thumb.fill()
        stroke(thumb, lineWidth)
    }

    private func fill(_ path: UIBezierPath, pressed: Bool) {
        (pressed ? tint(1, 0.5) : tint(0, 0.4)).setFill()
        path.fill()
    }

    private func stroke(_ path: UIBezierPath, _ lineWidth: CGFloat) {
        tint(1, 1).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    /// A grey with the controls' opacity applied.
    private func tint(_ white: CGFloat, _ alpha: CGFloat) -> UIColor {
        UIColor(white: white, alpha: alpha * drawAlpha)
    }

    private func drawLabel(_ text: String, in rect: CGRect) {
        guard !text.isEmpty else { return }
        func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
            [.font: UIFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: tint(1, 1)]
        }
        let string = text as NSString
        var size = min(rect.height * 0.4, 24)
        var measured = string.size(withAttributes: attributes(size))
        let limit = rect.width * 0.84
        if measured.width > limit, measured.width > 0 {
            size *= limit / measured.width
            measured = string.size(withAttributes: attributes(size))
        }
        guard size >= 5 else { return }
        string.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2),
                    withAttributes: attributes(size))
    }

    /// The dashed outline and the resize handle on the bottom right corner.
    private func drawEditMarks(_ context: CGContext, _ frame: CGRect) {
        context.saveGState()
        let outline = UIBezierPath(rect: frame)
        outline.lineWidth = 1.5
        outline.setLineDash([6, 4], count: 2, phase: 0)
        UIColor.white.setStroke()
        outline.stroke()
        context.restoreGState()

        let radius = Self.handleRadius
        let handle = UIBezierPath(ovalIn: CGRect(x: frame.maxX - radius, y: frame.maxY - radius,
                                                 width: radius * 2, height: radius * 2))
        UIColor.white.setFill()
        handle.fill()
        UIColor.black.setStroke()
        handle.lineWidth = 1
        handle.stroke()
    }
}

extension OnScreenControlsView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view?.isDescendant(of: toolbar) != true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

private extension OnScreenRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

private extension CGPoint {
    var onScreen: OnScreenPoint { OnScreenPoint(x: Double(x), y: Double(y)) }
}
