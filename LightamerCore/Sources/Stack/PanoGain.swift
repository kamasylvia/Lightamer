import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PanoGain (Plan M5-3-02 T2; KD-6) — the panorama exposure-gain segment: the
// ≤900px sample-canvas construction, the pairwise median-log overlap
// equations, the reference anchor, and the least-squares joint solve with the
// ±0.5 exp clip. Pure CPU, sequential, deterministic (G3③'s anchor).
//
// MIT ATTRIBUTION (CONVENTIONS 参考项目节): Portions derived from Lumen RAW
// (lumen-raw, MIT) — the GAIN-SEGMENT PARAMETERS: the ≤900px sampling canvas
// (merge.py:259 `ratio=min(1.,900/max(w,h))`), the ≥80-overlap-sample floor
// and the (0.04, 0.9) value gates (merge.py:265-267 — black-point/clipping
// exclusion), the equation form `g_i − g_j = median(log(J_j/J_i))`
// (merge.py:268-270), the reference anchor row (weight 10, value 0,
// merge.py:271), the least-squares joint solve (merge.py:272
// `np.linalg.lstsq`), and the `exp(clip(±.5))` gain ceiling (≈1.65× —
// merge.py:272, the single-noisy-pair blast guard). Swift rewrite; the
// no-disconnected-photo-lost property rides the anchor + min-norm solve
// (the merge.py:257-258 comment's semantics — see the solver note).
//
// SOLVER (checker O2 ruling): Accelerate `dgelsd` (SVD pseudo-inverse,
// minimum-norm least squares) — NOT the normal equations: a geometrically
// disconnected image contributes an all-zero column, which makes the normal
// equations SINGULAR (NaN path) while dgelsd's min-norm property resolves
// the variable to 0 → the disconnected image keeps gain e⁰ = 1. The two
// plan options were NOT equivalent freedoms; this is the load-bearing pick.
//
// DOMAIN (KD-6): the sample planes ride the ALREADY sRGB-encoded staged
// planes (the checker-minor-2 seam — the luma is computed from the encoded
// RGB directly, no second encode). The Rec709 luma weights are the shared
// `MertensFusion.grayCoefficients`.
// ─────────────────────────────────────────────────────────────────────────────

/// One source's gain-sampling canvas: the Rec709 luma of the bilinear gather
/// over the already-encoded staged plane + the per-sample validity mask
/// (the Lumen sample-gate semantics: 1 ≤ mx < sourceW−2, 1 ≤ my < sourceH−2).
public struct PanoGainSamplePlane: Sendable {
    public let width: Int
    public let height: Int
    public let luma: [Float]
    public let valid: [Bool]

    public init(width: Int, height: Int, luma: [Float], valid: [Bool]) {
        precondition(luma.count == width * height, "sample luma size mismatch")
        precondition(valid.count == width * height, "sample mask size mismatch")
        self.width = width
        self.height = height
        self.luma = luma
        self.valid = valid
    }
}

public enum PanoGain {

    // MARK: - Constants (KD-6: file constants, NOT parameters)

    /// The sample-canvas long-edge cap (merge.py:259).
    public static let sampleCanvasMaxEdge = 900.0
    /// The pairwise overlap-sample floor (merge.py:267 `mask.sum()<80`).
    public static let minOverlapSamples = 80
    /// The luma value gates (merge.py:266 — strict: black-point/clipping
    /// exclusions are open intervals).
    public static let gateLow: Float = 0.04
    public static let gateHigh: Float = 0.9
    /// The reference anchor weight (merge.py:271 `row[reference]=10`).
    public static let anchorWeight = 10.0
    /// The log-domain gain clip (merge.py:272 `np.clip(...,-.5,.5)` —
    /// the e^0.5 ≈ 1.65× ceiling).
    public static let clipLimit = 0.5

    // MARK: - The sample canvas (merge.py:259-264)

    /// The gain-sample canvas size for a canvas (w, h): the long edge capped
    /// at `sampleCanvasMaxEdge`, both edges ≥ 1 (merge.py:259-260 — the
    /// round() convention, NOT floor).
    public static func sampleCanvasSize(
        canvasWidth: Int, canvasHeight: Int
    ) -> (width: Int, height: Int) {
        let longest = max(canvasWidth, canvasHeight)
        let ratio = min(1.0, sampleCanvasMaxEdge / Double(max(1, longest)))
        return (
            width: max(1, Int((Double(canvasWidth) * ratio).rounded())),
            height: max(1, Int((Double(canvasHeight) * ratio).rounded())))
    }

