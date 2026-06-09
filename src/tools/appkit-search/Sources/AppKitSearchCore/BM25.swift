import Foundation

/// BM25 ranking, ported 1:1 from winui-search `BM25.cs`. Constants `k1=1.2`, `b=0.75`.
///
/// The clever, load-bearing detail: `tf` is NOT an integer count — it is a WEIGHTED
/// field-sum. `buildDoc` accumulates `tf[word] += weight` per token and `length +=
/// weight` per token, so a term in a weight-5.0 field contributes 5.0 to tf. This
/// reproduces the upstream weighted-field design instead of BM25F.
public enum BM25 {
    static let k1 = 1.2
    static let b = 0.75

    public struct Doc {
        public var tf: [String: Double] = [:]
        public var length: Double = 0
    }

    public struct Corpus {
        public var df: [String: Int] = [:]
        public var n: Int = 0
        public var avgDl: Double = 0
    }

    /// Accumulate weighted term frequencies and document length across fields.
    public static func buildDoc(_ fields: [(text: String, weight: Double)]) -> Doc {
        var doc = Doc()
        for (text, weight) in fields {
            for word in Tokenizer.tokenize(text) {
                doc.tf[word, default: 0] += weight
                doc.length += weight
            }
        }
        return doc
    }

    /// Build df (one increment per distinct term per doc), n, and avgDl over all docs.
    public static func buildCorpus(_ docs: [Doc]) -> Corpus {
        var corpus = Corpus()
        corpus.n = docs.count
        var totalLen = 0.0
        for doc in docs {
            totalLen += doc.length
            var seen = Set<String>()
            for word in doc.tf.keys where seen.insert(word).inserted {
                corpus.df[word, default: 0] += 1
            }
        }
        corpus.avgDl = totalLen / Double(max(docs.count, 1))
        return corpus
    }

    /// Sum of `idf * tfNorm` over query terms present in the doc (tf > 0).
    /// `idf = log((n - df + 0.5)/(df + 0.5) + 1)` — natural log with the Lucene `+1`
    /// non-negativity guard. `tfNorm = (tf*(k1+1)) / (tf + k1*(1 - b + b*(len/avgDl)))`.
    public static func score(_ doc: Doc, _ queryWords: [String], _ corpus: Corpus) -> Double {
        var score = 0.0
        for word in queryWords {
            guard let tf = doc.tf[word], tf != 0 else { continue }
            let df = Double(corpus.df[word] ?? 0)
            let idf = log((Double(corpus.n) - df + 0.5) / (df + 0.5) + 1)
            let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * (doc.length / corpus.avgDl)))
            score += idf * tfNorm
        }
        return score
    }

    /// Count how many of the given tokens appear at least once in the doc.
    /// Used for the coverage gate (computed from RAW query tokens).
    public static func countHits(_ doc: Doc, _ queryTokens: [String]) -> Int {
        var hits = 0
        for word in queryTokens {
            if let tf = doc.tf[word], tf > 0 { hits += 1 }
        }
        return hits
    }
}
