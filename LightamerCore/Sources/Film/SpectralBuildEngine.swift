import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SpectralBuildEngine — the Float64 build-time engine of the spectral film
// core (M8-1a T4). Per film×paper pair it emits every table the M8-1b GPU
// kernels consume (the golden twin and the table supplier):
//
//   • tc_lut  — the 192² integrated film-exposure table: the SHARED
//     coefficient table (SpectralTcFit) expanded to per-cell spectra,
//     folded with the film's windowed sensitivities and integrated over
//     the 81-wavelength axis (irradiance kind — the single arm, X1), with
//     the input gamut compression REMAP PRE-FOLDED (review M1: the
//     upstream default-on `input_gamut_compress` — new[tc] =
//     old[compress(tc)], radial xy Reinhard knee (0,1,6) toward the
//     spectral-locus polygon, centered on the projection white — the
//     centered-on-proj_xy discipline);
//   • m_in / m_out — CAT16(source white → projection white)·input RGB→XYZ
//     and output XYZ→RGB·CAT02(viewing white → output white);
//   • print + scan 3D tables — 33³ Float64 exact integrals (the ONLY
//     81-wavelength loops beside the tc expansion; upstream build_lut3d)
//     with the monotone-PCHIP preparation (per-axis slopes + per-cell
//     cmin/cmax clamp faces — the D-M8-3 adoption) stored float;
//   • the neutral balance — the sRGB 0.184 mid-gray walked through the
//     chain head (sRGB matrix per the upstream note, the tc gather, the
//     RAW stock curves) and the print exposure normalized by the
//     geometric-mean factor (the four-branch form; defaults = upstream
//     reference: normalize on, compensation off → f_mid);
//   • the curve faces — the film develop curves normalized (minus the
//     per-channel floor) on the 256-point log-exposure grid, the print
//     curves, the host-double-inverted grid steps (the X5 nail ② host
//     form), and the constant blocks.
//
// FLOAT64 POSTURE: every computation runs in Double; storage is Float
// (the value copy). The per-pixel Float64 REFERENCE faces live in
// `SpectralFilmRuntime` — the golden twin the M8-1b kernels are checked
// against (X5's host side; the MSL nails land in M8-1b).
//
// PLACES DELIBERATELY NOT REACHED (typed placeholders, fail-closed):
// preflash (default 0 = upstream identity-off), the black/white-point
// fits (default off), the adaptation surface (D-M8-7: constant off), the
// DIR coupler block (per-PIXEL runtime, M8-1b/M8-2 scope), the output
// OkLCh gamut compression (M8-1b scope per the plan's T4 table list).
//
// LICENSING: the math is assembled from public standards and the public
// papers; dt's module is the reading guide only (定位引用零转录 — no code
// or data bytes transcribed; the profile data arrives through the typed
// consumer face).
// ─────────────────────────────────────────────────────────────────────────────

/// One prepared 3D PCHIP table set (lut + per-axis slopes + per-cell
/// clamp bounds; the D-M8-3 adoption, stored float of Float64 values).
public struct SpectralFilmPchipSet: Sendable, Equatable {
    /// The lattice side (33 — the upstream lut_steps).
    public static let steps = 33

    public let lut: [Float]      // steps³ × 3
    public let sx: [Float]       // steps³ × 3 (x-axis slopes)
    public let sy: [Float]
    public let sz: [Float]
    public let cmin: [Float]     // (steps−1)³ × 3
    public let cmax: [Float]

    public static func == (lhs: SpectralFilmPchipSet, rhs: SpectralFilmPchipSet) -> Bool {
        lhs.lut.elementsEqual(rhs.lut, by: { $0.bitPattern == $1.bitPattern })
            && lhs.sx.elementsEqual(rhs.sx, by: { $0.bitPattern == $1.bitPattern })
            && lhs.sy.elementsEqual(rhs.sy, by: { $0.bitPattern == $1.bitPattern })
            && lhs.sz.elementsEqual(rhs.sz, by: { $0.bitPattern == $1.bitPattern })
            && lhs.cmin.elementsEqual(rhs.cmin, by: { $0.bitPattern == $1.bitPattern })
            && lhs.cmax.elementsEqual(rhs.cmax, by: { $0.bitPattern == $1.bitPattern })
    }
}

/// The per-sim table bundle (the M8-1b upload face's data content).
public struct SpectralFilmTables: Sendable, Equatable {
    public let tcSide: Int
    /// The integrated film-exposure table, 192² × 3 (row-major, u-major:
    /// index = i·side + j, i the u axis, j the v axis).
    public let tcLut: [SIMD3<Float>]
    /// The chromaticity the input is projected under (the film reference
    /// illuminant — the compression center and the CAT16 target).
    public let projXy: SIMD2<Float>
    public let mIn: [[Float]]    // 3×3 row-major
    public let mOut: [[Float]]
    /// The constant matrix blocks (the M8-1b upload companions).
    public let cat16: [[Float]]
    public let cat02: [[Float]]
    public let oklabM1: [[Float]]
    public let oklabM2: [[Float]]

    public let print: SpectralFilmPchipSet
    public let scan: SpectralFilmPchipSet

    /// The film develop curves, normalized (minus the per-channel floor),
    /// 256×3 row-major [i·3+c] — the runtime develop's lookup face.
    public let curvesNorm: [Float]
    /// The print (paper) develop curves, 256×3 — the print_develop face.
    public let printCurves: [Float]
    public let le0: Float
    public let leStep: Float
    /// The host-double-inverted grid step rounded to float (the X5 nail ②
    /// host form — the device never re-derives it).
    public let invLeStep: Float
    public let filmDmax: SIMD3<Float>
    public let filmDmin: SIMD3<Float>

    public let enlLo: SIMD3<Float>
    public let enlHi: SIMD3<Float>
    public let enlInvRange: SIMD3<Float>
    public let scanLo: SIMD3<Float>
    public let scanHi: SIMD3<Float>
    public let scanInvRange: SIMD3<Float>

    /// The print-exposure normalization (the geometric-mean mid-gray
    /// factor) and the print exposure in log10.
    public let midgrayFactor: Float
    public let log10PrintExposure: Float
    /// The exposure scale — identically 1.0: the exposure EV rides the
    /// solve-gain consumption layer (D-M8-8), never the expose chain head.
    public let evScale: Float

    /// The print- and viewing-leg illuminant SPDs (dichroic-filtered
    /// enlarger light; the viewing SPD) and the viewing luminance normal.
    public let illumPrint: [Float]   // 81
    public let illumView: [Float]    // 81
    public let xyzNorm: Float

    /// The mid-gray chain-head print exposure AFTER the mid-gray factor
    /// (the closure gate's measurement face: its channel scatter is the
    /// neutrality metric).
    public let midgrayPrintRaw: SIMD3<Float>
    /// The print CC triple the build resolved (the solved neutral pair's
    /// [0, M, Y]; the M8-2 solve face's seed and the audit face).
    public let solvedPrintCC: SIMD3<Float>

