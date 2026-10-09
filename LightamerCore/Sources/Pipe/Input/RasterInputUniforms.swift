import Foundation
import simd

// ─────────────────────────────────────────────────────────────────────────────
// RasterInputUniforms — the raster input leg's OWN flat uniform ABI
// (Plan M4-1-01 T7, KD-6). Deliberately NOT the `Aces2Uniforms` type (the
// RESEARCH §3.4 anti-coupling ruling: the inverse leg's signature evolves
// independently of the forward's frozen buffer). The layout ORDER below is
// the ABI, mirrored member-for-member by `RasterInputUniforms` in
// `RasterInputKernels.metal`; the size-probe kernel pins the byte count.
//
// Sections: the TRC head (the linearize face — the transfer kind ordinal,
// the gamma value, the ICC parametric set, the sampled-table count), the
// ACES 2.0 parameter point (the same field shapes the forward packs, built
// from `Aces2Reference.params(..., rgcOn: false)` — the raster policy), the
// [i0'] exit matrix + the scene-linear branch matrix, the four gamut
// tables, and the 4096-entry sampled-TRC plane (zero-padded when unused —
// the flat single-buffer discipline, zero function constants).
// ─────────────────────────────────────────────────────────────────────────────

public struct RasterInputUniforms: Sendable {

    /// The packed plane (the ABI).
    public var floats: [SIMD4<Float>]

    // Section sizes (float4 units).
    public static let headFloat4Count = 4
    public static let tsFloat4Count = 3
    public static let jmhParamsFloat4Count = 14
    public static let gamFloat4Count = 3
    public static let matrixFloat4Count = 3
    public static let tableFloat4Count = 91      // 362 floats → 364 → 91
    public static let cuspFloat4Count = 272      // 362×3 → 1088 → 272
    public static let sampledFloat4Count = 1024  // 4096 floats

    public static var float4Count: Int {
        headFloat4Count
            + tsFloat4Count
            + jmhParamsFloat4Count * 2
            + gamFloat4Count
            + matrixFloat4Count * 2
            + tableFloat4Count * 3
            + cuspFloat4Count
            + sampledFloat4Count
    }

    /// The transfer-kind ordinals (the Swift/Metal shared vocabulary —
    /// the RasterTransfer case order minus its associated payloads).
    public enum TransferKind: Int32, Sendable {
        case linear = 0
        case srgbPiecewise = 1
        case gamma = 2
        case iccParametric = 3
        case iccSampled = 4
        case st2084 = 5
        case hlg = 6
        case bt1886 = 7
    }

    /// The head's transfer ordinal + parameters for one description.
    static func transferFace(
        _ transfer: RasterTransfer
    ) -> (kind: TransferKind, gamma: Float,
          paramType: Float, params: [Float], sampled: [Float]) {
        switch transfer {
        case .linear: return (.linear, 2.2, 0, [], [])
        case .srgbPiecewise: return (.srgbPiecewise, 2.2, 0, [], [])
        case .gamma(let g): return (.gamma, Float(g), 0, [], [])
        case .iccParametric(let type, let params):
            let floats = params.map { Float($0) }
            let padded = floats + [Float](repeating: 0, count: max(0, 7 - floats.count))
            return (.iccParametric, 2.2, Float(type), Array(padded.prefix(7)), [])
        case .iccSampled(let table):
            let padded = table + [Float](repeating: 0, count: max(0, 4096 - table.count))
            return (.iccSampled, 2.2, 0, [], Array(padded.prefix(4096)))
        case .st2084: return (.st2084, 2.2, 0, [], [])
        case .hlg: return (.hlg, 2.2, 0, [], [])
        case .bt1886: return (.bt1886, 2.4, 0, [], [])
        }
    }

