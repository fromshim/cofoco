// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CofocoApp",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Cofoco", targets: ["CofocoApp"])],
    targets: [
        .executableTarget(name: "CofocoApp"),
        .testTarget(name: "CofocoAppTests", dependencies: ["CofocoApp"]),
    ]
)
