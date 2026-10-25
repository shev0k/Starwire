//
//  KeyboardEditorScreen.swift
//  Starwire
//
//  Settings > Keyboards > Change keys (batch 4.5): each on-screen keyboard layout drawn as it
//  is, where tapping a key and then another key makes the first one send the second. Remapped
//  keys show their new label in Starwire's violet. The remaps are kept per layout in the settings
//  store (`keyboard_remapped_keys`), through StarwireKit's KeyboardCustomization.
//

import StarwireKit
import SwiftUI

struct KeyboardEditorScreen: View {
    @ObservedObject var model: SettingsModel
    var onDone: () -> Void
    @State private var preset = KeyboardPreset.full
    @State private var selected: String?

    private var remaps: [KeyboardPreset: [String: String]] {
        KeyboardCustomization.decodeRemaps(model.string(KeyboardCustomization.remapKey))
    }

    private var layout: FullKeyboardLayout {
        KeyboardCustomization.layout(preset, remaps: remaps[preset] ?? [:])
    }

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("ios_title_keyboard_edit"))
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(L("ios_done"), action: onDone)
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.49, green: 0.23, blue: 0.93))
                    .accessibilityIdentifier("keyboard-editor-done")
            }
            Picker(L("ios_title_keyboard_preset"), selection: $preset) {
                ForEach(KeyboardPreset.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: preset) { _, _ in selected = nil }

            Text(selected == nil ? L("ios_keyboard_edit_pick_key") : L("ios_keyboard_edit_pick_target"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            keyboard
                .frame(height: 260)

            if let selected {
                targets(for: selected)
            } else if !(remaps[preset] ?? [:]).isEmpty {
                Button(L("ios_keyboard_edit_reset"), role: .destructive) { save(nil, for: nil) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("keyboard-editor-reset")
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(StarfieldBackground(paused: true).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var keyboard: some View {
        GeometryReader { geometry in
            let rows = layout.rows
            let rowHeight = geometry.size.height / CGFloat(max(rows.count, 1))
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let weights = CGFloat(row.reduce(0) { $0 + $1.weight })
                    HStack(spacing: 0) {
                        ForEach(row, id: \.id) { key in
                            keyButton(key)
                                .frame(width: geometry.size.width * CGFloat(key.weight) / max(weights, 1), height: rowHeight)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.35)))
    }

    private func keyButton(_ key: FullKeyboardKey) -> some View {
        let remapped = remaps[preset]?[key.id] != nil
        let isSelected = selected == key.id
        let canEdit = key.kind != .hide
        return Button {
            guard canEdit else { return }
            selected = isSelected ? nil : key.id
        } label: {
            Text(key.label.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(remapped ? Color(red: 0.49, green: 0.23, blue: 0.93) : Color.white.opacity(canEdit ? 0.14 : 0.05)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2.5))
                .padding(2)
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityLabel(key.label.replacingOccurrences(of: "\n", with: " "))
        .accessibilityValue(remapped ? L("ios_keyboard_edit_remapped") : "")
        .accessibilityIdentifier("keyboard-editor-key-\(key.id)")
    }

    private func targets(for keyID: String) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 6) {
                Button(L("ios_keyboard_edit_own_key")) { save(nil, for: keyID) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("keyboard-editor-own")
                ForEach(KeyboardCustomization.targets.filter { $0.kind != .hide }, id: \.id) { target in
                    Button {
                        save(target.id, for: keyID)
                    } label: {
                        Text(target.label.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("keyboard-editor-target-\(target.id)")
                }
            }
        }
    }

    /// Saves a remap (nil target: the key's own again; nil key: the whole layout reset)
    private func save(_ target: String?, for keyID: String?) {
        var all = remaps
        var map = all[preset] ?? [:]
        if let keyID {
            map[keyID] = (target == keyID) ? nil : target
        } else {
            map.removeAll()
        }
        all[preset] = map
        model.set(.string(KeyboardCustomization.encodeRemaps(all)), for: KeyboardCustomization.remapKey)
        selected = nil
    }
}
