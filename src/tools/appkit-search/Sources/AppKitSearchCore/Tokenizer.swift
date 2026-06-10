import Foundation

/// The single tokenizer, ported from winui-search `BM25.Tokenize` in exact order:
/// (1) invariant lowercase, (2) regex `[^a-z0-9\s\-] -> ' '` (hyphens preserved),
/// (3) split on the ASCII space, (4) keep words with `count > 1` that aren't stopwords.
///
/// No stemming happens here — stemming is upstream in `Synonyms.preprocess`. CamelCase
/// splitting is a separate helper (`splitCamelCase`) fed as its own weighted doc field.
public enum Tokenizer {
    // [^a-z0-9\s\-] — strip everything that isn't a lowercase letter, digit, whitespace,
    // or hyphen. Applied AFTER lowercasing, so only `a-z` is needed.
    private static let nonAlpha = try! NSRegularExpression(pattern: "[^a-z0-9\\s\\-]")

    /// Locale-independent (invariant) lowercasing matching .NET `ToLowerInvariant`.
    /// Using the fixed `en_US_POSIX` locale avoids the Turkish dotless-i problem
    /// (where `I`.lowercased() would yield `ı` under a Turkish host locale).
    public static func invariantLowercased(_ s: String) -> String {
        s.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    public static func tokenize(_ text: String) -> [String] {
        let lower = invariantLowercased(text)
        let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let stripped = nonAlpha.stringByReplacingMatches(in: lower, range: range, withTemplate: " ")
        // Split on the ASCII space only, dropping empty entries (RemoveEmptyEntries).
        return stripped.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.count > 1 && !StopWords.common.contains($0) }
    }

    /// Lowercase + strip every non-`[a-z0-9]` char (no separators). Builds the
    /// no-separator form used for compound/substring name boosts.
    public static func compactQuery(_ q: String) -> String {
        let lower = invariantLowercased(q)
        return String(lower.unicodeScalars.filter {
            ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9")
        })
    }

    /// Split a CamelCase/PascalCase identifier into space-separated words.
    /// "NSGlassEffectView" -> "NS Glass Effect View"; "ColorPicker" -> "Color Picker".
    /// A space is inserted before an uppercase char when the previous char is lowercase
    /// OR the next char is lowercase (so the trailing cap of an acronym joins the
    /// following word: "NSGlass" -> "NS Glass").
    public static func splitCamelCase(_ s: String) -> String {
        if s.isEmpty { return s }
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(s.count + 8)
        for i in 0..<chars.count {
            let c = chars[i]
            if i > 0 && c.isUppercase
                && (chars[i - 1].isLowercase || (i + 1 < chars.count && chars[i + 1].isLowercase)) {
                out.append(" ")
            }
            out.append(c)
        }
        return out
    }
}
