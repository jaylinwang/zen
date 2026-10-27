// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Zen",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ZenCore", targets: ["ZenCore"]), .library(name: "ZenUI", targets: ["ZenUI"]), .executable(name: "Zen", targets: ["ZenApp"])],
    targets: [
        .target(name: "ZenCore"),
        .target(name: "ZenUI", dependencies: ["ZenCore"], resources: [.process("Resources")]),
        .executableTarget(name: "ZenApp", dependencies: ["ZenUI", "ZenCore"]),

        .executableTarget(name: "ZenChecks", dependencies: ["ZenCore", "ZenUI"], path: "Verification"),
        .executableTarget(name: "ZenCoreChecks", dependencies: ["ZenCore"], path: "Tests/ZenCoreTests")
    ]
)
