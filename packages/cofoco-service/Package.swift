// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CofocoService",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "cofoco-service", targets: ["CofocoService"])],
    dependencies: [
        .package(path: "../cofoco-core"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.101.2"),
    ],
    targets: [
        .executableTarget(name: "CofocoService", dependencies: [
            .product(name: "CofocoCore", package: "cofoco-core"),
            .product(name: "MCP", package: "swift-sdk"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
        ]),
        .testTarget(name: "CofocoServiceTests", dependencies: ["CofocoService"]),
    ]
)
