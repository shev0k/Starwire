//
//  GameSettingsScreen.swift
//  Starwire
//
//  One game's own settings (Android's AppSettingsActivity, app_preferences.xml), or a Quick Launch
//  entry's: each list has "Use the global setting" first, and a switch makes the game follow the
//  global settings again without losing its own. Saved by StarwireKit's GameSettingsStore with
//  Android's JSON.
//

import StarwireKit
import SwiftUI

struct GameSettingsScreen: View {
    let hostID: String
    /// The app's id, or "quicklaunch:<key>" for a Quick Launch entry's settings
    let appID: String
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var settings = GameSettings()
    @State private var loaded = false
    @State private var typed = ""

    private var quickLaunchKey: String? {
        appID.hasPrefix("quicklaunch:") ? String(appID.dropFirst("quicklaunch:".count)) : nil
    }

    private var storeKey: String {
        quickLaunchKey ?? GameSettings.key(hostUUID: hostID, appID: appID)
    }

    private var title: String {
        if let quickLaunchKey {
            return StarwireSettings.quickLaunch.entry(forKey: quickLaunchKey)?.displayNameLong ?? L("quick_launch_settings")
        }
        return library.host(hostID)?.games.first { $0.id == appID }?.name ?? L("ios_game_settings_title")
    }

    private var defaultEntry: String {
        L(quickLaunchKey != nil ? GameSettingsLayout.quickLaunchDefaultEntryKey : GameSettingsLayout.defaultEntryKey)
    }

    var body: some View {
        ZStack {
            StarfieldBackground(paused: state.isStreaming)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: title)
                Text(L("ios_game_settings_title"))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 20)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(GameSettingsLayout.groups) { group in
                            if let titleKey = group.titleKey {
                                Text(L(titleKey))
                                    .font(.headline)
                                    .padding(.top, 18)
                                    .padding(.bottom, 6)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(group.items) { item in
                                row(item)
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("game-settings") { dismiss() }
        .onAppear {
            if !loaded {
                settings = StarwireSettings.gameSettings.settings(forKey: storeKey)
                loaded = true
            }
        }
    }

    private func save() {
        StarwireSettings.gameSettings.set(settings, forKey: storeKey)
    }

    @ViewBuilder
    private func row(_ item: SettingsItem) -> some View {
        let isUseGlobal = item.id == GameSettingsLayout.useGlobalKey
        let enabled = isUseGlobal || !settings.useGlobalSettings
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(isUseGlobal && quickLaunchKey != nil ? GameSettingsLayout.quickLaunchUseGlobalTitleKey : item.titleKey))
                        .font(.headline)
                    if let summary = isUseGlobal && quickLaunchKey != nil
                        ? GameSettingsLayout.quickLaunchUseGlobalSummaryKey : item.summaryKey {
                        Text(L(summary))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                control(item)
            }
        }
        .padding(.vertical, 12)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .controllerFocusable("game-setting-\(item.id)", cornerRadius: 12) { controllerAction(item) }
    }

    @ViewBuilder
    private func control(_ item: SettingsItem) -> some View {
        switch item.control {
        case .toggle:
            Toggle(L(item.titleKey), isOn: Binding(get: { settings.useGlobalSettings }, set: {
                settings.useGlobalSettings = $0
                save()
            }))
            .labelsHidden()
            .tint(Color(red: 0.6, green: 0.45, blue: 1))
        case .list(let entries, let values, let allowsCustom):
            let current = value(of: item.id)
            Menu {
                Button(defaultEntry) { setValue(nil, for: item.id) }
                ForEach(values.indices, id: \.self) { i in
                    Button(L(entries[i])) { setValue(values[i], for: item.id) }
                }
                if allowsCustom {
                    Button(L("ios_custom_value")) { askText(item) }
                }
            } label: {
                listLabel(current.flatMap { value in values.firstIndex(of: value).map { L(entries[$0]) } ?? value }
                          ?? defaultEntry)
            }
            .accessibilityLabel(L(item.titleKey))
        case .text:
            Button { askText(item) } label: {
                listLabel(value(of: item.id) ?? defaultEntry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(item.titleKey))
        default:
            EmptyView()
        }
    }

    private func listLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    // MARK: - Values

    /// The game's value for a row, as text, or nil for "use the global setting"
    private func value(of id: String) -> String? {
        switch id {
        case "list_app_resolution": return settings.resolution
        case "list_app_fps": return settings.fps > 0 ? String(settings.fps) : nil
        case "text_app_bitrate_kbps": return settings.bitrate > 0 ? "\(settings.bitrate / 1000) Mbps" : nil
        case "list_app_frame_pacing": return settings.framePacing
        case "text_app_actual_display_refresh_rate":
            return settings.actualDisplayRefreshRate > 0 ? String(settings.actualDisplayRefreshRate) : nil
        case "list_app_enable_hdr": return settings.enableHdr
        case "list_app_enable_perf_overlay": return settings.enablePerfOverlay
        default:
            guard let key = GameSettingsLayout.item(id)?.overrides else { return nil }
            return settings.gameOptions[key]
        }
    }

    private func setValue(_ value: String?, for id: String) {
        switch id {
        case "list_app_resolution": settings.resolution = value
        case "list_app_fps": settings.fps = value.flatMap { Int($0) } ?? 0
        case "text_app_bitrate_kbps":
            settings.bitrate = value.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
                .map { Int(($0 * 1000).rounded()) } ?? 0
        case "list_app_frame_pacing": settings.framePacing = value
        case "text_app_actual_display_refresh_rate":
            settings.actualDisplayRefreshRate = value.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
        case "list_app_enable_hdr": settings.enableHdr = value
        case "list_app_enable_perf_overlay": settings.enablePerfOverlay = value
        default:
            guard let key = GameSettingsLayout.item(id)?.overrides else { return }
            settings.gameOptions[key] = value
        }
        save()
    }

    private func askText(_ item: SettingsItem) {
        typed = ""
        state.show(PanelContent(title: L(item.titleKey),
                                message: item.id == "text_app_bitrate_kbps" ? L("ios_bitrate_in_mbps") : L("ios_custom_value_help"),
                                textField: (defaultEntry, $typed, .numbersAndPunctuation),
                                buttons: [
                                    PanelButton(title: L("ios_ok")) {
                                        let text = typed.trimmingCharacters(in: .whitespaces)
                                        setValue(text.isEmpty ? nil : text, for: item.id)
                                    },
                                    PanelButton(title: defaultEntry) { setValue(nil, for: item.id) },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }

    /// A on a controller: the choices as a panel
    private func controllerAction(_ item: SettingsItem) {
        switch item.control {
        case .toggle:
            settings.useGlobalSettings.toggle()
            save()
        case .list(let entries, let values, _):
            guard !settings.useGlobalSettings else { return }
            var buttons = [PanelButton(title: defaultEntry) { setValue(nil, for: item.id) }]
            buttons += values.indices.map { i in PanelButton(title: L(entries[i])) { setValue(values[i], for: item.id) } }
            buttons.append(PanelButton(title: L("applist_menu_cancel"), role: .cancel))
            state.show(PanelContent(title: L(item.titleKey), buttons: buttons))
        case .text:
            if !settings.useGlobalSettings { askText(item) }
        default:
            break
        }
    }
}
