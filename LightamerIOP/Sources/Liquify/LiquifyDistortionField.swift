import Foundation
import simd
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Liquify path model + CPU distortion-field builder (Plan 06-06 T1, IOP-GEO-05).
//
// Darktable reference: `src/iop/liquify.c` (tree dc58cf0ba1):
//   - `dt_liquify_path_data_t`  :225-257  (header + warp + node — transcribed
//     below as `LiquifyPathData`; dt packs GUI state `selected`/`hovered` and
//     the array linkage `prev`/`idx`/`next` into params — Lightamer keeps the
//     geometry + semantic fields only; linkage derives from array order,
//     D-06-06-T1-2)
//   - MAX_NODES = 100           :47
//   - warp types                :218-223  (linear / radial grow / radial shrink)
//   - `init_warp`               :2621-2630 (defaults: control1 0.5, control2 0.75)
//   - `interpolate_cubic_bezier`:734-760  (polynomial-basis sampling)
//   - `build_lookup_table`      :815-868  (intensity profile bezier,
//                                          reparameterized on x)
//   - `mix_warps`               :692-729  (angle-continuous strength mixing)
//   - `interpolate_paths`       :1719-1800 (stamp chain at |radius|·0.1 steps)
//   - `compute_round_stamp_extent` :869-877
//   - `apply_round_stamp`       :893-1013 (4-quadrant field deposition)
//
// COORDINATE PREMISE (L020 — pinned here, asserted in LiquifyParityTests):
// `LiquifyPathData` points are stored as FRACTIONS of the module's ENTRY
// frame (0…1 over the frame as it enters the liquify module; dt stores
// pixels and rescales by the pipe scale per run — normalized storage is
// Lightamer's own-format decision, D-06-06-T1-1: params stay
// resolution-independent across PREVIEW/FULL runs, match the mask point
// model D-06-CONTEXT-7, and the iscale rescale disappears). The builder
// resolves to PLANE PIXELS of the requested frame; the warp kernel samples
// in exactly that domain (field grid coords == kernel sampling coords — the
// L020 same-domain requirement).
//
// FIELD SEMANTICS: the grid is the BACKWARD SAMPLING map
// `out(q) = in(q + F(q))` — a radial-GROW stamp therefore deposits vectors
// POINTING TOWARD the stamp center, which the kernel turns into
// magnification (dt's apply_round_stamp q1..q4 collapses to
// disp = −g·(dx, dy) per cell — verified term by term against :978-1013).
// ─────────────────────────────────────────────────────────────────────────────

/// dt `dt_liquify_warp_type_enum_t` (liquify.c:218-223) — raw values frozen
/// (sidecar ONE-WAY, Phase 2 convention).
public enum LiquifyWarpType: Int, Codable, Hashable, Sendable {
    /// A linear warp originating from one point (push along strength).
    case linear = 0
    /// A radial warp originating from one point (magnify).
    case radialGrow = 1
    /// Radial shrink (the strength sign flips at deposit — dt :907-910).
    case radialShrink = 2
}

/// dt `dt_liquify_path_data_enum_t` (:199-204) — the path element kind.
public enum LiquifyPathType: Int, Codable, Hashable, Sendable {
    case invalidated = 0  // list terminator (dt MAX_NODES sentinel)
    case moveTo = 1       // starts a subpath; LONE move = a single stamp
    case lineTo = 2       // linear segment to the point
    case curveTo = 3      // cubic bezier through ctrl1/ctrl2
}

/// dt `dt_liquify_node_type_enum_t` (:206-211) — kept for sidecar fidelity
/// (the v1 overlay draws every node type identically).
public enum LiquifyNodeType: Int, Codable, Hashable, Sendable {
    case cusp = 0
    case smooth = 1
    case symmetrical = 2
    case autosmooth = 3
}

/// Liquify resampling kernel family (dt's interpolation switch in
/// `_apply_global_distortion_map_cl`, liquify.c:1470-1497; kdesc resolution
/// 100 :1470).
public enum LiquifyInterpolation: String, Codable, Hashable, Sendable {
    case bilinear
    case bicubic
    case lanczos2
    case lanczos3

    /// dt `kdesc.size` — half the kernel width (taps 1−a … a).
    public var kernelSize: Int {
        switch self {
        case .bilinear: return 1
        case .bicubic, .lanczos2: return 2
        case .lanczos3: return 3
        }
    }
}

