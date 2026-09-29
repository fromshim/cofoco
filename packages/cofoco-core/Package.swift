// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CofocoCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CofocoCore", targets: ["CofocoCore"])],
    targets: [
        .target(name: "CofocoCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "CofocoCoreTests", dependencies: ["CofocoCore"]),
    ]
)
