@testable import LightamerCore
@testable import LightamerIOP
@testable import Lightamer
import Metal
import XCTest

/// CropToolRotationTests (Plan M9-3-T3) — the crop-tool rotate/straighten
/// orchestration: the linked-change atomic batch, the linked-refit
/// predicate (#742/#1388/#1794), the 90° bit↔direction probes, and the
/// Constrain-Crop shrink.
///
/// ANTI-VACUUM / HAND VALUES:
/// - the batch face: TWO history items in commit order (angle first, crop
///   last); undo walks them LIFO — the FIRST undo reverts the CROP refit,
///   the second reverts the angle (the D-M9G-1 registered order). The
///   one-notification face (zero intermediate renders) is the recordLinked
///   implementation's single-Task construction (no spy surface on the
///   final coordinator; the undo order + the atomic two-item landing are
///   the machine-checked face of that ruling).
/// - the span hand value: a 600×400 frame at 30° spans floor(600·cos30 +
///   400·sin30) × floor(600·sin30 + 400·cos30) = floor(719.6) ×
///   floor(646.4) = 719 × 646 (the ashift AABB shape).
/// - the 90° probes: `.rotCW90`'s forward map sends the TOP-RIGHT input
///   pixel to the BOTTOM-RIGHT output pixel — visually clockwise; and an
///   explicit bit SURVIVES EXIF resolution changes (the D-M9G-6
///   persistence face, `resolved(forEXIF:)` non-auto passthrough).
@MainActor
final class CropToolRotationTests: XCTestCase {

    private var editorState: EditorState!
    private var ashift: ModuleInstance?
    private var crop: ModuleInstance?
    private var flip: ModuleInstance?

    override func setUp() {
        super.setUp()
        editorState = EditorState()
        let seed = [
            ModuleInstance(module: AshiftModule.self, params: AshiftModule.Params()),
            ModuleInstance(module: FlipModule.self, params: FlipModule.Params(orientation: .none)),
            ModuleInstance(module: CropModule.self, params: CropModule.Params()),
        ]
        editorState.resetHistoryForNewImage(defaultInstances: seed)
        ashift = editorState.instances.first { $0.opName == AshiftModule.opName }
        crop = editorState.instances.first { $0.opName == CropModule.opName }
        flip = editorState.instances.first { $0.opName == FlipModule.opName }
    }

    // MARK: - the frame bridge hand value

    func testRotatedFrameSpanHandValue() {
        let span = CropToolRotation.RotatedFrameBridge.span(w0: 600, h0: 400, angleDegrees: 30)
        XCTAssertEqual(span.x, 719, accuracy: 0.5, "floor(600·cos30 + 400·sin30)")
        XCTAssertEqual(span.y, 646, accuracy: 0.5, "floor(600·sin30 + 400·cos30)")
        // angle 0 spans exactly the frame
        let zero = CropToolRotation.RotatedFrameBridge.span(w0: 600, h0: 400, angleDegrees: 0)
        XCTAssertEqual(zero.x, 600, accuracy: 0.5)
        XCTAssertEqual(zero.y, 400, accuracy: 0.5)
        // the bridge round-trips: crop fractions ↔ rotated-frame normalization
        let span30 = SIMD2(719.0, 646.0)
        let original = CropFitAngle.Rect(x0: 0.1, y0: 0.2, x1: 0.9, y1: 0.8)
        let rotated = CropToolRotation.RotatedFrameBridge.cropToRotated(original, span: span30, w0: 600, h0: 400)
        let back = CropToolRotation.RotatedFrameBridge.rotatedToCrop(rotated, span: span30, w0: 600, h0: 400)
        XCTAssertEqual(back.x0, original.x0, accuracy: 1e-12)
        XCTAssertEqual(back.y1, original.y1, accuracy: 1e-12)
    }

    // MARK: - the atomic batch + the linked-refit predicate

