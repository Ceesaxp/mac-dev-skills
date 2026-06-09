import Testing
import Foundation
@testable import AppKitAPICore

private func makeIndex() throws -> SymbolIndex {
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: Data(Fixtures.appKit.utf8))
    return SymbolIndex(graphs: [graph])
}

@Test func indexBuildsAndLooksUpByQualifiedName() throws {
    let index = try makeIndex()
    #expect(index.symbolCount == 3)

    let hit = try #require(index.check("NSGlassEffectView.effectIsInteractive"))
    #expect(hit.kind.identifier == "swift.property")
    #expect(hit.macOSAvailability?.introducedString == "27.0")

    #expect(index.check("NSGlassEffectView.doesNotExist") == nil)
}

@Test func indexResolvesMembersOfAType() throws {
    let index = try makeIndex()
    let members = index.members(of: "NSGlassEffectView")
    #expect(members.map(\.names.title) == ["effectIsInteractive"])
}

@Test func indexSearchRanksExactPrefixFirst() throws {
    let index = try makeIndex()
    let results = index.search("glass", limit: 10)
    #expect(results.first?.names.title == "NSGlassEffectView")
}
