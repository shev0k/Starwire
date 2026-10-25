//
//  SettingsScreen.swift
//  Starwire
//
//  Every setting, drawn from StarwireKit's SettingsLayout: Android's sections as pills, its plain
//  names and summaries, the "Impact:" lines, the credits for settings from other forks, and the
//  predicted-impact panel beside the Stream section on wide screens. Settings iOS can't use or
//  Vibeshine doesn't have are left out. The values go to the saved store; the stream reads them
//  through StarwireSettings.
//

import AVFoundation
import AVKit
import CoreHaptics
import CoreMotion
import StarwireKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The saved settings, for the screens that change them.
@MainActor
final class SettingsModel: ObservableObject {
    let store: SettingsStore
    @Published private(set) var revision = 0

    init(store: SettingsStore = StarwireSettings.savedStore) {
        self.store = store
    }

    func value(_ key: String) -> SettingValue? {
        store.value(key)
    }

    func bool(_ key: String) -> Bool {
        if case .bool(let value)? = store.value(key) { return value }
        return false
    }

    func int(_ key: String) -> Int {
        if case .int(let value)? = store.value(key) { return value }
        return 0
    }

    func string(_ key: String) -> String {
        if case .string(let value)? = store.value(key) { return SettingsLayout.normalizedValue(value, for: key) }
        return ""
    }

    func set(_ value: SettingValue, for key: String) {
        try? store.set(value, for: key)
        StarwireSettings.reload()
        revision += 1
    }

    func reset(_ key: String) {
        store.reset(key)
        StarwireSettings.reload()
        revision += 1
    }

    /// Whether a requirement holds now.
    func holds(_ requirement: SettingRequirement?) -> Bool {
        switch requirement {
        case nil:
            return true
        case .value(let key, let values)?:
            if case .bool(let on)? = store.value(key) {
                return values.contains(on ? "true" : "false")
            }
            return values.contains(string(key))
        case .device(let feature)?:
            return Self.deviceHas(feature)
        }
    }

    static func deviceHas(_ feature: DeviceFeature) -> Bool {
        switch feature {
        case .vibration: return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        case .hdrDisplay: return AVPlayer.availableHDRModes.contains(.hdr10)
        case .motionSensors: return CMMotionManager().isDeviceMotionAvailable
        case .pictureInPicture: return AVPictureInPictureController.isPictureInPictureSupported()
        case .touchscreen: return true
        }
    }

    /// Shown, its group shown, and its show-when holds
    func isVisible(_ item: SettingsItem) -> Bool {
        item.isShown && holds(item.showWhen)
    }

    /// Its dependency is on and its enabled-when holds
    func isEnabled(_ item: SettingsItem) -> Bool {
        (item.dependency.map { bool($0) } ?? true) && holds(item.enabledWhen)
    }
}

struct SettingsScreen: View {
    let initialSection: String?
    /// Only these sections (the stream menu's More settings); nil for all
    var only: [String]? = nil
    /// Closes the screen when it isn't in a navigation stack (over a stream)
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SettingsModel()
    @State private var section = SettingsLayout.sections[0].id
    @State private var exporting: SettingsDocument?
    @State private var importing = false
    @State private var query = ""

    private var sections: [SettingsSection] {
        guard let only else { return SettingsLayout.sections }
        return SettingsLayout.sections.filter { only.contains($0.id) }
    }

