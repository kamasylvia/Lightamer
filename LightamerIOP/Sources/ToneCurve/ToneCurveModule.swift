import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// TONECURVE — the L/a/b curve iop (Phase 3 Plan 03-03-T3, IOP-TONE-03).
//
// Darktable reference: `src/iop/tonecurve.c` (tree dc58cf0ba1) +
// `src/common/curve_tools.c` + `data/kernels/basic.cl:1426-1490`:
//   - params v5      :97-108  three node sets (L/a/b, ≤20 nodes),
//                             types (monotone hermite default), autoscale_ab
//                             (manual/Lab/XYZ/RGB), unbound_ab,
//                             preserve_colors (RGB norm family)
//   - commit_params  :722-841 0x10000 tables ×3, autoscale re-derivations
//                             (XYZ-linked / RGB-linked), 5 extrapolation
//                             fits
//   - process        :411-500 LUT + extrapolation on L, then the
//                             autoscale branch for a/b
//   - kernel         basic.cl tonecurve (same semantics; NEAREST LUT)
//
// LAB DOMAIN: fused Rec2020→Lab→Rec2020 via Common/LabMath.h (Plan 03-03
// Goal) — dt's pixelpipe converts around the IOP_CS_LAB module instead.
//
// RECORDED DIVERGENCES (see also ToneCurveLUT.swift header):
// 1. RGB-linked table + pixel path derive/apply over the WORKING space
//    (linear Rec2020); dt hard-codes ProPhoto (tonecurve.c:471/496). The
//    working-domain decision (Plan 03-03 Goal) makes Rec2020 the
//    semantic home; the LUMINANCE norm uses the Rec2020 Y row.
// 2. LUT values are not integer-quantized and the lookup index ROUNDS to
//    nearest (dt truncates — see ColisaModule header for the boundary
//    rationale); both deviations are ≤1 LUT LSB.
// 3. `tonecurve_preset` (params int, UI-state only in dt) is not ported —
//    no pixel effect.
// 4. CL-vs-CPU threshold: the kernel uses the CL form (x < 1.0 → LUT,
//    else extrapolation — color_conversion.h:77-93); dt's CPU process
//    thresholds at the last-node x instead. Identical for curves whose
//    last node sits at 1.0 (all golden cases; the GUI constrains nodes
//    to [0,1]).
// ─────────────────────────────────────────────────────────────────────────

public enum ToneCurveKernel {
    public static let functionName = "tonecurve_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ToneCurveModule: IOPModule {

    /// dt `dt_iop_tonecurve_node_t` (:76-80).
    public struct Node: Codable, Hashable, Sendable {
        public var x: Float
        public var y: Float
        public init(x: Float, y: Float) {
            self.x = x
            self.y = y
        }
    }

    public struct Params: Codable, Hashable, Sendable {
        /// Node sets for the L, a and b curves (normalized [0,1] box).
        public var curveL: [Node]
        public var curveA: [Node]
        public var curveB: [Node]
        public var typeL: ToneCurveLUT.CurveType
        public var typeA: ToneCurveLUT.CurveType
        public var typeB: ToneCurveLUT.CurveType
        /// dt default: DT_S_SCALE_AUTOMATIC_RGB (:103).
        public var autoscaleAb: ToneCurveLUT.AutoscaleAb
        /// dt default: 1 (:105).
        public var unboundAb: Bool
        /// dt default: DT_RGB_NORM_AVERAGE (:106).
        public var preserveColors: ToneCurveLUT.RGBNorm

        public init(
            curveL: [Node] = ToneCurveModule.defaultLNodes,
            curveA: [Node] = ToneCurveModule.defaultAbNodes,
            curveB: [Node] = ToneCurveModule.defaultAbNodes,
            typeL: ToneCurveLUT.CurveType = .monotoneHermite,
            typeA: ToneCurveLUT.CurveType = .monotoneHermite,
            typeB: ToneCurveLUT.CurveType = .monotoneHermite,
            autoscaleAb: ToneCurveLUT.AutoscaleAb = .rgbLinked,
            unboundAb: Bool = true,
            preserveColors: ToneCurveLUT.RGBNorm = .average
        ) {
            self.curveL = curveL
            self.curveA = curveA
            self.curveB = curveB
            self.typeL = typeL
            self.typeA = typeA
            self.typeB = typeB
            self.autoscaleAb = autoscaleAb
            self.unboundAb = unboundAb
            self.preserveColors = preserveColors
        }
    }