/// One path element — the `dt_liquify_path_data_t` transcription
/// (liquify.c:225-257). Geometry is stored as FRACTIONS of the module's
/// entry frame; the effective strength vector is `strength − point` and the
/// effective radius scalar is `|radius − point|` (dt stores both as points
/// because "the only thing we can reasonably distort_transform are points",
/// liquify.c:233-234).
public struct LiquifyPathData: Codable, Hashable, Sendable {

    /// The path element kind (dt `header.type`).
    public var type: LiquifyPathType
    /// The warp flavor of this node (dt `warp.type`; `init_warp` default
    /// linear).
    public var warpType: LiquifyWarpType
    public var nodeType: LiquifyNodeType

    /// Warp anchor (dt `warp.point`).
    public var point: SIMD2<Float>
    /// Strength handle TIP (dt `warp.strength`; vector = strength − point).
    public var strength: SIMD2<Float>
    /// Radius handle TIP (dt `warp.radius`; scalar = |radius − point|).
    public var radius: SIMD2<Float>
    /// Intensity-profile bezier controls, range 0…1 (dt `control1`/`control2`;
    /// `init_warp` defaults 0.5 / 0.75).
    public var control1: Float
    public var control2: Float
    /// dt status bits (:213-218); the builder consumes the INTERPOLATED bit
    /// (2) — stamps it generates carry it and deposit at 0.1× strength
    /// (STAMP_RELOCATION, :51-53).
    public var status: Int

    /// Curve control points (dt `node.ctrl1/ctrl2`), CURVE_TO only.
    public var ctrl1: SIMD2<Float>
    public var ctrl2: SIMD2<Float>

    public static let maxNodes = 100                    // dt MAX_NODES :47
    static let stampRelocation: Double = 0.1            // dt STAMP_RELOCATION :51
    static let interpolationPoints = 100                // dt INTERPOLATION_POINTS :50
    static let lookupOversample = 10                    // dt LOOKUP_OVERSAMPLE :49
    static let statusInterpolated = 2                   // dt STATUS_INTERPOLATED :215

    public init(
        type: LiquifyPathType,
        warpType: LiquifyWarpType = .linear,
        nodeType: LiquifyNodeType = .autosmooth,
        point: SIMD2<Float>,
        strength: SIMD2<Float>? = nil,
        radius: SIMD2<Float>? = nil,
        control1: Float = 0.5,
        control2: Float = 0.75,
        status: Int = 0,
        ctrl1: SIMD2<Float>? = nil,
        ctrl2: SIMD2<Float>? = nil
    ) {
        self.type = type
        self.warpType = warpType
        self.nodeType = nodeType
        self.point = point
        // dt `init_warp` (:2621-2630): radius/strength default to the point
        // (zero effective vector/scalar) — a placed-but-undragged node is a
        // no-op stamp.
        self.strength = strength ?? point
        self.radius = radius ?? point
        self.control1 = control1
        self.control2 = control2
        self.status = status
        self.ctrl1 = ctrl1 ?? point
        self.ctrl2 = ctrl2 ?? point
    }

    /// The effective strength vector (fractions of the entry frame).
    public var strengthVector: SIMD2<Float> { strength - point }
    /// The effective radius scalar (fraction of the entry frame; resolved
    /// against max(frame.w, frame.h) — a circle stays a circle under
    /// non-uniform frame aspects).
    public var radiusScalar: Float {
        let d = radius - point
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    // MARK: factories (dt alloc_move_to/alloc_line_to/alloc_curve_to shapes)

    public static func moveTo(
        _ p: SIMD2<Float>, warpType: LiquifyWarpType = .linear
    ) -> LiquifyPathData {
        LiquifyPathData(type: .moveTo, warpType: warpType, point: p)
    }
    public static func lineTo(
        _ p: SIMD2<Float>, warpType: LiquifyWarpType = .linear
    ) -> LiquifyPathData {
        LiquifyPathData(type: .lineTo, warpType: warpType, point: p)
    }
    public static func curveTo(
        _ p: SIMD2<Float>, warpType: LiquifyWarpType = .linear,
        ctrl1: SIMD2<Float>, ctrl2: SIMD2<Float>
    ) -> LiquifyPathData {
        LiquifyPathData(type: .curveTo, warpType: warpType, point: p, ctrl1: ctrl1, ctrl2: ctrl2)
    }
}

// MARK: - CPU distortion-field builder (the `_build_global_distortion_map`
// pipeline, liquify.c:1177-1210)

public enum LiquifyDistortionField {

