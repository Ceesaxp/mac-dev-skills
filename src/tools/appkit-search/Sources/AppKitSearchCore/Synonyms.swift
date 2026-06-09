import Foundation

/// Synonym pipeline ported from winui-search `Synonyms.cs`. THREE mechanisms across
/// TWO pipeline stages; the mechanism is preserved verbatim, the DATA is retranslated
/// to AppKit vocabulary (NSButton, NSTableView, NSPopover, NSSplitViewController, ...).
///
/// Pipeline order (from `SearchEngine.search`):
///   raw -> preprocess (phrases + stems appended) -> tokenize -> expand (synonyms
///   appended) -> score.  The coverage gate deliberately uses RAW tokenize output only.
public enum Synonyms {
    /// Stage 1a: multi-word phrases merged into a single token. Keys lowercase,
    /// matched as exact word-boundary substrings. Retranslated to Mac phrasings.
    static let phrases: [(phrase: String, replacement: String)] = [
        // Liquid Glass / materials
        ("glass effect", "nsglasseffectview"),
        ("liquid glass", "nsglasseffectview"),
        ("glass container", "nsglasseffectcontainerview"),
        ("visual effect", "nsvisualeffectview"),
        // Lists / tables
        ("data grid", "nstableview"),
        ("data-grid", "nstableview"),
        ("table view", "nstableview"),
        ("outline view", "nsoutlineview"),
        ("collection view", "nscollectionview"),
        ("source list", "nsoutlineview"),
        // Navigation / windows
        ("split view", "nssplitviewcontroller"),
        ("side bar", "nssplitviewcontroller"),
        ("tab view", "nstabviewcontroller"),
        ("tool bar", "nstoolbar"),
        ("title bar", "nstoolbar"),
        ("window controller", "nswindowcontroller"),
        // Sheets / alerts / panels / menus
        ("open panel", "nsopenpanel"),
        ("save panel", "nssavepanel"),
        ("file picker", "nsopenpanel"),
        ("folder picker", "nsopenpanel"),
        ("color picker", "nscolorwell"),
        ("color well", "nscolorwell"),
        ("pop over", "nspopover"),
        ("context menu", "contextmenu"),
        ("right click menu", "contextmenu"),
        ("right-click menu", "contextmenu"),
        ("menu bar", "nsstatusitem"),
        ("status bar", "nsstatusitem"),
        ("status item", "nsstatusitem"),
        ("share sheet", "nssharingservicepicker"),
        // Input
        ("text field", "nstextfield"),
        ("text view", "nstextview"),
        ("text area", "nstextview"),
        ("search field", "nssearchfield"),
        ("combo box", "nscombobox"),
        ("pop up button", "nspopupbutton"),
        ("popup button", "nspopupbutton"),
        ("check box", "checkbox"),
        ("radio button", "radio"),
        ("segmented control", "nssegmentedcontrol"),
        ("gesture recognizer", "nsgesturerecognizer"),
        ("tracking area", "nstrackingarea"),
        // Layout
        ("stack view", "nsstackview"),
        ("grid view", "nsgridview"),
        ("auto layout", "autolayout"),
        // Drag & drop
        ("drag and drop", "dragdrop"),
        ("drag drop", "dragdrop"),
        // Color / appearance / a11y
        ("dark mode", "appearance"),
        ("screen reader", "voiceover"),
        ("screen-reader", "voiceover"),
        ("sf symbol", "nsimage"),
        ("sf symbols", "nsimage"),
        ("writing tools", "nswritingtoolscoordinator"),
    ]

    /// Stage 1b: irregular stems the algorithmic stemmer can't reach.
    static let stemExceptions: [String: [String]] = [
        "paginated": ["page"],
        "paginating": ["page"],
        "paging": ["page"],
        "pages": ["page"],
        "tabbed": ["tab", "tabs"],
    ]

