import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// DrtOutputColorSpace — the OQ-7-A export ICC resolver (Plan M2-9-02 T1, KD-1):
// the encoding (space, EOTF) pair IS the output ICC. One function, exhaustive
// over the 6×7 cartesian domain with NO default arms (a new DrtEncodingSpace /
// DrtEotf case breaks the build until its arm is authored — the M2DRT-06
// registration-gate discipline); combos outside `legalEOTFs(for:)` are typed
// rejections (the record layer may PERSIST them — linear / gamma18 — the
// linkage table never offers them, the mapping refuses them).
//
// Legal domain (Alcedo `export_icc_profile_resolver.cpp` ResolveConfigProfileFileName
// row-for-row — the behavior benchmark; GPL read-only):
//   rec709  × {bt1886, gamma22}      p3d65 × {gamma22, st2084}
//   p3d60   × {gamma26}              p3dci × {gamma26}
//   xyz     × {gamma26}              rec2020 × {st2084, hlg}
//
// Construction (KD-1, host-verified 2026-10-03 — probes in M2-9-02-DECISIONS):
//   • HDR (st2084 / hlg): SYSTEM profiles by name — rec2020 →
//     kCGColorSpaceITUR_2100_PQ/HLG, p3d65+st2084 → kCGColorSpaceDisplayP3_PQ
//     (the m2-6-3 D2 viewport precedent's same choice).
//   • SDR powers: CALIBRATED ICC PROFILES BUILT FROM BYTES. The plan's
//     `CGColorSpaceCreateCalibratedRGB` face is DEAD on macOS 27: the generated
//     profile is nonconformant (wtpt carries the raw chromaticity instead of
//     the D50 PCS tristimulus, bXYZ degenerates to (32768, 1, -32768), all
//     three TRC tags alias one offset) and every ColorSync/CI conversion
//     through it returns garbage (probed; DECISIONS §1). The replacement keeps
//     the plan's SEMANTICS — primaries per space + power gamma per EOTF + D50
//     PCS — as a hand-built ICC v4 matrix-shaper profile (Bradford-adapted)
//     fed to `CGColorSpace(iccProfileData:)`. Deterministic bytes; canonical
//     Rec709 anchors match the public sRGB ICC constants.
//   • xyz + gamma26: the XYZ basis as the RGB matrix — R=X, G=Y, B=Z is the
//     IDENTITY matrix over tristimulus space with white E (1,1,1); not
//     singular as a matrix profile (the xy-CHROMATICITY form is what
//     degenerates). Bradford-adapted E→D50 like every other arm.
//
// peak 不入 ICC (v1, KD-1): peakLuminance rides the EotfBox record (render)
// and the enqueue gate (M2-9-03); the ICC annotation carries space+TRC only —
// the UltraHDR carrier (ALCE-02, V2) owns peak annotation later.
//
// Instances are CACHED one-per-(space, eotf), forever (the 13-2
// LinearVariantCache precedent, D-13-2-7: per-render instance churn
// destabilized the CI leg; the exit leg's identity pass keys on the instance).
// ─────────────────────────────────────────────────────────────────────────────

public enum DrtOutputColorSpace {

