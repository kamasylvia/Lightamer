import Foundation
import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// DehazeModule — Plan 08-5 T1, IOP-FX-04 (op "hazeremoval", v50 slot 14.0).
//
// Darktable reference (tree dc58cf0ba1): `src/iop/hazeremoval.c` +
// `data/kernels/hazeremoval.cl:22-163` (the four sliding box min/max
// kernels + the transition map + the restore — verbatim line ports).
//
//   - params :66-67,576  strength(−1..1, 0.2) / distance(0..1, 0.2) /
//                        adaptive(TRUE). `compatibility_mode` NOT ported
//                        (a quickselect pivot-order artifact, zero math
//                        effect — D-08-5-T1-1).
//   - windows :576-583   w1 = 2+⌈4·wscale⌉, w2 = 3+⌈6·wscale⌉, wscale =
//                        adaptive ? roi.scale/iscale : 1 (the reference
//                        function is the ONE source of truth).
//   - ambient :~400-544  A0 + distance_max via the dark-channel-prior
//                        order statistics (0.95/0.95 quantiles) — the CPU
//                        float64 reference routine IS the production
//                        routine (one implementation, golden-authority
//                        shape), fed the DECIMATED statistics grid.
//   - guided filter      dt's guided_filter(w2) is REPLACED by the box
//                        mean (w2, two separable passes) — the FROZEN
//                        planner ruling (R5 消解); visual delta is a
//                        Manual-Only item, the full guided port is the
//                        Reversibility seam.
//   - A0 reuse           the dt gui_data preview/full sync pit
//                        (:595-645) answered the Lightamer way: the
//                        ambient stats come from a FIXED long-edge-1024
//                        decimated grid (scale-consistent + bounded
//                        readback), cached on the module and validated by
//                        the grid-content hash — an upstream or content
//                        change rehashes the grid (recompute), the
//                        module's OWN param changes (the strength slider
//                        drag, dt's motivating use case) keep the hash
//                        and REUSE. Readback = same-CB drain (L014);
//                        every dispatch rides makeEncoder (L031).
//   - tiling             dt's flags() carries NO ALLOW_TILING (the whole-
//                        image ambient statistics are the reason) — the
//                        module declares .supportsBlending only, so the
//                        whole-plane execution contract holds.
//
// SEED: DISABLED (dt defaults strength 0.2/distance 0.2 are not pixel
// identity — the creative-module disposition; the 08-5 panel drives this
// instance). strength == 0 ⇒ t ≡ 1 ⇒ the routed-blit value identity.
// ─────────────────────────────────────────────────────────────────────────

public enum DehazeKernel {
    public static let ambientGridFunction = "dehaze_ambient_grid"
    public static let boxMinXFunction = "dehaze_box_min_x"
    public static let boxMinYFunction = "dehaze_box_min_y"
    public static let boxMaxXFunction = "dehaze_box_max_x"
    public static let boxMaxYFunction = "dehaze_box_max_y"
    public static let transisionMapFunction = "dehaze_transision_map"
    public static let boxMeanXFunction = "dehaze_box_mean_x"
    public static let boxMeanYFunction = "dehaze_box_mean_y"
    public static let applyFunction = "dehaze_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)

    /// All nine kernels (the Registry PSO pre-warm list).
    public static let allFunctionNames = [
        ambientGridFunction, boxMinXFunction, boxMinYFunction,
        boxMaxXFunction, boxMaxYFunction, transisionMapFunction,
        boxMeanXFunction, boxMeanYFunction, applyFunction,
    ]
}

public final class DehazeModule: IOPModule {

    /// dt `dt_iop_hazeremoval_params_t` (:64-70) minus compatibility_mode
    /// (D-08-5-T1-1).
    public struct Params: Codable, Hashable, Sendable {
        /// dt `strength` ∈ [−1, 1] $DEFAULT 0.2 — the haze-removal strength
        /// (1 = the full physical inversion).
        public var strength: Float
        /// dt `distance` ∈ [0, 1] $DEFAULT 0.2 — the maximal camera
        /// distance to remove haze for (drives t_min through distance_max).
        public var distance: Float
        /// dt `adaptive` $DEFAULT TRUE — the box windows scale with the
        /// pipe resolution ratio.
        public var adaptive: Bool

