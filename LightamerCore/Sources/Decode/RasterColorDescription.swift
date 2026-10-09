import CryptoKit
import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// RasterColorDescription — the source color description of a raster (TIFF)
// input (Plan M4-1-01 T1, KD-1; the naming follows the Alcedo
// `raster_color_description.hpp` SEMANTICS — read-only design reference,
// no code copied). Pure Core value type: parsed once per decode from the
// file header, never persisted (file-is-truth — the description rides
// `DecodedImage`, M4-1-02 wires the pipeline).
//
// RESOLUTION ORDER (TIFF, header-only; the first USABLE rule wins — the
// three usable checks fall through, they do not error):
//   ① embedded ICC (matrix-shaper with chad undone / v4.4 cicp / LUT
//     discrimination — see RasterIccParser);
//   ①′ embedded ICC ∧ TRC == linear ∧ float32 → sceneLinear (matrix branch
//     only — the checker E1 half-edge; the in-repo victim chain is the
//     BandStreamer stack-merge float32 TIFF with a linear-Rec2020 ICC);
//   ② no ICC ∧ float32 → scene-linear Rec.709 default;
//   ③ otherwise → sRGB default (the product default, `defaultReason`
//     records why).
// A usable-check failure demotes the ICC to "not present" (reason recorded)
// and the order continues at ②/③.
//
// PEAK LADDER (display-referred): SDR = 100 / PQ = mDCv → MaxCLL → 1000,
// clamped [100, 10000] / HLG = 1000.
// ─────────────────────────────────────────────────────────────────────────────

/// Where the pixel values live (KD-1).
public enum RasterReferral: String, Sendable {
    /// Display-referred (encode-linearized display values in source
    /// primaries) — the ACES 2.0 inverse branch consumes it.
    case displayReferred
    /// Scene-linear (float planes: no-ICC float32 or linear-ICC float32) —
    /// the matrix branch consumes it, no inverse DRT.
    case sceneLinear
}

/// The source transfer curve (the linearize step's input specification).
public enum RasterTransfer: Sendable, Equatable {
    case linear
    /// The IEC 61966-2-1 piecewise (the analytic sRGB form).
    case srgbPiecewise
    /// A pure power (the exponent).
    case gamma(Double)
    /// An ICC parametric curve kept verbatim (type 0..4 + its parameters).
    case iccParametric(type: UInt8, params: [Double])
    /// A sampled curve resampled to 4096 entries over code 0...1.
    case iccSampled([Float])
    case st2084
    case hlg
    /// BT.1886 terminal form (Lb 0 → the pure 2.4 power); present for the
    /// kernel-mirror completeness, no ICC resolution arm produces it.
    case bt1886
}

/// Where the description came from (the UI readout + the input-leg branch
/// selector; the plan's TIFF-narrowed set — the PNG chunk / EXR / EXIF
/// family needs no cases).
public enum RasterColorOrigin: String, Sendable {
    case iccMatrixShaper
    /// The LUT-profile pixels were converted on the CI leg (the ONLY CI-leg
    /// TIFF form): the description describes the CONVERTED plane.
    case iccLutConverted
    case iccCicp
    /// No ICC, float32 — the scene-linear Rec.709 default (②).
    case tiffNoIccFloatLinear
    /// The sRGB default (③).
    case defaultSrgb
}

/// The resolved color description (KD-1 field set).
public struct RasterColorDescription: Sendable, Equatable {
    public var referral: RasterReferral
    /// Rx Ry Gx Gy Bx By Wx Wy — native (unadapted) chromaticities.
    public var primariesXY: SIMD8<Float>
    public var transfer: RasterTransfer
    public var peakLuminanceNits: Float
    public var origin: RasterColorOrigin
    /// The ICC 'desc' string (UI readout only).
    public var profileDescription: String?
    /// Why a default landed (walkthrough observation face; nil = the file
    /// described itself).
    public var defaultReason: String?
    /// The embedded ICC profile identity (SHA-256 truncated) — the
    /// description↔file mismatch guard (KD-5, the upstream §4.3 shape).
    /// nil = no embedded profile.
    public var profileHash: UInt64?

    public init(
        referral: RasterReferral,
        primariesXY: SIMD8<Float>,
        transfer: RasterTransfer,
        peakLuminanceNits: Float,
        origin: RasterColorOrigin,
        profileDescription: String? = nil,
        defaultReason: String? = nil,
        profileHash: UInt64? = nil
    ) {
        self.referral = referral
        self.primariesXY = primariesXY
        self.transfer = transfer
        self.peakLuminanceNits = peakLuminanceNits
        self.origin = origin
        self.profileDescription = profileDescription
        self.defaultReason = defaultReason
        self.profileHash = profileHash
    }

