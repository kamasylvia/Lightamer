import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralNeutralSolve (Plan M8-3+ T1) — the build-time neutral-CC solve
// extracted as a static pure function (R-M83P-3's seam).
//
// The 2D Newton ladder over (mCC, yCC) drove the mid-gray log-channel
// ratios to zero (C neutral-fixed at 0) — moved here VERBATIM from
// `SpectralBuildEngine.build`'s :720-750 body (the fma-identical form:
// the engine's nested `logRatios`/`illumPrintFor`/`printRaw` closures
// re-homed as the solve's inputs, the iteration order untouched). The
// engine keeps the pinned-branch judgment (`parameters.printCC != nil`
// → pinned verbatim, clamped=false, no solve); ONLY the free branch
// calls this function.
//
// Inputs: the mid-gray density spectrum (CC-independent — it lives
// upstream of the enlarger head), the enlarger SPD, the dichroic table,
// the print sensitivities, the seed and the dial domain. Outputs: the
// (m, y) pair + the clamped flag (either dial's final value touches the
// domain wall within 1e-9) + the terminal residual + the round count.
// The T2 conservation fallback consumes `clamped`; the panel's disclosed
// face reads it through `tables.clamped`.
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralNeutralSolve {

    /// The dial domain (OQ-M83-2: [0, 250] is FROZEN — the physical
    /// enlarger-head dial range; evidence B proved the wall's outside
    /// holds no light, so widening is a placebo).
    public static let dialLo = 0.0
    public static let dialHi = 250.0

    /// The legacy seed (the pre-T1 verbatim behavior — nil neutralSeed
    /// resolves here).
    public static let legacySeed = (m: 50.0, y: 50.0)

    /// The ladder constants (the :720-750 body's verbatim values).
    public static let rounds = 32
    public static let finiteDifferenceEps = 1e-4
    public static let residualBreak = 1e-12
    public static let stepBreak = 1e-10
    public static let determinantFloor = 1e-300
    /// The wall-touch tolerance (a dial within this of the wall counts
    /// as touching — the clamped face's judgment band).
    public static let wallTouchTolerance = 1e-9

    /// The solve's single output (the pair + the clamped flag + the
    /// terminal residual + the rounds the ladder ran).
    public struct Solution: Sendable, Equatable {
        public let m: Double
        public let y: Double
        public let clamped: Bool
        /// The terminal |r.x| + |r.y| (the convergence metric face).
        public let residual: Double
        /// The ladder rounds consumed (the round-verdict face — T1's
        /// 32→16 decision reads this across the 28-pair probe).
        public let roundsUsed: Int
    }

    /// The 2D Newton ladder (the :732-748 loop verbatim — same order,
    /// same breaks, same clamps; `illumFor` re-homes the engine's
    /// `illumPrintFor(cc:_:)` nested closure).
    ///
    /// - Parameters:
    ///   - midgrayDS: the mid-gray density spectrum (81, CC-independent).
    ///   - printSens: the paper's print sensitivities ([λ][c]).
    ///   - illuminant: the enlarger SPD on the engine axis.
    ///   - dichroic: the dichroic transmissions ([λ][c]).
    ///   - seed: the (m, y) start (nil = the legacy (50, 50)).
    public static func solve(
        midgrayDS: [Double], printSens: [[Double]],
        illuminant: [Double], dichroic: [[Double]],
        seed: (m: Double, y: Double)? = nil
    ) -> Solution {
        let axisCount = midgrayDS.count

        func illumFor(cc m: Double, _ y: Double) -> [Double] {
            let cc = SIMD3<Double>(0, m, y)
            let dim = (0..<3).map { c -> Double in
                1.0 - pow(10.0, -cc[c] / 100.0)
            }
            return (0..<axisCount).map { l -> Double in
                var total = 1.0
                for c in 0..<3 {
                    let f = dichroic[l][c]
                    total *= 1.0 - (1.0 - f) * dim[c]
                }
                return illuminant[l] * total
            }
        }

        func printRaw(
            _ ds: [Double], _ illum: [Double]
        ) -> SIMD3<Double> {
            var raw = SIMD3<Double>.zero
            for l in 0..<axisCount {
                var light = illum[l] * pow(10.0, -ds[l])
                if !(light.isFinite) { light = 0.0 }
                raw.x += light * printSens[l][0]
                raw.y += light * printSens[l][1]
                raw.z += light * printSens[l][2]
            }
            return raw
        }

        func logRatios(_ illum: [Double]) -> SIMD2<Double> {
            let raw = printRaw(midgrayDS, illum)
            return SIMD2<Double>(
                log(raw.y / max(raw.x, 1e-300)),
                log(raw.z / max(raw.x, 1e-300)))
        }

        var m = seed?.m ?? legacySeed.m
        var y = seed?.y ?? legacySeed.y
        let eps = finiteDifferenceEps
        var residual = Double.infinity
        var used = 0
        for _ in 0..<rounds {
            let r = logRatios(illumFor(cc: m, y))
            residual = abs(r.x) + abs(r.y)
            used += 1
            if residual < residualBreak { break }
            let rm = logRatios(illumFor(cc: m + eps, y))
            let ry = logRatios(illumFor(cc: m, y + eps))
            let dMdx = (rm.x - r.x) / eps
            let dYdx = (ry.x - r.x) / eps
            let dMdy = (rm.y - r.y) / eps
            let dYdy = (ry.y - r.y) / eps
            let det = dMdx * dYdy - dYdx * dMdy
            guard det.isFinite, abs(det) > determinantFloor else { break }
            let dm = (-r.x * dYdy + r.y * dYdx) / det
            let dy = (-r.y * dMdx + r.x * dMdy) / det
            m = min(max(m + dm, dialLo), dialHi)
            y = min(max(y + dy, dialLo), dialHi)
            if max(abs(dm), abs(dy)) < stepBreak { break }
        }
        let tol = wallTouchTolerance
        let clamped = min(m - dialLo, dialHi - m) <= tol
            || min(y - dialLo, dialHi - y) <= tol
        return Solution(
            m: m, y: y, clamped: clamped, residual: residual,
            roundsUsed: used)
    }

    // MARK: - T2: the conservation fallback (OQ-M83-1 ②)

    /// The wall the solve touched (nil = interior convergence — the
    /// fallback never runs). The fallback pins the touched dial and
    /// re-optimizes the free dial in 1D (golden-section, Float64).
    public enum Wall: Sendable, Equatable {
        case mLo, mHi, yLo, yHi
    }

    /// The fallback's single output: the wall-pinned pair + the
    /// channel-affine normalization gain (the geometric-mean归一's
    /// per-channel twin — safe pairs ride ones, bit-identical).
    public struct Fallback: Sendable, Equatable {
        public let m: Double
        public let y: Double
        /// The per-channel mid-gray normalization gain (midgray raw's
        /// geometric mean ÷ channel raw — the residual compensation).
        public let channelGain: SIMD3<Double>
        /// The post-fallback residual (must sit below the clamped
        /// point's residual — the A1 monotonic gate).
        public let residual: Double
    }

    /// The golden-section 1D line search (40 rounds Float64 — the
    /// wall-interior optimum of the free dial at the pinned wall).
    public static func wallLineSearch(
        wall: Wall, fixed: Double, otherSeed: Double,
        midgrayDS: [Double], printSens: [[Double]],
        illuminant: [Double], dichroic: [[Double]]
    ) -> (value: Double, residual: Double) {
        let axisCount = midgrayDS.count
        func illumFor(cc m: Double, _ y: Double) -> [Double] {
            let cc = SIMD3<Double>(0, m, y)
            let dim = (0..<3).map { c -> Double in
                1.0 - pow(10.0, -cc[c] / 100.0)
            }
            return (0..<axisCount).map { l -> Double in
                var total = 1.0
                for c in 0..<3 {
                    total *= 1.0 - (1.0 - dichroic[l][c]) * dim[c]
                }
                return illuminant[l] * total
            }
        }
        func residualAt(m: Double, y: Double) -> Double {
            var raw = SIMD3<Double>.zero
            let illum = illumFor(cc: m, y)
            for l in 0..<axisCount {
                var light = illum[l] * pow(10.0, -midgrayDS[l])
                if !(light.isFinite) { light = 0.0 }
                raw.x += light * printSens[l][0]
                raw.y += light * printSens[l][1]
                raw.z += light * printSens[l][2]
            }
            return abs(log(raw.y / max(raw.x, 1e-300)))
                + abs(log(raw.z / max(raw.x, 1e-300)))
        }
        // The free dial's search interval: the full domain narrowed
        // around the seed (the wall point's free coordinate ± 60 CC,
        // clamped to the domain — the optimum sits near the wall point).
        var lo = max(dialLo, otherSeed - 60.0)
        var hi = min(dialHi, otherSeed + 60.0)
        let gr = 0.6180339887498949
        var c = hi - gr * (hi - lo)
        var d = lo + gr * (hi - lo)
        func at(_ v: Double) -> Double {
            switch wall {
            case .mLo, .mHi: return residualAt(m: fixed, y: v)
            case .yLo, .yHi: return residualAt(m: v, y: fixed)
            }
        }
        var fc = at(c), fd = at(d)
        for _ in 0..<40 {
            if fc < fd {
                hi = d; d = c; fd = fc; c = hi - gr * (hi - lo); fc = at(c)
            } else {
                lo = c; c = d; fc = fd; d = lo + gr * (hi - lo); fd = at(d)
            }
        }
        let value = (lo + hi) / 2.0
        return (value, at(value))
    }

    /// The wall the solution touched (the argmin face — the dial whose
    /// final value sits nearest the wall, ties → Y).
    public static func touchedWall(_ solution: Solution) -> Wall? {
        guard solution.clamped else { return nil }
        let dmLo = solution.m - dialLo, dmHi = dialHi - solution.m
        let dyLo = solution.y - dialLo, dyHi = dialHi - solution.y
        let mDist = min(dmLo, dmHi), yDist = min(dyLo, dyHi)
        if yDist <= mDist {
            return (solution.y - dialLo) <= (dialHi - solution.y)
                ? .yLo : .yHi
        }
        return (solution.m - dialLo) <= (dialHi - solution.m)
            ? .mLo : .mHi
    }

    /// The conservation fallback: the wall-pinned 1D optimum + the
    /// channel-affine gain. Safe solutions (clamped=false) answer nil —
    /// the caller keeps the verbatim path (the zero-drift proof).
    public static func fallback(
        solution: Solution,
        midgrayDS: [Double], printSens: [[Double]],
        illuminant: [Double], dichroic: [[Double]]
    ) -> Fallback? {
        guard let wall = touchedWall(solution) else { return nil }
        let fixed: Double
        let seed: Double
        switch wall {
        case .mLo: fixed = dialLo; seed = solution.y
        case .mHi: fixed = dialHi; seed = solution.y
        case .yLo: fixed = dialLo; seed = solution.m
        case .yHi: fixed = dialHi; seed = solution.m
        }
        let searched = wallLineSearch(
            wall: wall, fixed: fixed, otherSeed: seed,
            midgrayDS: midgrayDS, printSens: printSens,
            illuminant: illuminant, dichroic: dichroic)
        let (m, y): (Double, Double)
        switch wall {
        case .mLo, .mHi: (m, y) = (fixed, searched.value)
        case .yLo, .yHi: (m, y) = (searched.value, fixed)
        }
        // The channel-affine gain: the mid-gray raw at the fallback pair
        // normalized by its own geometric mean (per-channel — the safe
        // pairs' gain==ones face is the identity member).
        var raw = SIMD3<Double>.zero
        let dim = (0..<3).map { c -> Double in
            1.0 - pow(10.0, -SIMD3<Double>(0, m, y)[c] / 100.0)
        }
        for l in 0..<midgrayDS.count {
            var total = 1.0
            for c in 0..<3 {
                total *= 1.0 - (1.0 - dichroic[l][c]) * dim[c]
            }
            var light = illuminant[l] * total * pow(10.0, -midgrayDS[l])
            if !(light.isFinite) { light = 0.0 }
            raw.x += light * printSens[l][0]
            raw.y += light * printSens[l][1]
            raw.z += light * printSens[l][2]
        }
        let gm = pow(
            max(raw.x, 1e-300) * max(raw.y, 1e-300) * max(raw.z, 1e-300),
            1.0 / 3.0)
        let gain = SIMD3<Double>(
            gm / max(raw.x, 1e-300), gm / max(raw.y, 1e-300),
            gm / max(raw.z, 1e-300))
        return Fallback(m: m, y: y, channelGain: gain, residual: searched.residual)
    }

    // MARK: - T2: the reversal explicit route (R-M83P-1)

    /// The reversal print-mode id (the FilmRecord.reversalPrintMode
    /// vocabulary — unknown strings degrade to nil/legacy at the record
    /// face, never here).
    public static let directPositiveMode = "direct-positive"

    /// The direct-positive solve: the SAME Newton ladder, but the target
    /// is the SCAN-leg output neutrality (the reversal density's polarity
    /// is inverted — the print-exposure target is meaningless). Inputs
    /// are the scan-leg faces (paper base/channel densities + viewing
    /// SPD + CMFs + norm): the ladder drives the mid-gray scan XYZ's
    /// log-channel ratios to zero over the (m, y) dials — which ride the
    /// print-exposure light exactly as in the legacy arm (the dials'
    /// physical seat is unchanged; only the TARGET moved downstream).
    public static func solveDirectPositive(
        midgrayDS: [Double], printSens: [[Double]],
        scanBase: [Double], scanChanDens: [[Double]],
        illuminant: [Double], viewSPD: [Double], cmfs: [[Double]],
        xyzNorm: Double, dichroic: [[Double]],
        seed: (m: Double, y: Double)? = nil
    ) -> Solution {
        let axisCount = midgrayDS.count
        func illumFor(cc m: Double, _ y: Double) -> [Double] {
            let cc = SIMD3<Double>(0, m, y)
            let dim = (0..<3).map { c -> Double in
                1.0 - pow(10.0, -cc[c] / 100.0)
            }
            return (0..<axisCount).map { l -> Double in
                var total = 1.0
                for c in 0..<3 {
                    total *= 1.0 - (1.0 - dichroic[l][c]) * dim[c]
                }
                return illuminant[l] * total
            }
        }
        // The scan-leg neutrality ratios at one (m, y): the print raw
        // (mid-gray through the dialed light) → print-leg log face →
        // paper curves are BYPASSED (the scan target needs only the
        // print-density RATIOS — the curves are monotone per-channel, so
        // ratio-zero upstream = ratio-zero downstream) → scan XYZ ratios.
        func logRatios(_ illum: [Double]) -> SIMD2<Double> {
            var praw = SIMD3<Double>.zero
            for l in 0..<axisCount {
                var light = illum[l] * pow(10.0, -midgrayDS[l])
                if !(light.isFinite) { light = 0.0 }
                praw.x += light * printSens[l][0]
                praw.y += light * printSens[l][1]
                praw.z += light * printSens[l][2]
            }
            // The print-density proxy (log face) → scan densities →
            // viewing XYZ (the scan-leg integral verbatim).
            let plog = SIMD3<Double>(
                log10(max(praw.x, 0.0) + 1e-10),
                log10(max(praw.y, 0.0) + 1e-10),
                log10(max(praw.z, 0.0) + 1e-10))
            var xyz = SIMD3<Double>.zero
            for l in 0..<axisCount {
                var ds = scanBase[l]
                for c in 0..<3 { ds += scanChanDens[l][c] * plog[c] }
                var light = viewSPD[l] * pow(10.0, -ds)
                if !(light.isFinite) { light = 0.0 }
                xyz.x += light * cmfs[l][0]
                xyz.y += light * cmfs[l][1]
                xyz.z += light * cmfs[l][2]
            }
            return SIMD2<Double>(
                log((xyz.y / xyzNorm) / max(xyz.x / xyzNorm, 1e-300)),
                log((xyz.z / xyzNorm) / max(xyz.x / xyzNorm, 1e-300)))
        }
        var m = seed?.m ?? legacySeed.m
        var y = seed?.y ?? legacySeed.y
        let eps = finiteDifferenceEps
        var residual = Double.infinity
        var used = 0
        for _ in 0..<rounds {
            let r = logRatios(illumFor(cc: m, y))
            residual = abs(r.x) + abs(r.y)
            used += 1
            if residual < residualBreak { break }
            let rm = logRatios(illumFor(cc: m + eps, y))
            let ry = logRatios(illumFor(cc: m, y + eps))
            let dMdx = (rm.x - r.x) / eps
            let dYdx = (ry.x - r.x) / eps
            let dMdy = (rm.y - r.y) / eps
            let dYdy = (ry.y - r.y) / eps
            let det = dMdx * dYdy - dYdx * dMdy
            guard det.isFinite, abs(det) > determinantFloor else { break }
            let dm = (-r.x * dYdy + r.y * dYdx) / det
            let dy = (-r.y * dMdx + r.x * dMdy) / det
            m = min(max(m + dm, dialLo), dialHi)
            y = min(max(y + dy, dialLo), dialHi)
            if max(abs(dm), abs(dy)) < stepBreak { break }
        }
        let tol = wallTouchTolerance
        let clamped = min(m - dialLo, dialHi - m) <= tol
            || min(y - dialLo, dialHi - y) <= tol
        return Solution(
            m: m, y: y, clamped: clamped, residual: residual,
            roundsUsed: used)
    }
}
