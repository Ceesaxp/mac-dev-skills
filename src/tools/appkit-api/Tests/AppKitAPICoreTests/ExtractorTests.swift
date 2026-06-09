import Testing
import Foundation
@testable import AppKitAPICore

@Test func buildsTargetTriple() {
    #expect(Extractor.targetTriple(sdkVersion: "27.0") == "arm64-apple-macos27.0")
    #expect(Extractor.targetTriple(sdkVersion: "26.1") == "arm64-apple-macos26.1")
}

@Test func cacheDirIsKeyedBySDKVersionAndModule() {
    let dir = Extractor.cacheDir(sdkVersion: "27.0", module: "AppKit")
    #expect(dir.pathComponents.contains("appkit-api"))
    #expect(dir.pathComponents.contains("27.0"))
    #expect(dir.lastPathComponent == "AppKit")
}

@Test func extractArgsUseExplicitMacosSDK() {
    let args = Extractor.extractArguments(module: "AppKit", sdkPath: "/SDK", target: "arm64-apple-macos27.0", outputDir: "/out")
    #expect(args.contains("symbolgraph-extract"))
    #expect(args.contains("-module-name")); #expect(args.contains("AppKit"))
    #expect(args.contains("-sdk")); #expect(args.contains("/SDK"))
    #expect(args.contains("-target")); #expect(args.contains("arm64-apple-macos27.0"))
    #expect(args.contains("-minimum-access-level")); #expect(args.contains("public"))
    #expect(args.contains("-output-dir")); #expect(args.contains("/out"))
}
