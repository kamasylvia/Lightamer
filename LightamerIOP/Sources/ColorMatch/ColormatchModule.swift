import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// ColormatchModule (Plan M5-1-01 T5, KD-5; OQ-M5-1-3/OQ-M5-1-7) — the
// `colormatch` op: the TRACK color-transfer linear arm (S1 Gaussian OT /
// S3 Reinhard solutions from LightamerCore's ColorMatchSolver), v50 slot
// 36.5 (LIGHTAMER-NATIVE row — sits between lut3d 36.0 and the dt-verbatim
// colortransfer 37.0; the creative band, well below the 70.0 layer floor).
//
// STRUCTURE: Lut3dModule 孪生 (flags [.supportsBlending, .allowTiling] —
// the grade-layer masking comes free through the existing blendop chain,
// OQ-M5-1-7; defaultColorspace .RGB; pointwise ROI).
//
// PARAMS (the linear arm's direct storage, OQ-M5-1-3): solver + the solved
// Oklab matrix/offset + strength + the two stats hashes + the effective
// solver (the R1 fallback diagnostic). ZERO sidecar schema change — the
// params ride the registry/ModuleInstance paramsData channel.
//
// NIL ENCODING (checker 回注 E2, 2026-10-09): the three optionals encode
// EXPLICIT null (NOT encodeIfPresent absence) — the IopCatalog reflection
// guard compares the catalog key set against the DEFAULT-ENCODED key set,
// and the MCP apply_params path rejects unknown keys: with explicit nulls
// the catalog keys == the module keys closed under every attach shape.
// Decode stays tolerant (missing/null keys decode nil; an unknown solver
// rawValue degrades to the default — never a throw into the sidecar
// loader). The default Params() encoding is the BYTE identity core
// (strength 0) — the hash-zero-drift专测 pins the exact bytes.
//
// IDENTITY (L031 red line): `strength == 0` OR a missing stats-hash pair
// (the unsolved state) → `makeRoutedCommandBuffer()` blit identity —
// cache-neutral, exposure-0EV style, the lut3d nil-name precedent. The
// kernel dispatches ONLY in the non-identity state.
// ─────────────────────────────────────────────────────────────────────────────

public enum ColormatchKernel {
    /// MSL function name (`ColorMatchKernels.metal`, Plan M5-1-01 T6).
    public static let linear = "colormatch_linear"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class ColormatchModule: IOPModule {

    /// The linear-arm params (OQ-M5-1-3). `strength` defaults to 0 — the
    /// BYTE identity core (a fresh instance renders nothing).
    public struct Params: Codable, Hashable, Sendable {
        /// The user-selected solver (metadata for the re-solve face; the
        /// RENDER is driven by matrix/offset/strength alone).
        public var solver: ColorMatchSolverKind
        /// Row-major 3×3 Oklab-domain map (the solved Float32 storage).
        public var matrix: [Float]
        /// The Oklab-domain offset c = μt − M·μs.
        public var offset: [Float]
        /// α ∈ [0,1]; 0 = identity (the default — the addable-placeholder
        /// semantics until the M5-1-02 panel).
        public var strength: Float
        /// The stats identities behind the solve (L013 decimal Strings).
        /// nil = unsolved. EXPLICIT-null encoded (see the header note).
        public var sourceStatsHash: String?
        public var referenceStatsHash: String?
        /// The R1 fallback diagnostic (nil = no fallback recorded; equals
        /// `solver` byte-for-byte semantics on a clean solve).
        public var effectiveSolver: ColorMatchSolverKind?

        public init(
            solver: ColorMatchSolverKind = .gaussianOT,
            matrix: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1],
            offset: [Float] = [0, 0, 0],
            strength: Float = 0,
            sourceStatsHash: String? = nil,
            referenceStatsHash: String? = nil,
            effectiveSolver: ColorMatchSolverKind? = nil
        ) {
            self.solver = solver
            self.matrix = matrix
            self.offset = offset
            self.strength = strength
            self.sourceStatsHash = sourceStatsHash
            self.referenceStatsHash = referenceStatsHash
            self.effectiveSolver = effectiveSolver
        }

        private enum CodingKeys: String, CodingKey {
            case solver, matrix, offset, strength
            case sourceStatsHash, referenceStatsHash, effectiveSolver
        }

        /// EXPLICIT-null encode (checker E2): every key encodes EVERY time —
        /// nil as JSON null — so the encoded default key set is closed and
        /// the IopCatalog guard holds.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(solver, forKey: .solver)
            try c.encode(matrix, forKey: .matrix)
            try c.encode(offset, forKey: .offset)
            try c.encode(strength, forKey: .strength)
            try c.encode(sourceStatsHash, forKey: .sourceStatsHash)
            try c.encode(referenceStatsHash, forKey: .referenceStatsHash)
            try c.encode(effectiveSolver, forKey: .effectiveSolver)
        }