    /// Stage 2: cross-framework / cross-platform UI vocab -> AppKit class names.
    /// Keys and values lowercase. Retranslated data; the lookup mechanism is verbatim.
    static let map: [String: [String]] = [
        // Tables / lists
        "datagrid": ["nstableview", "nsoutlineview", "rows", "columns"],
        "table": ["nstableview", "nsoutlineview", "rows", "columns"],
        "grid": ["nstableview", "nsgridview", "nscollectionview"],
        "spreadsheet": ["nstableview", "rows"],
        "list": ["nstableview", "nsoutlineview", "nscollectionview"],
        "rows": ["nstableview"],
        "tree": ["nsoutlineview"],
        "treeview": ["nsoutlineview"],
        "outline": ["nsoutlineview"],
        "hierarchy": ["nsoutlineview"],

        // Dialogs / popups / menus
        "modal": ["nsalert", "sheet", "nspopover"],
        "dialog": ["nsalert", "sheet"],
        "alert": ["nsalert"],
        "popup": ["nspopover", "nsmenu", "nspopupbutton"],
        "prompt": ["nsalert"],
        "actionsheet": ["nsalert", "nsmenu"],
        "tooltip": ["tooltip", "nspopover"],
        "contextmenu": ["nsmenu"],
        "rightclick": ["nsmenu"],
        "menu": ["nsmenu", "nsmenuitem"],

        // Navigation / windows
        "sidebar": ["nssplitviewcontroller", "nssplitviewitem", "nsoutlineview"],
        "drawer": ["nssplitviewcontroller"],
        "inspector": ["nssplitviewcontroller", "nssplitviewitem"],
        "navbar": ["nstoolbar"],
        "toolbar": ["nstoolbar", "nstoolbaritem"],
        "tabbar": ["nstabviewcontroller", "nssegmentedcontrol"],
        "tabs": ["nstabviewcontroller"],
        "tabview": ["nstabviewcontroller"],
        "window": ["nswindowcontroller", "nswindow"],

        // Inputs
        "select": ["nspopupbutton", "nscombobox"],
        "dropdown": ["nspopupbutton", "nscombobox"],
        "picker": ["nsopenpanel", "nssavepanel", "nspopupbutton", "nscolorwell"],
        "stepper": ["nsstepper"],
        "slider": ["nsslider"],
        "toggle": ["nsswitch", "checkbox"],
        "switch": ["nsswitch"],
        "checkbox": ["nsbutton"],
        "radio": ["nsbutton"],
        "radiogroup": ["nsbutton"],
        "searchbox": ["nssearchfield"],
        "searchbar": ["nssearchfield"],
        "typeahead": ["nscombobox", "nssearchfield"],
        "combobox": ["nscombobox"],
        "segmented": ["nssegmentedcontrol"],

        // Text
        "textarea": ["nstextview"],
        "textbox": ["nstextfield", "nstextview"],
        "multiline": ["nstextview"],
        "richtext": ["nstextview", "textkit"],
        "wysiwyg": ["nstextview"],
        "label": ["nstextfield"],
        "heading": ["nstextfield"],
        "link": ["nsbutton"],

        // Layout
        "flex": ["nsstackview"],
        "flexbox": ["nsstackview"],
        "stack": ["nsstackview"],
        "container": ["nsstackview", "nsview"],
        "divider": ["nsbox"],
        "form": ["nsgridview", "nsstackview"],
        "constraint": ["nslayoutconstraint", "autolayout"],
        "constraints": ["nslayoutconstraint", "autolayout"],

        // Buttons / commands
        "button": ["nsbutton"],
        "fab": ["nsbutton"],
        "iconbutton": ["nsbutton"],

        // Media / images / symbols
        "icon": ["nsimage", "sfsymbols"],
        "image": ["nsimage", "nsimageview"],
        "symbol": ["nsimage", "sfsymbols"],
        "thumbnail": ["nsimageview"],

        // System / shell
        "tray": ["nsstatusitem"],
        "menulet": ["nsstatusitem"],
        "menubar": ["nsstatusitem"],
        "statustray": ["nsstatusitem"],
        "share": ["nssharingservicepicker"],
        "dragdrop": ["drag", "drop", "pasteboard"],
        "drag": ["dragdrop", "pasteboard"],
        "drop": ["dragdrop", "pasteboard"],
        "clipboard": ["pasteboard", "nspasteboard"],

        // Color / appearance
        "blur": ["nsvisualeffectview"],
        "vibrancy": ["nsvisualeffectview"],
        "material": ["nsvisualeffectview", "nsglasseffectview"],
        "glass": ["nsglasseffectview"],
        "appearance": ["nsappearance", "darkmode"],
        "darkmode": ["nsappearance", "appearance"],
        "color": ["nscolor"],

        // Accessibility
        "a11y": ["accessibility", "voiceover"],
        "accessibility": ["voiceover", "accessible"],
        "accessible": ["accessibility", "voiceover"],
        "voiceover": ["accessibility", "accessible"],
        "screenreader": ["voiceover", "accessibility"],

        // Documents / lifecycle
        "document": ["nsdocument"],
        "autosave": ["nsdocument"],

        // Abbreviations
        "btn": ["nsbutton"],
        "txt": ["nstextfield", "nstextview"],
        "img": ["nsimage", "nsimageview"],
    ]

