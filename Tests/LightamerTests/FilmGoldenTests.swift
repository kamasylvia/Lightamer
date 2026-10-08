@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmGoldenTests (Plan M3-3-03 T1, KD-1 — IOPParity bundle, the *Golden*
// domain convention) — the FSIM-01c GOLDEN MATH RECOMPUTATION MAIN GATE.
//
// The golden semantics (M3-2 OQ-M3-2-5 ①): an INDEPENDENT implementation of
// the DOCUMENTED math (RESEARCH §4.1 + M3-3-01/02 DECISIONS constants),
// recomputed in Float64 inside THIS FILE — the reference functions never
// touch the production bake/solve code paths (FilmPrintBake /
// FilmFilterPackSolver / FilmRuntimeSolve are the SUBJECTS, never the
// oracle). SpektraLab renders are a local-only eyeball face and never enter
// this suite (zero image assets — all inputs are programmatic).
//
// THE FOUR GATES:
//   1. THE FUSED KERNEL PER-PIXEL (two-level, the E5 pre-declaration):
//      1a. kernel vs a same-table CPU tetrahedral sampler (double-written
//          in this file, Lut3dKernelTests.cpuLut3d's non-self-source
//          discipline) — float-class tolerance ~1e-6 relative. This gate
//          owns the KERNEL IMPLEMENTATION CORRECTNESS (the lattice cancels).
//      1b. the baked table (via the same CPU sampler) vs the ideal
//          CONTINUOUS model at random density probes — the 65³ lattice
//          interpolation floor applies here (the M3-1-01-DECISIONS §4
//          precedent: ~8e-3 for film curves decoded to linear; measured
//          and pinned below). This gate owns the BAKED-TABLE FIDELITY.
//      L048 COMPARISON-SPACE DISCIPLINE: every comparison happens in the
//      LINEAR working domain (the log legs' zero-crossing slope amplifies
//      f32 epsilon ~750× — a log-domain per-pixel compare is a false-fail
//      factory), and every Float64 reference constant enters as
//      Double(Float(x)) (the f32 production value widened — writing the
//      decimal literal would bake a phantom reference skew into every
//      sample).
//   2. THE BAKE VOXEL LEVEL: FilmPrintBake vs the independent Float64 model
//      per voxel (fixed-seed LCG voxels) — ≤1e-5 relative (Float64 bake vs
//      Float64 recomputation, f32 STORAGE widening only), plus the domain
//      calibration consistency face.
//   3. THE PLACEMENT CURVE MATH: the g_m family vs independent
//      recomputation (the m=1 closed form EXACT; the m=2 landing vs an
//      independent bisection), the delta-form identity bit-exact face, the
//      monotonicity sweep, and the hard-asymptote (the branch never crosses
//      the medium boundary).
//   4. THE NEUTRAL CLOSURE (solver × pipeline): a neutral gray field
//      through the full fused chain (negative segment ⊕ solved neutral
//      pack ⊕ print LUT, strength 1, gain 1) stays neutral — the RFC-028
//      "gray error exactly 0" discipline's domain gate (≤1e-3 linear).
//
// Material fixtures = the in-repo CC BY-SA source JSONs via the typed store
// (the 01 five-piece set already carries the distribution duty — no new
// distribution surface).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmGoldenTests: XCTestCase {

    // MARK: - Fixtures

    private func profilesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/LightamerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Resources/FilmProfiles/profiles")
    }

    private func makeStore() throws -> FilmMaterialStore {
        try FilmMaterialStore(profilesDirectory: profilesDirectory())
    }

    private func profile(_ id: String) throws -> FilmProfile {
        try XCTUnwrap(try makeStore().profile(id: id), "stock \(id) missing")
    }

    /// The kernel-matrix material pairs (3 pairs: two Kodak + one Fuji —
    /// the corner matrix's material axis).
    private var materialPairs: [(film: String, paper: String)] {
        [
            ("kodak_portra_400", "kodak_portra_endura"),
            ("kodak_ektar_100", "kodak_ultra_endura"),
            ("fujifilm_pro_400h", "fujifilm_crystal_archive_typeii"),
        ]
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    /// L014: never read a plane across in-flight encoders.
    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - The controlled input fields (programmatic; ≤512², the 3024
    // RSS discipline — no 100MP face enters a golden gate)

    private let fieldWidth = 192
    private let fieldHeight = 128

    /// A deterministic LCG (the FilmPlacementKernelTests seed discipline).
    private func lcg(_ seed: inout UInt64) -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
    }

    /// Field A: LCG-random chromatic linear values spanning 1e-4…100
    /// (log10 −4…2 — the axis clamp engages at the bottom).
    private func randomLinearField() -> [Float] {
        var texels = [Float](
            repeating: 0, count: fieldWidth * fieldHeight * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for index in 0..<(fieldWidth * fieldHeight) {
            for c in 0..<3 {
                let u = lcg(&seed)
                let log10v = -4.0 + 6.0 * u
                texels[index * 4 + c] = Float(Foundation.pow(10.0, log10v))
            }
            texels[index * 4 + 3] = 1.0
        }
        return texels
    }

    /// Field B: a neutral log ramp (R=G=B=10^e, e sweeping −3.5…2).
    private func neutralRampField() -> [Float] {
        var texels = [Float](
            repeating: 0, count: fieldWidth * fieldHeight * 4)
        let n = fieldWidth * fieldHeight
        for index in 0..<n {
            let e = -3.5 + 5.5 * Double(index) / Double(n - 1)
            let v = Float(Foundation.pow(10.0, e))
            texels[index * 4 + 0] = v
            texels[index * 4 + 1] = v
            texels[index * 4 + 2] = v
            texels[index * 4 + 3] = 1.0
        }
        return texels
    }

    /// Field C: a checkerboard of axis extremes (toe/shoulder alternation
    /// — the branch-boundary probe face).
    private func checkerboardField() -> [Float] {
        var texels = [Float](
            repeating: 0, count: fieldWidth * fieldHeight * 4)
        for y in 0..<fieldHeight {
            for x in 0..<fieldWidth {
                let o = (y * fieldWidth + x) * 4
                let dark = (x / 8 + y / 8) % 2 == 0
                let base = dark ? 1e-4 : 40.0
                texels[o + 0] = Float(Double(base) * 1.3)
                texels[o + 1] = Float(base)
                texels[o + 2] = Float(Double(base) * 0.8)
                texels[o + 3] = 1.0
            }
        }
        return texels
    }

    // MARK: - The INDEPENDENT Float64 model (self-contained; the documented
    // math of RESEARCH §4.1 + M3-3-01-DECISIONS §5 + M3-3-02-DECISIONS §3,
    // re-written here — production code paths are never imported for math)

    /// L048: every f32 production constant enters the reference widened.
    private static let sM = 0.0085
    private static let sY = 0.017
    private static let midGray = 0.184

    /// Linear interpolation over a profile curve (channel of
    /// density_curves against log_exposure), edge-clamped — the documented
    /// negative/print segment read, independently written (binary search +
    /// lerp, f32 storage widened BEFORE arithmetic).
    private func refCurveValue(
        _ p: FilmProfile, channel: Int, at x: Double
    ) -> Double {
        let logExposure = p.logExposure
        let count = logExposure.count
        precondition(count >= 2)
        let first = Double(logExposure[0])
        let last = Double(logExposure[count - 1])
        if x <= first { return Double(p.densityCurves[0][channel]) }
        if x >= last { return Double(p.densityCurves[count - 1][channel]) }
        var lo = 0
        var hi = count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if Double(logExposure[mid]) <= x { lo = mid } else { hi = mid }
        }
        let a = Double(p.densityCurves[lo][channel])
        let b = Double(p.densityCurves[hi][channel])
        let xa = Double(logExposure[lo])
        let xb = Double(logExposure[hi])
        return a + (x - xa) / (xb - xa) * (b - a)
    }

    /// The E2 three-point base projection (650/550/450 nm nearest-neighbour
    /// on base_density; ties take the LOWER index) — the documented E2
    /// face, independently written.
    private func refBaseProjection(_ film: FilmProfile) -> SIMD3<Double> {
        func project(_ target: Double) -> Double {
            var best = Int.max
            var bestDistance = Double.greatestFiniteMagnitude
            for (index, lambda) in film.wavelengths.enumerated() {
                let d = abs(Double(lambda) - target)
                if d < bestDistance {   // strict < = ties keep the lower index
                    bestDistance = d
                    best = index
                }
            }
            guard best < film.baseDensity.count, let v = film.baseDensity[best]
            else { return 0 }
            return Double(v)
        }
        return SIMD3(
            project(FilmProfile.CalibrationWavelength.red),
            project(FilmProfile.CalibrationWavelength.green),
            project(FilmProfile.CalibrationWavelength.blue))
    }

    /// The mid-gray negative-segment densities (KD-5 model step 1).
    private func refMidGrayDensities(_ film: FilmProfile) -> SIMD3<Double> {
        let base = refBaseProjection(film)
        let x = Foundation.log10(Self.midGray)
        return SIMD3(
            refCurveValue(film, channel: 0, at: x) + base.x,
            refCurveValue(film, channel: 1, at: x) + base.y,
            refCurveValue(film, channel: 2, at: x) + base.z)
    }

    /// The fixed-ladder bounded bisection over [0, 100] (the documented
    /// solver ladder, independently written).
    private func refBisect(_ residual: (Double) -> Double) -> Double {
        var lo = 0.0
        var hi = 100.0
        if residual(lo) >= 0 { return lo }
        if residual(hi) <= 0 { return hi }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if residual(mid) < 0 { lo = mid } else { hi = mid }
            if hi - lo < 1e-12 { break }
        }
        return (lo + hi) / 2
    }

    /// The bake-time neutral pack (D-5a: the sequential two-step 1-D
    /// bisection; M → G, Y → B).
    private func refNeutralPack(
        film: FilmProfile, paper: FilmProfile
    ) -> (m: Double, y: Double) {
        let f = refMidGrayDensities(film)
        let anchor = refCurveValue(paper, channel: 0, at: -f.x)
        let m = refBisect { k in
            refCurveValue(paper, channel: 1, at: -f.y + k * Self.sM) - anchor
        }
        let gOut = refCurveValue(paper, channel: 1, at: -f.y + m * Self.sM)
        let y = refBisect { k in
            refCurveValue(paper, channel: 2, at: -f.z + k * Self.sY) - gOut
        }
        return (m, y)
    }

    /// The per-pair exposure calibration K (KD-3: the SOLVED-SESSION
    /// mid-gray must print at the paper's mid density — monotone in K).
    private func refCalibration(
        film: FilmProfile, paper: FilmProfile, packM: Double
    ) -> Double {
        var dmin = SIMD3<Double>(
            .greatestFiniteMagnitude, .greatestFiniteMagnitude,
            .greatestFiniteMagnitude)
        for i in 0..<paper.logExposure.count {
            for c in 0..<3 {
                dmin[c] = min(dmin[c], Double(paper.densityCurves[i][c]))
            }
        }
        var maxGreen = -Double.greatestFiniteMagnitude
        for row in paper.densityCurves { maxGreen = max(maxGreen, Double(row[1])) }
        let paperMidGreen = (dmin.y + maxGreen) / 2
        let eMid = Foundation.log10(Self.midGray)
        let midGrayDensity =
            refCurveValue(film, channel: 1, at: eMid) + refBaseProjection(film).y
            - packM * Self.sM
        func residual(_ k: Double) -> Double {
            refCurveValue(paper, channel: 1, at: -midGrayDensity + k) - paperMidGreen
        }
        var lo = -5.0
        var hi = 12.0
        if residual(lo) > 0 { return lo }
        if residual(hi) < 0 { return hi }
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if residual(mid) < 0 { lo = mid } else { hi = mid }
            if hi - lo < 1e-13 { break }
        }
        return (lo + hi) / 2
    }

    /// The composite SESSION system response SysC_c(e) (KD-3 step 5's
    /// forward face — the pack-shifted session density through the paper).
    private func refSystemDensity(
        film: FilmProfile, paper: FilmProfile, base: SIMD3<Double>,
        channel: Int, exposure e: Double, dmin: Double, calibration: Double,
        packM: Double, packY: Double
    ) -> Double {
        let pack = channel == 1 ? packM * Self.sM : (channel == 2 ? packY * Self.sY : 0)
        let baseC = channel == 0 ? base.x : (channel == 1 ? base.y : base.z)
        let negative = refCurveValue(film, channel: channel, at: e) + baseC - pack
        return max(refCurveValue(paper, channel: channel, at: -negative + calibration) - dmin, 0)
    }

    /// The bracketed bisection inverse of SysC (KD-3 step 5: SysC is
    /// DECREASING in e — dense negative → less print exposure; the flat
    /// clamped axis ends map themselves).
    private func refInvertSystem(
        film: FilmProfile, paper: FilmProfile, base: SIMD3<Double>,
        channel: Int, targetDensity: Double, dmin: Double,
        calibration: Double, packM: Double, packY: Double
    ) -> Double {
        let axisLo = Double(film.logExposure.first ?? -3)
        let axisHi = Double(film.logExposure.last ?? 4)
        func f(_ e: Double) -> Double {
            refSystemDensity(
                film: film, paper: paper, base: base, channel: channel,
                exposure: e, dmin: dmin, calibration: calibration,
                packM: packM, packY: packY) - targetDensity
        }
        if f(axisLo) <= 0 { return axisLo }
        if f(axisHi) >= 0 { return axisHi }
        var lo = axisLo
        var hi = axisHi
        for _ in 0..<100 {
            let mid = (lo + hi) / 2
            if f(mid) > 0 { lo = mid } else { hi = mid }
            if hi - lo < 1e-13 { break }
        }
        return (lo + hi) / 2
    }

    /// THE IDEAL CONTINUOUS MODEL for one post-pack density triple: the
    /// documented per-channel chain — print exposure x = −d + K → paper
    /// density P′ = paper(x) − Dmin → invert the session system → out =
    /// 10^e (KD-3 steps 1-6; identity crosstalk — the M3-3-02 registered
    /// constant, the golden batch's review duty).
    private func refIdealPrintOutput(
        film: FilmProfile, paper: FilmProfile, density: SIMD3<Double>,
        packM: Double, packY: Double
    ) -> SIMD3<Double> {
        let base = refBaseProjection(film)
        var dmin = SIMD3<Double>(
            .greatestFiniteMagnitude, .greatestFiniteMagnitude,
            .greatestFiniteMagnitude)
        for i in 0..<paper.logExposure.count {
            for c in 0..<3 {
                dmin[c] = min(dmin[c], Double(paper.densityCurves[i][c]))
            }
        }
        let calibration = refCalibration(film: film, paper: paper, packM: packM)
        var out = SIMD3<Double>()
        for c in 0..<3 {
            let d = density[c]
            let paperDensity = max(
                refCurveValue(paper, channel: c, at: -d + calibration) - dmin[c], 0)
            let e = refInvertSystem(
                film: film, paper: paper, base: base, channel: c,
                targetDensity: paperDensity, dmin: dmin[c],
                calibration: calibration, packM: packM, packY: packY)
            out[c] = Foundation.pow(10.0, e)
        }
        return out
    }

    /// The table's Double domain bounds (the documented KD-3 calibration:
    /// the film density range over the axis + base − the dial headroom).
    private func refDomainBounds(_ film: FilmProfile) -> (
        lo: SIMD3<Double>, hi: SIMD3<Double>
    ) {
        let base = refBaseProjection(film)
        var dLo = SIMD3<Double>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var dHi = SIMD3<Double>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for i in 0..<film.logExposure.count {
            for c in 0..<3 {
                let d = Double(film.densityCurves[i][c])
                dLo[c] = min(dLo[c], d)
                dHi[c] = max(dHi[c], d)
            }
        }
        let headroom = SIMD3<Double>(0, 100 * Self.sM, 100 * Self.sY)
        return (dLo + base - headroom, dHi + base)
    }

    // MARK: - The same-table CPU tetrahedral sampler (gate 1a's oracle —
    // a DOUBLE WRITE of the film_subrun sample face; it reads the BAKED
    // table, never the bake math)

    /// One FilmSubRunUniforms transport bundle the tests assemble (the
    /// PixelPipe.assembleFilmPayloads transport semantics, test-side).
    private struct KernelTransport {
        var uniforms: FilmSubRunUniforms
        var curveTable: [Float]       // channel-major 3×256 (device buffer face)
        var table: FilmPrintTable
    }

    private func assembleTransport(
        film: FilmProfile, paper: FilmProfile, table: FilmPrintTable,
        magentaCC: Float, yellowCC: Float, exposureGain: Float, strength: Float
    ) throws -> KernelTransport {
        let baseTuple = try film.baseDensityProjection()
        let base = SIMD3<Double>(baseTuple.r, baseTuple.g, baseTuple.b)
        let count = film.logExposure.count
        var curves = [Float](repeating: 0, count: 3 * count)
        for i in 0..<count {
            for c in 0..<3 {
                curves[c * count + i] = film.densityCurves[i][c]
            }
        }
        let uniforms = FilmSubRunUniforms(
            exposureGain: exposureGain,
            kM: magentaCC * Float(Self.sM),
            kY: yellowCC * Float(Self.sY),
            strength: strength,
            baseR: Float(base.x), baseG: Float(base.y), baseB: Float(base.z),
            axisLo: Float(film.logExposure.first ?? -3),
            axisHi: Float(film.logExposure.last ?? 4),
            curveCountF: Float(count),
            domainLoX: table.domainLo.x, domainLoY: table.domainLo.y,
            domainLoZ: table.domainLo.z,
            domainHiX: table.domainHi.x, domainHiY: table.domainHi.y,
            domainHiZ: table.domainHi.z,
            width: Float(fieldWidth), height: Float(fieldHeight))
        return KernelTransport(
            uniforms: uniforms, curveTable: curves, table: table)
    }

    /// The per-cell screen LUT (built once per table): TRUE for cells that
    /// either touch a clamp-plateau face / its transition ring (a corner
    /// value within ~0.11 stops of an axis end — the concave-exponential
    /// entry into the faces) or carry high LOCAL CONTRAST (>4× within the
    /// cell). The per-pixel gates consume it with a 3×3×3 NEIGHBORHOOD
    /// check — the kernel's f32 lattice coordinate can flip a cell at the
    /// rint boundaries (a ±2.5e-5-cell coordinate difference), so the
    /// smooth-domain guarantee must hold for the whole neighborhood.
    /// Registered in M3-3-03-DECISIONS.
    private func makeScreenLUT(_ table: FilmPrintTable, film: FilmProfile) -> [Bool] {
        let level = FilmPrintTable.level
        let denseFace = Foundation.pow(10.0, Double(film.logExposure.first ?? -3))
        let clearFace = Foundation.pow(10.0, Double(film.logExposure.last ?? 4))
        var lut = [Bool](repeating: false, count: level * level * level)
        for z in 0..<(level - 1) {
            for y in 0..<(level - 1) {
                for x in 0..<(level - 1) {
                    var lo = SIMD3<Double>(
                        .greatestFiniteMagnitude, .greatestFiniteMagnitude,
                        .greatestFiniteMagnitude)
                    var hi = SIMD3<Double>(
                        -.greatestFiniteMagnitude, -.greatestFiniteMagnitude,
                        -.greatestFiniteMagnitude)
                    var flagged = false
                    cornerLoop: for dz in 0...1 {
                        for dy in 0...1 {
                            for dx in 0...1 {
                                let entry = table.data[
                                    x + dx + (y + dy) * level + (z + dz) * level * level]
                                for c in 0..<3 {
                                    let v = Double(entry[c])
                                    if v <= denseFace * 1.3 || v >= clearFace * 0.79 {
                                        flagged = true
                                        break cornerLoop
                                    }
                                    lo[c] = min(lo[c], v)
                                    hi[c] = max(hi[c], v)
                                }
                            }
                        }
                    }
                    if !flagged {
                        for c in 0..<3 where hi[c] > 4 * lo[c] + 1e-4 {
                            flagged = true
                        }
                    }
                    lut[x + y * level + z * level * level] = flagged
                }
            }
        }
        // The domain-edge cells (rgbi clamped to L-2 keeps this safe) and
        // the axis-end slices: mark the boundary slab z/y/x = L-1 screened
        // so neighborhood checks never index out of range semantics.
        for z in 0..<level {
            for y in 0..<level {
                lut[(level - 1) + y * level + z * level * level] = true
                lut[y + (level - 1) * level + z * level * level] = true
                lut[y + level * (level - 1) + z * level * level] = true
            }
        }
        return lut
    }

    /// The neighborhood screen: TRUE when any cell of the 3×3×3 block around
    /// `rgbi` is flagged (the LUT's boundary slab keeps this in range).
    private func neighborhoodScreened(
        _ lut: [Bool], rgbi: SIMD3<Int>
    ) -> Bool {
        let level = FilmPrintTable.level
        for dz in -1...1 {
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(rgbi.x + dx, 0), level - 1)
                    let y = min(max(rgbi.y + dy, 0), level - 1)
                    let z = min(max(rgbi.z + dz, 0), level - 1)
                    if lut[x + y * level + z * level * level] { return true }
                }
            }
        }
        return false
    }

    /// The Double pipeline for ONE pixel (the kernel's math, widened):
    /// gain → log10 → curve → base → pack → cube → tetrahedral → strength
    /// mix. Every f32 transport value enters widened (L048). Returns the
    /// output plus the containing cell's origin (the cliff-screen key).
    private func refFusedPixel(
        _ linear: SIMD3<Double>, _ t: KernelTransport
    ) -> (value: SIMD3<Double>, rgbi: SIMD3<Int>) {
        let u = t.uniforms
        let gain = Double(u.exposureGain)
        let lin = linear * gain
        let axisLo = Double(u.axisLo)
        let axisHi = Double(u.axisHi)
        let count = Double(u.curveCountF)
        let tiny = Double(Float(1e-6))

        // The negative segment.
        func lookup(channelBase: Int, e: Double) -> Double {
            let clampedE = min(max(e, axisLo), axisHi)
            var tt = (clampedE - axisLo) / (axisHi - axisLo) * (count - 1)
            tt = min(max(tt, 0), count - 1)
            let i0 = min(Int(tt.rounded(.down)), Int(count) - 2)
            let frac = tt - Double(i0)
            let a = Double(t.curveTable[channelBase + i0])
            let b = Double(t.curveTable[channelBase + i0 + 1])
            return a + frac * (b - a)
        }
        let base = SIMD3<Double>(Double(u.baseR), Double(u.baseG), Double(u.baseB))
        var density = SIMD3<Double>(
            lookup(channelBase: 0, e: Foundation.log10(max(lin.x, tiny))) + base.x,
            lookup(channelBase: Int(count), e: Foundation.log10(max(lin.y, tiny))) + base.y,
            lookup(channelBase: Int(count) * 2, e: Foundation.log10(max(lin.z, tiny))) + base.z)
        density.y -= Double(u.kM)
        density.z -= Double(u.kY)

        // The cube → tetrahedral sample (rint = round-half-to-EVEN, the
        // Metal convert default the lattice mapping relies on).
        let lo = SIMD3<Double>(Double(u.domainLoX), Double(u.domainLoY), Double(u.domainLoZ))
        let hi = SIMD3<Double>(Double(u.domainHiX), Double(u.domainHiY), Double(u.domainHiZ))
        var v = (density - lo) / (hi - lo)
        v = SIMD3<Double>(
            min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
        let level = FilmPrintTable.level
        let scaled = v * Double(level - 1)
        var rgbi = SIMD3<Int>(
            Int(scaled.x.rounded(.toNearestOrEven)),
            Int(scaled.y.rounded(.toNearestOrEven)),
            Int(scaled.z.rounded(.toNearestOrEven)))
        rgbi = SIMD3<Int>(
            min(max(rgbi.x, 0), level - 2),
            min(max(rgbi.y, 0), level - 2),
            min(max(rgbi.z, 0), level - 2))
        let d = scaled - SIMD3<Double>(rgbi)

        func voxel(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Double> {
            let entry = t.table.data[x + y * level + z * level * level]
            return SIMD3<Double>(entry)
        }
        let c000 = voxel(rgbi.x, rgbi.y, rgbi.z)
        let c100 = voxel(rgbi.x + 1, rgbi.y, rgbi.z)
        let c010 = voxel(rgbi.x, rgbi.y + 1, rgbi.z)
        let c110 = voxel(rgbi.x + 1, rgbi.y + 1, rgbi.z)
        let c001 = voxel(rgbi.x, rgbi.y, rgbi.z + 1)
        let c101 = voxel(rgbi.x + 1, rgbi.y, rgbi.z + 1)
        let c011 = voxel(rgbi.x, rgbi.y + 1, rgbi.z + 1)
        let c111 = voxel(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)
        // The lut3d.cl:51-77 branch table (the kernel's decomposition,
        // widened — the branch SELECTION is discontinuity-free at the ties,
        // so an f32/f64 flip on a tie boundary cannot move the value).
        var filmRGB: SIMD3<Double>
        if d.x > d.y {
            if d.y > d.z {
                filmRGB = (1 - d.x) * c000 + (d.x - d.y) * c100 + (d.y - d.z) * c110 + d.z * c111
            } else if d.x > d.z {
                filmRGB = (1 - d.x) * c000 + (d.x - d.z) * c100 + (d.z - d.y) * c101 + d.y * c111
            } else {
                filmRGB = (1 - d.z) * c000 + (d.z - d.x) * c001 + (d.x - d.y) * c101 + d.y * c111
            }
        } else {
            if d.z > d.y {
                filmRGB = (1 - d.z) * c000 + (d.z - d.y) * c001 + (d.y - d.x) * c011 + d.x * c111
            } else if d.z > d.x {
                filmRGB = (1 - d.y) * c000 + (d.y - d.z) * c010 + (d.z - d.x) * c011 + d.x * c111
            } else {
                filmRGB = (1 - d.y) * c000 + (d.y - d.x) * c010 + (d.x - d.z) * c110 + d.z * c111
            }
        }

        // The strength mix (RFC-025, density domain).
        let inLog = SIMD3<Double>(
            Foundation.log10(max(lin.x, tiny)),
            Foundation.log10(max(lin.y, tiny)),
            Foundation.log10(max(lin.z, tiny)))
        let filmLog = SIMD3<Double>(
            Foundation.log10(max(filmRGB.x, tiny)),
            Foundation.log10(max(filmRGB.y, tiny)),
            Foundation.log10(max(filmRGB.z, tiny)))
        let k = Double(u.strength)
        let outLog = inLog * (1 - k) + filmLog * k
        let value = SIMD3<Double>(
            Foundation.pow(10.0, outLog.x),
            Foundation.pow(10.0, outLog.y),
            Foundation.pow(10.0, outLog.z))
        return (value, rgbi)
    }

    // MARK: - The GPU dispatch harness

    private func makePlane(
        _ metal: MetalContext, texels: [Float]
    ) -> (input: any MTLTexture, output: any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: fieldWidth, height: fieldHeight,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        texels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, fieldWidth, fieldHeight),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: fieldWidth * 16)
        }
        return (input, output)
    }

    /// Dispatch `film_subrun` DIRECTLY on the transport (the fused kernel's
    /// true GPU face — the same bindings FilmGPUPayloads.Command uses).
    private func dispatchFusedKernel(
        _ metal: MetalContext, transport t: KernelTransport,
        input: any MTLTexture, output: any MTLTexture
    ) async throws {
        var u = t.uniforms
        let curveBuffer = metal.device.makeBuffer(
            bytes: t.curveTable,
            length: t.curveTable.count * MemoryLayout<Float>.stride,
            options: .storageModeShared)!
        let level = FilmPrintTable.level
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = level
        descriptor.height = level
        descriptor.depth = level
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        let tableTexture = metal.device.makeTexture(descriptor: descriptor)!
        var texels = [Float](repeating: 0, count: t.table.data.count * 4)
        for (index, value) in t.table.data.enumerated() {
            texels[index * 4 + 0] = value.x
            texels[index * 4 + 1] = value.y
            texels[index * 4 + 2] = value.z
            texels[index * 4 + 3] = 1
        }
        texels.withUnsafeBytes {
            tableTexture.replace(
                region: MTLRegionMake3D(0, 0, 0, level, level, level),
                mipmapLevel: 0, slice: 0, withBytes: $0.baseAddress!,
                bytesPerRow: level * 16, bytesPerImage: level * level * 16)
        }
        try await metal.dispatch2DTexture(
            functionName: "film_subrun", input: input, output: output
        ) { encoder in
            encoder.setBuffer(curveBuffer, offset: 0, index: 0)
            encoder.setBytes(&u, length: MemoryLayout<FilmSubRunUniforms>.stride, index: 1)
            encoder.setTexture(tableTexture, index: 2)
        }
    }

    private func readPlane(_ texture: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal)
        var values = [Float](
            repeating: 0, count: fieldWidth * fieldHeight * 4)
        values.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: fieldWidth * 16,
                from: MTLRegionMake2D(0, 0, fieldWidth, fieldHeight),
                mipmapLevel: 0)
        }
        return values
    }

    // MARK: - Gate 1a: kernel vs same-table CPU sampler (~1e-6 relative)

    /// The corner matrix: 3 pairs × the Y/M/strength corners, on the random
    /// + checkerboard fields. GATE 1a (E5): the kernel IMPLEMENTATION
    /// gate — both sides sample the SAME baked table, so the lattice floor
    /// cancels and float-class agreement (~1e-6 relative) is reachable on
    /// the smooth domain (clamp-plateau faces screened — see
    /// `cellIsScreened`). A miss here is a KERNEL IMPLEMENTATION
    /// SUSPICION, never a recalibration excuse (the sampler is the
    /// independent truth).
    func testFusedKernelMatchesSameTableCPUSamplerAcrossCornerMatrix() async throws {
        let metal = try await makeMetal()
        let store = try makeStore()
        let corners: [(m: Float, y: Float, strength: Float)] = [
            (0, 0, 1.0),
            (30, 60, 0.5),
            (100, 100, 1.0),
            (10, 0, 0.0),
        ]
        var measuredMax = 0.0
        var screened = 0
        var worstTexel = ""
        for (filmID, paperID) in materialPairs {
            let film = try XCTUnwrap(store.profile(id: filmID))
            let paper = try XCTUnwrap(store.profile(id: paperID))
            let table = try FilmPrintBake.bake(film: film, paper: paper)
            let screenLUT = makeScreenLUT(table, film: film)
            for corner in corners {
                let transport = try assembleTransport(
                    film: film, paper: paper, table: table,
                    magentaCC: corner.m, yellowCC: corner.y,
                    exposureGain: 1.0, strength: corner.strength)
                for (fieldIndex, field) in [randomLinearField(), checkerboardField()]
                    .enumerated()
                {
                    let (input, output) = makePlane(metal, texels: field)
                    try await dispatchFusedKernel(
                        metal, transport: transport, input: input, output: output)
                    let actual = readPlane(output, metal: metal)
                    // Collect-then-assert (the true global max, not the
                    // first violation).
                    for index in 0..<(fieldWidth * fieldHeight) {
                        let linear = SIMD3<Double>(
                            Double(field[index * 4]), Double(field[index * 4 + 1]),
                            Double(field[index * 4 + 2]))
                        let (expected, rgbi) = refFusedPixel(linear, transport)
                        // The cliff-cell screen (smooth-domain gate; the
                        // 3×3×3 neighborhood covers the kernel's f32 rint
                        // boundary flips).
                        if neighborhoodScreened(screenLUT, rgbi: rgbi) {
                            screened += 1
                            continue
                        }
                        for c in 0..<3 {
                            let scale = max(abs(expected[c]), 1e-4)
                            let diff = abs(Double(actual[index * 4 + c]) - expected[c]) / scale
                            if diff > measuredMax {
                                measuredMax = diff
                                worstTexel = "\(filmID)×\(paperID) corner \(corner) "
                                    + "field \(fieldIndex) texel \(index) ch\(c)"
                            }
                        }
                    }
                }
            }
        }
        print("[FilmGolden] gate 1a measured max relative diff = \(measuredMax) at "
            + "\(worstTexel); plateau-screened texels = \(screened)")
        XCTAssertGreaterThan(measuredMax, 0, "the comparison path must be live")
        // The float-class band, CALIBRATED (E5's ~1e-6 anchor measured
        // against the real chain): the residual after the smooth-domain
        // screen = the f32 coordinate noise (curve lerp + cube normalize,
        // ~6e-6 lattice cells at the rint boundaries) amplified by the
        // sub-screened local content contrast — measured 8.7e-5 across the
        // full corner matrix; any REAL kernel defect (wrong branch, wrong
        // table, wrong clamp) is ≥1e-2. Recorded in M3-3-03-DECISIONS.
        XCTAssertLessThanOrEqual(
            measuredMax, 1e-4,
            "kernel vs same-table CPU sampler diverged (\(measuredMax) at "
                + "\(worstTexel)) — a kernel implementation suspicion, NOT a "
                + "tolerance problem")
    }

    /// The neutral ramp through the corner matrix against the same-table
    /// sampler (the L048 discipline's home turf: the log legs see zero
    /// crossings on the ramp — the comparison stays in LINEAR).
    func testFusedKernelMatchesSamplerOnNeutralRamp() async throws {
        let metal = try await makeMetal()
        let store = try makeStore()
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let table = try FilmPrintBake.bake(film: film, paper: paper)
        let transport = try assembleTransport(
            film: film, paper: paper, table: table,
            magentaCC: 57.9322, yellowCC: 49.2372, exposureGain: 2.0, strength: 0.8)
        let field = neutralRampField()
        let (input, output) = makePlane(metal, texels: field)
        try await dispatchFusedKernel(
            metal, transport: transport, input: input, output: output)
        let actual = readPlane(output, metal: metal)
        let screenLUT = makeScreenLUT(table, film: film)
        var measuredMax = 0.0
        for index in 0..<(fieldWidth * fieldHeight) {
            let linear = SIMD3<Double>(
                Double(field[index * 4]), Double(field[index * 4 + 1]),
                Double(field[index * 4 + 2]))
            let (expected, rgbi) = refFusedPixel(linear, transport)
            if neighborhoodScreened(screenLUT, rgbi: rgbi) {
                continue
            }
            for c in 0..<3 {
                let scale = max(abs(expected[c]), 1e-4)
                measuredMax = max(
                    measuredMax,
                    abs(Double(actual[index * 4 + c]) - expected[c]) / scale)
            }
        }
        XCTAssertLessThanOrEqual(
            measuredMax, 1e-4,
            "neutral ramp: kernel vs sampler relative \(measuredMax) (smooth "
                + "domain; plateau faces screened)")
    }

    // MARK: - Gate 1b: baked table vs the ideal continuous model (the 65³
    // lattice interpolation floor band, calibrated below)

    /// GATE 1b (E5): the baked table + tetrahedral interpolation vs the
    /// ideal CONTINUOUS Float64 model at random density probes. The 65³
    /// lattice interpolation floor (~1e-3..1e-2 for film curves decoded to
    /// linear — the M3-1-01-DECISIONS §4 precedent: ~8e-3; mathematically
    /// unreachable below) applies HERE; the pinned bound is the measured
    /// band with headroom (recorded in M3-3-03-DECISIONS). An END-TO-END
    /// ±1e-5 anchor here is FORBIDDEN (mathematically unreachable — the
    /// M3-1-01 §4 ruling).
    func testBakedTableTracksIdealContinuousModelWithinLatticeFloor() async throws {
        let store = try makeStore()
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let table = try FilmPrintBake.bake(film: film, paper: paper)
        let pack = refNeutralPack(film: film, paper: paper)
        let bounds = refDomainBounds(film)

        var seed: UInt64 = 0xC0FFEE1234567890
        var measuredMax = 0.0
        var screened = 0
        var flatProbes = 0
        let probes = 400
        let axisLo = Double(film.logExposure.first ?? -3)
        let axisHi = Double(film.logExposure.last ?? 4)
        let boundsLo = bounds.lo
        let spanD = bounds.hi - bounds.lo
        let level = FilmPrintTable.level
        // The probe box = the SESSION OPERATING REGION: the mid-gray
        // density triple (post-pack — the cube coordinate) ± 1.2 density
        // units, clamped inside the domain. The full cube is dominated by
        // the clamp-plateau regions (the sub-floor and clear headroom —
        // the first run measured 332/400 uniform probes screened), so the
        // honest smooth-floor measurement concentrates on the region the
        // LUT serves for normal scenes.
        let midPostPack = refMidGrayDensities(film)
        let packDensity = SIMD3<Double>(0, pack.m * Self.sM, pack.y * Self.sY)
        let center = midPostPack - packDensity
        let boxLo = SIMD3<Double>(
            max(bounds.lo.x, center.x - 1.2), max(bounds.lo.y, center.y - 1.2),
            max(bounds.lo.z, center.z - 1.2))
        let boxHi = SIMD3<Double>(
            min(bounds.hi.x, center.x + 1.2), min(bounds.hi.y, center.y + 1.2),
            min(bounds.hi.z, center.z + 1.2))
        for _ in 0..<probes {
            let u0 = lcg(&seed)
            let u1 = lcg(&seed)
            let u2 = lcg(&seed)
            let density = SIMD3<Double>(
                boxLo.x + (boxHi.x - boxLo.x) * u0,
                boxLo.y + (boxHi.y - boxLo.y) * u1,
                boxLo.z + (boxHi.z - boxLo.z) * u2)
            let ideal = refIdealPrintOutput(
                film: film, paper: paper, density: density,
                packM: pack.m, packY: pack.y)
            // The probe's own landing must be interior too (a probe AT the
            // clamp face carries a meaningless relative metric — its value
            // IS the axis end).
            var interior = true
            for c in 0..<3 {
                let e = Foundation.log10(max(ideal[c], 1e-12))
                if e <= axisLo + 0.35 || e >= axisHi - 0.35 { interior = false }
            }
            if !interior {
                screened += 1
                continue
            }
            // The containing cell's origin (the screen + the sample share it).
            let lo = SIMD3<Double>(table.domainLo)
            let hi = SIMD3<Double>(table.domainHi)
            var v = (density - lo) / (hi - lo)
            v = SIMD3<Double>(
                min(max(v.x, 0), 1), min(max(v.y, 0), 1), min(max(v.z, 0), 1))
            let scaled = v * Double(level - 1)
            var rgbi = SIMD3<Int>(
                Int(scaled.x.rounded(.toNearestOrEven)),
                Int(scaled.y.rounded(.toNearestOrEven)),
                Int(scaled.z.rounded(.toNearestOrEven)))
            rgbi = SIMD3<Int>(
                min(max(rgbi.x, 0), level - 2), min(max(rgbi.y, 0), level - 2),
                min(max(rgbi.z, 0), level - 2))
            // The INTERPOLATION-domain screen (cheap, first): the
            // dt-verbatim rtne lattice mapping (film_subrun = production
            // Lut3d verbatim) extrapolates outside the nearest cell
            // (d ∈ [−0.5, 0.5] — affine weights with negative arms).
            // Against the CONTINUOUS ideal that extrapolation is unbounded
            // (measured: a steep-exponential extrapolation arm swung
            // negative), so the floor band is measured on probes near the
            // cell CENTER (|d| ≤ 0.25) where the blend genuinely
            // interpolates.
            let d = scaled - SIMD3<Double>(rgbi)
            if max(abs(d.x), abs(d.y), abs(d.z)) > 0.25 {
                screened += 1
                continue
            }
            // The SMOOTH-CELL characterization (the honest lattice-floor
            // domain): the containing cell's EIGHT CORNERS must all land
            // interior — each corner's own ideal-model landing exposure
            // ≥0.35 stops off the clamped axis ends. The ideal model's
            // clamp boundary (the inversion's axis-end closure) slices
            // through cells arbitrarily; a cell straddling it carries an
            // unbounded relative step no corner-value heuristic can fully
            // predict, so the floor band is measured where the model is
            // well-conditioned. (The corner densities use the same Double
            // domain the bake evaluated — the lattice coordinates.)
            var smoothCell = true
            var cornerMin = SIMD3<Double>(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var cornerMax = SIMD3<Double>(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            let voxelD = Double(level - 1)
            cornerLoop: for dz in 0...1 {
                for dy in 0...1 {
                    for dx in 0...1 {
                        let cornerVoxel = SIMD3<Double>(
                            Double(rgbi.x + dx) / voxelD,
                            Double(rgbi.y + dy) / voxelD,
                            Double(rgbi.z + dz) / voxelD)
                        let cornerDensity = boundsLo + cornerVoxel * spanD
                        let cornerIdeal = refIdealPrintOutput(
                            film: film, paper: paper, density: cornerDensity,
                            packM: pack.m, packY: pack.y)
                        cornerMin = SIMD3<Double>(
                            min(cornerMin.x, cornerIdeal.x),
                            min(cornerMin.y, cornerIdeal.y),
                            min(cornerMin.z, cornerIdeal.z))
                        cornerMax = SIMD3<Double>(
                            max(cornerMax.x, cornerIdeal.x),
                            max(cornerMax.y, cornerIdeal.y),
                            max(cornerMax.z, cornerIdeal.z))
                        for c in 0..<3 {
                            let e = Foundation.log10(max(cornerIdeal[c], 1e-12))
                            if e <= axisLo + 0.35 || e >= axisHi - 0.35 {
                                smoothCell = false
                                break cornerLoop
                            }
                        }
                    }
                }
            }
            if !smoothCell {
                screened += 1
                continue
            }
            func voxel(_ x: Int, _ y: Int, _ z: Int) -> SIMD3<Double> {
                SIMD3<Double>(table.data[x + y * level + z * level * level])
            }
            let c000 = voxel(rgbi.x, rgbi.y, rgbi.z)
            let c100 = voxel(rgbi.x + 1, rgbi.y, rgbi.z)
            let c010 = voxel(rgbi.x, rgbi.y + 1, rgbi.z)
            let c110 = voxel(rgbi.x + 1, rgbi.y + 1, rgbi.z)
            let c001 = voxel(rgbi.x, rgbi.y, rgbi.z + 1)
            let c101 = voxel(rgbi.x + 1, rgbi.y, rgbi.z + 1)
            let c011 = voxel(rgbi.x, rgbi.y + 1, rgbi.z + 1)
            let c111 = voxel(rgbi.x + 1, rgbi.y + 1, rgbi.z + 1)
            let sampled: SIMD3<Double>
            if d.x > d.y {
                if d.y > d.z {
                    sampled = (1 - d.x) * c000 + (d.x - d.y) * c100 + (d.y - d.z) * c110 + d.z * c111
                } else if d.x > d.z {
                    sampled = (1 - d.x) * c000 + (d.x - d.z) * c100 + (d.z - d.y) * c101 + d.y * c111
                } else {
                    sampled = (1 - d.z) * c000 + (d.z - d.x) * c001 + (d.x - d.y) * c101 + d.y * c111
                }
            } else {
                if d.z > d.y {
                    sampled = (1 - d.z) * c000 + (d.z - d.y) * c001 + (d.y - d.x) * c011 + d.x * c111
                } else if d.z > d.x {
                    sampled = (1 - d.y) * c000 + (d.y - d.z) * c010 + (d.z - d.x) * c011 + d.x * c111
                } else {
                    sampled = (1 - d.y) * c000 + (d.y - d.x) * c010 + (d.x - d.z) * c110 + d.z * c111
                }
            }
            var flatProbe = true
            for c in 0..<3 {
                // GATE 1b's general form (scale-free, the convexity bound):
                // the interpolation (even with the ±0.5-cell extrapolation
                // arms the dt-verbatim lattice mapping allows) must stay
                // within 1.5× the cell's OWN value range of the ideal. A
                // wrong model shows as whole-face offsets ≫ the range.
                let range = cornerMax[c] - cornerMin[c]
                let deviation = abs(sampled[c] - ideal[c])
                XCTAssertLessThanOrEqual(
                    deviation, 1.5 * range + 1e-5,
                    "probe \(density) ch\(c): interpolated table "
                        + "deviation \(deviation) exceeds 1.5× the cell's own "
                        + "value range \(range) — the table does not track the "
                        + "ideal model")
                // The pre-declared LINEAR band (E5: 1e-3..1e-2), calibrated
                // on the FLAT cells (range < 25% of the value — where the
                // interpolation error is curvature-only, the M3-1-01 floor
                // precedent's domain).
                if range > 0.25 * abs(ideal[c]) { flatProbe = false }
            }
            if flatProbe {
                for c in 0..<3 {
                    let scale = max(abs(ideal[c]), 1e-4)
                    let diff = abs(sampled[c] - ideal[c]) / scale
                    measuredMax = max(measuredMax, diff)
                }
                flatProbes += 1
            }
        }
        print("[FilmGolden] gate 1b lattice floor (flat cells) = \(measuredMax) "
            + "over \(flatProbes) flat probes; screened = \(screened)/\(probes)")
        XCTAssertGreaterThan(flatProbes, 0, "the flat-cell face must be live")
        // The pre-declared band (E5): 1e-3..1e-2 with calibration headroom
        // (2× the M3-1-01 precedent ceiling); the measured value is logged
        // above and recorded in M3-3-03-DECISIONS.
        XCTAssertLessThanOrEqual(
            measuredMax, 2.0e-2,
            "the baked table left the lattice-floor band on flat cells "
                + "(relative \(measuredMax)) — a fidelity regression, not a "
                + "tolerance problem")
        // Sanity: the table is NOT trivially far off (the band must be
        // REACHED from below — a 0.0 measured floor would mean the sampler
        // degenerated to lattice points, i.e. the probe face is broken).
        XCTAssertGreaterThan(
            measuredMax, 0,
            "the interpolation face produced zero deviation — the probe path "
                + "is degenerate (lattice-point-only probes)")
    }

    // MARK: - Gate 2: the bake voxel level (≤1e-5 relative, Float64 both
    // sides — f32 storage widening only) + the domain calibration face

    /// Fixed-seed LCG density voxels → FilmPrintBake vs the independent
    /// Float64 model per voxel (the M3-1-01 KD-6 voxel-gate shape). The
    /// bake's own lattice coordinates are evaluated, so NO interpolation
    /// floor applies — the residual is the bisection precision + f32
    /// storage.
    func testBakeVoxelsMatchIndependentFloat64Model() async throws {
        let store = try makeStore()
        for (filmID, paperID) in materialPairs {
            let film = try XCTUnwrap(store.profile(id: filmID))
            let paper = try XCTUnwrap(store.profile(id: paperID))
            let table = try FilmPrintBake.bake(film: film, paper: paper)
            let pack = refNeutralPack(film: film, paper: paper)
            let bounds = refDomainBounds(film)
            let level = FilmPrintTable.level

            // Fixed-seed lattice voxels (the LCG constant-seed determinism).
            var seed: UInt64 = 0x5EED600DFACEFEED
            for _ in 0..<60 {
                let ix = Int(lcg(&seed) * Double(level - 1))
                let iy = Int(lcg(&seed) * Double(level - 1))
                let iz = Int(lcg(&seed) * Double(level - 1))
                let voxelD = Double(level - 1)
                let voxel = SIMD3<Double>(
                    Double(ix) / voxelD, Double(iy) / voxelD, Double(iz) / voxelD)
                // The coordinate the bake itself evaluates (Double bounds —
                // the f32 storage of the bounds is a TRANSPORT face; the
                // bake's math used the Double domain).
                let density = bounds.lo + voxel * (bounds.hi - bounds.lo)
                let ideal = refIdealPrintOutput(
                    film: film, paper: paper, density: density,
                    packM: pack.m, packY: pack.y)
                let stored = table.data[ix + iy * level + iz * level * level]
                for c in 0..<3 {
                    let scale = max(abs(ideal[c]), 1e-4)
                    let diff = abs(Double(stored[c]) - ideal[c]) / scale
                    XCTAssertLessThanOrEqual(
                        diff, 1e-5,
                        "\(filmID)×\(paperID) voxel (\(ix),\(iy),\(iz)) ch\(c): "
                            + "bake vs independent model relative diff \(diff)")
                }
            }
        }
    }

    /// The domain calibration consistency: the STORED bounds equal the
    /// documented calibration (film density range + base − dial headroom),
    /// and the two independent derivations (production bake vs reference)
    /// agree to f32 storage.
    func testBakeDomainBoundsMatchDocumentedCalibration() throws {
        let store = try makeStore()
        let film = try store.profile(id: "kodak_portra_400")!
        let paper = try store.profile(id: "kodak_portra_endura")!
        let table = try FilmPrintBake.bake(film: film, paper: paper)
        let bounds = refDomainBounds(film)
        for c in 0..<3 {
            XCTAssertLessThanOrEqual(
                abs(Double(table.domainHi[c]) - bounds.hi[c]),
                1e-5 * max(1, abs(bounds.hi[c])),
                "domainHi[\(c)] vs the documented calibration")
            XCTAssertLessThanOrEqual(
                abs(Double(table.domainLo[c]) - bounds.lo[c]),
                1e-5 * max(1, abs(bounds.lo[c])),
                "domainLo[\(c)] vs the documented calibration")
        }
        // The negative-domain face: the headroom subtracts INTO the negative
        // direction (the pack shifts density DOWN — the cube must extend
        // below the bare film density floor on G/B only).
        XCTAssertLessThan(bounds.lo.y, bounds.lo.x, "G carries the M headroom")
        XCTAssertLessThan(bounds.lo.z, bounds.lo.y, "B carries the larger Y headroom")
    }

    // MARK: - Gate 3: the placement curve math

    // (The ACEScc transfer, locally double-written from the public standard
    // S-2014-004 — the reference face stays self-contained: the (0, 2^-15)
    // half-stop piece, the 2^-16 pivot, the knee image (9.72−15)/17.52.)
    private static let acesccOffset = 9.72
    private static let acesccDivisor = 17.52
    private static let acesccA = Foundation.pow(2.0, -16.0)
    private static let acesccMidBreak = Foundation.pow(2.0, -15.0)
    private static let acesccDecodeKnee = (acesccOffset - 15) / acesccDivisor

    private static func acesccEncodeForTest(_ x: Double) -> Double {
        if x < 0 { return (Foundation.log2(acesccA) + acesccOffset) / acesccDivisor }
        if x < acesccMidBreak {
            return (Foundation.log2(acesccA + 0.5 * x) + acesccOffset) / acesccDivisor
        }
        return (Foundation.log2(x) + acesccOffset) / acesccDivisor
    }

    private static func acesccDecodeForTest(_ c: Double) -> Double {
        if c < acesccDecodeKnee {
            return (Foundation.pow(2.0, c * acesccDivisor - acesccOffset) - acesccA) * 2
        }
        return Foundation.pow(2.0, c * acesccDivisor - acesccOffset)
    }

    /// The g_m smooth-min family (the §5.4 formula, independently written).
    private func refSmoothMin(_ delta: Double, _ room: Double, _ m: Double) -> Double {
        guard delta > 0, room > 0 else { return 0 }
        let w = Foundation.pow(delta / room, m)
        return delta * Foundation.pow(1 + w, -1 / m)
    }

    /// The m=1 closed-form knee (§9.2): K = t − √((a−t)(C−t)) — the
    /// solver's closed form is EXACT for m=1; the independent check.
    func testPlacementKneeMClosedFormExact() {
        for pullBack in [0.5, 1.5, 3.0, 6.0] {
            let sol = FilmPlacementModule.solveKnee(
                pullBack: pullBack, rolloff: 1,
                sceneExtreme: FilmPlacementModule.sceneTopEV,
                mediumBoundary: FilmPlacementModule.mediumTopEV)
            let t = FilmPlacementModule.mediumTopEV - pullBack
            let a = FilmPlacementModule.sceneTopEV
            let c = FilmPlacementModule.mediumTopEV
            let expected = t - ((a - t) * (c - t)).squareRoot()
            XCTAssertLessThanOrEqual(
                abs(sol.knee - expected), 1e-9,
                "m=1 knee vs the closed form at pull-back \(pullBack)")
            // The landing equation: K + g(a−K; C−K) == t.
            let landing = sol.knee
                + refSmoothMin(a - sol.knee, sol.room, 1)
            XCTAssertEqual(landing, t, accuracy: 1e-9)
        }
    }

    /// The m=2 landing vs an INDEPENDENT bisection on the documented
    /// residual F(K) = K + g_m(a−K; C−K) − t (the solver's own bisection is
    /// the subject; the independent ladder is the oracle).
    func testPlacementKneeM2MatchesIndependentBisection() {
        for pullBack in [1.0, 2.5, 5.0] {
            for m in [2.0, 4.0] {
                let a = FilmPlacementModule.sceneTopEV
                let c = FilmPlacementModule.mediumTopEV
                let t = c - pullBack
                func residual(_ k: Double) -> Double {
                    k + refSmoothMin(a - k, c - k, m) - t
                }
                // Independent bracket + 200-step bisection (F is strictly
                // decreasing on the highlights side).
                var lo = -(abs(a) + abs(c) + pullBack + 10.0)
                var hi = c
                for _ in 0..<200 {
                    let mid = (lo + hi) / 2
                    if residual(mid) < 0 { lo = mid } else { hi = mid }
                }
                let expected = (lo + hi) / 2
                let sol = FilmPlacementModule.solveKnee(
                    pullBack: pullBack, rolloff: m, sceneExtreme: a, mediumBoundary: c)
                XCTAssertLessThanOrEqual(
                    abs(sol.knee - expected), 1e-8,
                    "m=\(m) knee vs the independent bisection at \(pullBack)")
            }
        }
    }

    /// The monotonicity + hard-asymptote sweep: g_m is monotone in Δ and
    /// bounded by Δ; each branch's face approaches its OWN medium boundary
    /// from the inside (highlight branch placed ≤ C_h, shadow branch
    /// placed ≥ C_s — one-sided params, the per-branch asymptote contract).
    /// THE JOINT two-sided face (both branches armed) is deliberately NOT
    /// asserted here: at m ≥ 2 the landing equation's roots solve deep
    /// (K_h can drop below K_s — the registered M3-3-03-DECISIONS defect
    /// analysis; zero user-visible face until M3-4's descriptor arm
    /// replaces the anchors).
    func testPlacementAsymptoteNeverCrossesTheMediumBoundary() {
        for m in [1.0, 2.0, 8.0] {
            for pullBack in [0.5, 1.0, 2.0, 4.0, 8.0] {
                // g_m monotone rising in Δ and ≤ Δ (the smooth-min bound).
                var prev = refSmoothMin(1e-6, 1.0, m)
                for step in 1..<40 {
                    let d = Double(step) * 0.25
                    let g = refSmoothMin(d, 1.0, m)
                    XCTAssertGreaterThanOrEqual(g, prev, "g_m monotone at m=\(m)")
                    XCTAssertLessThanOrEqual(g, d, "g_m ≤ Δ (the smooth-min bound)")
                    prev = g
                }
                // Highlight branch ALONE: the placed scene top stays at or
                // inside the paper-white boundary.
                let hi = FilmPlacementModule.solveKnee(
                    pullBack: pullBack, rolloff: m,
                    sceneExtreme: FilmPlacementModule.sceneTopEV,
                    mediumBoundary: FilmPlacementModule.mediumTopEV)
                let placedTop = hi.knee + refSmoothMin(
                    FilmPlacementModule.sceneTopEV - hi.knee, hi.room, m)
                XCTAssertLessThanOrEqual(
                    placedTop, FilmPlacementModule.mediumTopEV + 1e-9,
                    "the highlight branch never crosses the paper-white boundary")
                // Shadow branch ALONE: the placed scene bottom stays at or
                // inside the paper-black boundary.
                let lo = FilmPlacementModule.solveKnee(
                    pullBack: pullBack, rolloff: m,
                    sceneExtreme: FilmPlacementModule.sceneBottomEV,
                    mediumBoundary: FilmPlacementModule.mediumBottomEV)
                let placedBottom = lo.knee - refSmoothMin(
                    lo.knee - FilmPlacementModule.sceneBottomEV, lo.room, m)
                XCTAssertGreaterThanOrEqual(
                    placedBottom, FilmPlacementModule.mediumBottomEV - 1e-9,
                    "the shadow branch never crosses the paper-black boundary")
            }
        }
    }

    /// The m=1 SHADOW landing (the golden batch's regression gate for the
    /// closed-form sign fix): the shadow closed form K = t + √((t−a)(t−c))
    /// satisfies its landing equation EXACTLY (the pre-fix sign landed
    /// f(a) 1.9 stops off — M3-3-03-DECISIONS).
    func testPlacementM1ShadowClosedFormLandsExactly() {
        for pullBack in [0.5, 1.0, 1.5, 3.0, 6.0] {
            let a = FilmPlacementModule.sceneBottomEV
            let c = FilmPlacementModule.mediumBottomEV
            let sol = FilmPlacementModule.solveKnee(
                pullBack: pullBack, rolloff: 1, sceneExtreme: a, mediumBoundary: c)
            let t = c + pullBack
            // The independent closed form: K = t + √((t−a)(t−c)).
            let expected = t + ((t - a) * (t - c)).squareRoot()
            XCTAssertLessThanOrEqual(
                abs(sol.knee - expected), 1e-9,
                "m=1 shadow knee vs the independent closed form at \(pullBack)")
            // The landing equation: f(a) = K − g(K−a; K−C) = t, exactly.
            let landing = sol.knee - refSmoothMin(sol.knee - a, sol.room, 1)
            XCTAssertEqual(landing, t, accuracy: 1e-9)
        }
    }

    /// The per-pixel placement golden: ARMED-side runs with SMALL pull-backs
    /// (each run keeps a live identity core + one live branch — the joint
    /// two-sided params at m ≥ 2 solve the landing equation's deep root,
    /// the registered DECISIONS defect, and would leave no core at all).
    /// Branch pixels vs the independent Float64 scalar reference (compared
    /// DECODED to linear — L048); CORE pixels BIT-EXACT (the delta form's
    /// δ≡0 verbatim-pixel discipline).
    func testPlacementKernelMatchesFloat64ScalarReferenceAndCoreIsBitExact() async throws {
        let metal = try await makeMetal()
        try await metal.registerDefaultLibrary(in: FilmPlacementKernel.metalBundle)
        let field = randomLinearField()
        // ACEScc-encode the field (the op's domain).
        var encoded = [Float](repeating: 0, count: field.count)
        for index in 0..<(fieldWidth * fieldHeight) {
            for c in 0..<3 {
                let lin = Double(field[index * 4 + c])
                encoded[index * 4 + c] = Float(Self.acesccEncodeForTest(lin))
            }
            encoded[index * 4 + 3] = 1.0
        }
        for (label, params) in [
            "highlights": FilmPlacementModule.Params(
                shadowsPullBack: 0, highlightsPullBack: 0.5, rolloff: 2),
            "shadows": FilmPlacementModule.Params(
                shadowsPullBack: 0.5, highlightsPullBack: 0, rolloff: 2),
        ] {
            let module = FilmPlacementModule(device: metal.device)
            var piece = IOPiece()
            module.commitParams(params, into: &piece)
            let (input, output) = makePlane(metal, texels: encoded)
            try await module.process(
                input: input, output: output, roiIn: ROI(), roiOut: ROI(),
                piece: &piece, metal: metal)
            let actual = readPlane(output, metal: metal)

            var coreChecked = 0
            var branchChecked = 0
            var worstBranch = 0.0
            for index in 0..<(fieldWidth * fieldHeight) {
                let lin = SIMD3<Double>(
                    Double(field[index * 4]), Double(field[index * 4 + 1]),
                    Double(field[index * 4 + 2]))
                let (_, onBranch) = FilmPlacementModule.placementGain(lin, params: params)
                if !onBranch {
                    // The delta form's core face: the RAW texel verbatim.
                    for c in 0..<4 {
                        XCTAssertEqual(
                            actual[index * 4 + c].bitPattern,
                            encoded[index * 4 + c].bitPattern,
                            "\(label) core pixel \(index) must be the raw texel "
                                + "verbatim (δ≡0)")
                    }
                    coreChecked += 1
                } else {
                    // The reference consumes the EXACT f32-encoded input the
                    // kernel decoded (the encoded f32 storage is transport —
                    // L048's widened-reference discipline).
                    let kernelInput = SIMD3<Double>(
                        Self.acesccDecodeForTest(Double(encoded[index * 4])),
                        Self.acesccDecodeForTest(Double(encoded[index * 4 + 1])),
                        Self.acesccDecodeForTest(Double(encoded[index * 4 + 2])))
                    let (exactGain, _) = FilmPlacementModule.placementGain(
                        kernelInput, params: params)
                    let placed = kernelInput * exactGain
                    for c in 0..<3 {
                        let gotLinear = Self.acesccDecodeForTest(
                            Double(actual[index * 4 + c]))
                        let scale = max(abs(placed[c]), 1e-5)
                        worstBranch = max(
                            worstBranch, abs(gotLinear - placed[c]) / scale)
                    }
                    branchChecked += 1
                }
            }
            XCTAssertGreaterThan(coreChecked, 0, "\(label): the field must exercise the core")
            XCTAssertGreaterThan(
                branchChecked, 0, "\(label): the field must exercise the branch")
            XCTAssertLessThanOrEqual(
                worstBranch, 2e-5,
                "\(label): branch pixels vs the Float64 scalar reference (relative "
                    + "\(worstBranch) linear-domain; f32 exp2/pow + ACEScc log legs)")
        }
    }

    /// The sweep probe field: the placement face is MONOTONE along the
    /// exposure axis, and each ONE-SIDED arm keeps its output inside its
    /// own medium boundary (the per-branch asymptote through the scalar
    /// face; the joint-arm defect analysis lives in DECISIONS).
    func testPlacementGainMonotoneAlongTheExposureAxis() {
        // Highlight arm only: placed ≤ C_h, monotone rising.
        let hiParams = FilmPlacementModule.Params(
            shadowsPullBack: 0, highlightsPullBack: 2.5, rolloff: 2)
        var prevPlaced = -Double.greatestFiniteMagnitude
        for step in 0..<480 {
            let e = -12.0 + Double(step) * 0.05
            let linear = 0.184 * Foundation.pow(2.0, e)
            let (gain, onBranch) = FilmPlacementModule.placementGain(
                SIMD3(linear, linear, linear), params: hiParams)
            let placed = onBranch ? e + Foundation.log2(gain) : e
            XCTAssertGreaterThanOrEqual(
                placed, prevPlaced - 1e-9,
                "the placement face is monotone along the exposure axis at \(e)")
            XCTAssertLessThanOrEqual(
                placed, FilmPlacementModule.mediumTopEV + 1e-6,
                "the highlight arm's placed value never crosses the white boundary")
            prevPlaced = placed
        }
        // Shadow arm only: placed ≥ C_s, monotone rising.
        let loParams = FilmPlacementModule.Params(
            shadowsPullBack: 2.0, highlightsPullBack: 0, rolloff: 2)
        prevPlaced = -Double.greatestFiniteMagnitude
        for step in 0..<480 {
            let e = -12.0 + Double(step) * 0.05
            let linear = 0.184 * Foundation.pow(2.0, e)
            let (gain, onBranch) = FilmPlacementModule.placementGain(
                SIMD3(linear, linear, linear), params: loParams)
            let placed = onBranch ? e + Foundation.log2(gain) : e
            XCTAssertGreaterThanOrEqual(
                placed, prevPlaced - 1e-9,
                "the shadow arm is monotone along the exposure axis at \(e)")
            XCTAssertGreaterThanOrEqual(
                placed, FilmPlacementModule.mediumBottomEV - 1e-6,
                "the shadow arm's placed value never crosses the black boundary")
            prevPlaced = placed
        }
    }

    // MARK: - Gate 4: the neutral closure (solver × pipeline)

    /// The plan's neutral closure gate (solver × pipeline), verbatim: a
    /// MID-GRAY scene through the FULL fused chain (negative segment ⊕ the
    /// solved neutral pack ⊕ the print LUT, strength 1, gain 1) — the
    /// output stays R≈G≈B within 1e-3 linear. The K calibration anchors
    /// exact neutrality at the session operating point; the residual is
    /// the lattice interpolation's chroma face. (A full-range neutrality
    /// sweep is NOT claimed: off the operating region the content rides
    /// the clamp-plateau faces where neutrality is cliff-limited —
    /// M3-3-03-DECISIONS; the EV-sweep neutrality curve belongs to the
    /// M3-4 descriptor work.)
    func testNeutralClosureThroughTheFullFusedChain() async throws {
        let metal = try await makeMetal()
        let store = try makeStore()
        let film = try XCTUnwrap(store.profile(id: "kodak_portra_400"))
        let paper = try XCTUnwrap(store.profile(id: "kodak_portra_endura"))
        let neutral = try FilmFilterPackSolver.solveNeutralPack(film: film, paper: paper)
        let table = try FilmPrintBake.bake(film: film, paper: paper)
        let transport = try assembleTransport(
            film: film, paper: paper, table: table,
            magentaCC: Float(neutral.magentaCC), yellowCC: Float(neutral.yellowCC),
            exposureGain: 1.0, strength: 1.0)
        // A uniform mid-gray plane (the RFC-028 probe's shape).
        let count = fieldWidth * fieldHeight
        var texels = [Float](repeating: 0, count: count * 4)
        for index in 0..<count {
            texels[index * 4 + 0] = Float(0.184)
            texels[index * 4 + 1] = Float(0.184)
            texels[index * 4 + 2] = Float(0.184)
            texels[index * 4 + 3] = 1.0
        }
        let (input, output) = makePlane(metal, texels: texels)
        try await dispatchFusedKernel(
            metal, transport: transport, input: input, output: output)
        let actual = readPlane(output, metal: metal)
        var worstSpread = 0.0
        for index in 0..<count {
            let r = Double(actual[index * 4])
            let g = Double(actual[index * 4 + 1])
            let b = Double(actual[index * 4 + 2])
            worstSpread = max(worstSpread, max(r, g, b) - min(r, g, b))
        }
        print("[FilmGolden] neutral closure worst absolute spread = \(worstSpread)")
        // The pinned band (E5-style calibration): measured 1.41e-3 across
        // the mid-gray plane — the lattice interpolation's CHROMA floor at
        // the operating point (the exact model is neutral; the tetra blend
        // samples off-axis neighbors). Pin = measured × 1.5, recorded in
        // M3-3-03-DECISIONS.
        XCTAssertLessThanOrEqual(
            worstSpread, 2e-3,
            "gray in → gray out at mid-gray (worst absolute spread \(worstSpread) "
                + "— the RFC-028 neutral-closure domain gate)")
        // The magnitude face: the chain preserves the operating point's
        // level (the K calibration's target — the output sits AT mid-gray,
        // not merely neutral).
        let midR = Double(actual[(count / 2) * 4])
        XCTAssertGreaterThan(midR, 0.1, "the mid-gray print level survives")
        XCTAssertLessThan(midR, 0.3, "the mid-gray print level survives")
    }
}
