import ArgumentParser
import Foundation
import AppKitSearchCore

@main
struct AppKitSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appkit-search",
        abstract: "BM25 search over a curated, embedded corpus of canonical AppKit patterns.",
        subcommands: [Search.self, Get.self, List.self, Debug.self]
    )
}

/// Load the embedded corpus, surfacing a clean error instead of trapping.
private func loadCorpus() throws -> Corpus {
    do { return try Corpus.load() }
    catch { throw ValidationError("Failed to load embedded corpus: \(error)") }
}

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search patterns. Multiple quoted args run as a batch (one query each); positional words of a single query are joined.")
    @Option(name: .long, help: "Max results per query.") var max: Int = 5
    @Option(name: .long, help: "Restrict to a category.") var category: String?
    @Argument(help: "Query words, or multiple quoted queries for batch mode.") var query: [String] = []

    func run() throws {
        let corpus = try loadCorpus()
        let engine = try SearchEngine(patterns: corpus.patterns)
        guard !query.isEmpty else { throw ValidationError("Provide at least one query.") }

        // Heuristic: a single arg containing a space, OR a single arg, is one query.
        // Multiple args are treated as a batch of distinct queries (winui convention).
        if query.count == 1 {
            let q = query[0]
            let results = engine.search(q, max: max, category: category).map(SearchHit.init)
            print(try emitJSON(SearchOutput(query: q, results: results)))
        } else {
            // Cross-query dedup: a pattern already shown in an earlier query is omitted
            // from later ones unless its score is >= 1.3x the earlier score.
            var bestSeen: [String: Double] = [:]
            var blocks: [BatchSearchOutput.QueryBlock] = []
            for q in query {
                let raw = engine.search(q, max: max, category: category)
                var kept: [SearchHit] = []
                for r in raw {
                    if let prev = bestSeen[r.id], r.score < prev * 1.3 { continue }
                    bestSeen[r.id] = Swift.max(bestSeen[r.id] ?? 0, r.score)
                    kept.append(SearchHit(r))
                }
                blocks.append(.init(query: q, results: kept))
            }
            print(try emitJSON(BatchSearchOutput(queries: blocks)))
        }
    }
}

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the full pattern(s) by id (skill convention: <= 3 ids).")
    @Argument(help: "One or more pattern ids.") var ids: [String]

    func run() throws {
        let corpus = try loadCorpus()
        var outputs: [PatternOutput] = []
        var missing: [String] = []
        for id in ids {
            if let p = corpus.byId[id] { outputs.append(PatternOutput(p)) }
            else { missing.append(id) }
        }
        if !outputs.isEmpty { print(try emitJSON(outputs.count == 1 ? AnyEncodable(outputs[0]) : AnyEncodable(outputs))) }
        if !missing.isEmpty {
            FileHandle.standardError.write(Data("Pattern(s) not found: \(missing.joined(separator: ", "))\n".utf8))
            throw ExitCode(1)
        }
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all patterns grouped by category.")
    @Option(name: .long, help: "Restrict to a category.") var category: String?

    func run() throws {
        let corpus = try loadCorpus()
        var byCategory: [String: [ListOutput.Item]] = [:]
        var order: [String] = []
        for p in corpus.patterns {
            if let cat = category, p.category.lowercased() != cat.lowercased() { continue }
            if byCategory[p.category] == nil { order.append(p.category) }
            let trimmed = p.minMacOS?.trimmingCharacters(in: .whitespaces)
            let minMac = (trimmed?.isEmpty ?? true) ? nil : trimmed
            byCategory[p.category, default: []].append(.init(id: p.id, title: p.title, minMacOS: minMac))
        }
        let groups = order.map { ListOutput.CategoryGroup(category: $0, patterns: byCategory[$0] ?? []) }
        print(try emitJSON(ListOutput(categories: groups)))
    }
}

struct Debug: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnostic: show the preprocess/tokenize/expand pipeline and unfloored top scores.")
    @Argument(help: "Query words (joined into one query).") var query: [String]

    func run() throws {
        let corpus = try loadCorpus()
        let engine = try SearchEngine(patterns: corpus.patterns)
        let q = query.joined(separator: " ")
        let preprocessed = Synonyms.preprocess(q)
        let tokens = Tokenizer.tokenize(preprocessed)
        let expanded = Synonyms.expand(tokens)
        let rawTokens = Array(Set(Tokenizer.tokenize(q))).sorted()
        // Unfloored top: search with a high max so the floor doesn't trim, then map.
        let top = engine.search(q, max: 20).map {
            DebugOutput.Scored(id: $0.id, title: $0.title, score: $0.score, hasNameBoost: $0.hasNameBoost)
        }
        print(try emitJSON(DebugOutput(
            query: q, preprocessed: preprocessed, tokens: tokens,
            expanded: expanded, rawTokens: rawTokens, top: top)))
    }
}

/// Type-erasing Encodable wrapper so `get` can emit either a single object or an array
/// through the same `emitJSON` path.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
