import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// RasterIccParser — the self-hosted ICC byte parser for the RASTER (file
// domain) color description (Plan M4-1-01 T1, KD-1). Parses the ICC header +
// tag table straight from `CGColorSpaceCopyICCData` bytes:
//
//   • matrix-shaper primaries (rXYZ/gXYZ/bXYZ) with the `chad` tag undone
//     back to the native (unadapted) white; v2 profiles without `chad`
//     rebuild the Bradford adaptation from `wtpt` (Alcedo raster plan §4.2
//     semantics — read-only reference, no code copied);
//   • TRC parameterization (`para` type 0..4 with its parameter sets) and
//     sampling (multi-entry `curv` tables resampled to 4096 entries);
//   • the ICC v4.4 `cicp` tag (overrides TRC/primaries);
//   • LUT-based discrimination (A2B0 present AND no matrix-shaper tags —
//     when both coexist the matrix-shaper WINS, the Alcedo D4 wording
//     "A2B0 with no matrix-shaper tags" verbatim);
//   • `mDCv` / `ccll` HDR metadata tags for the PQ peak ladder;
//   • the `desc` (v2 textDescription / v4 mluc) profile description.
//
// DISPLAY-PROFILE ZERO TOUCH (KD-2 note): the display domain (DisplayProfile)
// keeps its own xyzTag walk — this parser is intentionally separate because
// the display fallback-chain semantics differ (merging would couple the two
// families' fallback paths). DisplayProfile.swift was consulted as the PATTERN
// reference only.
//
// ZERO THIRD-PARTY ICC LIBRARY (dependency-minimization red line): every
// field read here is public ICC specification layout (ICC.1:2022).
//
// TRC DIRECTION CONVENTION: an ICC profile TRC maps DEVICE CODE → LINEAR
// (the profile's own linearization). The linearize step consumes it in that
// direction; the canonicalization compares the sample table (normalized by
// its endpoint) against the candidate analytic shapes in the same direction.
// ─────────────────────────────────────────────────────────────────────────────

/// The parsed ICC profile facts the description resolver needs.
struct RasterIccProfile: Sendable {

    /// The ICC data color space signature ('RGB ' / 'GRAY' / 'CMYK' / …).
    enum DataModel: String, Sendable {
        case rgb = "RGB "
        case gray = "GRAY"
        case cmyk = "CMYK"
        case other
    }

    /// A parametric curve (ICC `para` function types 0..4).
    struct Parametric: Sendable, Equatable {
        /// ICC parametric function type (0..4).
        var type: UInt8
        /// The parameter set g,a,b,c,d,e,f (only the prefix the type uses).
        var params: [Double]
    }

    /// One TRC as stored in the profile (pre-canonicalization).
    enum TRC: Sendable, Equatable {
        /// `curv` count 0 — the identity.
        case identity
        /// `curv` count 1 — the u8Fixed8 single-value gamma face.
        case gammaValue(Double)
        /// A multi-entry `curv` table (u16 samples over code 0...1).
        case table([Double])
        /// A `para` parametric curve.
        case parametric(Parametric)
        /// No TRC tag for this channel.
        case absent
    }

    /// The device data model.
    var model: DataModel
    /// Native (unadapted) primaries as (x, y) chromaticity pairs — R, G, B.
    var primariesXY: (rx: Double, ry: Double, gx: Double, gy: Double, bx: Double, by: Double)?
    /// Native white point (x, y).
    var whiteXY: (x: Double, y: Double)?
    /// The per-channel TRCs (rTRC/gTRC/bTRC or the single grayTRC).
    var trcR: TRC
    var trcG: TRC
    var trcB: TRC
    /// The v4.4 `cicp` tag payload (colourPrimaries, transferCharacteristics,
    /// matrixCoefficients, fullRangeFlag) — present means it OVERRIDES the
    /// profile's TRC and primaries.
    var cicp: (primaries: UInt8, transfer: UInt8, matrix: UInt8, fullRange: UInt8)?
    /// True when an A2B0 LUT tag is present.
    var hasA2B0: Bool
    /// True when all three matrix-shaper tags (rXYZ/gXYZ/bXYZ) are present.
    var hasMatrixShaper: Bool
    /// The `mDCv` mastering-metadata max luminance (nits), when present.
    var mdcvMaxLuminanceNits: Double?
    /// The `ccll` MaxCLL (nits), when present.
    var maxCLLNits: Double?
    /// The `desc` profile description string, when readable.
    var profileDescription: String?
}

