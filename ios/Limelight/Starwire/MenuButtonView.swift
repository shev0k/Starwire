//
//  MenuButtonView.swift
//  Starwire
//
//  The stream menu's floating button (batch 4.5): a frosted round button with Starwire's rainbow
//  as a thin ring, that opens and closes the menu and can be dragged anywhere. It can also sit on
//  the left or right edge as a slim tab: always (the edge style), when dropped close to a side,
//  or by itself after a while untouched. Tapping the tab opens the menu. Its spot is saved per
//  orientation as a fraction of the room it can move in, as Android's FloatingButton does; the
//  size, opacity and docking come from StarwireKit's MenuButtonOptions.
//

import StarwireKit
import UIKit

final class FloatingMenuButton: UIView {
    var onTap: () -> Void = {}

    private var options: MenuButtonOptions
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let tint = UIView()
    private let ring = CAGradientLayer()
    private let ringMask = CAShapeLayer()
    private let icon = UIImageView()
    private var dockedEdge: MenuButtonDock.Edge?
    private var downPoint: CGPoint = .zero
    private var downCentre: CGPoint = .zero
    private var dragging = false
    private var idleTimer: Timer?
    private let defaults = UserDefaults(suiteName: StarwireSettings.suiteName) ?? .standard
    static let dockKey = "floating_button_dock"

    init(options: MenuButtonOptions = MenuButtonOptions(store: StarwireSettings.store)) {
        self.options = options
        let size = options.size.points
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        blur.isUserInteractionEnabled = false
        blur.clipsToBounds = true
        addSubview(blur)
        tint.backgroundColor = UIColor(red: 0x1A / 255, green: 0x12 / 255, blue: 0x38 / 255, alpha: 0.55)
        tint.isUserInteractionEnabled = false
        blur.contentView.addSubview(tint)
        // The rainbow from the wordmark, as a ring
        ring.type = .conic
        ring.colors = RainbowPalette.stops.map { UIColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1).cgColor }
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ringMask.fillColor = UIColor.clear.cgColor
        ringMask.strokeColor = UIColor.white.cgColor
        ring.mask = ringMask
        layer.addSublayer(ring)
        icon.tintColor = .white
        icon.contentMode = .center
        addSubview(icon)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
        alpha = options.idleOpacity
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Menu"
        accessibilityIdentifier = "StreamMenuButton"
        if options.style == .edge, let saved = defaults.string(forKey: Self.dockKey), let edge = MenuButtonDock.Edge(rawValue: saved) {
            dockedEdge = edge
        } else if options.style == .edge {
            dockedEdge = .right
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        idleTimer?.invalidate()
    }

    var isDocked: Bool { dockedEdge != nil }

    /// New options during a stream (the menu's More settings)
    func apply(_ newOptions: MenuButtonOptions) {
        options = newOptions
        if options.style == .edge && dockedEdge == nil {
            dockedEdge = .right
        } else if options.style == .floating && dockedEdge != nil && options.autoHide == nil {
            dockedEdge = nil
            defaults.removeObject(forKey: Self.dockKey)
        }
        let size = options.size.points
        bounds.size = isDocked ? CGSize(width: MenuButtonDock.tabWidth, height: MenuButtonDock.tabHeight) : CGSize(width: size, height: size)
        restyle()
        alpha = restingAlpha
        scheduleAutoHide()
    }

    // MARK: Look

