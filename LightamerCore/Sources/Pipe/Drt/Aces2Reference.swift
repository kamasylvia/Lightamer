import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// Aces2Reference — the Float64 reference implementation of the ACES 2.0
// Output Transform (Plan M2-6-2 T3, KD-5). THE algorithm-structure authority
// for the aces20 method: the Metal kernel (Aces2Kernels.metal) mirrors these
// stages stage-for-stage and the golden tests pin the parity.
//
// PORTED FROM aces-core (upstream SHA 069b0bc3e1f6c62820f19fdae2fecec3f4fc0
// f80, v2.0 main, 2026-09-01; Apache-2.0 — Portions Copyright Contributors
// to the ACES Project; see NOTICE):
//   • `lib/Lib.Academy.Tonescale.ctl` — TSParams/init_TSParams (:14-74),
//     tonescale_fwd/inv (:77-97).
//   • `lib/Lib.Academy.OutputTransform.ctl` — the compression/tonemap/gamut
//     function family (:155-1671), the ODTParams table builders
//     (init_ODTParams :1632-1672 + the make_*/build_* families), and
//     outputTransform_fwd (:1674-1688).
// Each function cites its upstream anchor. NOT ported (v1 subset, KD-1):
//   outputTransform_inv (forward-only render path), hueDependentUpperHull
//   Gamma (dead in the upstream forward path), the LMT creative family,
//   the ACES 1.x RRT/ODT hard tables.
//
// ═══ ALGORITHM STRUCTURE MAP (stage numbers = the shared vocabulary with
//     the kernel + golden tests; stage order = outputTransform_fwd) ═══
//
//   Pre-run (per parameter point — CPU-built tables in `Params`):
//     TSParams           (Tonescale.ctl init_TSParams :30-74)
//     input/reach/limit JMhParams (Cam16.swift — init_JMhParams)
//     limit_J_max = Y_to_J(peak, input); model_gamma_inv
//     TABLE_reach_M[362] (make_reach_m_table :1386-1440)
//     chroma constants   (sat/sat_thr/compr/chroma_compress_scale :1652-1656)
//     mid_J/focus_dist/lower_hull_gamma_inv (:1659-1662)
//     TABLE_hues[362] + TABLE_gamut_cusps[362][3]
//                        (make_uniform_hue_gamut_table :1357-1383)
//     TABLE_upper_hull_gamma[362] (:1528-1606)
//     hue_linearity_search_range (:1608-1630)
//   [0] Working-space linear Rec2020 → AP0 (ACES2065-1) — the fixed input
//       gamut (CONTEXT 衔界面; the dctl-style in_gamut menu is not exposed).
//   [1] RGC前置 (KD-3, default ON; upstream v1.3 LMT — Aces2RGC) — runs on
//       AP0 (the LMT's home space), BEFORE the ODT proper.
//   [2] clamp_AP0_to_AP1(aces, 0, ts.forward_limit) (:1677).
//   [3] RGB_to_JMh(clamped, input_params = AP0) (:1679).
//   [4] tonemap_and_compress_fwd (:526-542): J→Y→tonescale_fwd→Y→J (the
//       JMh-parameterized tonescale), then chroma_compress_fwd on M
//       (:440-490 — the M-axis purity/saturation roll-off).
//   [5] gamut_compress_fwd (:866-888 → compress_gamut :728-774): JMh
//       limiting against the limiting-gamut cusp table + the reach table.
//   [6] JMh_to_RGB(compressed, limit_params = the limiting space) (:1685).
//   [7] Peak normalization ×(100/peak) — Lightamer's EotfBox contract is
//       1.0 = peak nits (the upstream hands 1.0 = the 100-nit reference
//       white to its display encodes; the EOTF itself stays in EotfBox,
//       the M2-6-1 KD-4 separation).
// ─────────────────────────────────────────────────────────────────────────────

/// The ACES 2.0 ODT reference namespace.
enum Aces2Reference {

    // MARK: - Chroma / gamut constants (:73-90 — 逐常数断言面)

    static let chromaCompress: Double = 2.4
    static let chromaCompressFact: Double = 3.3
    static let chromaExpand: Double = 1.3
    static let chromaExpandFact: Double = 0.69
    static let chromaExpandThr: Double = 0.5
    static let smoothCusps: Double = 0.12
    static let smoothM: Double = 0.27
    static let cuspMidBlend: Double = 1.3
    static let focusGainBlend: Double = 0.3
    static let focusDistance: Double = 1.35
    static let focusDistanceScaling: Double = 1.75
    static let compressionThreshold: Double = 0.75

    // Table geometry (:42-58).
    static let tableSize = 360
    static let totalTableSize = tableSize + 2   // 362 — the wrap entries
    static let cuspCornerCount = 6
    static let totalCornerCount = cuspCornerCount + 2
    static let maxSortedCorners = 2 * cuspCornerCount
    static let reachCuspTolerance: Double = 1e-3
    static let displayCuspTolerance: Double = 1e-7
    static let gammaMinimum: Double = 0.0
    static let gammaMaximum: Double = 5.0
    static let gammaSearchStep: Double = 0.4
    static let gammaAccuracy: Double = 1e-5

    // MARK: - TSParams (Tonescale.ctl :14-74)

    /// The tonescale parameter set (`TSParams`).
    struct TSParams {
        let n: Double
        let nR: Double
        let g: Double
        let t1: Double
        let cT: Double
        let s2: Double
        let u2: Double
        let m2: Double
        let forwardLimit: Double
        let inverseLimit: Double
        let logPeak: Double

        /// `init_TSParams` (:30-74).
        init(peakLuminance: Double) {
            let n = peakLuminance
            let nR = 100.0
            let g = 1.15
            let c = 0.18
            let cD = 10.013
            let wG = 0.14
            let t1 = 0.04
            let rHitMin = 128.0
            let rHitMax = 896.0
            let rHit = rHitMin + (rHitMax - rHitMin)
                * (Foundation.log(n / nR) / Foundation.log(10000.0 / 100.0))
            let m0 = n / nR
            let m1 = 0.5 * (m0 + (m0 * (m0 + 4 * t1)).squareRoot())
            let u = Foundation.pow((rHit / m1) / ((rHit / m1) + 1), g)
            let m = m1 / u
            let wI = Foundation.log(n / 100.0) / Foundation.log(2.0)
            let cT = cD / nR * (1 + wI * wG)
            let gIp = 0.5 * (cT + (cT * (cT + 4 * t1)).squareRoot())
            let gIpp2 = -(m1 * Foundation.pow(gIp / m, 1 / g))
                / (Foundation.pow(gIp / m, 1 / g) - 1)
            let w2 = c / gIpp2
            let s2 = w2 * m1
            let u2 = Foundation.pow((rHit / m1) / ((rHit / m1) + w2), g)
            let m2 = m1 / u2
            self.n = n
            self.nR = nR
            self.g = g
            self.t1 = t1
            self.cT = cT
            self.s2 = s2
            self.u2 = u2
            self.m2 = m2
            self.forwardLimit = 8.0 * rHit
            self.inverseLimit = n / (u2 * nR)
            self.logPeak = Foundation.log10(n / nR)
        }
    }