    /// The Euclidean length (stdlib SIMD2 has no `.magnitude` — the
    /// GeometryPointMapper manual-norm convention).
    static func length(_ v: SIMD2<Double>) -> Double {
        (v.x * v.x + v.y * v.y).squareRoot()
    }

    /// One resolved stamp — a circular warp deposit (dt's interpolated
    /// `dt_liquify_warp_t`; geometry in PLANE PIXELS of the resolved frame).
    public struct Stamp: Sendable {
        var type: LiquifyWarpType
        var point: SIMD2<Double>
        /// Effective strength vector, 0.5-scaled (dt :903-905) and 0.1-scaled
        /// for interpolated stamps (:905-907) — the SHRINK sign is NOT folded
        /// here (dt flips it after mixing, :907-910).
        var strength: SIMD2<Double>
        /// Effective radius scalar (pixels).
        var radius: Double
        var control1: Double
        var control2: Double
    }

    // MARK: path interpolation (dt interpolate_paths :1719-1800)

    /// Interpolate the stored path list into the stamp chain. `frame` is the
    /// plane pixel size the stamps resolve into (the run's dscIn, or the
    /// mapper's entry frame). Empty result = identity (the normal
    /// empty-path case).
    public static func interpolateStamps(
        paths: [LiquifyPathData], frame: SIMD2<Double>
    ) -> [Stamp] {
        var stamps: [Stamp] = []
        guard !paths.isEmpty else { return stamps }

        func px(_ v: SIMD2<Float>) -> SIMD2<Double> {
            SIMD2(Double(v.x) * frame.x, Double(v.y) * frame.y)
        }
        func makeStamp(_ d: LiquifyPathData, interpolated: Bool) -> Stamp {
            var s = (px(d.strength) - px(d.point)) * 0.5
            if interpolated { s *= LiquifyPathData.stampRelocation }
            return Stamp(
                type: d.warpType,
                point: px(d.point),
                strength: s,
                radius: Double(d.radiusScalar) * max(frame.x, frame.y),
                control1: Double(d.control1),
                control2: Double(d.control2))
        }

        for (index, data) in paths.enumerated() {
            switch data.type {
            case .invalidated:
                continue  // list terminator — dt stops the scan (:1725-1727)
            case .moveTo:
                // LONE move (no line/curve successor) = one full-strength
                // stamp (dt :1729-1739 `header.next == -1`).
                let next = index + 1 < paths.count ? paths[index + 1].type : nil
                if next != .lineTo && next != .curveTo {
                    stamps.append(makeStamp(data, interpolated: false))
                }
            case .lineTo, .curveTo:
                guard index > 0 else { continue }
                let prev = paths[index - 1]
                guard prev.type != .invalidated else { continue }
                let p1 = px(prev.point), p2 = px(data.point)
                if data.type == .lineTo {
                    // dt :1744-1760: stamps along the segment at
                    // |radius|·STAMP_RELOCATION arc steps.
                    let total = LiquifyDistortionField.length(p2 - p1)
                    var arc = 0.0
                    while arc < total {
                        let t = total > 0 ? arc / total : 0
                        let pt = p1 * (1 - t) + p2 * t
                        var stamp = mixWarps(makeStamp(prev, interpolated: false),
                                             makeStamp(data, interpolated: false),
                                             pt: pt, t: t)
                        stamp.strength *= LiquifyPathData.stampRelocation
                        stamps.append(stamp)
                        // dt :1756-1760 advances by |radius|·0.1 — a zero
                        // radius would loop forever there; Lightamer breaks
                        // instead (D-06-06-T1-5).
                        let step = stamp.radius * LiquifyPathData.stampRelocation
                        guard step > 0 else { break }
                        arc += step
                    }
                } else {
                    // dt :1762-1796: bezier + arc-length parameterization.
                    var buffer = [SIMD2<Double>](repeating: .zero, count: LiquifyPathData.interpolationPoints)
                    interpolateCubicBezier(p1, px(data.ctrl1), px(data.ctrl2), p2, into: &buffer)
                    let total = arcLength(buffer)
                    var arc = 0.0
                    var restart = RestartCookie()
                    while arc < total {
                        let t = total > 0 ? arc / total : 0
                        let pt = pointAtArcLength(buffer, arc, &restart)
                        var stamp = mixWarps(makeStamp(prev, interpolated: false),
                                             makeStamp(data, interpolated: false),
                                             pt: pt, t: t)
                        stamp.strength *= LiquifyPathData.stampRelocation
                        stamps.append(stamp)
                        // Same zero-radius guard as the line leg above.
                        let step = stamp.radius * LiquifyPathData.stampRelocation
                        guard step > 0 else { break }
                        arc += step
                    }
                }
            }
        }
        return stamps
    }

