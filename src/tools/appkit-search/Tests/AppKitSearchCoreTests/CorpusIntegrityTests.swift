import Testing
import Foundation
@testable import AppKitSearchCore

// MARK: - Layer 3: corpus integrity (guards the curated corpus against authoring drift)

private func loadedCorpus() throws -> Corpus { try Corpus.load() }

@Test func corpusDecodesAndIsNonEmpty() throws {
    let corpus = try loadedCorpus()
    #expect(!corpus.patterns.isEmpty)
}

@Test func idsAreUniqueKebabCase() throws {
    let corpus = try loadedCorpus()
    var seen = Set<String>()
    let kebab = try Regex("^[a-z0-9]+(-[a-z0-9]+)*$")
    for p in corpus.patterns {
        #expect(seen.insert(p.id).inserted, "duplicate id: \(p.id)")
        #expect((try? kebab.firstMatch(in: p.id)) ?? nil != nil, "id not kebab-case: \(p.id)")
    }
}

@Test func requiredTextFieldsAreNonEmpty() throws {
    let corpus = try loadedCorpus()
    for p in corpus.patterns {
        #expect(!p.title.isEmpty, "\(p.id): empty title")
        #expect(!p.summary.isEmpty, "\(p.id): empty summary")
        #expect(!p.swiftCode.isEmpty, "\(p.id): empty swiftCode")
        #expect(!p.whenToUse.isEmpty, "\(p.id): empty whenToUse")
        #expect(!p.keySymbols.isEmpty, "\(p.id): empty keySymbols")
        #expect(p.keySymbols.allSatisfy { !$0.isEmpty }, "\(p.id): blank keySymbol")
        #expect(!p.tags.isEmpty, "\(p.id): empty tags")
        #expect(p.tags.allSatisfy { !$0.isEmpty }, "\(p.id): blank tag")
        #expect(!p.imports.isEmpty, "\(p.id): empty imports")
        #expect(p.imports.allSatisfy { !$0.isEmpty }, "\(p.id): blank import")
    }
}

@Test func higReferenceIsPresentAndPlausible() throws {
    let corpus = try loadedCorpus()
    for p in corpus.patterns {
        #expect(!p.higReference.section.isEmpty, "\(p.id): empty HIG section")
        #expect(p.higReference.url.hasPrefix("https://developer.apple.com/design/human-interface-guidelines"),
                "\(p.id): HIG url not a HIG page: \(p.higReference.url)")
    }
}

@Test func relatedIdsResolveToExistingPatterns() throws {
    let corpus = try loadedCorpus()
    let ids = Set(corpus.patterns.map(\.id))
    for p in corpus.patterns {
        for rel in p.related ?? [] {
            #expect(ids.contains(rel), "\(p.id): related id does not resolve: \(rel)")
        }
    }
}

@Test func categoriesAreWithinKnownSet() throws {
    let corpus = try loadedCorpus()
    for p in corpus.patterns {
        #expect(knownCategories.contains(p.category), "\(p.id): unknown category '\(p.category)'")
    }
}

@Test func minMacOSParsesWhenPresent() throws {
    let corpus = try loadedCorpus()
    // Accept "26", "26.0", "26.1" etc.; nil/empty means broadly available.
    let versionRe = try Regex("^[0-9]+(\\.[0-9]+){0,2}$")
    for p in corpus.patterns {
        guard let v = p.minMacOS, !v.isEmpty else { continue }
        #expect((try? versionRe.firstMatch(in: v)) ?? nil != nil, "\(p.id): minMacOS not a version: \(v)")
        let major = Int(v.split(separator: ".").first.map(String.init) ?? "")
        #expect(major != nil, "\(p.id): minMacOS major not an int: \(v)")
    }
}

@Test func sharedInstanceMatchesFreshLoad() throws {
    #expect(Corpus.shared.patterns.count == (try loadedCorpus().patterns.count))
}