    /// `tonescale_fwd` (:77-86) — scene-referred in, luminance (nits) out.
    static func tonescaleFwd(_ x: Double, _ ts: TSParams) -> Double {
        let f = ts.m2 * Foundation.pow(max(0.0, x) / (x + ts.s2), ts.g)
        let h = max(0.0, f * f / (f + ts.t1))
        return h * ts.nR
    }

    /// `tonescale_inv` (:88-97) — luminance (nits) in, scene-referred out.
    static func tonescaleInv(_ y: Double, _ ts: TSParams) -> Double {
        let z = max(0.0, min(ts.n / (ts.u2 * ts.nR), y))
        let h = (z + (z * (4 * ts.t1 + z)).squareRoot()) / 2
        return ts.s2 / (Foundation.pow(ts.m2 / h, 1 / ts.g) - 1)
    }

    // MARK: - J/Y bridges (:214-252 — via the JMhParams scalars)

    /// `J_to_Y` (:236-242): A = (J/100)^invCz → Ra = A_w_J·A →
    /// Y = PRC_inv(Ra)/F_L_n.
    static func jToY(_ j: Double, _ p: Aces2Cam.JMhParams) -> Double {
        let a = Aces2Cam.jToAchromatic(abs(j), invCz: p.invCz)
        let ra = p.awJ * a
        return Aces2Cam.postAdaptationCompressionInv(ra) / p.fLn
    }

    /// `Y_to_J` (:244-252): Ra = PRC_fwd(|Y|·F_L_n) →
    /// J = J_scale·(Ra/A_w_J)^cz.
    static func yToJ(_ y: Double, _ p: Aces2Cam.JMhParams) -> Double {
        let ra = Aces2Cam.postAdaptationCompressionFwd(abs(y) * p.fLn)
        return Aces2Cam.achromaticToJ(ra * p.invAwJ, cz: p.cz)
    }

    // MARK: - Table index helpers (:155-183, :350-359)

    static func huePositionInUniformTable(_ hue: Double, _ tableSize: Int) -> Int {
        Int(Aces2Cam.wrapTo360(hue) / 360.0 * Double(tableSize))
    }

    static func nextPositionInTable(_ entry: Int, _ tableSize: Int) -> Int {
        (entry + 1) % tableSize
    }

    static func baseHueForPosition(_ i: Int, _ tableSize: Int) -> Double {
        Double(i) * 360.0 / Double(tableSize)
    }

    /// `reach_M_from_table` (:350-359).
    static func reachMFromTable(_ h: Double, _ table: [Double]) -> Double {
        let base = huePositionInUniformTable(h, tableSize)
        let t = h - Double(base)
        let iLo = base + 1
        let iHi = iLo + 1
        return table[iLo] + t * (table[iHi] - table[iLo])
    }

    // MARK: - Small shapes (:361-433)

    /// `reinhard_remap` (:361-377).
    static func reinhardRemap(_ scale: Double, _ nd: Double, invert: Bool) -> Double {
        if invert {
            return nd >= 1.0 ? scale : scale * -(nd / (nd - 1))
        }
        return scale * nd / (1 + nd)
    }

    /// `midpoint` (:379-382).
    static func midpoint(_ low: Double, _ high: Double) -> Double {
        (low + high) / 2
    }

    /// `toe` (:384-410) — the k1/k2 shaper remapping x below `limit`.
    static func toe(
        _ x: Double, _ limit: Double, _ k1In: Double, _ k2In: Double,
        invert: Bool
    ) -> Double {
        if x > limit { return x }
        let k2 = max(k2In, 0.001)
        let k1 = (k1In * k1In + k2 * k2).squareRoot()
        let k3 = (limit + k1) / (limit + k2)
        if invert {
            return (x * x + k1 * x) / (k3 * (x + k2))
        }
        let minusB = k3 * x - k1
        let minusC = k2 * k3 * x
        return 0.5 * (minusB + (minusB * minusB + 4 * minusC).squareRoot())
    }

    /// `chroma_compress_norm` (:412-433) — the hue-dependent M normalizer.
    static func chromaCompressNorm(_ h: Double, _ scale: Double) -> Double {
        let hr = Aces2Cam.degreesToRadians(h)
        let a = cos(hr)
        let b = sin(hr)
        let cosHr2 = a * a - b * b
        let sinHr2 = 2.0 * a * b
        let cosHr3 = 4.0 * a * a * a - 3.0 * a
        let sinHr3 = 3.0 * b - 4.0 * b * b * b
        let m = 11.34072 * a
            + 16.46899 * cosHr2
            + 7.88380 * cosHr3
            + 14.66441 * b
            - 6.37224 * sinHr2
            + 9.19364 * sinHr3
            + 77.12896
        return m * scale
    }

    // MARK: - Chroma compression (:435-524)

    /// `chroma_compress_fwd` (:440-490) — returns (tonemapped J, M', h).
    static func chromaCompressFwd(
        _ jmh: SIMD3<Double>, _ tonemappedJ: Double, _ p: Params
    ) -> SIMD3<Double> {
        let j = jmh.x
        let m = jmh.y
        let h = jmh.z
        var mCompr = m
        if m != 0 {
            let nJ = tonemappedJ / p.limitJMax
            let snJ = max(0.0, 1 - nJ)
            let mNorm = chromaCompressNorm(h, p.chromaCompressScale)
            let limit = Foundation.pow(nJ, p.modelGammaInv)
                * reachMFromTable(h, p.tableReachM) / mNorm
            let toeLimit = limit - 0.001
            let toeSnJSat = snJ * p.sat
            let toeSqrtNJSatThr = (nJ * nJ + p.satThr).squareRoot()
            let toeNJCompr = nJ * p.compr
            // Rescale M to the tonemapped J (Hellwig model-gamma power —
            // keeps chromaticities constant).
            mCompr = m * Foundation.pow(tonemappedJ / j, p.modelGammaInv)
            // Normalize by the hue's normalizer M.
            mCompr = mCompr / mNorm
            // The reverse-toe expansion (shadow/mid saturation boost).
            mCompr = limit
                - toe(limit - mCompr, toeLimit, toeSnJSat, toeSqrtNJSatThr, invert: false)
            // The compression toe (the highlight saturation roll-off).
            mCompr = toe(mCompr, limit, toeNJCompr, snJ, invert: false)
            // Denormalize.
            mCompr = mCompr * mNorm
        }
        return SIMD3(tonemappedJ, mCompr, h)
    }