    func testLinkedBatchAtomicityAndUndoOrder() throws {
        let frame = SIMD2(600.0, 400.0)

        // (a) the full-frame crop + a 10° turn: the batch carries BOTH
        // items (angle first, crop last — the largest frame refits).
        let batch = CropToolRotation.linkedSnapshots(
            ashift: ashift, crop: crop, rotationDegrees: 10, frameSize: frame)
        XCTAssertNotNil(batch)
        let items = try XCTUnwrap(batch)
        XCTAssertEqual(items.count, 2, "the largest frame refits: two items")
        XCTAssertEqual(items[0].opName, AshiftModule.opName, "angle first (commit order)")
        XCTAssertEqual(items[1].opName, CropModule.opName, "crop last (commit order)")
        let angleAfter = try items[0].params(of: AshiftModule.self).rotation
        XCTAssertEqual(Double(angleAfter), 10, accuracy: 1e-6)

        // (b) landing through the EditorState face: exactly TWO history
        // items; the live set carries both.
        editorState.recordLinkedChanges(items, label: "history_rotate")
        XCTAssertEqual(editorState.history.items.count, 2, "the batch lands atomically")
        let liveAshift = try XCTUnwrap(
            editorState.instances.first { $0.opName == AshiftModule.opName })
        XCTAssertEqual(try liveAshift.params(of: AshiftModule.self).rotation, 10, accuracy: 1e-6)

        // (c) undo walks LIFO: the FIRST undo reverts the CROP refit (the
        // angle still 10), the SECOND reverts the angle.
        XCTAssertTrue(editorState.performUndo())
        let afterFirstUndo = try XCTUnwrap(
            editorState.instances.first { $0.opName == AshiftModule.opName })
        XCTAssertEqual(Double(try afterFirstUndo.params(of: AshiftModule.self).rotation), 10,
            accuracy: 1e-6, "the first undo leaves the ANGLE (it reverts the crop)")
        let cropAfterFirstUndo = try XCTUnwrap(
            editorState.instances.first { $0.opName == CropModule.opName })
        let cropParamsAfter = try cropAfterFirstUndo.params(of: CropModule.self)
        // the refit SHRANK the largest frame at 10°: undo restores full frame
        XCTAssertEqual(cropParamsAfter.left, 0, accuracy: 1e-9)
        XCTAssertEqual(cropParamsAfter.right, 1, accuracy: 1e-9)
        XCTAssertTrue(editorState.performUndo())
        let afterSecondUndo = try XCTUnwrap(
            editorState.instances.first { $0.opName == AshiftModule.opName })
        XCTAssertEqual(Double(try afterSecondUndo.params(of: AshiftModule.self).rotation), 0,
            accuracy: 1e-6, "the second undo reverts the angle")
    }

