---
name: appkit-ui-testing
description: "Automated UI testing for native macOS AppKit apps with XCUITest — write a UI test class, run the whole suite in one xcodebuild test pass, read results. Covers element queries, interactions, value checks (NSTextField, NSPopUpButton, NSSwitch), sheets, popovers, menus, NSAlert, file panels, persistence, screenshots, and accessibility audits. Use to validate an AppKit app's UI behaves as specified."
---

### Approach

The goal is to validate UI and app behavior **automatically**, without manual clicking, by exercising controls, asserting their state, and checking the app behaves as specified. macOS's built-in UI automation is **XCUITest** (the `XCTest` UI-testing APIs) — the AppKit analog of the WinUI `winapp ui` driver. The key difference: XCUITest is **code in a UI-test target**, not a standalone CLI. You write one test class, then run the whole thing in a single `xcodebuild test` pass and read the result bundle.

Two ways to work:
1. **Interactive discovery** — launch the app, open **Accessibility Inspector** (Xcode → Open Developer Tool → Accessibility Inspector) and hover/inspect to read each element's role, label, and **identifier**. Slow, but the way to discover identifiers for hidden/dynamic elements (sheet buttons, menu items, popover contents).
2. **Scripted batch testing** — write a `UITests.swift` test class that drives every requirement and asserts expected behavior, then run it once. Repeatable, produces a pass/fail record. **Prefer this** unless you're exploring an app you didn't write.

> The whole approach depends on stable accessibility identifiers. Apps the `appkit-design` / `appkit-code-review` skills produce set `setAccessibilityIdentifier(_:)` on every interactive control. If a control has no identifier, XCUITest can only find it by label or position — brittle. Add identifiers first.

### Prerequisite: a UI-test target

The `templates/Project.swift` in `appkit-dev-workflow` already defines a `MyAppUITests` target of product type `.uiTests`. If an existing project has no UI-test target, add one to `Project.swift` and `tuist generate`:
```swift
.target(
    name: "MyAppUITests",
    destinations: .macOS,
    product: .uiTests,
    bundleId: "com.example.MyAppUITests",
    deploymentTargets: .macOS("26.0"),
    sources: ["MyAppUITests/**"],
    dependencies: [.target(name: "MyApp")]
)
```

### Step 1: Use the Running App

XCUITest launches its **own** instance of the app under test (`XCUIApplication().launch()`); you don't attach to a PID the way `winapp` does. There's no need to pre-launch — `launch()` builds the activation for you. Use `launchArguments`/`launchEnvironment` to put the app into a known test state (e.g. a temp data dir) so runs are deterministic and don't clobber real user data.

### Step 2: Write the Test Class

**If you wrote the code:** skip discovery — you already know every identifier from the source. Write tests directly. Inspector won't show sheets/menus/popovers until they're open anyway.

**If you're verifying code you didn't write:** open Accessibility Inspector to read identifiers, and read the source for `setAccessibilityIdentifier` calls on elements that aren't on screen yet (sheet buttons, secondary windows).

Create `MyAppUITests/UITests.swift` covering every requirement in one class. XCTest reports per-method pass/fail, so each `func test…()` is one assertion group:

```swift
import XCTest

final class UITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false          // stop a test method at its first failed assert
        app = XCUIApplication()
        app.launchArguments = ["-uiTest", "1"] // app reads this to use a temp data dir
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // ── Element existence ──
    func testLaunchShowsMainControls() {
        XCTAssertTrue(app.buttons["BtnSave"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["TxtUserName"].exists)
    }

    // ── Navigation (source-list / split view) ──
    func testNavigateToSettings() {
        app.outlines["Sidebar"].staticTexts["Settings"].click()
        XCTAssertTrue(app.textFields["TxtUserName"].waitForExistence(timeout: 3))
    }

    // ── Interactions + value assertions ──
    func testSetUsernameCommits() {
        let field = app.textFields["TxtUserName"]
        field.click()
        field.typeText("TestUser")
        app.buttons["BtnSave"].click()         // commits the binding (see Gotchas)
        XCTAssertEqual(field.value as? String, "TestUser")
    }

    func testThemePopUpDefault() {
        XCTAssertEqual(app.popUpButtons["CmbTheme"].value as? String, "System")
    }

    func testLoggingSwitchOff() {
        // NSSwitch reports 1/0 via the toggle value
        XCTAssertEqual(app.switches["TglLogging"].value as? Int, 0)
    }

    // ── Accessibility audit (macOS 14+) ──
    func testAccessibilityAudit() throws {
        try app.performAccessibilityAudit()    // fails on contrast, missing labels, hit-region, etc.
    }

    // ── Screenshot for visual review (see Step 3.5) ──
    func testCaptureInitialState() {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "01-initial"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
```

