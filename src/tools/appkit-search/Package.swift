// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "appkit-search",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "AppKitSearchCore",
            resources: [.process("Data")]
        ),
        .executableTarget(
            name: "appkit-search",
            dependencies: [
                "AppKitSearchCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "AppKitSearchCoreTests", dependencies: ["AppKitSearchCore"])
    ]
)
