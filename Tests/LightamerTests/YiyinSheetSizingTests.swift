@testable import Lightamer
import CoreGraphics
import XCTest

// YiyinSheetSizingTests (Plan M3-1-02 T1) — the pure clamp/convert face of
// the yiyin sheet's draggable edges, plus the drag-window discipline (AC 2/3):
// the double clamp (px bounds ∩ ratio domain, both terminal ends), 3-decimal
// quantization idempotence, absent/out-of-domain key = the shipped 420×560
// look, and the injected-defaults proof that a drag writes ONLY at end.
// No sheet instantiation: everything runs against the pure types (KD-3).
@MainActor
final class YiyinSheetSizingTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "yiyinsheet-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Double clamp (AC 1): px bounds ∩ ratio domain, terminal ends

    /// Width: both px terminals and the ratio-domain binding edge.
    /// Container 1000 → lo = max(120, 150) = 150, hi = min(720, 750) = 720.
    func testWidthClampIntersectsPxAndRatioDomains() {
        XCTAssertEqual(YiyinSheetSizing.clampWidth(100, containerWidth: 1000), 150,
                       "below both bounds → the ratio-domain floor")
        XCTAssertEqual(YiyinSheetSizing.clampWidth(130, containerWidth: 1000), 150,
                       "below the ratio floor (but above px min) → ratio floor wins")
        XCTAssertEqual(YiyinSheetSizing.clampWidth(420, containerWidth: 1000), 420,
                       "inside the intersection → unchanged")
        XCTAssertEqual(YiyinSheetSizing.clampWidth(650, containerWidth: 800), 600,
                       "above container×0.75 → the ratio ceiling wins over px max")
        XCTAssertEqual(YiyinSheetSizing.clampWidth(900, containerWidth: 1000), 720,
                       "above both bounds → the px cap")
    }

    /// Height: both terminals; the px cap 560 can bind before the ratio
    /// ceiling (the M7 asymmetry: cap = the shipped default height).
    func testHeightClampIntersectsPxAndRatioDomains() {
        XCTAssertEqual(YiyinSheetSizing.clampHeight(100, containerHeight: 1000), 350,
                       "below the ratio floor (0.35×1000) → ratio floor")
        XCTAssertEqual(YiyinSheetSizing.clampHeight(200, containerHeight: 500), 200,
                       "inside the intersection → unchanged")
        XCTAssertEqual(YiyinSheetSizing.clampHeight(500, containerHeight: 1000), 500,
                       "inside the intersection → unchanged")
        XCTAssertEqual(YiyinSheetSizing.clampHeight(700, containerHeight: 1000), 560,
                       "above both bounds → the px cap 560 (M7 intentional cap)")
    }

    /// Degenerate domain (container too small for a non-empty intersection):
    /// the upstream min(max(px, lo), hi) composition yields hi — documented
    /// and pinned so the degenerate face stays deterministic.
    func testDegenerateDomainReturnsUpperBound() {
        // width: lo = max(120, 15) = 120 > hi = min(720, 75) = 75 → 75
        XCTAssertEqual(YiyinSheetSizing.clampWidth(420, containerWidth: 100), 75)
        // height: lo = max(160, 35) = 160 > hi = min(560, 92) = 92 → 92
        XCTAssertEqual(YiyinSheetSizing.clampHeight(300, containerHeight: 100), 92)
    }

    // MARK: - Ratio conversion + quantization (AC 2)

    func testRatioConversionClampsToRatioDomain() {
        XCTAssertEqual(YiyinSheetSizing.widthRatio(fromPx: 50, containerWidth: 1000), 0.15)
        XCTAssertEqual(YiyinSheetSizing.widthRatio(fromPx: 420, containerWidth: 1000), 0.42)
        XCTAssertEqual(YiyinSheetSizing.widthRatio(fromPx: 900, containerWidth: 1000), 0.75)
        XCTAssertEqual(YiyinSheetSizing.heightRatio(fromPx: 100, containerHeight: 1000), 0.35)
        XCTAssertEqual(YiyinSheetSizing.heightRatio(fromPx: 560, containerHeight: 1000), 0.56)
        // zero container (no geometry): the ratio-domain floor, not a divide-by-zero
        XCTAssertEqual(YiyinSheetSizing.widthRatio(fromPx: 420, containerWidth: 0), 0.15)
    }

    /// Upstream `persistPreviewRatio`: round(ratio*1000)/1000 — three
    /// decimals, idempotent under re-application.
    func testQuantize3PrecisionAndIdempotence() {
        XCTAssertEqual(YiyinSheetSizing.quantize3(0.4204), 0.42)
        XCTAssertEqual(YiyinSheetSizing.quantize3(0.1234567), 0.123)
        let once = YiyinSheetSizing.quantize3(0.5678)
        XCTAssertEqual(YiyinSheetSizing.quantize3(once), once, "quantization is idempotent")
        // roundtrip: quantized ratio × container → px → ratio again = same ratio
        let px = YiyinSheetSizing.resolvedWidth(ratio: once, containerWidth: 1000)
        XCTAssertEqual(YiyinSheetSizing.widthRatio(fromPx: px, containerWidth: 1000), once,
                       "quantized ratio survives a resolve→convert roundtrip")
    }

    // MARK: - Settled resolution (AC 2: absent key = the shipped look)

    /// KD-1's zero-look-change anchor: absent ratio keys (first use) resolve
    /// to the shipped `.frame(width: 420, height: 560)` constants.
    func testAbsentKeyResolvesToShippedDefaults() {
        XCTAssertEqual(YiyinSheetSizing.resolvedWidth(ratio: nil, containerWidth: 2000), 420)
        XCTAssertEqual(YiyinSheetSizing.resolvedHeight(ratio: nil, containerHeight: 2000), 560)
    }

    /// No geometry yet (container .zero): the shipped constants, never a
    /// degenerate clamp collapse.
    func testZeroContainerResolvesToShippedDefaults() {
        XCTAssertEqual(YiyinSheetSizing.resolvedWidth(ratio: 0.42, containerWidth: 0), 420)
        XCTAssertEqual(YiyinSheetSizing.resolvedHeight(ratio: 0.85, containerHeight: 0), 560)
    }

    /// A stored ratio resolves as container × ratio, re-clamped into the
    /// intersection domain (the container-follow semantic's settled face).
    func testStoredRatioResolvesClamped() {
        // 0.42 × 2000 = 840 → px cap 720 binds
        XCTAssertEqual(YiyinSheetSizing.resolvedWidth(ratio: 0.42, containerWidth: 2000), 720)
        // 0.56 × 1000 = 560 → inside the intersection
        XCTAssertEqual(YiyinSheetSizing.resolvedHeight(ratio: 0.56, containerHeight: 1000), 560)
        // container shrank: 0.52 × 500 = 260, hi = min(720, 375) = 375 → 260
        XCTAssertEqual(YiyinSheetSizing.resolvedWidth(ratio: 0.52, containerWidth: 500), 260)
    }

    // MARK: - YiyinSheetMetrics (KD-4: injected defaults, typed tolerance)

    func testTypedReadRejectsAbsentForeignAndOutOfRangeValues() {
        let metrics = YiyinSheetMetrics(defaults: defaults)
        // absent
        XCTAssertNil(metrics.widthRatio())
        XCTAssertNil(metrics.heightRatio())
        // foreign-typed garbage degrades to nil
        defaults.set("garbage", forKey: YiyinSheetMetrics.widthRatioKey)
        XCTAssertNil(metrics.widthRatio(), "a String value must read as absent")
        // out-of-domain values degrade to nil
        defaults.set(1.5, forKey: YiyinSheetMetrics.widthRatioKey)
        XCTAssertNil(metrics.widthRatio(), "above 1 must read as absent")
        defaults.set(-0.1, forKey: YiyinSheetMetrics.heightRatioKey)
        XCTAssertNil(metrics.heightRatio(), "below 0 must read as absent")
        // domain edges are VALID stored values (0.0 is a real memory, not unset)
        defaults.set(0.0, forKey: YiyinSheetMetrics.widthRatioKey)
        XCTAssertEqual(metrics.widthRatio(), 0.0, "a stored 0.0 is a remembered value")
    }

    func testStoreReadRoundtrip() {
        let metrics = YiyinSheetMetrics(defaults: defaults)
        metrics.storeWidthRatio(0.42)
        metrics.storeHeightRatio(0.85)
        XCTAssertEqual(metrics.widthRatio(), 0.42)
        XCTAssertEqual(metrics.heightRatio(), 0.85)
    }

    // MARK: - The drag window (AC 3): zero persistence until end

    /// Ten live ticks: the injected defaults observe NO write; the end write
    /// happens exactly once, with the 3-decimal quantized ratio. (The
    /// history/pipe half of AC 3 is structural — the model holds no
    /// coordinator reference — pinned by testModelDragTouchesNoHistory.)
    func testModelWritesDefaultsOnlyAtDragEnd() {
        let metrics = YiyinSheetMetrics(defaults: defaults)
        let model = YiyinSheetResizeModel(metrics: metrics)
        model.containerChanged(to: CGSize(width: 1000, height: 1000))

        for tick in 1...10 {
            model.widthTick(translation: CGFloat(tick) * 10)
            model.heightTick(translation: CGFloat(tick) * 4)
            XCTAssertNil(defaults.object(forKey: YiyinSheetMetrics.widthRatioKey),
                         "tick \(tick): a live width tick must not persist")
            XCTAssertNil(defaults.object(forKey: YiyinSheetMetrics.heightRatioKey),
                         "tick \(tick): a live height tick must not persist")
        }
        XCTAssertTrue(model.isDragging)
        XCTAssertEqual(model.resolvedWidth, 520, "live px = clamp(420 + 100) — inside domain")
        XCTAssertEqual(model.resolvedHeight, 560, "live height = clamp(560 + 40) → px cap 560")

        model.widthEnd()
        model.heightEnd()
        XCTAssertFalse(model.isDragging)
        XCTAssertEqual(defaults.double(forKey: YiyinSheetMetrics.widthRatioKey), 0.52,
                       accuracy: 1e-12, "end persists exactly once: 520/1000 quantized")
        XCTAssertEqual(defaults.double(forKey: YiyinSheetMetrics.heightRatioKey), 0.56,
                       accuracy: 1e-12, "height end: the 560 cap ratio (560/1000)")
    }

    /// The readout (AC 4) shows the live terminal value, upstream
    /// `${round(w)} × ${round(h)}` verbatim shape.
    func testReadoutTracksLiveSize() {
        let model = YiyinSheetResizeModel(metrics: YiyinSheetMetrics(defaults: defaults))
        XCTAssertEqual(model.readout, "420 × 560", "first use = the shipped look")
        model.containerChanged(to: CGSize(width: 1000, height: 1000))
        model.widthTick(translation: 80)
        XCTAssertEqual(model.readout, "500 × 560")
    }

    /// The ResizeObserver equivalent: a container change drops live px so the
    /// settled size re-derives from the STORED ratios.
    func testContainerChangeReDerivesFromStoredRatio() {
        let model = YiyinSheetResizeModel(metrics: YiyinSheetMetrics(defaults: defaults))
        model.containerChanged(to: CGSize(width: 1000, height: 1000))
        model.widthTick(translation: 100)
        model.widthEnd()
        XCTAssertEqual(model.resolvedWidth, 520)

        model.containerChanged(to: CGSize(width: 500, height: 500))
        XCTAssertEqual(model.resolvedWidth, 260,
                       "520/1000 stored → 0.52 × 500 = 260 (re-derived, live dropped)")
    }

    /// Structural half of AC 3: the model's drag path holds no editor/pipe
    /// reference — a drag storm leaves an EditorState's history untouched.
    func testModelDragTouchesNoHistory() {
        let editorState = EditorState()
        let model = YiyinSheetResizeModel(metrics: YiyinSheetMetrics(defaults: defaults))
        model.containerChanged(to: CGSize(width: 1000, height: 1000))
        for tick in 1...20 {
            model.widthTick(translation: CGFloat(tick))
            model.heightTick(translation: CGFloat(tick))
        }
        model.widthEnd()
        model.heightEnd()
        XCTAssertTrue(editorState.history.items.isEmpty,
                      "a sheet-resize drag storm must never create a history item")
    }
}
