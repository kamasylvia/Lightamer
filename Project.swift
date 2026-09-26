import ProjectDescription

// ─────────────────────────────────────────────────────────────────────────────
// Lightamer — Tuist manifest (D-02/D-02a multi-target + Tuist)
//
// Five targets, compiler-enforced module DAG (D-03):
//   LightamerCore (framework, no Lightamer deps — EXTERNAL packages allowed:
//     the D-03 line is "no other Lightamer target", Plan 11-01 wires WebP)
//     ↑
//   LightamerIOP (framework, deps Core)
//     ↑
//   Lightamer (app, deps Core + IOP)
//   LightamerTests  → { Core, IOP }   (@testable import of both)
//   LightamerUITests → Lightamer app  (drives the running app)
//
// Locks honored: D-05 bundle id `com.kamasylvia.lightamer` (one-way),
// D-33 Swift 6 strict concurrency (complete), macOS 27.0 floor on ALL targets
// (FOUND-01), ENABLE_HARDENED_RUNTIME (DIST-5).
// SPM policy (D-11-CONTEXT-1): Swift-WebP is the ONLY package in this
// project — libavif stays out (native public.avif on the macOS 27 floor).
// ─────────────────────────────────────────────────────────────────────────────

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete", // D-33 (one-way)
    "MARKETING_VERSION": "0.1.0",
    "CURRENT_PROJECT_VERSION": "1",
    // Manual signing with the local self-signed "Lightamer Dev" identity —
    // every target signs with the SAME stable certificate so macOS TCC grants
    // (XCUITest automation, keychain) key to the certificate instead of the
    // per-build cdhash; ad-hoc "-" re-prompts after every rebuild and breaks
    // plugin dlopen (Team-ID mismatch). Distribution switches to a real
    // Developer ID in Phase 13 (DIST-02).
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Lightamer Dev",
    "METAL_ENABLE_DEBUGGING_INFO": "YES",
]

// Per-configuration hardening (the Xcode 26 debug-dylib + library-validation
// trap: a hardened Debug app cannot load its .debug.dylib when incremental
// builds leave mixed ad-hoc/cert signatures → SIGABRT at spawn). Debug runs
// unhardened + monolithic; Release keeps hardened runtime for DIST-5.
let debugConfigSettings: SettingsDictionary = [
    "ENABLE_DEBUG_DYLIB": "NO",
    "ENABLE_HARDENED_RUNTIME": "NO",
]
let releaseConfigSettings: SettingsDictionary = [
    "ENABLE_HARDENED_RUNTIME": "YES", // DIST-5
    // PERF-5's formal Release-configuration gate (Plan 03-06-T7) builds the
    // test target against Release frameworks; @testable import requires
    // testability on those modules (Debug default YES, Release default NO).
    "ENABLE_TESTABILITY": "YES",
]