### What to Test

Write a test for **every requirement** from the user's prompt.

| Requirement | XCUITest approach |
|---|---|
| "Has a button that does X" | `app.buttons["Id"].exists`, `.click()`, then assert the resulting state |
| "Text field shows value" | `app.textFields["Id"].value as? String` (or `.staticTexts[...].label` for labels) |
| "Status text contains …" | `XCTAssertTrue((app.staticTexts["Status"].value as? String ?? "").contains("done"))` |
| "Pop-up is set to X" | `app.popUpButtons["Id"].value as? String` |
| "Switch / checkbox on/off" | `app.switches["Id"].value as? Int` (1/0); `app.checkBoxes["Id"].value` |
| "Navigate between panes" | click the sidebar/source-list row, `waitForExistence` on a pane-specific element |
| "Open file panel" | trigger it, then drive the panel as a separate window (see File Panels below) |
| "Save file panel" | same — type into the name field, click Save |
| "Right-click context menu" | `el.rightClick()`, then `app.menuItems["Copy"].click()` |
| "Confirmation alert (sheet)" | trigger, then `app.sheets.buttons["Delete"].click()` (or `app.dialogs` / `.buttons["OK"]`) |
| "Data persists" | set values, click a commit button, verify the **data file on disk** (not via relaunch) |
| "All controls accessible" | `try app.performAccessibilityAudit()` |

### Step 3: Run and Read Results

Run the whole UI suite in one pass and write a result bundle:
```bash
xcodebuild test \
  -scheme MyApp \
  -destination 'platform=macOS' \
  -only-testing:MyAppUITests \
  -resultBundlePath ./TestResults.xcresult \
  -derivedDataPath ./build
```
Read pass/fail from the test output. For structured results (and to pull screenshots/audit findings), inspect the result bundle:
```bash
xcrun xcresulttool get test-results summary --path ./TestResults.xcresult     # overview
xcrun xcresulttool get test-results tests   --path ./TestResults.xcresult     # per-test status
```
Only change code if a test fails. (On older Xcode, use `xcrun xcresulttool get --format json --path …`; the `test-results` subcommands are the current form.)

### Step 3.5: Look at the Screenshots

XCUITest assertions don't see clipping, overlap, wrong theming, or controls bleeding past their container — an audit/assert can pass while the window is visually broken. **Attach a screenshot of the main window (and any state after a major interaction) as in `testCaptureInitialState` above, then open the PNGs from the result bundle** (`xcrun xcresulttool export … --type file`, or just open the `.xcresult` in Xcode).

**Visual checklist — fail the run if any item is `no`:**
- [ ] No unintended scrollbars
- [ ] No text truncated to `…` that shouldn't be
- [ ] Hero/primary elements fully visible (not sliced)
- [ ] Right-edge and bottom controls fully visible
- [ ] No overlapping rows or controls
- [ ] Content uses the available width — no asymmetric dead zones
- [ ] Spacing intentional — not cramped, not unintentionally vast
- [ ] Theming matches the ask (Light/Dark/Increased Contrast if relevant)
- [ ] On Tahoe: toolbar/sidebar glass renders; content isn't hidden behind a floating toolbar
- [ ] Focus/hover/error states render if tested

If the checklist fails, it's a bug — fix before declaring done. Window too small → resize per `appkit-design` Step 4.

### Step 4: Fix and Rerun (only if the user asked)

If tests fail:
1. Read the failure detail from the result bundle.
2. Batch-fix all issues in one pass.
3. Rebuild with `./build-and-run.sh --skip-run` (catches compile breaks from the fix).
4. Rerun the `xcodebuild test` command above.

**Maximum 2 fix-and-rerun cycles.** If the same tests keep failing after 2 cycles, report them as known issues and move on — don't loop.

