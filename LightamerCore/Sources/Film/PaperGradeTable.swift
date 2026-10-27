import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PaperGradeTable (Plan M9-2 T2) — the variable-contrast grade presets.
//
// A COMPUTED piece, not a copied table (X-M92-2): each grade's
// (magenta CC, yellow CC, exposure trim) is fitted through OUR OWN
// spectral chain against the ISO Range figures printed in the paper's
// own datasheet (MULTIGRADE RC technical information, ISO 6846:1992 —
// MG IV RC DELUXE: 00=180, 0=160, 1=130, 2=110, 3=90, 4=60, 5=40, the
// unfiltered paper ≈ 110). The dial convention follows the plan: grades
// 00-2 ride the YELLOW dial (yellow absorbs blue — the HIGH-contrast
// blue emulsion loses exposure → SOFTER), grades 3-5 ride the MAGENTA
// dial (magenta absorbs green — the LOW-contrast green emulsion loses
// exposure → HARDER). Both dials drive R monotonically: yellow up → R
// up, magenta up → R down.
//
// MODEL (documented, self-contained Double math over the same faces the
// build engine uses — dichroic transmissions + the paper's spectral
// sensitivities + the per-channel fan curves):
//   • The enlarger light for a CC pair rides the engine's dichroic face
//     (`illumPrintFor` semantics, re-derived here compactly).
//   • Paper channel c's exposure: E_c = Σλ illum(λ)·paperSens_c(λ)
//     (the BW negative's transmission spectrum is channel-flat — it
//     cancels in the RANGE ratio and is carried by the exposure trim).
//   • The blended paper response at log-exposure offset t:
//     D(t) = mean_c curve_c(t + logE_c0 − logE_c) — the same channel
//     mean the scan leg applies through the neutral [1/3,1/3,1/3]
//     silver split.
//   • The modeled ISO range R(dial): the log10 exposure span between
//     D = fog+0.04 and D = fog+0.9 on the blended curve — bisected per
//     grade against the datasheet R values.
// The pure function is deterministic; `PaperGradeTableTests` pins the
// round-trip against paper_grades.json (the persisted record of the
// fit, regenerated alongside).
// ─────────────────────────────────────────────────────────────────────────────

/// The seven Multigrade grade keys, verbatim (MAJ-1: "00" and "0" are
/// DISTINCT grades — Int encodings are ambiguous, never introduce them).
public enum PaperGradeTable {

    public static let gradeKeys: [String] =
        ["00", "0", "1", "2", "3", "4", "5"]

    /// The datasheet ISO Range targets (log10 × 100), MG IV RC DELUXE.
    public static let isoRangeTargets: [String: Double] = [
        "00": 180, "0": 160, "1": 130, "2": 110,
        "3": 90, "4": 60, "5": 40,
    ]

    /// One grade preset: the pinned printCC pair (C stays 0) and the
    /// mid-gray exposure trim (EV — the speed change the datasheet's
    /// paper-speed row documents, refit through the modeled mid-gray).
    public struct GradePreset: Codable, Hashable, Sendable {
        public var magentaCC: Double
        public var yellowCC: Double
        public var exposureEv: Double
        public init(magentaCC: Double, yellowCC: Double, exposureEv: Double) {
            self.magentaCC = magentaCC
            self.yellowCC = yellowCC
            self.exposureEv = exposureEv
        }
    }

    // MARK: - The fit