/// The ICC byte-layout parser (pure functions over `Data`).
enum RasterIccParser {

    // MARK: - Entry

    /// Parse ICC profile bytes into the fact struct. nil for malformed
    /// headers/tag tables (the resolver treats nil as "no usable ICC").
    static func parse(_ data: Data) -> RasterIccProfile? {
        let b = [UInt8](data)
        guard b.count >= 132 else { return nil }
        // 'acsp' signature at 36 (the profile-file sanity anchor).
        guard String(bytes: b[36..<40], encoding: .ascii) == "acsp" else { return nil }

        let modelSig = String(bytes: b[16..<20], encoding: .ascii) ?? ""
        let model: RasterIccProfile.DataModel
        switch modelSig {
        case "RGB ": model = .rgb
        case "GRAY": model = .gray
        case "CMYK": model = .cmyk
        default: model = .other
        }

        // ── tag table ──
        let tagCount = Int(b.beUInt32(at: 128))
        guard tagCount > 0, tagCount < 1024 else { return nil }
        var tags: [String: (offset: Int, size: Int)] = [:]
        for i in 0..<tagCount {
            let entry = 132 + i * 12
            guard entry + 12 <= b.count else { return nil }
            let sig = String(bytes: b[entry..<entry + 4], encoding: .ascii) ?? ""
            let offset = Int(b.beUInt32(at: entry + 4))
            let size = Int(b.beUInt32(at: entry + 8))
            guard offset + size <= b.count, size > 0 else { continue }
            tags[sig] = (offset, size)
        }

        var profile = RasterIccProfile(
            model: model, primariesXY: nil, whiteXY: nil,
            trcR: .absent, trcG: .absent, trcB: .absent,
            cicp: nil, hasA2B0: tags["A2B0"] != nil, hasMatrixShaper: false,
            mdcvMaxLuminanceNits: nil, maxCLLNits: nil, profileDescription: nil)

        // ── the v4.4 cicp tag (overrides TRC/primaries downstream) ──
        if let cicp = tags["cicp"], cicp.size >= 8 {
            // 'cicp' type: 4-byte sig + 4 reserved + the 4 payload bytes.
            profile.cicp = (
                primaries: b[cicp.offset + 8],
                transfer: b[cicp.offset + 9],
                matrix: b[cicp.offset + 10],
                fullRange: b[cicp.offset + 11])
        }

        // ── HDR metadata tags (the PQ peak ladder sources) ──
        if let mdcv = tags["mdcv"], mdcv.size >= 32 {
            // Apple/CTA-861.3 mastering metadata: 3 primaries × (x,y) u16
            // [×50000] + white (x,y) u16 + maxLum u32 + minLum u32 [×10000].
            let base = mdcv.offset + 8
            let maxLum = Double(b.beUInt32(at: base + 16)) / 10000.0
            if maxLum > 0 { profile.mdcvMaxLuminanceNits = maxLum }
        }
        if let ccll = tags["ccll"], ccll.size >= 12 {
            let base = ccll.offset + 8
            let maxCLL = Double(b.beUInt32(at: base)) / 10000.0
            if maxCLL > 0 { profile.maxCLLNits = maxCLL }
        }

        // ── profile description (v2 textDescription or v4 mluc) ──
        if let desc = tags["desc"] {
            profile.profileDescription = Self.parseDescription(b, offset: desc.offset, size: desc.size)
        }

        // ── matrix-shaper primaries + native white ──
        func xyz(_ sig: String) -> SIMD3<Double>? {
            guard let t = tags[sig], t.size >= 20 else { return nil }
            // XYZType: 'XYZ ' + 4 reserved + 3 × s15Fixed16.
            return SIMD3<Double>(
                Double(b.beInt32(at: t.offset + 8)) / 65536.0,
                Double(b.beInt32(at: t.offset + 12)) / 65536.0,
                Double(b.beInt32(at: t.offset + 16)) / 65536.0)
        }
        if let r = xyz("rXYZ"), let g = xyz("gXYZ"), let bl = xyz("bXYZ") {
            profile.hasMatrixShaper = true
            // The chad adaptation: PCS = chad × native → native = chad⁻¹ × PCS.
            // v2 profiles without chad rebuild the Bradford from wtpt.
            let chad: RasterIccMat3
            if let chadTag = tags["chad"], chadTag.size >= 44 {
                let base = chadTag.offset + 8
                var rows = [[Double]](repeating: [0, 0, 0], count: 3)
                for row in 0..<3 {
                    for col in 0..<3 {
                        rows[row][col] = Double(b.beInt32(at: base + (row * 3 + col) * 4)) / 65536.0
                    }
                }
                chad = RasterIccMat3(rows: rows)
            } else {
                // No chad tag: assume the PCS media white (wtpt) IS the
                // native white chromaticity and build Bradford D50→wtpt.
                if let wtpt = xyz("wtpt"), wtpt.y > 0 {
                    let nativeWhite = SIMD3<Double>(wtpt.x / wtpt.y, 1.0, wtpt.z / wtpt.y)
                    chad = RasterIccMat3.bradfordAdaptation(from: nativeWhite, to: Self.d50PCS)
                } else {
                    chad = RasterIccMat3.identity
                }
            }
            let inv = chad.inverse
            let nativeR = inv * r
            let nativeG = inv * g
            let nativeB = inv * bl
            let nativeW: SIMD3<Double>
            if let wtpt = xyz("wtpt") {
                nativeW = inv * wtpt
            } else {
                nativeW = nativeR + nativeG + nativeB
            }
            func xy(_ v: SIMD3<Double>) -> (Double, Double) {
                let s = v.x + v.y + v.z
                guard s > 0 else { return (0, 0) }
                return (v.x / s, v.y / s)
            }
            let rxy = xy(nativeR), gxy = xy(nativeG), bxy = xy(nativeB), wxy = xy(nativeW)
            profile.primariesXY = (rxy.0, rxy.1, gxy.0, gxy.1, bxy.0, bxy.1)
            profile.whiteXY = (wxy.0, wxy.1)
        }

        // ── TRCs ──
        if model == .gray {
            if let t = tags["kTRC"] { profile.trcR = parseTRC(b, t) }
        } else {
            if let t = tags["rTRC"] { profile.trcR = parseTRC(b, t) }
            if let t = tags["gTRC"] { profile.trcG = parseTRC(b, t) }
            if let t = tags["bTRC"] { profile.trcB = parseTRC(b, t) }
        }

        return profile
    }