    /// `chroma_compress_inv` (:492-524).
    static func chromaCompressInv(
        _ jmhTc: SIMD3<Double>, _ j: Double, _ p: Params
    ) -> SIMD3<Double> {
        let tonemappedJ = jmhTc.x
        let mCompr = jmhTc.y
        let h = jmhTc.z
        var m = mCompr
        if mCompr != 0 {
            let nJ = tonemappedJ / p.limitJMax
            let snJ = max(0.0, 1 - nJ)
            let mNorm = chromaCompressNorm(h, p.chromaCompressScale)
            let limit = Foundation.pow(nJ, p.modelGammaInv)
                * reachMFromTable(h, p.tableReachM) / mNorm
            let toeLimit = limit - 0.001
            let toeSnJSat = snJ * p.sat
            let toeSqrtNJSatThr = (nJ * nJ + p.satThr).squareRoot()
            let toeNJCompr = nJ * p.compr
            m = mCompr / mNorm
            m = toe(m, limit, toeNJCompr, snJ, invert: true)
            m = limit - toe(limit - m, toeLimit, toeSnJSat, toeSqrtNJSatThr, invert: true)
            m = m * mNorm
            m = m * Foundation.pow(tonemappedJ / j, -p.modelGammaInv)
        }
        return SIMD3(j, m, h)
    }

    // MARK: - tonemap_and_compress (:526-560)

    /// `tonemap_and_compress_fwd` (:526-542).
    static func tonemapAndCompressFwd(
        _ jmh: SIMD3<Double>, _ p: Params
    ) -> SIMD3<Double> {
        let linear = jToY(jmh.x, p.inputParams) / Aces2Cam.refLuminance
        let tonemappedY = tonescaleFwd(linear, p.ts)
        let jTs = yToJ(tonemappedY, p.inputParams)
        return chromaCompressFwd(jmh, jTs, p)
    }

    // MARK: - Gamut compression math (:562-918)

    /// `compute_compression_vector_slope` (:562-577).
    static func compressionVectorSlope(
        _ intersectJ: Double, _ focusJ: Double, _ limitJMax: Double, _ slopeGain: Double
    ) -> Double {
        let directionScalar = intersectJ < focusJ ? intersectJ : limitJMax - intersectJ
        return directionScalar * (intersectJ - focusJ) / (focusJ * slopeGain)
    }

    /// `solve_J_intersect` (:579-604).
    static func solveJIntersect(
        _ j: Double, _ m: Double, _ focusJ: Double, _ maxJ: Double, _ slopeGain: Double
    ) -> Double {
        let mScaled = m / slopeGain
        let a = mScaled / focusJ
        if j < focusJ {
            let b = 1 - mScaled
            let c = -j
            let det = b * b - 4 * a * c
            let root = det.squareRoot()
            return -2 * c / (b + root)
        } else {
            let b = -(1 + mScaled + maxJ * a)
            let c = maxJ * mScaled + j
            let det = b * b - 4 * a * c
            let root = det.squareRoot()
            return -2 * c / (b - root)
        }
    }

    /// `smin_scaled` (:606-614).
    static func sminScaled(_ a: Double, _ b: Double, _ scaleReference: Double) -> Double {
        let sScaled = smoothCusps * scaleReference
        let h = max(sScaled - abs(a - b), 0.0) / sScaled
        return min(a, b) - h * h * h * sScaled * (1.0 / 6.0)
    }

    /// `estimate_line_and_boundary_intersection_M` (:616-639).
    static func estimateLineAndBoundaryIntersectionM(
        _ jAxisIntersect: Double, _ slope: Double, _ invGamma: Double,
        _ jMax: Double, _ mMax: Double, _ jIntersectionReference: Double
    ) -> Double {
        let normalisedJ = jAxisIntersect / jIntersectionReference
        let shiftedIntersection = jIntersectionReference
            * Foundation.pow(normalisedJ, invGamma)
        return shiftedIntersection * mMax / (jMax - slope * mMax)
    }

    /// `find_gamut_boundary_intersection` (:641-671).
    static func findGamutBoundaryIntersection(
        _ jmCusp: SIMD2<Double>, _ jMax: Double, _ gammaTopInv: Double,
        _ gammaBottomInv: Double, _ jIntersectSource: Double, _ slope: Double,
        _ jIntersectCusp: Double
    ) -> Double {
        let mBoundaryLower = estimateLineAndBoundaryIntersectionM(
            jIntersectSource, slope, gammaBottomInv, jmCusp.x, jmCusp.y, jIntersectCusp)
        let fJIntersectCusp = jMax - jIntersectCusp
        let fJIntersectSource = jMax - jIntersectSource
        let fJMcuspJ = jMax - jmCusp.x
        let mBoundaryUpper = estimateLineAndBoundaryIntersectionM(
            fJIntersectSource, -slope, gammaTopInv, fJMcuspJ, jmCusp.y, fJIntersectCusp)
        return sminScaled(mBoundaryLower, mBoundaryUpper, jmCusp.y)
    }

    /// `get_focus_gain` (:686-702).
    static func getFocusGain(
        _ j: Double, _ analyticalThreshold: Double, _ limitJMax: Double, _ focusDist: Double
    ) -> Double {
        var gain = limitJMax * focusDist
        if j > analyticalThreshold {
            var gainAdjustment = Foundation.log10(
                (limitJMax - analyticalThreshold) / max(0.0001, limitJMax - j))
            gainAdjustment = gainAdjustment * gainAdjustment + 1
            gain = gain * gainAdjustment
        }
        return gain
    }

    /// `remap_M` (:704-726).
    static func remapM(
        _ m: Double, _ gamutBoundaryM: Double, _ reachBoundaryM: Double, invert: Bool
    ) -> Double {
        let boundaryRatio = gamutBoundaryM / reachBoundaryM
        let proportion = max(boundaryRatio, compressionThreshold)
        let threshold = proportion * gamutBoundaryM
        if m <= threshold || proportion >= 1 {
            return m
        }
        let mOffset = m - threshold
        let gamutOffset = gamutBoundaryM - threshold
        let reachOffset = reachBoundaryM - threshold
        let scale = reachOffset / ((reachOffset / gamutOffset) - 1)
        let nd = mOffset / scale
        return threshold + reinhardRemap(scale, nd, invert: invert)
    }

    /// `compute_focus_J` (:845-848).
    static func computeFocusJ(
        _ cuspJ: Double, _ midJ: Double, _ limitJMax: Double
    ) -> Double {
        let t = min(1.0, cuspMidBlend - cuspJ / limitJMax)
        return cuspJ + t * (midJ - cuspJ)
    }

    /// The hue-dependent parameter bundle (`HueDependentGamutParams`,
    /// `init_HueDependentGamutParams` :850-864).
    struct HueDependentGamutParams {
        let jmCusp: SIMD2<Double>
        let gammaTopInv: Double
        let gammaBottomInv: Double
        let focusJ: Double
        let analyticalThreshold: Double
    }

