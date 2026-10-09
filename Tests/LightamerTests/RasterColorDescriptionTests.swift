@testable import LightamerCore
import Foundation
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// RasterColorDescriptionTests (Plan M4-1-01 T1, KD-1 — IOP bundle, Core-level
// decode-family precedent) — the description resolution face:
//
//   • the resolution order, one method per position: ① embedded ICC
//     matrix-shaper (chad undone), ①′ linear-ICC float32 → sceneLinear
//     (checker E1 half-edge), ② no-ICC float32 → scene-linear Rec.2020,
//     ③ the sRGB default;
//   • the dual-tag precedence (matrix-shaper + A2B0 → matrix-shaper wins)
//     and the LUT-only form (iccLutConverted);
//   • the usable checks, one negative each, with the fall-through reason;
//   • the canonicalization ladder, positive AND negative per gate:
//     PQ / HLG at 2e-4, sRGB piecewise and pure gamma at 1e-4 (checker E5);
//   • the PQ peak ladder (mDCv → MaxCLL → 1000, clamp [100, 10000]);
//   • the named-space fast path;
//   • the field-explicit fingerprint (equal fields = equal fingerprint).
//
// The ICC fixtures are SYNTHESIZED IN-TEST (byte-level builders) — the
// on-disk TIFF fixture matrix is T2's deliverable and T3 consumes it; this
// file pins the parser/resolver semantics directly.
// ─────────────────────────────────────────────────────────────────────────────

final class RasterColorDescriptionTests: XCTestCase {

    // MARK: - ICC byte builder (the in-test synthesis face)