    func testLinkedRefitPredicateThreeBranches() throws {
        let frame = SIMD2(600.0, 400.0)

        // #1794 branch ①: a HAND-ADJUSTED small frame that still fits →
        // NO crop item (the predicate never touches it).
        var handCrop = CropModule.Params()
        handCrop.left = 0.3; handCrop.top = 0.3; handCrop.right = 0.7; handCrop.bottom = 0.7
        var handRecord = try XCTUnwrap(crop)
        try handRecord.setParams(handCrop, as: CropModule.self)
        let keepBatch = CropToolRotation.linkedSnapshots(
            ashift: ashift, crop: handRecord, rotationDegrees: 5, frameSize: frame)
        XCTAssertEqual(keepBatch?.count, 1, "a still-fitting hand frame is untouched")
        XCTAssertEqual(keepBatch?.first?.opName, AshiftModule.opName)

        // #1794 branch ②: a hand frame that NO LONGER fits at 40° shrinks
        // about its own centre, aspect kept (the batch carries both items).
        // The probe frame: (0.1..0.95)×(0.15..0.9) of 600×400 — its top-right
        // corner genuinely leaves the rotated frame at 40°.
        var bigCrop = CropModule.Params()
        bigCrop.left = 0.1; bigCrop.top = 0.15; bigCrop.right = 0.95; bigCrop.bottom = 0.9
        var bigRecord = handRecord
        try bigRecord.setParams(bigCrop, as: CropModule.self)
        let shrinkBatch = CropToolRotation.linkedSnapshots(
            ashift: ashift, crop: bigRecord, rotationDegrees: 40, frameSize: frame)
        XCTAssertEqual(shrinkBatch?.count, 2, "a no-longer-fitting frame refits")
        let refitRecord = try XCTUnwrap(shrinkBatch?.last)
        let refit = try refitRecord.params(of: CropModule.self)
        // aspect kept: the PIXEL aspect (in the 600×400 AABB) survives —
        // the normalized fraction aspect is frame-shape-dependent and is
        // NOT the invariant (hand value: 510×300 = 1.7).
        let beforeW = Double(bigCrop.right - bigCrop.left) * 600
        let beforeH = Double(bigCrop.bottom - bigCrop.top) * 400
        // the shrunk frame still fits at the new angle (the bridge back)
        let span40 = CropToolRotation.RotatedFrameBridge.span(w0: 600, h0: 400, angleDegrees: 40)
        let refitRect = CropFitAngle.Rect(
            x0: Double(refit.left), y0: Double(refit.top),
            x1: Double(refit.right), y1: Double(refit.bottom))
        let inRotated = CropToolRotation.RotatedFrameBridge.cropToRotated(
            refitRect, span: span40, w0: 600, h0: 400)
        XCTAssertTrue(CropFitAngle.isWithinImage(
            inRotated, angleDegrees: 40, w: 600, h: 400), "the refit fits at 40°")
        // aspect kept: the ROTATED-FRAME pixel aspect (upstream's domain —
        // the AABB fractions change the pixel aspect by construction, the
        // 600×400 rotated-frame domain is the invariant)
        let afterW = inRotated.width * 600
        let afterH = inRotated.height * 400
        XCTAssertEqual(afterW / afterH, beforeW / beforeH, accuracy: 1e-6, "aspect kept")
        XCTAssertLessThanOrEqual(afterW, beforeW + 1e-9, "a hand frame never grows")

        // #1388: angle back to 0 regrows the largest frame (the full frame)
        let backBatch = CropToolRotation.linkedSnapshots(
            ashift: ashift, crop: crop, rotationDegrees: 0, frameSize: frame)
        XCTAssertNil(backBatch, "angle 0 → 0 is a no-op face (nothing to commit)")
        // from a non-zero angle back to 0, the TURNED crop (largest@12°
        // after the first hop landed) regrows to the full frame
        let turnBatch = try XCTUnwrap(CropToolRotation.linkedSnapshots(
            ashift: ashift, crop: crop, rotationDegrees: 12, frameSize: frame))
        XCTAssertEqual(turnBatch.count, 2, "the full-frame crop refits to largest@12°")
        editorState.recordLinkedChanges(turnBatch, label: "history_rotate")
        let nowAshift = try XCTUnwrap(
            editorState.instances.first { $0.opName == AshiftModule.opName })
        let turnedCrop = try XCTUnwrap(
            editorState.instances.first { $0.opName == CropModule.opName })
        let backToZero = try XCTUnwrap(CropToolRotation.linkedSnapshots(
            ashift: nowAshift, crop: turnedCrop, rotationDegrees: 0, frameSize: frame))
        XCTAssertEqual(backToZero.count, 2, "#1388: the regrow carries both items")
        let restored = try backToZero[1].params(of: CropModule.self)
        // 1e-6: the Float-record tolerance (the regrow re-lands through
        // the Float params record; 8.9e-9 measured residue)
        XCTAssertEqual(restored.left, 0, accuracy: 1e-6, "#1388: the full frame regrows")
        XCTAssertEqual(restored.bottom, 1, accuracy: 1e-6)
        // and the plain full-frame crop at a non-zero angle back to 0 is
        // angle-only (the full frame never shrank — nothing to regrow)
        let fullBack = CropToolRotation.linkedSnapshots(
            ashift: nowAshift, crop: crop, rotationDegrees: 0, frameSize: frame)
        XCTAssertEqual(fullBack?.count, 1, "the untouched full frame needs no crop item")
    }

    // MARK: - the 90° probes + the explicit-bit persistence