    // MARK: - TRC tag decoding

    /// Decode one curve-type tag (`curv` or `para`).
    static func parseTRC(_ b: [UInt8], _ t: (offset: Int, size: Int)) -> RasterIccProfile.TRC {
        let sig = String(bytes: b[t.offset..<t.offset + 4], encoding: .ascii) ?? ""
        if sig == "curv", t.size >= 12 {
            let count = Int(b.beUInt32(at: t.offset + 8))
            if count == 0 { return .identity }
            if count == 1 {
                // u8Fixed8 gamma face (count 1 = one u16 value).
                let raw = UInt16(b[t.offset + 12]) << 8 | UInt16(b[t.offset + 13])
                return .gammaValue(Double(raw) / 256.0)
            }
            guard t.offset + 12 + count * 2 <= b.count else { return .absent }
            var samples = [Double](repeating: 0, count: count)
            for i in 0..<count {
                let raw = UInt16(b[t.offset + 12 + i * 2]) << 8
                    | UInt16(b[t.offset + 13 + i * 2])
                samples[i] = Double(raw) / 65535.0
            }
            return .table(samples)
        }
        if sig == "para", t.size >= 16 {
            // 'para' + 4 reserved + functionType u16 + 2 reserved + params.
            let fnType = UInt16(b[t.offset + 8]) << 8 | UInt16(b[t.offset + 9])
            let paramCount: Int
            switch fnType {
            case 0: paramCount = 1
            case 1: paramCount = 3
            case 2: paramCount = 4
            case 3: paramCount = 5
            case 4: paramCount = 7
            default: return .absent
            }
            guard t.offset + 12 + paramCount * 4 <= b.count else { return .absent }
            var params = [Double](repeating: 0, count: paramCount)
            for i in 0..<paramCount {
                params[i] = Double(b.beInt32(at: t.offset + 12 + i * 4)) / 65536.0
            }
            return .parametric(RasterIccProfile.Parametric(
                type: UInt8(fnType), params: params))
        }
        return .absent
    }