    /// dt `mix_warps` (:692-729): angle-continuous interpolation of two
    /// stamps onto the path point `pt`. Operates on the strength VECTORS
    /// (uniformly 0.5-scaled vs dt's raw vectors — arguments unchanged, the
    /// magnitude mix is linear, so the transcription is exact).
    static func mixWarps(_ w1: Stamp, _ w2: Stamp, pt: SIMD2<Double>, t: Double) -> Stamp {
        func mix(_ a: Double, _ b: Double) -> Double { a * (1 - t) + b * t }
        var result = Stamp(
            type: w1.type, point: pt, strength: .zero,
            radius: mix(w1.radius, w2.radius),
            control1: mix(w1.control1, w2.control1),
            control2: mix(w1.control2, w2.control2))
        let p1 = w1.strength, p2 = w2.strength
        var arg1 = atan2(p1.y, p1.x)
        var arg2 = atan2(p2.y, p2.x)
        var invert = false
        if arg1 > 0 && arg2 < -.pi / 2 {
            invert = true
            arg1 = .pi - arg1
            arg2 = -.pi - arg2
        } else if arg1 < -.pi / 2 && arg2 > 0 {
            invert = true
            arg1 = -.pi - arg1
            arg2 = .pi - arg2
        }
        let magnitude = mix(LiquifyDistortionField.length(p1), LiquifyDistortionField.length(p2))
        let phi = invert ? .pi - mix(arg1, arg2) : mix(arg1, arg2)
        result.strength = SIMD2(magnitude * cos(phi), magnitude * sin(phi))
        return result
    }

    /// The union of the stamp extents (dt `compute_round_stamp_extent`
    /// :869-877) CLAMPED to `bounds`. Stamps entirely outside `bounds` are
    /// dropped (dt `_get_map_extent` :1032-1055 keeps stamps NOT entirely
    /// outside the roi). nil = no stamps intersect (the module renders
    /// identity). The clamp to bounds is a Lightamer tightening (D-06-06-T1-3):
    /// output pixels never read cells beyond their own roi, and the mapper's
    /// bilinear sampler treats out-of-extent as zero.
    public static func stampExtent(
        of stamps: [Stamp], bounds: SIMD2<Int>
    ) -> (origin: SIMD2<Int>, size: SIMD2<Int>)? {
        stampExtent(of: stamps, boundsOrigin: .zero, boundsSize: bounds)
    }

    /// Rect variant: `boundsOrigin`/`boundsSize` in frame pixels (the
    /// module passes its output roi; the mapper passes the full frame).
    public static func stampExtent(
        of stamps: [Stamp], boundsOrigin: SIMD2<Int>, boundsSize: SIMD2<Int>
    ) -> (origin: SIMD2<Int>, size: SIMD2<Int>)? {
        var union: (origin: SIMD2<Int>, size: SIMD2<Int>)?
        for stamp in stamps {
            let iradius = Int(stamp.radius.rounded())
            guard iradius > 0 else { continue }  // degenerate stamp — no-op
            let bx = Int(stamp.point.x.rounded()) - iradius
            let by = Int(stamp.point.y.rounded()) - iradius
            let side = 2 * iradius + 1
            if bx >= boundsOrigin.x + boundsSize.x || by >= boundsOrigin.y + boundsSize.y
                || bx + side <= boundsOrigin.x || by + side <= boundsOrigin.y {
                continue
            }
            if var u = union {
                let x0 = min(u.origin.x, bx), y0 = min(u.origin.y, by)
                let x1 = max(u.origin.x + u.size.x, bx + side)
                let y1 = max(u.origin.y + u.size.y, by + side)
                u.origin = SIMD2(x0, y0)
                u.size = SIMD2(x1 - x0, y1 - y0)
                union = u
            } else {
                union = (SIMD2(bx, by), SIMD2(side, side))
            }
        }
        guard var u = union else { return nil }
        // Clamp into bounds (the grid never spans beyond the run's region).
        let x0 = max(u.origin.x, boundsOrigin.x), y0 = max(u.origin.y, boundsOrigin.y)
        let x1 = min(u.origin.x + u.size.x, boundsOrigin.x + boundsSize.x)
        let y1 = min(u.origin.y + u.size.y, boundsOrigin.y + boundsSize.y)
        u.origin = SIMD2(x0, y0)
        u.size = SIMD2(max(1, x1 - x0), max(1, y1 - y0))
        return u
    }

