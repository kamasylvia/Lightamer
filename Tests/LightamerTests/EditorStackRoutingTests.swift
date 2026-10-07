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
        // The executed cardinality (DECISIONS D3): 34 populated − 1 = 33.
        XCTAssertEqual(expected.count, 33)
        XCTAssertEqual(rehomedOps.count, 33)
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
