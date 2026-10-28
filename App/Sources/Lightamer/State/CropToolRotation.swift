import Foundation
import LightamerCore
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────
// CropToolRotation (Plan M9-3-T3, M9GEO-01) — the crop-tool rotate/
// straighten orchestration. Every entrance funnels through ONE linked-
// change path (the upstream `with_angle` single-funnel lesson, issues
// #742/#1388/#1794): the angle handle, the straighten slider and the auto
// straighten button all produce the SAME ashift.rotation + refitted-crop
// snapshot pair through `linkedSnapshots`.
//
// FRAME BRIDGE: the crop op stores fractions of the ASHIFT OUTPUT frame
// (the rotated AABB), while the T1 closed form (CropFitAngle) works in
// the upstream rotated-frame normalization (the ORIGINAL w×h, centred).
// `RotatedFrameBridge` converts between the two for one pure-rotation
// geometry: the rotated frame sits centred inside the AABB (span =
// floor(w0·|cosθ| + h0·|sinθ|) × floor(w0·|sinθ| + h0·|cosθ|) — the
// ashift modifyROIOut shape). The keystone family does NOT ride this
// bridge (Guided upright owns it; the crop linkage is the rotation face).
//
// LINKED-REFIT PREDICATE (D-M9G-1): the angle is the truth, the frame is
// derived — the refit runs ONLY through CropFitAngle.withAngle, which
// keeps a hand-adjusted frame that still fits untouched, shrinks one that
// no longer fits about its own centre (aspect kept), and regrows the
// largest frame as the angle returns (#1794/#1388). A frame the predicate
// leaves untouched produces NO second history item.
//
// 90° STEPS write flip.orientation's EXPLICIT bits (D-M9G-6: an explicit
// bit overrides `.auto` permanently — `resolved(forEXIF:)` passes non-auto
// straight through, so EXIF changes never flip it back). The bit↔visual
// direction mapping is pinned by golden probes in CropToolRotationTests
// (.rotCW90 = the top-right corner lands bottom-right = clockwise).
// ─────────────────────────────────────────────────────────────────────────

enum CropToolRotation {

    /// The rotated-frame bridge: output-frame (AABB) fractions ⇄ the
    /// upstream rotated-frame normalization. All math in Double.
    enum RotatedFrameBridge {

        /// The AABB span of an original `w0 × h0` frame rotated by
        /// `angleDegrees` about its centre (floor — the ashift
        /// modifyROIOut integer shape).
        static func span(w0: Double, h0: Double, angleDegrees: Double) -> SIMD2<Double> {
            let a = abs(angleDegrees) * Double.pi / 180
            let s = sin(a), c = cos(a)
            return SIMD2(floor(w0 * c + h0 * s), floor(w0 * s + h0 * c))
        }

        /// A crop rect in OUTPUT-frame fractions → the same rectangle in
        /// the rotated-frame normalization (pixels of the original w×h
        /// frame, centred). The rotated frame occupies the centred
        /// `w0 × h0` window of the AABB.
        static func cropToRotated(
            _ crop: CropFitAngle.Rect, span: SIMD2<Double>, w0: Double, h0: Double
        ) -> CropFitAngle.Rect {
            // output-frame pixels → AABB-local (centred) → rotated-frame pixels
            let px0 = (crop.x0 - 0.5) * span.x
            let py0 = (crop.y0 - 0.5) * span.y
            let px1 = (crop.x1 - 0.5) * span.x
            let py1 = (crop.y1 - 0.5) * span.y
            return CropFitAngle.Rect(
                x0: px0 / w0 + 0.5, y0: py0 / h0 + 0.5,
                x1: px1 / w0 + 0.5, y1: py1 / h0 + 0.5)
        }

        /// The rotated-frame normalization → output-frame fractions (the
        /// inverse bridge; clamped into the AABB by the caller's crop
        /// commit clamp).
        static func rotatedToCrop(
            _ rotated: CropFitAngle.Rect, span: SIMD2<Double>, w0: Double, h0: Double
        ) -> CropFitAngle.Rect {
            let px0 = (rotated.x0 - 0.5) * w0
            let py0 = (rotated.y0 - 0.5) * h0
            let px1 = (rotated.x1 - 0.5) * w0
            let py1 = (rotated.y1 - 0.5) * h0
            return CropFitAngle.Rect(
                x0: px0 / span.x + 0.5, y0: py0 / span.y + 0.5,
                x1: px1 / span.x + 0.5, y1: py1 / span.y + 0.5)
        }
    }