    // MARK: Fingerprint (L013 field-explicit FNV — never JSON, never Hasher)

    /// The explicit-field FNV-1a fold — the develop-output cache key's
    /// description atom (T8). Two descriptions with equal explicit fields
    /// produce equal fingerprints.
    public func stableFingerprint() -> UInt64 {
        func fold(_ seed: UInt64, _ bytes: UnsafeRawBufferPointer) -> UInt64 {
            StableHash.combine(seed, bytes)
        }
        func foldString(_ seed: UInt64, _ s: String) -> UInt64 {
            var out = seed
            var bytes = Array(s.utf8)
            bytes.withUnsafeBufferPointer { out = fold(out, UnsafeRawBufferPointer($0)) }
            return out
        }
        var h = foldString(StableHash.fnvOffsetBasis, "rasterdesc.v1")
        h = foldString(h, referral.rawValue)
        h = foldString(h, origin.rawValue)
        func foldFloats(_ values: [Float]) {
            for v in values {
                withUnsafeBytes(of: v.bitPattern) { h = fold(h, $0) }
            }
        }
        foldFloats([primariesXY[0], primariesXY[1], primariesXY[2], primariesXY[3],
                    primariesXY[4], primariesXY[5], primariesXY[6], primariesXY[7]])
        withUnsafeBytes(of: peakLuminanceNits.bitPattern) { h = fold(h, $0) }
        // The transfer discriminant + payloads (field-explicit; a Double's
        // bit pattern is the identity — no string serialization).
        func foldDiscriminant(_ tag: String) {
            h = foldString(h, tag)
        }
        switch transfer {
        case .linear: foldDiscriminant("linear")
        case .srgbPiecewise: foldDiscriminant("srgb_piecewise")
        case .gamma(let g):
            foldDiscriminant("gamma")
            withUnsafeBytes(of: g.bitPattern) { h = fold(h, $0) }
        case .iccParametric(let type, let params):
            foldDiscriminant("icc_parametric")
            withUnsafeBytes(of: UInt64(type)) { h = fold(h, $0) }
            for p in params {
                withUnsafeBytes(of: p.bitPattern) { h = fold(h, $0) }
            }
        case .iccSampled(let table):
            foldDiscriminant("icc_sampled")
            withUnsafeBytes(of: UInt64(table.count)) { h = fold(h, $0) }
            for v in table {
                withUnsafeBytes(of: v.bitPattern) { h = fold(h, $0) }
            }
        case .st2084: foldDiscriminant("st2084")
        case .hlg: foldDiscriminant("hlg")
        case .bt1886: foldDiscriminant("bt1886")
        }
        return h
    }
}

// MARK: - The resolver (the resolution order + usable checks + peak ladder)

public enum RasterColorResolver {

    // MARK: Named color-space constants (xy chromaticities)

    public static let sRGBPrimaries = SIMD8<Float>(
        0.640, 0.330, 0.300, 0.600, 0.150, 0.060, 0.3127, 0.3290)
    public static let displayP3Primaries = SIMD8<Float>(
        0.680, 0.320, 0.265, 0.690, 0.150, 0.060, 0.3127, 0.3290)
    public static let adobeRGBPrimaries = SIMD8<Float>(
        0.6400, 0.3300, 0.2100, 0.7100, 0.1500, 0.0600, 0.3127, 0.3290)
    public static let rec2020Primaries = SIMD8<Float>(
        0.708, 0.292, 0.170, 0.797, 0.131, 0.046, 0.3127, 0.3290)
    public static let proPhotoPrimaries = SIMD8<Float>(
        0.7347, 0.2653, 0.1596, 0.8404, 0.0366, 0.0001, 0.3457, 0.3585)

    /// The SDR reference peak (nits).
    public static let sdrPeakNits: Float = 100.0
    /// The HLG reference peak (nits).
    public static let hlgPeakNits: Float = 1000.0
    /// The PQ peak-ladder clamp.
    public static let peakClamp: (ClosedRange<Float>) = 100.0...10000.0

    // MARK: Resolution entry