    private var current: SettingsSection {
        sections.first { $0.id == section } ?? sections[0]
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    /// An SF Symbol for each section, for the sidebar
    static func symbol(_ id: String) -> String {
        switch id {
        case "stream": return "play.rectangle"
        case "sound": return "speaker.wave.2"
        case "controllers": return "gamecontroller"
        case "menu": return "list.bullet.rectangle"
        case "touch": return "hand.tap"
        case "keyboard": return "keyboard"
        case "onscreen": return "circle.grid.cross"
        case "pc": return "desktopcomputer"
        case "app": return "app.badge"
        case "advanced": return "wrench.and.screwdriver"
        case "about": return "info.circle"
        default: return "gearshape"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StarfieldBackground(paused: state.isStreaming)
                    .ignoresSafeArea()
                // A sidebar beside the settings where there's room; pills above them where not
                if geometry.size.width >= 760 {
                    HStack(alignment: .top, spacing: 0) {
                        sidebar
                            .frame(width: 270)
                        content(width: geometry.size.width - 270)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ScreenHeader(title: L("ios_settings_title"), showsBack: onClose == nil) { closeButton }
                        searchField.padding(.horizontal, 20)
                        if query.isEmpty { pills }
                        content(width: geometry.size.width)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("settings") { close() }
        .onAppear {
            if let initialSection, sections.contains(where: { $0.id == initialSection }) {
                section = initialSection
            } else {
                section = sections[0].id
            }
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                      document: exporting, contentType: .json, defaultFilename: "starwire-settings") { result in
            if case .failure(let error) = result {
                state.message(L("ios_settings_export"), error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importSettings(result)
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if onClose != nil {
            Button(L("ios_done")) { close() }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.49, green: 0.23, blue: 0.93))
                .accessibilityIdentifier("settings-done")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if onClose == nil {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("ios_back"))
                    .controllerFocusable("header-back", cornerRadius: 22) { dismiss() }
                }
                Text(L("ios_settings_title"))
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                closeButton
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            searchField
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(sections) { item in
                        sidebarButton(item)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 12)
    }

    private func sidebarButton(_ item: SettingsSection) -> some View {
        let selected = query.isEmpty && section == item.id
        return Button {
            query = ""
            section = item.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: Self.symbol(item.id))
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color(red: 0.49, green: 0.23, blue: 0.93) : Color.white.opacity(0.10)))
                    .foregroundStyle(.white)
                Text(L(item.titleKey))
                    .font(.body.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? .black : .white)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? Color.white : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("pill-\(item.id)")
        .controllerFocusable("pill-\(item.id)", cornerRadius: 14) {
            query = ""
            section = item.id
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField(L("ios_settings_search"), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings-search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("ios_settings_search_clear"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.10)))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Content

    /// Rows whose name or summary has every search word, by section
    private var results: [(section: SettingsSection, groups: [SettingsGroup])] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return sections.compactMap { section in
            let groups = section.groups.compactMap { group -> SettingsGroup? in
                let found = group.keeping { item in
                    let text = (L(item.titleKey) + " " + (item.summaryKey.map { L($0) } ?? "")).lowercased()
                    return words.allSatisfy { text.contains($0) }
                }
                return found.items.isEmpty ? nil : found
            }
            return groups.isEmpty ? nil : (section, groups)
        }
    }

    private func content(width: CGFloat) -> some View {
        let wide = width >= CGFloat(SettingsFeel.panelMinWidth) && section == "stream" && query.isEmpty
        return HStack(alignment: .top, spacing: 20) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if query.isEmpty {
                            Text(L(current.titleKey))
                                .font(.title.weight(.heavy))
                                .foregroundStyle(.white)
                                .accessibilityAddTraits(.isHeader)
                                .id("top")
                            if !wide && section == "stream" {
                                PredictedImpactPanel(model: model)
                            }
                            ForEach(current.groups) { group in
                                groupView(group, sectionTitle: L(current.titleKey))
                            }
                            if section == "app" {
                                transferButtons
                            }
                        } else {
                            let found = results
                            if found.isEmpty {
                                Text(L("ios_settings_search_none"))
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.8))
                                    .id("top")
                            }
                            ForEach(found, id: \.section.id) { entry in
                                ForEach(entry.groups) { group in
                                    groupView(group, sectionTitle: L(entry.section.titleKey))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .onChange(of: section) { _, _ in proxy.scrollTo("top", anchor: .top) }
                .onChange(of: state.focus.focused) { _, id in
                    if let id, id.hasPrefix("setting-") {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            if wide {
                ScrollView {
                    PredictedImpactPanel(model: model)
                        .frame(width: 340)
                }
                .padding(.trailing, 20)
                .padding(.top, 12)
            }
        }
    }

    @Environment(\.layoutDirection) private var layoutDirection

    private var pills: some View {
        // They wrap rather than scroll, so every section is in reach at once
        WrappingLayout(spacing: 10, rightToLeft: layoutDirection == .rightToLeft) {
                ForEach(sections) { item in
                    Button { section = item.id } label: {
                        Text(L(item.titleKey))
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .foregroundStyle(section == item.id ? .black : .white)
                            .background(section == item.id ? Color.white : Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(section == item.id ? [.isSelected] : [])
                    .accessibilityIdentifier("pill-\(item.id)")
                    .controllerFocusable("pill-\(item.id)", cornerRadius: 22) { section = item.id }
                }
        }
        // The section buttons grow with the text only so far, so the settings stay in view
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    /// A group's rows on one frosted card, under the group's name (or the section's)
    @ViewBuilder
    private func groupView(_ group: SettingsGroup, sectionTitle: String) -> some View {
        let items = group.items.filter { model.isVisible($0) }
        if model.holds(group.showWhen) && !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text((group.titleKey.map { L($0) } ?? sectionTitle).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.99))
                    .padding(.leading, 6)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SettingRow(item: item, model: model, perform: perform)
                            .padding(.horizontal, 16)
                            .id("setting-\(item.id)")
                        if index < items.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 16)
                        }
                    }
                }
                .frostedCard(cornerRadius: 20, padding: 0)
            }
        }
    }

    private var transferButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("ios_settings_transfer"))
                .font(.headline)
                .padding(.top, 14)
            HStack(spacing: 12) {
                Button(L("ios_settings_export")) { exportSettings() }
                    .buttonStyle(.bordered)
                    .controllerFocusable("settings-export") { exportSettings() }
                Button(L("ios_settings_import")) { importing = true }
                    .buttonStyle(.bordered)
                    .controllerFocusable("settings-import") { importing = true }
            }
            Text(L("ios_settings_transfer_help"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
        }
    }

