// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CofocoCLI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CofocoCLI", targets: ["CofocoCLI"]),
        .executable(name: "cofoco", targets: ["cofoco"]),
    ],
    targets: [
        .target(name: "CofocoCLI", linkerSettings: [.linkedFramework("Security")]),
        .executableTarget(name: "cofoco", dependencies: ["CofocoCLI"]),
        .testTarget(name: "CofocoCLITests", dependencies: ["CofocoCLI"]),
    ]
)
