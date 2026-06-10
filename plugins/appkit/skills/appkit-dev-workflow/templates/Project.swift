// Tuist manifest for a programmatic AppKit app on macOS 26 Tahoe.
//
// Usage:  tuist generate --no-open   ->  MyApp.xcworkspace  ->  ./build-and-run.sh
// Docs:   https://docs.tuist.dev
//
// Rename "MyApp" throughout, drop your Swift files under Sources/, and (optionally)
// UI tests under UITests/. The deployment target is 26.0 so you get Liquid Glass and
// the floating glass toolbar/sidebar automatically. To support older macOS, LOWER it
// (e.g. .macOS("14.0")) and gate any NSGlassEffectView use behind
// `if #available(macOS 26, *)`.
//
// Edit this file with `tuist edit` to get autocomplete, syntax highlighting, and
// validation of the ProjectDescription API for your installed Tuist version.

import ProjectDescription

let project = Project(
    name: "MyApp",

    // External Swift Package dependencies (uncomment to use). For a small graph,
    // declaring them inline here is simplest; for a large one, prefer a
    // Tuist/Package.swift + `tuist install` + `.external(name:)` (see the
    // appkit-dev-workflow skill).
    packages: [
        // .remote(url: "https://github.com/sparkle-project/Sparkle",
        //         requirement: .upToNextMajor(from: "2.0.0")),
    ],

    // Project-wide build settings applied to every target.
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",            // Swift 6 language mode (strict concurrency). "5.0" opts out.
        "MARKETING_VERSION": "1.0",
        "CURRENT_PROJECT_VERSION": "1",
        "CODE_SIGN_STYLE": "Automatic",    // sign to run locally; Developer ID for release (appkit-packaging)
    ]),

    targets: [
        .target(
            name: "MyApp",
            destinations: .macOS,
            product: .app,
            bundleId: "com.example.MyApp",
            deploymentTargets: .macOS("26.0"),
            // GENERATE_INFOPLIST_FILE is on by default in Tuist; we extend the
            // generated plist. No NSMainStoryboardFile / NSMainNibFile key: this is
            // a code-only app whose entry point is Sources/main.swift
            // (NSApplication.shared + AppDelegate).
            infoPlist: .extendingDefault(with: [
                "NSPrincipalClass": "NSApplication",
                "LSApplicationCategoryType": "public.app-category.productivity",
                "NSHumanReadableCopyright": "© 2026 Example",
            ]),
            sources: ["Sources/**"],
            resources: [],
            dependencies: [
                // .package(product: "Sparkle"),
            ],
            settings: .settings(base: [
                "ENABLE_HARDENED_RUNTIME": "YES",   // required for notarization later; harmless in Debug
            ])
        ),

        .target(
            name: "MyAppUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.example.MyAppUITests",
            deploymentTargets: .macOS("26.0"),
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "MyApp"),
            ]
        ),
    ]

    // Schemes are generated automatically: Tuist creates a shared "MyApp" scheme
    // whose Test action includes MyAppUITests (because the UI-test target depends
    // on MyApp). To customise, add an explicit `schemes:` array here.
)
