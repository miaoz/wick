// swift-tools-version: 6.2
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
        .executableTarget(
            name: "Wick"
        )
    ]
)