    /// The `desc` tag: v2 textDescriptionType or v4 mlucType.
    static func parseDescription(_ b: [UInt8], offset: Int, size: Int) -> String? {
        guard size >= 12 else { return nil }
        let sig = String(bytes: b[offset..<offset + 4], encoding: .ascii) ?? ""
        if sig == "mluc" {
            // mluc: 4 sig + 4 reserved + recordCount u32 + recordSize u32,
            // then records: language 2 + country 2 + length u32 + offset u32.
            let recordCount = Int(b.beUInt32(at: offset + 8))
            guard recordCount >= 1 else { return nil }
            let base = offset + 16
            let length = Int(b.beUInt32(at: base + 4))
            let strOffset = Int(b.beUInt32(at: base + 8))
            guard length >= 2, offset + strOffset + length <= b.count else { return nil }
            let utf16 = stride(from: offset + strOffset, to: offset + strOffset + length, by: 2)
                .map { UInt16(b[$0]) << 8 | UInt16(b[$0 + 1]) }
            return String(decoding: utf16, as: UTF16.self)
        }
        if sig == "desc" {
            // textDescription: 4 sig + 4 reserved + asciiCount u32 + ascii…
            let asciiCount = Int(b.beUInt32(at: offset + 8))
            guard asciiCount > 0, offset + 12 + asciiCount <= b.count else { return nil }
            let bytes = b[(offset + 12)..<(offset + 12 + asciiCount - 1)]
            return String(decoding: bytes, as: UTF8.self)
        }
        return nil
    }

    /// The D50 PCS illuminant (XYZ), the ICC constant.
    static let d50PCS = SIMD3<Double>(0.96420288, 1.0, 0.82490539)
}

// MARK: - TRC evaluation + canonicalization (the Core host Float64 twins)

/// The host-side Float64 transfer-curve math for the raster input leg — the
/// canonical formulas (public standards) the Metal kernels re-state and the
/// golden tests pin. Core does NOT import LightamerIOP (the module boundary);
/// the IOPP cross-anchor against `LutTransferMath` happens in that bundle's
/// tests only.
enum RasterTRC {

    // MARK: sRGB piecewise (IEC 61966-2-1)

    /// The sRGB EOTF: code → linear.
    static func srgbPiecewiseDecode(_ code: Double) -> Double {
        let c = min(max(code, 0), 1)
        return c <= 0.04045 ? c / 12.92 : Foundation.pow((c + 0.055) / 1.055, 2.4)
    }

