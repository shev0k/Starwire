// swift-tools-version:5.9
//
// StarwireKit: the app's logic with no UIKit, so its tests run on Windows, macOS and CI with
// `swift test`. See docs/ios/port-plan.md ("Architecture") for what moves in here.

import PackageDescription

let package = Package(
    name: "StarwireKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "StarwireKit", targets: ["StarwireKit"]),
    ],
    targets: [
        .target(name: "StarwireKit"),
        // Fixtures are read from disk by path (FixtureFile), so they work the same on every platform
        .testTarget(name: "StarwireKitTests", dependencies: ["StarwireKit"], exclude: ["Fixtures"]),
    ]
)
