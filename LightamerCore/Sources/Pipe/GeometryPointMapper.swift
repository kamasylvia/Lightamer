import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// GeometryPointMapper (Plan 06-03 T2; D-06-CONTEXT-7 content-anchored masks).
//
// Masks store their point lists in FULL-DECODE-FRAME NORMALIZED coordinates
// (dt's model, `masks.h` forms); the composite window lives in post-geometry
// pixels. This mapper converts points between the two by composing the base
// chain's GEOMETRY segments (V50 slots lens 13 → ashift 15 → flip 16 → crop
// 24.5, the enabled instances in chain order) — the same mechanism dt uses
// via `dt_dev_distort_backtransform_plus` (masks/gradient.c:1172, liquify
// path mapping liquify.c:606-612).
//
//   forward  : decode-frame normalized → composite-frame normalized
//   inverse  : composite-frame normalized → decode-frame normalized
//
// Coordinate convention: CONTINUOUS PIXELS inside the segments (pixel
// centers at integer + 0.5; the mirror maps x → W − x so center i+0.5
// lands on center W−1−i — the exact continuous counterpart of
// `FlipOrientation.inputXY`'s integer w−x−1). Normalized at the boundary:
// n = px / size (component-wise).
//
// SEGMENTS (each module owns its math — Core cannot import IOP, D-03):
// - `.affine`      — crop (translation + scale, exact) and flip
//                    (orientation remap, exact)
// - `.homography`  — ashift (04-03 H matrix + its explicit inverse; the
//                    module's process/ROI legs use the same pair)
// - `.radial`      — lens (04-04 k1/k2 coefficients; the inverse IS the
//                    kernel's sampling map `LensModule.forwardPoint`, the
//                    forward solves it by guarded Newton — plan allows
//                    iterative inversion with a precision gate)
// - `.liquifyIdentity` — the 6-6 reservation (RESEARCH Risk 9: an EMPTY
//                    liquify is the NORMAL path, so the placeholder must be
//                    the identity, never a gap).
//
// EMPTY/DISABLED modules contribute NOTHING (identity passthrough by
// omission) — the neutral base chain maps masks 1:1 (the common path).
// ─────────────────────────────────────────────────────────────────────────────

/// One chain geometry segment in continuous pixel coordinates. `inSize` is
/// the segment's input frame (plane pixels); `outSize` its output frame.
public enum GeometrySegment: Sendable, Equatable {

    /// Exact 2×3 affine (crop window / flip orientation).
    /// forward: p' = A·p + t. Crop: p' = p − origin. Flip: see
    /// `Affine2D.flip`.
    case affine(Affine2D, inSize: SIMD2<Double>, outSize: SIMD2<Double>)

    /// ashift: forward p' = H·p − clip (dt process leg with full-window
    /// ROIs); inverse p = Hinv·(p' + clip). `outSpan` = the module's
    /// `fullOutputSpan` (the full-output frame the clip is relative to).
    case homography(forward: Mat3D, inverse: Mat3D, clip: SIMD2<Double>,
                    inSize: SIMD2<Double>, outSpan: SIMD2<Double>)

    /// lens: the CORRECTION mapping in radius units. `inversePixel` here is
    /// the warp kernel's sampling map (composite q → decode p =
    /// c + dir·Rd(u), Rd(u) = u(1 + k1u² + k2u⁴)); `forwardPixel` solves
    /// it (decode p → composite q) by guarded Newton on u.
    case radial(k1: Double, k2: Double, size: SIMD2<Double>)

    /// 6-6 reservation: an empty liquify path is the NORMAL path (RESEARCH
    /// Risk 9) — the placeholder maps points 1:1 until the displacement
    /// field lands.
    case liquifyIdentity
}

/// The exact affine (`p' = A·p + t`, row-major 2×2 + translation).
public struct Affine2D: Sendable, Equatable {
    public var a00: Double
    public var a01: Double
    public var a10: Double
    public var a11: Double
    public var tx: Double
    public var ty: Double

    public init(a00: Double, a01: Double, a10: Double, a11: Double, tx: Double, ty: Double) {
        self.a00 = a00; self.a01 = a01; self.a10 = a10; self.a11 = a11
        self.tx = tx; self.ty = ty
    }

    public static let identity = Affine2D(a00: 1, a01: 0, a10: 0, a11: 1, tx: 0, ty: 0)

