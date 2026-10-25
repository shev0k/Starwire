//
//  ShortcutsManagerView.swift
//  Starwire
//
//  The "Shortcuts and commands" sheet of the stream menu: the custom commands (add, edit, delete)
//  and the imported shortcuts (import a JSON file from Files, remove them). Based on Starwire for
//  Android's custom commands and imported shortcuts (GPL-3.0). The saving and reading is
//  StarwireKit's CustomCommandsStore and ImportedShortcutsStore.
//

import StarwireKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Presents the sheet from a view controller (iPad: form sheet). `onChange` is called after
/// anything is saved, so the stream menu can reload.
func presentShortcutsManager(from controller: UIViewController, onChange: @escaping () -> Void) {
    let host = UIHostingController(rootView: ShortcutsManagerView(onChange: onChange))
    host.modalPresentationStyle = controller.traitCollection.userInterfaceIdiom == .pad ? .formSheet : .pageSheet
    controller.present(host, animated: true)
}

/// The two stores and what the list shows.
final class ShortcutsManagerModel: ObservableObject {
    @Published private(set) var commands: [CustomCommand] = []
    @Published private(set) var imported: [Shortcut] = []

    private let commandStore: CustomCommandsStore
    private let importStore: ImportedShortcutsStore

    init() {
        let storage = StarwireSettings.store.storage
        commandStore = CustomCommandsStore(storage: storage)
        importStore = ImportedShortcutsStore(storage: storage)
        refresh()
    }

    private func refresh() {
        commands = commandStore.commands
        imported = importStore.load()
    }

    func save(_ command: CustomCommand, replacing id: String?) {
        if let id {
            commandStore.update(id: id, with: command)
        } else {
            commandStore.add(command)
        }
        refresh()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets where commands.indices.contains(index) {
            commandStore.remove(id: commands[index].id)
        }
        refresh()
    }

    /// Saves the file and returns how many shortcuts it has. Throws a message for the alert.
    func importFile(at url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // A big file is refused before it is read
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if size > ShortcutImport.maxFileBytes {
            throw ShortcutImportError("the file is too big to be a shortcuts file")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ShortcutImportError("the file could not be read")
        }
        let count = try importStore.save(data)
        refresh()
        return count
    }

    func clearImported() {
        importStore.clear()
        refresh()
    }
}

private struct ManagerAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct EditTarget: Identifiable {
    let id = UUID()
    let command: CustomCommand?
}

private func afterText(_ action: CommandAfterAction) -> String {
    switch action {
    case .none: return "None"
    case .closeMenu: return "Close the menu"
    case .disconnect: return "Disconnect"
    case .quit: return "Quit the session"
    case .sleep: return "Sleep (not on iOS)"
    }
}

struct ShortcutsManagerView: View {
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ShortcutsManagerModel()
    @State private var editing: EditTarget?
    @State private var showingImporter = false
    @State private var confirmingRemove = false
    @State private var alert: ManagerAlert?

