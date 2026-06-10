// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "appkit-api",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "0.5.0")
    ],
    targets: [
        .target(
            name: "AppKitAPICore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess")
            ]
        ),
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