    public func apply(_ p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(a00 * p.x + a01 * p.y + tx, a10 * p.x + a11 * p.y + ty)
    }

    /// Exact inverse (affine with invertible 2×2; every geometry affine
    /// here is invertible by construction — window/swap/mirror).
    public func inverted() -> Affine2D {
        let det = a00 * a11 - a01 * a10
        precondition(abs(det) > 1e-12, "geometry affine is singular")
        let i00 = a11 / det, i01 = -a01 / det
        let i10 = -a10 / det, i11 = a00 / det
        return Affine2D(
            a00: i00, a01: i01, a10: i10, a11: i11,
            tx: -(i00 * tx + i01 * ty), ty: -(i10 * tx + i11 * ty))
    }

    /// crop forward: p' = p − (left·W, top·H) — the window extraction.
    public static func crop(left: Double, top: Double, inputSize: SIMD2<Double>) -> Affine2D {
        Affine2D(a00: 1, a01: 0, a10: 0, a11: 1, tx: -left * inputSize.x, ty: -top * inputSize.y)
    }

    /// flip forward in the module's kernel order (flip X/Y first, then
    /// swap — `FlipOrientation.outputXY`'s continuous counterpart); `bits`
    /// = the dt orientation bit field (bit0 Y, bit1 X, bit2 SWAP).
    public static func flip(bits: Int, inputSize: SIMD2<Double>) -> Affine2D {
        let w = inputSize.x, h = inputSize.y
        var a = Affine2D.identity
        if bits & 0b010 != 0 { // FLIP_X: x → w − x
            a = Affine2D(a00: -1, a01: 0, a10: 0, a11: 1, tx: w, ty: 0).composed(with: a)
        }
        if bits & 0b001 != 0 { // FLIP_Y: y → h − y
            a = Affine2D(a00: 1, a01: 0, a10: 0, a11: -1, tx: 0, ty: h).composed(with: a)
        }
        if bits & 0b100 != 0 { // SWAP_XY last (kernel order)
            a = Affine2D(a00: 0, a01: 1, a10: 1, a11: 0, tx: 0, ty: 0).composed(with: a)
        }
        return a
    }

    /// self ∘ other (`other` first, then `self`).
    public func composed(with other: Affine2D) -> Affine2D {
        Affine2D(
            a00: a00 * other.a00 + a01 * other.a10,
            a01: a00 * other.a01 + a01 * other.a11,
            a10: a10 * other.a00 + a11 * other.a10,
            a11: a10 * other.a01 + a11 * other.a11,
            tx: a00 * other.tx + a01 * other.ty + tx,
            ty: a10 * other.tx + a11 * other.ty + ty)
    }
}

/// The composed base-chain geometry mapper (D-06-CONTEXT-7).
public struct GeometryPointMapper: Sendable {

    /// The decode frame (plane pixels at the run's entry scale — the mask
    /// coordinate system's unit frame).
    public let frameSize: SIMD2<Double>

    /// The composite output frame (after the full chain; equal to the
    /// frame when no geometry is enabled).
    public let outputSize: SIMD2<Double>

    /// Chain order (forward = decode → composite). Empty = identity.
    public let segments: [GeometrySegment]

    public init(frameSize: SIMD2<Double>, segments: [GeometrySegment], outputSize: SIMD2<Double>) {
        self.frameSize = frameSize
        self.segments = segments
        self.outputSize = outputSize
    }

    // ── pixel-space mapping ──

    /// Decode-frame pixel → composite-frame pixel (content direction).
    public func forwardPixel(_ p: SIMD2<Double>) -> SIMD2<Double> {
        var size = frameSize
        var q = p
        for segment in segments {
            (q, size) = Self.forward(segment, q, size)
        }
        return q
    }

    /// Composite-frame pixel → decode-frame pixel (the rasterizer's
    /// per-pixel leg — where does this window pixel's CONTENT live).
    public func inversePixel(_ q: SIMD2<Double>) -> SIMD2<Double> {
        var size = outputSize
        var p = q
        for segment in segments.reversed() {
            (p, size) = Self.inverse(segment, p, size)
        }
        return p
    }

    // ── normalized API (the plan's contract surface) ──