    private static let wordSeparators = CharacterSet(charactersIn: " \t\n\r,.;:!?()[]{}\"'")

    private static func isWordChar(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }

    /// Algorithmic suffix-stripping stemmer (ported verbatim). Yields candidate base
    /// forms; wrong candidates simply match nothing in the corpus.
    static func stem(_ word: String) -> [String] {
        if word.isEmpty { return [] }
        var out: [String] = []
        let chars = Array(word)
        let n = chars.count
        if n > 5 && word.hasSuffix("ing") {
            let b = String(chars[0..<(n - 3)])     // editing -> edit
            out.append(b)
            out.append(b + "e")                    // closing -> close
            let bc = Array(b)
            if bc.count >= 2 && bc[bc.count - 1] == bc[bc.count - 2] {
                out.append(String(bc[0..<(bc.count - 1)]))  // dragging -> drag
            }
        } else if n > 4 && word.hasSuffix("ed") {
            let b = String(chars[0..<(n - 2)])     // edited -> edit
            out.append(b)
            out.append(String(chars[0..<(n - 1)])) // themed -> theme
            let bc = Array(b)
            if bc.count >= 2 && bc[bc.count - 1] == bc[bc.count - 2] {
                out.append(String(bc[0..<(bc.count - 1)]))  // dropped -> drop
            }
        } else if n > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") {
            out.append(String(chars[0..<(n - 1)])) // tabs -> tab
            if n > 4 && word.hasSuffix("es") {
                out.append(String(chars[0..<(n - 2)])) // boxes -> box
            }
        }
        return out
    }

    /// Stage 1: append merged phrase tokens AND stemmed base forms, KEEPING originals.
    public static func preprocess(_ query: String) -> String {
        let lower = Tokenizer.invariantLowercased(query)
        let lowerScalars = Array(lower.unicodeScalars)
        var sb = lower

        // Phrases: exact word-boundary substring match; append the merged token.
        for (phrase, replacement) in phrases {
            var searchRange = lower.startIndex..<lower.endIndex
            while let r = lower.range(of: phrase, options: [], range: searchRange) {
                let startOffset = lower.distance(from: lower.startIndex, to: r.lowerBound)
                let endOffset = lower.distance(from: lower.startIndex, to: r.upperBound)
                let leftOk = startOffset == 0 || !isWordChar(lowerScalars[startOffset - 1])
                let rightOk = endOffset == lowerScalars.count || !isWordChar(lowerScalars[endOffset])
                if leftOk && rightOk {
                    sb += " " + replacement
                }
                searchRange = r.upperBound..<lower.endIndex
            }
        }

        // Stemming: append base forms for inflected query words. Exceptions take precedence.
        let words = lower.components(separatedBy: wordSeparators).filter { !$0.isEmpty }
        for word in words {
            if let bases = stemExceptions[word] {
                for b in bases { sb += " " + b }
            } else {
                for b in stem(word) { sb += " " + b }
            }
        }
        return sb
    }

    /// Stage 2: append deduped synonyms for each token, with the compound-suffix guard.
    public static func expand(_ queryWords: [String]) -> [String] {
        var result = queryWords
        var seen = Set(queryWords)
        let queryWordSet = Set(queryWords)
        for w in queryWords {
            guard let syns = map[w] else { continue }
            // Compound-suffix guard: skip a bare token if a longer compound ending in
            // it is already present (e.g. 'filepicker' present -> don't expand 'picker').
            let hasCompoundParent = queryWordSet.contains { other in
                other.count > w.count && other.hasSuffix(w)
            }
            if hasCompoundParent { continue }
            for s in syns where seen.insert(s).inserted {
                result.append(s)
            }
        }
        return result
    }
}