    // MARK: - Actions

    private func perform(_ action: String) {
        switch action {
        case "pair_microphone":
            state.path.append(.micPairing(hostID: nil))
        case "open_custom_commands", "import_shortcuts", "clear_imported_shortcuts":
            if let top = AppState.topViewController() {
                presentShortcutsManager(from: top) {}
            }
        case "reset_onscreen_controls_layout":
            OnScreenLayoutStore(store: StarwireSettings.savedStore).reset()
            state.message(L("title_reset_osc"), L("ios_osc_reset_done"))
        case "copy_version":
            UIPasteboard.general.string = AboutScreen.versionDetails
            state.message(L("title_about_version"), L("about_copied"))
        case "open_source", "show_credits":
            state.path.append(.about)
        case "show_licences":
            state.path.append(.licences)
        default:
            if let url = URL(string: action), action.hasPrefix("https://") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func exportSettings() {
        do {
            let data = try SettingsJSON.export(StarwireSettings.savedStore)
            exporting = SettingsDocument(data: data)
        } catch {
            state.message(L("ios_settings_export"), error.localizedDescription)
        }
    }

    private func importSettings(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let report = try SettingsJSON.import(Data(contentsOf: url), into: StarwireSettings.savedStore,
                                                 games: StarwireSettings.gameSettings)
            StarwireSettings.reload()
            model.set(model.value("list_fps") ?? .string("60"), for: "list_fps")
            state.message(L("ios_settings_import"), L("ios_settings_imported", String(describing: report)))
        } catch {
            state.message(L("ios_settings_import"), error.localizedDescription)
        }
    }
}

/// The settings as a JSON file for the Files app.
struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// One setting: its name, summary, impact line and credit, with its control.
struct SettingRow: View {
    let item: SettingsItem
    @ObservedObject var model: SettingsModel
    let perform: (String) -> Void
    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let enabled = model.isEnabled(item)
        let stacked = typeSize.isAccessibilitySize
        Group {
            if stacked || isWideControl {
                VStack(alignment: .leading, spacing: 10) {
                    texts
                    control
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    texts
                    Spacer(minLength: 12)
                    control
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .controllerFocusable("setting-\(item.id)", cornerRadius: 12) { controllerAction() }
    }

    private var isWideControl: Bool {
        if case .slider = item.control { return true }
        if case .text = item.control { return true }
        return false
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(item.titleKey))
                .font(.headline)
            if let summary = summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
            }
            if let impact = item.impactKey {
                (Text(L(SettingsImpact.labelKey) + " ").bold().foregroundColor(Color(red: 0.75, green: 0.6, blue: 1))
                    + Text(L(impact)))
                    .font(.footnote)
            }
            if let credit = item.credit {
                Text(credit.text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var summary: String? {
        if item.summaryShowsChoice, case .list(let entries, let values, _) = item.control,
           let index = values.firstIndex(of: model.string(item.id)) {
            return L(entries[index])
        }
        return item.summaryKey.map { L($0) }
    }

    @ViewBuilder
    private var control: some View {
        if item.id == "list_languages" {
            // iOS keeps each app's language in its own page in iOS Settings
            Button(L("ios_open_language_settings")) { openLanguageSettings() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("setting-\(item.id)")
        } else {
            standardControl
        }
    }

    private func openLanguageSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    @ViewBuilder
    private var standardControl: some View {
        switch item.control {
        case .toggle:
            Toggle(L(item.titleKey), isOn: Binding(get: { model.bool(item.id) }, set: { setToggle($0) }))
                .labelsHidden()
                .tint(Color(red: 0.6, green: 0.45, blue: 1))
                .accessibilityIdentifier("setting-\(item.id)")
        case .list(let entries, let values, let allowsCustom):
            listMenu(entries: entries, values: values, allowsCustom: allowsCustom)
        case .dynamicList(let defaultEntry):
            MicrophoneDevicePicker(key: item.id, defaultEntry: defaultEntry, model: model)
        case .slider(let range, let step, let divisor, let unitKey, let allowsCustom):
            SettingSlider(key: item.id, title: L(item.titleKey), range: range, step: step, divisor: divisor,
                          unit: unitKey.map { L($0) }, allowsCustom: allowsCustom, model: model)
        case .text(let input, let maxLength):
            SettingTextField(key: item.id, title: L(item.titleKey), input: input, maxLength: maxLength, model: model)
        case .action(let action):
            Button(L("ios_open")) { perform(action) }
                .buttonStyle(.bordered)
                .accessibilityLabel(L(item.titleKey))
        case .link(let url):
            Button { perform(url) } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(item.titleKey))
        }
    }

    /// The resolution lists start with this device's own sizes, worked out from its screen
    private var deviceSizes: [(title: String, value: String)] {
        guard item.id == "list_resolution" || item.id == "list_app_resolution",
              let window = AppState.topViewController()?.view.window else { return [] }
        let insets = window.safeAreaInsets
        let choices = DeviceResolutions.choices(screen: window.bounds.size,
                                                insets: (insets.top, insets.left, insets.bottom, insets.right),
                                                scale: window.screen.scale)
        var sizes = [(L("ios_resolution_full_screen", choices.fullScreen), choices.fullScreen)]
        if choices.safeArea != choices.fullScreen {
            sizes.append((L("ios_resolution_safe_area", choices.safeArea), choices.safeArea))
        }
        return sizes
    }

    private func listMenu(entries: [String], values: [String], allowsCustom: Bool) -> some View {
        let current = model.string(item.id)
        let index = values.firstIndex(of: current)
        let device = deviceSizes
        let deviceTitle = device.first { $0.value == current }?.title
        // Vibeshine has no in-stream microphone (the Apollo route)
        let shown = values.indices.filter { !(item.id == "list_microphone_target" && values[$0] == "host") }
        return Menu {
            ForEach(device, id: \.value) { size in
                Button {
                    model.set(.string(size.value), for: item.id)
                } label: {
                    if size.value == current {
                        Label(size.title, systemImage: "checkmark")
                    } else {
                        Text(size.title)
                    }
                }
            }
            ForEach(shown, id: \.self) { i in
                Button {
                    model.set(.string(values[i]), for: item.id)
                } label: {
                    if i == index {
                        Label(L(entries[i]), systemImage: "checkmark")
                    } else {
                        Text(L(entries[i]))
                    }
                }
            }
            if allowsCustom {
                Button(L("ios_custom_value")) { askCustom(current: current) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(deviceTitle ?? index.map { L(entries[$0]) } ?? current)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Color.white.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel(L(item.titleKey))
        .accessibilityValue(index.map { L(entries[$0]) } ?? current)
        .accessibilityIdentifier("setting-\(item.id)")
    }

    @State private var customText = ""

    private func askCustom(current: String) {
        customText = current
        state.show(PanelContent(title: L(item.titleKey), message: L("ios_custom_value_help"),
                                textField: (current, $customText, .numbersAndPunctuation),
                                buttons: [
                                    PanelButton(title: L("ios_ok")) {
                                        let typed = customText.trimmingCharacters(in: .whitespaces)
                                        if (try? model.store.set(.string(typed), for: item.id)) == nil {
                                            state.message(L(item.titleKey), L("ios_custom_value_bad"))
                                        }
                                        model.set(model.value(item.id) ?? .string(typed), for: item.id)
                                    },
                                    PanelButton(title: L("applist_menu_cancel"), role: .cancel),
                                ]))
    }

    private func setToggle(_ on: Bool) {
        if on, let confirmation = item.confirmation {
            state.show(PanelContent(title: L(confirmation.titleKey), message: L(confirmation.messageKey), buttons: [
                PanelButton(title: L(SettingConfirmation.yesKey)) { model.set(.bool(true), for: item.id) },
                PanelButton(title: L(SettingConfirmation.noKey), role: .cancel),
            ]))
        } else {
            model.set(.bool(on), for: item.id)
        }
    }

    /// A on a controller: flip a switch, open a list's menu as a panel, run an action.
    private func controllerAction() {
        guard model.isEnabled(item) else { return }
        if item.id == "list_languages" {
            openLanguageSettings()
            return
        }
        switch item.control {
        case .toggle:
            setToggle(!model.bool(item.id))
        case .list(let entries, let values, _):
            let shown = values.indices.filter { !(item.id == "list_microphone_target" && values[$0] == "host") }
            var buttons = shown.map { i in
                PanelButton(title: (values[i] == model.string(item.id) ? "✓ " : "") + L(entries[i])) {
                    model.set(.string(values[i]), for: item.id)
                }
            }
            buttons.append(PanelButton(title: L("applist_menu_cancel"), role: .cancel))
            state.show(PanelContent(title: L(item.titleKey), buttons: buttons))
        case .slider(let range, let step, _, _, _):
            // Each press moves one step; past the end it starts again
            let next = model.int(item.id) + step
            model.set(.int(next > range.upperBound ? range.lowerBound : next), for: item.id)
        case .action(let action):
            perform(action)
        case .link(let url):
            perform(url)
        case .dynamicList, .text:
            break
        }
    }
}

struct SettingSlider: View {
    let key: String
    let title: String
    let range: ClosedRange<Int>
    let step: Int
    let divisor: Int
    let unit: String?
    let allowsCustom: Bool
    @ObservedObject var model: SettingsModel
    @EnvironmentObject private var state: AppState
    @State private var typed = ""

    var body: some View {
        let value = model.int(key)
        HStack(spacing: 12) {
            Slider(value: Binding(get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                                  set: { model.set(.int(Int(($0 / Double(step)).rounded()) * step), for: key) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                .accessibilityLabel(title)
                .accessibilityValue(text(value))
                .accessibilityIdentifier("setting-\(key)")
            if allowsCustom {
                // A number can be typed straight in (the bitrate in Mbps, past the slider's end too)
                HStack(spacing: 4) {
                    TextField(title, text: $typed)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .frame(width: 64)
                        .focused($editing)
                        .onSubmit(commit)
                        .onAppear { typed = number(value) }
                        .onChange(of: value) { _, new in if !editing { typed = number(new) } }
                        .onChange(of: editing) { _, now in if !now { commit() } }
                        .accessibilityIdentifier("setting-\(key)-value")
                    if let unit {
                        Text(unit).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.12)))
                if model.store.savedValue(key) != nil && model.store.defaultValue(key) != model.store.savedValue(key)
                    && SettingsCatalog.definition(key)?.defaultValue == nil {
                    // A computed default (the bitrate follows the resolution and frame rate)
                    Button(L("ios_recommended")) { model.reset(key) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("setting-\(key)-recommended")
                }
            } else {
                Text(text(value))
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 80, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    @FocusState private var editing: Bool

    private func number(_ value: Int) -> String {
        divisor > 1
            ? (value % divisor == 0 ? String(value / divisor) : String(format: "%.1f", Double(value) / Double(divisor)))
            : String(value)
    }

    private func commit() {
        if let number = Double(typed.replacingOccurrences(of: ",", with: ".")), number > 0 {
            let saved = Int((number * Double(divisor)).rounded())
            if (try? model.store.set(.int(saved), for: key)) == nil {
                state.message(title, L("ios_custom_value_bad"))
            }
            model.set(model.value(key) ?? .int(saved), for: key)
        }
        typed = number(model.int(key))
    }

    private func text(_ value: Int) -> String {
        let number = divisor > 1
            ? (value % divisor == 0 ? String(value / divisor) : String(format: "%.1f", Double(value) / Double(divisor)))
            : String(value)
        return unit.map { "\(number) \($0)" } ?? number
    }

    private func askValue(_ value: Int) {
        typed = divisor > 1 ? String(Double(value) / Double(divisor)) : String(value)
        state.show(PanelContent(title: title, message: unit, textField: (typed, $typed, .decimalPad), buttons: [
            PanelButton(title: L("ios_ok")) {
                if let number = Double(typed.replacingOccurrences(of: ",", with: ".")) {
                    model.set(.int(Int((number * Double(divisor)).rounded())), for: key)
                }
            },
            PanelButton(title: L("applist_menu_cancel"), role: .cancel),
        ]))
    }
}

struct SettingTextField: View {
    let key: String
    let title: String
    let input: SettingTextInput
    let maxLength: Int?
    @ObservedObject var model: SettingsModel
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .keyboardType(input == .number ? .numberPad : input == .decimal ? .decimalPad : .default)
            .autocorrectionDisabled()
            .onAppear { text = model.string(key) }
            .onSubmit(save)
            .onChange(of: text) { _, new in
                if let maxLength, new.count > maxLength {
                    text = String(new.prefix(maxLength))
                }
            }
            .onDisappear(perform: save)
            .accessibilityIdentifier("setting-\(key)")
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed != model.string(key) {
            model.set(.string(trimmed), for: key)
        }
    }
}

/// The microphone to capture from: iOS's own choice, or one of the inputs it offers now.
struct MicrophoneDevicePicker: View {
    let key: String
    let defaultEntry: String
    @ObservedObject var model: SettingsModel

    var body: some View {
        let inputs = AVAudioSession.sharedInstance().availableInputs ?? []
        let current = model.string(key)
        Menu {
            Button(L(defaultEntry)) { model.set(.string("0"), for: key) }
            ForEach(inputs, id: \.uid) { input in
                Button(input.portName) { model.set(.string(input.uid), for: key) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(inputs.first { $0.uid == current }?.portName ?? L(defaultEntry))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Color.white.opacity(0.12), in: Capsule())
        }
        .accessibilityIdentifier("setting-\(key)")
    }
}

/// Android's predicted-impact panel: where the pacing settings put the stream between fastest
/// response and smoothest motion, what moves it, and the input delay and battery use.
struct PredictedImpactPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let _ = model.revision
        let feel = SettingsFeel.describe(model.store)
        VStack(alignment: .leading, spacing: 12) {
            Text(L(SettingsFeel.titleKey))
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            HStack {
                Text(L(SettingsFeel.fastestKey))
                Spacer()
                Text(L(SettingsFeel.smoothestKey))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.92))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [.orange, .pink, .purple, Color(red: 0.4, green: 0.45, blue: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .offset(x: CGFloat(feel.position) * (geometry.size.width - 26))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
            .accessibilityElement()
            .accessibilityLabel(L(SettingsFeel.titleKey))
            .accessibilityValue("\(Int((feel.position * 100).rounded()))%")
            Text(L(SettingsFeel.movingItKey))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
            ForEach(Array(feel.factors.enumerated()), id: \.offset) { _, factor in
                HStack {
                    Text(L(SettingsFeel.factorRowKey, L(factor.titleKey), valueText(factor.value)))
                    Spacer()
                    Text(L(factor.effect.nameKey))
                        .bold()
                        .foregroundStyle(factor.effect == .noEffect || factor.effect == .notUsed ? .white.opacity(0.6) : .white)
                }
                .font(.footnote)
            }
            Text(L(feel.descriptionKey))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Color.white.opacity(0.2))
            levelRow(L(SettingsFeel.delayKey), feel.delay)
            levelRow(L(SettingsFeel.batteryKey), feel.battery)
        }
        .padding(20)
        .frostedCard(cornerRadius: 22, padding: 0)
    }

    private func valueText(_ value: SettingsFeel.FactorValue) -> String {
        switch value {
        case .label(let key): return L(key)
        case .literal(let text): return text
        }
    }

    private func levelRow(_ title: String, _ level: SettingsFeel.Level) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(L(level.nameKey)).bold()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
