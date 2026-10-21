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
//   LightamerTestsIOP/Layers/Library/Sessions/Export/App
//     → { Core, IOP, Lightamer, WebP, MCP }   (M2-4-0 D3: identical dep face
//       on all six — 62 files @testable-import the app state across domains;
//       membership = explicit file lists, BUNDLE-MAP.txt is the source of
//       truth, single <3G-per-host memory gate replaces the old monolith)
//   LightamerUITests → Lightamer app  (drives the running app)
//
// Plan 13-1: +2 app extensions (the project's first NEW target shape):
//   LightamerQuickLook  → { Core, IOP }  (com.apple.quicklook.preview)
//   LightamerSpotlight  → { Core, IOP }  (com.apple.spotlight.import)
// Both embed into the host app (the app's dependencies below) and link the
// SHARED frameworks via @rpath (the Frameworks copy phase stays on the APP
// only — the appex processes resolve Core/IOP from the host bundle).
//
// Locks honored: D-05 bundle id `com.kamasylvia.lightamer` (one-way),
// D-33 Swift 6 strict concurrency (complete), macOS 27.0 floor on ALL targets
// (FOUND-01), ENABLE_HARDENED_RUNTIME (DIST-5).
// SPM policy (D-11-CONTEXT-1, revised Plan 14-1 T2): TWO packages —
// Swift-WebP (11-01, WebP write) and swift-sdk (14-1, the MCP server,
// EXACT-pinned: the 0.x line churns, no version ranges). Transitive deps
// ride along and are pinned in .package.resolved: swift-nio (a REAL app
// dependency — the SDK's HTTP server transport is a framework-agnostic
// pure-function face with NO listener, the NIO adapter leg is app code),
// swift-log, swift-system, eventsource. libavif stays out (native
// public.avif on the macOS 27 floor).
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

