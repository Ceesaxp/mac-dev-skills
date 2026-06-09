enum Fixtures {
    // Minimal AppKit symbol graph: a class, one of its properties, and a deprecated method.
    static let appKit = """
    {
      "metadata": { "formatVersion": { "major": 0, "minor": 6, "patch": 0 }, "generator": "test" },
      "module": { "name": "AppKit" },
      "symbols": [
        {
          "kind": { "identifier": "swift.class", "displayName": "Class" },
          "identifier": { "precise": "c:objc(cs)NSGlassEffectView", "interfaceLanguage": "swift" },
          "names": { "title": "NSGlassEffectView" },
          "pathComponents": ["NSGlassEffectView"],
          "declarationFragments": [
            { "kind": "keyword", "spelling": "class" },
            { "kind": "text", "spelling": " " },
            { "kind": "identifier", "spelling": "NSGlassEffectView" }
          ],
          "availability": [ { "domain": "macOS", "introduced": { "major": 26, "minor": 0 } } ]
        },
        {
          "kind": { "identifier": "swift.property", "displayName": "Instance Property" },
          "identifier": { "precise": "c:objc(cs)NSGlassEffectView(py)effectIsInteractive", "interfaceLanguage": "swift" },
          "names": { "title": "effectIsInteractive" },
          "pathComponents": ["NSGlassEffectView", "effectIsInteractive"],
          "declarationFragments": [
            { "kind": "keyword", "spelling": "var" },
            { "kind": "text", "spelling": " " },
            { "kind": "identifier", "spelling": "effectIsInteractive" },
            { "kind": "text", "spelling": ": " },
            { "kind": "typeIdentifier", "spelling": "Bool" }
          ],
          "availability": [ { "domain": "macOS", "introduced": { "major": 27, "minor": 0 } } ]
        },
        {
          "kind": { "identifier": "swift.method", "displayName": "Instance Method" },
          "identifier": { "precise": "c:objc(cs)NSCursor(im)showCenteredAt", "interfaceLanguage": "swift" },
          "names": { "title": "show(centeredAt:size:completionHandler:)" },
          "pathComponents": ["NSCursor", "show(centeredAt:size:completionHandler:)"],
          "declarationFragments": [
            { "kind": "keyword", "spelling": "func" },
            { "kind": "text", "spelling": " " },
            { "kind": "identifier", "spelling": "show" }
          ],
          "availability": [ {
            "domain": "macOS",
            "introduced": { "major": 10, "minor": 9 },
            "deprecated": { "major": 14, "minor": 0 },
            "message": "Use NSCursor.disappearingItemCursor instead"
          } ]
        }
      ],
      "relationships": [
        { "kind": "memberOf",
          "source": "c:objc(cs)NSGlassEffectView(py)effectIsInteractive",
          "target": "c:objc(cs)NSGlassEffectView" }
      ]
    }
    """
}