    private func restyle() {
        let docked = dockedEdge != nil
        let corner = docked ? MenuButtonDock.tabWidth / 2 : bounds.width / 2
        blur.frame = bounds
        blur.layer.cornerRadius = corner
        tint.frame = blur.bounds
        ring.frame = bounds
        ringMask.frame = bounds
        ringMask.lineWidth = docked ? 1.5 : 2
        ringMask.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: max(corner - 1, 0)).cgPath
        let symbol = docked ? (dockedEdge == .left ? "chevron.compact.right" : "chevron.compact.left") : "line.3.horizontal"
        let points = docked ? 13 : options.size.points * 0.38
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: points, weight: .bold))
        icon.frame = bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: corner).cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        restyle()
    }

    // MARK: Place

    /// Moves to the saved spot for the screen's orientation.
    func place(in screen: CGSize) {
        guard !dragging else { return }
        let keys = FloatingButtonPlacement.keys(portrait: FloatingButtonPlacement.isPortrait(screen))
        var fraction: CGPoint?
        if defaults.object(forKey: keys.x) != nil, defaults.object(forKey: keys.y) != nil {
            fraction = CGPoint(x: defaults.double(forKey: keys.x), y: defaults.double(forKey: keys.y))
        }
        let size = options.size.points
        let room = CGSize(width: max(screen.width - size, 0), height: max(screen.height - size, 0))
        var origin = FloatingButtonPlacement.defaultOrigin
        if let fraction, fraction.x.isFinite, fraction.y.isFinite {
            origin = CGPoint(x: min(max(fraction.x, 0), 1) * room.width, y: min(max(fraction.y, 0), 1) * room.height)
        }
        let button = CGRect(origin: origin, size: CGSize(width: size, height: size))
        if let edge = dockedEdge {
            frame = tabFrame(edge: edge, centreY: button.midY, screen: screen)
        } else {
            frame = button
        }
        alpha = restingAlpha
        scheduleAutoHide()
    }

    /// Back to its opacity at rest (after the menu hid it)
    func restoreRestingAlpha() {
        UIView.animate(withDuration: 0.3) { self.alpha = self.restingAlpha }
    }

    private var restingAlpha: CGFloat {
        isDocked ? options.idleOpacity * MenuButtonDock.tabOpacityFactor : options.idleOpacity
    }

    private func tabFrame(edge: MenuButtonDock.Edge, centreY: CGFloat, screen: CGSize) -> CGRect {
        let insets = superview?.safeAreaInsets ?? .zero
        return MenuButtonDock.tabFrame(edge: edge, centreY: centreY, screen: screen, top: insets.top, bottom: insets.bottom)
    }

    private func dock(to edge: MenuButtonDock.Edge, animated: Bool) {
        guard let parent = superview else { return }
        dockedEdge = edge
        defaults.set(edge.rawValue, forKey: Self.dockKey)
        let target = tabFrame(edge: edge, centreY: frame.midY, screen: parent.bounds.size)
        let change = {
            self.frame = target
            self.alpha = self.restingAlpha
            self.restyle()
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: change)
        } else {
            change()
        }
        accessibilityHint = "Docked to the side"
    }

    private func undock(animated: Bool) {
        guard let parent = superview, let edge = dockedEdge else { return }
        dockedEdge = nil
        defaults.removeObject(forKey: Self.dockKey)
        let target = MenuButtonDock.buttonFrame(fromTab: frame, edge: edge, size: options.size.points, screen: parent.bounds.size)
        let change = {
            self.frame = target
            self.restyle()
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: change)
        } else {
            change()
        }
        accessibilityHint = nil
    }

    private func scheduleAutoHide() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard !isDocked, let seconds = options.autoHide, superview != nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, let parent = self.superview, !self.dragging else { return }
            self.dock(to: MenuButtonDock.nearestEdge(buttonFrame: self.frame, screen: parent.bounds.size), animated: true)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil { idleTimer?.invalidate() } else { scheduleAutoHide() }
    }

    // MARK: Touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // A slim tab is easier to hit with a little room around it
        bounds.insetBy(dx: isDocked ? -12 : -4, dy: isDocked ? -6 : -4).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let parent = superview else { return }
        idleTimer?.invalidate()
        downPoint = touch.location(in: parent)
        downCentre = center
        dragging = false
        UIView.animate(withDuration: 0.12) {
            self.alpha = 1
            self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let parent = superview else { return }
        let point = touch.location(in: parent)
        let scale = window?.screen.scale ?? 2
        if !dragging && (abs(point.x - downPoint.x) * scale > FloatingButtonPlacement.dragThresholdPixels
                         || abs(point.y - downPoint.y) * scale > FloatingButtonPlacement.dragThresholdPixels) {
            dragging = true
            transform = .identity
            // Pulling a tab off the edge makes it a button again, unless tabs are the style
            if isDocked && options.style == .floating {
                undock(animated: false)
                downCentre = center
            }
        }
        guard dragging else { return }
        let size = parent.bounds.size
        if let edge = dockedEdge {
            // A tab slides along its edge
            frame = tabFrame(edge: edge, centreY: downCentre.y + point.y - downPoint.y, screen: size)
        } else {
            let half = bounds.width / 2
            center = CGPoint(x: min(max(downCentre.x + point.x - downPoint.x, half), size.width - half),
                             y: min(max(downCentre.y + point.y - downPoint.y, half), size.height - half))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(tap: !dragging)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(tap: false)
    }

    private func finish(tap: Bool) {
        UIView.animate(withDuration: 0.12) { self.transform = .identity }
        if dragging, let parent = superview {
            let size = parent.bounds.size
            if options.style == .edge {
                // A tab goes to whichever side it was dragged nearer
                dock(to: centerXSide(in: size), animated: true)
            } else if MenuButtonDock.snaps(buttonFrame: frame, screen: size) {
                dock(to: MenuButtonDock.nearestEdge(buttonFrame: frame, screen: size), animated: true)
            }
            save(in: size)
        }
        dragging = false
        UIView.animate(withDuration: 0.4) { self.alpha = self.restingAlpha }
        scheduleAutoHide()
        if tap {
            onTap()
        }
    }

    private func centerXSide(in size: CGSize) -> MenuButtonDock.Edge {
        frame.midX < size.width / 2 ? .left : .right
    }

    /// Saves the spot as the button's own top-left corner, so a tab keeps its height
    private func save(in size: CGSize) {
        let buttonSize = options.size.points
        let origin = CGPoint(x: isDocked ? (dockedEdge == .left ? 0 : size.width - buttonSize) : frame.minX,
                             y: frame.midY - buttonSize / 2)
        let room = CGSize(width: max(size.width - buttonSize, 1), height: max(size.height - buttonSize, 1))
        let keys = FloatingButtonPlacement.keys(portrait: FloatingButtonPlacement.isPortrait(size))
        defaults.set(Double(min(max(origin.x / room.width, 0), 1)), forKey: keys.x)
        defaults.set(Double(min(max(origin.y / room.height, 0), 1)), forKey: keys.y)
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }
}