    /// Typed placeholders (v1 identities): preflash off (exposure 0 →
    /// zero raw), the black/white-point fits off.
    public let preflashRaw: SIMD3<Float>
    public let blackWhiteActive: Bool

    /// The structural byte volume (the carrier budget face: tc_lut
    /// 442,368 B + ≈2.1 MB per PCHIP set — the RESEARCH §4.1 order).
    public var tableByteCount: Int {
        let pchipBytes = { (set: SpectralFilmPchipSet) -> Int in
            (set.lut.count + set.sx.count + set.sy.count + set.sz.count
                + set.cmin.count + set.cmax.count) * MemoryLayout<Float>.size
        }
        return tcLut.count * MemoryLayout<SIMD3<Float>>.size
            + pchipBytes(print) + pchipBytes(scan)
            + (curvesNorm.count + printCurves.count) * MemoryLayout<Float>.size
    }

    public static func == (lhs: SpectralFilmTables, rhs: SpectralFilmTables) -> Bool {
        lhs.tcSide == rhs.tcSide && lhs.projXy == rhs.projXy
            && zip(lhs.tcLut, rhs.tcLut).allSatisfy { $0 == $1 }
            && lhs.mIn.elementsEqual(rhs.mIn, by: { $0.elementsEqual($1, by: { $0.bitPattern == $1.bitPattern }) })
            && lhs.mOut.elementsEqual(rhs.mOut, by: { $0.elementsEqual($1, by: { $0.bitPattern == $1.bitPattern }) })
            && lhs.print == rhs.print && lhs.scan == rhs.scan
            && lhs.curvesNorm.elementsEqual(rhs.curvesNorm, by: { $0.bitPattern == $1.bitPattern })
            && lhs.printCurves.elementsEqual(rhs.printCurves, by: { $0.bitPattern == $1.bitPattern })
            && lhs.le0.bitPattern == rhs.le0.bitPattern
            && lhs.leStep.bitPattern == rhs.leStep.bitPattern
            && lhs.invLeStep.bitPattern == rhs.invLeStep.bitPattern
            && lhs.filmDmax == rhs.filmDmax && lhs.filmDmin == rhs.filmDmin
            && lhs.enlLo == rhs.enlLo && lhs.enlHi == rhs.enlHi
            && lhs.enlInvRange == rhs.enlInvRange
            && lhs.scanLo == rhs.scanLo && lhs.scanHi == rhs.scanHi
            && lhs.scanInvRange == rhs.scanInvRange
            && lhs.midgrayFactor.bitPattern == rhs.midgrayFactor.bitPattern
            && lhs.log10PrintExposure.bitPattern == rhs.log10PrintExposure.bitPattern
            && lhs.evScale.bitPattern == rhs.evScale.bitPattern
            && lhs.illumPrint.elementsEqual(rhs.illumPrint, by: { $0.bitPattern == $1.bitPattern })
            && lhs.illumView.elementsEqual(rhs.illumView, by: { $0.bitPattern == $1.bitPattern })
            && lhs.xyzNorm.bitPattern == rhs.xyzNorm.bitPattern
            && lhs.midgrayPrintRaw == rhs.midgrayPrintRaw
            && lhs.solvedPrintCC == rhs.solvedPrintCC
            && lhs.preflashRaw == rhs.preflashRaw
            && lhs.blackWhiteActive == rhs.blackWhiteActive
    }
}

/// The build-time typed errors (fail-closed).
public enum SpectralBuildError: Error, Equatable {
    /// The profile's spectral face degraded at decode (nil after the
    /// tolerant gates) — the build cannot proceed without it.
    case missingSpectralFace(String)
    /// A named illuminant is not in the assembled SPD set.
    case unknownIlluminant(String)
    /// The projection face failed (all-null series or field degraded).
    case projectionUnavailable(String)
    /// A placeholder arm was explicitly enabled — v1 never consumes it.
    case unsupportedInV1(String)
}

/// The Float64 build-time engine (M8-1a T4).
public enum SpectralBuildEngine {

    // MARK: - Parameters

    public struct Parameters: Sendable {
        /// The enlarger light source (the SPD set name) and the print CC
        /// triple (0-100) applied through the dichroic transmissions.
        /// `printCC == nil` (the default) = the build SOLVES its own pair
        /// CC for a neutral mid-gray print (the spectral-domain neutral
        /// balance — the measured upstream CC table's premises do not
        /// carry over self-approximated dichroics, measured ~4e-1 miss at
        /// the table's values); a non-nil triple is pinned verbatim
        /// (C rides along but the solve convention keeps it 0).
        public var enlargerIlluminant: String
        public var printCC: SIMD3<Double>?
        /// The mid-gray four-branch switches (defaults = the upstream
        /// reference: normalize on, compensation off → f_mid).
        public var normalizePrintExposure: Bool
        public var printExposureCompensation: Bool
        /// The print exposure (linear; its log10 is the runtime face).
        public var printExposure: Double
        /// The density floor per channel (the grain-domain domain floor;
        /// v1 carries no decoded pack floors → the neutral default 0).
        public var grainDensityMin: SIMD3<Double>
        /// The input/output working spaces (defaults: linear Rec2020,
        /// D65 white — the project's working posture).
        public var inputSpace: SpectralConstants.RGBSpace
        public var outputSpace: SpectralConstants.RGBSpace
        /// The tc grid side and the 3D lattice (the upstream values).
        public var tcSide: Int
        public var lutSteps: Int
        // ---- typed placeholders (v1 identities; nonzero/on = error) ----
        /// Upstream `preflash_exposure`, default 0 = identity-off. v1
        /// never consumes it (review m7).
        public var preflashExposure: Double
        /// Upstream's black/white-point fits — default off.
        public var scanBlackCorrection: Bool
        public var scanWhiteCorrection: Bool
        /// Upstream's adaptation surface (D-M8-7: constant off in v1 —
        /// the profile carries the coefficients but the reference runtime
        /// resolves the switch off).
        public var adaptationSurface: Bool