    /// The OQ-7-A resolver: the DRT encoding pair → the output ICC.
    /// Typed `AppError.invalidParameter` for every combination outside the
    /// legal linkage table (and for the impossible case of the system
    /// refusing its own named profiles — defensive, never observed).
    public static func drtOutputColorSpace(
        space: DrtEncodingSpace, eotf: DrtEotf
    ) throws -> CGColorSpace {
        if let cached = cache(space: space, eotf: eotf) { return cached }
        let built: CGColorSpace
        switch space {
        case .rec709:
            switch eotf {
            case .bt1886:
                // BT.1886 = Lb 0 → β 0 → the pure 2.4 power (M2-6-1
                // DECISIONS §D2 terminal form — the dctl reference is the
                // bare 2.4; content encoding carries no black lift).
                built = try calibratedICC(
                    gamut: .rec709, white: .d65, gamma: 2.4,
                    label: "Lightamer Rec709 BT.1886")
            case .gamma22:
                built = try calibratedICC(
                    gamut: .rec709, white: .d65, gamma: 2.2,
                    label: "Lightamer Rec709 Gamma 2.2")
            case .linear, .st2084, .hlg, .gamma26, .gamma18:
                throw illegal(space: space, eotf: eotf)
            }
        case .p3d65:
            switch eotf {
            case .gamma22:
                built = try calibratedICC(
                    gamut: .p3, white: .d65, gamma: 2.2,
                    label: "Lightamer P3-D65 Gamma 2.2")
            case .st2084:
                built = try systemSpace(.displayP3PQ, space: space, eotf: eotf)
            case .linear, .hlg, .bt1886, .gamma26, .gamma18:
                throw illegal(space: space, eotf: eotf)
            }
        case .p3d60:
            switch eotf {
            case .gamma26:
                built = try calibratedICC(
                    gamut: .p3, white: .d60, gamma: 2.6,
                    label: "Lightamer P3-D60 Gamma 2.6")
            case .linear, .st2084, .hlg, .bt1886, .gamma22, .gamma18:
                throw illegal(space: space, eotf: eotf)
            }
        case .p3dci:
            switch eotf {
            case .gamma26:
                built = try calibratedICC(
                    gamut: .p3, white: .dci, gamma: 2.6,
                    label: "Lightamer P3-DCI Gamma 2.6")
            case .linear, .st2084, .hlg, .bt1886, .gamma22, .gamma18:
                throw illegal(space: space, eotf: eotf)
            }
        case .xyz:
            switch eotf {
            case .gamma26:
                // The XYZ basis: R=X, G=Y, B=Z — the IDENTITY matrix over
                // tristimulus space, white E (see header note).
                built = try calibratedICC(
                    gamut: .xyzBasis, white: .e, gamma: 2.6,
                    label: "Lightamer XYZ Gamma 2.6")
            case .linear, .st2084, .hlg, .bt1886, .gamma22, .gamma18:
                throw illegal(space: space, eotf: eotf)
            }
        case .rec2020:
            switch eotf {
            case .st2084:
                built = try systemSpace(.itur2100PQ, space: space, eotf: eotf)
            case .hlg:
                built = try systemSpace(.itur2100HLG, space: space, eotf: eotf)
            case .linear, .bt1886, .gamma22, .gamma26, .gamma18:
                throw illegal(space: space, eotf: eotf)
            }
        }
        store(built, space: space, eotf: eotf)
        return built
    }

    // MARK: - The legal-set mirror (typed rejection text)

    private static func illegal(
        space: DrtEncodingSpace, eotf: DrtEotf
    ) -> AppError {
        .invalidParameter(
            "drt output ICC: \(space.rawValue)+\(eotf.rawValue) is outside the "
                + "linkage table (legalEOTFs(for: \(space.rawValue))) — the record "
                + "may persist it, the export mapping refuses it")
    }

    // MARK: - System named profiles (the HDR arms)

    private enum SystemSpaceName {
        static let itur2100PQ = "kCGColorSpaceITUR_2100_PQ"
        static let itur2100HLG = "kCGColorSpaceITUR_2100_HLG"
        static let displayP3PQ = "kCGColorSpaceDisplayP3_PQ"
    }

    private enum SystemSpaceKey { case itur2100PQ, itur2100HLG, displayP3PQ }

    private static func systemSpace(
        _ key: SystemSpaceKey, space: DrtEncodingSpace, eotf: DrtEotf
    ) throws -> CGColorSpace {
        let rawName: String
        switch key {
        case .itur2100PQ: rawName = SystemSpaceName.itur2100PQ
        case .itur2100HLG: rawName = SystemSpaceName.itur2100HLG
        case .displayP3PQ: rawName = SystemSpaceName.displayP3PQ
        }
        guard let system = CGColorSpace(name: rawName as CFString) else {
            throw AppError.invalidParameter(
                "drt output ICC: system profile \(rawName) unavailable "
                    + "(\(space.rawValue)+\(eotf.rawValue))")
        }
        return system
    }

    // MARK: - Instance cache (one per combo, forever — D-13-2-7)

    private struct CacheKey: Hashable {
        let space: DrtEncodingSpace
        let eotf: DrtEotf
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var instances: [CacheKey: CGColorSpace] = [:]

    private static func cache(space: DrtEncodingSpace, eotf: DrtEotf) -> CGColorSpace? {
        lock.lock()
        defer { lock.unlock() }
        return instances[CacheKey(space: space, eotf: eotf)]
    }