    /// Deposit every stamp into a zeroed grid whose (0,0) cell is `origin`
    /// in frame pixels. dt's 4-quadrant deposition (:978-1013) collapses to
    /// (axis guards just prevent double-adding the axes):
    ///   linear: disp += −strength · profile[dist]
    ///   radial: disp += −g·(dx, dy), g = ±|strength|·profile[dist]/iradius
    public static func deposit(
        stamps: [Stamp], origin: SIMD2<Int>, width: Int, height: Int
    ) -> [SIMD2<Float>] {
        var grid = [SIMD2<Float>](repeating: .zero, count: width * height)
        for stamp in stamps {
            let iradius = Int(stamp.radius.rounded())
            guard iradius > 0 else { continue }
            // Stamp center in grid coords (dt :925-930 — the origin is the
            // ROUNDED point; out-of-grid cells are skipped per access).
            let cx = Int(stamp.point.x.rounded()) - origin.x
            let cy = Int(stamp.point.y.rounded()) - origin.y
            let tableSize = iradius * LiquifyPathData.lookupOversample
            guard let lookup = buildLookupTable(
                distance: tableSize, control1: stamp.control1, control2: stamp.control2)
            else { continue }
            let isLinear = stamp.type == .linear
            let shrinkSign: Double = stamp.type == .radialShrink ? -1 : 1

            func depositCell(_ gx: Int, _ gy: Int, _ vec: SIMD2<Double>) {
                guard gx >= 0, gy >= 0, gx < width, gy < height else { return }
                grid[gy * width + gx] += SIMD2(Float(vec.x), Float(vec.y))
            }

            for dy in 0...iradius {
                for dx in 0...iradius {
                    let dist = (Double(dx * dx) + Double(dy * dy)).squareRoot()
                    let idist = Int((dist * Double(LiquifyPathData.lookupOversample)).rounded())
                    if idist >= tableSize { break }  // dt :974-977 — row done
                    let profile = lookup[idist]
                    if isLinear {
                        let w = -stamp.strength * profile
                        depositCell(cx + dx, cy - dy, w)
                        if dx != 0 { depositCell(cx - dx, cy - dy, w) }
                        if dx != 0 && dy != 0 { depositCell(cx - dx, cy + dy, w) }
                        if dy != 0 { depositCell(cx + dx, cy + dy, w) }
                    } else {
                        let g = shrinkSign * LiquifyDistortionField.length(stamp.strength) * profile
                            / Double(iradius)
                        // disp = −g·(offset) — toward the center for grow.
                        func radial(_ ox: Int, _ oy: Int) -> SIMD2<Double> {
                            SIMD2(-g * Double(ox), -g * Double(oy))
                        }
                        depositCell(cx + dx, cy - dy, radial(dx, -dy))
                        if dx != 0 { depositCell(cx - dx, cy - dy, radial(-dx, -dy)) }
                        if dx != 0 && dy != 0 { depositCell(cx - dx, cy + dy, radial(-dx, dy)) }
                        if dy != 0 { depositCell(cx + dx, cy + dy, radial(dx, dy)) }
                    }
                }
            }
        }
        return grid
    }

    /// Full pipeline: paths → stamps → grid over `bounds` (plane pixels).
    /// nil = nothing to do (identity — the module's normal empty-path case).
    public static func build(
        paths: [LiquifyPathData], frame: SIMD2<Double>, bounds: SIMD2<Int>
    ) -> DisplacementField? {
        build(paths: paths, frame: frame, boundsOrigin: .zero, boundsSize: bounds)
    }