    /// One source's sample canvas: the spherical map over the SCALED rect
    /// (the leg passes rectX = x0·ratio, scale·ratio — merge.py:261-262)
    /// with bilinear gathering through `rowReader` (already-encoded RGBA
    /// full rows; the closure reads source rows [firstRow, firstRow+rowCount)
    /// in one call). Valid samples gather Rec709 luma; everything outside
    /// the Lumen gate stays invalid.
    public static func samplePlane(
        rectX: Double, rectY: Double, width: Int, height: Int,
        scale: Double, source: PanoSourceGeometry,
        rowReader: (Int, Int) throws -> [Float]
    ) throws -> PanoGainSamplePlane {
        let (mx, my) = PanoWarp.sphericalMap(
            rectX: rectX, rectY: rectY, width: width, height: height,
            scale: scale, source: source)
        var luma = [Float](repeating: 0, count: width * height)
        var valid = [Bool](repeating: false, count: width * height)
        let sourceWidth = source.width
        let sourceHeight = source.height
        let cr = MertensFusion.grayCoefficients.r
        let cg = MertensFusion.grayCoefficients.g
        let cb = MertensFusion.grayCoefficients.b
        let maxX = Float(sourceWidth - 2)
        let maxY = Float(sourceHeight - 2)
        for y in 0..<height {
            // The source-row span this sample row's valid points touch —
            // ONE staged read per sample row (the gather is smooth along
            // the map, so the span stays narrow).
            var minRow = Int.max
            var maxRow = Int.min
            let rowBase = y * width
            for x in 0..<width {
                let sx = mx[rowBase + x]
                let sy = my[rowBase + x]
                if sx >= 1, sy >= 1, sx < maxX, sy < maxY {
                    let row = Int(sy)
                    minRow = min(minRow, row)
                    maxRow = max(maxRow, row + 1)
                }
            }
            guard minRow != Int.max else { continue }
            let first = max(0, minRow)
            let last = min(sourceHeight - 1, maxRow) // inclusive
            let rows = try rowReader(first, last - first + 1)
            precondition(
                rows.count == (last - first + 1) * sourceWidth * 4,
                "rowReader returned \(rows.count) floats for "
                    + "\(last - first + 1) rows")
            for x in 0..<width {
                let sx = mx[rowBase + x]
                let sy = my[rowBase + x]
                guard sx >= 1, sy >= 1, sx < maxX, sy < maxY else { continue }
                // Bilinear gather (the INTER_LINEAR semantics with the
                // gate guaranteeing in-bounds neighbors — the replicate
                // path can never engage inside the gate).
                let ix = min(Int(sx), sourceWidth - 2)
                let fx = sx - Float(ix)
                let iy = min(Int(sy), sourceHeight - 2)
                let fy = sy - Float(iy)
                let stride = sourceWidth * 4
                let row0 = (iy - first) * stride
                let row1 = row0 + stride
                let column = ix * 4
                func lumaAt(_ base: Int, _ column: Int) -> Float {
                    let p = base + column
                    return cr * rows[p] + cg * rows[p + 1] + cb * rows[p + 2]
                }
                let top = lumaAt(row0, column) * (1 - fx)
                    + lumaAt(row0, column + 4) * fx
                let bottom = lumaAt(row1, column) * (1 - fx)
                    + lumaAt(row1, column + 4) * fx
                luma[rowBase + x] = top * (1 - fy) + bottom * fy
                valid[rowBase + x] = true
            }
        }
        return PanoGainSamplePlane(
            width: width, height: height, luma: luma, valid: valid)
    }

    // MARK: - The equation system (merge.py:265-271)