    static func initHueDependentGamutParams(
        _ hue: Double, _ p: Params
    ) -> HueDependentGamutParams {
        let iHi = lookupHueInterval(hue, p.tableHues, p.hueLinearitySearchRange)
        let t = hue - p.tableHues[iHi - 1]
        let jmCusp = cuspFromTable(hue, p.tableGamutCusps)
        let gammaTopInv = p.tableUpperHullGamma[iHi - 1]
            + t * (p.tableUpperHullGamma[iHi] - p.tableUpperHullGamma[iHi - 1])
        let focusJ = computeFocusJ(jmCusp.x, p.midJ, p.limitJMax)
        let analyticalThreshold = jmCusp.x
            + focusGainBlend * (p.limitJMax - jmCusp.x)
        return HueDependentGamutParams(
            jmCusp: jmCusp, gammaTopInv: gammaTopInv,
            gammaBottomInv: p.lowerHullGammaInv, focusJ: focusJ,
            analyticalThreshold: analyticalThreshold)
    }

    /// `compress_gamut` (:728-774).
    static func compressGamut(
        _ jmh: SIMD3<Double>, _ jx: Double, _ p: Params, _ hdp: HueDependentGamutParams,
        invert: Bool
    ) -> SIMD3<Double> {
        let j = jmh.x
        let m = jmh.y
        let h = jmh.z
        let slopeGain = getFocusGain(
            jx, hdp.analyticalThreshold, p.limitJMax, p.focusDist)
        let jIntersectSource = solveJIntersect(
            j, m, hdp.focusJ, p.limitJMax, slopeGain)
        let gamutSlope = compressionVectorSlope(
            jIntersectSource, hdp.focusJ, p.limitJMax, slopeGain)
        let jIntersectCusp = solveJIntersect(
            hdp.jmCusp.x, hdp.jmCusp.y, hdp.focusJ, p.limitJMax, slopeGain)
        let gamutBoundaryM = findGamutBoundaryIntersection(
            hdp.jmCusp, p.limitJMax, hdp.gammaTopInv, hdp.gammaBottomInv,
            jIntersectSource, gamutSlope, jIntersectCusp)
        if gamutBoundaryM <= 0 {
            return SIMD3(j, 0, h)
        }
        let reachMaxM = reachMFromTable(h, p.tableReachM)
        let reachBoundaryM = estimateLineAndBoundaryIntersectionM(
            jIntersectSource, gamutSlope, p.modelGammaInv, p.limitJMax,
            reachMaxM, p.limitJMax)
        let remappedM = remapM(m, gamutBoundaryM, reachBoundaryM, invert: invert)
        return SIMD3(jIntersectSource + remappedM * gamutSlope, remappedM, h)
    }

    /// `cusp_from_table` (:776-808).
    static func cuspFromTable(_ h: Double, _ table: [SIMD3<Double>]) -> SIMD2<Double> {
        var lowI = 0
        var highI = 1 + tableSize
        var i = huePositionInUniformTable(h, tableSize) + 1
        while lowI + 1 < highI {
            if h > table[i].z {
                lowI = i
            } else {
                highI = i
            }
            i = Int(midpoint(Double(lowI), Double(highI)))
        }
        let lo = table[highI - 1]
        let hi = table[highI]
        let t = (h - lo.z) / (hi.z - lo.z)
        return SIMD2(
            lo.x + t * (hi.x - lo.x),
            lo.y + t * (hi.y - lo.y))
    }

    /// `lookup_hue_interval` (:810-838).
    static func lookupHueInterval(
        _ h: Double, _ hueTable: [Double], _ range: (Int, Int)
    ) -> Int {
        var i = 1 + huePositionInUniformTable(h, totalTableSize)
        var iLo = max(1, i + range.0)
        var iHi = min(1 + tableSize, i + range.1)
        while iLo + 1 < iHi {
            if h > hueTable[i] {
                iLo = i
            } else {
                iHi = i
            }
            i = Int(midpoint(Double(iLo), Double(iHi)))
        }
        return max(1, iHi)
    }

    /// `gamut_compress_fwd` (:866-888).
    static func gamutCompressFwd(_ jmh: SIMD3<Double>, _ p: Params) -> SIMD3<Double> {
        let j = jmh.x
        let m = jmh.y
        let h = jmh.z
        if j <= 0 { return SIMD3(0, 0, h) }
        if m < 0 || j > p.limitJMax { return SIMD3(j, 0, h) }
        let hdp = initHueDependentGamutParams(h, p)
        return compressGamut(jmh, j, p, hdp, invert: false)
    }

    // MARK: - Table builders (:920-1630)

    /// `generate_unit_cube_cusp_corners` (:1001-1020) — R, Y, G, C, B, M
    /// generation order so the hues rotate correctly.
    static func unitCubeCuspCorner(_ corner: Int) -> SIMD3<Double> {
        func flag(_ shift: Int) -> Double {
            ((corner + shift) % cuspCornerCount) < 3 ? 1.0 : 0.0
        }
        return SIMD3(flag(1), flag(5), flag(3))
    }

    /// `build_limiting_cusp_corners_tables` (:1022-1060) — the RGB and JMh
    /// corner cycles (lowest hue rotated to [1], ends wrapped ±360).
    static func buildLimitingCuspCornersTables(
        _ params: Aces2Cam.JMhParams, _ peakLuminance: Double
    ) -> (rgb: [SIMD3<Double>], jmh: [SIMD3<Double>]) {
        var tempRGB: [SIMD3<Double>] = []
        var tempJMh: [SIMD3<Double>] = []
        var minIndex = 0
        for i in 0..<cuspCornerCount {
            let rgb = (peakLuminance / Aces2Cam.refLuminance)
                * unitCubeCuspCorner(i)
            let jmh = Aces2Cam.rgbToJMh(rgb, params)
            tempRGB.append(rgb)
            tempJMh.append(jmh)
            if jmh.z < tempJMh[minIndex].z { minIndex = i }
        }
        var rgbCorners = [SIMD3<Double>](repeating: .zero, count: totalCornerCount)
        var jmhCorners = [SIMD3<Double>](repeating: .zero, count: totalCornerCount)
        for i in 0..<cuspCornerCount {
            rgbCorners[i + 1] = tempRGB[(i + minIndex) % cuspCornerCount]
            jmhCorners[i + 1] = tempJMh[(i + minIndex) % cuspCornerCount]
        }
        rgbCorners[0] = rgbCorners[cuspCornerCount]
        rgbCorners[cuspCornerCount + 1] = rgbCorners[1]
        jmhCorners[0] = jmhCorners[cuspCornerCount]
        jmhCorners[cuspCornerCount + 1] = jmhCorners[1]
        jmhCorners[0].z -= 360
        jmhCorners[cuspCornerCount + 1].z += 360
        return (rgbCorners, jmhCorners)
    }

