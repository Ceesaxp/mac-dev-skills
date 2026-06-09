import Foundation

public struct AvailabilityOut: Encodable, Sendable {
    public let introduced: String?
    public let deprecated: String?
    public let obsoleted: String?
    public let message: String?

    public init?(_ a: Availability?) {
        guard let a else { return nil }
        introduced = a.introducedString
        deprecated = a.deprecatedString
        obsoleted = a.obsoletedString
        message = a.message
    }
}

public struct SymbolOut: Encodable, Sendable {
    public let name: String
    public let qualified: String
    public let kind: String
    public let declaration: String
    public let availability: AvailabilityOut?

    public init(_ s: Symbol) {
        name = s.names.title
        qualified = s.qualifiedName
        kind = s.kind.identifier
        declaration = s.declaration
        availability = AvailabilityOut(s.macOSAvailability)
    }
}

/// Encode any Encodable as pretty, key-sorted JSON for CLI output.
public func emitJSON<T: Encodable>(_ value: T) throws -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try enc.encode(value), as: UTF8.self)
}