    var body: some View {
        NavigationStack {
            List {
                commandsSection
                importedSection
            }
            .accessibilityIdentifier("ShortcutsManager")
            .navigationTitle("Shortcuts and commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("ShortcutsManagerDone")
                }
            }
            .sheet(item: $editing) { target in
                CommandEditor(existing: target.command) { command in
                    model.save(command, replacing: target.command?.id)
                    onChange()
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .plainText],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .confirmationDialog("Remove the imported shortcuts?", isPresented: $confirmingRemove,
                                titleVisibility: .visible) {
                Button("Remove imported shortcuts", role: .destructive) {
                    model.clearImported()
                    onChange()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(item: $alert) { item in
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var commandsSection: some View {
        Section {
            ForEach(model.commands) { command in
                Button {
                    editing = EditTarget(command: command)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.displayName).foregroundStyle(.primary)
                        Text(command.keys.displayString).font(.footnote).foregroundStyle(.secondary)
                        if command.after != .none {
                            Text("After: \(afterText(command.after))").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { model.delete(at: $0); onChange() }
            Button {
                editing = EditTarget(command: nil)
            } label: {
                Label("Add command", systemImage: "plus")
            }
            .accessibilityIdentifier("AddCommand")
        } header: {
            Text("Custom commands")
        } footer: {
            Text("A command sends a key combination to the PC. Swipe a command to delete it.")
        }
    }

    private var importedSection: some View {
        Section {
            if model.imported.isEmpty {
                Text("None imported").foregroundStyle(.secondary)
            } else {
                Text("\(model.imported.count) imported: \(ShortcutImport.summaryNames(model.imported))")
            }
            Button {
                showingImporter = true
            } label: {
                Label("Import from Files", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("ImportShortcuts")
            Button(role: .destructive) {
                confirmingRemove = true
            } label: {
                Label("Remove imported shortcuts", systemImage: "trash")
            }
            .disabled(model.imported.isEmpty)
            .accessibilityIdentifier("RemoveImportedShortcuts")
        } header: {
            Text("Imported shortcuts")
        } footer: {
            Text("A JSON file of shortcuts. They appear on the stream menu's Shortcuts page. Importing again replaces them.")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alert = ManagerAlert(title: "Import failed",
                                 message: "Couldn't import the shortcuts: \(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let count = try model.importFile(at: url)
                onChange()
                alert = ManagerAlert(title: "Imported",
                                     message: count == 1 ? "Imported 1 shortcut." : "Imported \(count) shortcuts.")
            } catch {
                let message = (error as? ShortcutImportError)?.message ?? error.localizedDescription
                alert = ManagerAlert(title: "Import failed", message: "Couldn't import the shortcuts: \(message)")
            }
        }
    }
}

/// Adds a command, or edits one. Saves only with a name and a key.
private struct CommandEditor: View {
    static let maxNameLength = 40

    let existing: CustomCommand?
    let onSave: (CustomCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var ctrl: Bool
    @State private var alt: Bool
    @State private var shift: Bool
    @State private var meta: Bool
    @State private var keyCode: Int?
    @State private var after: CommandAfterAction

    init(existing: CustomCommand?, onSave: @escaping (CustomCommand) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _ctrl = State(initialValue: existing?.keys.ctrl ?? false)
        _alt = State(initialValue: existing?.keys.alt ?? false)
        _shift = State(initialValue: existing?.keys.shift ?? false)
        _meta = State(initialValue: existing?.keys.meta ?? false)
        _keyCode = State(initialValue: existing?.keys.androidKeyCode)
        _after = State(initialValue: existing?.after ?? .none)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedName.isEmpty && keyCode != nil }

    /// The model's key list, plus the key of an imported command that isn't in it.
    private var keyOptions: [(code: Int, name: String)] {
        var options = AndroidKeyCode.pickableKeys.map { (code: $0.androidKeyCode, name: $0.name) }
        if let code = existing?.keys.androidKeyCode, !options.contains(where: { $0.code == code }) {
            options.append((code: code, name: "Key \(code)"))
        }
        return options
    }

    /// iOS can't sleep the device, so Sleep is only listed for a command that already has it.
    private var afterOptions: [CommandAfterAction] {
        var options: [CommandAfterAction] = [.none, .closeMenu, .disconnect, .quit]
        if existing?.after == .sleep { options.append(.sleep) }
        return options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("CommandName")
                } header: {
                    Text("Name")
                } footer: {
                    Text("Required. Up to \(Self.maxNameLength) characters.")
                }
                Section {
                    Toggle("Ctrl", isOn: $ctrl)
                    Toggle("Alt", isOn: $alt)
                    Toggle("Shift", isOn: $shift)
                    Toggle("Win", isOn: $meta)
                    Picker("Key", selection: $keyCode) {
                        Text("Choose a key").tag(Int?.none)
                        ForEach(keyOptions, id: \.code) { option in
                            Text(option.name).tag(Int?.some(option.code))
                        }
                    }
                    .accessibilityIdentifier("CommandKey")
                } header: {
                    Text("Keys")
                } footer: {
                    if keyCode == nil { Text("Choose a key to save the command.") }
                }
                Section {
                    Picker("After the keys", selection: $after) {
                        ForEach(afterOptions, id: \.self) { Text(afterText($0)).tag($0) }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add command" : "Edit command")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: name) { _, newValue in
                if newValue.count > Self.maxNameLength {
                    name = String(newValue.prefix(Self.maxNameLength))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("CommandCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("CommandSave")
                }
            }
        }
    }

    private func save() {
        guard let keyCode, !trimmedName.isEmpty else { return }
        let keys = KeyCombination(ctrl: ctrl, alt: alt, shift: shift, meta: meta, androidKeyCode: keyCode)
        onSave(CustomCommand(id: existing?.id ?? UUID().uuidString, name: trimmedName,
                             iconName: existing?.iconName ?? "Keyboard", keys: keys, after: after))
        dismiss()
    }
}
