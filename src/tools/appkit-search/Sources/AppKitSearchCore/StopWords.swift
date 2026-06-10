import Foundation

/// Stop words ported verbatim from winui-search `StopWords.cs`.
///
/// `common` is the hot-path query+index stoplist applied INSIDE `Tokenizer.tokenize`
/// (dropped from both query tokens and indexed doc text). `tagOnly` is the
/// superset-only-for-tags list, removed from curated tag arrays via `filterTagList`
/// but NOT from tokenization, so a query like "text view" keeps "text" and still
/// matches NSTextView via its camelCase-split title field.
public enum StopWords {
    /// Common words that don't help discriminate between patterns. ~180 words.
    /// BM25 already does IDF weighting, but stripping these saves space/tokens.
    public static let common: Set<String> = [
        // Articles, conjunctions, pronouns, prepositions
        "the", "a", "an", "and", "or", "is", "are", "was", "were", "be", "been",
        "can", "will", "that", "this", "it", "its", "in", "on", "of", "to", "for",
        "with", "by", "from", "as", "at", "has", "have", "had", "not", "but",
        "all", "any", "each", "how", "when", "where", "which", "who", "you", "your",
        "we", "our", "they", "them", "their", "also", "more", "than", "like", "just",
        "about", "into", "over", "such", "only", "very", "well", "see",
        // Generic verbs
        "use", "used", "using", "set", "get", "make", "made",
        "displays", "display", "displaying", "presents", "shows", "show", "lets", "let",
        "between", "while", "contain", "contains", "containing",
        "maintain", "maintains", "maintaining",
        // Generic UI nouns (no discrimination value across many controls)
        "control", "controls", "property", "properties", "value", "values",
        "default", "custom", "new", "component", "sample", "example",
        "user", "content", "app", "item", "items", "element", "elements",
        // Tech terms / infra
        "csharp", "xaml", "uwp", "winui", "communitytoolkit",
        // Description filler from docs
        "some", "note", "however", "should", "similar", "objects", "object", "allows",
        "setting", "based", "usage", "having", "public", "instead", "provide", "found",
        "does", "support", "many", "main", "case", "create", "certain",
        "depending", "technical", "reasons", "inherits", "treated", "added", "whichever",
        "acts", "provided", "subsequent", "happens", "sequentially", "pretty", "shares",
        "needs", "generate", "accessible", "replacement", "look", "specify",
        "interface", "represents", "source", "whose", "loaded", "ienumerable",
        "instances", "instance", "examples",
        // Auto-extraction noise from sample code / commit messages
        "true", "false", "pass", "done", "constructor",
        "functionality", "effect", "through", "various", "modern", "easy", "simple",
        "kind", "type", "types", "approach", "amount", "least", "space",
        // Low-signal words common in sample header text
        "basic", "adding", "changes", "header", "options", "another",
    ]

    /// Words that pollute curated tag lists but a user might legitimately type as a
    /// query token. Removed from tag dictionaries (in `filterTagList`) but NOT from
    /// `Tokenizer.tokenize`.
    public static let tagOnly: Set<String> = [
        "text",     // *Text* patterns keep it via camelCase-split title
        "input",    // input controls keep it via title split
        "layout",   // near-zero IDF subcategory noise
        "pick",     // picker patterns keep "picker" via title split
        "basics",   // section heading filler
        "advanced", // kept via title split where it matters
    ]

    /// True if the token should be dropped from BOTH query tokens AND tag dicts.
    public static func isCommon(_ w: String) -> Bool { common.contains(w) }

    /// True if the token should be dropped from tag dicts (a superset of `isCommon`).
    public static func isTagNoise(_ w: String) -> Bool { common.contains(w) || tagOnly.contains(w) }

    /// Drops stop words (common + tagOnly), single-word `*sample`-suffix tokens, and
    /// dedupes (case-folded, order-preserving). Multi-word tags ("context menu") are
    /// preserved as-is. Use this for tag arrays; for query tokenization use `isCommon`.
    public static func filterTagList(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(tags.count)
        for t in tags {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = Tokenizer.invariantLowercased(trimmed)
            if isTagNoise(lower) { continue }
            // Drop auto-extracted *sample suffix tokens like "imagecroppersample"
            // (only single-word tokens; preserve multi-word tags as-is).
            if !lower.contains(" "), lower.count > "sample".count, lower.hasSuffix("sample") {
                continue
            }
            if seen.insert(lower).inserted { result.append(lower) }
        }
        return result
    }
}