        /// Tolerant decode: missing/null keys → the defaults; an unknown
        /// solver rawValue degrades to `.gaussianOT` (the Lut3dModule
        /// inputEncoding try? pattern — never a throw into the loader).
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            solver = (try? c.decodeIfPresent(ColorMatchSolverKind.self, forKey: .solver))
                ?? nil ?? .gaussianOT
            matrix = try c.decodeIfPresent([Float].self, forKey: .matrix)
                ?? [1, 0, 0, 0, 1, 0, 0, 0, 1]
            offset = try c.decodeIfPresent([Float].self, forKey: .offset) ?? [0, 0, 0]
            strength = try c.decodeIfPresent(Float.self, forKey: .strength) ?? 0
            sourceStatsHash = try? c.decodeIfPresent(String.self, forKey: .sourceStatsHash)
            referenceStatsHash = try? c.decodeIfPresent(String.self, forKey: .referenceStatsHash)
            effectiveSolver = try? c.decodeIfPresent(
                ColorMatchSolverKind.self, forKey: .effectiveSolver)
        }

        /// The identity-blit gate (the unsolved face = either hash nil).
        public var isUnsolved: Bool {
            sourceStatsHash == nil || referenceStatsHash == nil
        }
    }

    public static let opName = "colormatch"

    /// LIGHTAMER-NATIVE V50Order row 36.5 (KD-5): the TRACK color-transfer
    /// neighborhood — lut3d (36.0) < colormatch < the dt-verbatim
    /// colortransfer (37.0, unregistered); inside the creative band, well
    /// below the 70.0 terminal-tail floor (layer-mask legality).
    public static let iopOrder: Float = 36.5

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    private let device: (any MTLDevice)?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: - Commit (the L069 lock discipline — reference state guarded)

    private let stateLock = NSLock()
    private var uniformsBuffer: (any MTLBuffer)?
    private var committed: Params?

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        // The identity gate (L031): strength 0 or the unsolved state → no
        // uniforms; process takes the routed blit.
        guard params.strength != 0, !params.isUnsolved,
            params.matrix.count == 9, params.offset.count == 3
        else {
            stateLock.withLock {
                committed = params
                uniformsBuffer = nil
            }
            piece.data = nil
            return
        }

        // The kernel's α-invariant terms (KD-6 recommended expansion):
        // out = x + α·((M−I)·x + c).
        let terms = ColorMatchSolver.strengthKernelTerms(params.asSolution)
        var uniforms = ColormatchUniforms()
        uniforms.setMi(terms.mMinusI)
        uniforms.setC(terms.c)
        uniforms.strength = params.strength

        let resolved = device ?? MTLCreateSystemDefaultDevice()
        let buffer: (any MTLBuffer)? = stateLock.withLock {
            if uniformsBuffer == nil || committed != params {
                uniformsBuffer = resolved?.makeBuffer(
                    length: MemoryLayout<ColormatchUniforms>.stride,
                    options: .storageModeShared)
                committed = params
            }
            return uniformsBuffer
        }
        guard let buffer else {
            piece.data = nil
            return
        }
        withUnsafeBytes(of: &uniforms) {
            buffer.contents().copyMemory(
                from: $0.baseAddress!, byteCount: MemoryLayout<ColormatchUniforms>.stride)
        }
        piece.data = buffer
    }

    // MARK: - Process (pointwise — tiling-safe, zero halo)

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
        let buffer: (any MTLBuffer)? = stateLock.withLock { uniformsBuffer }
        guard let buffer else {
            // The identity state (strength 0 / unsolved / device-less): the
            // routed blit copy (L031 — a hardwired queue blit races the
            // export chain cross-queue).
            try blitIdentity(input: input, output: output, metal: metal)
            return
        }
        try await metal.dispatch2DTexture(
            functionName: ColormatchKernel.linear,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// Whole-window routed blit (the FilmPlacement/Lut3d shape, L031).
    private func blitIdentity(
        input: any MTLTexture, output: any MTLTexture, metal: MetalContext
    ) throws {
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: input.width, height: input.height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()  // L008: encode close precedes commit
        commandBuffer.commit()
    }
}

// The params → solver-seam bridge (the module does not re-derive solutions;
// M5-1-02's solve flow ASSEMBLES params from a ColorMatchSolution).
extension ColormatchModule.Params {
    /// The view of these params as a solution-shaped value for the uniform
    /// terms (the matrix/offset pair is the same wire shape).
    var asSolution: ColorMatchSolution {
        ColorMatchSolution(
            solver: solver, effectiveSolver: effectiveSolver ?? solver,
            matrix: matrix, offset: offset,
            sourceStatsHash: UInt64(sourceStatsHash ?? "0") ?? 0,
            referenceStatsHash: UInt64(referenceStatsHash ?? "0") ?? 0)
    }
}

/// The MSL uniform mirror (flat floats — zero function constants; the ABI
/// is pinned by the T6 size-probe).
struct ColormatchUniforms {
    var mi0: Float = 0; var mi1: Float = 0; var mi2: Float = 0
    var mi3: Float = 0; var mi4: Float = 0; var mi5: Float = 0
    var mi6: Float = 0; var mi7: Float = 0; var mi8: Float = 0
    var c0: Float = 0; var c1: Float = 0; var c2: Float = 0
    var strength: Float = 0

    mutating func setMi(_ v: [Float]) {
        mi0 = v[0]; mi1 = v[1]; mi2 = v[2]
        mi3 = v[3]; mi4 = v[4]; mi5 = v[5]
        mi6 = v[6]; mi7 = v[7]; mi8 = v[8]
    }
    mutating func setC(_ v: [Float]) {
        c0 = v[0]; c1 = v[1]; c2 = v[2]
    }
}
