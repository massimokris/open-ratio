// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RatioNative",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RatioCore", targets: ["RatioCore"]),
        .executable(name: "RatioNative", targets: ["RatioNative"])
    ],
    targets: [
        .target(name: "RatioCore"),
        .executableTarget(name: "RatioNative", dependencies: ["RatioCore"]),
        .testTarget(name: "RatioCoreTests", dependencies: ["RatioCore"])
    ],
    swiftLanguageVersions: [.v5]
)