    /// `find_reach_corners_table` (:1062-1123).
    static func findReachCornersTable(
        _ params: Aces2Cam.JMhParams, forwardLimit: Double, limitJMax: Double
    ) -> [SIMD3<Double>] {
        var jmhCorners = [SIMD3<Double>](repeating: .zero, count: totalCornerCount)
        let limitA = Aces2Cam.jToAchromatic(limitJMax, invCz: params.invCz)
        var tempJMh: [SIMD3<Double>] = []
        var minIndex = 0
        for i in 0..<cuspCornerCount {
            let rgbVector = unitCubeCuspCorner(i)
            var lower = 0.0
            var upper = forwardLimit
            while (upper - lower) > reachCuspTolerance {
                let test = (lower + upper) / 2
                let a = Aces2Cam.rgbToAab(test * rgbVector, params).x
                if a < limitA {
                    lower = test
                } else {
                    upper = test
                }
            }
            let corner = Aces2Cam.rgbToJMh(upper * rgbVector, params)
            tempJMh.append(corner)
            if corner.z < tempJMh[minIndex].z { minIndex = i }
        }
        for i in 0..<cuspCornerCount {
            jmhCorners[i + 1] = tempJMh[(i + minIndex) % cuspCornerCount]
        }
        jmhCorners[0] = jmhCorners[cuspCornerCount]
        jmhCorners[cuspCornerCount + 1] = jmhCorners[1]
        jmhCorners[0].z -= 360
        jmhCorners[cuspCornerCount + 1].z += 360
        return jmhCorners
    }

    /// `extract_sorted_cube_hues` (:1125-1161) — the merged unique hue list
    /// (zero-filled beyond the consumed count, like the CTL array default).
    static func extractSortedCubeHues(
        _ reachJMh: [SIMD3<Double>], _ limitJMh: [SIMD3<Double>]
    ) -> [Double] {
        var sorted = [Double](repeating: 0, count: maxSortedCorners)
        var idx = 0
        var reachIdx = 1
        var limitIdx = 1
        while reachIdx < (cuspCornerCount + 1) || limitIdx < (cuspCornerCount + 1) {
            let reachHue = reachJMh[reachIdx].z
            let limitHue = limitJMh[limitIdx].z
            if reachHue == limitHue {
                sorted[idx] = reachHue
                reachIdx += 1
                limitIdx += 1
            } else if reachHue < limitHue {
                sorted[idx] = reachHue
                reachIdx += 1
            } else {
                sorted[idx] = limitHue
                limitIdx += 1
            }
            idx += 1
        }
        return sorted
    }

    /// `build_hue_sample_interval` (:1163-1178).
    static func buildHueSampleInterval(
        _ samples: Int, _ lower: Double, _ upper: Double,
        _ hueTable: inout [Double], _ base: Int
    ) {
        guard samples > 0 else { return }
        let delta = (upper - lower) / Double(samples)
        for i in 0..<samples {
            hueTable[base + i] = lower + Double(i) * delta
        }
    }

    /// `build_hue_table` (:1180-1239). NOTE: the upstream reads `last_idx`
    /// uninitialized on the first corner (CTL array semantics) — resolved
    /// deterministically here as −1 (never equal on the first pass;
    /// DECISIONS §D6).
    static func buildHueTable(_ sortedHues: [Double]) -> [Double] {
        var hueTable = [Double](repeating: 0, count: totalTableSize)
        let idealSpacing = Double(tableSize) / 360.0
        var samplesCount = [Int](repeating: 0, count: maxSortedCorners + 2)
        var lastIdx = -1
        var minIndex = sortedHues[0] == 0.0 ? 0 : 1
        for hueIdx in 0..<maxSortedCorners {
            var nominalIdx = min(
                max(Int((sortedHues[hueIdx] * idealSpacing).rounded()), minIndex),
                tableSize - 1)
            if lastIdx == nominalIdx {
                if hueIdx > 1
                    && samplesCount[hueIdx - 2] != samplesCount[hueIdx - 1] - 1 {
                    samplesCount[hueIdx - 1] = samplesCount[hueIdx - 1] - 1
                } else {
                    nominalIdx = nominalIdx + 1
                }
            }
            samplesCount[hueIdx] = min(nominalIdx, tableSize - 1)
            minIndex = nominalIdx
            lastIdx = minIndex
        }
        var totalSamples = 0
        buildHueSampleInterval(
            samplesCount[0], 0.0, sortedHues[0], &hueTable, totalSamples + 1)
        totalSamples += samplesCount[0]
        for i in 1..<maxSortedCorners {
            let samples = samplesCount[i] - samplesCount[i - 1]
            buildHueSampleInterval(
                samples, sortedHues[i - 1], sortedHues[i], &hueTable, totalSamples + 1)
            totalSamples += samples
        }
        buildHueSampleInterval(
            tableSize - totalSamples, sortedHues[maxSortedCorners - 1], 360.0,
            &hueTable, totalSamples + 1)
        hueTable[0] = hueTable[tableSize - 1] - 360
        hueTable[1 + tableSize] = hueTable[1] + 360
        return hueTable
    }

    /// `find_display_cusp_for_hue` (:1241-1325).
    static func findDisplayCuspForHue(
        _ hue: Double,
        _ rgbCorners: [SIMD3<Double>],
        _ jmhCorners: [SIMD3<Double>],
        _ params: Aces2Cam.JMhParams
    ) -> SIMD2<Double> {
        var upperCorner = 1
        var found = false
        var i = upperCorner
        while i != totalCornerCount && !found {
            if jmhCorners[i].z > hue {
                upperCorner = i
                found = true
            }
            i += 1
        }
        let lowerCorner = upperCorner - 1
        if jmhCorners[lowerCorner].z == hue {
            return SIMD2(jmhCorners[lowerCorner].x, jmhCorners[lowerCorner].y)
        }
        let cuspLower = rgbCorners[lowerCorner]
        let cuspUpper = rgbCorners[upperCorner]
        var lowerT = 0.0
        var upperT = 1.0
        var jmh: SIMD3<Double>
        while (upperT - lowerT) > displayCuspTolerance {
            let sampleT = midpoint(lowerT, upperT)
            let sample = cuspLower + sampleT * (cuspUpper - cuspLower)
            jmh = Aces2Cam.rgbToJMh(sample, params)
            if jmh.z < jmhCorners[lowerCorner].z {
                upperT = sampleT
            } else if jmh.z >= jmhCorners[upperCorner].z {
                lowerT = sampleT
            } else if jmh.z > hue {
                upperT = sampleT
            } else {
                lowerT = sampleT
            }
        }
        let sampleT = midpoint(lowerT, upperT)
        let sample = cuspLower + sampleT * (cuspUpper - cuspLower)
        jmh = Aces2Cam.rgbToJMh(sample, params)
        return SIMD2(jmh.x, jmh.y)
    }

