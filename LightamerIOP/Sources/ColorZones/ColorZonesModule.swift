import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// ColorZonesModule (Plan 05-04-T2, IOP-COLOR-05) — dt's `colorzones`
// (v50 60.0, Lab three-curve L/C/h select + 3×0x10000 LUT, SMOOTH/v3
// process path), transliterated from
//   - src/iop/colorzones.c (params v5 layout :66-83 = channel int +
//     3×20 nodes + 3 num_nodes + 3 types + strength float + mode int +
//     splines_version int = 520B; commit V2 branch :2874-2892 — nodes
//     verbatim + strength-folded y, V2-nonperiodic for select L/C,
//     V2-PERIODIC for select h; process_v3 :526-570; lookup :413-418
//     LERP between adjacent entries)
//   - data/kernels/basic.cl:3121-3185 `colorzones_v3` (same math)
//   - data/kernels/color_conversion.h:70-75 `lookup` (NEAREST truncation)
// (tree dc58cf0ba1).
//
// LAB DOMAIN (03-03 Goal pattern): fused Rec2020→Lab→Rec2020 via
// Common/LabMath.h in ONE kernel.
//
// LOOKUP DIVERGENCE (recorded, ParityGate envelope covers): dt's CPU leg
// LERPs between adjacent LUT entries (colorzones.c:413-418) while dt's CL
// leg — and this kernel — use NEAREST truncation
// (color_conversion.h:70-75 `xi = (int)(x·0x10000)`). Both dt legs agree
// except at sub-LSB interpolation curvature — ≤ ~6e-6 abs on smooth
// curves; the dual gate's 1e-4 envelope absorbs the systematic leg gap
// with 2 orders of margin. CPU-vs-GPU leg choice: FOLLOWS THE CL LEG
// (GPU output must match the module's own GPU path, not dt's CPU leg).
//
// SMOOTH/STRONG (recorded): v1 legacy (STRONG/diffuse path, process_v1
// + LCh-domain math) is NOT ported — SMOOTH (v3) is dt's default
// (DT_IOP_COLORZONES_MODE_SMOOTH) and the only path the CL kernel
// implements. Params.mode is carried for sidecar fidelity but the kernel
// always runs the v3 math; DECISIONS D-05-04-T2-2 records the parity
// scope (strong parity = out of scope, noted for v2).
//
// SPLINES VERSION (recorded): V2 only. V1's wrap-node commit is not
// ported (dt itself writes V2 for all new edits;
// splines_version defaults to V2 in init). See ColorZonesLUT header for
// the V2-vs-V1 reuse verdict.
//
// DEFAULTS DIVERGENCE (recorded): default strength = 0 AND default curves
// = identity (2 nodes (0.25,0.5)-(0.75,0.5), select h per
// _reset_parameters/_reset_nodes) — dt's $DEFAULT curves are flat-0.5
// (no-op through the v3 math: Lm/hm = 0, Cm = 2·0.5 = 1) so identity
// holds either way; the (0.25..0.75) node placement keeps the GUI curve
// editor's default view meaningful. Seed ENABLED-neutral.
//
// ROI (L020/L021): pointwise identity — dscIn already carries the entry
// scaling, no re-multiplication by scale anywhere; tileHalo = 0.
// ─────────────────────────────────────────────────────────────────────────

public enum ColorZonesKernel {
    public static let functionName = "colorzones_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ColorZonesModule: IOPModule {

    /// dt `dt_iop_colorzones_node_t` (colorzones.c:66-70).
    public struct Node: Codable, Hashable, Sendable {
        public var x: Float
        public var y: Float
        public init(x: Float, y: Float) {
            self.x = x
            self.y = y
        }
    }

    /// dt `dt_iop_colorzones_params_t` v5 shape (colorzones.c:72-83).
    /// Node capacity is dynamic (≤20 enforced at commit); the fixed
    /// 3×20 C array is a serialization detail, not carried here.
    public struct Params: Codable, Hashable, Sendable {
        public var channel: ColorZonesLUT.SelectChannel
        public var curveL: [Node]
        public var curveC: [Node]
        public var curveH: [Node]
        public var typeL: ToneCurveLUT.CurveType
        public var typeC: ToneCurveLUT.CurveType
        public var typeH: ToneCurveLUT.CurveType
        public var strength: Float
        public var mode: ColorZonesLUT.ProcessMode

        /// dt `_reset_nodes` identity placement (colorzones.c:814-827):
        /// touch_edges (select L/C) → k/(n−1); hue → (k+0.5)/n, y = 0.5.
        public static func identityNodes(hueStyle: Bool) -> [Node] {
            if hueStyle {
                return [Node(x: 0.25, y: 0.5), Node(x: 0.75, y: 0.5)]
            }
            return [Node(x: 0, y: 0.5), Node(x: 1, y: 0.5)]
        }

        public init(
            channel: ColorZonesLUT.SelectChannel = .hue,
            curveL: [Node] = identityNodes(hueStyle: false),
            curveC: [Node] = identityNodes(hueStyle: false),
            curveH: [Node] = identityNodes(hueStyle: true),
            typeL: ToneCurveLUT.CurveType = .catmullRom,
            typeC: ToneCurveLUT.CurveType = .catmullRom,
            typeH: ToneCurveLUT.CurveType = .catmullRom,
            strength: Float = 0,
            mode: ColorZonesLUT.ProcessMode = .smooth
        ) {
            self.channel = channel
            self.curveL = curveL
            self.curveC = curveC
            self.curveH = curveH
            self.typeL = typeL
            self.typeC = typeC
            self.typeH = typeH
            self.strength = strength
            self.mode = mode
        }
    }

