import ArgumentParser
import Foundation
import AppKitAPICore

@main
struct AppKitAPI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appkit-api",
        abstract: "Query macOS SDK API existence and availability from symbol-graph data.",
        subcommands: [Check.self, Members.self, AvailabilityCmd.self, Search.self, Enums.self]
    )
}

struct ModuleOption: ParsableArguments {
    @Option(name: .long, help: "SDK module to query (default: AppKit).")
    var module: String = "AppKit"
}

private func loadIndex(_ module: String) async throws -> SymbolIndex {
    do { return try await Extractor().index(module: module) }
    catch { throw ValidationError("Failed to load \(module) symbol graph: \(error)") }
}

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check whether a symbol exists (e.g. NSGlassEffectView.effectIsInteractive).")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Qualified name: Type or Type.member.") var symbol: String

    func run() async throws {
        let index = try await loadIndex(opts.module)
        if let s = index.check(symbol) {
            struct R: Encodable { let query: String; let exists: Bool; let symbol: SymbolOut }
            print(try emitJSON(R(query: symbol, exists: true, symbol: SymbolOut(s))))
        } else {
            struct R: Encodable { let query: String; let exists: Bool }
            print(try emitJSON(R(query: symbol, exists: false)))
            throw ExitCode(1)
        }
    }
}

struct Members: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the members of a type.")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Type name, e.g. NSGlassEffectView.") var type: String

    func run() async throws {
        let index = try await loadIndex(opts.module)
        struct R: Encodable { let type: String; let members: [SymbolOut] }
        print(try emitJSON(R(type: type, members: index.members(of: type).map(SymbolOut.init))))
    }
}

struct AvailabilityCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "availability", abstract: "Show macOS availability for a symbol.")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Symbol name (title or qualified).") var symbol: String

    func run() async throws {
        let index = try await loadIndex(opts.module)
        struct R: Encodable { let symbol: String; let matches: [SymbolOut] }
        print(try emitJSON(R(symbol: symbol, matches: index.availability(of: symbol).map(SymbolOut.init))))
    }
}

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fuzzy-search symbols by name.")
    @OptionGroup var opts: ModuleOption
    @Option(name: .long, help: "Max results.") var limit: Int = 20
    @Argument(help: "Query.") var query: String

    func run() async throws {
        let index = try await loadIndex(opts.module)
        struct R: Encodable { let query: String; let results: [SymbolOut] }
        print(try emitJSON(R(query: query, results: index.search(query, limit: limit).map(SymbolOut.init))))
    }
}

struct Enums: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the cases of an enum type.")
    @OptionGroup var opts: ModuleOption
    @Argument(help: "Enum type name.") var type: String

    func run() async throws {
        let index = try await loadIndex(opts.module)
        struct R: Encodable { let type: String; let cases: [SymbolOut] }
        print(try emitJSON(R(type: type, cases: index.enumCases(of: type).map(SymbolOut.init))))
    }
}