    /// Resolve the description for a TIFF (header-only knowledge).
    /// - Parameters:
    ///   - iccData: the embedded ICC bytes (`CGColorSpace.copyICCData()`),
    ///     nil when the file carries none.
    ///   - colorSpaceName: the CGColorSpace registered name
    ///     (`kCGColorSpace…`) when the embedded profile matched a system
    ///     space — the canonicalization fast path.
    ///   - isFloat: true when the pixel storage is float32
    ///     (bitsPerComponent == 32).
    public static func resolve(
        iccData: Data?, colorSpaceName: String?, isFloat: Bool
    ) -> RasterColorDescription {
        // ① named-space fast path (an embedded system profile — canonical
        // by construction; no byte parse needed).
        if let name = colorSpaceName, let named = namedSpaceDescription(name) {
            var d = named
            d.profileHash = hash(iccData)
            applyPriméRule(&d, isFloat: isFloat)
            return d
        }
        // ① embedded ICC byte parse.
        if let iccData, let profile = RasterIccParser.parse(iccData),
           let d = descriptionFromProfile(profile, iccData: iccData) {
            var resolved = d
            applyPriméRule(&resolved, isFloat: isFloat)
            return resolved
        }
        // The ICC was absent, unparseable, or UNUSABLE — fall through.
        let unusableReason = iccData != nil
            ? "embedded ICC failed the usable checks (or did not parse) — demoted to not-present"
            : nil
        if isFloat {
            // ② no-ICC float32 → scene-linear Rec.709.
            return RasterColorDescription(
                referral: .sceneLinear,
                primariesXY: Self.rec2020Primaries,
                transfer: .linear,
                peakLuminanceNits: sdrPeakNits,
                origin: .tiffNoIccFloatLinear,
                profileDescription: nil,
                defaultReason: unusableReason ?? "no ICC, float32 storage → scene-linear Rec.709 default",
                profileHash: nil)
        }
        // ③ the sRGB default.
        return RasterColorDescription(
            referral: .displayReferred,
            primariesXY: Self.sRGBPrimaries,
            transfer: .srgbPiecewise,
            peakLuminanceNits: sdrPeakNits,
            origin: .defaultSrgb,
            profileDescription: nil,
            defaultReason: unusableReason ?? "no usable ICC — sRGB default",
            profileHash: hash(iccData))
    }

    /// The ①′ half-edge (checker E1): an embedded ICC whose transfer is
    /// LINEAR on a float32 plane → scene-linear (matrix branch only; the
    /// primaries/white still come from the ICC). Display-referred linear on
    /// non-float storage stays display-referred (the linearize step is the
    /// identity there).
    private static func applyPriméRule(_ d: inout RasterColorDescription, isFloat: Bool) {
        if isFloat, d.transfer == .linear, d.referral == .displayReferred {
            d.referral = .sceneLinear
            d.defaultReason = "linear-ICC float32 → scene-linear"
        }
    }

    // MARK: Named-space fast path