    public static let opName = "colorzones"

    /// Darktable v50 order slot 60.0.
    public static let iopOrder: Float = 60.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    // MARK: Buffer layout (single MTLBuffer)

    public static let sectionBytes = ColorZonesLUT.resolution * MemoryLayout<Float>.size
    public static let tableLOffset = 0
    public static let tableCOffset = sectionBytes
    public static let tableHOffset = 2 * sectionBytes
    public static let uniformOffset = 3 * sectionBytes
    public static let uniformLength = 16

    struct ColorZonesUniforms {
        var channel: Int32
        var pad0: Int32
        var pad1: Float
        var pad2: Float

        init(channel: Int32) {
            self.channel = channel
            self.pad0 = 0
            self.pad1 = 0
            self.pad2 = 0
        }
    }

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt commit V2 branch (:2874-2892): strength-folded nodes →
    /// 3×0x10000 tables (periodic only for select h) → single buffer.
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolvedDevice = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }

        let periodicH = params.channel == .hue
        let tableL = ColorZonesLUT.buildTable(
            nodes: params.curveL.map { (Double($0.x), Double($0.y)) },
            type: params.typeL, strength: Double(params.strength),
            periodic: false)
        let tableC = ColorZonesLUT.buildTable(
            nodes: params.curveC.map { (Double($0.x), Double($0.y)) },
            type: params.typeC, strength: Double(params.strength),
            periodic: false)
        let tableH = ColorZonesLUT.buildTable(
            nodes: params.curveH.map { (Double($0.x), Double($0.y)) },
            type: params.typeH, strength: Double(params.strength),
            periodic: periodicH)

        if pieceBuffer == nil || committed != params {
            var uniforms = ColorZonesUniforms(channel: Int32(params.channel.rawValue))
            let length = Self.uniformOffset + Self.uniformLength
            if pieceBuffer == nil {
                pieceBuffer = resolvedDevice.makeBuffer(
                    length: length, options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                let contents = buffer.contents()
                for (table, offset) in [
                    (tableL, Self.tableLOffset),
                    (tableC, Self.tableCOffset),
                    (tableH, Self.tableHOffset),
                ] {
                    var floats = table.map { Float($0) }
                    floats.withUnsafeBytes {
                        contents.advanced(by: offset)
                            .copyMemory(from: $0.baseAddress!, byteCount: Self.sectionBytes)
                    }
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

    // MARK: - ROI (L020/L021 — pointwise identity)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    // MARK: - Process (single dispatch)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let buffer = piece.data else { return }
        try await metal.dispatch2DTexture(
            functionName: ColorZonesKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: Self.tableLOffset, index: 0)
            encoder.setBuffer(buffer, offset: Self.tableCOffset, index: 1)
            encoder.setBuffer(buffer, offset: Self.tableHOffset, index: 2)
            encoder.setBuffer(buffer, offset: Self.uniformOffset, index: 3)
        }
    }

    // MARK: - CPU reference (Double mirror for parity tests)

    /// dt process_v3 (:526-570) in Double on Lab values. `tables` are the
    /// committed Double LUTs (0x10000 entries each); lookup is dt's CPU
    /// LERP between adjacent entries (:413-418). `selectChannel` mirrors
    /// the committed channel.
    public static func reference(
        lab: SIMD3<Double>,
        tables: (l: [Double], c: [Double], h: [Double]),
        selectChannel: ColorZonesLUT.SelectChannel
    ) -> SIMD3<Double> {
        let a = lab.y, b = lab.z
        // dt atan2 hue normalization (process_v3 :541): fmod into [0,1).
        var h = (atan2(b, a) + 2.0 * Double.pi).truncatingRemainder(dividingBy: 2.0 * Double.pi)
        h /= 2.0 * Double.pi
        let c = (b * b + a * a).squareRoot()
        let select: Double
        var blend = 0.0
        switch selectChannel {
        case .lightness:
            select = min(1.0, lab.x / 100.0)
        case .chroma:
            select = min(1.0, c / 128.0)
        case .hue:
            select = h
            blend = (1.0 - c / 128.0) * (1.0 - c / 128.0)
        }
        let lm = (blend * 0.5 + (1.0 - blend) * lookupLERP(tables.l, select)) - 0.5
        let hm = (blend * 0.5 + (1.0 - blend) * lookupLERP(tables.h, select)) - 0.5
        blend *= blend
        let cm = 2.0 * lookupLERP(tables.c, select)
        let l = lab.x * pow(2.0, 4.0 * lm)
        let angle = 2.0 * Double.pi * (h + hm)
        return SIMD3(l, cos(angle) * cm * c, sin(angle) * cm * c)
    }

    /// dt CPU `lookup` (:413-418): LERP between adjacent LUT entries
    /// (NOT the CL leg's truncation — header divergence note).
    public static func lookupLERP(_ lut: [Double], _ x: Double) -> Double {
        let scaled = Double(ColorZonesLUT.resolution) * x
        let bin0 = min(max(Int(scaled), 0), ColorZonesLUT.resolution - 1)
        let bin1 = min(max(Int(scaled) + 1, 0), ColorZonesLUT.resolution - 1)
        let f = scaled - Double(bin0)
        return lut[bin1] * f + lut[bin0] * (1.0 - f)
    }

    /// dt CL `lookup` (color_conversion.h:70-75): NEAREST truncation —
    /// the GPU leg this module's kernel follows.
    public static func lookupNearest(_ lut: [Double], _ x: Double) -> Double {
        let xi = min(max(Int(x * Double(ColorZonesLUT.resolution)), 0), ColorZonesLUT.resolution - 1)
        return lut[xi]
    }
}
