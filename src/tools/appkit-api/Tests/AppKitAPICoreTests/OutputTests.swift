import Testing
import Foundation
@testable import AppKitAPICore

@Test func projectsSymbolToStableJSON() throws {
    let graph = try JSONDecoder().decode(SymbolGraph.self, from: Data(Fixtures.appKit.utf8))
    let index = SymbolIndex(graphs: [graph])
    let sym = try #require(index.check("NSGlassEffectView.effectIsInteractive"))

    let out = SymbolOut(sym)
    #expect(out.name == "effectIsInteractive")
    #expect(out.qualified == "NSGlassEffectView.effectIsInteractive")
    #expect(out.kind == "swift.property")
    #expect(out.declaration == "var effectIsInteractive: Bool")
    #expect(out.availability?.introduced == "27.0")

    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let json = String(decoding: try enc.encode(out), as: UTF8.self)
    #expect(json.contains("\"introduced\":\"27.0\""))
}