    // MARK: - decode helpers (the record face)

    private static func ashiftParams(_ instance: ModuleInstance?) throws -> AshiftModule.Params {
        guard let instance else { return AshiftModule.Params() }
        return try instance.params(of: AshiftModule.self)
    }

    private static func cropParams(_ instance: ModuleInstance?) throws -> CropModule.Params {
        guard let instance else { return CropModule.Params() }
        return try instance.params(of: CropModule.self)
    }

    private static func flipParams(_ instance: ModuleInstance?) throws -> FlipModule.Params {
        guard let instance else { return FlipModule.Params(orientation: .none) }
        return try instance.params(of: FlipModule.self)
    }

    private static func reEncoded<M: IOPModule>(
        _ template: ModuleInstance?, module: M.Type, params: M.Params
    ) -> ModuleInstance {
        if let template {
            var copy = template
            try? copy.setParams(params, as: module)
            return copy
        }
        return ModuleInstance(module: module, params: params)
    }

    // MARK: - the linked rotation refit (the single funnel)

    /// The angle handle / straighten slider / auto-straighten funnel:
    /// turns `ashift.rotation` to `rotationDegrees` and refits the crop
    /// rect through `CropFitAngle.withAngle`. Returns the snapshot batch
    /// in COMMIT ORDER (angle first, crop last — undo LIFO reverts the
    /// crop refit first, then the angle); the crop element is omitted
    /// when the predicate leaves the frame untouched (nil = nothing to
    /// commit: same angle AND no refit).
    ///
    /// `frameSize` is the upright-input frame size in pixels (the plane
    /// the rotation acts on — the decoded/derived plane, not the AABB).
    static func linkedSnapshots(
        ashift: ModuleInstance?, crop: ModuleInstance?,
        rotationDegrees: Float, frameSize: SIMD2<Double>
    ) -> [ModuleInstance]? {
        guard frameSize.x > 0, frameSize.y > 0 else { return nil }
        guard let oldAshift = try? ashiftParams(ashift) else { return nil }
        guard let cropParams = try? cropParams(crop) else { return nil }
        guard abs(rotationDegrees) <= 45 else { return nil }

        var newAshiftParams = oldAshift
        newAshiftParams.rotation = rotationDegrees
        let angleChanged = abs(Double(rotationDegrees) - Double(oldAshift.rotation)) > 1e-6

        // The frame refit only reacts to angle changes (a same-angle call
        // is a no-op face — the predicate never moves a frame without one).
        guard angleChanged else { return nil }

        let span = RotatedFrameBridge.span(
            w0: frameSize.x, h0: frameSize.y, angleDegrees: Double(rotationDegrees))
        let oldSpan = RotatedFrameBridge.span(
            w0: frameSize.x, h0: frameSize.y, angleDegrees: Double(oldAshift.rotation))

        // The crop record lives in the OLD angle's AABB; express it in the
        // rotated-frame normalization first. The AABB at a non-zero angle
        // EXTENDS past the original photo (the transparent outside); a crop
        // rectangle is only ever meaningful INSIDE the photo, so the mapped
        // rect clamps into the rotated-frame's 0..1 (this also restores the
        // largest-frame alignment: the full-frame crop maps to exactly the
        // rotated frame's unit, whose largest-fit identity #1388 relies on).
        let mapped = RotatedFrameBridge.cropToRotated(
            CropFitAngle.Rect(
                x0: Double(cropParams.left), y0: Double(cropParams.top),
                x1: Double(cropParams.right), y1: Double(cropParams.bottom)),
            span: oldSpan, w0: frameSize.x, h0: frameSize.y)
        let rotatedRect = CropFitAngle.Rect(
            x0: min(max(mapped.x0, 0), 1),
            y0: min(max(mapped.y0, 0), 1),
            x1: min(max(mapped.x1, 0), 1),
            y1: min(max(mapped.y1, 0), 1))

        // The closed-form refit (upstream with_angle: largest regrows,
        // hand frames keep when they fit, shrink in place when they don't).
        let refitted = CropFitAngle.withAngle(
            rotatedRect,
            angleDegrees: Double(oldAshift.rotation),
            newAngleDegrees: Double(rotationDegrees),
            w: frameSize.x, h: frameSize.y)

        var snapshots: [ModuleInstance] = []
        snapshots.append(reEncoded(ashift, module: AshiftModule.self, params: newAshiftParams))

        // The predicate face: did the frame move at all (in its own domain,
        // 1e-9 — the upstream crop.rs compare tolerance)?
        // 1e-6: the Float-record tolerance (the crop fractions round-trip
        // the record as Float — the f64 1e-9 gate would see phantom moves)
        let frameMoved = abs(refitted.x0 - rotatedRect.x0) > 1e-6
            || abs(refitted.y0 - rotatedRect.y0) > 1e-6
            || abs(refitted.x1 - rotatedRect.x1) > 1e-6
            || abs(refitted.y1 - rotatedRect.y1) > 1e-6
        if frameMoved {
            // Back through the bridge into the NEW angle's AABB fractions.
            let newCrop = RotatedFrameBridge.rotatedToCrop(
                refitted, span: span, w0: frameSize.x, h0: frameSize.y)
            var newCropParams = cropParams
            newCropParams.left = Float(newCrop.x0)
            newCropParams.top = Float(newCrop.y0)
            newCropParams.right = Float(newCrop.x1)
            newCropParams.bottom = Float(newCrop.y1)
            // Fractions must stay in the legal window (the crop commit
            // clamps; the refit geometry already guarantees fit, this is
            // the belt over the braces for AABB shrink rounding).
            newCropParams.left = min(max(newCropParams.left, 0), 1)
            newCropParams.top = min(max(newCropParams.top, 0), 1)
            newCropParams.right = min(max(newCropParams.right, 0), 1)
            newCropParams.bottom = min(max(newCropParams.bottom, 0), 1)
            snapshots.append(reEncoded(crop, module: CropModule.self, params: newCropParams))
        }
        return snapshots
    }