        public init(strength: Float = 0.2, distance: Float = 0.2, adaptive: Bool = true) {
            self.strength = strength
            self.distance = distance
            self.adaptive = adaptive
        }
    }

    public static let opName = "hazeremoval"

    /// Darktable v50 order slot 14.0 (V50Order verbatim, iop_order.c) — the
    /// scene-referred head, before exposure; < the 70.0 terminal floor →
    /// layer-mask eligible.
    public static let iopOrder: Float = 14.0

    /// dt flags() = INCLUDE_IN_STYLES | SUPPORTS_BLENDING — deliberately NO
    /// tiling flag (the whole-image ambient statistics); see the header.
    public static let flags: IOPFlags = [.supportsBlending]
    public static let defaultColorspace: IOPColorspace = .RGB

    // MSL mirrors (scalars only — the float3-in-constant-buffer padding
    // trap is sidestepped with individual floats, the lut3d lesson).

    struct GridUniforms {
        var blockX: UInt32
        var blockY: UInt32
    }

    struct BoxUniforms {
        var width: UInt32
        var height: UInt32
        var w: UInt32
    }

    struct TransisionUniforms {
        var width: UInt32
        var height: UInt32
        var strength: Float
        var a0r: Float
        var a0g: Float
        var a0b: Float
    }

    struct ApplyUniforms {
        var width: UInt32
        var height: UInt32
        var tMin: Float
        var a0r: Float
        var a0g: Float
        var a0b: Float
    }

    /// The cached ambient statistics + the grid-content hash that validates
    /// them (the dt gui_data cache, content-hash keyed).
    private struct AmbientCache {
        var ambient: DehazeReference.Ambient
        var inputHash: UInt64
        var gridW: Int
        var gridH: Int
    }

    private var ambientCache: AmbientCache?
    /// Test seam: how many times the ambient statistics were COMPUTED (the
    /// reuse contract: an own-param re-run must NOT bump this; a content
    /// change MUST).
    var ambientComputations = 0
    /// Test seam: the last computed/reused ambient (the parity tests pin
    /// the module's statistics against the reference routine's).
    var lastAmbientForTesting: DehazeReference.Ambient? { ambientCache?.ambient }
    /// Test seams (L020 — the chain-intermediate shape pins; the bloom
    /// scratch-seam shape). The box stages ping-pong scratchA/scratchB.
    var transitionTextureForTesting: (any MTLTexture)? { transitionTexture }
    var scratchAForTesting: (any MTLTexture)? { scratchA }
    var scratchBForTesting: (any MTLTexture)? { scratchB }

    // The single-channel scratch planes (per-size cached, .shared — the
    // bloom scratch shape, L018).
    private var transitionTexture: (any MTLTexture)?
    private var scratchA: (any MTLTexture)?
    private var scratchB: (any MTLTexture)?
    private var ambientGridTexture: (any MTLTexture)?
    private var scratchW = 0
    private var scratchH = 0

    private var committed: Params?

