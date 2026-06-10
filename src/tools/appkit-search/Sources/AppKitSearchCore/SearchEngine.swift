import Foundation

/// Flat BM25 search over the curated AppKit corpus (one doc per pattern — no nested
/// scenarios, no source split). Ports winui-search `SearchEngine` ranking: weighted
/// doc fields, post-BM25 multiplicative name boosts against the compact query, a
/// generic-title demotion, a platform-keyword reverse-map boost, the 70% relevance
/// floor, and the coverage gate computed from RAW (un-expanded) query tokens.
public final class SearchEngine: Sendable {
    public struct Result: Sendable, Equatable {
        public let id: String
        public let title: String
        public let category: String
        public let summary: String
        public let minMacOS: String?
        public let score: Double
        public let hasNameBoost: Bool
    }

    private let patterns: [Pattern]

    public init(patterns: [Pattern]) throws {
        self.patterns = patterns
    }

    // ─── Per-pattern doc field weights (homogeneous-corpus retranslation) ───
    private static let wKeySymbols = 5.0   // author-curated APIs — strongest signal
    private static let wTags = 3.0
    private static let wTitle = 3.0
    private static let wTitleSplit = 2.5   // camelCase-split title, separate field
    private static let wSummary = 1.0
    private static let wId = 1.0

    /// Platform-intent query keywords -> the specific pattern id to boost (×1.6).
    /// Keys are lowercase single tokens (after preprocess/tokenize).
    static let platformKeywordToPatternId: [String: String] = [
        "glass": "glass-effect-view-basic",
        "concentric": "concentric-corner-configuration",
        "concentricity": "concentric-corner-configuration",
        "sidebar": "splitviewcontroller-sidebar-inspector",
        "inspector": "splitviewcontroller-sidebar-inspector",
        "drag": "tableview-drag-drop-pasteboard-writer",
        "drop": "tableview-drag-drop-pasteboard-writer",
        "dragdrop": "tableview-drag-drop-pasteboard-writer",
        "picker": "open-save-panel-utype",
        "filepicker": "open-save-panel-utype",
        "folderpicker": "open-save-panel-utype",
        "statusitem": "statusitem-menubar-extra",
        "menulet": "statusitem-menubar-extra",
        "tray": "statusitem-menubar-extra",
    ]

    private func buildDoc(for p: Pattern) -> BM25.Doc {
        BM25.buildDoc([
            (p.keySymbols.joined(separator: " "), Self.wKeySymbols),
            (p.tags.joined(separator: " "), Self.wTags),
            (p.title, Self.wTitle),
            (Tokenizer.splitCamelCase(p.title), Self.wTitleSplit),
            (p.summary, Self.wSummary),
            (p.id, Self.wId),
        ])
    }

