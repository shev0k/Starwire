//
//  ControllerKeyboardView.swift
//  Starwire
//
//  The controller keyboard (batch 4.5): StarwireKit's ControllerKeyboard drawn as a card at the
//  bottom of the stream, in the manner of the PlayStation 5's keyboard. The d-pad or left stick
//  moves the ring, A types, L1 deletes, R1 is a space, L2 Shift, R2 the symbols, Start Enter, B
//  closes. Keys can also be tapped. Each key goes to the PC as it is typed; the line at the top
//  shows what was sent.
//

import StarwireKit
import SwiftUI
import UIKit

@MainActor
final class ControllerKeyboardModel: ObservableObject {
    let keyboard: ControllerKeyboard
    @Published private(set) var revision = 0
    var send: (InputEvent) -> Void = { _ in }
    var onClose: () -> Void = {}
    private var timer: Timer?

    init(holding: Int = 0) {
        keyboard = ControllerKeyboard(holding: holding)
    }

    func handle(_ state: ControllerState) {
        let now = ProcessInfo.processInfo.systemUptime
        keyboard.handle(state, now: now).forEach(send)
        changed()
    }

    func tap(row: Int, column: Int) {
        keyboard.tap(row: row, column: column, now: ProcessInfo.processInfo.systemUptime).forEach(send)
        changed()
    }

    func close() {
        timer?.invalidate()
        onClose()
    }

    private func changed() {
        revision += 1
        if !keyboard.isOpen {
            close()
            return
        }
        timer?.invalidate()
        guard let deadline = keyboard.nextDeadline else { return }
        let delay = max(deadline - ProcessInfo.processInfo.systemUptime, 0)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.keyboard.tick(now: ProcessInfo.processInfo.systemUptime)
                self.changed()
            }
        }
    }
}

struct ControllerKeyboardView: View {
    @ObservedObject var model: ControllerKeyboardModel

    var body: some View {
        let keyboard = model.keyboard
        let _ = model.revision
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(Color(red: 0.77, green: 0.71, blue: 0.99))
                Text(keyboard.preview.isEmpty ? "Type with your controller" : keyboard.preview + "\u{2009}|")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(keyboard.preview.isEmpty ? .white.opacity(0.5) : .white)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ControllerKeyboardPreview")
                if keyboard.shift != .off {
                    Text(keyboard.shift == .locked ? "CAPS" : "SHIFT")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 0.49, green: 0.23, blue: 0.93)))
                }
                Button { model.close() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35)))

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, key in
                            let start = row[..<index].reduce(0) { $0 + $1.span }
                            keyView(key, focused: keyboard.focus.row == rowIndex && keyboard.focus.column == start,
                                    shift: keyboard.shift != .off)
                                .gridCellColumns(key.span)
                                .onTapGesture { model.tap(row: rowIndex, column: start) }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                hint("L1", "Delete")
                hint("R1", "Space")
                hint("L2", "Shift")
                hint("R2", keyboard.page == .letters ? "Symbols" : "Letters")
                hint("\u{2630}", "Enter")
                hint("B", "Close")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(16)
        .frame(maxWidth: 780)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.22).opacity(0.9),
                                                  Color(red: 0.04, green: 0.03, blue: 0.10).opacity(0.92)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .environment(\.colorScheme, .dark)
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ControllerKeyboard")
    }

    private func keyView(_ key: ControllerKeyboardKey, focused: Bool, shift: Bool) -> some View {
        let label: String = {
            if case .character(let lower, let upper) = key.kind { return String(shift ? upper : lower) }
            return key.label
        }()
        let action: Bool = {
            if case .character = key.kind { return false }
            return true
        }()
        return Text(label)
            .font(.system(size: action ? 15 : 21, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(focused ? Color.white : Color.white.opacity(action ? 0.14 : 0.09)))
            .foregroundStyle(focused ? Color(red: 0.10, green: 0.06, blue: 0.22) : .white)
            .scaleEffect(focused ? 1.08 : 1)
            .shadow(color: focused ? Color(red: 0.79, green: 0.35, blue: 0.87).opacity(0.8) : .clear, radius: 8)
            .animation(.easeOut(duration: 0.08), value: focused)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }

    private func hint(_ button: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(button)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.5)))
            Text(text)
        }
    }
}
