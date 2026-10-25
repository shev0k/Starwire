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
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SettingsModel()
    @State private var section = SettingsLayout.sections[0].id
    @State private var exporting: SettingsDocument?
    @State private var importing = false

    private var current: SettingsSection {
        SettingsLayout.sections.first { $0.id == section } ?? SettingsLayout.sections[0]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StarfieldBackground(paused: state.isStreaming)
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: L("ios_settings_title"))
                    pills
                    let wide = geometry.size.width >= CGFloat(SettingsFeel.panelMinWidth) && section == "stream"
                    HStack(alignment: .top, spacing: 20) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    Text(L(current.titleKey))
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(Color(red: 0.75, green: 0.6, blue: 1))
                                        .accessibilityAddTraits(.isHeader)
                                        .id("top")
                                    if !wide && section == "stream" {
                                        PredictedImpactPanel(model: model)
                                    }
                                    ForEach(current.groups) { group in
                                        groupView(group)
                                    }
                                    if section == "app" {
                                        transferButtons
                                    }
                                }
                                .padding(.horizontal, 20)
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
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .controllerBack("settings") { dismiss() }
        .onAppear {
            if let initialSection, SettingsLayout.sections.contains(where: { $0.id == initialSection }) {
                section = initialSection
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

    private var pills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SettingsLayout.sections) { item in
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
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func groupView(_ group: SettingsGroup) -> some View {
        let items = group.items.filter { model.isVisible($0) }
        if model.holds(group.showWhen) && !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if let title = group.titleKey {
                    Text(L(title))
                        .font(.headline)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(items) { item in
                    SettingRow(item: item, model: model, perform: perform)
                        .id("setting-\(item.id)")
                    Divider().overlay(Color.white.opacity(0.08))
                }
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
                .foregroundStyle(.white.opacity(0.7))
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
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let impact = SettingsImpact.impactKey(for: item.impactKey ?? item.id) {
                (Text(L(SettingsImpact.labelKey) + " ").bold().foregroundColor(Color(red: 0.75, green: 0.6, blue: 1))
                    + Text(L(impact)))
                    .font(.footnote)
            }
            if let credit = item.credit {
                Text(credit.text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(item.titleKey))
        }
    }

    private func listMenu(entries: [String], values: [String], allowsCustom: Bool) -> some View {
        let current = model.string(item.id)
        let index = values.firstIndex(of: current)
        // Vibeshine has no in-stream microphone (the Apollo route)
        let shown = values.indices.filter { !(item.id == "list_microphone_target" && values[$0] == "host") }
        return Menu {
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
                Text(index.map { L(entries[$0]) } ?? current)
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
            Button(text(value)) {
                if allowsCustom { askValue(value) }
            }
            .buttonStyle(.plain)
            .font(.body.monospacedDigit())
            .frame(minWidth: 80, alignment: .trailing)
            .accessibilityHidden(!allowsCustom)
        }
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
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.8))
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
                .foregroundStyle(.white.opacity(0.7))
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