    private static func store(_ instance: CGColorSpace, space: DrtEncodingSpace, eotf: DrtEotf) {
        lock.lock()
        defer { lock.unlock() }
        instances[CacheKey(space: space, eotf: eotf)] = instance
    }
}

// MARK: - The calibrated ICC builder (bytes → CGColorSpace)

/// The gamut constants (xy chromaticity row order: r, g, b).
private enum DrtOutputGamut {
    /// xy triple per primary.
    case rec709
    case p3
    /// The XYZ basis — the identity matrix face (see DrtOutputColorSpace
    /// header): the primaries never enter; the matrix is built directly.
    case xyzBasis
}

/// The white constants (xy chromaticity).
private enum DrtOutputWhite {
    case d65
    case d60
    case dci
    case e
}

private extension DrtOutputWhite {
    /// (x, y) chromaticity.
    var xy: (Double, Double) {
        switch self {
        case .d65: return (0.3127, 0.3290)
        case .d60: return (0.32168, 0.33767)
        case .dci: return (0.314, 0.351)
        case .e: return (1.0 / 3.0, 1.0 / 3.0)
        }
    }
}

extension DrtOutputColorSpace {

    /// Build the calibrated profile for one legal SDR arm and mint the
    /// `CGColorSpace` from its bytes. Deterministic bytes (fixed timestamp,
    /// no profile ID) — the same combo always yields the same profile.
    fileprivate static func calibratedICC(
        gamut: DrtOutputGamut, white: DrtOutputWhite, gamma: Double, label: String
    ) throws -> CGColorSpace {
        let data = Self.iccProfileData(
            gamut: gamut, white: white, gamma: gamma, label: label)
        guard let space = CGColorSpace(iccProfileData: data as CFData) else {
            throw AppError.invalidParameter(
                "drt output ICC: ColorSync refused the generated profile (\(label))")
        }
        return space
    }

    /// The D50 PCS illuminant (ICC constant).
    fileprivate static let d50PCS = SIMD3<Double>(0.96420288, 1.0, 0.82490539)

    /// The Bradford chromatic-adaptation matrix (native white → PCS).
    private static let bradford = Mat3(rows: [
        [0.8951, 0.2664, -0.1614],
        [-0.7502, 1.7135, 0.0367],
        [0.0389, -0.0685, 1.0296],
    ])
    private static let bradfordInverse = Mat3(rows: [
        [0.9869929, -0.1470543, 0.1599627],
        [0.4323053, 0.5183603, 0.0492912],
        [-0.0085287, 0.0400428, 0.9684867],
    ])

    /// The adaptation matrix M_A for one native white (Bradford cone domain).
    fileprivate static func bradfordAdaptation(nativeWhite: SIMD3<Double>) -> Mat3 {
        let coneSource = bradford * nativeWhite
        let coneTarget = bradford * d50PCS
        var scale = Mat3.identity
        for i in 0..<3 {
            scale.rows[i][i] = coneTarget[i] / coneSource[i]
        }
        return bradfordInverse * scale * bradford
    }

    /// The RGB→XYZ(D50-adapted) matrix for one gamut+white: the native
    /// primaries matrix solved from the xy chromaticities (columns scaled so
    /// (1,1,1) → the native white tristimulus), then Bradford-adapted to D50.
    /// The xyzBasis gamut skips the chromaticity solve — the identity matrix
    /// over tristimulus space (R=X, G=Y, B=Z), adapted from white E.
    fileprivate static func rgbToXYZD50(gamut: DrtOutputGamut, white: DrtOutputWhite) -> Mat3 {
        let native: Mat3
        switch gamut {
        case .xyzBasis:
            native = Mat3.identity
        case .rec709, .p3:
            let primaries: [(Double, Double)] = gamut == .rec709
                ? [(0.640, 0.330), (0.300, 0.600), (0.150, 0.060)]
                : [(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)]
            let (wx, wy) = white.xy
            let w = SIMD3<Double>(wx / wy, 1.0, (1.0 - wx - wy) / wy)
            // C: chromaticity columns (unscaled); S: the per-primary scale
            // solving C·S = w.
            let columns = primaries.map { p -> SIMD3<Double> in
                SIMD3<Double>(p.0 / p.1, 1.0, (1.0 - p.0 - p.1) / p.1)
            }
            let c = Mat3(columns: columns)
            let s = c.inverse * w
            native = Mat3(columns: [
                columns[0] * s.x, columns[1] * s.y, columns[2] * s.z,
            ])
        }
        return bradfordAdaptation(nativeWhite: native * SIMD3<Double>(1, 1, 1)) * native
    }