    /// `build_cusp_table` (:1327-1355).
    static func buildCuspTable(
        _ hueTable: [Double],
        _ rgbCorners: [SIMD3<Double>],
        _ jmhCorners: [SIMD3<Double>],
        _ params: Aces2Cam.JMhParams
    ) -> [SIMD3<Double>] {
        var out = [SIMD3<Double>](repeating: .zero, count: totalTableSize)
        for i in 1..<totalTableSize {
            let hue = hueTable[i]
            let jm = findDisplayCuspForHue(hue, rgbCorners, jmhCorners, params)
            out[i] = SIMD3(jm.x, jm.y * (1 + smoothM * smoothCusps), hue)
        }
        out[0] = SIMD3(out[tableSize].x, out[tableSize].y, hueTable[0])
        out[1 + tableSize] = SIMD3(out[1].x, out[1].y, hueTable[1 + tableSize])
        return out
    }

    /// `make_uniform_hue_gamut_table` (:1357-1383).
    static func makeUniformHueGamutTable(
        reachParams: Aces2Cam.JMhParams,
        limitParams: Aces2Cam.JMhParams,
        forwardLimit: Double,
        limitJMax: Double,
        midJ: Double,
        focusDist: Double,
        lowerHullGammaInv: Double,
        peak: Double
    ) -> [SIMD3<Double>] {
        let reachJmhCorners = findReachCornersTable(
            reachParams, forwardLimit: forwardLimit, limitJMax: limitJMax)
        let (limitingRgbCorners, limitingJmhCorners) =
            buildLimitingCuspCornersTables(limitParams, peak)
        let sortedHues = extractSortedCubeHues(reachJmhCorners, limitingJmhCorners)
        let hueTable = buildHueTable(sortedHues)
        return buildCuspTable(hueTable, limitingRgbCorners, limitingJmhCorners, limitParams)
    }

    /// `make_reach_m_table` (:1386-1440).
    static func makeReachMTable(
        _ params: Aces2Cam.JMhParams, limitJMax: Double
    ) -> [Double] {
        var reachTable = [Double](repeating: 0, count: totalTableSize)
        for i in 0..<tableSize {
            let hue = baseHueForPosition(i, tableSize)
            let searchRange = 50.0
            let searchMaximum = 1300.0
            var low = 0.0
            var high = low + searchRange
            var outside = false
            while !outside && high < searchMaximum {
                let rgb = Aces2Cam.jmhToRGB(SIMD3(limitJMax, high, hue), params)
                outside = rgb.x < 0 || rgb.y < 0 || rgb.z < 0
                if !outside {
                    low = high
                    high = high + searchRange
                }
            }
            while high - low > 1e-2 {
                let sampleM = (high + low) / 2
                let rgb = Aces2Cam.jmhToRGB(SIMD3(limitJMax, sampleM, hue), params)
                outside = rgb.x < 0 || rgb.y < 0 || rgb.z < 0
                if outside {
                    high = sampleM
                } else {
                    low = sampleM
                }
            }
            reachTable[i + 1] = high
        }
        reachTable[0] = reachTable[tableSize]
        reachTable[1 + tableSize] = reachTable[1]
        return reachTable
    }

    /// The gamma test data bundle (`generate_gamma_test_data` :1458-1487;
    /// the per-test hue rides along as the upstream stores it).
    struct GammaTestData {
        var testJ: [Double]
        var jIntersectSource: [Double]
        var slopes: [Double]
        var jIntersectCusp: [Double]
        var hue: [Double]
    }

    /// `generate_gamma_test_data` (:1458-1487).
    static func generateGammaTestData(
        _ jmCusp: SIMD2<Double>, _ hue: Double,
        limitJMax: Double, midJ: Double, focusDist: Double
    ) -> GammaTestData {
        let testCount = 5
        let testPositions: [Double] = [0.01, 0.1, 0.5, 0.8, 0.99]
        let analyticalThreshold = jmCusp.x + focusGainBlend * (limitJMax - jmCusp.x)
        let focusJ = computeFocusJ(jmCusp.x, midJ, limitJMax)
        var data = GammaTestData(
            testJ: [], jIntersectSource: [], slopes: [], jIntersectCusp: [], hue: [])
        for i in 0..<testCount {
            let tj = jmCusp.x + testPositions[i] * (limitJMax - jmCusp.x)
            let slopeGain = getFocusGain(tj, analyticalThreshold, limitJMax, focusDist)
            let jIntersect = solveJIntersect(tj, jmCusp.y, focusJ, limitJMax, slopeGain)
            let slope = compressionVectorSlope(
                jIntersect, focusJ, limitJMax, slopeGain)
            let jc = solveJIntersect(jmCusp.x, jmCusp.y, focusJ, limitJMax, slopeGain)
            data.testJ.append(tj)
            data.jIntersectSource.append(jIntersect)
            data.slopes.append(slope)
            data.jIntersectCusp.append(jc)
            data.hue.append(hue)
        }
        return data
    }

    /// `evaluate_gamma_fit` (:1489-1526) — true = every test point lands
    /// OUTSIDE the luminance hull (the gamma is large enough).
    static func evaluateGammaFit(
        _ jmCusp: SIMD2<Double>,
        _ data: GammaTestData,
        _ topGammaInv: Double,
        limitJMax: Double,
        lowerHullGammaInv: Double,
        limitParams: Aces2Cam.JMhParams,
        peak: Double
    ) -> Bool {
        let luminanceLimit = peak / Aces2Cam.refLuminance
        for i in 0..<data.testJ.count {
            let approxLimitM = findGamutBoundaryIntersection(
                jmCusp, limitJMax, topGammaInv, lowerHullGammaInv,
                data.jIntersectSource[i], data.slopes[i], data.jIntersectCusp[i])
            let approxLimitJ = data.jIntersectSource[i]
                + data.slopes[i] * approxLimitM
            let approximateJMh = SIMD3(approxLimitJ, approxLimitM, data.hue[i])
            let newLimitRGB = Aces2Cam.jmhToRGB(approximateJMh, limitParams)
            // `outside_hull` (:1442-1445): any channel above the limit.
            let outside = newLimitRGB.x > luminanceLimit
                || newLimitRGB.y > luminanceLimit
                || newLimitRGB.z > luminanceLimit
            if !outside {
                return false
            }
        }
        return true
    }

