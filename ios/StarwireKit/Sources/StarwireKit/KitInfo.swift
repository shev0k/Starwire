// A placeholder so the package builds and its tests run on every platform. Phase 1 replaces it
// with the settings store; see docs/ios/port-plan.md.

/// What this build of StarwireKit is.
public struct KitInfo: Sendable, Equatable {
    /// The package's name, as shown in logs and the About screen.
    public let name: String
    /// The oldest iOS and iPadOS major version the app supports.
    public let minimumOSMajorVersion: Int

    public init(name: String = "StarwireKit", minimumOSMajorVersion: Int = 17) {
        self.name = name
        self.minimumOSMajorVersion = minimumOSMajorVersion
    }

    /// The values the app ships with.
    public static let current = KitInfo()
}
