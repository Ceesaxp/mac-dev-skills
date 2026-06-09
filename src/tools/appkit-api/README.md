# appkit-api

An SDK API + availability validator for macOS frameworks. Answers "does this
symbol exist, and what macOS version does it require?" from
`swift symbolgraph-extract` data — so an agent never guesses an API name or an
`@available` version.

## Build
```bash
swift build -c release        # or: scripts/build-tools.sh from the repo root
```

## Usage
```bash
appkit-api check NSGlassEffectView.effectIsInteractive   # exists? + availability
appkit-api availability NSViewCornerConfiguration        # min macOS / deprecation
appkit-api members NSGlassEffectView                      # members of a type
appkit-api search glass --limit 10                       # fuzzy name search
appkit-api enums NSGlassEffectView.Style                 # enum cases
appkit-api --module Foundation check NSString.length     # any SDK module
```

First query for a module extracts + caches its symbol graph under
`~/Library/Caches/appkit-api/<sdk-version>/<module>/` (~30s, ~31MB for AppKit);
later queries are instant. Cache invalidates automatically when the SDK version
changes. Requires the SDK to be resolvable via `xcrun --sdk macosx`.

## Tests
```bash
swift test     # Swift Testing; query logic runs against a checked-in fixture
```
