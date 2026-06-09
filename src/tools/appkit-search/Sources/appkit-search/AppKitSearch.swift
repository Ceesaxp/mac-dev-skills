import ArgumentParser
import Foundation
import AppKitSearchCore

@main
struct AppKitSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appkit-search",
        abstract: "BM25 search over a curated, embedded corpus of canonical AppKit patterns.",
        subcommands: []
    )
}