    /// Pack from the description + the built ACES 2.0 parameter point +
    /// the two branch matrices (Float64-built host side, packed f32).
    ///
    /// - Parameters:
    ///   - description: the source color description.
    ///   - params: `Aces2Reference.params(space:peak:rgcOn:)` at the raster
    ///     policy point (limiting = source-mapped space, rgcOn: false).
    ///   - sceneLinearMatrix: the source→Rec2020 matrix for the ②/①′
    ///     branch (nil for the display branch).
    init(
        description: RasterColorDescription,
        params: Aces2Reference.Params,
        sceneLinearMatrix: DrtMat3?
    ) {
        var f: [SIMD4<Float>] = []
        f.reserveCapacity(Self.float4Count)

        let face = Self.transferFace(description.transfer)
        let sampledCount = face.sampled.count

        // head0 = (peak, refLuminance, transferKind, gammaValue).
        f.append(SIMD4(
            Float(params.peak), Float(Aces2Cam.refLuminance),
            Float(face.kind.rawValue), face.gamma))
        // head1 = (paramType, g, a, b).
        f.append(SIMD4(face.paramType,
                       face.params.count > 0 ? face.params[0] : 0,
                       face.params.count > 1 ? face.params[1] : 0,
                       face.params.count > 2 ? face.params[2] : 0))
        // head2 = (c, d, e, f).
        f.append(SIMD4(face.params.count > 3 ? face.params[3] : 0,
                       face.params.count > 4 ? face.params[4] : 0,
                       face.params.count > 5 ? face.params[5] : 0,
                       face.params.count > 6 ? face.params[6] : 0))
        // head3 = (sampledCount, ·, ·, ·).
        f.append(SIMD4(Float(sampledCount), 0, 0, 0))

        // ts0/ts1/ts2 (ts2.zw = the hue-linearity search range).
        let ts = params.ts
        f.append(SIMD4(Float(ts.n), Float(ts.nR), Float(ts.g), Float(ts.t1)))
        f.append(SIMD4(Float(ts.cT), Float(ts.s2), Float(ts.u2), Float(ts.m2)))
        f.append(SIMD4(
            Float(ts.forwardLimit), Float(ts.logPeak),
            Float(params.hueLinearitySearchRange.0),
            Float(params.hueLinearitySearchRange.1)))

        func packJMh(_ p: Aces2Cam.JMhParams) {
            f.append(SIMD4(Float(p.fLn), Float(p.cz), Float(p.invCz), Float(p.awJ)))
            f.append(SIMD4(Float(p.invAwJ), 0, 0, 0))
            for rows in [p.rgbToCam16C, p.cam16CToRgb,
                         p.coneResponseToAab, p.aabToConeResponse] {
                f.append(SIMD4(Float(rows.r0.x), Float(rows.r0.y), Float(rows.r0.z), 0))
                f.append(SIMD4(Float(rows.r1.x), Float(rows.r1.y), Float(rows.r1.z), 0))
                f.append(SIMD4(Float(rows.r2.x), Float(rows.r2.y), Float(rows.r2.z), 0))
            }
        }
        packJMh(params.inputParams)
        packJMh(params.limitParams)

        // gam0/gam1/gam2.
        f.append(SIMD4(
            Float(params.limitJMax), Float(params.modelGammaInv),
            Float(params.sat), Float(params.satThr)))
        f.append(SIMD4(
            Float(params.compr), Float(params.chromaCompressScale),
            Float(params.midJ), Float(params.focusDist)))
        f.append(SIMD4(
            Float(params.lowerHullGammaInv), Float(params.peak), 0, 0))

        // The exit + branch matrices.
        func packMatrix(_ rows: DrtMat3) {
            f.append(SIMD4(Float(rows.r0.x), Float(rows.r0.y), Float(rows.r0.z), 0))
            f.append(SIMD4(Float(rows.r1.x), Float(rows.r1.y), Float(rows.r1.z), 0))
            f.append(SIMD4(Float(rows.r2.x), Float(rows.r2.y), Float(rows.r2.z), 0))
        }
        packMatrix(Aces2Cam.ap0ToRec2020)
        let scene = sceneLinearMatrix ?? Aces2Cam.ap0ToRec2020 // dead face for the display branch
        packMatrix(scene)

        func packTable(_ table: [Double]) {
            var padded = table.map { Float($0) }
            padded.append(contentsOf: [Float](repeating: 0, count: 364 - padded.count))
            for i in stride(from: 0, to: 364, by: 4) {
                f.append(SIMD4(padded[i], padded[i + 1], padded[i + 2], padded[i + 3]))
            }
        }
        packTable(params.tableReachM)
        packTable(params.tableHues)
        // cusps (362×3 → 1088 floats).
        var flat: [Float] = []
        flat.reserveCapacity(1088)
        for c in params.tableGamutCusps {
            flat.append(Float(c.x)); flat.append(Float(c.y)); flat.append(Float(c.z))
        }
        flat.append(contentsOf: [Float](repeating: 0, count: 1088 - flat.count))
        for i in stride(from: 0, to: 1088, by: 4) {
            f.append(SIMD4(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]))
        }
        packTable(params.tableUpperHullGamma)

        // The sampled TRC plane (zero-padded to the full 4096).
        var sampled = face.sampled
        sampled.append(contentsOf: [Float](repeating: 0, count: 4096 - sampled.count))
        for i in stride(from: 0, to: 4096, by: 4) {
            f.append(SIMD4(sampled[i], sampled[i + 1], sampled[i + 2], sampled[i + 3]))
        }

        precondition(f.count == Self.float4Count,
                     "RasterInputUniforms plane count drifted: \(f.count)")
        self.floats = f
    }
}
