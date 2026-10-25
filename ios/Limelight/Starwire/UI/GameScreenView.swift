//
//  GameScreenView.swift
//  Starwire
//
//  One PC's games (Android's AppView): a hero with the running or last played game in its cover's
//  colours, the game tiles, Vibeshine's Remote tiles, Quick Launch and the overrides bar. A tile
//  starts its game; holding it (or Menu on a controller) opens the app menu: resume or quit,
//  start in the virtual or primary display, this game's settings, hide, details.
//

import StarwireKit
import SwiftUI
import UIKit

/// Cover pictures, read once from the files moonlight-ios saved.
@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private var images: [String: UIImage] = [:]
    private var palettes: [String: CoverPalette] = [:]

    func image(_ path: String?) -> UIImage? {
        guard let path else { return nil }
        if let image = images[path] { return image }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        images[path] = image
        return image
    }

    func palette(_ path: String?) -> CoverPalette {
        guard let path, let image = image(path) else { return .fallback }
        if let palette = palettes[path] { return palette }
        let palette = CoverPalette.from(image: image)
        palettes[path] = palette
        return palette
    }
}

struct GameScreenView: View {
    let hostID: String
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showHidden = false
    @State private var heroID: String?

    private var host: PCItem? { library.host(hostID) }

    private var games: [GameItem] {
        (host?.games ?? []).filter { $0.kind == .game && (showHidden || !$0.hidden) }
    }

    private var remoteTiles: [GameItem] {
        (host?.games ?? []).filter { $0.isControlTile && !$0.hidden }
    }

    /// The running game, else the one last played, else the first
    private var hero: GameItem? {
        let all = host?.games.filter { $0.kind == .game } ?? []
        if let heroID, let chosen = all.first(where: { $0.id == heroID }) { return chosen }
        if let running = host?.runningGame { return running }
        if let last = StarwireSettings.lastPlayed(hostUUID: hostID), let game = all.first(where: { $0.id == last }) {
            return game
        }
        return games.first
    }

