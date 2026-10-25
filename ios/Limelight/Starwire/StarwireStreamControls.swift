//
//  StarwireStreamControls.swift
//  Starwire
//
//  Everything Starwire puts over a stream for input: the stream menu and its floating button,
//  the on-screen controller, the full keyboard, and the input coordinator. The stream screen
//  (StreamFrameViewController, ObjC) makes one, forwards its life to it, and handles the few
//  menu actions only it can do (bitrate, stats, quit, disconnect, the system keyboard).
//

import StarwireKit
import SwiftUI
import UIKit

@MainActor @objc(StarwireStreamControls)
final class StarwireStreamControls: NSObject {
    @objc let input: StarwireStreamInput
    private weak var view: UIView?
    private let title: String
    private let detail: String
    private let menuModel: StreamMenuModel
    private var menuHost: UIHostingController<StreamMenuPanel>?
    private let floatingButton = FloatingMenuButton()
    private var floatingButtonShown: Bool
    private var onScreenControls: OnScreenControlsView?
    private var fullKeyboard: FullKeyboardView?
    private var controllerKeyboard: UIHostingController<ControllerKeyboardView>?
    private var pictureScaling: PictureScaling
    private let touchDelivery = TouchDeliveryLink()

    // What only the stream screen can do
    @objc var onBitrate: (() -> Void)?
    /// Asks the PC for this bitrate, in kbps
    @objc var onSetBitrate: ((Int) -> Void)?
    /// How the picture fills the screen: "fit", "stretch" or "fill"
    @objc var onPictureScaling: ((String) -> Void)?
    /// The bitrate the PC applied, in kbps, for the menu
    @objc var bitrateKbps = 0
    @objc var onToggleStats: (() -> Void)?
    @objc var onSystemKeyboard: (() -> Void)?
    @objc var onQuit: (() -> Void)?
    @objc var onDisconnect: (() -> Void)?
    @objc var onNotice: ((String) -> Void)?
    @objc var present: ((UIViewController) -> Void)?
    /// Whether the statistics overlay shows, for the menu's switch
    @objc var statsShown = false

    /// The bitrate the PC applied, read out with the floating button ("70 Mbps")
    @objc var bitrateText: String? {
        get { floatingButton.accessibilityValue }
        set { floatingButton.accessibilityValue = newValue }
    }

    @objc static var bitrateChoicesMbps: [NSNumber] { StreamMenu.bitrateChoicesMbps.map { NSNumber(value: $0) } }

    @objc init(view: UIView, streamWidth: Int, streamHeight: Int, fps: Int, appName: String) {
        self.view = view
        title = appName
        detail = StreamMenu.detail(height: streamHeight, fps: fps)
        menuModel = StreamMenuModel(title: appName, chips: [StreamMenu.detail(height: streamHeight, fps: fps)].filter { !$0.isEmpty })
        input = StarwireStreamInput(streamWidth: streamWidth, streamHeight: streamHeight, viewSize: view.bounds.size,
                                    scale: view.window?.screen.scale ?? UIScreen.main.scale)
        floatingButtonShown = StarwireSettings.store.bool("checkbox_enable_floating_button")
        pictureScaling = PictureScaling(rawValue: StarwireSettings.store.string("list_video_scaling") ?? "") ?? .fit
        super.init()
        input.onOpenMenu = { [weak self] in self?.openMenu() }
        input.onGesture = { [weak self] action in self?.gesture(action) }
        input.onStreamShortcut = { [weak self] shortcut in
            switch shortcut {
            case .menu: self?.toggleMenu()
            case .stats: self?.onToggleStats?()
            case .disconnect: self?.onDisconnect?()
            }
        }
        input.onNotice = { [weak self] text in self?.onNotice?(text) }
        floatingButton.onTap = { [weak self] in self?.toggleMenu() }
        let gamepads = StarwireGamepads.shared
        gamepads.onOpenMenu = { [weak self] in self?.openMenu() }
        gamepads.onMenuButtons = { [weak self] buttons in self?.menuModel.controllerPressed(buttons) }
        gamepads.onNotice = { [weak self] text in self?.onNotice?(text) }
    }

