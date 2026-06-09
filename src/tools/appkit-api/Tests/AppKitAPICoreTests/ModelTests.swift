import Testing
import Foundation
@testable import AppKitAPICore

@Test func decodesSymbolGraph() throws {
    let data = Data(Fixtures.appKit.utf8)
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: data)
    #expect(graph.symbols.count == 3)
    #expect(graph.relationships.count == 1)

    let glass = try #require(graph.symbols.first { $0.names.title == "NSGlassEffectView" })
    #expect(glass.kind.identifier == "swift.class")
    #expect(glass.pathComponents == ["NSGlassEffectView"])
    #expect(glass.declaration == "class NSGlassEffectView")

    let prop = try #require(graph.symbols.first { $0.names.title == "effectIsInteractive" })
    let macos = try #require(prop.macOSAvailability)
    #expect(macos.introducedString == "27.0")

    let cursor = try #require(graph.symbols.first { $0.pathComponents.first == "NSCursor" })
    #expect(cursor.macOSAvailability?.deprecatedString == "14.0")
    #expect(cursor.macOSAvailability?.message == "Use NSCursor.disappearingItemCursor instead")
}
