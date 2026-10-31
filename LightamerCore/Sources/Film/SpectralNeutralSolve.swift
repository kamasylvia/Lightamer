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
}
