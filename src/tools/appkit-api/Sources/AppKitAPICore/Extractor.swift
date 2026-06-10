import Foundation
import Subprocess
import System

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

    public func sdkPath() async throws -> String { try await Self.output(of: "/usr/bin/xcrun", arguments: ["--sdk", "macosx", "--show-sdk-path"]) }
    public func sdkVersion() async throws -> String { try await Self.output(of: "/usr/bin/xcrun", arguments: ["--sdk", "macosx", "--show-sdk-version"]) }

    /// Ensure the symbol graphs for `module` are present in cache; extract if missing. Returns the cache dir.
    @discardableResult
    public func ensureExtracted(module: String) async throws -> URL {
        let version = try await sdkVersion()
        let dir = Self.cacheDir(sdkVersion: version, module: module)
        let primary = dir.appendingPathComponent("\(module).symbols.json")
        if FileManager.default.fileExists(atPath: primary.path) { return dir }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sdk = try await sdkPath()
        let target = Self.targetTriple(sdkVersion: version)
        let args = Self.extractArguments(module: module, sdkPath: sdk, target: target, outputDir: dir.path)
        _ = try await Self.output(of: "/usr/bin/swift", arguments: args)
        guard FileManager.default.fileExists(atPath: primary.path) else { throw ExtractorError.noGraphs(dir) }
        return dir
    }

    /// Load all `<module>*.symbols.json` files in `dir` into decoded graphs.
    public func loadGraphs(in dir: URL, module: String) throws -> [SymbolGraph] {
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { f in
                let n = f.lastPathComponent
                return f.pathExtension == "json" && (n == "\(module).symbols.json" || n.hasPrefix("\(module)@"))
            }
        guard !files.isEmpty else { throw ExtractorError.noGraphs(dir) }
        let dec = JSONDecoder()
        return try files.map { try dec.decode(SymbolGraph.self, from: Data(contentsOf: $0)) }
    }

    /// Build a ready-to-query index for a module (extracting + caching as needed).
    public func index(module: String) async throws -> SymbolIndex {
        let dir = try await ensureExtracted(module: module)
        return SymbolIndex(graphs: try loadGraphs(in: dir, module: module))
    }

    /// Runs a subprocess (via swift-subprocess) and returns its stdout as a trimmed string.
    /// Intended for short-output commands such as `xcrun` or the `swift` driver (whose symbol
    /// graphs go to `-output-dir`, not stdout). The 8 MiB collection limit is far above what
    /// these commands emit, so output is never truncated in practice.
    @discardableResult
    static func output(of launchPath: String, arguments args: [String]) async throws -> String {
        let result = try await Subprocess.run(
            .path(FilePath(launchPath)),
            arguments: Arguments(args),
            output: .string(limit: 8 * 1024 * 1024),
            error: .string(limit: 8 * 1024 * 1024)
        )
        if case .exited(0) = result.terminationStatus {
            return (result.standardOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let code: Int32
        switch result.terminationStatus {
        case let .exited(c): code = c
        case let .signaled(c): code = c
        }
        throw ExtractorError.command("\(launchPath) \(args.joined(separator: " "))",
                                     code,
                                     result.standardError ?? "")
    }
}