    /// `make_upper_hull_gamma_table` (:1528-1606).
    static func makeUpperHullGammaTable(
        _ gamutCuspTable: [SIMD3<Double>],
        limitJMax: Double,
        midJ: Double,
        focusDist: Double,
        lowerHullGammaInv: Double,
        limitParams: Aces2Cam.JMhParams,
        peak: Double
    ) -> [Double] {
        var upperHullGamma = [Double](repeating: 0, count: totalTableSize)
        for i in 1..<(1 + tableSize) {
            let hue = gamutCuspTable[i].z
            let jmCusp = SIMD2(gamutCuspTable[i].x, gamutCuspTable[i].y)
            let data = generateGammaTestData(
                jmCusp, hue, limitJMax: limitJMax, midJ: midJ, focusDist: focusDist)
            var low = gammaMinimum
            var high = low + gammaSearchStep
            var outside = false
            while !outside && high < gammaMaximum {
                let gammaFound = evaluateGammaFit(
                    jmCusp, data, 1 / high, limitJMax: limitJMax,
                    lowerHullGammaInv: lowerHullGammaInv, limitParams: limitParams,
                    peak: peak)
                if !gammaFound {
                    low = high
                    high = high + gammaSearchStep
                } else {
                    outside = true
                }
            }
            while (high - low) > gammaAccuracy {
                let testGamma = midpoint(high, low)
                let gammaFound = evaluateGammaFit(
                    jmCusp, data, 1 / testGamma, limitJMax: limitJMax,
                    lowerHullGammaInv: lowerHullGammaInv, limitParams: limitParams,
                    peak: peak)
                if gammaFound {
                    high = testGamma
                } else {
                    low = testGamma
                }
            }
            upperHullGamma[i] = 1 / high
        }
        upperHullGamma[0] = upperHullGamma[tableSize]
        upperHullGamma[tableSize + 1] = upperHullGamma[1]
        return upperHullGamma
    }

    /// `determine_hue_linearity_search_range` (:1608-1630).
    static func determineHueLinearitySearchRange(
        _ hueTable: [Double]
    ) -> (Int, Int) {
        let lowerPadding = 0
        let upperPadding = 1
        var lower = 0
        var upper = 1
        for i in 1..<(1 + tableSize) {
            let pos = huePositionInUniformTable(hueTable[i], totalTableSize)
            let delta = i - pos
            lower = min(lower, delta + lowerPadding)
            upper = max(upper, delta + upperPadding)
        }
        return (lower, upper)
    }

    // MARK: - ODTParams (the per-point table bundle, :1632-1672)

    /// Everything the per-pixel path needs for ONE (limiting, peak) point.
    /// The build is deterministic (fixed binary-search bounds) — the same
    /// inputs rebuild bit-identical tables.
    struct Params {
        let peak: Double
        let limitingSpace: DrtLimitingSpace
        let rgcOn: Bool

        let ts: TSParams
        let inputParams: Aces2Cam.JMhParams   // AP0
        let reachParams: Aces2Cam.JMhParams   // AP1
        let limitParams: Aces2Cam.JMhParams   // the limiting space

        let limitJMax: Double
        let modelGammaInv: Double
        let tableReachM: [Double]             // [totalTableSize]
        let sat: Double
        let satThr: Double
        let compr: Double
        let chromaCompressScale: Double
        let midJ: Double
        let focusDist: Double
        let lowerHullGammaInv: Double
        let tableHues: [Double]               // [totalTableSize]
        let tableGamutCusps: [SIMD3<Double>]  // [totalTableSize] (J, M, hue)
        let tableUpperHullGamma: [Double]     // [totalTableSize]
        let hueLinearitySearchRange: (Int, Int)

        /// `init_ODTParams` (:1632-1672) — build order matters (later
        /// tables consume earlier scalars; locals first, `self` last).
        init(limitingSpace: DrtLimitingSpace, peak: Double, rgcOn: Bool = true) {
            let limiting = Aces2Limiting.spaces[limitingSpace]!
            let inputParams = Aces2Cam.JMhParams(primaries: Aces2Cam.ap0)
            let reachParams = Aces2Cam.JMhParams(primaries: Aces2Cam.ap1)
            let limitParams = limiting.params
            let ts = TSParams(peakLuminance: peak)

            let limitJMax = yToJ(peak, inputParams)
            let modelGammaInv = 1 / Aces2Cam.modelGamma
            let tableReachM = Aces2Reference.makeReachMTable(reachParams, limitJMax: limitJMax)

            let sat = max(0.2, chromaExpand - (chromaExpand * chromaExpandFact) * ts.logPeak)
            let satThr = chromaExpandThr / peak
            let compr = chromaCompress + (chromaCompress * chromaCompressFact) * ts.logPeak
            let chromaCompressScale = Foundation.pow(0.03379 * peak, 0.30596) - 0.45135

            let midJ = yToJ(ts.cT * Aces2Cam.refLuminance, inputParams)
            let focusDist = focusDistance + focusDistance * focusDistanceScaling * ts.logPeak
            let lowerHullGamma = 1.14 + 0.07 * ts.logPeak
            let lowerHullGammaInv = 1 / lowerHullGamma

            let cusps = Aces2Reference.makeUniformHueGamutTable(
                reachParams: reachParams, limitParams: limitParams,
                forwardLimit: ts.forwardLimit, limitJMax: limitJMax,
                midJ: midJ, focusDist: focusDist,
                lowerHullGammaInv: lowerHullGammaInv, peak: peak)
            let tableUpperHullGamma = Aces2Reference.makeUpperHullGammaTable(
                cusps, limitJMax: limitJMax, midJ: midJ, focusDist: focusDist,
                lowerHullGammaInv: lowerHullGammaInv, limitParams: limitParams,
                peak: peak)
            let hueLinearitySearchRange = Aces2Reference.determineHueLinearitySearchRange(
                cusps.map { $0.z })

            self.limitingSpace = limitingSpace
            self.peak = peak
            self.rgcOn = rgcOn
            self.ts = ts
            self.inputParams = inputParams
            self.reachParams = reachParams
            self.limitParams = limitParams
            self.limitJMax = limitJMax
            self.modelGammaInv = modelGammaInv
            self.tableReachM = tableReachM
            self.sat = sat
            self.satThr = satThr
            self.compr = compr
            self.chromaCompressScale = chromaCompressScale
            self.midJ = midJ
            self.focusDist = focusDist
            self.lowerHullGammaInv = lowerHullGammaInv
            self.tableGamutCusps = cusps
            self.tableHues = cusps.map { $0.z }
            self.tableUpperHullGamma = tableUpperHullGamma
            self.hueLinearitySearchRange = hueLinearitySearchRange
        }
    }

    /// The memoized params accessor — the per-drag interactive face (the
    /// table build costs ~10⁵ CAM16 evaluations; a peak/limiting drag must
    /// not rebuild per dispatch). Keyed on (space, peak, rgc); the box is
    /// lock-guarded (render-tail concurrency; Swift 6 static-let safety).
    private final class ParamsCacheBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cache: [UInt64: Params] = [:]

        func get(_ key: UInt64) -> Params? {
            lock.lock()
            defer { lock.unlock() }
            return cache[key]
        }

