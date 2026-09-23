import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// HOMOGRAPHY — the 3×3 projective core behind `ashift` (Plan 04-03-T1,
// IOP-GEO-02). Pure CPU Double math, no Metal, no pipe state — the same
// role dt's `_homography()` + `mat3*` helpers play for `ashift.c`.
//
// Darktable reference: `src/iop/ashift.c` (tree dc58cf0ba1)
//   - `_homography`   :756-979  (10-step ShiftN-style synthesis; forward
//                                matrix, optionally inverted via `mat3inv`)
//   - `mat3mul/mulv`  :`src/common/math.h:195-228` (row-major, dest = m1*m2)
//   - `mat3inv`       :`src/common/matrices.c:53-88` (adjugate, eps 1e-7,
//                                error → caller falls back to identity)
//   - `commit_params` :5588-5626 (GENERIC mode folds f_length_kb=28,
//                                orthocorr=0, aspect=1 — the ONLY mode
//                                Lightamer implements, 04-03-DECISIONS D1)
//   - `modify_roi_out:1142-1211` (forward corners → AABB × clip → floor;
//                                <4px → disable piece)
//   - `modify_roi_in :1213-1285` (inverse corners + clip offset → AABB +
//                                interpolation margin → clamp bufIn)
//
// FRAME CONVENTION (L020 — read before touching ROI code):
// Our backward walk seeds from the FORWARD result (`PixelPipe.run`
// `levelROI`, dt `get_dimensions` `buf_out` semantics): `modifyROIOut`
// records the window origin in upstream coords and `modifyROIIn`
// receives output-FRAME coords (xy already upstream-relative). dt's
// `roi_in = roi_out + buf_in·cx`-style re-adds presuppose dt's
// window-RELATIVE roi_out and MUST NOT be re-applied here. The helpers
// below therefore map points between two absolute frames:
//   forward  : bufIn-frame  (0,0,Wbuf,Hbuf) → full-output-frame
//              (step-10 offset included, so the full-buf image lands ≥ 0)
//   inverse  : full-output-frame → bufIn-frame
// and the MODULE (AshiftModule) adds the clip offset + window re-basing
// (`process` subtracts `roiIn.xy`, dt `distort_backtransform` semantics).
//
// INTENTIONAL DIVERGENCES:
// 1. **Scale-blind warp in plane pixels.** dt divides by `roi.scale`
//    around the homography; our pipe stamps `dscIn` at entry size and both
//    ROIs share one scale per run, so H is built at plane size and all
//    coords stay in plane pixels. Multi-resolution stays proportional
//    (rotation AABB scales linearly), not bit-identical — correct for
//    geometry, and the forward/inverse pair stays exactly consistent.
// 2. **Bilinear border taps clamp; fully-outside writes transparent.**
//    dt's border behavior lives behind the interpolation dispatch
//    (`DT_INTERPOLATION_USERPREF_WARP`); the Swift↔Python synthesized
//    pair below is the pinned semantic (04-03-DECISIONS D4).
// ─────────────────────────────────────────────────────────────────────────

/// Row-major 3×3 Double matrix — moved to LightamerCore in Plan 06-03-T2
/// (D-06-03-T2-1: the mask point-mapper in Core needs it and Core cannot
/// import IOP). Verbatim re-export — every 04-03/04-04 API and test keeps
/// compiling unchanged.
public typealias Mat3D = LightamerCore.Mat3D

/// The CPU homography engine (Plan 04-03-T1): dt `_homography` verbatim in
/// Double + 4-point DLT + the quad fitter behind rectangle auto-detect.
public enum Homography {