    /// The sRGB inverse EOTF: linear → code.
    static func srgbPiecewiseEncode(_ linear: Double) -> Double {
        let v = min(max(linear, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * Foundation.pow(v, 1 / 2.4) - 0.055
    }

    // MARK: ST 2084 (PQ) — normalized shape (1.0 code = 1.0 relative)

    /// The PQ EOTF on the RELATIVE domain (code → linear / 10000 nits) —
    /// the shape the canonicalization compares (scale-invariant).
    static func pqDecodeRelative(_ code: Double) -> Double {
        let c = min(max(code, 0), 1)
        let ePow = Foundation.pow(c, 1 / DrtEotfMath.st2084M2)
        let fraction = (ePow - DrtEotfMath.st2084C1)
            / (DrtEotfMath.st2084C2 - DrtEotfMath.st2084C3 * ePow)
        // The safePow guard returns negative fractions verbatim (the decode
        // side's garbage-degradation face); the SHAPE comparator floors them
        // at 0 (PQ is 0 at code 0).
        return max(0, DrtEotfMath.safePow(fraction, 1 / DrtEotfMath.st2084M1))
    }

    // MARK: HLG — the 1000-nit reference display curve (neutral axis)

    /// The HLG display curve on the reference OOTF (γ = 1.2): the neutral
    /// display value for a signal — (OETF(signal))^1.2, normalized. A
    /// per-channel ICC TRC can only carry the neutral-axis form.
    static func hlgDisplayDecode(_ code: Double) -> Double {
        let scene = DrtEotfMath.hlgOETF(min(max(code, 0), 1))
        return DrtEotfMath.safePow(scene, DrtEotfMath.hlgGamma)
    }

    // MARK: Canonicalization ladder

    /// The sample count the canonicalization evaluates (the full code ramp).
    static let canonicalSampleCount = 64

    /// Canonicalize a sampled TRC (code → linear samples over 0...1) into
    /// the analytic form when the whole table sits inside the gate:
    /// ① ST 2084 / HLG shapes within 2e-4 (the upstream R1 lesson — PQ
    ///   export profiles ship 4096-point tables that MUST canonicalize);
    /// ② the sRGB piecewise within 1e-4 (Alcedo :253-254 same value);
    /// ③ a pure gamma within 1e-4 (log-log power fit);
    /// identity within 1e-4 → `.linear` (checked first — the ①′ premise).
    /// No hit → `.iccSampled` resampled to 4096 entries.
    static func canonicalize(samples: [Double]) -> RasterTransfer {
        let n = samples.count
        guard n >= 2 else { return .iccSampled(resample(samples, to: 4096).map(Float.init)) }
        var codes = [Double](repeating: 0, count: n)
        for i in 0..<n { codes[i] = Double(i) / Double(n - 1) }

        // Normalize by the endpoint (scale-invariance — a PQ table may ride
        // 10000-nit units, 100-nit units, or the relative domain).
        let last = samples[n - 1]
        guard last > 0 else { return .iccSampled(resample(samples, to: 4096).map(Float.init)) }
        let norm = samples.map { $0 / last }

        // identity (linear).
        var maxDev = 0.0
        for i in 0..<n { maxDev = max(maxDev, abs(norm[i] - codes[i])) }
        if maxDev <= 1e-4 { return .linear }

        // ① PQ / HLG shapes at 2e-4.
        maxDev = 0
        for i in 0..<n { maxDev = max(maxDev, abs(norm[i] - pqDecodeRelative(codes[i]))) }
        if maxDev <= 2e-4 { return .st2084 }

        maxDev = 0
        for i in 0..<n { maxDev = max(maxDev, abs(norm[i] - hlgDisplayDecode(codes[i]))) }
        if maxDev <= 2e-4 { return .hlg }

        // ② sRGB piecewise at 1e-4.
        maxDev = 0
        for i in 0..<n { maxDev = max(maxDev, abs(norm[i] - srgbPiecewiseDecode(codes[i]))) }
        if maxDev <= 1e-4 { return .srgbPiecewise }

        // ③ pure gamma at 1e-4 — the estimator is the MEDIAN of the
        // per-point instantaneous gammas ln(v)/ln(code). A log-log least
        // squares is biased by the u16 carrier's heteroscedastic quantization
        // noise (the fitted slope drifts ~0.005 and the residual blows the
        // 1e-4 gate — measured, T1); the median is robust to it (residual
        // ~8e-6 for an exact-gamma u16 table, measured).
        var gammas: [Double] = []
        for i in 1..<n where codes[i] > 0 && norm[i] > 0 && norm[i] < 1 {
            gammas.append(Foundation.log(norm[i]) / Foundation.log(codes[i]))
        }
        if gammas.count >= 8 {
            let sorted = gammas.sorted()
            let mid = sorted.count / 2
            let gamma = max(sorted.count % 2 == 1
                ? sorted[mid]
                : (sorted[mid - 1] + sorted[mid]) / 2, 1e-3)
            maxDev = 0
            for i in 1..<n {
                let model = Foundation.pow(codes[i], gamma)
                maxDev = max(maxDev, abs(norm[i] - model))
            }
            if maxDev <= 1e-4 { return .gamma(gamma) }
        }

        return .iccSampled(resample(samples, to: 4096).map { Float($0) })
    }

    /// Evaluate a parsed TRC into an evenly-spaced sample table (the input
    /// face canonicalization + usable checks consume).
    static func evaluate(_ trc: RasterIccProfile.TRC, points: Int = canonicalSampleCount) -> [Double]? {
        switch trc {
        case .absent:
            return nil
        case .identity:
            return (0..<points).map { Double($0) / Double(points - 1) }
        case .gammaValue(let g):
            return (0..<points).map { Foundation.pow(Double($0) / Double(points - 1), g) }
        case .table(let samples):
            return resample(samples, to: points)
        case .parametric(let p):
            return (0..<points).map { parametricEvaluate(p, code: Double($0) / Double(points - 1)) }
        }
    }

    /// The ICC parametric function formulas (ICC.1:2022 §10.5.3).
    static func parametricEvaluate(_ p: RasterIccProfile.Parametric, code: Double) -> Double {
        let g = p.params.count > 0 ? p.params[0] : 1
        switch p.type {
        case 0:
            return DrtEotfMath.safePow(code, g)
        case 1:
            let a = p.params.count > 1 ? p.params[1] : 0
            let b = p.params.count > 2 ? p.params[2] : 0
            return code >= -b / a ? DrtEotfMath.safePow(code * a + b, g) : 0
        case 2:
            let a = p.params.count > 1 ? p.params[1] : 0
            let b = p.params.count > 2 ? p.params[2] : 0
            let c = p.params.count > 3 ? p.params[3] : 0
            return code >= -b / a ? DrtEotfMath.safePow(code * a + b, g) + c : c
        case 3:
            let a = p.params.count > 1 ? p.params[1] : 0
            let b = p.params.count > 2 ? p.params[2] : 0
            let c = p.params.count > 3 ? p.params[3] : 0
            let d = p.params.count > 4 ? p.params[4] : 0
            return code >= d ? DrtEotfMath.safePow(code * a + b, g) : c * code
        case 4:
            let a = p.params.count > 1 ? p.params[1] : 0
            let b = p.params.count > 2 ? p.params[2] : 0
            let c = p.params.count > 3 ? p.params[3] : 0
            let d = p.params.count > 4 ? p.params[4] : 0
            let e = p.params.count > 5 ? p.params[5] : 0
            let f = p.params.count > 6 ? p.params[6] : 0
            return code >= d ? DrtEotfMath.safePow(code * a + b, g) + e : c * code + f
        default:
            return code
        }
    }

    /// Linear resample to `count` evenly-spaced entries.
    static func resample(_ samples: [Double], to count: Int) -> [Double] {
        guard samples.count >= 2 else {
            return [Double](repeating: samples.first ?? 0, count: count)
        }
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / Double(count - 1) * Double(samples.count - 1)
            let i0 = min(Int(t), samples.count - 2)
            let f = t - Double(i0)
            out[i] = samples[i0] * (1 - f) + samples[i0 + 1] * f
        }
        return out
    }
}

// MARK: - Minimal 3×3 (row-major) — the parser's colorimetry math

/// A minimal 3×3 matrix (row-major) for chad handling. Same role as the
/// export side's private Mat3 (that one is file-private to
/// DrtOutputColorSpace.swift — no cross-file reach without an export-face
// diff, which this plan's red lines forbid).
struct RasterIccMat3: Sendable {
    var rows: [[Double]]

