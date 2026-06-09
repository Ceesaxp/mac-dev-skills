import Foundation

public struct SymbolGraph: Decodable, Sendable {
    public let symbols: [Symbol]
    public let relationships: [Relationship]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbols = try c.decodeIfPresent([Symbol].self, forKey: .symbols) ?? []
        relationships = try c.decodeIfPresent([Relationship].self, forKey: .relationships) ?? []
    }
    enum CodingKeys: String, CodingKey { case symbols, relationships }
}

public struct Symbol: Decodable, Sendable {
    public struct Names: Decodable, Sendable { public let title: String }
    public struct Kind: Decodable, Sendable { public let identifier: String }
    public struct Identifier: Decodable, Sendable { public let precise: String }
    public struct Fragment: Decodable, Sendable { public let spelling: String }

    public let names: Names
    public let kind: Kind
    public let identifier: Identifier
    public let pathComponents: [String]
    public let declarationFragments: [Fragment]?
    public let availability: [Availability]?

    /// The qualified name, e.g. "NSGlassEffectView.effectIsInteractive".
    public var qualifiedName: String { pathComponents.joined(separator: ".") }

    /// The reconstructed Swift declaration, e.g. "var effectIsInteractive: Bool".
    public var declaration: String {
        (declarationFragments ?? []).map(\.spelling).joined()
    }

    /// The macOS entry from the availability list, if any.
    public var macOSAvailability: Availability? {
        availability?.first { $0.domain?.caseInsensitiveCompare("macOS") == .orderedSame }
    }
}

public struct Availability: Decodable, Sendable {
    public struct Version: Decodable, Sendable {
        public let major: Int
        public let minor: Int?
        public let patch: Int?
        public var string: String {
            var s = "\(major).\(minor ?? 0)"
            if let patch, patch != 0 { s += ".\(patch)" }
            return s
        }
    }
    public let domain: String?
    public let introduced: Version?
    public let deprecated: Version?
    public let obsoleted: Version?
    public let message: String?

    public var introducedString: String? { introduced?.string }
    public var deprecatedString: String? { deprecated?.string }
    public var obsoletedString: String? { obsoleted?.string }
}

public struct Relationship: Decodable, Sendable {
    public let kind: String
    public let source: String
    public let target: String
}