    /// Map a system color-space name to a canonical description (nil for
    /// names the fast path does not cover — the byte parse takes over).
    static func namedSpaceDescription(_ name: String) -> RasterColorDescription? {
        switch name {
        case "kCGColorSpaceSRGB", "kCGColorSpaceExtendedSRGB":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: sRGBPrimaries,
                transfer: .srgbPiecewise, peakLuminanceNits: sdrPeakNits,
                origin: .iccMatrixShaper, profileDescription: "sRGB")
        case "kCGColorSpaceLinearSRGB", "kCGColorSpaceExtendedLinearSRGB":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: sRGBPrimaries,
                transfer: .linear, peakLuminanceNits: sdrPeakNits,
                origin: .iccMatrixShaper, profileDescription: "Linear sRGB")
        case "kCGColorSpaceDisplayP3", "kCGColorSpaceExtendedDisplayP3":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: displayP3Primaries,
                transfer: .srgbPiecewise, peakLuminanceNits: sdrPeakNits,
                origin: .iccMatrixShaper, profileDescription: "Display P3")
        case "kCGColorSpaceDisplayP3_PQ":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: displayP3Primaries,
                transfer: .st2084, peakLuminanceNits: hlgPeakNits,
                origin: .iccCicp, profileDescription: "Display P3 PQ")
        case "kCGColorSpaceDisplayP3_HLG":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: displayP3Primaries,
                transfer: .hlg, peakLuminanceNits: hlgPeakNits,
                origin: .iccCicp, profileDescription: "Display P3 HLG")
        case "kCGColorSpaceITUR_2100_PQ":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: rec2020Primaries,
                transfer: .st2084, peakLuminanceNits: hlgPeakNits,
                origin: .iccCicp, profileDescription: "ITU-R BT.2100 PQ")
        case "kCGColorSpaceITUR_2100_HLG":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: rec2020Primaries,
                transfer: .hlg, peakLuminanceNits: hlgPeakNits,
                origin: .iccCicp, profileDescription: "ITU-R BT.2100 HLG")
        case "kCGColorSpaceITUR_2020", "kCGColorSpaceLinearITUR_2020":
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: rec2020Primaries,
                transfer: .linear, peakLuminanceNits: sdrPeakNits,
                origin: .iccMatrixShaper, profileDescription: "ITU-R BT.2020")
        case "kCGColorSpaceAdobeRGB1998":
            // The Adobe RGB (1998) profile curve is γ 563/256.
            return RasterColorDescription(
                referral: .displayReferred, primariesXY: adobeRGBPrimaries,
                transfer: .gamma(563.0 / 256.0), peakLuminanceNits: sdrPeakNits,
                origin: .iccMatrixShaper, profileDescription: "Adobe RGB (1998)")
        default:
            return nil
        }
    }

    // MARK: ICC profile → description (the ① arm)

    /// Build the description from a parsed profile; nil = unusable (the
    /// caller falls through to ②/③).
    static func descriptionFromProfile(
        _ profile: RasterIccProfile, iccData: Data
    ) -> RasterColorDescription? {
        let theHash = hash(iccData)

        // ── LUT-based RGB (A2B0 with NO matrix-shaper tags — the dual-tag
        // case is decided by the matrix-shaper win in the parser) ──
        if profile.model == .rgb, !profile.hasMatrixShaper, profile.hasA2B0 {
            // The pixels convert on the CI leg: the description describes
            // the CONVERTED plane (Rec.2020, linear, display-referred —
            // KD-5; the input leg walks raster_input_display with
            // TRC=linear → the linearize identity).
            return RasterColorDescription(
                referral: .displayReferred,
                primariesXY: rec2020Primaries,
                transfer: .linear,
                peakLuminanceNits: sdrPeakNits,
                origin: .iccLutConverted,
                profileDescription: profile.profileDescription,
                defaultReason: nil,
                profileHash: theHash)
        }

        // ── gray: the gray value copies to RGB (sRGB primaries + the
        // profile curve — the Alcedo single-channel form) ──
        if profile.model == .gray {
            let trc = profile.trcR
            guard let samples = RasterTRC.evaluate(trc),
                  isMonotonic(samples)
            else { return nil }
            let transfer = transferFromTRC(trc, samples: samples)
            return RasterColorDescription(
                referral: .displayReferred,
                primariesXY: sRGBPrimaries,
                transfer: transfer,
                peakLuminanceNits: sdrPeakNits,
                origin: .iccMatrixShaper,
                profileDescription: profile.profileDescription,
                defaultReason: nil,
                profileHash: theHash)
        }

        // ── RGB matrix-shaper ──
        guard profile.model == .rgb, profile.hasMatrixShaper,
              let p = profile.primariesXY, let w = profile.whiteXY
        else { return nil }

        // CICP override (v4.4): overrides TRC and primaries.
        var cicpTransfer: RasterTransfer?
        var cicpPrimaries: SIMD8<Float>?
        if let cicp = profile.cicp {
            switch cicp.transfer {
            case 16: cicpTransfer = .st2084
            case 18: cicpTransfer = .hlg
            case 8: cicpTransfer = .linear
            default: cicpTransfer = nil
            }
            switch cicp.primaries {
            case 1: cicpPrimaries = sRGBPrimaries
            case 9: cicpPrimaries = rec2020Primaries
            case 12: cicpPrimaries = displayP3Primaries
            default: cicpPrimaries = nil
            }
        }

        // The three TRCs must agree (the description carries ONE curve;
        // mismatch = unusable — DECISIONS records the narrowing).
        let trcs = [profile.trcR, profile.trcG, profile.trcB]
        guard let first = trcs.first, trcs.allSatisfy({ $0 == first }) else {
            return nil
        }
        let transfer: RasterTransfer
        if let cicpTransfer {
            transfer = cicpTransfer
        } else {
            guard let samples = RasterTRC.evaluate(first), isMonotonic(samples)
            else { return nil }
            transfer = transferFromTRC(first, samples: samples)
        }

        let primaries = cicpPrimaries ?? SIMD8<Float>(
            Float(p.rx), Float(p.ry), Float(p.gx), Float(p.gy),
            Float(p.bx), Float(p.by), Float(w.x), Float(w.y))

        // Usable checks 1+2: the primaries form a non-degenerate triangle
        // and the white lies inside it (barycentric).
        guard triangleUsable(primaries: primaries) else { return nil }

        // The PQ peak ladder (display-referred PQ only).
        let peak: Float
        switch transfer {
        case .st2084:
            peak = pqPeakLadder(profile: profile)
        case .hlg:
            peak = hlgPeakNits
        default:
            peak = sdrPeakNits
        }

        return RasterColorDescription(
            referral: .displayReferred,
            primariesXY: primaries,
            transfer: transfer,
            peakLuminanceNits: peak,
            origin: (profile.cicp != nil && (cicpTransfer != nil || cicpPrimaries != nil))
                ? .iccCicp : .iccMatrixShaper,
            profileDescription: profile.profileDescription,
            defaultReason: nil,
            profileHash: theHash)
    }

    // MARK: TRC → transfer (the canonicalization consumer)

    /// A parsed TRC → the description transfer. `curv` tables run the
    /// canonicalization ladder; parametric curves keep type+parameters (the
    /// Alcedo form); the u8Fixed8 single value IS the exact gamma carrier.
    static func transferFromTRC(_ trc: RasterIccProfile.TRC, samples: [Double]) -> RasterTransfer {
        switch trc {
        case .identity:
            return .linear
        case .gammaValue(let g):
            return .gamma(g)
        case .table:
            return RasterTRC.canonicalize(samples: samples)
        case .parametric(let p):
            return .iccParametric(type: p.type, params: p.params)
        case .absent:
            return .srgbPiecewise
        }
    }

    // MARK: Usable checks

    /// Non-degenerate primaries triangle (shoelace area gate).
    static func primariesTriangleArea(_ p: SIMD8<Float>) -> Double {
        let rx = Double(p[0]), ry = Double(p[1])
        let gx = Double(p[2]), gy = Double(p[3])
        let bx = Double(p[4]), by = Double(p[5])
        return 0.5 * abs(rx * (gy - by) + gx * (by - ry) + bx * (ry - gy))
    }

    /// The three usable checks over one description candidate.
    /// 1. the primaries form a non-degenerate triangle;
    /// 2. the white point lies inside that triangle (barycentric, small
    ///    quantization tolerance);
    /// 3. the transfer curve is monotonic.
    static func triangleUsable(primaries: SIMD8<Float>) -> Bool {
        if primariesTriangleArea(primaries) < 0.005 { return false }
        let rx = Double(primaries[0]), ry = Double(primaries[1])
        let gx = Double(primaries[2]), gy = Double(primaries[3])
        let bx = Double(primaries[4]), by = Double(primaries[5])
        let wx = Double(primaries[6]), wy = Double(primaries[7])
        // Barycentric coordinates of the white w.r.t. the primary triangle
        // (w = lR·R + lG·G + lB·B, lB = 1−lR−lG) — Cramer over the 2×2
        // system taken from the B vertex:
        //   wx−bx = lR(rx−bx) + lG(gx−bx)
        //   wy−by = lR(ry−by) + lG(gy−by)
        let det = (rx - bx) * (gy - by) - (gx - bx) * (ry - by)
        guard abs(det) > 1e-12 else { return false }
        let lR = ((wx - bx) * (gy - by) - (gx - bx) * (wy - by)) / det
        let lG = ((rx - bx) * (wy - by) - (wx - bx) * (ry - by)) / det
        let lB = 1.0 - lR - lG
        let tolerance = 0.01
        return lR >= -tolerance && lR <= 1 + tolerance
            && lG >= -tolerance && lG <= 1 + tolerance
            && lB >= -tolerance && lB <= 1 + tolerance
    }

    /// The sampled curve is non-decreasing (within numeric noise).
    static func isMonotonic(_ samples: [Double]) -> Bool {
        guard !samples.isEmpty else { return false }
        for i in 1..<samples.count where samples[i] < samples[i - 1] - 1e-6 {
            return false
        }
        return true
    }

    // MARK: Peak ladder

    /// PQ: mDCv max luminance → ccll MaxCLL → 1000, clamped [100, 10000].
    static func pqPeakLadder(profile: RasterIccProfile) -> Float {
        let candidate = profile.mdcvMaxLuminanceNits
            ?? profile.maxCLLNits
            ?? 1000.0
        let clamped = min(max(Float(candidate), peakClamp.lowerBound), peakClamp.upperBound)
        return clamped
    }

    // MARK: Profile hash (KD-5 — SHA-256 truncated)

    /// The truncated SHA-256 of the ICC bytes (the description↔file guard).
    public static func hash(_ iccData: Data?) -> UInt64? {
        guard let iccData else { return nil }
        let digest = CryptoKit.SHA256.hash(data: iccData)
        let bytes = Array(digest.prefix(8))
        var value: UInt64 = 0
        for b in bytes { value = (value << 8) | UInt64(b) }
        return value
    }
}