    /// The pairwise median-log equations + the reference anchor row (the
    /// internal seam the G3③ tests drive directly). Rows are `imageCount`
    /// wide; the last row is the anchor (weight `anchorWeight` at
    /// `reference`, value 0).
    static func equations(
        from planes: [PanoGainSamplePlane], reference: Int
    ) -> (matrix: [[Double]], values: [Double]) {
        precondition(!planes.isEmpty, "no sample planes")
        precondition(
            planes.allSatisfy {
                $0.width == planes[0].width && $0.height == planes[0].height
            }, "sample planes must share the canvas size")
        var matrix: [[Double]] = []
        var values: [Double] = []
        let pixelCount = planes[0].luma.count
        for i in planes.indices {
            for j in (i + 1)..<planes.count {
                var ratios: [Double] = []
                ratios.reserveCapacity(pixelCount)
                for k in 0..<pixelCount {
                    guard planes[i].valid[k], planes[j].valid[k] else {
                        continue
                    }
                    let li = Double(planes[i].luma[k])
                    let lj = Double(planes[j].luma[k])
                    guard li > Double(gateLow), li < Double(gateHigh),
                          lj > Double(gateLow), lj < Double(gateHigh)
                    else { continue }
                    ratios.append(log(lj / li))
                }
                guard ratios.count >= minOverlapSamples else { continue }
                var row = [Double](repeating: 0, count: planes.count)
                row[i] = 1
                row[j] = -1
                matrix.append(row)
                values.append(PanoCamera.median(ratios))
            }
        }
        var anchor = [Double](repeating: 0, count: planes.count)
        anchor[reference] = anchorWeight
        matrix.append(anchor)
        values.append(0)
        return (matrix, values)
    }

    // MARK: - The min-norm least-squares solve (checker O2)

    /// The SVD min-norm lstsq via Accelerate `dgelsd` (the header note —
    /// the disconnected-component safety). rcond = −1 (machine precision —
    /// the numpy `rcond=None` semantics). nil when LAPACK reports failure.
    static func solveLstsq(
        matrix: [[Double]], values: [Double], imageCount: Int
    ) -> [Double]? {
        let rows = values.count
        guard rows >= 1, imageCount >= 1 else { return nil }
        // Column-major A (LAPACK order) + B (ldb ≥ max(m, n)).
        var a = [Double](repeating: 0, count: rows * imageCount)
        for (r, row) in matrix.enumerated() {
            for c in 0..<imageCount {
                a[c * rows + r] = row[c]
            }
        }
        let ldb = max(rows, imageCount)
        var b = values
        b.append(
            contentsOf: [Double](
                repeating: 0, count: ldb - values.count))
        var s = [Double](repeating: 0, count: min(rows, imageCount))
        var rank: __CLPK_integer = 0
        var m = __CLPK_integer(rows)
        var n = __CLPK_integer(imageCount)
        var nrhs = __CLPK_integer(1)
        var lda = m
        var ldbInt = __CLPK_integer(ldb)
        var rcond = -1.0
        var info: __CLPK_integer = 0
        // The workspace query (lwork = −1; the optimal iwork size returns
        // in iwork[0]).
        var work = [Double](repeating: 0, count: 1)
        var iwork = [__CLPK_integer](repeating: 0, count: 1)
        var lwork: __CLPK_integer = -1
        dgelsd_(
            &m, &n, &nrhs, &a, &lda, &b, &ldbInt, &s, &rcond, &rank,
            &work, &lwork, &iwork, &info)
        guard info == 0, work[0].isFinite, work[0] > 0, iwork[0] > 0 else {
            return nil
        }
        lwork = __CLPK_integer(work[0])
        work = [Double](repeating: 0, count: Int(lwork))
        iwork = [__CLPK_integer](repeating: 0, count: Int(iwork[0]))
        // Fresh operands (the query must not consume them).
        for (r, row) in matrix.enumerated() {
            for c in 0..<imageCount {
                a[c * rows + r] = row[c]
            }
        }
        b = values
        b.append(
            contentsOf: [Double](
                repeating: 0, count: ldb - values.count))
        dgelsd_(
            &m, &n, &nrhs, &a, &lda, &b, &ldbInt, &s, &rcond, &rank,
            &work, &lwork, &iwork, &info)
        guard info == 0 else { return nil }
        return Array(b[0..<imageCount])
    }

    // MARK: - The entry (merge.py:272; the leg's gains segment)

    /// The joint solve + the ±0.5 exp clip. `clipped` = any log-domain
    /// solution exceeded the clip (the leg's warning record). A degenerate
    /// solve degrades to all-identity gains (honest, never NaN).
    public static func gains(
        planes: [PanoGainSamplePlane], reference: Int
    ) -> (gains: [Double], clipped: Bool) {
        let (matrix, values) = equations(from: planes, reference: reference)
        guard let solution = solveLstsq(
            matrix: matrix, values: values, imageCount: planes.count),
              solution.allSatisfy({ $0.isFinite })
        else {
            return (planes.map { _ in 1.0 }, false)
        }
        let clipped = solution.contains { abs($0) > clipLimit }
        let gains = solution.map { exp(min(max($0, -clipLimit), clipLimit)) }
        return (gains, clipped)
    }
}