    /// The memoized fit (per stock id — the fit is a pure function of
    /// the paper profile; the seconds-scale bisection family runs once
    /// per paper per session). The box form follows BakeFixtureBox's
    /// @unchecked Sendable precedent (Swift 6 strict concurrency rejects
    /// static mutable globals).
    private static let cacheBox = GradeCacheBox()
    private final class GradeCacheBox: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: [String: GradePreset]] = [:]
        func table(id: String, make: () -> [String: GradePreset]) -> [String: GradePreset] {
            lock.lock()
            defer { lock.unlock() }
            if let hit = tables[id] { return hit }
            let made = make()
            tables[id] = made
            return made
        }
    }
    public static func cachedTable(paper: FilmProfile) -> [String: GradePreset] {
        let id = paper.info.stock ?? paper.info.name ?? "?"
        return cacheBox.table(id: id) { fitTable(paper: paper) }
    }

    /// Fit the full grade table for one film/paper pair (the film's
    /// density spectrum is channel-flat for the BW family — the negative
    /// term cancels in the range; the paper carries the whole response).
    public static func fitTable(paper: FilmProfile) -> [String: GradePreset] {
        var table: [String: GradePreset] = [:]
        let neutralPreset = GradePreset(magentaCC: 0, yellowCC: 0, exposureEv: 0)
        for key in gradeKeys {
            table[key] = fitGrade(key, paper: paper, neutral: neutralPreset)
        }
        return table
    }

    /// One grade: bisect the responsible dial (Y for 00-2, M for 3-5)
    /// until the modeled ISO range matches the grade's CALIBRATED target.
    ///
    /// Calibration layer (DECISIONS-logged): the modeled blend's contrast
    /// SWING is narrower than the datasheet paper's (the traced fan's
    /// slope difference + the blind channel's dilution + the emulsion
    /// bands' spectral overlap all shrink it). The dial→R map is strictly
    /// MONOTONE in the model, so each family's dial is fitted against the
    /// datasheet R targets rescaled AFFINELY into the model's reachable
    /// band: neutral (dial 0) anchors to the datasheet's unfiltered R
    /// (110), the dial extreme anchors to the family's endpoint (00→180,
    /// 5→40). The monotone physics is ours; the absolute swing is the
    /// datasheet's.
    static func fitGrade(
        _ key: String, paper: FilmProfile, neutral: GradePreset
    ) -> GradePreset {
        guard PaperGradeTable.isoRangeTargets[key] != nil else { return neutral }
        let rNeutral = modeledIsoRange(m: 0, y: 0, paper: paper)
        let rYellowMax = modeledIsoRange(m: 0, y: 200, paper: paper)
        let rMagentaMin = modeledIsoRange(m: 200, y: 0, paper: paper)
        let unfilteredR = 110.0
        let softFamily = key == "00" || key == "0" || key == "1" || key == "2"
        var lo = 0.0, hi = 200.0, best = 0.0
        if softFamily {
            // Yellow: R rises with the dial. Calibrated target:
            // rNeutral + (target − unfilteredR)·(rYellowMax − rNeutral)/(180 − 110)
            let scale = (rYellowMax - rNeutral) / (180.0 - unfilteredR)
            let target = rNeutral
                + (isoRangeTargets[key]! - unfilteredR) * scale
            for _ in 0..<48 {
                let mid = 0.5 * (lo + hi)
                let r = modeledIsoRange(m: 0, y: mid, paper: paper)
                if r < target { best = mid; lo = mid } else { hi = mid }
            }
            let ev = exposureTrim(m: 0, y: best, paper: paper)
            return GradePreset(magentaCC: 0, yellowCC: best, exposureEv: ev)
        } else {
            // Magenta: R falls with the dial. Calibrated target:
            // rNeutral − (unfilteredR − target)·(rNeutral − rMagentaMin)/(110 − 40)
            let scale = (rNeutral - rMagentaMin) / (unfilteredR - 40.0)
            let target = rNeutral
                - (unfilteredR - isoRangeTargets[key]!) * scale
            for _ in 0..<48 {
                let mid = 0.5 * (lo + hi)
                let r = modeledIsoRange(m: mid, y: 0, paper: paper)
                if r > target { best = mid; lo = mid } else { hi = mid }
            }
            let ev = exposureTrim(m: best, y: 0, paper: paper)
            return GradePreset(magentaCC: best, yellowCC: 0, exposureEv: ev)
        }
    }

    // MARK: - The model (compact re-derivations of the engine faces)

    /// The dichroic-filtered enlarger spectrum for a CC pair — the same
    /// construction as SpectralBuildEngine.illumPrintFor (C fixed 0).
    static func enlargerSpectrum(m: Double, _ y: Double, axis: [Double],
                                 spd: [Double]) -> [Double] {
        let cc = SIMD3<Double>(0, m, y)
        let dim = (0..<3).map { 1.0 - pow(10.0, -cc[$0] / 100.0) }
        return (0..<axis.count).map { l in
            var total = 1.0
            for c in 0..<3 {
                let f = SpectralConstantsData.dichroicTransmissions[l][c]
                total *= 1.0 - (1.0 - f) * dim[c]
            }
            return spd[l] * total
        }
    }

    /// The blended characteristic's ISO range for a CC pair.
    static func modeledIsoRange(m: Double, y: Double, paper: FilmProfile) -> Double {
        let axis = paper.wavelengths.map { Double($0) }
        guard let logSens = paper.logSensitivity else { return 175 }
        let base = SpectralConstantsData.illuminants["TH-KG3"]
            ?? [Double](repeating: 1, count: axis.count)
        let spd = axis.count == base.count
            ? base : [Double](repeating: base.last ?? 1, count: axis.count)
        let illum = enlargerSpectrum(m: m, y, axis: axis, spd: spd)
        // Per-channel log exposures against the paper sensitivities.
        var logE = [Double](repeating: 0, count: 3)
        for c in 0..<3 {
            var sum = 0.0
            for l in 0..<axis.count {
                let s = pow(10.0, Double(logSens[l][c]))
                sum += illum[l] * s
            }
            logE[c] = log10(max(sum, 1e-300))
        }
        // ACTIVE-channel selection: the blind third emulsion (safelight
        // block, exposure ~1e-6 of the visible pair) must NOT dilute the
        // blend — its curve contribution pins at fog and drags the mean,
        // collapsing the dial sensitivity (measured at the -6 blind
        // floor: the yellow dial moved the modeled range by <1%). The
        // physical contrast mechanism lives in the VISIBLE pair (the
        // blue/high and green/low emulsions); a channel more than 2
        // decades below the strongest is inert paper base.
        var active: [Int] = []
        let strongest = logE.max() ?? 0
        for c in 0..<3 where logE[c] > strongest - 2.0 {
            active.append(c)
        }
        if active.isEmpty { active = [0] }
        let weight = 1.0 / Double(active.count)
        // The blended curve: mean over the ACTIVE channels of each
        // channel's own density curve at its shifted log exposure.
        let grid = paper.logExposure
        func blended(_ t: Double) -> Double {
            var acc = 0.0
            for c in active {
                let shifted = t + logE[c] - logE[active[0]]
                acc += weight * sampleCurve(grid, paper.densityCurves, channel: c,
                                             at: shifted)
            }
            return acc
        }
        // ISO 6846-style range, adapted to the blended curve's own
        // dynamic span (the blind third channel pins part of the mean —
        // the absolute D90 of the raw paper is unreachable in the blend,
        // so the range rides the blend's fog-to-max span: D_lo = fog+4%
        // of span, D_hi = fog+80% of span. The SLOPE differences — what
        // the dial moves — survive the adaptation; the datasheet targets
        // are matched through a proportional rescale below).
        var fog = Double.greatestFiniteMagnitude
        var dmax = -Double.greatestFiniteMagnitude
        for i in 0..<grid.count {
            let d = blended(Double(grid[i]))
            fog = min(fog, d); dmax = max(dmax, d)
        }
        let span = dmax - fog
        guard span > 0.1 else { return 175 }
        let lo = invert(grid, fog + 0.04 * span, blended)
        let hi = invert(grid, fog + 0.80 * span, blended)
        guard let lo, let hi, hi > lo else { return 175 }
        return (hi - lo) * 100.0
    }

    /// The mid-gray exposure trim in EV for a CC pair relative to the
    /// neutral head (the paper-speed row's modeled face: more filtration
    /// = less light = positive EV trim).
    static func exposureTrim(m: Double, y: Double, paper: FilmProfile) -> Double {
        let base = modeledMidgrayLight(0, 0, paper: paper)
        let lit = modeledMidgrayLight(m, y, paper: paper)
        guard base > 0, lit > 0 else { return 0 }
        return log2(base / lit)
    }

    static func modeledMidgrayLight(
        _ m: Double, _ y: Double, paper: FilmProfile
    ) -> Double {
        let axis = paper.wavelengths.map { Double($0) }
        guard let logSens = paper.logSensitivity else { return 1 }
        let base = SpectralConstantsData.illuminants["TH-KG3"]
            ?? [Double](repeating: 1, count: axis.count)
        let spd = axis.count == base.count
            ? base : [Double](repeating: base.last ?? 1, count: axis.count)
        let illum = enlargerSpectrum(m: m, y, axis: axis, spd: spd)
        var geometric = 0.0
        for c in 0..<3 {
            var sum = 0.0
            for l in 0..<axis.count {
                sum += illum[l] * pow(10.0, Double(logSens[l][c]))
            }
            geometric += log(max(sum, 1e-300))
        }
        return exp(geometric / 3.0)
    }

    // MARK: - Small helpers

    static func sampleCurve(
        _ grid: [Float], _ curves: [[Float]], channel: Int, at x: Double
    ) -> Double {
        let n = grid.count
        if x <= Double(grid[0]) { return Double(curves[0][channel]) }
        if x >= Double(grid[n - 1]) { return Double(curves[n - 1][channel]) }
        var lo = 0, hi = n - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if Double(grid[mid]) <= x { lo = mid } else { hi = mid }
        }
        let x0 = Double(grid[lo]), x1 = Double(grid[hi])
        let t = (x - x0) / max(x1 - x0, 1e-12)
        let d0 = Double(curves[lo][channel]), d1 = Double(curves[hi][channel])
        return d0 + (d1 - d0) * t
    }

    static func invert(
        _ grid: [Float], _ level: Double, _ f: (Double) -> Double
    ) -> Double? {
        // First crossing of `level` scanning left→right (the ISO toe
        // convention) on a coarse scan + one linear refinement.
        let n = grid.count
        let step = 0.02
        var x = Double(grid[0])
        var prev = f(x)
        while x < Double(grid[n - 1]) {
            x += step
            let v = f(x)
            if prev < level && v >= level {
                let t = (level - prev) / max(v - prev, 1e-12)
                return x - step + t * step
            }
            prev = v
        }
        return nil
    }
}