    var body: some View {
        ZStack {
            StarfieldBackground(cover: CoverCache.shared.palette(hero?.coverPath), paused: state.isStreaming)
                .ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        topBar
                        if let host {
                            if let hero {
                                HeroView(host: host, game: hero, onPlay: { tapped(hero) },
                                         onSettings: { state.path.append(.gameSettings(hostID: hostID, appID: hero.id)) })
                            }
                            QuickLaunchRow(currentHostID: hostID)
                            OverridesBar()
                            tilesSection(title: L("ios_on_pc", host.name), items: games, id: "games")
                            if !remoteTiles.isEmpty {
                                tilesSection(title: L("ios_vibeshine_remote"), items: remoteTiles, id: "remote")
                            }
                            if games.isEmpty && remoteTiles.isEmpty {
                                Text(L("ios_no_apps"))
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        } else {
                            Text(L("ios_pc_gone"))
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
                .onChange(of: state.focus.focused) { _, id in
                    if let id, id.hasPrefix("tile-") {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("games-\(hostID)") { dismiss() }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Label(host?.name ?? L("ios_back"), systemImage: "chevron.left")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("ios_back_to_pcs"))
            .controllerFocusable("games-back", cornerRadius: 22) { dismiss() }
            Spacer()
            if sizeClass == .regular {
                RainbowWordmark(paused: state.isStreaming)
                    .accessibilityHidden(true)
                Spacer()
            }
            Button { showHidden.toggle() } label: {
                Image(systemName: showHidden ? "eye.fill" : "eye.slash")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showHidden ? L("ios_hide_hidden_apps") : L("ios_show_hidden_apps"))
            .controllerFocusable("games-hidden", cornerRadius: 22) { showHidden.toggle() }
            Button { state.path.append(.settings(section: nil)) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("ios_settings_title"))
            .controllerFocusable("games-settings", cornerRadius: 22) { state.path.append(.settings(section: nil)) }
        }
        // The bar's buttons grow with the text only so far, so they keep fitting on a narrow screen
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.top, 8)
    }

    private func tilesSection(title: String, items: [GameItem], id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 128 : 104), spacing: 14)],
                      alignment: .leading, spacing: 14) {
                ForEach(items) { game in
                    GameTile(game: game, running: host?.runningAppID == game.id, paused: state.isStreaming,
                             open: { tapped(game) }, menu: { appMenu(game) })
                        .id("tile-\(game.id)")
                }
            }
        }
    }

    private func refresh() async {
        guard !state.isStreaming else { return }
        _ = await library.backend.refresh(hostID)
        library.reload()
    }

    // MARK: - Starting a game

    private func tapped(_ game: GameItem) {
        guard let host else { return }
        heroID = game.kind == .game ? game.id : heroID
        // Vibeshine's control tiles start at once: they work next to the running game, and the PC
        // asks when something needs confirming
        if let running = host.runningGame, !game.isControlTile {
            runningMenu(game: game, running: running)
        } else {
            state.startStream(hostID: hostID, appID: game.id)
        }
    }

    /// Another or the same game runs on the PC: resume it, or quit it first.
    private func runningMenu(game: GameItem, running: GameItem) {
        let same = running.id == game.id
        var buttons = [
            PanelButton(title: L("applist_menu_resume")) {
                state.startStream(hostID: hostID, appID: running.id, resume: true)
            },
            PanelButton(title: same ? L("applist_menu_quit") : L("applist_menu_quit_and_start"), role: .destructive) {
                quit(thenStart: same ? nil : game)
            },
        ]
        buttons.append(PanelButton(title: L("applist_menu_cancel"), role: .cancel))
        state.show(PanelContent(title: game.name, message: same ? nil : L("ios_is_running", running.name), buttons: buttons))
    }

    private func quit(thenStart next: GameItem?) {
        state.busy = L("applist_quit_app")
        Task {
            let error = await library.backend.quitApp(on: hostID)
            state.busy = nil
            library.reload()
            if let error {
                state.message(L("applist_quit_fail"), error)
            } else if let next {
                state.startStream(hostID: hostID, appID: next.id)
            }
        }
    }

    private func appMenu(_ game: GameItem) {
        guard let host else { return }
        heroID = game.kind == .game ? game.id : heroID
        var buttons: [PanelButton] = []
        if let running = host.runningGame {
            buttons.append(PanelButton(title: running.id == game.id ? L("applist_menu_resume") : L("ios_resume_running", running.name)) {
                state.startStream(hostID: hostID, appID: running.id, resume: true)
            })
            buttons.append(PanelButton(title: running.id == game.id ? L("applist_menu_quit") : L("applist_menu_quit_and_start"),
                                       role: .destructive) {
                quit(thenStart: running.id == game.id ? nil : game)
            })
        } else {
            buttons.append(PanelButton(title: L("ios_start")) { state.startStream(hostID: hostID, appID: game.id) })
        }
        if !game.isControlTile && host.runningGame == nil {
            buttons.append(PanelButton(title: L("applist_menu_start_vdisplay")) {
                state.startStream(hostID: hostID, appID: game.id, displayMode: .virtual)
            })
            buttons.append(PanelButton(title: L("applist_menu_start_primarydisplay")) {
                state.startStream(hostID: hostID, appID: game.id, displayMode: .primary)
            })
        }
        if !game.isControlTile {
            buttons.append(PanelButton(title: L("ios_game_settings_title")) {
                state.path.append(.gameSettings(hostID: hostID, appID: game.id))
            })
            buttons.append(PanelButton(title: L("applist_menu_add_quick_launch")) {
                QuickLaunchModel.shared.add(host: host, game: game)
                state.message(game.name, L("quick_launch_added"))
            })
        }
        buttons.append(PanelButton(title: game.hidden ? L("ios_show_app") : L("applist_menu_hide_app")) {
            library.backend.setHidden(!game.hidden, appID: game.id, on: hostID)
            library.reload()
        })
        buttons.append(PanelButton(title: L("applist_menu_details")) {
            let lines = [
                L("ios_detail_name") + ": " + game.name,
                L("applist_details_id") + " " + game.id,
                L("ios_detail_hdr") + ": " + (game.hdrSupported ? L("ios_yes") : L("ios_no")),
            ]
            state.message(L("applist_menu_details"), lines.joined(separator: "\n"))
        })
        buttons.append(PanelButton(title: L("applist_menu_cancel"), role: .cancel))
        state.show(PanelContent(title: game.name, message: game.hidden ? L("ios_hidden") : nil, buttons: buttons))
    }
}

