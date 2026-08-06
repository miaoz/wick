// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Wick",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Wick",
            targets: ["Wick"]
        )
    ],
    targets: [
        // Platform-independent journal models + sync engine (reusable by a future iOS app).
        .target(
            name: "WickSync",
            path: "Sources/WickSync"
        ),
        .target(
            name: "WickCore",
            dependencies: ["WickSync"],
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
        )
    ]
)
