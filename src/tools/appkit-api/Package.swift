// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "appkit-api",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(name: "AppKitAPICore"),
        .executableTarget(
            name: "appkit-api",
            dependencies: [
                "AppKitAPICore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "AppKitAPICoreTests", dependencies: ["AppKitAPICore"])
    ]
)