        func set(_ key: UInt64, _ p: Params) {
            lock.lock()
            defer { lock.unlock() }
            cache[key] = p
        }
    }

    private static let paramsCache = ParamsCacheBox()

    static func params(
        space: DrtLimitingSpace, peak: Double, rgcOn: Bool = true
    ) -> Params {
        var key = StableHash.fnvOffsetBasis
        Array(space.rawValue.utf8).withUnsafeBufferPointer {
            key = StableHash.combine(key, UnsafeRawBufferPointer($0))
        }
        withUnsafeBytes(of: peak.bitPattern) {
            key = StableHash.combine(key, $0)
        }
        withUnsafeBytes(of: rgcOn ? UInt64(1) : UInt64(0)) {
            key = StableHash.combine(key, $0)
        }
        if let hit = paramsCache.get(key) {
            return hit
        }
        let built = Params(limitingSpace: space, peak: peak, rgcOn: rgcOn)
        paramsCache.set(key, built)
        return built
    }

    // MARK: - Entry point (KD-5)

    /// `outputTransform_fwd` (:1674-1688) + the working-space entry stages
    /// ([0]/[1]) + the peak normalization ([7]) — ONE pixel of the aces20
    /// method.
    static func runPixel(_ p: Params, _ linearRec2020: SIMD3<Double>) -> SIMD3<Double> {
        // [0] working space → AP0.
        var aces = Aces2Cam.rec2020ToAP0.multiply(linearRec2020)
        // [1] the RGC前置 (default ON; the OpenDRT path never runs it — KD-3).
        if p.rgcOn {
            aces = Aces2RGC.compress(aces)
        }
        // [2] the AP0→AP1 clamp at the tonescale's forward limit.
        let clamped = Aces2Cam.clampAP0ToAP1(aces, lower: 0, upper: p.ts.forwardLimit)
        // [3] AP0 → JMh.
        let jmh = Aces2Cam.rgbToJMh(clamped, p.inputParams)
        // [4] tonescale + chroma compression.
        let tonemapped = tonemapAndCompressFwd(jmh, p)
        // [5] gamut compression against the limiting gamut.
        let compressed = gamutCompressFwd(tonemapped, p)
        // [6] JMh → limiting-space RGB (1.0 = the 100-nit reference white).
        let rgb = Aces2Cam.jmhToRGB(compressed, p.limitParams)
        // [7] peak-normalize to the EotfBox contract (1.0 = peak nits).
        return rgb * (Aces2Cam.refLuminance / p.peak)
    }
}

// MARK: - GPU bridge (Plan M2-6-2 T4, KD-5 — the M2-6-1 KD-4 shape)

/// The uniform buffer bridge to `Aces2Uniforms` in `Aces2Kernels.metal` —
/// a FLAT float4 plane (588 entries = 9408 bytes; the layout ORDER is the
/// ABI, mirrored member-for-member in the Metal struct; the size-probe
/// kernel pins the byte count). Parameters ride a BUFFER, never function
/// constants (OQ-10-A: a param drag re-uploads, recompiles NOTHING — one
/// PSO, resident). The per-point tables (reach-M / hues / cusps / upper
/// hull gamma) ride in the tail sections, zero-padded to whole float4s.
struct Aces2Uniforms {
    /// The packed plane (the ABI).
    var floats: [SIMD4<Float>]

    static let float4Count = 588
    static let tableFloat4Count = 91      // 362 floats → 364 → 91
    static let cuspFloat4Count = 272      // 362×3 floats → 1088 → 272

    /// Pack from the built Params (the Swift single source — the Metal
    /// struct never authors a per-params value).
    init(params: Aces2Reference.Params) {
        var f: [SIMD4<Float>] = []
        f.reserveCapacity(Self.float4Count)

        func pack(_ rows: DrtMat3) {
            f.append(SIMD4(Float(rows.r0.x), Float(rows.r0.y), Float(rows.r0.z), 0))
            f.append(SIMD4(Float(rows.r1.x), Float(rows.r1.y), Float(rows.r1.z), 0))
            f.append(SIMD4(Float(rows.r2.x), Float(rows.r2.y), Float(rows.r2.z), 0))
        }
        func packJMh(_ p: Aces2Cam.JMhParams) {
            f.append(SIMD4(Float(p.fLn), Float(p.cz), Float(p.invCz), Float(p.awJ)))
            f.append(SIMD4(Float(p.invAwJ), 0, 0, 0))
            pack(p.rgbToCam16C)
            pack(p.cam16CToRgb)
            pack(p.coneResponseToAab)
            pack(p.aabToConeResponse)
        }
        func packTable(_ table: [Double]) {
            var padded = table.map { Float($0) }
            padded.append(contentsOf: [Float](repeating: 0, count: 364 - padded.count))
            for i in stride(from: 0, to: 364, by: 4) {
                f.append(SIMD4(padded[i], padded[i + 1], padded[i + 2], padded[i + 3]))
            }
        }
        func packCusps(_ cusps: [SIMD3<Double>]) {
            var flat: [Float] = []
            flat.reserveCapacity(1088)
            for c in cusps {
                flat.append(Float(c.x)); flat.append(Float(c.y)); flat.append(Float(c.z))
            }
            flat.append(contentsOf: [Float](repeating: 0, count: 1088 - flat.count))
            for i in stride(from: 0, to: 1088, by: 4) {
                f.append(SIMD4(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]))
            }
        }

        // ts0/ts1/ts2 — ts2.zw carry the hue-linearity search range.
        let ts = params.ts
        f.append(SIMD4(Float(ts.n), Float(ts.nR), Float(ts.g), Float(ts.t1)))
        f.append(SIMD4(Float(ts.cT), Float(ts.s2), Float(ts.u2), Float(ts.m2)))
        f.append(SIMD4(
            Float(ts.forwardLimit), Float(ts.logPeak),
            Float(params.hueLinearitySearchRange.0),
            Float(params.hueLinearitySearchRange.1)))

        // input (AP0) JMhParams.
        packJMh(params.inputParams)
        // limit (limiting-space) JMhParams.
        packJMh(params.limitParams)

        // gam0/gam1/gam2.
        f.append(SIMD4(
            Float(params.limitJMax), Float(params.modelGammaInv),
            Float(params.sat), Float(params.satThr)))
        f.append(SIMD4(
            Float(params.compr), Float(params.chromaCompressScale),
            Float(params.midJ), Float(params.focusDist)))
        f.append(SIMD4(
            Float(params.lowerHullGammaInv), Float(params.peak),
            params.rgcOn ? 1 : 0, 0))

        // the fixed-space matrices.
        pack(Aces2Cam.ap0ToAP1)
        pack(Aces2Cam.ap1ToAP0)
        pack(Aces2Cam.rec2020ToAP0)

        // tables.
        packTable(params.tableReachM)
        packTable(params.tableHues)
        packCusps(params.tableGamutCusps)
        packTable(params.tableUpperHullGamma)

        assert(f.count == Self.float4Count, "Aces2Uniforms ABI drift: \(f.count)")
        floats = f
    }
}
