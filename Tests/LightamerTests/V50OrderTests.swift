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

    /// The table matches Darktable's v50_order: 93 entries spanning
    /// rawprepare 1.0 → gamma 78.0, first/last locked.
    func testEntriesCountApproximately76() {
        XCTAssertEqual(V50Order.entries.count, 93, "verbatim iop_order.c port = 93 entries")
        XCTAssertEqual(V50Order.entries.first?.opName, "rawprepare")
        XCTAssertEqual(V50Order.entries.first?.order, 1.0)
        XCTAssertEqual(V50Order.entries.last?.opName, "gamma")
        XCTAssertEqual(V50Order.entries.last?.order, 78.0)
    }

    /// No duplicate opName anywhere (lookups are by name); the ONLY position
    /// collision is the deliberate 28.5 cluster — channelmixerrgb / diffuse
    /// / censorize / negadoctor / blurs / primaries share 28.5, and no other
    /// order value repeats.
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
            Set(orderCounts.keys), [28.5],
            "28.5 is the only shared position"
        )
        XCTAssertEqual(
            Set(orderCounts[28.5]!.map(\.opName)), Set(clustered),
            "exactly the six documented modules share 28.5"
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
}
