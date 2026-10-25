//
//  StreamMenuPanel.swift
//  Starwire
//
//  The stream menu (batch 4.5): a panel that slides in from the right edge, with the game and the
//  stream's numbers at the top, quick switches as tiles, the stream's choices (bitrate, touch
//  mode, picture) as rows that open a page of choices, the keys to send, and Disconnect and Quit
//  Session at the bottom. What is on it comes from StarwireKit's StreamMenu.sections, so the
//  items are Android's OverlayMenuView's (GPL-3.0) in groups. It works by touch and by a
//  controller: the d-pad moves the focus ring, A chooses, B goes back or closes, and Android's
//  shortcuts stay (X mouse, Y keyboard, Start Guide, RB stats).
//

import StarwireKit
import SwiftUI
import UIKit

@MainActor
final class StreamMenuModel: ObservableObject {
    @Published var page: StreamMenuPage = .main
    @Published var state = StreamMenuState()
    /// The item the controller's focus ring is on; nil until a controller moves it
    @Published var focusID: String?
    @Published var shown = false

    let title: String
    let chips: [String]
    var readState: () -> StreamMenuState = { StreamMenuState() }
    var onAction: (StreamMenuAction) -> Void = { _ in }
    var onHidden: () -> Void = {}
    /// Columns of the tile grid, set by the panel from its width, for controller moves
    var tileColumns = 4

    init(title: String, chips: [String]) {
        self.title = title.isEmpty ? StreamMenu.title : title
        self.chips = chips
    }

    var sections: [StreamMenuSection] { StreamMenu.sections(state: state) }

    var pageItems: [StreamMenuItem] { page == .main ? [] : StreamMenu.items(on: page, state: state) }

    var pageTitle: String {
        switch page {
        case .main: return title
        case .shortcuts: return "Shortcuts"
        case .monitors: return "Monitors"
        case .touchMode: return "Touch mode"
        case .bitrate: return "Bitrate"
        case .picture: return "Picture"
        }
    }

    func reload() {
        state = readState()
    }

    func show() {
        reload()
        page = .main
        focusID = nil
        withAnimation(Self.motion) { shown = true }
    }

    func hide() {
        guard shown else { return }
        withAnimation(Self.motion) { shown = false }
        onHidden()
    }

    static var motion: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.88)
    }

    func choose(_ item: StreamMenuItem) {
        switch item.action {
        case .openPage(let target):
            go(to: target)
        case .back:
            go(to: .main)
        case .close:
            hide()
        default:
            if item.closesMenu { hide() }
            onAction(item.action)
            reload()
        }
    }

    private func go(to target: StreamMenuPage) {
        withAnimation(.easeInOut(duration: 0.18)) {
            page = target
        }
        focusID = focusID == nil ? nil : rows.first?.first
    }

    // MARK: Controller

    /// The items as rows for the d-pad: tile rows, then one row per list item, then the bar.
    var rows: [[String]] {
        var rows: [[String]] = []
        if page == .main {
            for section in sections {
                if section.style == .tiles {
                    let ids = section.items.map(\.id)
                    stride(from: 0, to: ids.count, by: tileColumns).forEach { rows.append(Array(ids[$0..<min($0 + tileColumns, ids.count)])) }
                } else {
                    rows += section.items.map { [$0.id] }
                }
            }
            rows.append(StreamMenu.bar.filter { $0.id != "close" }.map(\.id))
        } else {
            rows += pageItems.map { [$0.id] }
        }
        return rows
    }

    private func item(id: String) -> StreamMenuItem? {
        let all = (page == .main ? sections.flatMap(\.items) + StreamMenu.bar : pageItems)
        return all.first { $0.id == id }
    }

    /// Buttons newly pressed on a controller (already flipped when "Flip face buttons" is on).
    func controllerPressed(_ buttons: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        if buttons & GamepadButton.b != 0 {
            if page == .main { hide() } else { go(to: .main) }
            return
        }
        guard let current = focusID, let row = rows.firstIndex(where: { $0.contains(current) }),
              let column = rows[row].firstIndex(of: current) else {
            // The first press shows the ring on the first item
            if buttons & (GamepadButton.up | GamepadButton.down | GamepadButton.left | GamepadButton.right | GamepadButton.a) != 0 {
                focusID = rows[0][0]
            }
            handleShortcuts(buttons)
            return
        }
        if buttons & GamepadButton.a != 0, let item = item(id: current) {
            choose(item)
            return
        }
        if handleShortcuts(buttons) { return }
        var r = row, c = column
        if buttons & GamepadButton.down != 0 { r = min(row + 1, rows.count - 1) }
        if buttons & GamepadButton.up != 0 { r = max(row - 1, 0) }
        if r != row { c = min(column, rows[r].count - 1) }
        if buttons & GamepadButton.right != 0 { c = min(column + 1, rows[r].count - 1) }
        if buttons & GamepadButton.left != 0 { c = max(column - 1, 0) }
        focusID = rows[r][c]
    }

    @discardableResult
    private func handleShortcuts(_ buttons: Int) -> Bool {
        guard page == .main else { return false }
        let shortcut: StreamMenuAction?
        if buttons & GamepadButton.x != 0 { shortcut = .toggleMouseEmulation }
        else if buttons & GamepadButton.y != 0 { shortcut = .systemKeyboard }
        else if buttons & GamepadButton.start != 0 { shortcut = .guide }
        else if buttons & GamepadButton.rightBumper != 0 { shortcut = .toggleStats }
        else { shortcut = nil }
        guard let shortcut else { return false }
        hide()
        onAction(shortcut)
        return true
    }
}