    static var identity: RasterIccMat3 { RasterIccMat3(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]) }

    static func * (lhs: RasterIccMat3, rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            lhs.rows[0][0] * rhs.x + lhs.rows[0][1] * rhs.y + lhs.rows[0][2] * rhs.z,
            lhs.rows[1][0] * rhs.x + lhs.rows[1][1] * rhs.y + lhs.rows[1][2] * rhs.z,
            lhs.rows[2][0] * rhs.x + lhs.rows[2][1] * rhs.y + lhs.rows[2][2] * rhs.z)
    }

    var inverse: RasterIccMat3 {
        let a = rows
        let det = a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
            - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        guard det != 0 else { return .identity }
        let inv = { (v: Double) in v / det }
        return RasterIccMat3(rows: [
            [inv(a[1][1] * a[2][2] - a[1][2] * a[2][1]),
             inv(a[0][2] * a[2][1] - a[0][1] * a[2][2]),
             inv(a[0][1] * a[1][2] - a[0][2] * a[1][0])],
            [inv(a[1][2] * a[2][0] - a[1][0] * a[2][2]),
             inv(a[0][0] * a[2][2] - a[0][2] * a[2][0]),
             inv(a[0][2] * a[1][0] - a[0][0] * a[1][2])],
            [inv(a[1][0] * a[2][1] - a[1][1] * a[2][0]),
             inv(a[0][1] * a[2][0] - a[0][0] * a[2][1]),
             inv(a[0][0] * a[1][1] - a[0][1] * a[1][0])],
        ])
    }

    /// The Bradford adaptation matrix native → target white (cone domain
    /// diagonal scaling between the two Bradford cone responses).
    static func bradfordAdaptation(from native: SIMD3<Double>, to target: SIMD3<Double>) -> RasterIccMat3 {
        let bradford = RasterIccMat3(rows: [
            [0.8951, 0.2664, -0.1614],
            [-0.7502, 1.7135, 0.0367],
            [0.0389, -0.0685, 1.0296],
        ])
        let bradfordInverse = RasterIccMat3(rows: [
            [0.9869929, -0.1470543, 0.1599627],
            [0.4323053, 0.5183603, 0.0492912],
            [-0.0085287, 0.0400428, 0.9684867],
        ])
        let coneSource = bradford * native
        let coneTarget = bradford * target
        var scale = RasterIccMat3.identity
        for i in 0..<3 where coneSource[i] != 0 {
            scale.rows[i][i] = coneTarget[i] / coneSource[i]
        }
        return bradfordInverse * scale * bradford
    }

    static func * (lhs: RasterIccMat3, rhs: RasterIccMat3) -> RasterIccMat3 {
        RasterIccMat3(rows: (0..<3).map { r in
            (0..<3).map { c in
                (0..<3).map { lhs.rows[r][$0] * rhs.rows[$0][c] }.reduce(0, +)
            }
        })
    }
}

// MARK: - Big-endian byte readers

private extension Array where Element == UInt8 {
    func beUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24) | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8) | UInt32(self[offset + 3])
    }
    func beInt32(at offset: Int) -> Int32 {
        Int32(bitPattern: beUInt32(at: offset))
    }
}