### Assertion Reference

`value` returns different types per control — read the right one:

| Control | `.value` is | Example |
|---|---|---|
| `NSTextField` | `String` | `app.textFields["Id"].value as? String` |
| `NSTextView` | `String` | `app.textViews["Id"].value as? String` |
| `NSSecureTextField` | (masked) | assert via app state, not the field value |
| `NSPopUpButton` | selected title `String` | `app.popUpButtons["Id"].value as? String` |
| `NSComboBox` | `String` | `app.comboBoxes["Id"].value as? String` |
| `NSSwitch` / checkbox | `Int` 1/0 | `app.switches["Id"].value as? Int` |
| `NSSlider` | `Double` | `app.sliders["Id"].value as? Double` |
| `NSTextField (label)` | use `.label` | `app.staticTexts["Id"].label` |

Common commands: `el.click()`, `el.rightClick()`, `el.doubleClick()`, `el.typeText("…")`, `el.clearAndType` (write a helper: select-all + delete + type), `el.waitForExistence(timeout:)`, `el.coordinate(withNormalizedOffset:).click()` for precise hits, and `app.typeKey("s", modifierFlags: .command)` for keyboard shortcuts.

### Testing File Panels (NSOpenPanel / NSSavePanel)

Open/Save panels are separate windows owned by the app; XCUITest sees them in the same `app` element tree (no separate-process dance like the WinUI PickerHost):
```swift
app.buttons["BtnOpen"].click()
let panel = app.dialogs.firstMatch          // the open/save sheet/window
XCTAssertTrue(panel.waitForExistence(timeout: 3))
// Jump to a path: Cmd-Shift-G, type, return
app.typeKey("g", modifierFlags: [.command, .shift])
app.typeText("/tmp/test.txt\n")
panel.buttons["Open"].click()               // or "Save", "Cancel"
XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 3))
```
Use Accessibility Inspector on an open panel to find its control identifiers (the sidebar, file list, name field, Open/Cancel buttons).

### Testing Menus and Context Menus

```swift
// Context menu
app.outlines["List"].outlineRows.firstMatch.rightClick()
app.menuItems["Copy"].click()
XCTAssertEqual(app.staticTexts["Status"].value as? String, "Copied")

// Main menu bar
app.menuBars.menuBarItems["File"].click()
app.menuItems["Save As…"].click()
```
Menu items appear in the tree only while the menu is open; a `waitForExistence` after opening avoids races.

### Testing Sheets and NSAlert

Sheets (including `NSAlert.beginSheetModal`) attach to their parent window and appear as `app.sheets` (sometimes surfaced as `app.dialogs`):
```swift
app.buttons["BtnDelete"].click()
let sheet = app.sheets.firstMatch
XCTAssertTrue(sheet.waitForExistence(timeout: 3))
sheet.buttons["Delete"].click()             // or "Cancel"
XCTAssertFalse(sheet.waitForExistence(timeout: 2)) // dismissed
```
Alert buttons are matched by their title — give custom buttons clear titles, or set identifiers.

### Key Gotchas

- **`typeText` does NOT commit a default `NSTextField` binding** — Cocoa bindings/first-responder commit on **end editing** (focus loss / Return). Typing changes the displayed text but the model may not update. **Fix:** either click another control / press Tab / press Return after typing to force end-editing, or have the field commit continuously (`isContinuous = true` / a continuously-updating binding — see the design skill). This is the AppKit twin of the WinUI `UpdateSourceTrigger=PropertyChanged` gotcha.
- **Verify persistence via the data file, not a relaunch** — terminating and relaunching inside a test is fragile. Write to a temp dir (via `launchArguments`), then read the file with `FileManager` + `JSONDecoder` and assert.
- **Always `waitForExistence` for async UI** — sheets, menus, popovers, and freshly-loaded panes appear asynchronously; `.exists` checked too early returns false.
- **Identifiers beat labels** — labels are localized and change; set and query stable `accessibilityIdentifier`s.
- **`performAccessibilityAudit()` requires macOS 14+** — gate with `if #available` if you must support older test runners; it catches contrast, missing labels, clipped hit regions, and element-description issues for free.
- **One assertion group per `test…` method** with `continueAfterFailure = false` gives clean per-requirement pass/fail in the result bundle.