    /// dt `_homography` (`ashift.c:756-979`) verbatim, GENERIC mode only
    /// (`commit_params:5600-5605` fold: `f_length_kb` as passed,
    /// `orthocorr = 0`, `aspect = 1`; steps 5/8/9 go identity through the
    /// same arithmetic, not through simplification). Returns the FORWARD
    /// matrix (bufIn-frame → full-output-frame, step-10 offset included).
    ///
    /// - Parameters use dt units: `rotationDegrees` in degrees,
    ///   `shiftV/shiftH` in dt exp-shift units, `shear` raw.
    /// - `width/height` = the bufIn plane size (dt `piece->buf_in`).
    public static func compose(
        rotationDegrees: Double,
        shiftV: Double,
        shiftH: Double,
        shear: Double,
        fLengthKB: Double,
        width: Double,
        height: Double
    ) -> Mat3D {
        let u = width, v = height
        let phi = rotationDegrees * Double.pi / 180.0
        let cosi = cos(phi), sini = sin(phi)

        // GENERIC fold (dt `commit_params:5600-5605`).
        let fGlobal = fLengthKB
        let orthocorr = 0.0
        let aspect = 1.0
        let ascale = sqrt(aspect)

        let horifac = 1.0 - orthocorr / 100.0
        let exppaV = exp(shiftV)
        let fdbV = fGlobal / (14.4 + (v / u - 1.0) * 7.2)
        let radV = fdbV * (exppaV - 1.0) / (exppaV + 1.0)
        let alphaV = min(max(atan(radV), -1.5), 1.5)
        let rtV = sin(0.5 * alphaV)
        let rV = max(0.1, 2.0 * (horifac - 1.0) * rtV * rtV + 1.0)

        let vertifac = 1.0 - orthocorr / 100.0
        let exppaH = exp(shiftH)
        let fdbH = fGlobal / (14.4 + (u / v - 1.0) * 7.2)
        let radH = fdbH * (exppaH - 1.0) / (exppaH + 1.0)
        let alphaH = min(max(atan(radH), -1.5), 1.5)
        let rtH = sin(0.5 * alphaH)
        let rH = max(0.1, 2.0 * (vertifac - 1.0) * rtH * rtH + 1.0)

        // Step 1: flip x/y (dt `:813-816`).
        var minput = Mat3D(
            0, 1, 0,
            1, 0, 0,
            0, 0, 1)
        // Step 2: rotation about the (swapped) center (dt `:820-827`).
        var mwork = Mat3D(
            cosi, -sini, -0.5 * v * cosi + 0.5 * u * sini + 0.5 * v,
            sini, cosi, -0.5 * v * sini - 0.5 * u * cosi + 0.5 * u,
            0, 0, 1)
        var moutput = Mat3D.mul(mwork, minput)

        // Step 3: shear (dt `:834-839`).
        mwork = Mat3D(
            1, shear, 0,
            shear, 1, 0,
            0, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 4: vertical lens shift (dt `:848-854`).
        mwork = Mat3D(
            exppaV, 0, 0,
            0.5 * ((exppaV - 1.0) * u) / v, 2.0 * exppaV / (exppaV + 1.0),
            -0.5 * ((exppaV - 1.0) * u) / (exppaV + 1.0),
            (exppaV - 1.0) / v, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 5: horizontal compression (dt `:863-867`; identity in GENERIC).
        mwork = Mat3D(
            1, 0, 0,
            0, rV, 0.5 * u * (1.0 - rV),
            0, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 6: flip back (dt `:876-879`).
        mwork = Mat3D(
            0, 1, 0,
            1, 0, 0,
            0, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 7: horizontal lens shift (dt `:890-896`).
        mwork = Mat3D(
            exppaH, 0, 0,
            0.5 * ((exppaH - 1.0) * v) / u, 2.0 * exppaH / (exppaH + 1.0),
            -0.5 * ((exppaH - 1.0) * v) / (exppaH + 1.0),
            (exppaH - 1.0) / u, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 8: vertical compression (dt `:905-909`; identity in GENERIC).
        mwork = Mat3D(
            1, 0, 0,
            0, rH, 0.5 * v * (1.0 - rH),
            0, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 9: aspect scaling (dt `:918-921`; identity in GENERIC).
        mwork = Mat3D(
            ascale, 0, 0,
            0, 1.0 / ascale, 0,
            0, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        // Step 10: offset so no negative coords occur (dt `:929-956`).
        // dt visits integer corners (0,0)..(w-1,h-1) — verbatim here.
        let xs = width > 1 ? [0.0, width - 1.0] : [0.0]
        let ys = height > 1 ? [0.0, height - 1.0] : [0.0]
        var umin = Double.greatestFiniteMagnitude
        var vmin = Double.greatestFiniteMagnitude
        for y in ys {
            for x in xs {
                let p = moutput.applied(x, y)
                umin = min(umin, p.x / p.w)
                vmin = min(vmin, p.y / p.w)
            }
        }
        mwork = Mat3D(
            1, 0, -umin,
            0, 1, -vmin,
            0, 0, 1)
        minput = moutput
        moutput = Mat3D.mul(mwork, minput)

        return moutput
    }

    /// Solve the 4-point projective map `dst[i] = H * src[i]` (h33 = 1
    /// normalized) via 8×8 Gaussian elimination with partial pivot
    /// (~40 lines, no dependency — 04-RESEARCH §3). nil when singular.
    public static func dlt(
        src: [(x: Double, y: Double)],
        dst: [(x: Double, y: Double)]
    ) -> Mat3D? {
        guard src.count == 4, dst.count == 4 else { return nil }
        // Unknowns: h11 h12 h13 h21 h22 h23 h31 h32.
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = (src[i].x, src[i].y)
            let (xp, yp) = (dst[i].x, dst[i].y)
            a[2 * i][0] = x; a[2 * i][1] = y; a[2 * i][2] = 1
            a[2 * i][6] = -xp * x; a[2 * i][7] = -xp * y; a[2 * i][8] = xp
            a[2 * i + 1][3] = x; a[2 * i + 1][4] = y; a[2 * i + 1][5] = 1
            a[2 * i + 1][6] = -yp * x; a[2 * i + 1][7] = -yp * y; a[2 * i + 1][8] = yp
        }
        // Forward elimination with partial pivot.
        for col in 0..<8 {
            var piv = col
            for row in (col + 1)..<8 where abs(a[row][col]) > abs(a[piv][col]) {
                piv = row
            }
            guard abs(a[piv][col]) > 1e-12 else { return nil }
            if piv != col { a.swapAt(piv, col) }
            for row in (col + 1)..<8 {
                let f = a[row][col] / a[col][col]
                if f != 0 {
                    for k in col..<9 { a[row][k] -= f * a[col][k] }
                }
            }
        }
        // Back substitution.
        var h = [Double](repeating: 0, count: 8)
        for row in stride(from: 7, through: 0, by: -1) {
            var s = a[row][8]
            for k in (row + 1)..<8 { s -= a[row][k] * h[k] }
            h[row] = s / a[row][row]
        }
        return Mat3D(
            h[0], h[1], h[2],
            h[3], h[4], h[5],
            h[6], h[7], 1)
    }

    /// Fit `(rotation, shiftV, shiftH, shear)` so `compose(...)` maps
    /// `src` onto `dst` (least-squares corner error) — the rectangle
    /// auto-detect "反解参数" (04-03-T0 decision (2)). Deterministic
    /// coordinate descent with a fixed budget (no RNG, no dt NMS port):
    /// 60 sweeps × 4 params × ±step, step ×0.5 on stall. Returns the
    /// params + RMS corner error in pixels.
    public static func fitParams(
        src: [(x: Double, y: Double)],
        dst: [(x: Double, y: Double)],
        fLengthKB: Double,
        width: Double,
        height: Double
    ) -> (rotation: Double, shiftV: Double, shiftH: Double, shear: Double, rms: Double) {
        func rms(_ p: (Double, Double, Double, Double)) -> Double {
            let h = compose(
                rotationDegrees: p.0, shiftV: p.1, shiftH: p.2, shear: p.3,
                fLengthKB: fLengthKB, width: width, height: height)
            var s = 0.0
            for i in 0..<src.count {
                let q = h.project(src[i].x, src[i].y)
                s += (q.x - dst[i].x) * (q.x - dst[i].x) + (q.y - dst[i].y) * (q.y - dst[i].y)
            }
            return sqrt(s / Double(src.count))
        }
        var p = (0.0, 0.0, 0.0, 0.0)
        var step = (2.0, 0.2, 0.2, 0.05)
        var best = rms(p)
        for _ in 0..<60 {
            var moved = false
            for k in 0..<4 {
                for dir in [-1.0, 1.0] {
                    var q = p
                    let s = k == 0 ? step.0 : k == 1 ? step.1 : k == 2 ? step.2 : step.3
                    if k == 0 { q.0 += dir * s } else if k == 1 { q.1 += dir * s }
                    else if k == 2 { q.2 += dir * s } else { q.3 += dir * s }
                    let r = rms(q)
                    if r < best { best = r; p = q; moved = true }
                }
            }
            if !moved {
                step = (step.0 * 0.5, step.1 * 0.5, step.2 * 0.5, step.3 * 0.5)
                if step.0 < 1e-9 { break }
            }
        }
        return (p.0, p.1, p.2, p.3, best)
    }
}
