import LightamerCore
import LightamerIOP
import XCTest

/// FOUND-03 structure tests for the `V50Order` table (the verbatim port of
/// Darktable `iop_order.c:298-415`).
///
/// Note: the table ports to **93 entries** — the plan's "~76" estimate
/// undercounted; the verbatim source wins (recorded in 01-04-SUMMARY and
/// the executor protocol), so the count test asserts the source count.
final class V50OrderTests: XCTestCase {

    /// The table matches Darktable's v50_order + the Lightamer-native
    /// rows: 107 entries spanning rawprepare 1.0 → gamma 78.0, first/last
    /// locked (07-2: 93 → 94 with the skinSmooth 66.5 insertion — the first
    /// non-dt row; 08-5: 94 → 95 with the textOverlay 66.7 insertion — the
    /// second; M2-5-1: 95 → 105 with the ten grade rows — the acesccIn/Out
    /// envelope pair + the eight catalog ops; M3-3-02: 105 → 106 with
    /// filmPlacement 20.8 — the placement curve row; M5-1-01: 106 → 107
    /// with colormatch 36.5 — the TRACK color-transfer row; all flagged in
    /// the table at the rows).
    func testEntriesCountApproximately76() {
        XCTAssertEqual(V50Order.entries.count, 107, "93 dt-verbatim + skinSmooth + textOverlay + 10 M2-5-1 grade rows + filmPlacement + colormatch")
        XCTAssertEqual(V50Order.entries.first?.opName, "rawprepare")
        XCTAssertEqual(V50Order.entries.first?.order, 1.0)
        XCTAssertEqual(V50Order.entries.last?.opName, "gamma")
        XCTAssertEqual(V50Order.entries.last?.order, 78.0)
    }

    /// No duplicate opName anywhere (lookups are by name); the position
    /// collisions are exactly the TWO declared clusters — the deliberate
    /// 28.5 cluster (channelmixerrgb / diffuse / censorize / negadoctor /
    /// blurs / primaries) and, since M2-5-1, the 41.0 pair where the
    /// Lightamer-native colorWheels shares the slot with the UNREGISTERED
    /// dt colorbalance row (the declared exception, M2-5-1-DECISIONS).
    func testNoDuplicateOpNameExceptDeliberateCollisions() {
        let names = V50Order.entries.map(\.opName)
        XCTAssertEqual(Set(names).count, names.count, "every opName unique")

        let clustered = ["channelmixerrgb", "diffuse", "censorize", "negadoctor", "blurs", "primaries"]
        for name in clustered {
            XCTAssertEqual(V50Order.order(for: name), 28.5, "\(name) sits in the 28.5 cluster")
        }

        let orderCounts = Dictionary(grouping: V50Order.entries, by: \.order)
            .filter { $0.value.count > 1 }
        XCTAssertEqual(
            Set(orderCounts.keys), [28.5, 41.0],
            "28.5 (dt cluster) and 41.0 (colorWheels↔colorbalance, M2-5-1 declared) are the only shared positions"
        )
        XCTAssertEqual(
            Set(orderCounts[28.5]!.map(\.opName)), Set(clustered),
            "exactly the six documented modules share 28.5"
        )
        XCTAssertEqual(
            Set(orderCounts[41.0]!.map(\.opName)), ["colorbalance", "colorWheels"],
            "colorWheels shares 41.0 with the unregistered dt colorbalance row"
        )
    }

    /// Canonical milestone lookups + nil for unknown opNames (incl. the
    /// Phase 1 spike module, which deliberately has no V50Order slot).
    func testOrderForKnownModules() {
        XCTAssertEqual(V50Order.order(for: "rawprepare"), 1.0)
        XCTAssertEqual(V50Order.order(for: "demosaic"), 8.0)
        XCTAssertEqual(V50Order.order(for: "exposure"), 21.0)
        XCTAssertEqual(V50Order.order(for: "colorin"), 28.0)
        XCTAssertEqual(V50Order.order(for: "colorout"), 70.0)
        XCTAssertEqual(V50Order.order(for: "gamma"), 78.0)
        XCTAssertNil(V50Order.order(for: "does_not_exist"))
        XCTAssertNil(V50Order.order(for: "passthrough_spike"), "spike module has no slot")
    }