        public init(
            enlargerIlluminant: String = "TH-KG3",
            printCC: SIMD3<Double>? = nil,
            normalizePrintExposure: Bool = true,
            printExposureCompensation: Bool = false,
            printExposure: Double = 1.0,
            grainDensityMin: SIMD3<Double> = SIMD3<Double>(0, 0, 0),
            inputSpace: SpectralConstants.RGBSpace = SpectralConstants.rec2020,
            outputSpace: SpectralConstants.RGBSpace = SpectralConstants.rec2020,
            tcSide: Int = SpectralTcFit.gridSide,
            lutSteps: Int = SpectralFilmPchipSet.steps,
            preflashExposure: Double = 0.0,
            scanBlackCorrection: Bool = false,
            scanWhiteCorrection: Bool = false,
            adaptationSurface: Bool = false
        ) {
            self.enlargerIlluminant = enlargerIlluminant
            self.printCC = printCC
            self.normalizePrintExposure = normalizePrintExposure
            self.printExposureCompensation = printExposureCompensation
            self.printExposure = printExposure
            self.grainDensityMin = grainDensityMin
            self.inputSpace = inputSpace
            self.outputSpace = outputSpace
            self.tcSide = tcSide
            self.lutSteps = lutSteps
            self.preflashExposure = preflashExposure
            self.scanBlackCorrection = scanBlackCorrection
            self.scanWhiteCorrection = scanWhiteCorrection
            self.adaptationSurface = adaptationSurface
        }
    }

    // MARK: - Errors

    private static func requireSpectral(
        _ field: @autoclosure () -> [[Float]]?, _ name: String, _ stock: String
    ) throws -> [[Float]] {
        guard let value = field() else {
            throw SpectralBuildError.missingSpectralFace("\(stock): \(name)")
        }
        return value
    }

    // MARK: - The shared coefficient table memo (film-independent)

    private static let coefficientMemoLock = NSLock()
    private static var coefficientMemo: [UInt64: [SpectralTcFit.Coefficients]] = [:]

    /// The in-process memo key (L013 spirit: StableHash over the table
    /// identity — side, axis, CMFs; no Swift Hasher).
    private static func coefficientMemoKey(
        axis: [Double], cmfs: [[Double]], side: Int
    ) -> UInt64 {
        func fold(_ hash: UInt64, _ value: UInt64) -> UInt64 {
            var v = value
            return withUnsafeBytes(of: &v) {
                StableHash.combine(hash, UnsafeRawBufferPointer($0))
            }
        }
        var hash = fold(StableHash.fnvOffsetBasis, UInt64(side))
        for v in axis {
            hash = fold(hash, v.bitPattern)
        }
        for row in cmfs {
            for v in row {
                hash = fold(hash, v.bitPattern)
            }
        }
        return hash
    }

    /// The shared coefficient table (the film-independent fit — computed
    /// once per process identity, the plan risk-clause's build-cache
    /// remedy for the seconds-band fit).
    public static func sharedCoefficientTable(
        axis: [Double], cmfs: [[Double]], side: Int
    ) -> [SpectralTcFit.Coefficients] {
        let key = coefficientMemoKey(axis: axis, cmfs: cmfs, side: side)
        coefficientMemoLock.lock()
        if let hit = coefficientMemo[key] {
            coefficientMemoLock.unlock()
            return hit
        }
        coefficientMemoLock.unlock()
        let table = SpectralTcFit.fitCoefficientTable(
            axis: axis, cmfs: cmfs, side: side)
        coefficientMemoLock.lock()
        coefficientMemo[key] = table
        coefficientMemoLock.unlock()
        return table
    }

    // MARK: - The build

