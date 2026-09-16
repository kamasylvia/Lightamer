import ProjectDescription

// ─────────────────────────────────────────────────────────────────────────────
// Lightamer — Tuist manifest (D-02/D-02a multi-target + Tuist)
//
// Five targets, compiler-enforced module DAG (D-03):
//   LightamerCore (framework, no Lightamer deps)
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
// ─────────────────────────────────────────────────────────────────────────────

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete", // D-33 (one-way)
    "MARKETING_VERSION": "0.1.0",
    "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_STYLE": "Automatic",
    "CODE_SIGN_IDENTITY": "-",
    "ENABLE_HARDENED_RUNTIME": "YES", // DIST-5
    "METAL_ENABLE_DEBUGGING_INFO": "YES",
]

let project = Project(
    name: "Lightamer",
    organizationName: "kamasylvia",
    options: .options(
        // Project-wide default; per-target deploymentTargets below also set (RESEARCH §1 gotcha).
        deploymentTargets: .macOS("27.0"),
        textSettings: .textSettings(indentWidth: 4, tabWidth: 4)
    ),
    settings: .settings(base: baseSettings),
    targets: [
        // ═════════ LightamerCore (framework, no Lightamer deps) ═════════
        .target(
            name: "LightamerCore",
            destinations: [.macOS],
            product: .framework,
            bundleId: "com.kamasylvia.lightamer.core",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["LightamerCore/Sources/**"],
            resources: ["LightamerCore/Resources/**"],
            dependencies: [] // D-03: Core depends on nothing
        ),

        // ═════════ LightamerIOP (framework, depends on Core) ═════════
        .target(
            name: "LightamerIOP",
            destinations: [.macOS],
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
            destinations: [.macOS],
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
            destinations: [.macOS],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["Tests/LightamerTests/**"],
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
            ]
        ),

        // ═════════ LightamerUITests (UI, depends on the app) ═════════
        .target(
            name: "LightamerUITests",
            destinations: [.macOS],
            product: .uiTests,
            bundleId: "com.kamasylvia.lightamer.uitests",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["Tests/LightamerUITests/**"],
            dependencies: [
                .target(name: "Lightamer") // UITests drive the app
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "Lightamer",
            buildAction: .buildAction(targets: [.target("Lightamer")]),
            runAction: .runAction(configuration: .debug),
            testAction: .testAction(targets: [
                .target("LightamerTests"),
                .target("LightamerUITests"),
            ], configuration: .debug),
            archiveAction: .archiveAction(configuration: .release)
        )
    ]
)