    /// dt init() defaults (tonecurve.c:919-931): L has 2 nodes, a/b have 3.
    public static let defaultLNodes: [Node] = [Node(x: 0, y: 0), Node(x: 1, y: 1)]
    public static let defaultAbNodes: [Node] = [
        Node(x: 0, y: 0), Node(x: 0.5, y: 0.5), Node(x: 1, y: 1),
    ]

    public static let opName = "tonecurve"
    public static let iopOrder: Float = 48.0
    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: Buffer layout (single MTLBuffer, 16-byte-aligned sections)

    static let sectionFloats = ToneCurveLUT.resolution * MemoryLayout<Float>.size // 262144
    static let tableLOffset = 0
    static let tableAOffset = sectionFloats
    static let tableBOffset = 2 * sectionFloats
    static let coeffsOffset = 3 * sectionFloats // 15 floats (5 fits × 3) padded to 64
    static let coeffsLength = 64
    static let uniformOffset = coeffsOffset + coeffsLength
    static let uniformLength = 16

    struct ToneCurveUniforms {
        var autoscaleAb: Int32
        var unboundAb: Int32
        var preserveColors: Int32
        var lowApproximation: Float

        init(autoscaleAb: Int32, unboundAb: Int32, preserveColors: Int32, lowApproximation: Float) {
            self.autoscaleAb = autoscaleAb
            self.unboundAb = unboundAb
            self.preserveColors = preserveColors
            self.lowApproximation = lowApproximation
        }
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }

        let tables = ToneCurveLUT.commit(
            nodesL: params.curveL.map { (Double($0.x), Double($0.y)) },
            nodesA: params.curveA.map { (Double($0.x), Double($0.y)) },
            nodesB: params.curveB.map { (Double($0.x), Double($0.y)) },
            typeL: params.typeL,
            typeA: params.typeA,
            typeB: params.typeB,
            autoscaleAb: params.autoscaleAb
        )

        if pieceBuffer == nil || committed != params {
            var uniforms = ToneCurveUniforms(
                autoscaleAb: Int32(params.autoscaleAb.rawValue),
                unboundAb: params.unboundAb ? 1 : 0,
                preserveColors: Int32(params.preserveColors.rawValue),
                lowApproximation: Float(tables.lowApproximation)
            )
            let length = Self.uniformOffset + Self.uniformLength
            if pieceBuffer == nil {
                pieceBuffer = resolvedDevice.makeBuffer(
                    length: length, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                let contents = buffer.contents()
                for (table, offset) in [
                    (tables.tableL, Self.tableLOffset),
                    (tables.tableA, Self.tableAOffset),
                    (tables.tableB, Self.tableBOffset),
                ] {
                    var floats = table.map { Float($0) }
                    floats.withUnsafeBytes {
                        contents.advanced(by: offset)
                            .copyMemory(from: $0.baseAddress!, byteCount: Self.sectionFloats)
                    }
                }
                var coeffs: [Float] = []
                for c in [tables.coeffsL, tables.coeffsARight, tables.coeffsALeft,
                          tables.coeffsBRight, tables.coeffsBLeft] {
                    coeffs.append(contentsOf: c.map { Float($0) })
                }
                coeffs.withUnsafeBytes {
                    contents.advanced(by: Self.coeffsOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: 15 * 4)
                }
                withUnsafeBytes(of: &uniforms) {
                    contents.advanced(by: Self.uniformOffset)
                        .copyMemory(from: $0.baseAddress!, byteCount: Self.uniformLength)
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        let buffer = piece.data
        try await metal.dispatch2DTexture(
            functionName: ToneCurveKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            if let buffer {
                encoder.setBuffer(buffer, offset: Self.tableLOffset, index: 0)
                encoder.setBuffer(buffer, offset: Self.tableAOffset, index: 1)
                encoder.setBuffer(buffer, offset: Self.tableBOffset, index: 2)
                encoder.setBuffer(buffer, offset: Self.coeffsOffset, index: 3)
                encoder.setBuffer(buffer, offset: Self.uniformOffset, index: 4)
            }
        }
    }
}