    /// Run the full pipeline and return ranked results after boosts + floor + gate.
    public func search(_ query: String, max maxResults: Int = 5, category: String? = nil) -> [Result] {
        // Pipeline order: raw -> preprocess -> tokenize -> expand -> score.
        let preprocessed = Synonyms.preprocess(query)
        let queryWords = Tokenizer.tokenize(preprocessed)
        if queryWords.isEmpty { return [] }
        let queryCompact = Tokenizer.compactQuery(query)
        let expandedWords = Synonyms.expand(queryWords)

        // Coverage gate inputs: RAW query tokens (NOT preprocessed/expanded), distinct.
        let rawQueryTokens = Array(Set(Tokenizer.tokenize(query)))
        let applyCoverageGate = rawQueryTokens.count >= 3
        let coverageMin = (rawQueryTokens.count + 1) / 2  // ceil(N/2)

        // Targeted platform-intent boosts.
        var platformBoostIds = Set<String>()
        for w in queryWords {
            if let pid = Self.platformKeywordToPatternId[w] { platformBoostIds.insert(pid) }
        }
        let platformKeywordsInQuery = queryWords.filter { Self.platformKeywordToPatternId[$0] != nil }
        let nonPlatformQueryWords = queryWords.filter { Self.platformKeywordToPatternId[$0] == nil }

        let docs = patterns.map(buildDoc(for:))
        let corpus = BM25.buildCorpus(docs)

        // Longest compact title contained in the query (most-specific compound wins big).
        var longestCompactMatch: String? = nil
        for p in patterns {
            let compactTitle = Tokenizer.compactQuery(p.title)
            if compactTitle.count >= 8 && queryCompact.contains(compactTitle) {
                if longestCompactMatch == nil || compactTitle.count > longestCompactMatch!.count {
                    longestCompactMatch = compactTitle
                }
            }
        }

        var results: [Result] = []
        for (i, p) in patterns.enumerated() {
            if let cat = category, p.category.lowercased() != cat.lowercased() { continue }

            var s = BM25.score(docs[i], expandedWords, corpus)
            let titleLower = Tokenizer.invariantLowercased(p.title)
            let titleCompact = Tokenizer.compactQuery(p.title)
            var hasNameBoost = false

            // Substring boost: a long (>=6) query word fully inside the compact title.
            // Skip platform keywords (they have their own targeted boost).
            for qw in queryWords {
                if qw.count >= 6 && Self.platformKeywordToPatternId[qw] == nil && titleCompact.contains(qw) {
                    s *= 2.5
                    hasNameBoost = true
                    break
                }
            }

            // Whole-word title match.
            if titleLower.count > 2 {
                let titleTokens = Set(Tokenizer.tokenize(p.title))
                if queryWords.contains(where: { titleTokens.contains($0) }) {
                    s *= 2.0
                    hasNameBoost = true
                }
            }

            // Compound-title match — longest wins big (×4.0), others mild (×1.3).
            if titleCompact.count >= 8 && queryCompact.contains(titleCompact) {
                s *= (titleCompact == longestCompactMatch) ? 4.0 : 1.3
                hasNameBoost = true
            }

            // Platform-keyword reverse-map boost on the targeted pattern.
            if platformBoostIds.contains(p.id) {
                s *= 1.6
                hasNameBoost = true
            }

            // Reverse demotion: title contains a platform keyword from the query (e.g.
            // a *Picker pattern matched on "picker") but no non-keyword query word
            // independently matches the title/tags/keySymbols. The targeted pattern
            // already covers this intent, so demote the incidental match.
            if !platformKeywordsInQuery.isEmpty
                && platformKeywordsInQuery.contains(where: { titleLower.contains($0) })
                && !platformBoostIds.contains(p.id) {
                let hay = (p.title + " " + p.tags.joined(separator: " ")
                    + " " + p.keySymbols.joined(separator: " ")).lowercased()
                let hasOther = nonPlatformQueryWords.contains { hay.contains($0) }
                if !hasOther { s *= 0.3 }
            }

            // Generic-title demotion (placeholder-ish titles).
            if Self.isGenericTitle(p.title) { s *= 0.85 }

            // Coverage gate from RAW tokens; skipped when name-boosted.
            if applyCoverageGate && !hasNameBoost
                && BM25.countHits(docs[i], rawQueryTokens) < coverageMin {
                s = 0
            }

            if s <= 0 { continue }
            results.append(Result(
                id: p.id, title: p.title, category: p.category,
                summary: p.summary, minMacOS: normalizedMinMacOS(p.minMacOS),
                score: s, hasNameBoost: hasNameBoost))
        }

        // Stable sort: score desc, then id asc for determinism.
        results.sort { a, b in a.score != b.score ? a.score > b.score : a.id < b.id }

        // Relevance floor on runners-up: need >= 70% of top score. Top-1 always kept.
        if results.count > 1 {
            let floor = results[0].score * 0.70
            results = results.enumerated()
                .filter { $0.offset == 0 || $0.element.score >= floor }
                .map { $0.element }
        }

        return Array(results.prefix(maxResults))
    }

    /// Empty/nil minMacOS means broadly available — surface as nil.
    private func normalizedMinMacOS(_ v: String?) -> String? {
        guard let v, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    /// Placeholder-ish titles that deserve a small demotion.
    static func isGenericTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if t.lowercased() == "basic usage" { return true }
        if t.range(of: "^Example\\s*\\d*$", options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if t.range(of: "^Sample\\s*\\d*$", options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return false
    }
}
