//
//  StreamMenuView.swift
//  Starwire
//
//  The stream menu: a side sheet on the right, as Starwire for Android's OverlayMenuView
//  (GPL-3.0): a header with the game, a grid of tiles (switch tiles show their state), and Close,
//  Quit Session and Disconnect under it. What is on it comes from StarwireKit's StreamMenu. It is
//  driven by touch or by a controller (d-pad to move, A to choose, B to go back or close, and
//  Android's shortcuts: X mouse, Y keyboard, Start Guide, RB stats).
//

import StarwireKit
import UIKit

final class StreamMenuView: UIView {
    static let sheetWidth: CGFloat = 440
    static let margin: CGFloat = 16
    /// Android's default cover tint (violet), darkened for the panel
    static let tint = UIColor(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255, alpha: 1)

    var state: () -> StreamMenuState = { StreamMenuState() }
    var onAction: (StreamMenuAction) -> Void = { _ in }
    var onClose: () -> Void = {}

    private(set) var page: StreamMenuPage = .main
    private let sheet = UIView()
    private let header = UIStackView()
    private let swatch = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let scroll = UIScrollView()
    private let grid = UIView()
    private let bar = UIStackView()
    private var tiles: [(item: StreamMenuItem, button: UIButton)] = []
    private var barButtons: [(item: StreamMenuItem, button: UIButton)] = []
    private var focus = 0

    init(title: String, detail: String) {
        super.init(frame: .zero)
        accessibilityIdentifier = "StreamMenu"
        backgroundColor = .clear

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        Self.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Android: each channel * 0.22 + 10, about 96% opaque
        sheet.backgroundColor = UIColor(red: r * 0.22 + 10 / 255, green: g * 0.22 + 10 / 255, blue: b * 0.22 + 10 / 255, alpha: 0xF4 / 255)
        sheet.layer.cornerRadius = 28
        sheet.layer.cornerCurve = .continuous
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowOpacity = 0.4
        sheet.layer.shadowRadius = 12
        sheet.accessibilityViewIsModal = true
        addSubview(sheet)

        swatch.backgroundColor = Self.tint
        swatch.layer.cornerRadius = 10
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([swatch.widthAnchor.constraint(equalToConstant: 42), swatch.heightAnchor.constraint(equalToConstant: 56)])
        titleLabel.text = title.isEmpty ? StreamMenu.title : title
        titleLabel.font = .systemFont(ofSize: 20, weight: .black)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = UIColor(red: 0xE2 / 255, green: 0xE8 / 255, blue: 0xF0 / 255, alpha: 1)
        detailLabel.isHidden = detail.isEmpty
        let titles = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        titles.axis = .vertical
        titles.spacing = 2
        header.addArrangedSubview(swatch)
        header.addArrangedSubview(titles)
        header.spacing = 12
        header.alignment = .center
        sheet.addSubview(header)

        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(grid)
        sheet.addSubview(scroll)

        bar.axis = .vertical
        bar.spacing = 8
        sheet.addSubview(bar)
        buildBar()
        reload()

        let tapOutside = UITapGestureRecognizer(target: self, action: #selector(tappedOutside(_:)))
        tapOutside.cancelsTouchesInView = false
        addGestureRecognizer(tapOutside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // Touches outside the sheet still reach the stream, as on Android (no scrim)
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        sheet.frame.contains(point)
    }

    @objc private func tappedOutside(_ recognizer: UITapGestureRecognizer) {}

    // MARK: Showing

    func show(in parent: UIView) {
        page = .main
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(self)
        reload()
        layoutIfNeeded()
        // Slides in from the right while fading in, 320 ms, as on Android
        sheet.alpha = 0
        sheet.transform = CGAffineTransform(translationX: Self.sheetWidth * 0.4, y: 0)
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut]) {
            self.sheet.alpha = 1
            self.sheet.transform = .identity
        }
        // Close is selected first, so A just goes back to the game
        focus = tiles.count
        updateFocus()
        UIAccessibility.post(notification: .screenChanged, argument: sheet)
    }

    func hide() {
        // Android has no exit animation
        removeFromSuperview()
        onClose()
    }

    func reload() {
        buildTiles()
        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = bounds.inset(by: safeAreaInsets)
        let width = min(Self.sheetWidth, safe.width - 2 * Self.margin)
        sheet.frame = CGRect(x: safe.maxX - width - Self.margin, y: safe.minY + Self.margin, width: width,
                             height: safe.height - 2 * Self.margin)
        let inner = sheet.bounds.insetBy(dx: 20, dy: 20)
        header.frame = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 56)
        let barHeight = bar.systemLayoutSizeFitting(CGSize(width: inner.width, height: 0),
                                                    withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        bar.frame = CGRect(x: inner.minX, y: inner.maxY - barHeight, width: inner.width, height: barHeight)
        scroll.frame = CGRect(x: inner.minX, y: header.frame.maxY + 18, width: inner.width,
                              height: max(bar.frame.minY - 16 - header.frame.maxY - 18, 0))
        layoutGrid()
    }

