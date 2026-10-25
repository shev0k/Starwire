//
//  QuickLaunchViews.swift
//  Starwire
//
//  The game screen's Quick Launch row (games pinned from any PC) and the overrides bar (bitrate,
//  statistics overlay and codec for every stream until turned off), from Starwire for Android's
//  QuickLaunchView and OverridesView (GPL-3.0). The rules and saving are StarwireKit's
//  QuickLaunchStore and StreamOverridesStore.
//

import StarwireKit
import SwiftUI

@MainActor
final class QuickLaunchModel: ObservableObject {
    static let shared = QuickLaunchModel()
    @Published private(set) var entries: [QuickLaunchEntry] = []
    private let store = StarwireSettings.quickLaunch

    init() {
        entries = store.entries()
    }

    func reload() {
        entries = store.entries()
    }

    func add(host: PCItem, game: GameItem) {
        _ = store.add(computerUUID: host.id, computerName: host.name, appID: Int(game.id) ?? 0, appName: game.name)
        reload()
    }

    func remove(_ entry: QuickLaunchEntry) {
        store.remove(key: entry.key)
        reload()
    }

    func rename(_ entry: QuickLaunchEntry, to name: String) {
        _ = store.rename(key: entry.key, to: name)
        reload()
    }

    func move(_ entry: QuickLaunchEntry, left: Bool) {
        if left {
            _ = store.moveLeft(key: entry.key)
        } else {
            _ = store.moveRight(key: entry.key)
        }
        reload()
    }
}

struct QuickLaunchRow: View {
    let currentHostID: String
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: Library
    @ObservedObject private var model = QuickLaunchModel.shared
    @State private var newName = ""

