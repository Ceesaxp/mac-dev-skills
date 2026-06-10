import Foundation

/// Encode any Encodable as pretty, key-sorted JSON for CLI output. Matches appkit-api.
public func emitJSON<T: Encodable>(_ value: T) throws -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try enc.encode(value), as: UTF8.self)
}

// MARK: - search output DTOs (compact; code NOT included — agent calls `get`)

public struct SearchHit: Encodable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let summary: String
    public let minMacOS: String?
    public let score: Double

    public init(_ r: SearchEngine.Result) {
        id = r.id
        title = r.title
        category = r.category
        summary = r.summary
        minMacOS = r.minMacOS
        // Round to a stable, compact precision for output.
        score = (r.score * 1000).rounded() / 1000
    }
}

public struct SearchOutput: Encodable, Sendable {
    public let query: String
    public let results: [SearchHit]
    public let hint: String
    public init(query: String, results: [SearchHit]) {
        self.query = query
        self.results = results
        self.hint = "Call `appkit-search get <id>` for full code, key APIs, imports, and pitfalls."
    }
}

public struct BatchSearchOutput: Encodable, Sendable {
    public struct QueryBlock: Encodable, Sendable {
        public let query: String
        public let results: [SearchHit]
        public init(query: String, results: [SearchHit]) {
            self.query = query
            self.results = results
        }
    }
    public let queries: [QueryBlock]
    public let hint: String
    public init(queries: [QueryBlock]) {
        self.queries = queries
        self.hint = "Call `appkit-search get <id>` for full code, key APIs, imports, and pitfalls."
    }
}

// MARK: - get output DTO (full pattern)

public struct PatternOutput: Encodable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let category: String
    public let minMacOS: String?
    public let imports: [String]
    public let keySymbols: [String]
    public let swiftCode: String
    public let pitfalls: [String]
    public let related: [String]
    public let replaces: String?
    public let whenToUse: String
    public let higReference: HIGReference

    public init(_ p: Pattern) {
        id = p.id
        title = p.title
        summary = p.summary
        category = p.category
        let trimmed = p.minMacOS?.trimmingCharacters(in: .whitespaces)
        minMacOS = (trimmed?.isEmpty ?? true) ? nil : trimmed
        imports = p.imports
        keySymbols = p.keySymbols
        swiftCode = OutputFormatting.normalizeIndent(p.swiftCode)
        pitfalls = p.pitfalls ?? []
        related = p.related ?? []
        replaces = p.replaces
        whenToUse = p.whenToUse
        higReference = p.higReference
    }
}

// MARK: - list output DTO (grouped by category)

public struct ListOutput: Encodable, Sendable {
    public struct CategoryGroup: Encodable, Sendable {
        public let category: String
        public let patterns: [Item]
        public init(category: String, patterns: [Item]) {
            self.category = category
            self.patterns = patterns
        }
    }
    public struct Item: Encodable, Sendable {
        public let id: String
        public let title: String
        public let minMacOS: String?
        public init(id: String, title: String, minMacOS: String?) {
            self.id = id
            self.title = title
            self.minMacOS = minMacOS
        }
    }
    public let categories: [CategoryGroup]
    public init(categories: [CategoryGroup]) {
        self.categories = categories
    }
}

// MARK: - debug output DTO (tuning aid)

public struct DebugOutput: Encodable, Sendable {
    public struct Scored: Encodable, Sendable {
        public let id: String
        public let title: String
        public let score: Double
        public let hasNameBoost: Bool
        public init(id: String, title: String, score: Double, hasNameBoost: Bool) {
            self.id = id
            self.title = title
            self.score = score
            self.hasNameBoost = hasNameBoost
        }
    }
    public let query: String
    public let preprocessed: String
    public let tokens: [String]
    public let expanded: [String]
    public let rawTokens: [String]
    public let top: [Scored]
    public init(query: String, preprocessed: String, tokens: [String], expanded: [String], rawTokens: [String], top: [Scored]) {
        self.query = query
        self.preprocessed = preprocessed
        self.tokens = tokens
        self.expanded = expanded
        self.rawTokens = rawTokens
        self.top = top
    }
}

// MARK: - shared output formatting

public enum OutputFormatting {
    /// Re-map the distinct leading-whitespace levels in a code block to a canonical
    /// 0/2/4/6/... scale, preserving relative nesting. Ported from winui-search
    /// `NormalizeIndent`.
    public static func normalizeIndent(_ code: String) -> String {
        if code.isEmpty { return code }
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func leadingWhitespace(_ line: String) -> Int {
            var n = 0
            for ch in line {
                if ch == " " || ch == "\t" { n += 1 } else { break }
            }
            return n
        }
        var distinct = Set<Int>()
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            distinct.insert(leadingWhitespace(line))
        }
        if distinct.isEmpty { return code }
        var map: [Int: Int] = [:]
        for (rank, d) in distinct.sorted().enumerated() { map[d] = rank * 2 }

        var out = ""
        out.reserveCapacity(code.count)
        for (i, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if i > 0 { out.append("\n") }
                continue
            }
            let indent = leadingWhitespace(line)
            if i > 0 { out.append("\n") }
            out.append(String(repeating: " ", count: map[indent] ?? 0))
            out.append(String(line.dropFirst(indent)))
        }
        return out
    }

    /// True when the Swift block is just an empty NSViewController/awakeFromNib stub
    /// with no real members — the AppKit analog of `IsBoilerplatePageWrapper`. Such
    /// stubs carry no signal and are suppressed in `get` output.
    public static func isBoilerplateStub(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression)
        // e.g. `class X: NSViewController { override func loadView() { view = NSView() } }`
        // or an empty awakeFromNib / viewDidLoad that only calls super.
        let patterns = [
            #"class\s+\w+\s*:\s*NS\w+\s*\{\s*\}$"#,
            #"override\s+func\s+(awakeFromNib|viewDidLoad)\(\)\s*\{\s*(super\.\w+\(\)\s*;?\s*)?\}\s*\}$"#,
        ]
        for pat in patterns {
            if collapsed.range(of: pat, options: .regularExpression) != nil { return true }
        }
        return false
    }
}