// Plan 13-1: the appex processes resolve the SHARED frameworks from the
// host bundle — PlugIns/<appex>.appex/Contents/MacOS sits four directory
// levels below Contents/, hence the 4× "../" walk to Frameworks (the
// in-appex "../Frameworks" leg covers a future local copy).
let appexRunpathSettings: SettingsDictionary = [
    "LD_RUNPATH_SEARCH_PATHS":
        .string("$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks"),
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
                // Plan 14-1 (D-14-CONTEXT-1): the official MCP swift-sdk,
                // EXACT pin (0.x churn — R1). App target only; LightamerCore
                // keeps ZERO import MCP (the registry seam is pure Swift).
                .package(
                    url: "https://github.com/modelcontextprotocol/swift-sdk.git",
                    exact: "0.12.1"),
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
            // D-04: app-level assets + String Catalog. M2-5-3: the LUT
            // set rides as a FOLDER reference so the bundle keeps the
            // LUTs/ directory the seeder reads as a unit (a glob would
            // copy the 40 tables flat into Resources/).
            resources: [
                "Resources/Assets.xcassets",
                "Resources/Localizable.xcstrings",
                .folderReference(path: "Resources/LUTs"),
                // M3-3-01 T2 (KD-2): the CC BY-SA spektrafilm film/paper
                // profiles ride as a FOLDER reference too — the bundle keeps
                // the FilmProfiles/ directory (profiles/ + compliance
                // documents) intact and physically separate from the MIT
                // LUTs/ set; a folder reference (not a bare directory
                // string) because Tuist 4.208 silently ignores the latter
                // (M2-5-3 precedent).
                .folderReference(path: "Resources/FilmProfiles"),
                // Plan M2-10-01 (E1): bundled AI models ride as a folder
                // reference too — the repo-root Resources/AIModels directory
                // (model bytes gitignored, .keep tracked) copies into the
                // bundle preserving AIModels/<profile_id>/ hierarchy.
                .folderReference(path: "Resources/AIModels"),
                // LENS-03 T3: the pinned Lensfun snapshot rides as a
                // folder reference (the seeder reads version_1/ as a
                // unit; the per-file SHA manifest ships beside it).
                .folderReference(path: "Resources/Lensfun"),
                "Resources/TestFixtures/**",
            ],
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                // Plan 13-1: the two app extensions EMBED into the host
                // (Tuist routes .appExtension products into the app's embed
                // copy phase); the shared Core/IOP frameworks stay in the
                // app's Frameworks directory and are resolved by the appex
                // processes through the runpath below.
                .target(name: "LightamerQuickLook"),
                .target(name: "LightamerSpotlight"),
                // Plan 14-1 (D-14-CONTEXT-1③④): the MCP SDK product lands
                // ONLY on the app target — the adapter layer
                // App/Sources/Lightamer/MCP/ is the sole import site; Core
                // and IOP stay SDK-free (layering iron rule).
                .package(product: "MCP"),
                // Plan 14-1 T4 (research D1): swift-nio is a REAL app
                // dependency, not an SDK implementation detail — the SDK's
                // HTTP server transport has NO listener; the NIO adapter leg
                // (McpHTTPTransport.swift) imports the three faces below.
                .package(product: "NIOCore"),
                .package(product: "NIOPosix"),
                .package(product: "NIOHTTP1"),
            ],
            settings: .settings(
                base: baseSettings.merging([
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "ENABLE_USER_SELECTED_FILES": "read-write", // non-sandboxed file access
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    // L057-B hardening (2026-10-08): raise the main-thread
                    // stack from the 8MB default to 64MB. The three AX-pressure
                    // crashes (the .ips trio in .work/gui-acceptance/fix-batch/)
                    // are main-thread stack-guard faults: AppKit entry stack +
                    // SwiftUI AX/layout update + a destructor cascade reach the
                    // guard page at only 74-165 frames — Debug -Onone SwiftUI
                    // frames are tens of KB each. The detonation surfaces are
                    // REAL AX paths (VoiceOver drives the same menu populate /
                    // hitTest / AccessibilityViewGraph updates), so give every
                    // build 8x headroom; the reservation is virtual, committed
                    // on use (Chrome/Firefox carry the same linker flag).
                    "OTHER_LDFLAGS": [
                        "$(inherited)", "-Xlinker", "-stack_size", "-Xlinker", "0x4000000",
                    ],
                ]) { $1 }
            )
        ),

        // ═════════ LightamerQuickLook (QL appex, Plan 13-1 T1) ═════════
        .target(
            name: "LightamerQuickLook",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "com.kamasylvia.lightamer.quicklook", // D-05 naming extension
            deploymentTargets: .macOS("27.0"),
            infoPlist: .file(path: "App/Extensions/QuickLook/Info.plist"),
            sources: ["App/Extensions/QuickLook/**"],
            entitlements: .file(
                path: "App/Extensions/QuickLook/LightamerQuickLook.entitlements"),
            dependencies: [
                // NOT embedded here — the HOST app carries the Frameworks
                // copy phase; the appex resolves them through the runpath.
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
            ],
            settings: .settings(base: baseSettings.merging(appexRunpathSettings))
        ),

        // ═════════ LightamerSpotlight (mdimporter appex, Plan 13-1 T1) ══
        .target(
            name: "LightamerSpotlight",
            destinations: [.mac],
            product: .appExtension,
            bundleId: "com.kamasylvia.lightamer.spotlight", // D-05 naming extension
            deploymentTargets: .macOS("27.0"),
            infoPlist: .file(path: "App/Extensions/Spotlight/Info.plist"),
            sources: ["App/Extensions/Spotlight/**"],
            entitlements: .file(
                path: "App/Extensions/Spotlight/LightamerSpotlight.entitlements"),
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
            ],
            settings: .settings(base: baseSettings.merging(appexRunpathSettings))
        ),

        // ═════════ LightamerTestsIOPParity (unit test bundle — IOP kernel parity/golden sub-domain — D5 split domain, M2-4-0 D1/D5) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsIOPParity",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.iop.parity",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/ParityGate.swift",
                "Tests/LightamerTests/ChainBuilderHelpers.swift",
                "Tests/LightamerTests/AgXTests.swift",
                "Tests/LightamerTests/AshiftParityTests.swift",
                "Tests/LightamerTests/BilateralParityTests.swift",
                "Tests/LightamerTests/BlendOpParityTests.swift",
                "Tests/LightamerTests/ChannelMixerColorContrastParityTests.swift",
                "Tests/LightamerTests/ChannelMixerRGBParityTests.swift",
                "Tests/LightamerTests/ColisaParityTests.swift",
                "Tests/LightamerTests/ColormatchIdentityGoldenTests.swift",
                "Tests/LightamerTests/ColormatchKernelParityTests.swift",
                "Tests/LightamerTests/ColormatchModuleTests.swift",
                "Tests/LightamerTests/ColormatchResolverBoxTests.swift",
                "Tests/LightamerTests/ColorBalanceRGBParityTests.swift",
                "Tests/LightamerTests/ColorZonesParityTests.swift",
                "Tests/LightamerTests/CropParityTests.swift",
                "Tests/LightamerTests/DenoiseProfileDerivationTests.swift",
                "Tests/LightamerTests/DenoiseProfileParityTests.swift",
                "Tests/LightamerTests/EqualizerParityTests.swift",
                "Tests/LightamerTests/FilmPlacementKernelTests.swift",
                "Tests/LightamerTests/FilmGoldenTests.swift",
                "Tests/LightamerTests/FilmicRGBTests.swift",
                "Tests/LightamerTests/FlipParityTests.swift",
                "Tests/LightamerTests/GeometryGoldenTests.swift",
                "Tests/LightamerTests/GradeKernelGoldenTests.swift",
                "Tests/LightamerTests/DrtKernelGoldenTests.swift",
                "Tests/LightamerTests/Aces2KernelGoldenTests.swift",
                "Tests/LightamerTests/Aces2InverseTests.swift",
                "Tests/LightamerTests/RasterInputPlaneTests.swift",
                "Tests/LightamerTests/RasterKernelParityTests.swift",
                "Tests/LightamerTests/GoldenColorTests.swift",
                "Tests/LightamerTests/GoldenParityTests.swift",
                "Tests/LightamerTests/HDRPipelineMatrixTests.swift",
                "Tests/LightamerTests/HighpassSoftenTests.swift",
                "Tests/LightamerTests/LensParityTests.swift",
                "Tests/LightamerTests/LensScaleGoldenTests.swift",
                "Tests/LightamerTests/LensProjectionGoldenTests.swift",
                "Tests/LightamerTests/LevelsParityTests.swift",
                "Tests/LightamerTests/LiquifyParityTests.swift",
                "Tests/LightamerTests/LocalContrastTests.swift",
                "Tests/LightamerTests/Lut3dEncodingTests.swift",
                "Tests/LightamerTests/Lut3dGoldenImageTests.swift",
                "Tests/LightamerTests/Lut3dKernelTests.swift",
                "Tests/LightamerTests/LutLibraryRecursionTests.swift",
                "Tests/LightamerTests/McpRenderParityTests.swift",
                "Tests/LightamerTests/MertensFusionGoldenTests.swift",
                "Tests/LightamerTests/PanoGoldenTests.swift",
                "Tests/LightamerTests/MonochromeParityTests.swift",
                "Tests/LightamerTests/NLMeansParityTests.swift",
                "Tests/LightamerTests/NoiseFixtureStatisticsTests.swift",
                "Tests/LightamerTests/ParametricMaskParityTests.swift",
                "Tests/LightamerTests/RetouchParityTests.swift",
                "Tests/LightamerTests/ShadhiParityTests.swift",
                "Tests/LightamerTests/SharpenParityTests.swift",
                "Tests/LightamerTests/SigmoidTests.swift",
                "Tests/LightamerTests/SkinSmoothParityTests.swift",
                "Tests/LightamerTests/TemperatureParityTests.swift",
                "Tests/LightamerTests/ToneCurveParityTests.swift",
                "Tests/LightamerTests/ToneEqualKernelTests.swift",
                "Tests/LightamerTests/ToneEqualLUTTests.swift",
                "Tests/LightamerTests/ToneEqualModuleTests.swift",
                "Tests/LightamerTests/ToneEqualParityTests.swift",
                "Tests/LightamerTests/ToneEqualPerfTests.swift",
                "Tests/LightamerTests/VibranceVelviaParityTests.swift",
            ],
            resources: ["Resources/TestFixtures/**"], // same fixtures ride in every bundle (D3; ~6.2 MB each)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
            ]
        ),



        // ═════════ LightamerTestsIOP (unit test bundle — IOP domain, M2-4-0 D1/D5) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsIOP",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.iop",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/ParityGate.swift",
                "Tests/LightamerTests/ChainBuilderHelpers.swift",
                "Tests/LightamerTests/BilateralGrid3DTests.swift",
                "Tests/LightamerTests/BloomTests.swift",
                "Tests/LightamerTests/ChannelMixerColorContrastTests.swift",
                "Tests/LightamerTests/ChannelMixerCommonTests.swift",
                "Tests/LightamerTests/ChannelMixerRGBCommitTests.swift",
                "Tests/LightamerTests/CIContextPoolMemoKeyTests.swift",
                "Tests/LightamerTests/ColorZonesCommitTests.swift",
                "Tests/LightamerTests/CPUDerivationTests.swift",
                "Tests/LightamerTests/CubeLutParserTests.swift",
                "Tests/LightamerTests/GradeParamsCodingTests.swift",
                "Tests/LightamerTests/DefaultFaceTests.swift",
                "Tests/LightamerTests/DehazeTests.swift",
                "Tests/LightamerTests/EDRViewportTests.swift",
                "Tests/LightamerTests/FilmPlacementTests.swift",
                "Tests/LightamerTests/FocusStackTests.swift",
                "Tests/LightamerTests/FullRenderBenchmarkTests.swift",
                "Tests/LightamerTests/GaussianBlurTests.swift",
                "Tests/LightamerTests/GeometryPointMapperTests.swift",
                "Tests/LightamerTests/GrainTests.swift",
                "Tests/LightamerTests/HDRMergeMathTests.swift",
                "Tests/LightamerTests/HomographyTests.swift",
                "Tests/LightamerTests/IOPieceIscaleTests.swift",
                "Tests/LightamerTests/IOPModuleTests.swift",
                "Tests/LightamerTests/L021DoubleScaleAuditTests.swift",
                "Tests/LightamerTests/ExifLensFieldsTests.swift",
                "Tests/LightamerTests/DNGOpcodeProbeTests.swift",
                "Tests/LightamerTests/LensMatchHardeningTests.swift",
                "Tests/LightamerTests/LensfunMemoTests.swift",
                "Tests/LightamerTests/LensPerCorrectionTests.swift",
                "Tests/LightamerTests/LensAutoApplyTests.swift",
                "Tests/LightamerTests/LensAutoCropTests.swift",
                "Tests/LightamerTests/LensProjectionResolveTests.swift",
                "Tests/LightamerTests/LensSnapshotTests.swift",
                "Tests/LightamerTests/LensCacheIsolationTests.swift",
                "Tests/LightamerTests/LabRoundTripTests.swift",
                "Tests/LightamerTests/LensfunDBTests.swift",
                "Tests/LightamerTests/MemoryBudgetTests.swift",
                "Tests/LightamerTests/M2DefaultChainPerfTests.swift",
                "Tests/LightamerTests/MertensFusionTests.swift",
                "Tests/LightamerTests/MertensLegTests.swift",
                "Tests/LightamerTests/MertensRasterDomainTests.swift",
                "Tests/LightamerTests/MertensMergeKindTests.swift",
                "Tests/LightamerTests/MetalContextTests.swift",
                "Tests/LightamerTests/ModuleBoundaryTests.swift",
                "Tests/LightamerTests/MonochromeCommitTests.swift",
                "Tests/LightamerTests/MonochromeGridTests.swift",
                "Tests/LightamerTests/MTBAlignTests.swift",
                "Tests/LightamerTests/MultiDisplayProfileTests.swift",
                "Tests/LightamerTests/MultiResolutionTests.swift",
                "Tests/LightamerTests/NoiseProfileStoreTests.swift",
                "Tests/LightamerTests/PanoCameraTests.swift",
                "Tests/LightamerTests/PanoFeatureTests.swift",
                "Tests/LightamerTests/PanoCropTests.swift",
                "Tests/LightamerTests/PanoGainTests.swift",
                "Tests/LightamerTests/PanoLegTests.swift",
                "Tests/LightamerTests/PanoMatchTests.swift",
                "Tests/LightamerTests/PanoMergeKindTests.swift",
                "Tests/LightamerTests/PanoWarpTests.swift",
                "Tests/LightamerTests/PipeCacheTests.swift",
                "Tests/LightamerTests/PreviewBucketTests.swift",
                "Tests/LightamerTests/PreviewChainPerfTests.swift",
                "Tests/LightamerTests/RAW03Tests.swift",
                "Tests/LightamerTests/RawDecodeOverridesTests.swift",
                "Tests/LightamerTests/RAWDecoderTests.swift",
                "Tests/LightamerTests/RasterColorDescriptionTests.swift",
                "Tests/LightamerTests/RasterIccSemanticsTests.swift",
                "Tests/LightamerTests/RasterDecodeLegTests.swift",
                "Tests/LightamerTests/RasterRoutingTests.swift",
                "Tests/LightamerTests/ROINegotiationTests.swift",
                "Tests/LightamerTests/ScopeReduceTests.swift",
                "Tests/LightamerTests/SkinRegionGeometryTests.swift",
                "Tests/LightamerTests/SoftProofStageTests.swift",
                "Tests/LightamerTests/StackAggregateTests.swift",
                "Tests/LightamerTests/StackMergeServiceTests.swift",
                "Tests/LightamerTests/TerminalTrioTests.swift",
                "Tests/LightamerTests/TextOverlayTests.swift",
                "Tests/LightamerTests/TileNegotiationRegressionTests.swift",
                "Tests/LightamerTests/TilingOverlapTests.swift",
                "Tests/LightamerTests/TilingPlanTests.swift",
                "Tests/LightamerTests/V50OrderTests.swift",
                "Tests/LightamerTests/VibranceVelviaCommitTests.swift",
                "Tests/LightamerTests/VignetteTests.swift",
                "Tests/LightamerTests/VisionDetectTests.swift",
            ],
            resources: ["Resources/TestFixtures/**"], // same fixtures ride in every bundle (D3; ~6.2 MB each)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
            ]
        ),


        // ═════════ LightamerTestsLayers (unit test bundle — LAYERS domain, M2-4-0 D1) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsLayers",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.layers",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/ChainBuilderHelpers.swift",
                "Tests/LightamerTests/ColorMatchOklabTests.swift",
                "Tests/LightamerTests/ColorMatchSolverGoldenTests.swift",
                "Tests/LightamerTests/ColorMatchStatsTests.swift",
                "Tests/LightamerTests/ColorMatchCDFSolverTests.swift",
                "Tests/LightamerTests/ColorMatchPoolingTests.swift",
                "Tests/LightamerTests/ColorMatchBakeGoldenTests.swift",
                "Tests/LightamerTests/ColormatchCubeAssetTests.swift",
                "Tests/LightamerTests/AIPatchAssemblyTests.swift",
                "Tests/LightamerTests/AIMaskDeterminismTests.swift",
                "Tests/LightamerTests/AIMaskEditPathsTests.swift",
                "Tests/LightamerTests/AIMaskFeatherTests.swift",
                "Tests/LightamerTests/AIMaskGeometryTests.swift",
                "Tests/LightamerTests/AIMaskPlaneFormatTests.swift",
                "Tests/LightamerTests/AIMaskSemanticTests.swift",
                "Tests/LightamerTests/PersonInstanceMaskTests.swift",
                "Tests/LightamerTests/ACESccEnvelopeTests.swift",
                "Tests/LightamerTests/Aces2MathTests.swift",
                "Tests/LightamerTests/DepthMaskEditingTests.swift",
                "Tests/LightamerTests/DepthMaskPipelineTests.swift",
                "Tests/LightamerTests/DrtRecordTests.swift",
                "Tests/LightamerTests/DrtEotfTests.swift",
                "Tests/LightamerTests/RasterDefaultRecordTests.swift",
                "Tests/LightamerTests/DrtPresetsTests.swift",
                "Tests/LightamerTests/DrtTailTests.swift",
                "Tests/LightamerTests/RenderProcessSeamTests.swift",
                "Tests/LightamerTests/DrtPostMigrationTests.swift",
                "Tests/LightamerTests/GradeEnvelopePerfProbeTests.swift",
                "Tests/LightamerTests/DrawnMaskRasterTests.swift",
                "Tests/LightamerTests/DrawnMaskSpecTests.swift",
                "Tests/LightamerTests/FollowEdgesTests.swift",
                "Tests/LightamerTests/FilmHistoryTests.swift",
                "Tests/LightamerTests/FilmLegTests.swift",
                "Tests/LightamerTests/FilmDeterminismTests.swift",
                "Tests/LightamerTests/FilmDescriptorTests.swift",
                "Tests/LightamerTests/FilmPlacementDriverTests.swift",
                "Tests/LightamerTests/FilmPrintBakeTests.swift",
                "Tests/LightamerTests/FilmProfileTests.swift",
                "Tests/LightamerTests/FilmFilterPackSolverTests.swift",
                "Tests/LightamerTests/FilmRecordTests.swift",
                "Tests/LightamerTests/HistoryStackTests.swift",
                "Tests/LightamerTests/LayerCacheTests.swift",
                "Tests/LightamerTests/LayerCompositeTests.swift",
                "Tests/LightamerTests/LayerCoreTests.swift",
                "Tests/LightamerTests/LayerDragPerfTests.swift",
                "Tests/LightamerTests/LayerE2ERoundTripTests.swift",
                "Tests/LightamerTests/LayerSkeletonTests.swift",
                "Tests/LightamerTests/LayerUIWiringTests.swift",
                "Tests/LightamerTests/MaskCombineTests.swift",
                "Tests/LightamerTests/MaskCommandTests.swift",
                "Tests/LightamerTests/MaskEditIncrementTests.swift",
                "Tests/LightamerTests/MaskFeatherAlignTests.swift",
                "Tests/LightamerTests/MaskThumbnailRendererTests.swift",
                "Tests/LightamerTests/PipelineDocumentTests.swift",
                "Tests/LightamerTests/PipelineLinkageTests.swift",
                "Tests/LightamerTests/Plan0605LeftoverTests.swift",
                "Tests/LightamerTests/RangePanelMappingTests.swift",
                "Tests/LightamerTests/RasterMaskRoundTripTests.swift",
            ],
            resources: ["Resources/TestFixtures/**"], // same fixtures ride in every bundle (D3; ~6.2 MB each)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
            ]
        ),

        // ═════════ LightamerTestsLibrary (unit test bundle — LIB domain, M2-4-0 D1) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsLibrary",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.library",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/ChainBuilderHelpers.swift",
                "Tests/LightamerTests/AICredentialStoreTests.swift",
                "Tests/LightamerTests/AutoStackClusteringTests.swift",
                "Tests/LightamerTests/AIEndpointPolicyTests.swift",
                "Tests/LightamerTests/AIProviderClientTests.swift",
                "Tests/LightamerTests/AIRatingDescriptionTests.swift",
                "Tests/LightamerTests/BackgroundTaskRegistryTests.swift",
                "Tests/LightamerTests/ExifFoldTests.swift",
                "Tests/LightamerTests/ExifSearchParserTests.swift",
                "Tests/LightamerTests/FilmstripModelTests.swift",
                "Tests/LightamerTests/FilterPredicateTests.swift",
                "Tests/LightamerTests/FilterSQLTests.swift",
                "Tests/LightamerTests/ImageLinkerTests.swift",
                "Tests/LightamerTests/ImportCompletionRegressionTests.swift",
                "Tests/LightamerTests/ImportDropTests.swift",
                "Tests/LightamerTests/ImportFilterTests.swift",
                "Tests/LightamerTests/ImportCategoryTests.swift",
                "Tests/LightamerTests/ImportTransportTiffTests.swift",
                "Tests/LightamerTests/ImportServiceTests.swift",
                "Tests/LightamerTests/ImportMergeStackTests.swift",
                "Tests/LightamerTests/LibraryBenchmarkHarness.swift",
                "Tests/LightamerTests/LibraryDocumentTests.swift",
                "Tests/LightamerTests/LibraryFilterDomainTests.swift",
                "Tests/LightamerTests/LibraryGridModelTests.swift",
                "Tests/LightamerTests/LibraryGridStackTests.swift",
                "Tests/LightamerTests/LibraryInspectorModelTests.swift",
                "Tests/LightamerTests/LibraryLegacyGateTests.swift",
                "Tests/LightamerTests/LibraryProjectControllerTests.swift",
                "Tests/LightamerTests/LibraryQueriesTests.swift",
                "Tests/LightamerTests/StackPaginationTests.swift",
                "Tests/LightamerTests/LibraryRelinkModelTests.swift",
                "Tests/LightamerTests/LibrarySchemaTests.swift",
                "Tests/LightamerTests/LibrarySchemaV5Tests.swift",
                "Tests/LightamerTests/LibraryStackStoreTests.swift",
                "Tests/LightamerTests/LibrarySearchModelTests.swift",
                "Tests/LightamerTests/LibraryStoreTests.swift",
                "Tests/LightamerTests/LibraryThumbnailBridgeTests.swift",
                "Tests/LightamerTests/LightamerPresetTests.swift",
                "Tests/LightamerTests/LutLibraryStoreTests.swift",
                "Tests/LightamerTests/MetadataServiceTests.swift",
                "Tests/LightamerTests/MetadataTests.swift",
                "Tests/LightamerTests/MertensProvenanceTests.swift",
                "Tests/LightamerTests/PanoProvenanceTests.swift",
                "Tests/LightamerTests/ModelAssetCatalogTests.swift",
                "Tests/LightamerTests/ModelAssetStoreTests.swift",
                "Tests/LightamerTests/Phase4SidecarTests.swift",
                "Tests/LightamerTests/Phase5SidecarTests.swift",
                "Tests/LightamerTests/Phase6SidecarTests.swift",
                "Tests/LightamerTests/FilmSidecarTests.swift",
                "Tests/LightamerTests/SidecarV10Tests.swift",
                "Tests/LightamerTests/SidecarV11Tests.swift",
                "Tests/LightamerTests/PresetApplierTests.swift",
                "Tests/LightamerTests/PresetsStoreTests.swift",
                "Tests/LightamerTests/ProvenanceV4Tests.swift",
                "Tests/LightamerTests/EmbeddingScannerTests.swift",
                "Tests/LightamerTests/LabelEngineTests.swift",
                "Tests/LightamerTests/SemanticSearchTests.swift",
                "Tests/LightamerTests/SemanticStoreTests.swift",
                "Tests/LightamerTests/TileInferenceTests.swift",
                "Tests/LightamerTests/SidecarMetadataV3Tests.swift",
                "Tests/LightamerTests/SidecarRoundTripTests.swift",
                "Tests/LightamerTests/SidecarSeedTopUpTests.swift",
                "Tests/LightamerTests/SidecarTieBreakTests.swift",
                "Tests/LightamerTests/SmartAlbumStoreTests.swift",
                "Tests/LightamerTests/StableHashTests.swift",
                "Tests/LightamerTests/SingleWriterLockTests.swift",
                "Tests/LightamerTests/ProjectLockTests.swift",
                "Tests/LightamerTests/WordPieceTokenizerTests.swift",
                "Tests/LightamerTests/XMPContainerInjectorTests.swift",
                "Tests/LightamerTests/XMPExportMatrixTests.swift",
                "Tests/LightamerTests/XMPImportTests.swift",
                "Tests/LightamerTests/XMPWriterTests.swift",
            ],
            resources: [
                "Resources/TestFixtures/**",
                // Plan M2-10-02 (E2): the WordPiece golden fixture rides the
                // LIB bundle (revision-locked, <=10KB — Scripts/ai-models/
                // tokenizer_ref.py generates it; the CI face needs no model).
                "Tests/Fixtures/tokenizer_golden.json",
            ],
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
            ]
        ),

        // ═════════ LightamerTestsSessions (unit test bundle — SESS domain, M2-4-0 D1) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsSessions",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.sessions",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/CatalogBenchmarkHarness.swift",
                "Tests/LightamerTests/CatalogBrowserModelTests.swift",
                "Tests/LightamerTests/CatalogFilterSQLTests.swift",
                "Tests/LightamerTests/CatalogIndexSchemaTests.swift",
                "Tests/LightamerTests/CatalogModeIsolationTests.swift",
                "Tests/LightamerTests/CatalogOrganizationTests.swift",
                "Tests/LightamerTests/CatalogProjectorTests.swift",
                "Tests/LightamerTests/CatalogRebuildTests.swift",
                "Tests/LightamerTests/CatalogSmartAlbumDomainTests.swift",
                "Tests/LightamerTests/CatalogThumbnailRouterTests.swift",
                "Tests/LightamerTests/CatalogTreeModelTests.swift",
                "Tests/LightamerTests/CullingPipelineTests.swift",
                "Tests/LightamerTests/PasteSemanticsTests.swift",
                "Tests/LightamerTests/Perf07MassApplyTests.swift",
                "Tests/LightamerTests/ReconcileDiffTests.swift",
                "Tests/LightamerTests/SessionBatchApplierTests.swift",
                "Tests/LightamerTests/SessionBrowserModelTests.swift",
                "Tests/LightamerTests/SessionIndexMigrationTests.swift",
                "Tests/LightamerTests/SessionIndexStoreTests.swift",
                "Tests/LightamerTests/SessionReconcileE2ETests.swift",
                "Tests/LightamerTests/SessionSwitchTests.swift",
                "Tests/LightamerTests/SessionThumbnailProviderTests.swift",
                "Tests/LightamerTests/SessionTreeScannerTests.swift",
                "Tests/LightamerTests/SessionWatcherTests.swift",
                "Tests/LightamerTests/ThumbnailMemoryCacheTests.swift",
            ],
            resources: ["Resources/TestFixtures/**"], // same fixtures ride in every bundle (D3; ~6.2 MB each)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
            ]
        ),

        // ═════════ LightamerTestsExport (unit test bundle — EXPORT domain, M2-4-0 D1) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsExport",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.export",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/ChainBuilderHelpers.swift",
                "Tests/LightamerTests/DrtOutputColorSpaceTests.swift",
                "Tests/LightamerTests/RasterRoundTripTests.swift",
                "Tests/LightamerTests/ExportCollisionPolicyTests.swift",
                "Tests/LightamerTests/ExportDrtChainTests.swift",
                "Tests/LightamerTests/ExportDrtColorSpaceSrgbTests.swift",
                "Tests/LightamerTests/ExportDrtTailE2ETests.swift",
                "Tests/LightamerTests/ExportEncoderGoldenTests.swift",
                "Tests/LightamerTests/ExportGainMapTests.swift",
                "Tests/LightamerTests/ExportFilmChainTests.swift",
                "Tests/LightamerTests/ExportEncoderMetadataTests.swift",
                "Tests/LightamerTests/ExportFileNameTemplateTests.swift",
                "Tests/LightamerTests/ExportIccEmbedTests.swift",
                "Tests/LightamerTests/ExportMetadataPolicyTests.swift",
                "Tests/LightamerTests/ExportNamingE2ETests.swift",
                "Tests/LightamerTests/ExportNamerTests.swift",
                "Tests/LightamerTests/MertensFusionPerfProbeTests.swift",
                "Tests/LightamerTests/PanoFusionPerfProbeTests.swift",
                "Tests/LightamerTests/ExportPerfProbeTests.swift",
                "Tests/LightamerTests/ExportPhaseE2ETests.swift",
                "Tests/LightamerTests/ExportPipeTests.swift",
                "Tests/LightamerTests/ExportQuantizerTests.swift",
                "Tests/LightamerTests/ExportQueueContractTests.swift",
                "Tests/LightamerTests/ExportQueueTests.swift",
                "Tests/LightamerTests/ExportRecipeTests.swift",
                "Tests/LightamerTests/ExportRendererE2ETests.swift",
                "Tests/LightamerTests/ExportTargetsTests.swift",
                "Tests/LightamerTests/QuickLookPerfProbeTests.swift",
                "Tests/LightamerTests/QuickLookRendererTests.swift",
                "Tests/LightamerTests/SpotlightAttributeMapperTests.swift",
                "Tests/LightamerTests/WebPEncoderTests.swift",
                "Tests/LightamerTests/WebPIntegrationSmokeTests.swift",
                "Tests/LightamerTests/YiyinBordersTests.swift",
                "Tests/LightamerTests/YiyinE2ETests.swift",
                "Tests/LightamerTests/YiyinExifFormatTests.swift",
                "Tests/LightamerTests/YiyinExportSettingsTests.swift",
                "Tests/LightamerTests/YiyinFontStoreTests.swift",
                "Tests/LightamerTests/YiyinLayoutTests.swift",
                "Tests/LightamerTests/YiyinMetadataWalkTests.swift",
                "Tests/LightamerTests/YiyinWatermarkTests.swift",
            ],
            resources: ["Resources/TestFixtures/**"], // same fixtures ride in every bundle (D3; ~6.2 MB each)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
            ]
        ),

        // ═════════ LightamerTestsApp (unit test bundle — APP domain, M2-4-0 D1) ═════════
        // Membership is the explicit file list below — the single source of
        // truth is .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt
        // (T3 audits array-union == 231 domain files, no orphans/dupes).
        // No directory glob: the 231 test files stay flat in
        // Tests/LightamerTests/ and belong to exactly ONE domain target
        // each; only the three zero-test SHARED helpers may repeat.
        .target(
            name: "LightamerTestsApp",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.kamasylvia.lightamer.tests.app",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: [
                "Tests/LightamerTests/Fixtures.swift",
                "Tests/LightamerTests/ChainBuilderHelpers.swift",
                "Tests/LightamerTests/AIWorkerClientTests.swift",
                "Tests/LightamerTests/AIMaskPatchFlowTests.swift",
                "Tests/LightamerTests/ExportPresetTests.swift",
                "Tests/LightamerTests/AIWorkerProtocolTests.swift",
                "Tests/LightamerTests/AppErrorTests.swift",
                "Tests/LightamerTests/AnalysisRegistryTests.swift",
                "Tests/LightamerTests/CompatRecordTests.swift",
                "Tests/LightamerTests/EnhanceCopyTests.swift",
                "Tests/LightamerTests/DepthGoldenTests.swift",
                "Tests/LightamerTests/DepthPerfProbeTests.swift",
                "Tests/LightamerTests/DepthWorkerLegTests.swift",
                "Tests/LightamerTests/EnhanceDialogTests.swift",
                "Tests/LightamerTests/BeforeAfterTests.swift",
                "Tests/LightamerTests/BuiltInLutSetTests.swift",
                "Tests/LightamerTests/CatalogAddFaceTests.swift",
                "Tests/LightamerTests/CropOverlayTests.swift",
                "Tests/LightamerTests/DefaultLookTests.swift",
                "Tests/LightamerTests/LabelingDefaultsTests.swift",
                "Tests/LightamerTests/EditorMetalLegRegressionTests.swift",
                "Tests/LightamerTests/EditorStackRoutingTests.swift",
                "Tests/LightamerTests/EffectsWiringTests.swift",
                "Tests/LightamerTests/ExportAssemblyTests.swift",
                "Tests/LightamerTests/ExportGainMapPanelTests.swift",
                "Tests/LightamerTests/ExportInspectorFaceTests.swift",
                "Tests/LightamerTests/ExportMemoryKeysTests.swift",
                "Tests/LightamerTests/ExportNamingTemplateStoreTests.swift",
                "Tests/LightamerTests/EyedropperTests.swift",
                "Tests/LightamerTests/FulltextSearchTests.swift",
                "Tests/LightamerTests/GradeCatalogTests.swift",
                "Tests/LightamerTests/GUI22UndoWarmColdTests.swift",
                "Tests/LightamerTests/LutEncodingPanelTests.swift",
                "Tests/LightamerTests/McpCullingImageBudgetTests.swift",
                "Tests/LightamerTests/McpCullingToolsetTests.swift",
                "Tests/LightamerTests/McpEditingToolsetTests.swift",
                "Tests/LightamerTests/McpFinalSnapshotTests.swift",
                "Tests/LightamerTests/McpHostTests.swift",
                "Tests/LightamerTests/McpLauncherSentinelTests.swift",
                "Tests/LightamerTests/McpLauncherTests.swift",
                "Tests/LightamerTests/McpProjectArbitrationTests.swift",
                "Tests/LightamerTests/McpProjectReadOnlyErrorTests.swift",
                "Tests/LightamerTests/McpProjectToolsetTests.swift",
                "Tests/LightamerTests/McpSearchStateToolsetTests.swift",
                "Tests/LightamerTests/McpMatchColorToolsetTests.swift",
                "Tests/LightamerTests/McpMatchColorParityTests.swift",
                "Tests/LightamerTests/McpRegistrySnapshotTests.swift",
                "Tests/LightamerTests/McpControlToolsetTests.swift",
                "Tests/LightamerTests/AgentControlCoordinatorTests.swift",
                "Tests/LightamerTests/LensPanelReadoutTests.swift",
                "Tests/LightamerTests/LensProfileBrowserTests.swift",
                "Tests/LightamerTests/LensfunDistributionTests.swift",
                "Tests/LightamerTests/MaskDefaultBehaviorTests.swift",
                "Tests/LightamerTests/MaskGroupsPanelTests.swift",
                "Tests/LightamerTests/MaskItemSemanticsTests.swift",
                "Tests/LightamerTests/MaskRevisionTests.swift",
                "Tests/LightamerTests/MertensMergeUITests.swift",
                "Tests/LightamerTests/NodeCanvasGeometryTests.swift",
                "Tests/LightamerTests/NodeGraphCommandTests.swift",
                "Tests/LightamerTests/NodesPanelModelTests.swift",
                "Tests/LightamerTests/NodeOwnershipCatalogTests.swift",
                "Tests/LightamerTests/PanelWiringTests.swift",
                "Tests/LightamerTests/PanelParamsDecodeProbeTests.swift",
                "Tests/LightamerTests/ProjectReadOnlyFaceTests.swift",
                "Tests/LightamerTests/PanoMergeUITests.swift",
                "Tests/LightamerTests/SettingsPagesTests.swift",
                "Tests/LightamerTests/ACASettingsTests.swift",
                "Tests/LightamerTests/LCRSettingsTests.swift",
                "Tests/LightamerTests/AIEntryPointsTests.swift",
                "Tests/LightamerTests/SidecarV5Tests.swift",
                "Tests/LightamerTests/ProcessVersionCarrierTests.swift",
                "Tests/LightamerTests/DrtSidecarTests.swift",
                "Tests/LightamerTests/SidecarV7Tests.swift",
                "Tests/LightamerTests/SidecarV8Tests.swift",
                "Tests/LightamerTests/VersionSwapTests.swift",
                "Tests/LightamerTests/VersionsPanelTests.swift",
                "Tests/LightamerTests/HistoryRowJumpTests.swift",
                "Tests/LightamerTests/AdjustmentTransferTests.swift",
                "Tests/LightamerTests/CleanTerminateSentinelTests.swift",
                // F0P-02 T1-T4: the shell-handover menu/shell test families.
                "Tests/LightamerTests/MenuBridgeObservationTests.swift",
                "Tests/LightamerTests/NSMenuParityTests.swift",
                "Tests/LightamerTests/ShellGraphMigrationTests.swift",
                "Tests/LightamerTests/ShellWindowControllerSmokeTests.swift",
                "Tests/LightamerTests/SheetEnvironmentInjectionTests.swift",
                "Tests/LightamerTests/ToastFaceTests.swift",
                "Tests/LightamerTests/DrtPersistenceTests.swift",
                "Tests/LightamerTests/EditorPreviewColorSpaceTests.swift",
                "Tests/LightamerTests/LightamerSliderScrubTests.swift",
                "Tests/LightamerTests/SkillsReferenceTests.swift",
                "Tests/LightamerTests/FilmCoordinatorTests.swift",
                "Tests/LightamerTests/DrtPanelModelTests.swift",
                "Tests/LightamerTests/FilmPanelTests.swift",
                "Tests/LightamerTests/FilmCardTests.swift",
                "Tests/LightamerTests/FilmLatitudePanelTests.swift",
                "Tests/LightamerTests/DrtViewportTests.swift",
                "Tests/LightamerTests/RasterEditFaceTests.swift",
                "Tests/LightamerTests/RasterHdrViewportTests.swift",
                "Tests/LightamerTests/RasterEditFaceTests.swift",
                "Tests/LightamerTests/RasterHdrViewportTests.swift",
                "Tests/LightamerTests/RasterHdrViewportTests.swift",
                "Tests/LightamerTests/SoftProofUIWiringTests.swift",
                "Tests/LightamerTests/ThemeTokensTests.swift",
                "Tests/LightamerTests/ViewportTransformTests.swift",
                "Tests/LightamerTests/WorkspaceRoutingTests.swift",
                "Tests/LightamerTests/YiyinSheetSizingTests.swift",
                "Tests/LightamerTests/ImportCategorySelectorTests.swift",
                "Tests/LightamerTests/ImportProgressCoalescingTests.swift",
                "Tests/LightamerTests/ExportCollisionPickerTests.swift",
                "Tests/LightamerTests/NLMeansDragDowngradeTests.swift",
                "Tests/LightamerTests/ColorMatchServiceTests.swift",
                "Tests/LightamerTests/ColorMatchPanelModelTests.swift",
            ],
            resources: ["Resources/TestFixtures/**"], // same fixtures ride in every bundle (D3; ~6.2 MB each)
            dependencies: [
                .target(name: "LightamerCore"),
                .target(name: "LightamerIOP"),
                .target(name: "Lightamer"),
                .package(product: "WebP"),
                .package(product: "MCP"),
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
            // M2-4-0 D6: all six unit-test bundles + UITests LAST (order
            // invariant — UI tests always run after the unit bundles).
            // Note: `xcodebuild test` through this scheme hits the
            // testmanagerd enrollment prompt (L019b) — unit tests run via
            // Scripts/test-direct.sh direct launch; the testAction exists so
            // `build-for-testing` produces every .xctest in one pass.
            testAction: .targets(
                [
                    "LightamerTestsIOP", "LightamerTestsIOPParity",
                    "LightamerTestsLayers",
                    "LightamerTestsLibrary", "LightamerTestsSessions",
                    "LightamerTestsExport", "LightamerTestsApp",
                    "LightamerUITests",
                ],
                configuration: .debug
            ),
            runAction: .runAction(configuration: .debug),
            archiveAction: .archiveAction(configuration: .release)
        )
    ]
)
