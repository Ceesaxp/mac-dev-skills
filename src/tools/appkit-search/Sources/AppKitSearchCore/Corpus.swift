import Foundation

/// Loads the embedded curated corpus once from `Data/patterns.json` via `Bundle.module`.
/// No network, no cache, no TTL — a single embedded set, decoded at first access.
public struct Corpus: Sendable {
    /// Patterns in their on-disk (deterministic) order.
    public let patterns: [Pattern]
    /// Lookup by id.
    public let byId: [String: Pattern]

    public init(patterns: [Pattern]) {
        self.patterns = patterns
        self.byId = Dictionary(patterns.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    enum LoadError: Error, CustomStringConvertible {
        case resourceMissing
        var description: String {
            switch self {
            case .resourceMissing: return "Embedded corpus resource patterns.json not found in Bundle.module."
            }
        }
    }

    /// Decode the embedded `patterns.json`.
    public static func load() throws -> Corpus {
        guard let url = Bundle.module.url(forResource: "patterns", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let patterns = try JSONDecoder().decode([Pattern].self, from: data)
        return Corpus(patterns: patterns)
    }

    /// Shared, lazily-loaded instance. Traps on a malformed embedded corpus — that is
    /// an authoring bug the integrity tests must catch before shipping.
    public static let shared: Corpus = {
        do { return try load() }
        catch { fatalError("Failed to load embedded corpus: \(error)") }
    }()
}