    /// The full ICC v4 matrix-shaper profile bytes (deterministic).
    /// Tags: desc, cprt, wtpt (D50), chad, rXYZ, gXYZ, bXYZ, rTRC, gTRC,
    /// bTRC — the Alcedo asset structure (read-only benchmark) rebuilt from
    /// scratch, no GPL bytes.
    ///
    /// TRC = `curv` count 1 (u8Fixed8 power): HOST-VERIFIED — the v4 `para`
    /// fn-0 face is MISPARSED by macOS 27 ColorSync (every cross-profile
    /// conversion through it collapses to 0/1; probed against the identical
    /// matrix with a curv TRC converting exactly), while the plain curv
    /// power converts exactly (linear 0.5 → gamma-2.2 encode 0.7297). The
    /// u8Fixed8 carrier quantizes the power by 1/256 (2.2 → 2.19922) — the
    /// ICC format's own floor, the same face lcms-era profiles ship.
    fileprivate static func iccProfileData(
        gamut: DrtOutputGamut, white: DrtOutputWhite, gamma: Double, label: String
    ) -> Data {
        let m = rgbToXYZD50(gamut: gamut, white: white)
        var out = ByteSink()

        // ── tag payloads (built first; the header needs the total size) ──
        func xyz(_ v: SIMD3<Double>) -> Data {
            var d = ByteSink()
            d.fourCC("XYZ ")
            d.u32(0)
            d.s15(v.x); d.s15(v.y); d.s15(v.z)
            return d.data
        }
        let tagDesc = mluc(label)
        let tagCprt = mluc("Generated by Lightamer — public domain profile data")
        let tagWtpt = xyz(d50PCS)
        var chadPayload = ByteSink()
        chadPayload.fourCC("sf32")
        chadPayload.u32(0)
        let adapt = bradfordAdaptation(
            nativeWhite: {
                // Re-derive the native white for chad from the gamut+white.
                switch gamut {
                case .xyzBasis:
                    return SIMD3<Double>(1, 1, 1)
                case .rec709, .p3:
                    let (wx, wy) = white.xy
                    return SIMD3<Double>(wx / wy, 1.0, (1.0 - wx - wy) / wy)
                }
            }())
        for row in 0..<3 { for col in 0..<3 { chadPayload.s15(adapt.rows[row][col]) } }
        let tagChad = chadPayload.data
        let tagR = xyz(SIMD3<Double>(m.rows[0][0], m.rows[1][0], m.rows[2][0]))
        let tagG = xyz(SIMD3<Double>(m.rows[0][1], m.rows[1][1], m.rows[2][1]))
        let tagB = xyz(SIMD3<Double>(m.rows[0][2], m.rows[1][2], m.rows[2][2]))
        /// The `curv` count-1 TRC: one u8Fixed8 power (ICC floor 1/256).
        func curvGamma(_ g: Double) -> Data {
            var d = ByteSink()
            d.fourCC("curv")
            d.u32(0)
            d.u32(1) // count 1 = the u8Fixed8 gamma face
            d.u16(UInt16((g * 256.0).rounded()))
            d.u16(0) // (padding to the 4-byte element alignment)
            return d.data
        }
        let tagRTRC = curvGamma(gamma)
        let tagGTRC = curvGamma(gamma)
        let tagBTRC = curvGamma(gamma)

        // ── the header + tag table + payloads ────────────────────────────
        let tags: [(String, Data)] = [
            ("desc", tagDesc), ("cprt", tagCprt), ("wtpt", tagWtpt),
            ("chad", tagChad), ("rXYZ", tagR), ("gXYZ", tagG), ("bXYZ", tagB),
            ("rTRC", tagRTRC), ("gTRC", tagGTRC), ("bTRC", tagBTRC),
        ]
        let tagTableSize = 4 + tags.count * 12
        var entries: [(String, Int, Int)] = []
        var payload = ByteSink()
        for (name, data) in tags {
            // Tag offsets are 4-aligned (ICC rule) — pad before each entry.
            while (128 + tagTableSize + payload.data.count) % 4 != 0 { payload.u8(0) }
            entries.append((name, 128 + tagTableSize + payload.data.count, data.count))
            payload.append(data)
        }
        var header = ByteSink()
        let totalSize = 128 + tagTableSize + payload.alignedCount
        header.u32(UInt32(totalSize))
        header.u32(0) // preferred CMM: none
        header.u32(0x04300000) // v4.3
        header.fourCC("mntr")
        header.fourCC("RGB ")
        header.fourCC("XYZ ")
        header.u16(2026); header.u16(1); header.u16(1) // fixed datetime (determinism)
        header.u16(0); header.u16(0); header.u16(0)
        header.fourCC("acsp")
        header.u32(0) // platform
        header.u32(0) // flags
        header.u32(0) // manufacturer
        header.u32(0) // model
        header.u32(0); header.u32(0) // attributes
        header.u32(0) // rendering intent: perceptual
        header.s15(d50PCS.x); header.s15(d50PCS.y); header.s15(d50PCS.z)
        header.u32(0) // creator
        for _ in 0..<16 { header.u8(0) } // profile ID (absent)
        for _ in 0..<28 { header.u8(0) } // reserved
        precondition(header.data.count == 128, "ICC header must be 128 bytes")

        out.append(header.data)
        out.u32(UInt32(tags.count))
        for (name, off, size) in entries {
            out.fourCC(name)
            out.u32(UInt32(off))
            out.u32(UInt32(size))
        }
        out.append(payload.data)
        return out.data
    }