    private var columns: Int {
        // Sub pages use two columns; the main page fits up to five, as many as keep labels readable
        if page != .main { return 2 }
        return max(2, min(5, Int(scroll.bounds.width / 92)))
    }

    private func layoutGrid() {
        let spacing: CGFloat = 8
        let count = columns
        let tileWidth = (scroll.bounds.width - spacing * CGFloat(count - 1)) / CGFloat(count)
        let tileHeight: CGFloat = page == .main ? 76 : 48
        for (index, tile) in tiles.enumerated() {
            let row = index / count, column = index % count
            tile.button.frame = CGRect(x: CGFloat(column) * (tileWidth + spacing), y: CGFloat(row) * (tileHeight + spacing),
                                       width: tileWidth, height: tileHeight)
            // A switch tile's switch sits in its top corner
            tile.button.viewWithTag(99)?.frame.origin = CGPoint(x: tileWidth - 21, y: 6)
        }
        let rows = (tiles.count + count - 1) / count
        grid.frame = CGRect(x: 0, y: 0, width: scroll.bounds.width, height: CGFloat(rows) * (tileHeight + spacing))
        scroll.contentSize = grid.frame.size
    }

    // MARK: Tiles

    private func buildTiles() {
        tiles.forEach { $0.button.removeFromSuperview() }
        tiles = StreamMenu.items(on: page, state: state()).map { item in
            let button = makeTile(item)
            grid.addSubview(button)
            return (item, button)
        }
    }

    private func makeTile(_ item: StreamMenuItem) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = item.title
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var out = attributes
            out.font = .systemFont(ofSize: 12, weight: .semibold)
            return out
        }
        if !item.symbol.isEmpty && page == .main {
            configuration.image = UIImage(systemName: item.symbol)
            configuration.imagePlacement = .top
            configuration.imagePadding = 6
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20)
        }
        configuration.baseForegroundColor = .white
        let button = UIButton(configuration: configuration)
        button.layer.cornerRadius = 8
        button.layer.cornerCurve = .continuous
        button.accessibilityIdentifier = "menu_\(item.id)"
        if let on = item.isOn {
            button.accessibilityValue = on ? "On" : "Off"
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            button.backgroundColor = on ? UIColor(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255, alpha: 0x59 / 255)
                : UIColor.white.withAlphaComponent(0.10)
            let knob = UIView(frame: CGRect(x: 0, y: 0, width: 15, height: 8))
            knob.layer.cornerRadius = 4
            knob.layer.borderWidth = 1
            knob.layer.borderColor = UIColor.white.cgColor
            knob.backgroundColor = on ? .white : .clear
            knob.isUserInteractionEnabled = false
            knob.tag = 99
            button.addSubview(knob)
        } else {
            button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        }
        button.addAction(UIAction { [weak self] _ in self?.choose(item) }, for: .touchUpInside)
        return button
    }

    private func buildBar() {
        bar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        barButtons = StreamMenu.bar.map { item in
            var configuration = item.action == .close ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
            configuration.title = item.title
            configuration.cornerStyle = .capsule
            if item.action == .close {
                configuration.baseBackgroundColor = UIColor(red: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255, alpha: 1)
            } else {
                configuration.image = UIImage(systemName: item.symbol)
                configuration.imagePadding = 6
                configuration.baseForegroundColor = .white
            }
            let button = UIButton(configuration: configuration)
            button.accessibilityIdentifier = "menu_\(item.id)"
            button.addAction(UIAction { [weak self] _ in self?.choose(item) }, for: .touchUpInside)
            return (item, button)
        }
        let pills = UIStackView(arrangedSubviews: barButtons.dropFirst().map(\.button))
        pills.distribution = .fillEqually
        pills.spacing = 8
        if let close = barButtons.first?.button {
            bar.addArrangedSubview(close)
        }
        bar.addArrangedSubview(pills)
    }

    // MARK: Choosing

    private func choose(_ item: StreamMenuItem) {
        switch item.action {
        case .openPage(let target):
            switchPage(target)
            return
        case .back:
            switchPage(.main)
            return
        case .close:
            hide()
            return
        default:
            break
        }
        if item.closesMenu {
            hide()
            onAction(item.action)
        } else {
            onAction(item.action)
            // A switch tile stays open and redraws its switch
            let keep = focus
            reload()
            focus = min(keep, tiles.count + barButtons.count - 1)
            updateFocus()
        }
    }

    private func switchPage(_ target: StreamMenuPage) {
        page = target
        reload()
        layoutIfNeeded()
        focus = 0
        updateFocus()
        scroll.setContentOffset(.zero, animated: false)
    }

    // MARK: Controller

    /// Buttons newly pressed on a controller while the menu shows (GamepadButton flags, already
    /// flipped when "Flip face buttons" is on).
    func controllerPressed(_ buttons: Int) {
        let all = tiles.map(\.button) + barButtons.map(\.button)
        guard !all.isEmpty else { return }
        let count = columns
        if buttons & GamepadButton.b != 0 {
            if page == .main { hide() } else { switchPage(.main) }
            return
        }
        if buttons & GamepadButton.a != 0 {
            if focus < tiles.count {
                choose(tiles[focus].item)
            } else if focus - tiles.count < barButtons.count {
                choose(barButtons[focus - tiles.count].item)
            }
            return
        }
        if page == .main {
            if buttons & GamepadButton.x != 0 { hide(); onAction(.toggleMouseEmulation); return }
            if buttons & GamepadButton.y != 0 { hide(); onAction(.systemKeyboard); return }
            if buttons & GamepadButton.start != 0 { hide(); onAction(.guide); return }
            if buttons & GamepadButton.rightBumper != 0 { hide(); onAction(.toggleStats); return }
        }
        if buttons & GamepadButton.right != 0 { focus = min(focus + 1, all.count - 1) }
        if buttons & GamepadButton.left != 0 { focus = max(focus - 1, 0) }
        if buttons & GamepadButton.down != 0 {
            focus = focus < tiles.count ? min(focus + count, tiles.count) : min(focus + 1, all.count - 1)
        }
        if buttons & GamepadButton.up != 0 {
            focus = focus >= tiles.count ? max(tiles.count - 1, 0) : max(focus - count, 0)
        }
        updateFocus()
    }

    private func updateFocus() {
        let all = tiles.map(\.button) + barButtons.map(\.button)
        for (index, button) in all.enumerated() {
            let selected = index == focus
            button.layer.borderWidth = selected ? 2 : (index < tiles.count && tiles[index].item.isOn != nil ? 1 : 0)
            button.layer.borderColor = (selected ? UIColor.white : UIColor.white.withAlphaComponent(0.25)).cgColor
        }
        if focus < tiles.count {
            scroll.scrollRectToVisible(tiles[focus].button.frame, animated: true)
        }
    }
}