    public init() {}

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committed = params
        piece.data = nil
    }

    // MARK: - Neutral predicate

    /// strength 0 ⇒ t ≡ 1 ⇒ out = (in−A0)/1 + A0 ≈ in — NOT bit-identical
    /// through the divide form, so the neutral face takes the routed blit
    /// (the vignette shape). `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        p.strength == 0
    }

    // MARK: - scratch

    private func makeTexture(
        _ device: any MTLDevice, width: Int, height: Int, rgba: Bool
    ) -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: rgba ? .rgba32Float : .r32Float,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)!
    }

    private func ensureScratch(_ device: any MTLDevice, width: Int, height: Int) {
        guard width != scratchW || height != scratchH else { return }
        let (gridW, gridH, _, _) = DehazeReference.ambientGridDimensions(
            width: width, height: height)
        transitionTexture = makeTexture(device, width: width, height: height, rgba: false)
        scratchA = makeTexture(device, width: width, height: height, rgba: false)
        scratchB = makeTexture(device, width: width, height: height, rgba: false)
        ambientGridTexture = makeTexture(device, width: gridW, height: gridH, rgba: true)
        scratchW = width
        scratchH = height
        // A size change voids the cached grid texture's contents mapping —
        // the CONTENT hash below still guards the stats themselves.
    }

    // MARK: - process

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let params = committed else {
            throw MetalError.psoCreationFailed(DehazeKernel.applyFunction, nil)
        }
        if isNeutral(params) {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let width = input.width
        let height = input.height
        ensureScratch(metal.device, width: width, height: height)
        guard let transition = transitionTexture,
              let scratchA = scratchA, let scratchB = scratchB,
              let ambientGrid = ambientGridTexture else {
            throw MetalError.psoCreationFailed(DehazeKernel.applyFunction, nil)
        }

        // ── the windows (hazeremoval.c:576-583, reference = one truth) ──
        let windows = DehazeReference.windowSizes(
            adaptive: params.adaptive,
            roiScale: Double(roiIn.scale),
            iscale: Double(max(piece.iscale, 1e-9)))

        // ── the ambient statistics (decimated grid + content hash) ──────
        let (gridW, gridH, blockW, blockH) = DehazeReference.ambientGridDimensions(
            width: width, height: height)
        do {
            var uniforms = GridUniforms(blockX: UInt32(blockW), blockY: UInt32(blockH))
            guard let buffer = metal.device.makeBuffer(
                bytes: &uniforms, length: MemoryLayout<GridUniforms>.stride,
                options: .storageModeShared)
            else { throw MetalError.deviceUnavailable }
            let session = try await metal.makeEncoder(
                functionName: DehazeKernel.ambientGridFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(ambientGrid, index: 1)
            session.encoder.setBuffer(buffer, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: gridW, height: gridH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
            await session.commandBuffer.completed() // L014 same-CB drain
        }
        var grid = [Float](repeating: 0, count: gridW * gridH * 4)
        grid.withUnsafeMutableBytes {
            ambientGrid.getBytes(
                $0.baseAddress!, bytesPerRow: gridW * 16,
                from: MTLRegionMake2D(0, 0, gridW, gridH), mipmapLevel: 0)
        }
        // The content hash: grid float bits ⊕ dims (L013 — StableHash is
        // the only legal generator). Computed once, used by both cache legs.
        let inputHash = hashGrid(grid, gridW: gridW, gridH: gridH)

        let ambient: DehazeReference.Ambient
        if let cached = ambientCache,
           cached.inputHash == inputHash,
           cached.gridW == gridW, cached.gridH == gridH {
            ambient = cached.ambient // REUSE (own-param changes ride here)
        } else {
            let w1Grid = max(1, Int(
                (Double(windows.w1) * Double(gridW) / Double(max(width, 1))).rounded()))
            let doubles = grid.map { Double($0) }
            ambient = DehazeReference.ambientLight(
                doubles, planeW: gridW, planeH: gridH, w1: w1Grid)
            ambientCache = AmbientCache(
                ambient: ambient, inputHash: inputHash,
                gridW: gridW, gridH: gridH)
            ambientComputations += 1
        }

        let tMin = Float(min(
            max(Foundation.exp(-Double(params.distance) * ambient.distanceMax),
                1.0 / 1024.0), 1.0))

        // ── the GPU chain (dt process_cl order) ──────────────────────────
        // ① transition map (t = 1 − min(p/A0)·strength).
        do {
            var uniforms = TransisionUniforms(
                width: UInt32(width), height: UInt32(height),
                strength: params.strength,
                a0r: Float(ambient.a0.x), a0g: Float(ambient.a0.y),
                a0b: Float(ambient.a0.z))
            guard let buffer = metal.device.makeBuffer(
                bytes: &uniforms, length: MemoryLayout<TransisionUniforms>.stride,
                options: .storageModeShared)
            else { throw MetalError.deviceUnavailable }
            let session = try await metal.makeEncoder(
                functionName: DehazeKernel.transisionMapFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(transition, index: 1)
            session.encoder.setBuffer(buffer, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
        }
        // ② box MAX w1 (the `_transition_map` tail), separable.
        try await dispatchBox(
            DehazeKernel.boxMaxXFunction, from: transition, to: scratchA,
            width: width, height: height, w: windows.w1, metal: metal)
        try await dispatchBox(
            DehazeKernel.boxMaxYFunction, from: scratchA, to: scratchB,
            width: width, height: height, w: windows.w1, metal: metal)
        // ③ box MIN w1 (the refine).
        try await dispatchBox(
            DehazeKernel.boxMinXFunction, from: scratchB, to: scratchA,
            width: width, height: height, w: windows.w1, metal: metal)
        try await dispatchBox(
            DehazeKernel.boxMinYFunction, from: scratchA, to: scratchB,
            width: width, height: height, w: windows.w1, metal: metal)
        // ④ the guided-filter replacement: box mean w2, two passes (the
        // mean kernels are 2D — the dt min/max kernels are the 1D
        // row/column launches, the mean pair launches a 2D grid).
        try await dispatchBox2D(
            DehazeKernel.boxMeanXFunction, from: scratchB, to: scratchA,
            width: width, height: height, w: windows.w2, metal: metal)
        try await dispatchBox2D(
            DehazeKernel.boxMeanYFunction, from: scratchA, to: scratchB,
            width: width, height: height, w: windows.w2, metal: metal)
        // ⑤ the restore.
        do {
            var uniforms = ApplyUniforms(
                width: UInt32(width), height: UInt32(height),
                tMin: tMin,
                a0r: Float(ambient.a0.x), a0g: Float(ambient.a0.y),
                a0b: Float(ambient.a0.z))
            guard let buffer = metal.device.makeBuffer(
                bytes: &uniforms, length: MemoryLayout<ApplyUniforms>.stride,
                options: .storageModeShared)
            else { throw MetalError.deviceUnavailable }
            let session = try await metal.makeEncoder(
                functionName: DehazeKernel.applyFunction)
            session.encoder.setTexture(input, index: 0)
            session.encoder.setTexture(scratchB, index: 1)
            session.encoder.setTexture(output, index: 2)
            session.encoder.setBuffer(buffer, offset: 0, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding() // L008
            session.commandBuffer.commit()
        }
    }

    /// The box-kernel dispatch shape (1D row/column grid, the .cl launch
    /// geometry). L031: the encoder comes from makeEncoder — the routed
    /// acquisition point.
    private func dispatchBox(
        _ functionName: String,
        from: any MTLTexture, to: any MTLTexture,
        width: Int, height: Int, w: Int, metal: MetalContext
    ) async throws {
        var uniforms = BoxUniforms(
            width: UInt32(width), height: UInt32(height), w: UInt32(w))
        guard let buffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<BoxUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        // The dt launch: the X kernels dispatch HEIGHT rows, the Y kernels
        // dispatch WIDTH columns (get_global_id(0) = y / x respectively).
        let isColumnKernel = functionName == DehazeKernel.boxMinYFunction
            || functionName == DehazeKernel.boxMaxYFunction
        let lines = isColumnKernel ? width : height
        let session = try await metal.makeEncoder(functionName: functionName)
        session.encoder.setTexture(from, index: 0)
        session.encoder.setTexture(to, index: 1)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: lines, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        session.encoder.endEncoding() // L008
        session.commandBuffer.commit()
    }

    /// The 2D-kernel dispatch shape (the mean pair — a full 2D grid).
    private func dispatchBox2D(
        _ functionName: String,
        from: any MTLTexture, to: any MTLTexture,
        width: Int, height: Int, w: Int, metal: MetalContext
    ) async throws {
        var uniforms = BoxUniforms(
            width: UInt32(width), height: UInt32(height), w: UInt32(w))
        guard let buffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<BoxUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        let session = try await metal.makeEncoder(functionName: functionName)
        session.encoder.setTexture(from, index: 0)
        session.encoder.setTexture(to, index: 1)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding() // L008
        session.commandBuffer.commit()
    }

    /// The grid-content hash (float bits ⊕ dims) — StableHash only (L013).
    private func hashGrid(_ grid: [Float], gridW: Int, gridH: Int) -> UInt64 {
        var data = Data(capacity: grid.count * 4 + 16)
        grid.withUnsafeBytes { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(gridW).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(gridH).littleEndian) { data.append(contentsOf: $0) }
        return StableHash.hash(data)
    }

    /// Whole-window routed blit (the strength-0 value identity; the
    /// vignette shape). L031: the command buffer comes from
    /// makeRoutedCommandBuffer() — the ONE queue-acquisition point.
    private func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008
        commandBuffer.commit()
    }
}