/// The game at the top: its cover, name, what the stream will be, Play, and its settings.
struct HeroView: View {
    let host: PCItem
    let game: GameItem
    let onPlay: () -> Void
    let onSettings: () -> Void
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let layout = sizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
        layout {
            AppTileView(name: game.name, cover: CoverCache.shared.image(game.coverPath), showsName: false,
                        paused: state.isStreaming)
                .frame(width: sizeClass == .regular ? 180 : 120, height: sizeClass == .regular ? 240 : 160)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(host.runningAppID == game.id ? L("ios_running_now") : L("ios_last_played"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(game.name)
                    .font(.largeTitle.weight(.heavy))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                ChipRow(chips)
                // Side by side when they fit, else one above the other
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { heroButtons }
                    VStack(alignment: .leading, spacing: 12) { heroButtons }
                }
            }
        }
        .animation(.easeInOut(duration: StarfieldBackground.tintSeconds), value: game.id)
    }

    @ViewBuilder
    private var heroButtons: some View {
        Button(action: onPlay) {
            Label(host.runningAppID == game.id ? L("applist_menu_resume") : L("ios_play"), systemImage: "play.fill")
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 26)
                .frame(minHeight: 52)
                .foregroundStyle(.black)
                .background(Color.white, in: Capsule())
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hero-play")
        .controllerFocusable("hero-play", cornerRadius: 26, action: onPlay)
        Button(action: onSettings) {
            Text(L("ios_this_games_settings"))
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .frame(minHeight: 52)
                .background(Color.white.opacity(0.14), in: Capsule())
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(.plain)
        .controllerFocusable("hero-settings", cornerRadius: 26, action: onSettings)
    }

    /// Codec, resolution and frame rate, and HDR, from the settings this game streams with
    private var chips: [String] {
        let store = StarwireSettings.savedStore
        let values = store.effectiveValues(for: StarwireSettings.gameSettings.settings(hostUUID: host.id, appID: game.id))
        func string(_ key: String) -> String {
            if case .string(let value)? = values[key] { return value }
            return ""
        }
        var chips: [String] = []
        switch string("video_format") {
        case "forceav1": chips.append("AV1")
        case "forceh265": chips.append("HEVC")
        case "neverh265": chips.append("H.264")
        default: chips.append(L("ios_codec_auto"))
        }
        let height = SettingsStore.parseResolution(string("list_resolution"))?.1 ?? 720
        let fps = Double(string("list_fps")).map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? "60"
        chips.append("\(height)p · \(fps) FPS")
        if values["checkbox_enable_hdr"] == .bool(true) && game.hdrSupported {
            chips.append("HDR")
        }
        return chips
    }
}

/// One game or Remote tile.
struct GameTile: View {
    let game: GameItem
    let running: Bool
    let paused: Bool
    let open: () -> Void
    let menu: () -> Void

    var body: some View {
        AppTileView(name: game.name, cover: CoverCache.shared.image(game.coverPath), isSelected: running, paused: paused)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .opacity(game.hidden ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: AppTileView.cornerRadius))
            .onTapGesture(perform: open)
            .onLongPressGesture(minimumDuration: 0.5, perform: menu)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(game.name)
            .accessibilityValue(running ? L("ios_running_now") : (game.hidden ? L("ios_hidden") : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            .accessibilityAction(named: L("ios_app_menu"), menu)
            .accessibilityIdentifier("tile-\(game.name)")
            .controllerFocusable("tile-\(game.id)", cornerRadius: AppTileView.cornerRadius, menu: menu, action: open)
    }

}