    func testNinetyDegreeBitProbeAndPersistence() throws {
        // the bit↔direction probe: .rotCW90 sends the TOP-RIGHT input
        // pixel to the BOTTOM-RIGHT output (visually clockwise)
        let (w, h) = (100, 80)
        let out = FlipOrientation.outputXY(x: w - 1, y: 0, w: w, h: h, orientation: .rotCW90)
        XCTAssertEqual(out.x, h - 1)
        XCTAssertEqual(out.y, w - 1, "top-right lands bottom-right = clockwise")
        XCTAssertTrue(CropToolRotation.isClockwiseBit(.rotCW90), "the probe reads .rotCW90 as CW")
        XCTAssertFalse(CropToolRotation.isClockwiseBit(.rotCCW90), "the probe reads .rotCCW90 as CCW")

        // the .auto seed steps to an EXPLICIT bit
        let cwSnapshot = try XCTUnwrap(
            CropToolRotation.ninetyDegreeSnapshot(currentFlip: flip, clockwise: true))
        let cwParams = try cwSnapshot.params(of: FlipModule.self)
        XCTAssertEqual(cwParams.orientation, .rotCW90, "the auto seed steps to the explicit CW bit")
        // an explicit bit SURVIVES EXIF resolution (D-M9G-6 persistence)
        let resolved = FlipOrientation.resolved(cwParams.orientation, forEXIF: 8)
        XCTAssertEqual(resolved, .rotCW90, "non-auto passes through untouched")
        // stepping twice lands rot180; stepping CCW from auto lands rotCCW90
        let cwTwice = try XCTUnwrap(CropToolRotation.ninetyDegreeSnapshot(
            currentFlip: cwSnapshot, clockwise: true))
        XCTAssertEqual(try cwTwice.params(of: FlipModule.self).orientation, .rot180)
        let ccwOnce = try XCTUnwrap(
            CropToolRotation.ninetyDegreeSnapshot(currentFlip: flip, clockwise: false))
        XCTAssertEqual(try ccwOnce.params(of: FlipModule.self).orientation, .rotCCW90)
    }

    // MARK: - Constrain Crop

    func testConstrainCropShrinksBlankEdges() throws {
        // a 600×400 output frame whose content lives in the centre band;
        // the full-frame crop carries blank edges → the constrain shrinks
        // to the content band.
        let span = SIMD2(600.0, 400.0)
        let contentBand = (x0: 100, x1: 500, y0: 60, y1: 340)
        let probe: (SIMD2<Int>) -> Bool = { p in
            p.x >= contentBand.x0 && p.x <= contentBand.x1
                && p.y >= contentBand.y0 && p.y <= contentBand.y1
        }
        let cropParams = try XCTUnwrap(crop).params(of: CropModule.self)
        let rect = try XCTUnwrap(CropToolRotation.constrainedCropRect(
            current: cropParams, span: span, contentAt: probe),
            "a blank-edged frame constrains")
        // blank_fraction < 0.002: every edge sample of the result is content
        let px0 = Int(rect.x0 * 600), px1 = Int(rect.x1 * 600) - 1
        let py0 = Int(rect.y0 * 400), py1 = Int(rect.y1 * 400) - 1
        var blank = 0
        var samples = 0
        for i in 0..<48 {
            let fx = px0 + (px1 - px0) * i / 47
            let fy = py0 + (py1 - py0) * i / 47
            for edge in [SIMD2(fx, py0), SIMD2(fx, py1), SIMD2(px0, fy), SIMD2(px1, fy)] {
                samples += 1
                if !probe(edge) { blank += 1 }
            }
        }
        XCTAssertLessThan(Double(blank) / Double(max(samples, 1)), 0.002, "blank_fraction < 0.002")
        // aspect kept: the PIXEL aspect survives the shrink (1.5)
        XCTAssertEqual((rect.width * 600) / (rect.height * 400), 1.5, accuracy: 0.02,
            "pixel aspect kept (1.5)")
        // an already-fitting frame answers nil (no blank edges)
        let fitted = CropModule.Params(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8)
        XCTAssertNil(CropToolRotation.constrainedCropRect(
            current: fitted, span: span, contentAt: probe),
            "a fitting frame is untouched")
    }
}