    var body: some View {
        if !model.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L(QuickLaunchText.sectionTitle.rawValue))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.entries, id: \.key) { entry in
                            chip(entry)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func chip(_ entry: QuickLaunchEntry) -> some View {
        let host = library.host(entry.computerUUID)
        let running = host?.runningAppID == String(entry.appID)
        return Text(entry.computerUUID == currentHostID ? entry.displayName : entry.displayNameLong)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(running ? Color.green.opacity(0.35) : Color.white.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { start(entry) }
            .onLongPressGesture(minimumDuration: 0.5) { menu(entry) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.displayNameLong)
            .accessibilityValue(running ? L("ios_running_now") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { start(entry) }
            .accessibilityAction(named: L("ios_app_menu")) { menu(entry) }
            .controllerFocusable("quick-\(entry.key)", cornerRadius: 24, menu: { menu(entry) }) { start(entry) }
    }

    private func start(_ entry: QuickLaunchEntry) {
        guard let host = library.host(entry.computerUUID) else {
            state.message(entry.displayNameLong, L(QuickLaunchText.pcNotFound.rawValue))
            return
        }
        let appID = String(entry.appID)
        if let running = host.runningGame, running.id != appID {
            state.show(PanelContent(title: entry.displayName, message: L("ios_is_running", running.name), buttons: [
                PanelButton(title: L("applist_menu_resume")) {
                    state.startStream(hostID: host.id, appID: running.id, resume: true)
                },
                PanelButton(title: L("applist_menu_quit_and_start"), role: .destructive) {
                    Task {
                        if let error = await library.backend.quitApp(on: host.id) {
                            state.message(L("applist_quit_fail"), error)
                        } else {
                            state.startStream(hostID: host.id, appID: appID, quickLaunchKey: entry.key)
                        }
                    }
                },
                PanelButton(title: L("applist_menu_cancel"), role: .cancel),
            ]))
        } else {
            state.startStream(hostID: host.id, appID: appID, quickLaunchKey: entry.key,
                              resume: host.runningAppID == appID)
        }
    }

    private func menu(_ entry: QuickLaunchEntry) {
        var buttons = [
            PanelButton(title: L(QuickLaunchText.rename.rawValue)) { rename(entry) },
            PanelButton(title: L(QuickLaunchText.settings.rawValue)) {
                state.path.append(.gameSettings(hostID: entry.computerUUID, appID: "quicklaunch:" + entry.key))
            },
        ]
        if model.entries.first?.key != entry.key {
            buttons.append(PanelButton(title: L(QuickLaunchText.moveLeft.rawValue)) { model.move(entry, left: true) })
        }
        if model.entries.last?.key != entry.key {
            buttons.append(PanelButton(title: L(QuickLaunchText.moveRight.rawValue)) { model.move(entry, left: false) })
        }
        buttons.append(PanelButton(title: L(QuickLaunchText.delete.rawValue), role: .destructive) { model.remove(entry) })
        buttons.append(PanelButton(title: L("applist_menu_cancel"), role: .cancel))
        state.show(PanelContent(title: entry.displayNameLong, buttons: buttons))
    }

    private func rename(_ entry: QuickLaunchEntry) {
        newName = entry.displayName
        state.show(PanelContent(title: L(QuickLaunchText.renameTitle.rawValue),
                                message: L(QuickLaunchText.renameMessage.rawValue),
                                textField: (entry.originalAppName, $newName, .default),
                                buttons: [
                                    PanelButton(title: L("ios_ok")) { model.rename(entry, to: newName) },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }
}

/// The overrides bar: off by default; its switch shows the bitrate slider and the statistics and
/// codec buttons, which then apply to every stream started from here.
struct OverridesBar: View {
    @EnvironmentObject private var state: AppState
    @State private var overrides = StarwireSettings.overrides.overrides
    @State private var position = StarwireSettings.overrides.sliderPosition
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .accessibilityHidden(true)
                    Text(L(OverrideText.sectionTitle.rawValue))
                        .font(.headline)
                    Image(systemName: overrides.enabled ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(OverrideText.toggleDescription.rawValue))
            .accessibilityValue(overrides.enabled ? L("ios_on") : L("ios_off"))
            .controllerFocusable("overrides-toggle", cornerRadius: 12, action: toggle)
            if overrides.enabled {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { controls }
                    VStack(alignment: .leading, spacing: 10) { controls }
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        Button(text(overrides.statsOverlayLabel)) { cycle { $0.cycleStatsOverlay() } }
            .buttonStyle(OverrideChipStyle())
            .controllerFocusable("overrides-stats", cornerRadius: 22) { cycle { $0.cycleStatsOverlay() } }
        Button(text(overrides.codecLabel)) { cycle { $0.cycleCodec() } }
            .buttonStyle(OverrideChipStyle())
            .controllerFocusable("overrides-codec", cornerRadius: 22) { cycle { $0.cycleCodec() } }
        HStack(spacing: 10) {
            Button(text(StreamOverrides.sliderLabel(position: position))) { askBitrate() }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
            Slider(value: Binding(get: { Double(position) }, set: { setPosition(Int($0.rounded())) }),
                   in: 0...Double(StreamOverridesStore.sliderMaximum), step: 1)
                .frame(minWidth: 160)
                .accessibilityLabel(L(OverrideText.bitrateTitle.rawValue))
                .accessibilityValue(text(StreamOverrides.sliderLabel(position: position)))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.12), in: Capsule())
        .controllerFocusable("overrides-bitrate", cornerRadius: 22) {
            setPosition(position >= StreamOverridesStore.sliderMaximum ? 0 : position + 1)
        }
    }

    private func text(_ label: OverrideLabel) -> String {
        label.number.map { L(label.resourceName, $0) } ?? L(label.resourceName)
    }

    private func toggle() {
        let store = StarwireSettings.overrides
        store.toggleEnabled()
        overrides = store.overrides
    }

    private func cycle(_ change: (StreamOverridesStore) -> Void) {
        let store = StarwireSettings.overrides
        change(store)
        overrides = store.overrides
        position = store.sliderPosition
    }

    private func setPosition(_ value: Int) {
        let store = StarwireSettings.overrides
        store.setSliderPosition(value)
        position = store.sliderPosition
        overrides = store.overrides
    }

    private func askBitrate() {
        typed = overrides.bitrateKbps > 0 ? String(overrides.bitrateKbps / 1000) : ""
        state.show(PanelContent(title: L(OverrideText.bitrateDialogTitle.rawValue),
                                message: L(OverrideText.bitrateDialogMessage.rawValue, StreamOverridesStore.maximumBitrateMbps),
                                textField: ("0", $typed, .numberPad),
                                buttons: [
                                    PanelButton(title: L("ios_ok")) {
                                        let store = StarwireSettings.overrides
                                        let result = store.setBitrate(fromText: typed)
                                        overrides = store.overrides
                                        position = store.sliderPosition
                                        switch result {
                                        case .clamped:
                                            state.message(L(OverrideText.bitrateDialogTitle.rawValue),
                                                          L(OverrideText.bitrateMaximum.rawValue, StreamOverridesStore.maximumBitrateMbps))
                                        case .invalid:
                                            state.message(L(OverrideText.bitrateDialogTitle.rawValue),
                                                          L(OverrideText.invalidNumber.rawValue))
                                        case .ignored, .saved:
                                            break
                                        }
                                    },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }
}

struct OverrideChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.white.opacity(configuration.isPressed ? 0.25 : 0.12), in: Capsule())
    }
}
