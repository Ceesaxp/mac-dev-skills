import Foundation

public struct Extractor: Sendable {
    public init() {}

    // ---- Pure helpers (unit-tested) ----

    public static func targetTriple(sdkVersion: String) -> String {
        "arm64-apple-macos\(sdkVersion)"
    }

    public static func cacheDir(sdkVersion: String, module: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/appkit-api", isDirectory: true)
            .appendingPathComponent(sdkVersion, isDirectory: true)
            .appendingPathComponent(module, isDirectory: true)
    }

    public static func extractArguments(module: String, sdkPath: String, target: String, outputDir: String) -> [String] {
        ["symbolgraph-extract",
         "-module-name", module,
         "-sdk", sdkPath,
         "-target", target,
         "-minimum-access-level", "public",
         "-output-dir", outputDir]
    }

    // ---- Live operations (exercised by the end-to-end step, not unit tests) ----

    public enum ExtractorError: Error, CustomStringConvertible {
        case command(String, Int32, String)
        case noGraphs(URL)
        public var description: String {
            switch self {
            case let .command(cmd, code, err): return "`\(cmd)` failed (exit \(code)): \(err)"
            case let .noGraphs(dir): return "no .symbols.json found in \(dir.path)"
            }
        }
    }

    public func sdkPath() throws -> String { try Self.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"]) }
    public func sdkVersion() throws -> String { try Self.run("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"]) }

    /// Ensure the symbol graphs for `module` are present in cache; extract if missing. Returns the cache dir.
    @discardableResult
    public func ensureExtracted(module: String) throws -> URL {
        let version = try sdkVersion()
        let dir = Self.cacheDir(sdkVersion: version, module: module)
        let primary = dir.appendingPathComponent("\(module).symbols.json")
        if FileManager.default.fileExists(atPath: primary.path) { return dir }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sdk = try sdkPath()
        let target = Self.targetTriple(sdkVersion: version)
        let args = Self.extractArguments(module: module, sdkPath: sdk, target: target, outputDir: dir.path)
        _ = try Self.run("/usr/bin/swift", args)
        guard FileManager.default.fileExists(atPath: primary.path) else { throw ExtractorError.noGraphs(dir) }
        return dir
    }

    /// Load all `<module>*.symbols.json` files in `dir` into decoded graphs.
    public func loadGraphs(in dir: URL, module: String) throws -> [SymbolGraph] {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(module) && $0.pathExtension == "json" }
        guard !files.isEmpty else { throw ExtractorError.noGraphs(dir) }
        let dec = JSONDecoder()
        return try files.map { try dec.decode(SymbolGraph.self, from: Data(contentsOf: $0)) }
    }

    /// Build a ready-to-query index for a module (extracting + caching as needed).
    public func index(module: String) throws -> SymbolIndex {
        let dir = try ensureExtracted(module: module)
        return SymbolIndex(graphs: try loadGraphs(in: dir, module: module))
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out; proc.standardError = err
        try proc.run(); proc.waitUntilExit()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if proc.terminationStatus != 0 {
            throw ExtractorError.command("\(launchPath) \(args.joined(separator: " "))",
                                         proc.terminationStatus,
                                         String(decoding: errData, as: UTF8.self))
        }
        return outStr
    }
}