// MARK: - Panel

struct StreamMenuPanel: View {
    @ObservedObject var model: StreamMenuModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                if model.shown {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture { model.hide() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                    panel(width: min(geometry.size.width - 24, 420), height: geometry.size.height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .preferredColorScheme(.dark)
    }

    private func panel(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)
            Divider().overlay(Color.white.opacity(0.08))
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if model.page == .main {
                            mainPage(width: width)
                        } else {
                            choicePage
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: model.focusID) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            if model.page == .main {
                Divider().overlay(Color.white.opacity(0.08))
                bar.padding(16)
            }
        }
        .frame(width: width)
        .frame(maxHeight: height - 24)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, x: -4, y: 8)
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("StreamMenu")
        .onAppear { model.tileColumns = width >= 360 ? 4 : 3 }
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.22).opacity(0.92),
                                    Color(red: 0.04, green: 0.03, blue: 0.10).opacity(0.94)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if model.page != .main {
                Button { model.choose(StreamMenuItem(id: "back", title: "Back", symbol: "", action: .back, isOn: nil, closesMenu: false)) } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("menu-back")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.pageTitle)
                    .font(.title2.weight(.heavy))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                if model.page == .main && !model.chips.isEmpty {
                    ChipRow(model.chips, spacing: 6)
                }
            }
            Spacer(minLength: 8)
            Button { model.hide() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("menu-close")
        }
        .foregroundStyle(.white)
    }

    // MARK: Main page

    private func mainPage(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(model.sections, id: \.id) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.99))
                        .accessibilityAddTraits(.isHeader)
                    if section.style == .tiles {
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: width >= 360 ? 4 : 3)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(section.items, id: \.id) { tile($0) }
                        }
                    } else {
                        VStack(spacing: 6) {
                            ForEach(section.items, id: \.id) { row($0) }
                        }
                    }
                }
            }
        }
    }

    private func tile(_ item: StreamMenuItem) -> some View {
        let on = item.isOn == true
        let focused = model.focusID == item.id
        return Button { model.choose(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.symbol.isEmpty ? "circle" : item.symbol)
                    .font(.title3.weight(.semibold))
                    .frame(height: 24)
                Text(Self.plainTitle(item.title))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.79, green: 0.35, blue: 0.87)],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                             : AnyShapeStyle(Color.white.opacity(0.08)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? Color.white : Color.white.opacity(on ? 0.25 : 0.10), lineWidth: focused ? 3 : 1)
            }
            .scaleEffect(focused ? 1.04 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
        }
        .buttonStyle(PressableStyle())
        .id(item.id)
        .accessibilityLabel(Self.plainTitle(item.title))
        .accessibilityValue(item.isOn.map { $0 ? "On" : "Off" } ?? "")
        .accessibilityIdentifier("menu-\(item.id)")
    }

    private func row(_ item: StreamMenuItem, choice: Bool = false) -> some View {
        let focused = model.focusID == item.id
        let opensPage: Bool = {
            if case .openPage = item.action { return true }
            return false
        }()
        return Button { model.choose(item) } label: {
            HStack(spacing: 12) {
                if !item.symbol.isEmpty {
                    Image(systemName: item.symbol)
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.10)))
                }
                Text(Self.plainTitle(item.title))
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let value = item.value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                if choice && item.isOn == true {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.99))
                } else if opensPage {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(choice && item.isOn == true ? 0.14 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? Color.white : Color.clear, lineWidth: 3))
        }
        .buttonStyle(PressableStyle())
        .id(item.id)
        .accessibilityLabel(Self.plainTitle(item.title))
        .accessibilityValue(choice ? (item.isOn == true ? "Chosen" : "") : (item.value ?? ""))
        .accessibilityIdentifier("menu-\(item.id)")
    }

    // MARK: Choice pages

    private var choicePage: some View {
        VStack(spacing: 6) {
            ForEach(model.pageItems.filter { $0.id != "back" }, id: \.id) { row($0, choice: true) }
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 10) {
            ForEach(StreamMenu.bar.filter { $0.id != "close" }, id: \.id) { item in
                let focused = model.focusID == item.id
                let quit = item.id == "quit"
                Button { model.choose(item) } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(quit ? Color(red: 0.86, green: 0.15, blue: 0.27).opacity(0.85) : Color.white.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(focused ? Color.white : Color.clear, lineWidth: 3))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("menu-\(item.id)")
            }
        }
    }

    /// Android's titles carry the controller button in brackets ("Mouse (X)", "Guide (▶)"); the
    /// panel shows the plain name. Other brackets ("Trackpad (natural)") stay.
    static func plainTitle(_ title: String) -> String {
        guard let open = title.lastIndex(of: "("), title.hasSuffix(")") else { return title }
        let inside = title[title.index(after: open)..<title.index(before: title.endIndex)]
        guard ["X", "Y", "A", "B", "RB", "LB", "\u{25B6}"].contains(String(inside)) else { return title }
        return String(title[..<open]).trimmingCharacters(in: .whitespaces)
    }
}

/// A slight shrink while pressed
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