let project = Project(
    name: "Lightamer",
    organizationName: "kamasylvia",
    options: .options(
        // Tuist 4.208: Project.Options carries no project-wide deploymentTargets
        // — the per-target `deploymentTargets: .macOS("27.0")` below is the
        // single source (RESEARCH §1 gotcha satisfied on every target).
        textSettings: .textSettings(indentWidth: 4, tabWidth: 4)
    ),
            // The project's ONLY SPM package (D-11-CONTEXT-1, Plan 11-01 T4):
            // ainame/Swift-WebP — MIT, language mode 6, libwebp 1.5.0+ via
            // the libwebp-Xcode C source package (no xcframework download
            // step), macOS 11+ floor (no constraint under macOS 27).
            // WebP WRITE is absent from CGImageDestination on every macOS;
            // this is the single deliberate dependency (RESEARCH §2).
            packages: [
                .package(url: "https://github.com/ainame/Swift-WebP.git", from: "0.6.0"),
            ],
            settings: .settings(
                base: baseSettings,
                configurations: [
                    .debug(name: "Debug", settings: debugConfigSettings),
                    .release(name: "Release", settings: releaseConfigSettings),
                ]
            ),
    targets: [
        // ═════════ LightamerCore (framework, no Lightamer deps) ═════════
        .target(
            name: "LightamerCore",
            destinations: [.mac],
            product: .framework,
            bundleId: "com.kamasylvia.lightamer.core",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["LightamerCore/Sources/**"],
            resources: ["LightamerCore/Resources/**"],
            dependencies: [
                // D-03: Core depends on no other LIGHTAMER target; external
                // packages are allowed (Plan 11-01: WebP is the export
                // encoder's one non-native format — RESEARCH §2.3 placement).
                // Tuist 4.208 TargetDependency.package takes the PRODUCT
                // name only (resolved against the project packages above).
                .package(product: "WebP"),
            ],
        ),

        // ═════════ LightamerIOP (framework, depends on Core) ═════════
        .target(
            name: "LightamerIOP",
            destinations: [.mac],
            product: .framework,
            bundleId: "com.kamasylvia.lightamer.iop",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["LightamerIOP/Sources/**"],
            resources: ["LightamerIOP/Resources/**"],
            dependencies: [
                .target(name: "LightamerCore") // D-03: IOP → Core only
            ]
        ),

        // ═════════ Lightamer (app, depends on Core + IOP) ═════════
        .target(
            name: "Lightamer",
            destinations: [.mac],
            product: .app,
            bundleId: "com.kamasylvia.lightamer", // D-05 (one-way)
            deploymentTargets: .macOS("27.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Lightamer",
                    "CFBundleDocumentTypes": [
                        [
                            "CFBundleTypeName": "RAW Image",
                            "CFBundleTypeRole": "Viewer",
                            "LSItemContentTypes": [
                                "public.camera-raw-image",
                                "public.heic", "public.jpeg", "public.png",
                                "public.tiff", "org.webmproject.webp",
                            ],
                        ]
                    ],
                ]
            ),
            sources: ["App/Sources/**"],
            resources: ["Resources/**"], // D-04: app-level assets + String Catalog
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
            ],
            settings: .settings(
                base: baseSettings.merging([
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "ENABLE_USER_SELECTED_FILES": "read-write", // non-sandboxed file access
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                ]) { $1 }
            )
        ),

        // ═════════ LightamerTests (unit, depends on Core + IOP) ═════════
        .target(
            name: "LightamerTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["Tests/LightamerTests/**"],
            resources: ["Resources/TestFixtures/**"], // Plan 06: raster fixtures ride in the test bundle (Bundle(for:) access); the ~1.2 GB RAW camera samples stay untracked in .work/plans/01-05/samples/ and are located by path (see Fixtures.swift)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"), // Plan 03-02: D-T6 panel wiring tests drive the APP-side state (InspectorState/PipeCoordinator) via @testable
                .package(product: "WebP"), // Plan 11-01: the WebPIntegrationSmokeTests import WebP directly (link smoke)
            ]
        ),

        // ═════════ LightamerUITests (UI, depends on the app) ═════════
        .target(
            name: "LightamerUITests",
            destinations: [.mac],
            product: .uiTests,
            bundleId: "com.kamasylvia.lightamer.uitests",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["Tests/LightamerUITests/**"],
            dependencies: [
                .target(name: "Lightamer") // UITests drive the app
            ],
            // Hardened runtime OFF for the test runner: a hardened + ad-hoc
            // process enforces library validation, and an ad-hoc plugin can
            // never match ("different Team IDs" dlopen failure — the runner
            // and its .xctest each carry a unique ad-hoc identity). DIST-5
            // hardened-runtime applies to the shipped Release app; Debug is
            // unhardened per-configuration (see debugConfigSettings).
            settings: .settings(base: baseSettings.merging([
                "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "YES",
            ]))
        ),
    ],
    schemes: [
        .scheme(
            name: "Lightamer",
            buildAction: .buildAction(targets: [.target("Lightamer")]),
            testAction: .targets(
                ["LightamerTests", "LightamerUITests"],
                configuration: .debug
            ),
            runAction: .runAction(configuration: .debug),
            archiveAction: .archiveAction(configuration: .release)
        )
    ]
)
