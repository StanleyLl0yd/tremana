// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TreMana",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "TreMana", targets: ["TreMana"]),
        .library(name: "TreManaCore", targets: ["TreManaCore"])
    ],
    targets: [
        .target(name: "TreManaCore"),
        .executableTarget(name: "TreMana", dependencies: ["TreManaCore"], resources: [.process("Resources")]),
        .testTarget(name: "TreManaCoreTests", dependencies: ["TreManaCore"])
    ],
    swiftLanguageModes: [.v6]
)