    /// Plan 06-06-T2: liquify's warp-slot neighborhood — clipping 17.0 <
    /// liquify 18.0 < spots 19.0 < retouch 20.0 < exposure 21.0 (the module
    /// statics AND the table agree).
    func testLiquifySlotNeighborhood() {
        XCTAssertEqual(V50Order.order(for: "liquify"), 18.0)
        XCTAssertEqual(V50Order.order(for: "clipping"), 17.0)
        XCTAssertEqual(V50Order.order(for: "spots"), 19.0)
        XCTAssertEqual(V50Order.order(for: "retouch"), 20.0)
        XCTAssertEqual(V50Order.order(for: "exposure"), 21.0)
        XCTAssertLessThan(V50Order.order(for: "liquify")!, V50Order.order(for: "spots")!)
        XCTAssertLessThan(V50Order.order(for: "spots")!, V50Order.order(for: "retouch")!)
        XCTAssertLessThan(V50Order.order(for: "retouch")!, V50Order.order(for: "exposure")!)
        XCTAssertEqual(LiquifyModule.iopOrder, 18.0)
        XCTAssertGreaterThan(LiquifyModule.iopOrder, 17.0)
        XCTAssertLessThan(LiquifyModule.iopOrder, 19.0)
    }

    /// 04-02: the flip-before-crop hard constraint (`iop_order.c:810-812`
    /// "crop GUI broken if flip is done on top") — mechanism: the module
    /// statics AND the table agree, so the default chain sorts flip first.
    func testFlipBeforeCropOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "flip"), 16.0)
        XCTAssertEqual(V50Order.order(for: "crop"), 24.5)
        XCTAssertLessThan(V50Order.order(for: "flip")!, V50Order.order(for: "crop")!)
        XCTAssertEqual(FlipModule.iopOrder, 16.0)
        XCTAssertEqual(CropModule.iopOrder, 24.5)
        XCTAssertLessThan(FlipModule.iopOrder, CropModule.iopOrder)
    }

    /// 04-04: lens (13.0) sits after scalepixels (12.0), before
    /// cacorrectrgb (13.5, whose source comment orders CA-after-lens) —
    /// mechanism: the module statics AND the table agree.
    func testLensSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "lens"), 13.0)
        XCTAssertEqual(V50Order.order(for: "cacorrectrgb"), 13.5)
        XCTAssertLessThan(V50Order.order(for: "lens")!, V50Order.order(for: "cacorrectrgb")!)
        XCTAssertEqual(LensModule.iopOrder, 13.0)
        XCTAssertLessThan(LensModule.iopOrder, AshiftModule.iopOrder)
        XCTAssertLessThan(AshiftModule.iopOrder, FlipModule.iopOrder)
        XCTAssertLessThan(FlipModule.iopOrder, CropModule.iopOrder)
    }
    /// 04-05: detail five slots — equalizer 27.0 < highpass 34.0 <
    /// sharpen 35.0 < bilat 54.0 < soften 66.0; module statics AND the
    /// table agree, so the default chain sorts them structurally.
    func testDetailSlotOrderConstraints() {
        XCTAssertEqual(V50Order.order(for: "equalizer"), 27.0)
        XCTAssertEqual(V50Order.order(for: "highpass"), 34.0)
        XCTAssertEqual(V50Order.order(for: "sharpen"), 35.0)
        XCTAssertEqual(V50Order.order(for: "bilat"), 54.0)
        XCTAssertEqual(V50Order.order(for: "soften"), 66.0)
        XCTAssertEqual(EqualizerModule.iopOrder, 27.0)
        XCTAssertEqual(HighpassModule.iopOrder, 34.0)
        XCTAssertEqual(SharpenModule.iopOrder, 35.0)
        XCTAssertEqual(LocalContrastModule.iopOrder, 54.0)
        XCTAssertEqual(SoftenModule.iopOrder, 66.0)
        XCTAssertLessThan(EqualizerModule.iopOrder, ColorInModule.iopOrder)
        XCTAssertLessThan(HighpassModule.iopOrder, SharpenModule.iopOrder)
        XCTAssertLessThan(SharpenModule.iopOrder, LocalContrastModule.iopOrder)
        XCTAssertLessThan(LocalContrastModule.iopOrder, SoftenModule.iopOrder)
    }

    /// 05-02: colorbalancergb 41.5 — after colorbalance (41.0), before
    /// rgbcurve (42.0); module statics AND the table agree.
    func testColorBalanceRGBSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "colorbalancergb"), 41.5)
        XCTAssertEqual(ColorBalanceRGBModule.iopOrder, 41.5)
        XCTAssertLessThan(V50Order.order(for: "colorbalance")!, V50Order.order(for: "colorbalancergb")!)
        XCTAssertLessThan(V50Order.order(for: "colorbalancergb")!, V50Order.order(for: "rgbcurve")!)
    }

    /// 05-03: channelmixerrgb 28.5 — immediately after colorin (28.0),
    /// before nlmeans (29.0); module statics AND the table agree. The 28.5
    /// cluster tie-break is covered by SidecarTieBreakTests.
    func testChannelMixerRGBSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "channelmixerrgb"), 28.5)
        XCTAssertEqual(ChannelMixerRGBModule.iopOrder, 28.5)
        XCTAssertLessThan(V50Order.order(for: "colorin")!, V50Order.order(for: "channelmixerrgb")!)
        XCTAssertLessThan(V50Order.order(for: "channelmixerrgb")!, V50Order.order(for: "nlmeans")!)
    }

    /// 05-06: nlmeans 29.0 — immediately after colorin (28.0; Lab needs
    /// calibrated color, iop_order.c note), before colorchecker (30.0);
    /// module statics AND the table agree.
    func testNLMeansSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "nlmeans"), 29.0)
        XCTAssertEqual(NLMeansModule.iopOrder, 29.0)
        XCTAssertLessThan(V50Order.order(for: "colorin")!, V50Order.order(for: "nlmeans")!)
        XCTAssertLessThan(V50Order.order(for: "nlmeans")!, V50Order.order(for: "colorchecker")!)
    }

    /// 05-04: velvia 57.0 → vibrance 58.0 → colorzones 60.0; module statics
    /// AND the table agree.
    func testVelviaVibranceColorZonesSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "velvia"), 57.0)
        XCTAssertEqual(VelviaModule.iopOrder, 57.0)
        XCTAssertEqual(V50Order.order(for: "vibrance"), 58.0)
        XCTAssertEqual(VibranceModule.iopOrder, 58.0)
        XCTAssertLessThan(V50Order.order(for: "colorcontrast")!, V50Order.order(for: "velvia")!)
        XCTAssertLessThan(V50Order.order(for: "velvia")!, V50Order.order(for: "vibrance")!)
    }

    /// 05-08: bilateral 10.0 — after denoiseprofile (9.0, the first
    /// post-demosaic RGB slot), before exposure-era slots; module statics
    /// AND the table agree.
    func testBilateralSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "bilateral"), 10.0)
        XCTAssertEqual(BilateralModule.iopOrder, 10.0)
        XCTAssertLessThan(V50Order.order(for: "denoiseprofile")!, V50Order.order(for: "bilateral")!)
        XCTAssertLessThan(V50Order.order(for: "bilateral")!, V50Order.order(for: "exposure")!)
    }

    /// 07-2: skinSmooth 66.5 — the FIRST (and only) Lightamer-native row
    /// in the otherwise dt-verbatim table (D-07-CONTEXT-2). It sits in the
    /// blur/creative neighborhood — after soften (66.0), before splittoning
    /// (67.0); module statics AND the table agree; the position is unique
    /// (the 28.5 cluster stays the ONLY shared position — asserted above).
    func testSkinSmoothSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "skinSmooth"), 66.5)
        XCTAssertEqual(SkinSmoothModule.iopOrder, 66.5)
        XCTAssertLessThan(V50Order.order(for: "soften")!, V50Order.order(for: "skinSmooth")!)
        XCTAssertLessThan(V50Order.order(for: "skinSmooth")!, V50Order.order(for: "splittoning")!)
        XCTAssertEqual(SkinSmoothModule.opName, "skinSmooth")
        // The dt-verbatim discipline holds for the native row too: no
        // OTHER entry shares 66.5 (uniqueness — covered structurally by
        // testNoDuplicateOpNameExceptDeliberateCollisions, pinned here at
        // the value level for the audit trail).
        XCTAssertEqual(
            V50Order.entries.filter { $0.order == 66.5 }.count, 1,
            "66.5 is a unique position")
    }

    /// 08-5: textOverlay 66.7 — the SECOND Lightamer-native row (the
    /// 66.5–67.0 gap; D-08-CONTEXT-9): module statics AND the table agree;
    /// the position is unique; the 70.0 floor relation (layer-mask
    /// eligibility) and the yiyin watermark 77.0 division both hold.
    func testTextOverlaySlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "textOverlay"), 66.7)
        XCTAssertEqual(TextOverlayModule.iopOrder, 66.7)
        XCTAssertEqual(TextOverlayModule.opName, "textOverlay")
        XCTAssertLessThan(V50Order.order(for: "skinSmooth")!, V50Order.order(for: "textOverlay")!)
        XCTAssertLessThan(V50Order.order(for: "textOverlay")!, V50Order.order(for: "splittoning")!)
        // The layer-mask eligibility floor + the yiyin division.
        XCTAssertLessThan(66.7, 70.0, "textOverlay must sit BELOW the terminal tail floor")
        XCTAssertLessThan(
            V50Order.order(for: "textOverlay")!, V50Order.order(for: "watermark")!,
            "the editing text layer (66.7) vs the final-output watermark (77.0)")
        XCTAssertEqual(
            V50Order.entries.filter { $0.order == 66.7 }.count, 1,
            "66.7 is a unique position")
    }

    /// M3-3-02: filmPlacement 20.8 — the THIRD edit-window native row (the
    /// placement curve, KD-5): module statics AND the table agree; it sits
    /// BETWEEN acesccIn (20.5) and exposure (21.0) — the first grade-domain
    /// mapping, inside the envelope; the position is unique.
    func testFilmPlacementSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "filmPlacement"), 20.8)
        XCTAssertEqual(FilmPlacementModule.iopOrder, 20.8)
        XCTAssertEqual(FilmPlacementModule.opName, "filmPlacement")
        XCTAssertLessThan(V50Order.order(for: "acesccIn")!, V50Order.order(for: "filmPlacement")!)
        XCTAssertLessThan(V50Order.order(for: "filmPlacement")!, V50Order.order(for: "exposure")!)
        XCTAssertEqual(
            V50Order.entries.filter { $0.order == 20.8 }.count, 1,
            "20.8 is a unique position")
    }

    /// M5-1-01: colormatch 36.5 — the FOURTH edit-window native row (the
    /// TRACK color-transfer linear arm, KD-5): module statics AND the table
    /// agree; it sits BETWEEN lut3d (36.0) and the dt-verbatim (unregistered)
    /// colortransfer (37.0) — lut3d's creative neighborhood; the position is
    /// unique; the 70.0 floor relation (layer-mask legality) holds.
    func testColormatchSlotOrderConstraint() {
        XCTAssertEqual(V50Order.order(for: "colormatch"), 36.5)
        XCTAssertEqual(ColormatchModule.iopOrder, 36.5)
        XCTAssertEqual(ColormatchModule.opName, "colormatch")
        XCTAssertLessThan(V50Order.order(for: "lut3d")!, V50Order.order(for: "colormatch")!)
        XCTAssertLessThan(V50Order.order(for: "colormatch")!, V50Order.order(for: "colortransfer")!)
        XCTAssertLessThan(36.5, 70.0, "colormatch must sit BELOW the terminal tail floor")
        XCTAssertEqual(
            V50Order.entries.filter { $0.order == 36.5 }.count, 1,
            "36.5 is a unique position")
        // The dt rows stay verbatim and unregistered (the port's
        // placeholders — the modules themselves are not ported).
        XCTAssertEqual(V50Order.order(for: "colortransfer"), 37.0)
        XCTAssertEqual(V50Order.order(for: "colormapping"), 38.0)
    }

    /// 07-2 zero-move pin: the 66.5 insertion moved NO dt-verbatim row —
    /// the 93 original entries appear in the same relative order with the
    /// same values (an add-only insertion between soften and splittoning).
    /// 08-5 extends the pin: textOverlay is the second add-only row, and
    /// stripping BOTH native rows yields the 93-entry verbatim sequence.
    func testSkinSmoothInsertionMovesNoVerbatimRow() {
        // The dt-verbatim neighborhood, value-pinned on both sides of the
        // insertion point (iop_order.c:298-415 order).
        let neighborhood: [(String, Float)] = [
            ("grain", 65.0), ("soften", 66.0), ("skinSmooth", 66.5),
            ("textOverlay", 66.7), ("splittoning", 67.0), ("vignette", 68.0),
        ]
        let inTable = V50Order.entries.filter { entry in
            neighborhood.contains { $0.0 == entry.opName }
        }
        XCTAssertEqual(inTable.map(\.opName), neighborhood.map(\.0))
        XCTAssertEqual(inTable.map(\.order), neighborhood.map(\.1))

        // Whole-table relative order: stripping ALL native rows (07-2's
        // skinSmooth, 08-5's textOverlay, M2-5-1's ten grade rows, M3-3-02's
        // filmPlacement, M5-1-01's colormatch) must yield the pre-07-2
        // sequence back (spot anchors on both ends).
        let nativeRows: Set<String> = [
            "skinSmooth", "textOverlay",
            "acesccIn", "acesccOut", "colorWheels", "cat02WhiteBalance",
            "contrast", "white", "black", "saturation", "tint", "hls",
            "filmPlacement", "colormatch",
        ]
        let stripped = V50Order.entries.filter { !nativeRows.contains($0.opName) }
        XCTAssertEqual(stripped.count, 93)
        XCTAssertEqual(stripped.first?.opName, "rawprepare")
        XCTAssertEqual(stripped.last?.opName, "gamma")
        // Listing-order anchor: lut3d stays out of numeric order at its
        // source position (between filmicrgb and colisa) — verbatim port
        // signature the insertion must not disturb.
        let names = V50Order.entries.map(\.opName)
        let filmic = names.firstIndex(of: "filmicrgb")!
        let lut3d = names.firstIndex(of: "lut3d")!
        let colisa = names.firstIndex(of: "colisa")!
        XCTAssertLessThan(filmic, lut3d)
        XCTAssertLessThan(lut3d, colisa)
    }
}