    /// Build the per-sim tables for one film×paper pair. Float64
    /// throughout; the lattice fills parallelize per slice (deterministic
    /// index merge).
    public static func build(
        film: FilmProfile, paper: FilmProfile,
        parameters: Parameters = Parameters()
    ) throws -> SpectralFilmTables {
        // ---- placeholders fail closed (v1 identities) ----
        if parameters.preflashExposure != 0.0 {
            throw SpectralBuildError.unsupportedInV1("preflash")
        }
        if parameters.scanBlackCorrection || parameters.scanWhiteCorrection {
            throw SpectralBuildError.unsupportedInV1("black/white-point fits")
        }
        if parameters.adaptationSurface {
            throw SpectralBuildError.unsupportedInV1("adaptation surface")
        }

        let axis = SpectralConstantsData.wavelengthsNm
        let cmfs = SpectralConstantsData.cmfs
        let stock = film.info.stock ?? "?"

        // ---- the spectral faces (typed, fail-closed on degradation) ----
        let logSensitivity = try requireSpectral(
            film.logSensitivity, "log_sensitivity", stock)
        let filmSens: [[Double]] = logSensitivity.map { row in
            row.map { value in
                let v = pow(10.0, Double(value))
                return v.isFinite ? v : 0.0
            }
        }
        let filmBase = try film.baseDensityProjected()
            ?? { throw SpectralBuildError.projectionUnavailable("\(stock): base_density") }()
        let filmChan = try film.channelDensityProjected()
            ?? { throw SpectralBuildError.projectionUnavailable("\(stock): channel_density") }()
        // channelDensityProjected is channel-major [[Double]] 3×81 —
        // reassemble [λ][c].
        var filmChanDens = [[Double]](
            repeating: [Double](repeating: 0, count: 3), count: axis.count)
        for l in 0..<axis.count {
            for c in 0..<3 {
                let series = filmChan[c]
                guard l < series.count else {
                    throw SpectralBuildError.projectionUnavailable(
                        "\(stock): channel_density channel \(c)")
                }
                filmChanDens[l][c] = series[l]
            }
        }

        // ---- the illuminants ----
        guard let refName = film.info.referenceIlluminant,
            let refSPD = SpectralConstants.spd(named: refName) else {
            throw SpectralBuildError.unknownIlluminant(
                film.info.referenceIlluminant ?? "nil (reference)")
        }
        let projXyD = SpectralConstants.chromaticity(spd: refSPD)
        guard let viewName = paper.info.viewingIlluminant
            ?? film.info.viewingIlluminant,
            let viewSPD = SpectralConstants.spd(named: viewName) else {
            throw SpectralBuildError.unknownIlluminant(
                paper.info.viewingIlluminant ?? film.info.viewingIlluminant
                    ?? "nil (viewing)")
        }
        guard let enlargerSPD = SpectralConstants.spd(
            named: parameters.enlargerIlluminant) else {
            throw SpectralBuildError.unknownIlluminant(
                parameters.enlargerIlluminant)
        }

        // ---- m_in (CAT16 · input RGB→XYZ onto the projection white) ----
        let inputWhiteD = parameters.inputSpace.whiteXy
        let catIn = SpectralConstants.catMatrix(
            coneMatrix: SpectralConstants.cat16, srcXy: inputWhiteD,
            dstXy: SIMD2<Double>(projXyD.x, projXyD.y))
        let mInD = catIn.multiply(parameters.inputSpace.rgbToXYZ)

        // ---- the windowed sensitivities (erf4 bandpass, white-balance
        //      preserving — the per-channel renormalization against the
        //      film's reference illuminant) ----
        var sensW = filmSens
        if case .window(let window)? = film.adaptationWindowParams, window.count == 4 {
            let cUV = Double(window[0]), sUV = Double(window[1])
            let cIR = Double(window[2]), sIR = Double(window[3])
            var w = [Double](repeating: 0, count: axis.count)
            for l in 0..<axis.count {
                let wl = axis[l]
                let eUV = 0.5 * (1.0 + erf((wl - cUV) / (sUV * 2.0.squareRoot())))
                let eIR = 0.5 * (1.0 - erf((wl - cIR) / (sIR * 2.0.squareRoot())))
                w[l] = eUV * eIR
            }
            for m in 0..<3 {
                var num = 0.0, den = 0.0
                for l in 0..<axis.count {
                    num += sensW[l][m] * refSPD[l] * w[l]
                    den += sensW[l][m] * refSPD[l]
                }
                let norm = den > 0 ? num / den : 1.0
                for l in 0..<axis.count { sensW[l][m] *= w[l] / norm }
            }
        }

        // ---- the tc expansion (the ONLY fine-grid 81-wavelength loop) ----
        let side = parameters.tcSide
        let coefficients = sharedCoefficientTable(
            axis: axis, cmfs: cmfs, side: side)
        var tcRaw = [SIMD3<Double>](
            repeating: .zero, count: side * side)
        tcRaw.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: side) { i in
                for j in 0..<side {
                    let c = coefficients[i * side + j]
                    var acc = SIMD3<Double>.zero
                    for l in 0..<axis.count {
                        let s = SpectralTcFit.spectrum(
                            wavelength: axis[l], coefficients: c)
                        acc.x += s * sensW[l][0]
                        acc.y += s * sensW[l][1]
                        acc.z += s * sensW[l][2]
                    }
                    buffer[i * side + j] = acc
                }
            }
        }

        // ---- the input gamut compression remap (pre-folded; review M1) ----
        let locus = SpectralConstants.spectralLocusPolygon()
        let projXy = SIMD2<Double>(projXyD.x, projXyD.y)
        var tcLutD = tcRaw
        tcLutD.withUnsafeMutableBufferPointer { buffer in
            let scale = Double(side - 1)
            DispatchQueue.concurrentPerform(iterations: side) { i in
                for j in 0..<side {
                    let tc = SIMD2<Double>(
                        Double(i) / scale, Double(j) / scale)
                    let xy = SpectralConstants.quad2tri(u: tc.x, v: tc.y)
                    let compressed = SpectralConstants.compressXYRadial(
                        SIMD2<Double>(xy.x, xy.y), white: projXy, polygon: locus)
                    let ctc = SpectralConstants.tri2quad(
                        x: compressed.x, y: compressed.y)
                    // bilinear-clamped sample of the RAW table at the
                    // compressed address (the upstream remap form).
                    let gx = min(max(ctc.u * scale, 0), Double(side - 1))
                    let gy = min(max(ctc.v * scale, 0), Double(side - 1))
                    let x0 = min(Int(gx), side - 2)
                    let y0 = min(Int(gy), side - 2)
                    let fx = gx - Double(x0)
                    let fy = gy - Double(y0)
                    let c00 = tcRaw[x0 * side + y0]
                    let c10 = tcRaw[(x0 + 1) * side + y0]
                    let c01 = tcRaw[x0 * side + y0 + 1]
                    let c11 = tcRaw[(x0 + 1) * side + y0 + 1]
                    buffer[i * side + j] =
                        c00 * (1 - fx) * (1 - fy) + c10 * fx * (1 - fy)
                        + c01 * (1 - fx) * fy + c11 * fx * fy
                }
            }
        }
        let tcLut = tcLutD.map { SIMD3<Float>(
            Float($0.x), Float($0.y), Float($0.z)) }

        // ---- the film curve faces ----
        let le0D = Double(film.logExposure.first ?? -3.0)
        let leLast = Double(film.logExposure.last ?? 4.0)
        let leStepD = film.logExposure.count > 1
            ? (leLast - le0D) / Double(film.logExposure.count - 1) : 1.0
        let invLeStep = Float(1.0 / leStepD)  // host double → float (X5 nail ②)
        var curvesNorm = [Float](repeating: 0, count: film.logExposure.count * 3)
        var filmDmaxD = SIMD3<Double>.zero
        var filmDminD = SIMD3<Double>.zero
        var filmCurveMaxD = SIMD3<Double>.zero  // the RAW max (the enl domain)
        for c in 0..<3 {
            var mn = Double.infinity, mx = -Double.infinity
            for i in 0..<film.logExposure.count {
                let v = Double(film.densityCurves[i][c])
                mn = min(mn, v)
                mx = max(mx, v)
            }
            for i in 0..<film.logExposure.count {
                curvesNorm[i * 3 + c] = Float(Double(film.densityCurves[i][c]) - mn)
            }
            filmDmaxD[c] = mx - mn
            filmDminD[c] = mn
            filmCurveMaxD[c] = mx
        }
        // The print (paper) develop curves (the evaluated form of the
        // model — our consumer face carries the measured curves).
        var printCurves = [Float](
            repeating: 0, count: paper.logExposure.count * 3)
        for i in 0..<paper.logExposure.count {
            for c in 0..<3 {
                printCurves[i * 3 + c] = paper.densityCurves[i][c]
            }
        }
        let paperCurveMinD = (0..<3).map { c -> Double in
            paper.densityCurves.reduce(Double.infinity) {
                min($0, Double($1[c]))
            }
        }
        let paperCurveMaxD = (0..<3).map { c -> Double in
            paper.densityCurves.reduce(-Double.infinity) {
                max($0, Double($1[c]))
            }
        }

        // ---- the print leg ----
        // The dichroic-filtered enlarger light for a CC triple (0-100).
        func illumPrintFor(cc m: Double, _ y: Double) -> [Double] {
            // C stays neutral-fixed at 0 (the pack convention).
            let cc = SIMD3<Double>(0, m, y)
            let dim = (0..<3).map { c -> Double in
                1.0 - pow(10.0, -cc[c] / 100.0)
            }
            return (0..<axis.count).map { l -> Double in
                var total = 1.0
                for c in 0..<3 {
                    let f = SpectralConstantsData.dichroicTransmissions[l][c]
                    total *= 1.0 - (1.0 - f) * dim[c]
                }
                return enlargerSPD[l] * total
            }
        }
        let paperStock = paper.info.stock ?? "?"
        let paperLogSens = try requireSpectral(
            paper.logSensitivity, "log_sensitivity", paperStock)
        let printSens: [[Double]] = paperLogSens.map { row in
            row.map { value in
                let v = pow(10.0, Double(value))
                return v.isFinite ? v : 0.0
            }
        }
        // The paper's projected spectral densities (the null-aware face).
        let paperBase = try paper.baseDensityProjected()
            ?? { throw SpectralBuildError.projectionUnavailable("\(paperStock): base_density") }()
        let paperChan = try paper.channelDensityProjected()
            ?? { throw SpectralBuildError.projectionUnavailable("\(paperStock): channel_density") }()
        var scanChanDens = [[Double]](
            repeating: [Double](repeating: 0, count: 3), count: axis.count)
        for l in 0..<axis.count {
            for c in 0..<3 {
                scanChanDens[l][c] = paperChan[c][l]
            }
        }

        // ---- the mid-gray balance (geometric-mean normalization) ----
        // The reference gray walks the chain head in sRGB (the upstream
        // note: independent of the io space).
        let srgbWhiteD = SpectralConstants.srgb.whiteXy
        let catMid = SpectralConstants.catMatrix(
            coneMatrix: SpectralConstants.cat16, srcXy: srgbWhiteD,
            dstXy: projXy)
        let mSRGBD = catMid.multiply(SpectralConstants.srgb.rgbToXYZ)

        func exposeHead(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
            // m_in·rgb → xy → tri2quad → Mitchell gather → ×b (the
            // expose face; ev_scale ≡ 1 per D-M8-8).
            let xyz = mInD.multiplyVector(rgb)
            let b = xyz.x + xyz.y + xyz.z
            let xy = SIMD2<Double>(
                xyz.x / max(b, 1e-10), xyz.y / max(b, 1e-10))
            let tc = SpectralConstants.tri2quad(x: xy.x, y: xy.y)
            let gathered = SpectralFilmRuntime.tcGather(
                lut: tcLutD, side: side, u: tc.u * Double(side - 1),
                v: tc.v * Double(side - 1))
            let bb = b.isFinite ? b : 0.0
            return gathered * bb
        }

        func chainHeadCMY(gray: Double) -> SIMD3<Double> {
            let raw = exposeHead(SIMD3<Double>(gray, gray, gray))
            var cmy = SIMD3<Double>.zero
            for c in 0..<3 {
                let lograw = log10(max(raw[c], 0) + 1e-10)
                // the UNNORMALIZED stock curves (the upstream note)
                cmy[c] = SpectralFilmRuntime.interpCurve(
                    x: lograw, le0: le0D, leStep: leStepD,
                    curves: film.densityCurves, channel: c)
            }
            return cmy
        }

        func densitySpectrum(_ cmy: SIMD3<Double>) -> [Double] {
            (0..<axis.count).map { l -> Double in
                var ds = filmBase[l]
                for c in 0..<3 { ds += filmChanDens[l][c] * cmy[c] }
                return ds
            }
        }

        func printRaw(
            _ ds: [Double], _ illum: [Double]
        ) -> SIMD3<Double> {
            var raw = SIMD3<Double>.zero
            for l in 0..<axis.count {
                var light = illum[l] * pow(10.0, -ds[l])
                if !(light.isFinite) { light = 0.0 }
                raw.x += light * printSens[l][0]
                raw.y += light * printSens[l][1]
                raw.z += light * printSens[l][2]
            }
            return raw
        }

        func exposureFactor(
            _ ds: [Double], _ illum: [Double]
        ) -> Double {
            let raw = printRaw(ds, illum)
            let logSum = log(max(max(raw.x, 0), 1e-10))
                + log(max(max(raw.y, 0), 1e-10))
                + log(max(max(raw.z, 0), 1e-10))
            return 1.0 / exp(logSum / 3.0)
        }

        // ---- the mid-gray density spectrum (CC-independent: it lives
        //      upstream of the enlarger head) ----
        let midgrayCmy = chainHeadCMY(gray: SpectralConstants.midGrayAnchor)
        let midgrayDS = densitySpectrum(midgrayCmy)

        // ---- the neutral CC solve (the spectral-domain neutral balance)
        //
        // The upstream reference pins the print CC from the MEASURED
        // neutral_print_filters table — measured through the REAL dichroic
        // head, the real enlarger and the real light. Our dichroic curves
        // and SPDs are self-approximations (X6), so that table's premises
        // do not carry over: at the measured CC our simulated mid-gray
        // print raw misses channel-neutrality by ~4e-1 (measured, T4).
        // The build therefore solves its OWN pair CC: a 2D Newton ladder
        // over (mCC, yCC) driving the mid-gray log-channel ratios to zero
        // (C stays neutral-fixed at 0). Deterministic fixed ladder; the
        // solved CC is what M8-2's solve face consumes as its seed.
        var solvedCC: SIMD3<Double>
        if let pinned = parameters.printCC {
            solvedCC = pinned
        } else {
            func logRatios(_ illum: [Double]) -> SIMD2<Double> {
                let raw = printRaw(midgrayDS, illum)
                return SIMD2<Double>(
                    log(raw.y / max(raw.x, 1e-300)),
                    log(raw.z / max(raw.x, 1e-300)))
            }
            var m = 50.0, y = 50.0
            let eps = 1e-4
            for _ in 0..<32 {
                let r = logRatios(illumPrintFor(cc: m, y))
                if abs(r.x) + abs(r.y) < 1e-12 { break }
                let rm = logRatios(illumPrintFor(cc: m + eps, y))
                let ry = logRatios(illumPrintFor(cc: m, y + eps))
                let dMdx = (rm.x - r.x) / eps
                let dYdx = (ry.x - r.x) / eps
                let dMdy = (rm.y - r.y) / eps
                let dYdy = (ry.y - r.y) / eps
                let det = dMdx * dYdy - dYdx * dMdy
                guard det.isFinite, abs(det) > 1e-300 else { break }
                let dm = (-r.x * dYdy + r.y * dYdx) / det
                let dy = (-r.y * dMdx + r.x * dMdy) / det
                m = min(max(m + dm, 0.0), 250.0)
                y = min(max(y + dy, 0.0), 250.0)
                if max(abs(dm), abs(dy)) < 1e-10 { break }
            }
            solvedCC = SIMD3<Double>(0, m, y)
        }
        let illumPrintD = illumPrintFor(cc: solvedCC.y, solvedCC.z)

        var midgrayFactorD = 1.0
        let fMid = exposureFactor(midgrayDS, illumPrintD)
        var fComp = 1.0
        if parameters.printExposureCompensation {
            let cmyComp = chainHeadCMY(
                gray: SpectralConstants.midGrayAnchor * 1.0)  // ev_scale ≡ 1
            fComp = exposureFactor(densitySpectrum(cmyComp), illumPrintD)
        }
        switch (parameters.normalizePrintExposure,
                parameters.printExposureCompensation) {
        case (true, false): midgrayFactorD = fMid
        case (true, true): midgrayFactorD = fComp
        case (false, true): midgrayFactorD = fComp / fMid
        case (false, false): midgrayFactorD = 1.0
        }
        let midgrayPrintRawD = printRaw(midgrayDS, illumPrintD)
            * midgrayFactorD

        // ---- the enlarger + scan table domains ----
        let enlLoD = SIMD3<Double>(
            -parameters.grainDensityMin.x, -parameters.grainDensityMin.y,
            -parameters.grainDensityMin.z)
        let enlHiD = filmCurveMaxD
        let enlInvRangeD = SIMD3<Double>(
            1.0 / (enlHiD.x - enlLoD.x), 1.0 / (enlHiD.y - enlLoD.y),
            1.0 / (enlHiD.z - enlLoD.z))
        let scanLoD = SIMD3<Double>(
            paperCurveMinD[0], paperCurveMinD[1], paperCurveMinD[2])
        let scanHiD = SIMD3<Double>(
            paperCurveMaxD[0], paperCurveMaxD[1], paperCurveMaxD[2])
        let scanInvRangeD = SIMD3<Double>(
            1.0 / (scanHiD.x - scanLoD.x), 1.0 / (scanHiD.y - scanLoD.y),
            1.0 / (scanHiD.z - scanLoD.z))

        // ---- the viewing (scan) leg constants ----
        var xyzNormD = 0.0
        var viewXYZ = SIMD3<Double>.zero
        for l in 0..<axis.count {
            xyzNormD += viewSPD[l] * cmfs[l][1]
        }
        for c in 0..<3 {
            var sum = 0.0
            for l in 0..<axis.count { sum += viewSPD[l] * cmfs[l][c] }
            viewXYZ[c] = sum / xyzNormD
        }
        let viewXyD = SIMD2<Double>(
            viewXYZ.x / (viewXYZ.x + viewXYZ.y + viewXYZ.z),
            viewXYZ.y / (viewXYZ.x + viewXYZ.y + viewXYZ.z))
        let catOut = SpectralConstants.catMatrix(
            coneMatrix: SpectralConstants.cat02, srcXy: viewXyD,
            dstXy: parameters.outputSpace.whiteXy)
        let mOutD = parameters.outputSpace.xyzToRGB.multiply(catOut)

        // ---- the 3D tables (Float64 exact integrals → PCHIP → float) ----
        let steps = parameters.lutSteps
        let log10PrintExposureD = log10(max(parameters.printExposure, 1e-10))
        let preflashRawD = SIMD3<Double>.zero

        func printLeg(_ cmy: SIMD3<Double>) -> SIMD3<Double> {
            var raw = SIMD3<Double>.zero
            for l in 0..<axis.count {
                var ds = filmBase[l]
                for c in 0..<3 { ds += filmChanDens[l][c] * cmy[c] }
                var light = illumPrintD[l] * pow(10.0, -ds)
                if !(light.isFinite) { light = 0.0 }
                raw.x += light * printSens[l][0]
                raw.y += light * printSens[l][1]
                raw.z += light * printSens[l][2]
            }
            // the log face (preflight placeholder rides as zero)
            var out = SIMD3<Double>.zero
            for c in 0..<3 {
                let r = raw[c] * midgrayFactorD + preflashRawD[c]
                out[c] = log10(max(r, 0.0) + 1e-10)
            }
            return out
        }

        func scanLeg(_ cmy: SIMD3<Double>) -> SIMD3<Double> {
            var xyz = SIMD3<Double>.zero
            for l in 0..<axis.count {
                var ds = paperBase[l]
                for c in 0..<3 { ds += scanChanDens[l][c] * cmy[c] }
                var light = viewSPD[l] * pow(10.0, -ds)
                if !(light.isFinite) { light = 0.0 }
                xyz.x += light * cmfs[l][0]
                xyz.y += light * cmfs[l][1]
                xyz.z += light * cmfs[l][2]
            }
            var out = SIMD3<Double>.zero
            for c in 0..<3 {
                out[c] = log10(max(xyz[c] / xyzNormD, 0.0) + 1e-10)
            }
            return out
        }

        let printSet = try buildLut3d(
            steps: steps, lo: enlLoD, hi: enlHiD, fn: printLeg)
        let scanSet = try buildLut3d(
            steps: steps, lo: scanLoD, hi: scanHiD, fn: scanLeg)

        // ---- assemble ----
        return SpectralFilmTables(
            tcSide: side,
            tcLut: tcLut,
            projXy: SIMD2<Float>(Float(projXyD.x), Float(projXyD.y)),
            mIn: mInD.map { $0.map { Float($0) } },
            mOut: mOutD.map { $0.map { Float($0) } },
            cat16: SpectralConstants.cat16.map { $0.map { Float($0) } },
            cat02: SpectralConstants.cat02.map { $0.map { Float($0) } },
            oklabM1: SpectralConstants.oklabM1.map { $0.map { Float($0) } },
            oklabM2: SpectralConstants.oklabM2.map { $0.map { Float($0) } },
            print: printSet,
            scan: scanSet,
            curvesNorm: curvesNorm,
            printCurves: printCurves,
            le0: Float(le0D),
            leStep: Float(leStepD),
            invLeStep: invLeStep,
            filmDmax: SIMD3<Float>(filmDmaxD),
            filmDmin: SIMD3<Float>(filmDminD),
            enlLo: SIMD3<Float>(enlLoD),
            enlHi: SIMD3<Float>(enlHiD),
            enlInvRange: SIMD3<Float>(enlInvRangeD),
            scanLo: SIMD3<Float>(scanLoD),
            scanHi: SIMD3<Float>(scanHiD),
            scanInvRange: SIMD3<Float>(scanInvRangeD),
            midgrayFactor: Float(midgrayFactorD),
            log10PrintExposure: Float(log10PrintExposureD),
            evScale: 1.0,
            illumPrint: illumPrintD.map { Float($0) },
            illumView: viewSPD.map { Float($0) },
            xyzNorm: Float(xyzNormD),
            midgrayPrintRaw: SIMD3<Float>(midgrayPrintRawD),
            solvedPrintCC: SIMD3<Float>(solvedCC),
            preflashRaw: SIMD3<Float>(preflashRawD),
            blackWhiteActive: false)
    }

    // MARK: - The 3D lattice build + monotone PCHIP preparation

    /// fill the steps³ lattice with fn over [lo, hi]³ (slices run on the
    /// cooperative pool, deterministic merge) and prepare the PCHIP faces.
    static func buildLut3d(
        steps: Int, lo: SIMD3<Double>, hi: SIMD3<Double>,
        fn: (SIMD3<Double>) -> SIMD3<Double>
    ) throws -> SpectralFilmPchipSet {
        let n3 = steps * steps * steps * 3
        let m3 = (steps - 1) * (steps - 1) * (steps - 1) * 3
        var lut = [Float](repeating: 0, count: n3)
        lut.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: steps) { i in
                for j in 0..<steps {
                    for k in 0..<steps {
                        let cmy = SIMD3<Double>(
                            lo.x + (hi.x - lo.x) * Double(i) / Double(steps - 1),
                            lo.y + (hi.y - lo.y) * Double(j) / Double(steps - 1),
                            lo.z + (hi.z - lo.z) * Double(k) / Double(steps - 1))
                        let value = fn(cmy)
                        let base = ((i * steps + j) * steps + k) * 3
                        buffer[base + 0] = Float(value.x)
                        buffer[base + 1] = Float(value.y)
                        buffer[base + 2] = Float(value.z)
                    }
                }
            }
        }
        // The PCHIP preparation in Float64 over the float-stored lattice —
        // the same value face the runtime reads.
        var sx = [Float](repeating: 0, count: n3)
        var sy = [Float](repeating: 0, count: n3)
        var sz = [Float](repeating: 0, count: n3)
        var cmin = [Float](repeating: 0, count: m3)
        var cmax = [Float](repeating: 0, count: m3)
        let lutD = lut.map { Double($0) }
        var line = [Double](repeating: 0, count: steps)
        var slopes = [Double](repeating: 0, count: steps)
        func at(_ arr: [Double], _ i: Int, _ j: Int, _ k: Int, _ c: Int) -> Double {
            arr[((i * steps + j) * steps + k) * 3 + c]
        }
        func setSlot(
            _ arr: inout [Float], _ i: Int, _ j: Int, _ k: Int, _ c: Int,
            _ v: Double
        ) {
            arr[((i * steps + j) * steps + k) * 3 + c] = Float(v)
        }
        for j in 0..<steps {
            for k in 0..<steps {
                for c in 0..<3 {
                    for i in 0..<steps { line[i] = at(lutD, i, j, k, c) }
                    fillMonotoneSlopes1d(line: line, slopes: &slopes)
                    for i in 0..<steps { setSlot(&sx, i, j, k, c, slopes[i]) }
                }
            }
        }
        for i in 0..<steps {
            for k in 0..<steps {
                for c in 0..<3 {
                    for j in 0..<steps { line[j] = at(lutD, i, j, k, c) }
                    fillMonotoneSlopes1d(line: line, slopes: &slopes)
                    for j in 0..<steps { setSlot(&sy, i, j, k, c, slopes[j]) }
                }
            }
        }
        for i in 0..<steps {
            for j in 0..<steps {
                for c in 0..<3 {
                    for k in 0..<steps { line[k] = at(lutD, i, j, k, c) }
                    fillMonotoneSlopes1d(line: line, slopes: &slopes)
                    for k in 0..<steps { setSlot(&sz, i, j, k, c, slopes[k]) }
                }
            }
        }
        let m = steps - 1
        for i in 0..<m {
            for j in 0..<m {
                for k in 0..<m {
                    for c in 0..<3 {
                        var mn = at(lutD, i, j, k, c)
                        var mx = mn
                        for di in 0..<2 {
                            for dj in 0..<2 {
                                for dk in 0..<2 {
                                    let s = at(lutD, i + di, j + dj, k + dk, c)
                                    mn = min(mn, s)
                                    mx = max(mx, s)
                                }
                            }
                        }
                        let idx = ((i * m + j) * m + k) * 3 + c
                        cmin[idx] = Float(mn)
                        cmax[idx] = Float(mx)
                    }
                }
            }
        }
        return SpectralFilmPchipSet(
            lut: lut, sx: sx, sy: sy, sz: sz, cmin: cmin, cmax: cmax)
    }

    /// The monotone 1D slopes (the Fritsch-Carlson/Brodlie family — the
    /// published algorithm, our own form): interior harmonic-mean slopes
    /// zeroed at sign changes, endpoint slopes the 3-delta form with the
    /// monotonicity clamps.
    static func fillMonotoneSlopes1d(line: [Double], slopes: inout [Double]) {
        let size = line.count
        if size == 1 {
            slopes[0] = 0.0
            return
        }
        var deltas = [Double](repeating: 0, count: size - 1)
        for i in 0..<(size - 1) { deltas[i] = line[i + 1] - line[i] }
        if size == 2 {
            slopes[0] = deltas[0]
            slopes[1] = deltas[0]
            return
        }
        var left = 0.5 * (3.0 * deltas[0] - deltas[1])
        if left * deltas[0] <= 0.0 {
            left = 0.0
        } else if deltas[0] * deltas[1] < 0.0,
            abs(left) > abs(3.0 * deltas[0]) {
            left = 3.0 * deltas[0]
        }
        slopes[0] = left
        for i in 1..<(size - 1) {
            let dp = deltas[i - 1]
            let dn = deltas[i]
            slopes[i] = (dp == 0.0 || dn == 0.0 || dp * dn <= 0.0)
                ? 0.0 : 2.0 * dp * dn / (dp + dn)
        }
        var right = 0.5 * (3.0 * deltas[size - 2] - deltas[size - 3])
        if right * deltas[size - 2] <= 0.0 {
            right = 0.0
        } else if deltas[size - 2] * deltas[size - 3] < 0.0,
            abs(right) > abs(3.0 * deltas[size - 2]) {
            right = 3.0 * deltas[size - 2]
        }
        slopes[size - 1] = right
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SpectralFilmRuntime — the Float64 per-pixel reference faces (the golden
// twin; M8-1b's kernels are checked against these and the tables the
// engine supplies). Pure functions over the tables; no Metal, no pipeline
// imports (the build-time single source).
// ─────────────────────────────────────────────────────────────────────────────

public enum SpectralFilmRuntime {

    // MARK: - The tc gather (Mitchell B=C=1/3, reflected bounds)

    /// The reflected/clamped index (NaN lands on the low branch — the
    /// upstream NaN hardening).
    static func safeIndex(_ idx: Int, _ L: Int) -> Int {
        if idx < 0 { return -idx }
        if idx >= L { return 2 * (L - 1) - idx }
        return idx
    }

    /// The Mitchell-Netravali weights (B = C = 1/3).
    static func mitchellWeight(_ t: Double) -> Double {
        let B = 1.0 / 3.0, C = 1.0 / 3.0
        let x = abs(t)
        if x < 1.0 {
            return (1.0 / 6.0)
                * ((12.0 - 9.0 * B - 6.0 * C) * x * x * x
                    + (-18.0 + 12.0 * B + 6.0 * C) * x * x
                    + (6.0 - 2.0 * B))
        }
        if x < 2.0 {
            return (1.0 / 6.0)
                * ((-B - 6.0 * C) * x * x * x + (6.0 * B + 30.0 * C) * x * x
                    + (-12.0 * B - 48.0 * C) * x + (8.0 * B + 24.0 * C))
        }
        return 0.0
    }

    /// The base index + fraction with the NaN-to-low ordering.
    static func cubicBaseFraction(
        _ coord: Double, _ L: Int
    ) -> (base: Int, frac: Double) {
        if !(coord > 0.0) { return (0, 0.0) }
        if coord >= Double(L - 1) { return (L - 2, 1.0) }
        let base = Int(coord.rounded(.down))
        return (base, coord - Double(base))
    }

    /// The 2D Mitchell gather over the tc table (index units).
    public static func tcGather(
        lut: [SIMD3<Double>], side: Int, u: Double, v: Double
    ) -> SIMD3<Double> {
        let bx = cubicBaseFraction(u, side)
        let by = cubicBaseFraction(v, side)
        var wx = [Double](repeating: 0, count: 4)
        var wy = [Double](repeating: 0, count: 4)
        for i in 0..<4 {
            wx[i] = mitchellWeight(bx.frac + 1.0 - Double(i))
            wy[i] = mitchellWeight(by.frac + 1.0 - Double(i))
        }
        var acc = SIMD3<Double>.zero
        var wsum = 0.0
        for i in 0..<4 {
            let xi = safeIndex(bx.base - 1 + i, side)
            for j in 0..<4 {
                let yj = safeIndex(by.base - 1 + j, side)
                let w = wx[i] * wy[j]
                wsum += w
                acc += w * lut[xi * side + yj]
            }
        }
        if wsum != 0.0 { acc /= wsum }
        return acc
    }

    /// The expose face: m_in·rgb → xy → tri2quad → gather → ×b (the
    /// luminance scale; ev_scale ≡ 1, D-M8-8).
    public static func expose(
        rgb: SIMD3<Double>, mIn: [[Double]], tables: SpectralFilmTables
    ) -> SIMD3<Double> {
        let xyz = mIn.multiplyVector(rgb)
        let b = xyz.x + xyz.y + xyz.z
        let xy = SIMD2<Double>(
            xyz.x / max(b, 1e-10), xyz.y / max(b, 1e-10))
        let tc = SpectralConstants.tri2quad(x: xy.x, y: xy.y)
        let scale = Double(tables.tcSide - 1)
        let gathered = tcGather(
            lut: tables.tcLut.map { SIMD3<Double>($0) }, side: tables.tcSide,
            u: tc.u * scale, v: tc.v * scale)
        let bb = b.isFinite ? b : 0.0
        return gathered * bb * Double(tables.evScale)
    }

    /// The 1D curve lookup over the uniform log-exposure grid (the gamma
    /// factor defaults to 1 — no per-channel contrast in the reference).
    public static func interpCurve(
        x: Double, le0: Double, leStep: Double,
        curves: [[Float]], channel: Int, gamma: Double = 1.0
    ) -> Double {
        let count = curves.count
        let t = (x * gamma - le0) / leStep
        if t <= 0.0 { return Double(curves[0][channel]) }
        if t >= Double(count - 1) { return Double(curves[count - 1][channel]) }
        let i = Int(t)
        let f = t - Double(i)
        return Double(curves[i][channel])
            + f * (Double(curves[i + 1][channel]) - Double(curves[i][channel]))
    }

    // MARK: - The 3D monotone PCHIP evaluation

    /// The 8-cell hermite value.
    static func hermiteValue(
        _ y0: Double, _ y1: Double, _ m0: Double, _ m1: Double, _ t: Double
    ) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        return (2.0 * t3 - 3.0 * t2 + 1.0) * y0 + (t3 - 2.0 * t2 + t) * m0
            + (-2.0 * t3 + 3.0 * t2) * y1 + (t3 - t2) * m1
    }

    /// The monotone PCHIP 3D evaluation (Float64; coordinates in [0,
    /// steps−1] index units; the per-cell clamp face applied last).
    public static func pchip3dEvaluate(
        _ set: SpectralFilmPchipSet, _ r: Double, _ g: Double, _ b: Double
    ) -> SIMD3<Double> {
        let n = SpectralFilmPchipSet.steps
        let m = n - 1
        let bx = cubicBaseFraction(r, n)
        let by = cubicBaseFraction(g, n)
        let bz = cubicBaseFraction(b, n)
        func at(_ arr: [Float], _ i: Int, _ j: Int, _ k: Int, _ c: Int) -> Double {
            Double(arr[((i * n + j) * n + k) * 3 + c])
        }
        func clampIdx(_ arr: [Float], _ i: Int, _ j: Int, _ k: Int, _ c: Int) -> Double {
            let idx = ((min(max(i, 0), m) * m + min(max(j, 0), m))
                * m + min(max(k, 0), m)) * 3 + c
            return Double(arr[idx])
        }
        var out = SIMD3<Double>.zero
        for c in 0..<3 {
            let i = bx.base, j = by.base, k = bz.base
            let tr = bx.frac, tg = by.frac, tb = bz.frac
            let v000 = hermiteValue(
                at(set.lut, i, j, k, c), at(set.lut, i + 1, j, k, c),
                at(set.sx, i, j, k, c), at(set.sx, i + 1, j, k, c), tr)
            let v010 = hermiteValue(
                at(set.lut, i, j + 1, k, c), at(set.lut, i + 1, j + 1, k, c),
                at(set.sx, i, j + 1, k, c), at(set.sx, i + 1, j + 1, k, c), tr)
            let v001 = hermiteValue(
                at(set.lut, i, j, k + 1, c), at(set.lut, i + 1, j, k + 1, c),
                at(set.sx, i, j, k + 1, c), at(set.sx, i + 1, j, k + 1, c), tr)
            let v011 = hermiteValue(
                at(set.lut, i, j + 1, k + 1, c),
                at(set.lut, i + 1, j + 1, k + 1, c),
                at(set.sx, i, j + 1, k + 1, c),
                at(set.sx, i + 1, j + 1, k + 1, c), tr)
            let sy00 = at(set.sy, i, j, k, c) * (1 - tr)
                + at(set.sy, i + 1, j, k, c) * tr
            let sy10 = at(set.sy, i, j + 1, k, c) * (1 - tr)
                + at(set.sy, i + 1, j + 1, k, c) * tr
            let sy01 = at(set.sy, i, j, k + 1, c) * (1 - tr)
                + at(set.sy, i + 1, j, k + 1, c) * tr
            let sy11 = at(set.sy, i, j + 1, k + 1, c) * (1 - tr)
                + at(set.sy, i + 1, j + 1, k + 1, c) * tr
            let vz0 = hermiteValue(v000, v010, sy00, sy10, tg)
            let vz1 = hermiteValue(v001, v011, sy01, sy11, tg)
            let sz0 = (at(set.sz, i, j, k, c) * (1 - tr)
                + at(set.sz, i + 1, j, k, c) * tr) * (1 - tg)
                + (at(set.sz, i, j + 1, k, c) * (1 - tr)
                    + at(set.sz, i + 1, j + 1, k, c) * tr) * tg
            let sz1 = (at(set.sz, i, j, k + 1, c) * (1 - tr)
                + at(set.sz, i + 1, j, k + 1, c) * tr) * (1 - tg)
                + (at(set.sz, i, j + 1, k + 1, c) * (1 - tr)
                    + at(set.sz, i + 1, j + 1, k + 1, c) * tr) * tg
            var value = hermiteValue(vz0, vz1, sz0, sz1, tb)
            value = min(max(value, clampIdx(set.cmin, i, j, k, c)),
                        clampIdx(set.cmax, i, j, k, c))
            out[c] = value
        }
        return out
    }
}
