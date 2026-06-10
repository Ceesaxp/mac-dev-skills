import Foundation

/// The canonical set of category labels in the corpus taxonomy. The full 69-pattern
/// corpus authored by the separate workflow must keep `category` within this set; the
/// integrity tests enforce it so authoring drift surfaces immediately.
public let knownCategories: Set<String> = [
    "Liquid Glass & concentricity",
    "Modern input",
    "Auto Layout",
    "Lists & collections",
    "Drag & drop",
    "Window & navigation",
    "Sheets, alerts & panels",
    "App lifecycle",
    "Status bar",
    "Text",
    "Controls",
    "Color & appearance",
    "Accessibility",
    "SF Symbols",
    "Documents",
]

/// A reference to the macOS Human Interface Guidelines page consulted when authoring
/// a pattern's behavioral guidance.
public struct HIGReference: Codable, Sendable, Equatable {
    public let section: String
    public let url: String
}

/// One curated AppKit pattern. Mirrors the 14-field corpus schema in the plan.
///
/// Scored fields (carried into BM25): `title`, `summary`, `keySymbols`, `tags`, `id`.
/// Everything else is metadata surfaced by `get` / `list`.
public struct Pattern: Codable, Sendable, Equatable {
    public let id: String                 // kebab-case, unique
    public let title: String
    public let summary: String
    public let category: String
    public let keySymbols: [String]
    public let tags: [String]
    public let minMacOS: String?
    public let swiftCode: String
    public let imports: [String]
    public let pitfalls: [String]?
    public let related: [String]?
    public let replaces: String?
    public let whenToUse: String
    public let higReference: HIGReference

    public init(
        id: String, title: String, summary: String, category: String,
        keySymbols: [String], tags: [String], minMacOS: String?,
        swiftCode: String, imports: [String], pitfalls: [String]?,
        related: [String]?, replaces: String?, whenToUse: String,
        higReference: HIGReference
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.keySymbols = keySymbols
        self.tags = tags
        self.minMacOS = minMacOS
        self.swiftCode = swiftCode
        self.imports = imports
        self.pitfalls = pitfalls
        self.related = related
        self.replaces = replaces
        self.whenToUse = whenToUse
        self.higReference = higReference
    }
}