    // MARK: - 90° steps (the flip explicit bits)

    /// The bit↔direction probe (pinned by golden assertions in
    /// CropToolRotationTests): `.rotCW90`'s forward map sends the TOP-RIGHT
    /// input pixel to the BOTTOM-RIGHT output pixel — visually clockwise.
    static func isClockwiseBit(_ orientation: FlipOrientation) -> Bool {
        guard orientation.swapsXY else { return false }
        let w = 100, h = 80
        let out = FlipOrientation.outputXY(x: w - 1, y: 0, w: w, h: h, orientation: orientation)
        // clockwise moves the top-right corner to the bottom-right
        return out.x > (h / 2)
    }

    /// The 90° step: reads the current flip orientation (an explicit bit
    /// stays; `.auto` resolves first so the step lands on a concrete bit),
    /// steps one 90° turn in the requested visual direction, and returns
    /// the re-encoded snapshot. nil when the current orientation is not a
    /// pure 90°-step family member (the 180/transverse states step through
    /// the rotate-180 composition instead — out of this batch's face).
    static func ninetyDegreeSnapshot(
        currentFlip: ModuleInstance?, clockwise: Bool
    ) -> ModuleInstance? {
        guard let flipParams = try? flipParams(currentFlip) else { return nil }
        // .auto resolves to .none here (no EXIF at the record face) — the
        // step must land on an EXPLICIT bit to survive EXIF changes (D-M9G-6).
        let base: FlipOrientation
        switch flipParams.orientation {
        case .auto: base = .none
        default: base = flipParams.orientation
        }
        // Rotate the ORIENTATION BIT the same visual direction the image
        // turns: composing the current orientation with a further CW/CCW
        // step. Orientation composition in the bit field: applying `a`
        // then `b` = b∘a; the 90° steps cycle none→cw90→rot180→ccw90 (CW)
        // and none→ccw90→rot180→cw90 (CCW).
        let cwCycle: [FlipOrientation] = [.none, .rotCW90, .rot180, .rotCCW90]
        guard let idx = cwCycle.firstIndex(of: base) else { return nil }
        let next = clockwise ? cwCycle[(idx + 1) % 4] : cwCycle[(idx + 3) % 4]
        var newParams = flipParams
        newParams.orientation = next
        return reEncoded(currentFlip, module: FlipModule.self, params: newParams)
    }

