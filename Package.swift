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
        .target(
            name: "WickCore",
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
        )
    ]
)
