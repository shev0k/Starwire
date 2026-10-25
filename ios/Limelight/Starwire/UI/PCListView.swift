//
//  PCListView.swift
//  Starwire
//
//  The PCs this device knows, as frosted cards (Android's PcView). Tapping one opens its games,
//  pairing first when needed. Each card's menu has pairing, wake, the network test, details and
//  delete.
//

import StarwireKit
import SwiftUI

struct PCListView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: Library
    @State private var address = ""

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 18)]

    var body: some View {
        ZStack {
            StarfieldBackground(paused: state.isStreaming)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if library.hosts.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(library.hosts) { host in
                                PCCard(host: host, open: { open(host) }, menu: { showMenu(host) })
                            }
                            addCard
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            StarwireLogo(paused: state.isStreaming)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            RainbowWordmark(paused: state.isStreaming)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            iconButton("plus", label: L("title_add_pc"), id: "pcs-add") { askForAddress() }
            iconButton("info.circle", label: L("ios_about_title"), id: "pcs-about") { state.path.append(.about) }
            iconButton("gearshape.fill", label: L("ios_settings_title"), id: "pcs-settings") {
                state.path.append(.settings(section: nil))
            }
        }
        .padding(.top, 12)
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .controllerFocusable(id, cornerRadius: 24, action: action)
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 18) {
            ProgressView()
                .accessibilityHidden(true)
            Text(L("searching_pc").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.title3)
                .multilineTextAlignment(.center)
            Text(L("ios_searching_help"))
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                pillButton(L("title_add_pc"), id: "pcs-add-empty") { askForAddress() }
                pillButton(L("ios_demo_try"), id: "pcs-demo") { state.message(L("ios_demo_try"), L("ios_demo_how")) }
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func pillButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 20)
                .frame(minHeight: 48)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .controllerFocusable(id, cornerRadius: 24, action: action)
    }

    private var addCard: some View {
        Button { askForAddress() } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 36))
                    .accessibilityHidden(true)
                Text(L("title_add_pc"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .frostedCard(cornerRadius: 22, padding: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pcs-add-card")
        .controllerFocusable("pcs-add-card", cornerRadius: 22) { askForAddress() }
    }

    // MARK: - Actions

    private func open(_ host: PCItem) {
        state.busy = L("applist_connect_msg")
        Task {
            let result = await library.backend.refresh(host.id)
            state.busy = nil
            library.reload()
            switch result {
            case .ok:
                state.path.append(.games(hostID: host.id))
            case .needsPairing:
                pair(host)
            case .failed(let error):
                // A PC that was paired before still shows its saved games
                if host.isPaired && !host.games.isEmpty {
                    state.path.append(.games(hostID: host.id))
                } else {
                    state.message(L("conn_error_title"), error.isEmpty ? L("error_pc_offline") : error)
                }
            }
        }
    }

    private func pair(_ host: PCItem) {
        Task {
            let error = await library.backend.pair(host.id) { pin in
                state.show(PanelContent(title: L("pair_pairing_title"),
                                        message: L("pair_pairing_msg") + "\n\n" + L("pair_pairing_help"),
                                        highlight: pin,
                                        buttons: [PanelButton(title: L("applist_menu_cancel"), role: .cancel) {
                                            library.backend.cancelPairing()
                                        }]))
            }
            state.dismissPanel()
            library.reload()
            if let error {
                state.message(L("pair_fail"), error)
            } else {
                open(host)
            }
        }
    }

    private func askForAddress() {
        address = ""
        state.show(PanelContent(title: L("title_add_pc"), message: L("ios_add_pc_help"),
                                textField: (L("ip_hint"), $address, .URL),
                                buttons: [
                                    PanelButton(title: L("ios_add"), identifier: "pcs-add-confirm") { add() },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }

    private func add() {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            state.message(L("title_add_pc"), L("addpc_enter_ip"))
            return
        }
        state.busy = L("ios_adding_pc")
        Task {
            let error = await library.backend.addHost(address: typed)
            state.busy = nil
            library.reload()
            if let error {
                state.message(L("title_add_pc"), error.isEmpty ? L("addpc_fail") : error)
            }
        }
    }

    private func showMenu(_ host: PCItem) {
        var buttons: [PanelButton] = []
        if host.status == .online && !host.isPaired {
            buttons.append(PanelButton(title: L("pcview_menu_pair_pc")) { pair(host) })
        }
        if host.isPaired {
            buttons.append(PanelButton(title: L("pcview_menu_app_list")) { open(host) })
        }
        if host.status != .online {
            buttons.append(PanelButton(title: L("pcview_menu_send_wol")) {
                state.message(L("wol_waking_pc"), library.backend.wake(host.id))
            })
        }
        if host.isPaired && host.canSleep && host.status == .online {
            buttons.append(PanelButton(title: L("ios_pc_sleep")) { confirmSleep(host) })
        }
        buttons.append(PanelButton(title: L("pcview_menu_test_network")) { testNetwork() })
        buttons.append(PanelButton(title: L("pcview_menu_details")) { details(host) })
        buttons.append(PanelButton(title: L("pcview_menu_delete_pc"), role: .destructive) { confirmDelete(host) })
        buttons.append(PanelButton(title: L("applist_menu_cancel"), role: .cancel))
        state.show(PanelContent(title: host.name, message: statusText(host), buttons: buttons))
    }

    private func confirmSleep(_ host: PCItem) {
        state.show(PanelContent(title: L("ios_pc_sleep_question", host.name), message: L("ios_pc_sleep_wake_help"),
                                buttons: [
                                    PanelButton(title: L("ios_pc_sleep_confirm"), role: .destructive) {
                                        Task {
                                            let error = await library.backend.sleepPC(host.id)
                                            state.message(host.name, error ?? L("ios_pc_sleeping"))
                                        }
                                    },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }

    private func confirmDelete(_ host: PCItem) {
        state.show(PanelContent(title: L("pcview_menu_delete_pc"), message: L("delete_pc_msg"),
                                buttons: [
                                    PanelButton(title: L("pcview_menu_delete_pc"), role: .destructive) {
                                        library.backend.removeHost(host.id)
                                        library.reload()
                                    },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }

    private func testNetwork() {
        state.busy = L("nettest_title_waiting")
        Task {
            let blocked = await library.backend.testNetwork()
            state.busy = nil
            let text: String
            if let blocked {
                text = blocked.isEmpty ? L("nettest_text_success") : L("nettest_text_failure") + blocked
            } else {
                text = L("nettest_text_inconclusive")
            }
            state.message(L("nettest_title_done"), text)
        }
    }

    private func details(_ host: PCItem) {
        let none = L("ios_none")
        let lines = [
            (L("ios_detail_name"), host.name),
            (L("ios_detail_status"), statusText(host)),
            (L("ios_detail_active_address"), host.activeAddress ?? none),
            (L("ios_detail_local_address"), host.localAddress ?? none),
            (L("ios_detail_remote_address"), host.externalAddress ?? none),
            (L("ios_detail_ipv6_address"), host.ipv6Address ?? none),
            (L("ios_detail_manual_address"), host.manualAddress ?? none),
            (L("ios_detail_mac"), host.macAddress ?? none),
            (L("ios_detail_running"), host.runningGame?.name ?? none),
            (L("ios_detail_https_port"), String(host.httpsPort)),
        ]
        state.message(L("pcview_menu_details"), lines.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
    }

    private func statusText(_ host: PCItem) -> String {
        switch (host.status, host.pairing) {
        case (.online, .paired): return L("ios_pc_online_paired")
        case (.online, _): return L("ios_pc_online_unpaired")
        case (.offline, _): return L("pcview_menu_header_offline")
        case (.unknown, _): return L("pcview_menu_header_unknown")
        }
    }
}

/// One PC: a frosted card with its name, whether it's on and paired, and what it's running.
struct PCCard: View {
    let host: PCItem
    let open: () -> Void
    let menu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 30))
                        .accessibilityHidden(true)
                    Spacer()
                    Circle()
                        .fill(dotColour)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                Text(host.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                if let running = host.runningGame {
                    Label(L("ios_pc_running", running.name), systemImage: "play.fill")
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .frostedCard(cornerRadius: 22, padding: 18)
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture(perform: open)
        .onLongPressGesture(minimumDuration: 0.5, perform: menu)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityIdentifier("PCCard-\(host.name)")
        .accessibilityAction(named: L("ios_pc_menu"), menu)
        .controllerFocusable("pc-\(host.id)", cornerRadius: 22, menu: menu, action: open)
    }

    private var status: String {
        switch (host.status, host.pairing) {
        case (.online, .paired): return L("ios_pc_online_paired")
        case (.online, _): return L("ios_pc_online_unpaired")
        case (.offline, _): return L("pcview_menu_header_offline")
        case (.unknown, _): return L("pcview_menu_header_unknown")
        }
    }

    private var dotColour: Color {
        switch host.status {
        case .online: return host.isPaired ? .green : .yellow
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}