    /// The stream is up: show the controls the settings ask for.
    @objc func streamStarted(hostFeatureFlags: UInt32, pcUUID: String?, host: String, appID: Int) {
        input.streamStarted(hostFeatureFlags: hostFeatureFlags, pcUUID: pcUUID, host: host, appID: appID)
        guard let view else { return }
        touchDelivery.start(in: view)
        if StarwireSettings.store.bool("checkbox_show_onscreen_controls") {
            setOnScreenControls(shown: true)
        }
        if floatingButtonShown {
            view.addSubview(floatingButton)
            floatingButton.place(in: view.bounds.size)
        }
        if pictureScaling != .fit {
            onPictureScaling?(pictureScaling.rawValue)
        }
        // For the device tests' pictures: the controller keyboard with no controller
        if UserDefaults.standard.bool(forKey: "StarwireOpenControllerKeyboard") {
            setControllerKeyboard(shown: true)
        }
        onNotice?("Hold \(StarwireGamepads.shared.menuTriggerTitle) to open menu")
    }

    /// A four or five-finger tap
    private func gesture(_ action: GestureAction) {
        switch action {
        case .none: break
        case .menu: toggleMenu()
        case .fullKeyboard: perform(.toggleFullKeyboard)
        case .systemKeyboard: perform(.systemKeyboard)
        case .onScreenControls: perform(.toggleOnScreenControls)
        case .stats: perform(.toggleStats)
        case .panZoom: perform(.togglePanZoom)
        case .menuButton: perform(.toggleFloatingButton)
        }
    }

    /// The view changed size or turned.
    @objc func layout() {
        guard let view else { return }
        input.layout(viewSize: view.bounds.size, scale: view.window?.screen.scale ?? UIScreen.main.scale)
        floatingButton.place(in: view.bounds.size)
        if let osc = onScreenControls { osc.frame = view.bounds }
        if let keyboard = fullKeyboard { keyboard.frame = view.bounds }
        floatingButton.superview?.bringSubviewToFront(floatingButton)
    }

    /// Returns true when the PC's cursor was just shown again, so the caller waits a moment
    /// before stopping the connection.
    @objc func streamStopping() -> Bool {
        fullKeyboard?.releaseAll()
        touchDelivery.stop()
        menuHost?.view.removeFromSuperview()
        menuHost = nil
        StarwireGamepads.shared.menuOpen = false
        return input.streamStopping()
    }

    // MARK: Menu

    @objc var menuShown: Bool { menuModel.shown }

    @objc func toggleMenu() {
        if menuShown { menuModel.hide() } else { openMenu() }
    }