/// The floating menu button: tap to open or close the menu, drag to move it. Its spot is saved
/// per orientation as a fraction of the room it can move in (Android's FloatingButton).
final class FloatingMenuButton: UIButton {
    var onTap: () -> Void = {}
    private var downPoint: CGPoint = .zero
    private var downOrigin: CGPoint = .zero
    private var dragging = false
    private let defaults = UserDefaults(suiteName: StarwireSettings.suiteName) ?? .standard

    init() {
        let size = FloatingButtonPlacement.size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)),
                 for: .normal)
        tintColor = .white
        backgroundColor = UIColor(red: 0x1A / 255, green: 0x12 / 255, blue: 0x38 / 255, alpha: 0xD9 / 255)
        layer.cornerRadius = size / 2
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(red: 0xC4 / 255, green: 0xB5 / 255, blue: 0xFD / 255, alpha: 0xB3 / 255).cgColor
        alpha = FloatingButtonPlacement.idleAlpha
        accessibilityLabel = "Menu"
        accessibilityIdentifier = "StreamMenuButton"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Moves to the saved spot for the screen's orientation.
    func place(in screen: CGSize) {
        guard !dragging else { return }
        let keys = FloatingButtonPlacement.keys(portrait: FloatingButtonPlacement.isPortrait(screen))
        var fraction: CGPoint?
        if defaults.object(forKey: keys.x) != nil, defaults.object(forKey: keys.y) != nil {
            fraction = CGPoint(x: defaults.double(forKey: keys.x), y: defaults.double(forKey: keys.y))
        }
        frame.origin = FloatingButtonPlacement.origin(fraction: fraction, screen: screen)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let parent = superview else { return }
        downPoint = touch.location(in: parent)
        downOrigin = frame.origin
        dragging = false
        UIView.animate(withDuration: 0.12) { self.alpha = 1 }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let parent = superview else { return }
        let point = touch.location(in: parent)
        let scale = window?.screen.scale ?? 2
        if !dragging && (abs(point.x - downPoint.x) * scale > FloatingButtonPlacement.dragThresholdPixels
                         || abs(point.y - downPoint.y) * scale > FloatingButtonPlacement.dragThresholdPixels) {
            dragging = true
        }
        if dragging {
            let origin = CGPoint(x: downOrigin.x + point.x - downPoint.x, y: downOrigin.y + point.y - downPoint.y)
            let fraction = FloatingButtonPlacement.fraction(origin: origin, screen: parent.bounds.size)
            frame.origin = FloatingButtonPlacement.origin(fraction: fraction, screen: parent.bounds.size)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(tap: !dragging)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(tap: false)
    }

    private func finish(tap: Bool) {
        UIView.animate(withDuration: 0.4) { self.alpha = FloatingButtonPlacement.idleAlpha }
        if dragging, let parent = superview {
            let fraction = FloatingButtonPlacement.fraction(origin: frame.origin, screen: parent.bounds.size)
            let keys = FloatingButtonPlacement.keys(portrait: FloatingButtonPlacement.isPortrait(parent.bounds.size))
            defaults.set(Double(fraction.x), forKey: keys.x)
            defaults.set(Double(fraction.y), forKey: keys.y)
        }
        dragging = false
        if tap {
            onTap()
        }
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }
}
