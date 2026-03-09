// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CandleMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CandleMenuBar",
            targets: ["CandleMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CandleMenuBar"
        )
    ]
)
