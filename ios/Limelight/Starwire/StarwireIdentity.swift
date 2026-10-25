//
//  StarwireIdentity.swift
//  Starwire
//
//  The client's certificate and private key, kept in the Keychain instead of plain files in
//  Documents. The host pinned this certificate when the iPad paired, so the bytes must never
//  change: StarwireKit's IdentityMigration copies them, reads them back, and only then removes
//  the files. See docs/ios/security/2026-10-25-keychain-identity.md.
//

import Foundation
import Security
import StarwireKit

/// Keychain items, one per identity item: generic passwords under one service, readable after
/// the first unlock and never moved to another device (no backup, no iCloud Keychain).
final class KeychainIdentityStore: IdentityStore {
    let service: String

    init(service: String = "io.github.shev0k.starwire.identity") {
        self.service = service
    }

    private func query(_ item: IdentityItem) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
    }

    func read(_ item: IdentityItem) throws -> Data? {
        var query = query(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw IdentityStoreError.readFailed(item, "OSStatus \(status)")
        }
    }

    func write(_ data: Data, for item: IdentityItem) throws {
        // Replace whatever is there, so the accessibility is always the one set here
        SecItemDelete(query(item) as CFDictionary)
        var attributes = query(item)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw IdentityStoreError.writeFailed(item, "OSStatus \(status)")
        }
    }

    func delete(_ item: IdentityItem) throws {
        let status = SecItemDelete(query(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw IdentityStoreError.deleteFailed(item, "OSStatus \(status)")
        }
    }

    /// The accessibility a stored item has, for the tests and the log.
    func accessibility(_ item: IdentityItem) -> String? {
        var query = query(item)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else {
            return nil
        }
        return attributes[kSecAttrAccessible as String] as? String
    }
}

/// The old files in Documents, named as moonlight-ios named them.
final class FileIdentityStore: IdentityStore {
    let folder: URL

    init(folder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.folder = folder
    }

    func read(_ item: IdentityItem) throws -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent(item.rawValue))
    }

    func write(_ data: Data, for item: IdentityItem) throws {
        try data.write(to: folder.appendingPathComponent(item.rawValue), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(_ item: IdentityItem) throws {
        let url = folder.appendingPathComponent(item.rawValue)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// What CryptoManager reads and writes the identity through.
@objc(StarwireIdentity)
final class StarwireIdentity: NSObject {
    /// The old files go once the Keychain holds the same bytes. Batch 2 shipped first with this
    /// off and proved on the iPad that the Keychain copy kept it paired, then turned it on.
    static let removeFilesAfterMigration = false

    private static let lock = NSLock()
    private static var migrated = false
    private static var keychainUsable = true
    private static var lastOutcome = "not run"

    static var keychain: IdentityStore = KeychainIdentityStore()
    static var files: IdentityStore = FileIdentityStore()

    /// Moves the identity into the Keychain, once per launch, before anything reads it.
    @objc static func migrateIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !migrated else { return }
        migrated = true
        let outcome = IdentityMigration(removeFiles: removeFilesAfterMigration).run(files: files, keychain: keychain)
        switch outcome {
        case .failed:
            // The Keychain refused: keep using the files, and save nothing new there
            keychainUsable = false
        default:
            keychainUsable = true
        }
        lastOutcome = "\(outcome)"
        StarwireLog.info("Client identity: \(outcome)")
    }

    /// One identity item (client.crt, client.key or client.p12), or nil if there is none.
    @objc static func data(forItem name: String) -> Data? {
        migrateIfNeeded()
        guard let item = IdentityItem(rawValue: name) else { return nil }
        if keychainUsable, let data = try? keychain.read(item) {
            return data
        }
        return try? files.read(item)
    }

    /// Saves a new identity item: into the Keychain, or a file if the Keychain refuses.
    @objc static func write(_ data: Data, forItem name: String) {
        migrateIfNeeded()
        guard let item = IdentityItem(rawValue: name) else { return }
        do {
            guard keychainUsable else { throw IdentityStoreError.writeFailed(item, "Keychain not in use this launch") }
            try keychain.write(data, for: item)
        } catch {
            StarwireLog.error("Client identity: \(item.rawValue) not saved in the Keychain (\(error)); saving it as a file")
            try? files.write(data, for: item)
        }
    }

    /// How the migration went this launch, for the log and the device runs.
    @objc static var migrationOutcome: String {
        lock.lock()
        defer { lock.unlock() }
        return lastOutcome
    }

    /// For the unit tests: start again with other stores.
    static func reset(keychain: IdentityStore, files: IdentityStore) {
        lock.lock()
        self.keychain = keychain
        self.files = files
        migrated = false
        keychainUsable = true
        lastOutcome = "not run"
        lock.unlock()
    }
}