    @objc func openMenu() {
        guard let view, !menuShown else { return }
        menuModel.readState = { [weak self] in self?.menuState() ?? StreamMenuState() }
        menuModel.onAction = { [weak self] action in self?.perform(action) }
        menuModel.onHidden = { [weak self] in
            StarwireGamepads.shared.menuOpen = false
            // The menu button comes back as the panel slides out
            self?.floatingButton.isUserInteractionEnabled = true
            self?.floatingButton.restoreRestingAlpha()
            // Off the screen once the panel has slid out, so touches reach the stream again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let self, !self.menuModel.shown else { return }
                self.menuHost?.view.removeFromSuperview()
            }
        }
        let host = menuHost ?? UIHostingController(rootView: StreamMenuPanel(model: menuModel))
        host.view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if host.view.superview == nil { view.addSubview(host.view) }
        menuHost = host
        menuModel.show()
        StarwireGamepads.shared.menuOpen = true
        // The panel has its own close button; the menu button would sit on top of it
        UIView.animate(withDuration: 0.2) { self.floatingButton.alpha = 0 }
        floatingButton.isUserInteractionEnabled = false
        StarwireLog.info("Input: stream menu opened")
    }

    private func menuState() -> StreamMenuState {
        var state = StreamMenuState()
        state.fullKeyboardShown = fullKeyboard != nil
        state.mouseEmulation = StarwireGamepads.shared.mouseEmulationOn
        state.statsShown = statsShown
        state.panZoom = input.panZoomOn
        state.sensitivityOn = input.sensitivityOn
        state.sensitivityPercent = StarwireSettings.store.int("seekbar_touch_sensitivity")
        state.onScreenControlsShown = onScreenControls != nil
        state.floatingButtonShown = floatingButtonShown
        state.showFixHostCursor = input.offersHostCursorFix
        state.touchMode = input.dispatcher.mode
        state.bitrateMbps = bitrateKbps / 1000
        state.pictureScaling = pictureScaling
        state.controllerConnected = StarwireGamepads.shared.hasController
        let storage = StarwireSettings.store.storage
        state.customCommands = CustomCommandsStore(storage: storage).commands
        state.importedShortcuts = ImportedShortcutsStore(storage: storage).load()
        return state
    }

    private func perform(_ action: StreamMenuAction) {
        StarwireLog.info("Input: menu \(action)")
        switch action {
        case .systemKeyboard:
            // After a controller, its own keyboard; after a touch, the system's
            if StarwireSettings.store.bool("checkbox_controller_keyboard") && StarwireGamepads.shared.hasController
                && StarwireGamepads.shared.lastActivity > input.lastTouch {
                setControllerKeyboard(shown: true)
            } else {
                onSystemKeyboard?()
            }
        case .toggleFullKeyboard: setFullKeyboard(shown: fullKeyboard == nil)
        case .toggleMouseEmulation: StarwireGamepads.shared.toggleMouseEmulation()
        case .toggleStats: onToggleStats?()
        case .guide: pressGuide()
        case .bitrate: onBitrate?()
        case .touchMode: chooseTouchMode()
        case .fixHostCursor: input.fixHostCursor()
        case .togglePanZoom: input.togglePanZoom()
        case .toggleSensitivity: input.toggleSensitivity()
        case .keys(let shortcut): input.send(shortcut)
        case .toggleOnScreenControls: setOnScreenControls(shown: onScreenControls == nil)
        case .editOnScreenControls:
            setOnScreenControls(shown: true)
            onScreenControls?.beginEditing()
        case .toggleFloatingButton: setFloatingButton(shown: !floatingButtonShown)
        case .customCommand(let command):
            input.run(command) { [weak self] after in self?.after(after) }
        case .manageShortcuts:
            if let presenter = topViewController() {
                presentShortcutsManager(from: presenter) { [weak self] in self?.menuModel.reload() }
            }
        case .quit: onQuit?()
        case .disconnect: onDisconnect?()
        case .setTouchMode(let mode):
            input.touchModeIndex = mode.rawValue
            onNotice?("Touch mode: \(mode.title)")
        case .setBitrate(let mbps): onSetBitrate?(mbps * 1000)
        case .setPictureScaling(let scaling): setPictureScaling(scaling)
        case .controllerKeyboard: setControllerKeyboard(shown: true)
        case .streamSettings: showStreamSettings()
        case .openPage, .back, .close: break
        }
    }

    private func after(_ action: CommandAfterAction) {
        switch action {
        case .none: break
        case .closeMenu: menuModel.hide()
        case .disconnect: onDisconnect?()
        case .quit: onQuit?()
        case .sleep: onNotice?("Starwire can't put this device to sleep. iOS doesn't let apps do that.")
        }
    }

    /// Guide for 100 ms on the first controller, as Android's sendGuideButton
    private func pressGuide() {
        input.send([.controller(ControllerState(number: 0, activeMask: 1, buttons: GamepadButton.guide))])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.input.send([.controller(ControllerState(number: 0, activeMask: 1))])
        }
    }

    private func chooseTouchMode() {
        let sheet = UIAlertController(title: "Touch mode", message: nil, preferredStyle: .actionSheet)
        for (index, name) in StarwireStreamInput.touchModeTitles.enumerated() {
            let current = index == input.touchModeIndex
            sheet.addAction(UIAlertAction(title: current ? "\(name) (now)" : name, style: .default) { [weak self] _ in
                self?.input.touchModeIndex = index
                self?.onNotice?("Touch mode: \(name)")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let view, let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.maxX - 240, y: view.bounds.midY, width: 1, height: 1)
        }
        present?(sheet)
    }

    /// The view controller on top, to present a sheet from
    private func topViewController() -> UIViewController? {
        var top = view?.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: Overlays

    private func setOnScreenControls(shown: Bool) {
        guard let view else { return }
        if shown, onScreenControls == nil {
            let osc = OnScreenControlsView(frame: view.bounds) { [weak self] event in self?.input.send([event]) }
            view.addSubview(osc)
            onScreenControls = osc
        } else if !shown, let osc = onScreenControls {
            osc.endEditing(save: false)
            osc.removeFromSuperview()
            onScreenControls = nil
        }
        keepOnTop()
    }

    private func setFullKeyboard(shown: Bool) {
        guard let view else { return }
        if shown, fullKeyboard == nil {
            let keyboard = FullKeyboardView { [weak self] event in self?.input.send([event]) }
            keyboard.frame = view.bounds
            keyboard.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            keyboard.onHide = { [weak self] in self?.setFullKeyboard(shown: false) }
            view.addSubview(keyboard)
            fullKeyboard = keyboard
        } else if !shown, let keyboard = fullKeyboard {
            keyboard.releaseAll()
            keyboard.removeFromSuperview()
            fullKeyboard = nil
        }
        keepOnTop()
    }

    /// The controller keyboard, at the bottom of the screen above the safe area
    @objc func setControllerKeyboard(shown: Bool) {
        guard let view else { return }
        let gamepads = StarwireGamepads.shared
        if shown, controllerKeyboard == nil {
            setFullKeyboard(shown: false)
            let model = ControllerKeyboardModel(holding: gamepads.heldButtons)
            model.send = { [weak self] event in self?.input.send([event]) }
            model.onClose = { [weak self] in self?.setControllerKeyboard(shown: false) }
            let host = UIHostingController(rootView: ControllerKeyboardView(model: model))
            host.view.backgroundColor = .clear
            host.sizingOptions = [.intrinsicContentSize]
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
                host.view.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),
                host.view.widthAnchor.constraint(lessThanOrEqualToConstant: 780),
            ])
            host.view.alpha = 0
            host.view.transform = CGAffineTransform(translationX: 0, y: 40)
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                host.view.alpha = 1
                host.view.transform = .identity
            }
            controllerKeyboard = host
            gamepads.onKeyboardState = { [weak model] state in model?.handle(state) }
            gamepads.keyboardOpen = true
            StarwireLog.info("Input: controller keyboard opened")
        } else if !shown, let host = controllerKeyboard {
            controllerKeyboard = nil
            gamepads.keyboardOpen = false
            gamepads.onKeyboardState = nil
            UIView.animate(withDuration: 0.2, animations: {
                host.view.alpha = 0
                host.view.transform = CGAffineTransform(translationX: 0, y: 40)
            }, completion: { _ in host.view.removeFromSuperview() })
        }
        keepOnTop()
    }

    private func setPictureScaling(_ scaling: PictureScaling) {
        pictureScaling = scaling
        input.setPictureScaling(scaling)
        onPictureScaling?(scaling.rawValue)
        onNotice?("Picture: \(scaling.title)")
    }

    /// The settings that take effect mid-stream, over the stream
    private func showStreamSettings() {
        guard let presenter = topViewController() else { return }
        let screen = StreamSettingsSheet.make { [weak self] in self?.settingsChanged() }
        presenter.present(screen, animated: true)
    }

    /// Settings changed mid-stream: apply the ones that can be
    private func settingsChanged() {
        StarwireSettings.reload()
        let store = StarwireSettings.store
        // Live: the gestures, the menu button's look, the full keyboard's layout and size
        input.dispatcher.gestures.settings = GestureSettings(store: store)
        floatingButton.apply(MenuButtonOptions(store: store))
        if let view {
            floatingButton.place(in: view.bounds.size)
        }
        if fullKeyboard != nil {
            setFullKeyboard(shown: false)
            setFullKeyboard(shown: true)
        }
        menuModel.reload()
    }

    private func setFloatingButton(shown: Bool) {
        floatingButtonShown = shown
        if shown, let view {
            view.addSubview(floatingButton)
            floatingButton.place(in: view.bounds.size)
        } else {
            floatingButton.removeFromSuperview()
        }
    }

    /// The menu over everything, the floating button over the menu
    private func keepOnTop() {
        guard let view else { return }
        if let menu = menuHost?.view, menu.superview == view { view.bringSubviewToFront(menu) }
        if floatingButton.superview == view { view.bringSubviewToFront(floatingButton) }
    }
}
