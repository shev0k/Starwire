import Foundation

/// The three parts of the client's identity: the certificate and private key the host pins at
/// pairing. moonlight-ios kept them as files in Documents; Starwire keeps them in the Keychain.
/// The raw values are the old file names, and the Keychain items' account names.
public enum IdentityItem: String, CaseIterable, Sendable {
    /// The certificate, PEM.
    case certificate = "client.crt"
    /// The private key, PEM. Pairing signs with it.
    case privateKey = "client.key"
    /// The certificate and key together, PKCS #12 with the passphrase "limelight", for TLS.
    case pkcs12 = "client.p12"
}

/// Where an identity can be kept. The app has two: the old files and the Keychain. Tests use
/// `MemoryIdentityStore`.
public protocol IdentityStore: AnyObject {
    func read(_ item: IdentityItem) throws -> Data?
    func write(_ data: Data, for item: IdentityItem) throws
    func delete(_ item: IdentityItem) throws
}

extension IdentityStore {
    /// All three items, or nil unless every one is there.
    public func readAll() throws -> [IdentityItem: Data]? {
        var items: [IdentityItem: Data] = [:]
        for item in IdentityItem.allCases {
            guard let data = try read(item), !data.isEmpty else {
                return nil
            }
            items[item] = data
        }
        return items
    }

    /// True if any of the three items is there.
    public func hasAny() throws -> Bool {
        try IdentityItem.allCases.contains { try read($0) != nil }
    }
}

/// An identity store in memory, for tests and the demo mode.
public final class MemoryIdentityStore: IdentityStore {
    public var items: [IdentityItem: Data]
    /// Makes every write fail, to test what happens when the Keychain refuses.
    public var failWrites = false
    /// Makes reads return these bytes instead, to test a read-back that doesn't match.
    public var corruptReads: [IdentityItem: Data] = [:]

    public init(items: [IdentityItem: Data] = [:]) {
        self.items = items
    }

    public func read(_ item: IdentityItem) throws -> Data? {
        corruptReads[item] ?? items[item]
    }

    public func write(_ data: Data, for item: IdentityItem) throws {
        if failWrites {
            throw IdentityStoreError.writeFailed(item, "refused by the test")
        }
        items[item] = data
    }

    public func delete(_ item: IdentityItem) throws {
        items[item] = nil
    }
}

public enum IdentityStoreError: Error, Equatable {
    case writeFailed(IdentityItem, String)
    case readFailed(IdentityItem, String)
    case deleteFailed(IdentityItem, String)
}

/// Moves the client's identity from the old files into the Keychain without changing a byte of
/// it, so the PC still knows this client and nobody has to pair again.
///
/// The order keeps the old files until the copy is proven: write each item, read it back,
/// compare. The files go only when `removeFiles` is on and the Keychain holds the same bytes.
/// If anything fails, the Keychain copy is removed and the app keeps using the files.
public struct IdentityMigration {
    public enum Outcome: Equatable {
        /// No identity anywhere yet: the app makes a new one, straight into the Keychain.
        case nothingToMigrate
        /// Copied from the files into the Keychain and checked.
        case migrated(filesRemoved: Bool)
        /// The Keychain had it already.
        case alreadyInKeychain(filesRemoved: Bool)
        /// The Keychain couldn't take it, or gave back different bytes. Nothing was removed; the
        /// app keeps using the files.
        case failed(String)
        /// The Keychain and the files hold different identities. Nothing was changed; the
        /// Keychain's is used, since it is the newer.
        case conflict
    }

    public var removeFiles: Bool

    public init(removeFiles: Bool) {
        self.removeFiles = removeFiles
    }

    public func run(files: IdentityStore, keychain: IdentityStore) -> Outcome {
        let fileItems = (try? files.readAll()) ?? nil
        let keychainItems: [IdentityItem: Data]?
        do {
            keychainItems = try keychain.readAll()
        } catch {
            return .failed("Keychain read: \(error)")
        }

        if let keychainItems {
            guard let fileItems else {
                return .alreadyInKeychain(filesRemoved: false)
            }
            if fileItems != keychainItems {
                return .conflict
            }
            return .alreadyInKeychain(filesRemoved: removeFiles && remove(files))
        }

        guard let fileItems else {
            return .nothingToMigrate
        }

        // Half an identity in the Keychain (an earlier try that stopped part way) is replaced.
        do {
            for item in IdentityItem.allCases {
                try keychain.write(fileItems[item]!, for: item)
            }
            guard try keychain.readAll() == fileItems else {
                undo(keychain)
                return .failed("the Keychain gave back different bytes")
            }
        } catch {
            undo(keychain)
            return .failed("\(error)")
        }
        return .migrated(filesRemoved: removeFiles && remove(files))
    }

    private func remove(_ files: IdentityStore) -> Bool {
        var removed = true
        for item in IdentityItem.allCases {
            do {
                try files.delete(item)
            } catch {
                removed = false
            }
        }
        return removed
    }

    private func undo(_ keychain: IdentityStore) {
        for item in IdentityItem.allCases {
            try? keychain.delete(item)
        }
    }
}