    /// The mluc (multi-localized unicode) type with one en-US entry.
    private static func mluc(_ text: String) -> Data {
        var d = ByteSink()
        let utf16 = Array(text.utf16)
        d.fourCC("mluc")
        d.u32(0)
        d.u32(1) // record count
        d.u32(12) // record size
        d.u8(UInt8(ascii: "e")); d.u8(UInt8(ascii: "n")) // language "en"
        d.u8(UInt8(ascii: "U")); d.u8(UInt8(ascii: "S")) // country "US"
        d.u32(UInt32(utf16.count * 2))
        d.u32(28) // string offset relative to the mluc start (header 16 + record 12)
        for unit in utf16 { d.u16(unit) }
        return d.data
    }
}

/// Big-endian byte assembler for the profile writer.
private struct ByteSink {
    private(set) var data = Data()

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) {
        data.append(UInt8(v >> 8 & 0xFF)); data.append(UInt8(v & 0xFF))
    }
    mutating func u32(_ v: UInt32) {
        data.append(UInt8(v >> 24 & 0xFF)); data.append(UInt8(v >> 16 & 0xFF))
        data.append(UInt8(v >> 8 & 0xFF)); data.append(UInt8(v & 0xFF))
    }
    mutating func fourCC(_ s: String) {
        let bytes = Array(s.utf8.prefix(4))
        precondition(bytes.count == 4, "fourCC must be 4 bytes")
        for b in bytes { u8(b) }
    }
    /// ICC s15Fixed16.
    mutating func s15(_ v: Double) {
        let raw = Int32((v * 65536.0).rounded())
        u32(UInt32(bitPattern: raw))
    }
    mutating func append(_ other: Data) { data.append(other) }
    /// The payload face's byte count including alignment padding.
    var alignedCount: Int { data.count }
}

/// A minimal 3×3 matrix (row-major) for the colorimetry math.
private struct Mat3 {
    var rows: [[Double]]

    init(rows: [[Double]]) { self.rows = rows }
    init(columns: [SIMD3<Double>]) {
        rows = (0..<3).map { r in columns.map { $0[r] } }
    }
    static var identity: Mat3 { Mat3(rows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]) }

    static func * (lhs: Mat3, rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            lhs.rows[0][0] * rhs.x + lhs.rows[0][1] * rhs.y + lhs.rows[0][2] * rhs.z,
            lhs.rows[1][0] * rhs.x + lhs.rows[1][1] * rhs.y + lhs.rows[1][2] * rhs.z,
            lhs.rows[2][0] * rhs.x + lhs.rows[2][1] * rhs.y + lhs.rows[2][2] * rhs.z)
    }
    static func * (lhs: Mat3, rhs: Mat3) -> Mat3 {
        Mat3(rows: (0..<3).map { r in
            (0..<3).map { c in
                (0..<3).map { lhs.rows[r][$0] * rhs.rows[$0][c] }.reduce(0, +)
            }
        })
    }
    var inverse: Mat3 {
        let a = rows
        let det = a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
            - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        let inv = { (v: Double) in v / det }
        return Mat3(rows: [
            [inv(a[1][1] * a[2][2] - a[1][2] * a[2][1]),
             inv(a[0][2] * a[2][1] - a[0][1] * a[2][2]),
             inv(a[0][1] * a[1][2] - a[0][2] * a[1][1])],
            [inv(a[1][2] * a[2][0] - a[1][0] * a[2][2]),
             inv(a[0][0] * a[2][2] - a[0][2] * a[2][0]),
             inv(a[0][2] * a[1][0] - a[0][0] * a[1][2])],
            [inv(a[1][0] * a[2][1] - a[1][1] * a[2][0]),
             inv(a[0][1] * a[2][0] - a[0][0] * a[2][1]),
             inv(a[0][0] * a[1][1] - a[0][1] * a[1][0])],
        ])
    }
}