    // MARK: - Constrain Crop (the blank-edge shrink)

    /// One-click black-edge shrink (the upstream `constrain_to_image`
    /// face): the content probe answers "is this output-frame pixel real
    /// content" (the caller wires the rendered plane's alpha/luminance);
    /// the rect shrinks toward its centre until every one of the 4×48
    /// edge samples is content (upstream's 48×4 sampling shape), keeping
    /// the crop's aspect (the upstream `constrained` semantics — the
    /// shrink is centred + aspect-kept). Returns nil when the current
    /// rect already fits (no blank edges) or the probe is exhausted.
    static func constrainedCropRect(
        current: CropModule.Params,
        span: SIMD2<Double>,
        contentAt: (SIMD2<Int>) -> Bool
    ) -> CropFitAngle.Rect? {
        let rect = CropFitAngle.Rect(
            x0: Double(current.left), y0: Double(current.top),
            x1: Double(current.right), y1: Double(current.bottom))
        func edgeIsBlank(_ rect: CropFitAngle.Rect) -> Bool {
            let samples = 48
            let left = Int(rect.x0 * span.x), right = Int(rect.x1 * span.x) - 1
            let top = Int(rect.y0 * span.y), bottom = Int(rect.y1 * span.y) - 1
            for i in 0..<samples {
                let fx = left + (right - left) * i / (samples - 1)
                let fy = top + (bottom - top) * i / (samples - 1)
                if !contentAt(SIMD2(fx, top)) { return true }
                if !contentAt(SIMD2(fx, bottom)) { return true }
                if !contentAt(SIMD2(left, fy)) { return true }
                if !contentAt(SIMD2(right, fy)) { return true }
            }
            return false
        }
        if !edgeIsBlank(rect) { return nil }
        // Binary shrink keeping the crop's PIXEL aspect (the upstream
        // `constrained` semantics): scale the original pixel size about the
        // rect's centre until every 4×48 edge sample is content. The
        // equal-step normalized shrink would silently change the aspect.
        let w0 = rect.width * span.x
        let h0 = rect.height * span.y
        func fits(scale: Double) -> Bool {
            let candidate = CropFitAngle.Rect.fromCenter(rect.center, width: w0 * scale / span.x, height: h0 * scale / span.y)
            return !edgeIsBlank(candidate)
        }
        if fits(scale: 1) { return nil }
        // binary search for the LARGEST fitting scale (lo = the largest
        // known-fitting, hi = the smallest known-failing; 20 rounds ≈ 1e-6
        // of the span — the returned lo keeps every edge sample content).
        var lo = 0.0
        var hi = 1.0
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if fits(scale: mid) { lo = mid } else { hi = mid }
        }
        guard lo > 1e-6 else { return nil }
        return CropFitAngle.Rect.fromCenter(rect.center, width: w0 * lo / span.x, height: h0 * lo / span.y)
    }

    /// The Constrain-Crop snapshot: nil when the frame already fits.
    static func constrainCropSnapshot(
        crop: ModuleInstance, span: SIMD2<Double>,
        contentAt: (SIMD2<Int>) -> Bool
    ) -> ModuleInstance? {
        guard let cropParams = try? cropParams(crop) else { return nil }
        guard let rect = constrainedCropRect(
            current: cropParams, span: span, contentAt: contentAt)
        else { return nil }
        var newParams = cropParams
        newParams.left = Float(rect.x0)
        newParams.top = Float(rect.y0)
        newParams.right = Float(rect.x1)
        newParams.bottom = Float(rect.y1)
        return reEncoded(crop, module: CropModule.self, params: newParams)
    }
}