    /// Decode-frame normalized → composite-frame normalized.
    public func forward(normalized p: SIMD2<Double>) -> SIMD2<Double> {
        forwardPixel(SIMD2(p.x * frameSize.x, p.y * frameSize.y)) / outputSize
    }

    /// Composite-frame normalized → decode-frame normalized.
    public func inverse(normalized q: SIMD2<Double>) -> SIMD2<Double> {
        let p = inversePixel(SIMD2(q.x * outputSize.x, q.y * outputSize.y))
        return SIMD2(p.x / frameSize.x, p.y / frameSize.y)
    }

    // ── segment legs (pixel space, sizes propagate) ──

    static func forward(
        _ s: GeometrySegment, _ p: SIMD2<Double>, _ inSize: SIMD2<Double>
    ) -> (SIMD2<Double>, SIMD2<Double>) {
        switch s {
        case let .affine(a, _, outSize):
            return (a.apply(p), outSize)
        case let .homography(h, _, clip, _, outSpan):
            let projected = h.project(p.x, p.y)
            return (SIMD2(projected.x - clip.x, projected.y - clip.y), outSpan)
        case let .radial(k1, k2, size):
            precondition(size == inSize, "lens segment frame drift")
            return (Self.lensForward(p, k1: k1, k2: k2, size: size), size)
        case .liquifyIdentity:
            return (p, inSize)
        }
    }

    static func inverse(
        _ s: GeometrySegment, _ q: SIMD2<Double>, _ outSize: SIMD2<Double>
    ) -> (SIMD2<Double>, SIMD2<Double>) {
        switch s {
        case let .affine(a, inSize, _):
            return (a.inverted().apply(q), inSize)
        case let .homography(_, hInv, clip, inSize, outSpan):
            precondition(outSpan == outSize, "ashift segment frame drift")
            let shifted = hInv.project(q.x + clip.x, q.y + clip.y)
            return (SIMD2(shifted.x, shifted.y), inSize)
        case let .radial(k1, k2, size):
            precondition(size == outSize, "lens segment frame drift")
            return (Self.lensInverse(q, k1: k1, k2: k2, size: size), size)
        case .liquifyIdentity:
            return (q, outSize)
        }
    }

    // ── lens legs (u = radius in halfW units; center = frame center) ──

    /// Rd(u) = u·(1 + k1·u² + k2·u⁴) — `LensModule.forwardRadius` verbatim
    /// (dc1/dc3 = 0 in the manual mapping).
    static func lensDistortedRadius(_ u: Double, k1: Double, k2: Double) -> Double {
        u * (1 + k1 * u * u + k2 * u * u * u * u)
    }

    /// Composite q → decode p (the warp kernel's sampling map).
    static func lensInverse(
        _ q: SIMD2<Double>, k1: Double, k2: Double, size: SIMD2<Double>
    ) -> SIMD2<Double> {
        let c = size / 2
        let halfW = size.x / 2
        let d = q - c
        let u = ((d.x * d.x + d.y * d.y).squareRoot()) / halfW
        guard u > 1e-12 else { return q }
        let rd = lensDistortedRadius(u, k1: k1, k2: k2)
        return c + d * (rd / u)
    }

    /// Decode p → composite q: solve u_q with Rd(u_q) = u_p (guarded
    /// Newton; on stall a 60-step bisection on [0, u_bound] finishes the
    /// job — the radial polynomial is monotone over the correction range).
    /// The caller's roundtrip gate (0.1 px) is the referee.
    static func lensForward(
        _ p: SIMD2<Double>, k1: Double, k2: Double, size: SIMD2<Double>
    ) -> SIMD2<Double> {
        let c = size / 2
        let halfW = size.x / 2
        let d = p - c
        let up = ((d.x * d.x + d.y * d.y).squareRoot()) / halfW
        guard up > 1e-12 else { return p }
        func f(_ u: Double) -> Double { u + k1 * u * u * u + k2 * u * u * u * u * u - up }

        var u = up
        var converged = false
        for _ in 0..<24 {
            let u2 = u * u
            let value = f(u)
            let fp = 1 + 3 * k1 * u2 + 5 * k2 * u2 * u2
            guard abs(fp) > 1e-12 else { break }
            let step = value / fp
            u -= step
            if abs(step) < 1e-14 { converged = true; break }
        }
        if !converged, abs(f(u)) > 1e-9 {
            // Bisection fallback on [0, hi] — f(0) = −up < 0; grow hi
            // until f(hi) ≥ 0 then halve.
            var lo = 0.0
            var hi = max(1.0, 2 * up)
            while f(hi) < 0, hi < 64 { hi *= 2 }
            for _ in 0..<80 {
                let mid = 0.5 * (lo + hi)
                if f(mid) < 0 { lo = mid } else { hi = mid }
            }
            u = 0.5 * (lo + hi)
        }
        u = max(u, 0)
        return c + d * (u / up)
    }