    /// Full pipeline over a rect region (the module's roi-out; the mapper's
    /// full frame). nil = nothing to do (identity).
    public static func build(
        paths: [LiquifyPathData], frame: SIMD2<Double>,
        boundsOrigin: SIMD2<Int>, boundsSize: SIMD2<Int>
    ) -> DisplacementField? {
        let stamps = interpolateStamps(paths: paths, frame: frame)
        guard let extent = stampExtent(
            of: stamps, boundsOrigin: boundsOrigin, boundsSize: boundsSize)
        else { return nil }
        let vectors = deposit(
            stamps: stamps, origin: extent.origin,
            width: extent.size.x, height: extent.size.y)
        return DisplacementField(forward: DisplacementField.Grid(
            origin: extent.origin, width: extent.size.x, height: extent.size.y,
            vectors: vectors))
    }

    // MARK: profile lookup table (dt build_lookup_table :815-868)

    /// The warp intensity profile: f(0) = 1, f(distance) = 0, smooth at both
    /// ends — a cubic bezier (0,1)→(c1,1)→(c2,0)→(1,0) reparameterized on x.
    /// `distance` = table_size = iradius × LOOKUP_OVERSAMPLE.
    static func buildLookupTable(
        distance: Int, control1: Double, control2: Double
    ) -> [Double]? {
        guard distance > 0 else { return nil }
        var clookup = [SIMD2<Double>](repeating: .zero, count: distance + 2)
        interpolateCubicBezier(
            SIMD2(0, 1),
            SIMD2(control1, 1),
            SIMD2(control2, 0),
            SIMD2(1, 0),
            into: &clookup)
        var lookup = [Double](repeating: 0, count: distance + 2)
        lookup[0] = 1.0
        let step = 1.0 / Double(distance)
        var x = 0.0
        var cptr = 1                              // dt `clookup + 1`
        let scanEnd = distance + 1                // dt `cptr_end`
        for i in 1..<distance {
            x += step
            while cptr < scanEnd && clookup[cptr].x < x { cptr += 1 }
            let dx1 = clookup[cptr].x - clookup[cptr - 1].x
            let dx2 = x - clookup[cptr - 1].x
            // Degenerate flat x-segment guard (dt divides by zero — recorded
            // deviation D-06-06-T1-4): carry the segment's end value.
            lookup[i] = dx1 > 0
                ? clookup[cptr].y + (dx2 / dx1) * (clookup[cptr].y - clookup[cptr - 1].y)
                : clookup[cptr].y
        }
        lookup[distance] = 0.0
        return lookup
    }

    // MARK: bezier + arc-length helpers (dt :711-760)

    /// dt `interpolate_cubic_bezier` (:734-760) — polynomial-basis form,
    /// verbatim.
    static func interpolateCubicBezier(
        _ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>,
        _ p3: SIMD2<Double>, into buffer: inout [SIMD2<Double>]
    ) {
        let n = buffer.count
        guard n >= 2 else { return }
        let a = p3 - 3 * p2 + 3 * p1 - p0
        let b = 3 * p2 - 6 * p1 + 3 * p0
        let c = 3 * p1 - 3 * p0
        let d = p0
        let step = 1.0 / Double(n)
        buffer[0] = p0
        var t = step
        for i in 1..<(n - 1) {
            buffer[i] = ((a * t + b) * t + c) * t + d
            t += step
        }
        buffer[n - 1] = p3
    }

    /// dt `get_arc_length` (:716-721).
    static func arcLength(_ points: [SIMD2<Double>]) -> Double {
        var length = 0.0
        for i in 1..<points.count { length += LiquifyDistortionField.length(points[i - 1] - points[i]) }
        return length
    }

    /// dt `restart_cookie_t` (:724-727).
    struct RestartCookie {
        var i = 1
        var length = 0.0
    }

    /// dt `point_at_arc_length` (:736-760) — a bezier parameter usually does
    /// not correspond to arc length, so reparameterize by walking segments.
    static func pointAtArcLength(
        _ points: [SIMD2<Double>], _ arcLength: Double, _ restart: inout RestartCookie
    ) -> SIMD2<Double> {
        var walked = restart.length
        var i = restart.i
        while i < points.count {
            let prevLength = walked
            walked += length(points[i - 1] - points[i])
            if walked >= arcLength {
                let t = (arcLength - prevLength) / (walked - prevLength)
                restart.i = i
                restart.length = prevLength
                return points[i - 1] * (1 - t) + points[i] * t
            }
            i += 1
        }
        return points[points.count - 1]
    }
}
