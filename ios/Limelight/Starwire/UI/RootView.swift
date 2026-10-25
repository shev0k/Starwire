//
//  RootView.swift
//  Starwire
//
//  The SwiftUI app (phase 3): the PC list, a PC's games, settings and about, on one navigation
//  stack over the starfield, with the app's own panels on top. Upstream's storyboards stay in the
//  tree, unused.
//

import StarwireKit
import SwiftUI
import UIKit

@objc(StarwireAppUI)
final class StarwireAppUI: NSObject {
    /// The window's root: the demo PC in demo mode, else the real ones.
    @MainActor @objc static func makeRootViewController() -> UIViewController {
        StarwireSettings.migrateLegacySettingsOnce(StarwireHostLibraryFacade.legacyCoreDataSettings())
        var demo = StarwireSettings.demoModeEnabled
        #if DEBUG
        // The unit tests run inside the app: no discovery or PCs while they run
        demo = demo || NSClassFromString("XCTestCase") != nil
        #endif
        let backend: LibraryBackend = demo ? DemoLibraryBackend() : LiveLibraryBackend()
        if backend.isDemo {
            StarwireLog.info("Demo mode: no PC is used")
        }
        let state = AppState(library: Library(backend: backend))
        let controller = UIHostingController(rootView: RootView().environmentObject(state)
            .environmentObject(state.library).environmentObject(state.focus))
        controller.view.backgroundColor = UIColor(red: 0.04, green: 0.035, blue: 0.094, alpha: 1)
        return controller
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedOnce = false

    var body: some View {
        NavigationStack(path: $state.path) {
            PCListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .games(let hostID):
                        GameScreenView(hostID: hostID)
                    case .settings(let section):
                        SettingsScreen(initialSection: section)
                    case .gameSettings(let hostID, let appID):
                        GameSettingsScreen(hostID: hostID, appID: appID)
                    case .about:
                        AboutScreen()
                    case .licences:
                        LicencesScreen()
                    case .micPairing(let hostID):
                        MicPairingScreen(hostID: hostID)
                    }
                }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .overlay {
            if let panel = state.panel {
                PanelView(panel: panel)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let busy = state.busy {
                BusyView(text: busy)
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.panel?.id)
        .onAppear(perform: firstAppear)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.backend.startDiscovery()
                openShortcutHost()
            case .background:
                library.backend.stopDiscovery()
            default:
                break
            }
        }
    }

    private func firstAppear() {
        guard !openedOnce else { return }
        openedOnce = true
        library.backend.startDiscovery()
        if openShortcutHost() {
            return
        }
        // One PC: straight to its games, as moonlight-ios did
        if library.hosts.count == 1, let only = library.hosts.first {
            open(only.id)
        }
    }

    @discardableResult
    private func openShortcutHost() -> Bool {
        guard let id = library.backend.takePendingShortcutHost() else { return false }
        open(id)
        return true
    }

    private func open(_ hostID: String) {
        state.path = [.games(hostID: hostID)]
    }
}

/// The app's own menus, questions and messages: a frosted card over the screen. A controller
/// moves between its buttons; B closes it.
struct PanelView: View {
    let panel: PanelContent
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var focus: ControllerFocus
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { cancel() }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                Text(panel.title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let highlight = panel.highlight {
                    Text(highlight)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(highlight.map(String.init).joined(separator: " "))
                }
                if let message = panel.message, !message.isEmpty {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let field = panel.textField {
                    TextField(field.placeholder, text: field.binding)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(field.keyboard)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($fieldFocused)
                        .onAppear { fieldFocused = true }
                }
                VStack(spacing: 8) {
                    ForEach(panel.buttons) { button in
                        panelButton(button)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 440)
            .frostedCard(cornerRadius: 24, padding: 0)
            .padding(24)
            .environment(\.controllerScope, "panel")
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { focus.pushScope("panel") }
        .onDisappear { focus.popScope("panel") }
        .controllerBack("panel") { cancel() }
    }

    private func panelButton(_ button: PanelButton) -> some View {
        Button {
            state.dismissPanel()
            button.action()
        } label: {
            Text(button.title)
                .font(.body.weight(button.role == .cancel ? .regular : .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(button.role == .destructive ? Color(red: 1, green: 0.6, blue: 0.6) : .white)
                .background(Color.white.opacity(button.role == .cancel ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(button.identifier ?? button.title)
        .controllerFocusable("panel-\(button.id)", cornerRadius: 12) {
            state.dismissPanel()
            button.action()
        }
    }

    private func cancel() {
        let cancel = panel.buttons.first { $0.role == .cancel }
        state.dismissPanel()
        cancel?.action()
    }
}

struct BusyView: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(text)
                    .font(.body)
            }
            .padding(24)
            .frostedCard(cornerRadius: 20, padding: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The screens' common top bar: a back button and a title, with buttons on the trailing side.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var showsBack = true
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 14) {
            if showsBack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ios_back"))
                .controllerFocusable("header-back", cornerRadius: 24) { dismiss() }
            }
            Text(title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, showsBack: Bool = true) {
        self.init(title: title, showsBack: showsBack) { EmptyView() }
    }
}