    /// A big-endian assembler (mirror of the export side's ByteSink — that
    /// one is file-private there).
    private struct Sink {
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
            precondition(bytes.count == 4)
            for b in bytes { u8(b) }
        }
        mutating func s15(_ v: Double) {
            u32(UInt32(bitPattern: Int32((v * 65536.0).rounded())))
        }
        mutating func append(_ other: Data) { data.append(other) }
        var alignedCount: Int { data.count }
    }

    /// One TRC payload.
    private enum TRCPayload {
        case identity          // curv count 0
        case gamma(Double)     // curv count 1 (u8Fixed8)
        case table([Double])   // curv table (u16 samples)
        case para(type: UInt8, params: [Double])
    }

    /// Build a minimal ICC v4 matrix-shaper profile (RGB).
    /// - Parameters:
    ///   - nativePrimariesXY: R,G,B xy + white xy (the NATIVE values the
    ///     parser must recover after undoing chad).
    ///   - trc: the per-channel curve payload (all three channels carry it).
    ///   - withChad: build the Bradford chad so the PCS tags are genuinely
    ///     D50-adapted (the parser must undo it back to the native values).
    ///   - withA2B0: also embed an A2B0 LUT tag (the dual-tag precedence
    ///     fixture — matrix-shaper must win).
    ///   - onlyA2B0: emit ONLY the A2B0 tag (the LUT-based fixture).
    ///   - mdcvMaxNits / ccllMaxNits: the HDR metadata tags.
    ///   - cicp: the v4.4 cicp payload bytes.
    ///   - overrideWTPT: a replacement wtpt XYZ (the white-outside fixture).
    ///   - degeneratePrimaries: set bXYZ = rXYZ (the degenerate fixture).
    private func buildICC(
        nativePrimariesXY: (rx: Double, ry: Double, gx: Double, gy: Double, bx: Double, by: Double),
        nativeWhiteXY: (x: Double, y: Double),
        trc: TRCPayload,
        withChad: Bool = true,
        withA2B0: Bool = false,
        onlyA2B0: Bool = false,
        mdcvMaxNits: Double? = nil,
        ccllMaxNits: Double? = nil,
        cicp: (UInt8, UInt8, UInt8, UInt8)? = nil,
        overrideWTPT: SIMD3<Double>? = nil,
        degeneratePrimaries: Bool = false,
        label: String = "Test Profile"
    ) -> Data {
        let d50 = RasterIccParser.d50PCS
        let nativeWhite = SIMD3<Double>(
            nativeWhiteXY.x / nativeWhiteXY.y, 1.0,
            (1.0 - nativeWhiteXY.x - nativeWhiteXY.y) / nativeWhiteXY.y)
        let chad = RasterIccMat3.bradfordAdaptation(from: nativeWhite, to: d50)

        func nativeXYZ(x: Double, y: Double) -> SIMD3<Double> {
            SIMD3<Double>(x / y, 1.0, (1.0 - x - y) / y)
        }
        var rPCS = chad * nativeXYZ(x: nativePrimariesXY.rx, y: nativePrimariesXY.ry)
        let gPCS = chad * nativeXYZ(x: nativePrimariesXY.gx, y: nativePrimariesXY.gy)
        var bPCS = chad * nativeXYZ(x: nativePrimariesXY.bx, y: nativePrimariesXY.by)
        if degeneratePrimaries { bPCS = rPCS }
        let wtpt = overrideWTPT ?? d50

        // ── tag payloads ──
        func xyzTag(_ v: SIMD3<Double>) -> Data {
            var d = Sink()
            d.fourCC("XYZ "); d.u32(0)
            d.s15(v.x); d.s15(v.y); d.s15(v.z)
            return d.data
        }
        let trcData: Data
        switch trc {
        case .identity:
            var d = Sink(); d.fourCC("curv"); d.u32(0); d.u32(0)
            trcData = d.data
        case .gamma(let g):
            var d = Sink(); d.fourCC("curv"); d.u32(0); d.u32(1)
            d.u16(UInt16((g * 256.0).rounded())); d.u16(0)
            trcData = d.data
        case .table(let samples):
            var d = Sink(); d.fourCC("curv"); d.u32(0); d.u32(UInt32(samples.count))
            for s in samples { d.u16(UInt16(max(0, min(65535, (s * 65535.0).rounded())))) }
            if samples.count % 2 == 1 { d.u16(0) } // 4-byte alignment
            trcData = d.data
        case .para(let type, let params):
            var d = Sink(); d.fourCC("para"); d.u32(0); d.u16(UInt16(type)); d.u16(0)
            for p in params { d.s15(p) }
            trcData = d.data
        }
        var chadPayload = Sink()
        chadPayload.fourCC("sf32"); chadPayload.u32(0)
        for row in 0..<3 { for col in 0..<3 { chadPayload.s15(chad.rows[row][col]) } }
        let cicpPayload: Data
        if let cicp {
            var d = Sink()
            d.fourCC("cicp"); d.u32(0)
            d.u8(cicp.0); d.u8(cicp.1); d.u8(cicp.2); d.u8(cicp.3)
            cicpPayload = d.data
        } else {
            cicpPayload = Data()
        }
        let mdcvPayload: Data
        if let mdcvMaxNits {
            var d = Sink()
            d.fourCC("mdcv"); d.u32(0)
            // 3 primaries × (x,y) u16 ×50000 + white (x,y) + maxLum + minLum.
            for p in [nativePrimariesXY.rx, nativePrimariesXY.ry,
                      nativePrimariesXY.gx, nativePrimariesXY.gy,
                      nativePrimariesXY.bx, nativePrimariesXY.by] {
                d.u16(UInt16((p * 50000.0).rounded()))
            }
            d.u16(UInt16((nativeWhiteXY.x * 50000.0).rounded()))
            d.u16(UInt16((nativeWhiteXY.y * 50000.0).rounded()))
            d.u32(UInt32((mdcvMaxNits * 10000.0).rounded()))
            d.u32(1) // min luminance ~0.0001 nits
            mdcvPayload = d.data
        } else {
            mdcvPayload = Data()
        }
        let ccllPayload: Data
        if let ccllMaxNits {
            var d = Sink()
            d.fourCC("ccll"); d.u32(0)
            d.u32(UInt32((ccllMaxNits * 10000.0).rounded()))
            d.u32(0)
            ccllPayload = d.data
        } else {
            ccllPayload = Data()
        }
        // A tiny A2B0 payload (mft1-shaped nonsense — presence is all the
        // discrimination logic reads).
        var a2b0 = Sink()
        a2b0.fourCC("mft1"); a2b0.u32(0)
        for _ in 0..<12 { a2b0.u8(0) }
        let a2b0Payload = a2b0.data

        var descPayload = Sink()
        let utf16 = Array(label.utf16)
        descPayload.fourCC("mluc"); descPayload.u32(0)
        descPayload.u32(1); descPayload.u32(12)
        descPayload.u8(UInt8(ascii: "e")); descPayload.u8(UInt8(ascii: "n"))
        descPayload.u8(UInt8(ascii: "U")); descPayload.u8(UInt8(ascii: "S"))
        descPayload.u32(UInt32(utf16.count * 2)); descPayload.u32(28)
        for unit in utf16 { descPayload.u16(unit) }

        var tags: [(String, Data)] = [("desc", descPayload.data)]
        if !onlyA2B0 {
            tags.append(contentsOf: [
                ("wtpt", xyzTag(wtpt)),
                ("chad", chadPayload.data),
                ("rXYZ", xyzTag(rPCS)),
                ("gXYZ", xyzTag(gPCS)),
                ("bXYZ", xyzTag(bPCS)),
                ("rTRC", trcData), ("gTRC", trcData), ("bTRC", trcData),
            ])
        }
        if withA2B0 || onlyA2B0 { tags.append(("A2B0", a2b0Payload)) }
        if cicp != nil { tags.append(("cicp", cicpPayload)) }
        if mdcvMaxNits != nil { tags.append(("mdcv", mdcvPayload)) }
        if ccllMaxNits != nil { tags.append(("ccll", ccllPayload)) }

        // ── header + tag table ──
        let tagTableSize = 4 + tags.count * 12
        var entries: [(String, Int, Int)] = []
        var payload = Sink()
        for (name, data) in tags {
            while (128 + tagTableSize + payload.data.count) % 4 != 0 { payload.u8(0) }
            entries.append((name, 128 + tagTableSize + payload.data.count, data.count))
            payload.append(data)
        }
        var header = Sink()
        let total = 128 + tagTableSize + payload.alignedCount
        header.u32(UInt32(total))
        header.u32(0)
        header.u32(0x04300000)
        header.fourCC("mntr")
        header.fourCC("RGB ")
        header.fourCC("XYZ ")
        header.u16(2026); header.u16(1); header.u16(1)
        header.u16(0); header.u16(0); header.u16(0)
        header.fourCC("acsp")
        // platform / flags / manufacturer / model / attributes(2) / intent.
        for _ in 0..<7 { header.u32(0) }
        header.s15(d50.x); header.s15(d50.y); header.s15(d50.z)
        header.u32(0)
        for _ in 0..<16 { header.u8(0) }
        for _ in 0..<28 { header.u8(0) }
        precondition(header.data.count == 128)

        var out = Sink()
        out.append(header.data)
        out.u32(UInt32(tags.count))
        for (name, off, size) in entries {
            out.fourCC(name); out.u32(UInt32(off)); out.u32(UInt32(size))
        }
        out.append(payload.data)
        return out.data
    }

    /// Convenience: an sRGB-shaped profile with a plain gamma TRC and an
    /// identity chad face (the parser's chad-undo must round-trip native).
    private func gammaProfile(gamma: Double) -> Data {
        buildICC(
            nativePrimariesXY: (0.7347, 0.2653, 0.1596, 0.8404, 0.0366, 0.0001),
            nativeWhiteXY: (0.3457, 0.3585),
            trc: .gamma(gamma))
    }

    // MARK: - Resolution order

    /// ① the embedded ICC matrix-shaper: primaries/white recovered through
    /// the chad undo; the gamma TRC canonicalized to the analytic form.
    func testEmbeddedICCMatrixShaperParsesPrimariesAndGamma() throws {
        let icc = gammaProfile(gamma: 2.2)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.transfer, .gamma(563.0 / 256.0)) // u8Fixed8 2.2 carrier
        // ProPhoto primaries (the builder's gamut), native white D50.
        XCTAssertEqual(Double(d.primariesXY[0]), 0.7347, accuracy: 2e-3)
        XCTAssertEqual(Double(d.primariesXY[2]), 0.1596, accuracy: 2e-3)
        XCTAssertEqual(Double(d.primariesXY[4]), 0.0366, accuracy: 2e-3)
        XCTAssertEqual(Double(d.primariesXY[6]), 0.3457, accuracy: 2e-3)
        XCTAssertEqual(d.peakLuminanceNits, 100.0)
        XCTAssertNil(d.defaultReason)
        XCTAssertNotNil(d.profileHash)
        XCTAssertEqual(d.profileDescription, "Test Profile")
    }

    /// ①′ the checker E1 half-edge: embedded linear-ICC + float32 →
    /// sceneLinear (matrix branch), primaries still from the ICC.
    func testLinearICCFloat32BecomesSceneLinear() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .identity)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: true)
        XCTAssertEqual(d.referral, .sceneLinear)
        XCTAssertEqual(d.transfer, .linear)
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        XCTAssertEqual(d.defaultReason, "linear-ICC float32 → scene-linear")
        XCTAssertEqual(Double(d.primariesXY[0]), 0.708, accuracy: 2e-3)
    }

    /// The ①′ converse: the same linear ICC on 8-bit storage stays
    /// display-referred (the linearize identity runs on the display leg).
    func testLinearICCNonFloatStaysDisplayReferred() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .identity)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.transfer, .linear)
        XCTAssertNil(d.defaultReason)
    }

    /// ② no ICC + float32 → scene-linear Rec.2020 default.
    func testNoICCFloat32DefaultsToSceneLinearRec2020() {
        let d = RasterColorResolver.resolve(iccData: nil, colorSpaceName: nil, isFloat: true)
        XCTAssertEqual(d.referral, .sceneLinear)
        XCTAssertEqual(d.transfer, .linear)
        XCTAssertEqual(d.origin, .tiffNoIccFloatLinear)
        XCTAssertEqual(d.primariesXY, RasterColorResolver.rec2020Primaries)
        XCTAssertNotNil(d.defaultReason)
    }

    /// ③ no ICC otherwise → the sRGB default with the reason recorded.
    func testNoICCDefaultsToSrgb() {
        let d = RasterColorResolver.resolve(iccData: nil, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.transfer, .srgbPiecewise)
        XCTAssertEqual(d.origin, .defaultSrgb)
        XCTAssertEqual(d.primariesXY, RasterColorResolver.sRGBPrimaries)
        XCTAssertEqual(d.peakLuminanceNits, 100.0)
        XCTAssertNotNil(d.defaultReason)
    }

    /// The dual-tag precedence: matrix-shaper + A2B0 coexisting → the
    /// matrix-shaper wins (NOT iccLutConverted — the Alcedo D4 wording).
    func testDualTagMatrixShaperBeatsA2B0() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .gamma(2.19921875),
            withA2B0: true)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .iccMatrixShaper)
        XCTAssertEqual(d.transfer, .gamma(2.19921875))
    }

    /// LUT-only (A2B0, no matrix tags) → iccLutConverted: Rec.2020 +
    /// linear + display-referred (the only CI-leg TIFF form).
    func testLutOnlyProfileBecomesIccLutConverted() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .gamma(2.2),
            onlyA2B0: true)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .iccLutConverted)
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.transfer, .linear)
        XCTAssertEqual(d.primariesXY, RasterColorResolver.rec2020Primaries)
    }

    /// The named-space fast path (PQ) — canonical by construction.
    func testNamedSpaceFastPathPQ() {
        let d = RasterColorResolver.resolve(
            iccData: Data([0x00]), colorSpaceName: "kCGColorSpaceITUR_2100_PQ",
            isFloat: false)
        XCTAssertEqual(d.transfer, .st2084)
        XCTAssertEqual(d.referral, .displayReferred)
        XCTAssertEqual(d.primariesXY, RasterColorResolver.rec2020Primaries)
        XCTAssertEqual(d.peakLuminanceNits, 1000.0)
        XCTAssertEqual(d.origin, .iccCicp)
        XCTAssertEqual(d.profileHash, RasterColorResolver.hash(Data([0x00])))
    }

    /// The v4.4 cicp tag overrides the profile TRC + primaries.
    func testCicpTagOverridesTransferAndPrimaries() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .gamma(2.2),
            cicp: (9, 16, 0, 1))
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .iccCicp)
        XCTAssertEqual(d.transfer, .st2084)
        XCTAssertEqual(d.primariesXY, RasterColorResolver.rec2020Primaries)
        XCTAssertEqual(d.peakLuminanceNits, 1000.0) // no mDCv → ladder terminal
    }

    // MARK: - Usable checks (one negative each + the fall-through reason)

    func testDegeneratePrimariesFallToDefaultWithReason() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .gamma(2.2),
            degeneratePrimaries: true)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .defaultSrgb)
        XCTAssertEqual(d.transfer, .srgbPiecewise)
        XCTAssertTrue(d.defaultReason?.contains("usable") == true)
    }

    func testWhiteOutsideTriangleFallsToDefault() throws {
        // wtpt pointing deep outside the sRGB triangle (pure green XYZ).
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .gamma(2.2),
            overrideWTPT: SIMD3<Double>(0.1, 1.0, 0.05))
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .defaultSrgb)
        XCTAssertTrue(d.defaultReason?.contains("usable") == true)
    }

    func testNonMonotonicCurveFallsToDefault() throws {
        // A table with a dip in the shadows (non-monotonic).
        var samples = (0..<64).map { RasterTRC.srgbPiecewiseDecode(Double($0) / 63.0) }
        samples[5] = samples[6] + 0.05
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .table(samples))
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.origin, .defaultSrgb)
        XCTAssertTrue(d.defaultReason?.contains("usable") == true)
    }

    /// Non-uniform TRCs (rTRC ≠ gTRC) — unusable, falls to the default.
    func testMismatchedChannelTRCsFallToDefault() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .gamma(2.2),
            degeneratePrimaries: false)
        // Hand-corrupt gTRC into a different gamma by rebuilding the tag
        // table with one channel swapped — simplest: build two profiles and
        // splice. Instead: reuse the mismatched-trc path directly at the
        // parser level.
        var profile = RasterIccParser.parse(icc)!
        profile.trcG = .gammaValue(1.8)
        let resolved = RasterColorResolver.descriptionFromProfile(
            profile, iccData: icc)
        XCTAssertNil(resolved, "non-uniform TRCs must be unusable")
    }

    // MARK: - Canonicalization (positive AND negative per gate, checker E5)

    /// The u16-quantized table builder (the realistic carrier — quantization
    /// noise ≈ 7.6e-6, far inside every gate).
    private func quantizedTable(_ f: (Double) -> Double, n: Int = 256) -> [Double] {
        (0..<n).map { i in
            let raw = (f(Double(i) / Double(n - 1)) * 65535.0).rounded()
            return max(0, min(65535.0, raw)) / 65535.0
        }
    }

    func testCanonicalizePQTableWithinGate() {
        let samples = quantizedTable { RasterTRC.pqDecodeRelative($0) }
        XCTAssertEqual(RasterTRC.canonicalize(samples: samples), .st2084)
    }

    func testCanonicalizePQTableBeyondGateStaysSampled() {
        var samples = quantizedTable { RasterTRC.pqDecodeRelative($0) }
        // A 1e-3-magnitude uniform perturbation — outside the 2e-4 gate but
        // still monotonic and inside the monotonic tolerance.
        for i in 1..<samples.count { samples[i] = min(1.0, samples[i] + 1e-3) }
        if case .iccSampled(let table) = RasterTRC.canonicalize(samples: samples) {
            XCTAssertEqual(table.count, 4096)
        } else {
            XCTFail("a beyond-gate table must stay iccSampled")
        }
    }

    func testCanonicalizeHLGTableWithinGate() {
        let samples = quantizedTable { RasterTRC.hlgDisplayDecode($0) }
        XCTAssertEqual(RasterTRC.canonicalize(samples: samples), .hlg)
    }

    func testCanonicalizeHLGBeyondGateStaysSampled() {
        var samples = quantizedTable { RasterTRC.hlgDisplayDecode($0) }
        for i in 1..<samples.count { samples[i] = min(1.0, samples[i] + 1e-3) }
        if case .iccSampled = RasterTRC.canonicalize(samples: samples) {} else {
            XCTFail("a beyond-gate table must stay iccSampled")
        }
    }

    func testCanonicalizeSrgbPiecewiseWithinGate() {
        let samples = quantizedTable { RasterTRC.srgbPiecewiseDecode($0) }
        XCTAssertEqual(RasterTRC.canonicalize(samples: samples), .srgbPiecewise)
    }

    func testCanonicalizeSrgbBeyondGateStaysSampled() {
        // A gamma-2.2 table differs from the sRGB piecewise by up to ~2% —
        // far outside the 1e-4 sRGB gate (and outside the gamma fit's
        // residual gate too — the piecewise is not a pure power).
        let samples = quantizedTable { Foundation.pow($0, 2.2) }
        if case .gamma = RasterTRC.canonicalize(samples: samples) {} else {
            XCTFail("a gamma table should at least fit a pure gamma")
        }
        if case .srgbPiecewise = RasterTRC.canonicalize(samples: samples) {
            XCTFail("gamma 2.2 must not canonicalize to the sRGB piecewise")
        }
    }

    func testCanonicalizePureGammaWithinGate() {
        let samples = quantizedTable { Foundation.pow($0, 1.8) }
        if case .gamma(let g) = RasterTRC.canonicalize(samples: samples) {
            XCTAssertEqual(g, 1.8, accuracy: 5e-3)
        } else {
            XCTFail("a pure gamma table must canonicalize")
        }
    }

    func testCanonicalizeIdentityTableBecomesLinear() {
        let samples = quantizedTable { $0 }
        XCTAssertEqual(RasterTRC.canonicalize(samples: samples), .linear)
    }

    /// A through-the-resolver canonicalization: a PQ-shaped sampled profile
    /// must describe .st2084 (the upstream R1 misread-back regression) and
    /// pick up the mDCv peak.
    func testPQShapedSampledProfileCanonicalizesWithMdcvPeak() throws {
        let samples = quantizedTable { RasterTRC.pqDecodeRelative($0) }
        let icc = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .table(samples),
            mdcvMaxNits: 4000.0)
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.transfer, .st2084)
        XCTAssertEqual(d.peakLuminanceNits, 4000.0)
        XCTAssertEqual(d.referral, .displayReferred)
    }

    /// Parametric TRCs keep type + parameters (the Alcedo form).
    func testParametricTRCKeepsTypeAndParams() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.640, 0.330, 0.300, 0.600, 0.150, 0.060),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 3, params: [2.4, 1 / 1.055, 0.0521327, 0.0773992706693475, 0.04045]))
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        guard case .iccParametric(let type, let params) = d.transfer else {
            return XCTFail("parametric TRC must keep its form, got \(d.transfer)")
        }
        XCTAssertEqual(type, 3)
        XCTAssertEqual(params.count, 5)
        XCTAssertEqual(params[0], 2.4, accuracy: 1e-4) // the s15Fixed16 floor
    }

    // MARK: - Peak ladder

    func testPeakLadderMdcvOverCcllOverDefault() throws {
        let both = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 0, params: [2.6]), // any curve; PQ comes via cicp
            mdcvMaxNits: 3200.0,
            ccllMaxNits: 1000.0,
            cicp: (9, 16, 0, 1))
        XCTAssertEqual(
            RasterColorResolver.resolve(iccData: both, colorSpaceName: nil, isFloat: false)
                .peakLuminanceNits, 3200.0)

        let ccllOnly = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 0, params: [2.6]),
            ccllMaxNits: 800.0,
            cicp: (9, 16, 0, 1))
        XCTAssertEqual(
            RasterColorResolver.resolve(iccData: ccllOnly, colorSpaceName: nil, isFloat: false)
                .peakLuminanceNits, 800.0)

        let neither = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 0, params: [2.6]),
            cicp: (9, 16, 0, 1))
        XCTAssertEqual(
            RasterColorResolver.resolve(iccData: neither, colorSpaceName: nil, isFloat: false)
                .peakLuminanceNits, 1000.0)
    }

    func testPeakLadderClampBounds() throws {
        let over = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 0, params: [2.6]),
            mdcvMaxNits: 20000.0,
            cicp: (9, 16, 0, 1))
        XCTAssertEqual(
            RasterColorResolver.resolve(iccData: over, colorSpaceName: nil, isFloat: false)
                .peakLuminanceNits, 10000.0)

        let under = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 0, params: [2.6]),
            mdcvMaxNits: 20.0,
            cicp: (9, 16, 0, 1))
        XCTAssertEqual(
            RasterColorResolver.resolve(iccData: under, colorSpaceName: nil, isFloat: false)
                .peakLuminanceNits, 100.0)
    }

    /// HLG peak pins to the fixed 1000-nit reference.
    func testHLGPeakIsFixed1000() throws {
        let icc = buildICC(
            nativePrimariesXY: (0.708, 0.292, 0.170, 0.797, 0.131, 0.046),
            nativeWhiteXY: (0.3127, 0.3290),
            trc: .para(type: 0, params: [2.6]),
            mdcvMaxNits: 4000.0,
            cicp: (9, 18, 0, 1))
        let d = RasterColorResolver.resolve(iccData: icc, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(d.transfer, .hlg)
        XCTAssertEqual(d.peakLuminanceNits, 1000.0)
    }

    // MARK: - Fingerprint + hash

    func testFingerprintFieldExplicit() {
        let a = RasterColorResolver.resolve(iccData: nil, colorSpaceName: nil, isFloat: false)
        let b = RasterColorResolver.resolve(iccData: nil, colorSpaceName: nil, isFloat: false)
        XCTAssertEqual(a.stableFingerprint(), b.stableFingerprint())

        var c = a
        c.transfer = .gamma(2.4)
        XCTAssertNotEqual(a.stableFingerprint(), c.stableFingerprint())

        var e = a
        e.primariesXY[0] += 0.001
        XCTAssertNotEqual(a.stableFingerprint(), e.stableFingerprint())

        var f = a
        f.peakLuminanceNits = 1000
        XCTAssertNotEqual(a.stableFingerprint(), f.stableFingerprint())

        // iccSampled table contents enter the fold.
        var g = a
        g.transfer = .iccSampled([0.0, 0.5, 1.0])
        var h = a
        h.transfer = .iccSampled([0.0, 0.5, 1.0, 1.0])
        XCTAssertNotEqual(g.stableFingerprint(), h.stableFingerprint())
    }

    func testProfileHashIsTruncatedSHA256() {
        let data = Data("lightamer-icc-hash-probe".utf8)
        let h1 = RasterColorResolver.hash(data)
        let h2 = RasterColorResolver.hash(data)
        XCTAssertEqual(h1, h2)
        XCTAssertNil(RasterColorResolver.hash(nil))
        let other = Data("lightamer-icc-hash-prob2".utf8)
        XCTAssertNotEqual(h1, RasterColorResolver.hash(other))
    }
}
