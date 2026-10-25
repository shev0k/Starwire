//
//  AppState.swift
//  Starwire
//
//  Where the app is: the screens on the navigation stack, the panel on top (menus, questions and
//  messages, drawn by the app so a controller can use them), and the stream. Shared by every
//  screen through the environment.
//

import StarwireKit
import SwiftUI
import UIKit

enum Route: Hashable {
    case games(hostID: String)
    case settings(section: String?)
    case gameSettings(hostID: String, appID: String)
    case about
    case licences
    case micPairing(hostID: String?)
}

/// A button in a panel.
struct PanelButton: Identifiable {
    enum Role {
        case normal, cancel, destructive
    }

    let id = UUID()
    var title: String
    var role: Role = .normal
    /// Shown in the device-run tests' queries; the title when nil
    var identifier: String?
    var action: () -> Void = {}
}

/// A menu, a question or a message, drawn over the screen.
struct PanelContent: Identifiable {
    let id = UUID()
    var title: String
    var message: String?
    /// A large line under the title (the pairing PIN)
    var highlight: String?
    var textField: (placeholder: String, binding: Binding<String>, keyboard: UIKeyboardType)?
    var buttons: [PanelButton]
}

@MainActor
final class AppState: ObservableObject {
    @Published var path: [Route] = []
    @Published var panel: PanelContent?
    @Published private(set) var isStreaming = false
    @Published var busy: String?

    let library: Library
    let focus: ControllerFocus

    init(library: Library, focus: ControllerFocus? = nil) {
        self.library = library
        self.focus = focus ?? ControllerFocus()
    }

    func show(_ panel: PanelContent) {
        self.panel = panel
    }

    func message(_ title: String, _ text: String?) {
        panel = PanelContent(title: title, message: text, buttons: [PanelButton(title: L("ios_ok"), role: .cancel)])
    }

    func dismissPanel() {
        panel = nil
    }

    // MARK: - Streams

    /// Starts `appID` on the PC with the settings it should use. `displayMode` replaces "Display
    /// on the PC" for this launch (the app menu's virtual or primary display).
    /// `resume` leaves the overrides bar out, as Android does for a session that already runs.
    func startStream(hostID: String, appID: String, displayMode: VirtualDisplayMode? = nil,
                     quickLaunchKey: String? = nil, resume: Bool = false) {
        guard !isStreaming else { return }
        StarwireSettings.prepareForStream(hostUUID: hostID, appID: appID, displayMode: displayMode,
                                          quickLaunchKey: quickLaunchKey, applyOverrides: !resume)
        StarwireSettings.rememberLastPlayed(hostUUID: hostID, appID: appID)
        StarwireMicrophone.shared.prepare(hostUUID: hostID, address: library.host(hostID)?.activeAddress)
        guard let controller = library.backend.streamViewController(appID: appID, on: hostID, onFinished: { [weak self] in
            self?.streamFinished(hostID: hostID)
        }) else {
            StarwireSettings.streamEnded()
            message(L("conn_error_title"), L("ios_app_gone"))
            return
        }
        isStreaming = true
        focus.isPaused = true
        Self.topViewController()?.present(controller, animated: true)
    }

    private func streamFinished(hostID: String) {
        StarwireSettings.streamEnded()
        isStreaming = false
        focus.isPaused = false
        // The running game changed on the PC
        Task {
            _ = await library.backend.refresh(hostID)
            library.reload()
        }
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
