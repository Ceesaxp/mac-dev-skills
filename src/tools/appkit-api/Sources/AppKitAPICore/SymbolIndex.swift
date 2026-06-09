import Foundation

public struct SymbolIndex: Sendable {
    private let all: [Symbol]
    private let byPrecise: [String: Symbol]
    private let byQualified: [String: [Symbol]]
    private let memberPreciseByContainer: [String: [String]]

    public var symbolCount: Int { all.count }

    public init(graphs: [SymbolGraph]) {
        var all: [Symbol] = []
        var byPrecise: [String: Symbol] = [:]
        var byQualified: [String: [Symbol]] = [:]
        var members: [String: [String]] = [:]

        for graph in graphs {
            for s in graph.symbols {
                all.append(s)
                byPrecise[s.identifier.precise] = s
                byQualified[s.qualifiedName, default: []].append(s)
            }
            for r in graph.relationships where r.kind == "memberOf" {
                members[r.target, default: []].append(r.source)
            }
        }
        self.all = all
        self.byPrecise = byPrecise
        self.byQualified = byQualified
        self.memberPreciseByContainer = members
    }

    /// Exact qualified-name lookup ("Type" or "Type.member"). Returns the first match.
    public func check(_ qualified: String) -> Symbol? {
        byQualified[qualified]?.first
    }

    /// All symbols whose qualified name or title contains `name`.
    public func availability(of name: String) -> [Symbol] {
        if let exact = byQualified[name] { return exact }
        let lower = name.lowercased()
        return all.filter {
            $0.qualifiedName.lowercased() == lower || $0.names.title.lowercased() == lower
        }
    }

    /// Members of a type, resolved via the `memberOf` relationship.
    public func members(of typeName: String) -> [Symbol] {
        guard let container = byQualified[typeName]?.first else { return [] }
        let ids = memberPreciseByContainer[container.identifier.precise] ?? []
        return ids.compactMap { byPrecise[$0] }
            .sorted { $0.names.title < $1.names.title }
    }

    /// Enum cases of an enum type (members whose kind is an enum case).
    public func enumCases(of typeName: String) -> [Symbol] {
        members(of: typeName).filter { $0.kind.identifier == "swift.enum.case" }
    }

    /// Fuzzy search over titles and qualified names: exact > prefix > contains.
    public func search(_ query: String, limit: Int) -> [Symbol] {
        let q = query.lowercased()
        func score(_ s: Symbol) -> Int? {
            let t = s.names.title.lowercased()
            let qn = s.qualifiedName.lowercased()
            if t == q { return 0 }
            if t.hasPrefix(q) { return 1 }
            if qn.hasPrefix(q) { return 2 }
            if t.contains(q) { return 3 }
            if qn.contains(q) { return 4 }
            return nil
        }
        return all
            .compactMap { s in score(s).map { (s, $0) } }
            .sorted { ($0.1, $0.0.names.title) < ($1.1, $1.0.names.title) }
            .prefix(limit)
            .map(\.0)
    }
}
