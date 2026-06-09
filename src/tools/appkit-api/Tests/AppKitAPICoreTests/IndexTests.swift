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

@Test func enumCasesOfEnumTypeReturnsOnlyCases() throws {
    let json = """
    {
      "symbols": [
        {
          "kind": { "identifier": "swift.enum", "displayName": "Enumeration" },
          "identifier": { "precise": "s:SomeEnum", "interfaceLanguage": "swift" },
          "names": { "title": "SomeEnum" },
          "pathComponents": ["SomeEnum"],
          "declarationFragments": [{ "kind": "keyword", "spelling": "enum SomeEnum" }]
        },
        {
          "kind": { "identifier": "swift.enum.case", "displayName": "Enumeration Case" },
          "identifier": { "precise": "s:SomeEnum.alpha", "interfaceLanguage": "swift" },
          "names": { "title": "alpha" },
          "pathComponents": ["SomeEnum", "alpha"],
          "declarationFragments": [{ "kind": "keyword", "spelling": "case alpha" }]
        },
        {
          "kind": { "identifier": "swift.enum.case", "displayName": "Enumeration Case" },
          "identifier": { "precise": "s:SomeEnum.beta", "interfaceLanguage": "swift" },
          "names": { "title": "beta" },
          "pathComponents": ["SomeEnum", "beta"],
          "declarationFragments": [{ "kind": "keyword", "spelling": "case beta" }]
        },
        {
          "kind": { "identifier": "swift.property", "displayName": "Instance Property" },
          "identifier": { "precise": "s:SomeEnum.label", "interfaceLanguage": "swift" },
          "names": { "title": "label" },
          "pathComponents": ["SomeEnum", "label"],
          "declarationFragments": [{ "kind": "keyword", "spelling": "var label: String" }]
        }
      ],
      "relationships": [
        { "kind": "memberOf", "source": "s:SomeEnum.alpha", "target": "s:SomeEnum" },
        { "kind": "memberOf", "source": "s:SomeEnum.beta",  "target": "s:SomeEnum" },
        { "kind": "memberOf", "source": "s:SomeEnum.label", "target": "s:SomeEnum" }
      ]
    }
    """
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: Data(json.utf8))
    let index = SymbolIndex(graphs: [graph])
    let cases = index.enumCases(of: "SomeEnum")
    // Only the two enum-case members should be returned; the property must be excluded.
    #expect(cases.map(\.names.title).sorted() == ["alpha", "beta"])
}
