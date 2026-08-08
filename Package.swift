// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Wick",
    platforms: [
        .macOS(.v13),
        // The shared WickSync target supports iOS; macOS-only targets are
        // simply never built for it (the iPhone app links WickSync alone).
        .iOS(.v16)
    ],
    products: [
        .executable(
            name: "Wick",
            targets: ["Wick"]
        ),
        // Consumed by the iOS app via a local package reference.
        .library(
            name: "WickSync",
            targets: ["WickSync"]
        ),
        // Shared trading calendar (physics + data + SwiftUI/SpriteKit rendering),
        // consumed by both the macOS app and the iOS app.
        .library(
            name: "WickCalendarKit",
            targets: ["WickCalendarKit"]
        )
    ],
    targets: [
        // Platform-independent journal models + sync engine (reusable by a future iOS app).
        .target(
            name: "WickSync",
            path: "Sources/WickSync"
        ),
        // Cross-platform trading calendar (macOS + iOS): data, paper physics, and the
        // SwiftUI/SpriteKit rendering. Depends on WickSync for L10n/AppLanguage/day keys.
        .target(
            name: "WickCalendarKit",
            dependencies: ["WickSync"],
            path: "Sources/WickCalendarKit"
        ),
        .target(
            name: "WickCore",
            dependencies: ["WickSync", "WickCalendarKit"],
            path: "Sources/WickCore"
        ),
        .executableTarget(
            name: "Wick",
            dependencies: ["WickCore"],
            path: "Sources/Wick"
        ),
        .testTarget(
            name: "WickTests",
            dependencies: ["WickCore"],
            path: "Tests/WickTests"
        ),
        .testTarget(
            name: "WickSyncTests",
            dependencies: ["WickSync"],
            path: "Tests/WickSyncTests"
        ),
        .testTarget(
            name: "WickCalendarKitTests",
            dependencies: ["WickCalendarKit"],
            path: "Tests/WickCalendarKitTests"
        )
    ]
)