    // MARK: - Composition from a base chain (the driver/rasterizer entry)

    /// Compose the enabled geometry segments of a base chain in v50 order
    /// (lens 13 → ashift 15 → flip 16 → crop 24.5; the (iopOrder,
    /// multiPriority) sort is the pipe's own). Non-geometric and neutral
    /// modules contribute nothing. liquify (6-6) will join through the same
    /// hook — its EMPTY-path hook returns `.liquifyIdentity` (the normal
    /// path, RESEARCH Risk 9).
    public static func compose(
        boxes: [any ModuleBoxing], frameSize: SIMD2<Double>
    ) -> GeometryPointMapper {
        let sorted = boxes.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        var segments: [GeometrySegment] = []
        var size = frameSize
        for box in sorted where box.enabled {
            if let result = box.pointMapSegmentErased(inputSize: size) {
                segments.append(result.segment)
                size = result.outputSize
            }
        }
        return GeometryPointMapper(frameSize: frameSize, segments: segments, outputSize: size)
    }

    // MARK: - GPU uniform composition (the rasterizer's inverse chain as
    // ONE projective 3×3 in normalized coords + lens constants)

    /// The composite of every NON-radial segment (ashift ∘ flip ∘ crop)
    /// INVERTED and expressed as a single projective matrix on NORMALIZED
    /// coordinates (composite_n → pre-lens_n — the rasterizer applies the
    /// lens leg after it). nil components collapse to identity.
    ///
    /// Built as the forward pixel-space composite (per-segment frames
    /// cancel pairwise — each segment's output frame IS the next segment's
    /// input frame), inverted, then conjugated by the endpoint diagonals:
    /// p_n = D(frame)⁻¹ · M_fwd⁻¹ · D(out) · q_n.
    public var projectiveInverseComposite: Mat3D {
        var m = Mat3D.identity
        var outSize = frameSize
        for segment in segments {
            switch segment {
            case let .affine(a, _, segOut):
                let am = Mat3D(a.a00, a.a01, a.tx, a.a10, a.a11, a.ty, 0, 0, 1)
                m = Mat3D.mul(am, m)
                outSize = segOut
            case let .homography(h, _, clip, _, outSpan):
                // forward p' = H·p − clip ⇔ homogeneous (H·p − clip·w)/w:
                // rows 0/1 lose clip·row2; row 2 stays.
                let hm = Mat3D(
                    h[0, 0] - clip.x * h[2, 0], h[0, 1] - clip.x * h[2, 1], h[0, 2] - clip.x * h[2, 2],
                    h[1, 0] - clip.y * h[2, 0], h[1, 1] - clip.y * h[2, 1], h[1, 2] - clip.y * h[2, 2],
                    h[2, 0], h[2, 1], h[2, 2])
                m = Mat3D.mul(hm, m)
                outSize = outSpan
            case .radial, .liquifyIdentity:
                break // radial handled separately (non-projective); liquify identity
            }
        }
        // The GPU leg consumes the INVERSE direction (window pixel → decode
        // content): p_n = D(frame)⁻¹ · M_fwd⁻¹ · D(out) · q_n.
        guard let mInv = m.inverted() else {
            return Mat3D.identity
        }
        func diag(_ sx: Double, _ sy: Double) -> Mat3D {
            Mat3D(sx, 0, 0, 0, sy, 0, 0, 0, 1)
        }
        return Mat3D.mul(
            Mat3D.mul(diag(1 / frameSize.x, 1 / frameSize.y), mInv),
            diag(outSize.x, outSize.y))
    }

    /// The lens parameters for the GPU leg (nil = no radial segment).
    public var lensParams: (k1: Double, k2: Double)? {
        for segment in segments.reversed() {
            if case let .radial(k1, k2, _) = segment { return (k1, k2) }
        }
        return nil
    }
}
