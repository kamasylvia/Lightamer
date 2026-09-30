import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// EditorStackRoutingTests (Plan M2-3-3 T2) — the seven-tab rehoming machine
// checks:
//
//   1. COMPLETENESS (checker m3): the DYNAMIC populated provider set
//      (`registerDefaultProviders(defaultFace: true)` → `panelOpNames`)
//      minus {TextOverlay} appears in the routing table EXACTLY ONCE —
//      the yiyin pair rehomes to the top-bar-sheet disposition inside the
//      table, Preset has no registry op (outside the domain), Lut rehomes
//      once on the LUT page.
//   2. THE DISABLED SIX never appear in the table (the M2-1 narrowed face;
//      checker E1: Display Transform = Vignette + the DRT placeholder — no
//      AgX row).
//   3. PAGE ORDER == the Alcedo `EditorAdjustmentStack.qml` sequence
//      (`allCases` order pinned).
//   4. TextOverlay is NOT in the table (the yiyin sheet's text carrier).
//   5. The TAB-MATRIX markdown agrees with the table line by line (every
//      opName literal present, panel-row counts equal, the yiyin pair in
//      the sheet section, the special-page slots declared).
//   6. T1's tool rail states (the three sections + the collapse semantics)
//      — the plan's T1 marker assertions ride this file.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class EditorStackRoutingTests: XCTestCase {

    // MARK: - The dynamic populated set (the m3 assertion domain)

    /// `registerDefaultProviders(defaultFace: true)` = the production
    /// default-face provider population.
    private func populatedDefaultFaceProviderOps() -> Set<String> {
        let state = InspectorState()
        state.registerDefaultProviders(defaultFace: true)
        return Set(state.panelOpNames)
    }

    func testPopulatedRegistryMinusTextOverlayRehomesExactlyOnce() {
        let populated = populatedDefaultFaceProviderOps()
        // The dynamic face sanity: the M2-1 disabled six never populate the
        // default face (the registry gate) and TextOverlay does.
        for disabled in Self.disabledSix {
            XCTAssertFalse(
                populated.contains(disabled),
                "\(disabled) is the M2-1 disabled face — it must never populate")
        }
        XCTAssertTrue(
            populated.contains(TextOverlayModule.opName),
            "textOverlay populates the provider face (it rides the yiyin sheet)")

        // The m3 domain: populated − {TextOverlay} == the table's rehomed
        // set, each exactly once.
        let expected = populated.subtracting([TextOverlayModule.opName])
        let rehomed = EditorTabRoutingTable.allRehomedPanels
        let rehomedOps = rehomed.map(\.opName)

        XCTAssertEqual(
            Set(rehomedOps), expected,
            "the table rehomes exactly the populated face minus textOverlay")
        XCTAssertEqual(
            rehomedOps.count, Set(rehomedOps).count,
            "every panel rehomes EXACTLY ONCE (no double-homing)")
        // The executed cardinality (M2-5-2 T3): 40 populated − 1 = 39.
        // (M2-3-3 base 34 − textOverlay = 33; +6 T3 scalar providers
        // [cat02WhiteBalance/contrast/white/black/tint/saturation] → 40.)
        XCTAssertEqual(expected.count, 39)
        XCTAssertEqual(rehomedOps.count, 39)
    }

    // MARK: - M2-5-2 T3: the six scalar panels (AC#4)

    /// The six catalog ops' providers populate AND their rows ride the
    /// right pages/groups. The panels' slider ranges/defaults cite the
    /// modules' own range constants AT COMPILE TIME (GradeScalarPanels.swift
    /// — the "constant reference" acceptance form: zero hand-copied drift
    /// is a construction property, not a runtime assertion).
    func testScalarPanelProvidersRegisterAndRoute() {
        let state = InspectorState()
        state.registerDefaultProviders(defaultFace: true)
        let populated = Set(state.panelOpNames)
        let scalarOps: Set<String> = [
            Cat02WBModule.opName, ContrastModule.opName, WhiteModule.opName,
            BlackModule.opName, TintModule.opName, SaturationModule.opName,
        ]
        XCTAssertTrue(
            scalarOps.isSubset(of: populated),
            "the six scalar panels must populate the provider face")
        // Tone main: contrast/white/black (the Alcedo Tone catalog rows).
        let toneMain = EditorTabRoutingTable.panels(for: .tone)
            .filter { !$0.isAdvancedGroup }.map(\.opName)
        for op in [ContrastModule.opName, WhiteModule.opName, BlackModule.opName] {
            XCTAssertTrue(toneMain.contains(op), "\(op) rides the Tone main face")
        }
        // Look: saturation → Master; cat02WhiteBalance/tint → Color.
        let look = EditorTabRoutingTable.panels(for: .look)
        XCTAssertEqual(
            look.first { $0.opName == SaturationModule.opName }?.group, .master)
        XCTAssertEqual(
            look.first { $0.opName == Cat02WBModule.opName }?.group, .color)
        XCTAssertEqual(look.first { $0.opName == TintModule.opName }?.group, .color)
    }

    func testDisabledSixNamesNeverAppearInTheRoutingTable() {
        let rehomedOps = Set(EditorTabRoutingTable.allRehomedPanels.map(\.opName))
        for disabled in Self.disabledSix {
            XCTAssertFalse(
                rehomedOps.contains(disabled),
                "the disabled op \(disabled) must never rehome (checker E1/D5)")
        }
    }

    func testPageOrderMatchesTheAlcedoSequence() {
        XCTAssertEqual(
            EditorTabRoute.allCases,
            [.tone, .look, .lut, .displayTransform, .geometry, .rawDecode, .mask],
            "the page order == the Alcedo EditorAdjustmentStack sequence")
    }

    func testTextOverlayIsNotInTheTable() {
        let rehomedOps = EditorTabRoutingTable.allRehomedPanels.map(\.opName)
        XCTAssertFalse(
            rehomedOps.contains(TextOverlayModule.opName),
            "textOverlay is the yiyin sheet's carrier — never a table row")
    }

    func testSpecialPageContentSlots() {
        // Display Transform: Vignette row + the DRT placeholder section
        // (checker E1 — NO AgX row anywhere on the page).
        XCTAssertEqual(
            EditorTabRoutingTable.panels(for: .displayTransform).map(\.opName),
            [VignetteModule.opName])
        XCTAssertEqual(
            EditorTabRoutingTable.specialContent(for: .displayTransform),
            .displayTransformPlaceholder)
        // RAW Decode: the T4 CIRAW panel slot (no registry op rehomes).
        XCTAssertTrue(EditorTabRoutingTable.panels(for: .rawDecode).isEmpty)
        XCTAssertEqual(
            EditorTabRoutingTable.specialContent(for: .rawDecode), .rawDecodePanel)
        // Mask: the layers pre-home (no registry op rehomes).
        XCTAssertTrue(EditorTabRoutingTable.panels(for: .mask).isEmpty)
        XCTAssertEqual(
            EditorTabRoutingTable.specialContent(for: .mask), .layersPanel)
        // The plain pages carry no special slot.
        for tab in [EditorTabRoute.tone, .look, .lut, .geometry] {
            XCTAssertEqual(
                EditorTabRoutingTable.specialContent(for: tab), .none,
                "\(tab) is a plain panel page")
        }
    }

    // MARK: - M2-5-2: the Tone convergence (KD-1 / checker m2)

    /// T1 carrier + T3 completion: the Tone main face IS the Alcedo six-row
    /// catalog (exposure/contrast/white/black/the ONE shadhi row/curve).
    func testTonePageConvergedWithCompatGroup() {
        let tone = EditorTabRoutingTable.panels(for: .tone)
        let main = tone.filter { !$0.isAdvancedGroup }
        let compat = tone.filter { $0.isAdvancedGroup }
        // AC#1: the six-row main face in the Alcedo catalog order (the
        // contrast/white/black rows joined with the T3 provider batch).
        XCTAssertEqual(
            main.map(\.opName),
            [
                ExposureModule.opName, ContrastModule.opName,
                WhiteModule.opName, BlackModule.opName,
                ShadhiModule.opName, ToneCurveModule.opName,
            ],
            "the Alcedo Tone main face = the six catalog rows")
        // D5: temperature's main-face removal IS the "Tone −1 row".
        XCTAssertFalse(main.contains { $0.opName == TemperatureModule.opName })
        // D10: the D6-era five stay EDITABLE — the compat fold, not a delete.
        XCTAssertEqual(
            Set(compat.map(\.opName)),
            [
                LevelsModule.opName, ColisaModule.opName,
                ColorContrastModule.opName, ToneEqualModule.opName,
                TemperatureModule.opName,
            ])
        XCTAssertTrue(
            compat.allSatisfy { $0.group == .compat },
            "every compat row carries the compat group (the fold header source)")
        // checker m2: the shadhi op rides EXACTLY ONE row (the two-slider
        // panel is the pair's minimal faithful mapping; the two-row branch
        // is deleted for the `ForEach(id: \.opName)` static-id conflict).
        XCTAssertEqual(tone.filter { $0.opName == ShadhiModule.opName }.count, 1)
    }

    // MARK: - M2-5-2: the Look four-group IA (KD-1 / D9 / checker m1)

    /// T2 regroup + T3 additions: the pre-M2-5-2 13 rows ALL keep a home
    /// (zero loss) and the catalog ops hang with their provider batches.
    /// hls/colorWheels join at T5/T4 — their absence here is the T3 state.
    func testLookPageFourGroupIALedger() {
        let look = EditorTabRoutingTable.panels(for: .look)
        // Zero loss: the 13 pre-M2-5-2 rows, verbatim, still all present.
        let ledger13: Set<String> = [
            VibranceModule.opName, VelviaModule.opName,
            MonochromeModule.opName, ColorBalanceRGBModule.opName,
            ColorZonesModule.opName, SkinSmoothModule.opName,
            SharpenModule.opName, HighpassModule.opName,
            SoftenModule.opName, LocalContrastModule.opName,
            EqualizerModule.opName, GrainModule.opName,
            BloomModule.opName,
        ]
        XCTAssertTrue(
            ledger13.isSubset(of: Set(look.map(\.opName))),
            "every pre-M2-5-2 Look row keeps a home (zero loss)")
        // T3 additions: the catalog order's Saturation (Master) + the Color
        // seat's White Balance (CAT02) / Tint.
        XCTAssertEqual(look.count, 16, "13 ledger + 3 T3 catalog rows")
        XCTAssertEqual(
            look.filter { $0.group == .master }.map(\.opName),
            [SaturationModule.opName, VibranceModule.opName],
            "Master = Saturation / Vibrance (§2.3 order)")
        XCTAssertEqual(
            Set(look.filter { $0.group == .color }.map(\.opName)),
            [Cat02WBModule.opName, TintModule.opName],
            "T3 Color seat: CAT02 WB + Tint; hls/colorWheels join T5/T4")
        // Group membership (KD-1 §2.3 mapping + checker m1's colorzones).
        let group = { (op: String) in look.first { $0.opName == op }?.group }
        let drtSeatOps = [
            EqualizerModule.opName, SharpenModule.opName,
            GrainModule.opName, BloomModule.opName,
        ]
        for op in drtSeatOps {
            XCTAssertEqual(group(op), .look, "\(op) rides the D9 seat")
        }
        let textureOps = [
            VelviaModule.opName, MonochromeModule.opName,
            ColorBalanceRGBModule.opName, ColorZonesModule.opName,
            SkinSmoothModule.opName, HighpassModule.opName,
            SoftenModule.opName, LocalContrastModule.opName,
        ]
        for op in textureOps {
            XCTAssertEqual(
                group(op), .detailTexture,
                "\(op) rides Detail/Texture (m1: colorzones included)")
        }
        // D9: the four DRT-seat rows carry the honest pre-DRT note.
        for op in drtSeatOps {
            XCTAssertEqual(
                look.first { $0.opName == op }?.note, "panel_note_pre_drt",
                "\(op) must carry the pre-DRT note")
        }
        XCTAssertEqual(
            look.filter { $0.note != nil }.count, 4, "exactly the four D9 notes")
        // LUT page: lmt stays (D10 字面) — Look never hosts it.
        XCTAssertFalse(look.contains { $0.opName == Lut3dModule.opName })
        XCTAssertEqual(
            EditorTabRoutingTable.panels(for: .lut).map(\.opName),
            [Lut3dModule.opName])
    }

    func testGeometryAdvancedGroupComposition() {
        let advanced = EditorTabRoutingTable.panels(for: .geometry)
            .filter(\.isAdvancedGroup)
            .map(\.opName)
        // The D6-only items fold into the Advanced group; the Alcedo
        // framing basics stay main.
        XCTAssertEqual(
            Set(advanced),
            [
                AshiftModule.opName, LiquifyModule.opName,
                ChannelMixerRGBModule.opName, ChannelMixerModule.opName,
                DehazeModule.opName,
            ])
        let main = EditorTabRoutingTable.panels(for: .geometry)
            .filter { !$0.isAdvancedGroup }
            .map(\.opName)
        XCTAssertEqual(
            Set(main),
            [CropModule.opName, FlipModule.opName, LensModule.opName])
    }

    // MARK: - The TAB-MATRIX markdown reconciliation (the T2 acceptance)

    /// The repo root (the Fixtures.swift walk).
    private static let repoRoot: String = {
        let testsDir = (#filePath as NSString).deletingLastPathComponent
        return ((testsDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent
    }()

    private var tabMatrixMarkdown: String {
        let url = URL(fileURLWithPath: Self.repoRoot)
            .appendingPathComponent(".work/gsd/phases/m2-3-ui-shell/M2-3-TAB-MATRIX.md")
        return try! String(contentsOf: url, encoding: .utf8)
    }

    func testTabMatrixMatchesTheRoutingTableLineByLine() {
        let markdown = tabMatrixMarkdown
        let rehomed = EditorTabRoutingTable.allRehomedPanels

        // Every rehomed op's backtick-quoted literal appears (page rows and
        // the sheet rows both quote the opName literal).
        for descriptor in rehomed {
            XCTAssertTrue(
                markdown.contains("`\(descriptor.opName)`"),
                "TAB-MATRIX must quote the rehomed op \(descriptor.opName)")
        }
        // Panel-row counts: the main table's opName-quoted rows == the
        // page rows; the sheet section quotes the yiyin pair.
        let pageRows = EditorTabRoute.allCases.flatMap {
            EditorTabRoutingTable.panels(for: $0)
        }
        for descriptor in pageRows {
            XCTAssertTrue(
                markdown.contains("| `\(descriptor.opName)` |"),
                "the page row \(descriptor.opName) rides the main table")
        }
        for descriptor in EditorTabRoutingTable.topBarSheetPanels {
            XCTAssertTrue(
                markdown.contains("| `\(descriptor.opName)` |"),
                "the sheet row \(descriptor.opName) rides the sheet section")
        }
        // The special slots are declared.
        XCTAssertTrue(markdown.contains("arrives with M2-6"), "the DRT slot")
        XCTAssertTrue(markdown.contains("LayersPanelView"), "the Mask pre-home")
        XCTAssertTrue(markdown.contains("CIRAW"), "the RAW Decode slot")
        // The page order line.
        XCTAssertTrue(
            markdown.contains("Tone → Look → LUT → Display Transform → Geometry → RAW Decode → Mask"),
            "the md pins the Alcedo page sequence")
    }

    // MARK: - T1: the tool rail (the three sections + markers)

    func testToolRailSectionsCarryTheT1Markers() {
        let sections = EditorRailSection.allCases
        XCTAssertEqual(sections.map(\.rawValue), ["history", "versions", "nodes"])
        XCTAssertEqual(sections.map(\.marker), [
            "editor.rail.history", "editor.rail.versions", "editor.rail.nodes",
        ])
    }

    func testEditorShellMarkerSurface() {
        // The shell + slot markers (T1 machine-check face, m8's view-level
        // assertions landing with the T2 test batch). Marker segments are
        // the case values verbatim (rawValue-derived).
        XCTAssertEqual(EditorTabRoute.tone.marker, "editor.stack.tab.tone")
        XCTAssertEqual(
            EditorTabRoute.displayTransform.marker,
            "editor.stack.tab.displayTransform")
        XCTAssertEqual(
            EditorTabRoute.allCases.map(\.marker),
            [
                "editor.stack.tab.tone",
                "editor.stack.tab.look",
                "editor.stack.tab.lut",
                "editor.stack.tab.displayTransform",
                "editor.stack.tab.geometry",
                "editor.stack.tab.rawDecode",
                "editor.stack.tab.mask",
            ])
    }

    // MARK: - The disabled-six constant (the M2-1 disable face, quoted once)

    private static let disabledSix: Set<String> = [
        FilmicRGBModule.opName,
        SigmoidModule.opName,
        AgXModule.opName,
        DenoiseProfileModule.opName,
        NLMeansModule.opName,
        BilateralModule.opName,
    ]
}
