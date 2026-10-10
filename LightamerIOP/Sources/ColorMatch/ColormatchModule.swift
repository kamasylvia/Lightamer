import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// ColormatchModule (Plan M5-1-01 T5, KD-5; OQ-M5-1-3/OQ-M5-1-7; extended
// M5-1-02 T5) — the `colormatch` op: the TRACK color-transfer op, v50 slot
// 36.5 (LIGHTAMER-NATIVE row — sits between lut3d 36.0 and the dt-verbatim
// colortransfer 37.0; the creative band, well below the 70.0 layer floor).
//
// STRUCTURE: Lut3dModule 孪生 (flags [.supportsBlending, .allowTiling] —
// the grade-layer masking comes free through the existing blendop chain,
// OQ-M5-1-7; defaultColorspace .RGB; pointwise ROI).
//
// TWO RENDER ARMS (the params' solver picks the state machine):
// - LINEAR (gaussianOT/reinhard, Plan M5-1-01): matrix/offset/strength
//   ride the params; the α-invariant kernel `colormatch_linear` expands
//   x + α·((M−I)·x + c).
// - LUT (.cdf, M5-1-02): strength is a BAKE INPUT (KD-3) — the applied
//   table is `ColorMatchBake.bake(solution, strength)` and the dispatch
//   REUSES the shared `lut3d_tetrahedral` kernel function (zero new
//   sampling kernel, G2; Lut3dKernels.metal zero-diff) through this
//   module's OWN PSO + rgba32Float table texture, with IDENTITY fwd/inv
//   matrices and the unit domain (the bake output IS the working-space
//   map — OQ-2, no encoding semantics).
//
// PARAMS (the direct storage, OQ-M5-1-3): solver + the solved Oklab
// matrix/offset + strength + the two stats hashes + the effective solver
// (the R1 fallback diagnostic) + the LUT arm's `{assetRef, assetHash}`
// (KD-4). ZERO sidecar schema change — the params ride the registry/
// ModuleInstance paramsData channel; the table bytes NEVER enter
// paramsData (the <8KB bound).
//
// NIL ENCODING (checker 回注 E2, 2026-10-09): the P1 optionals encode
// EXPLICIT null (NOT encodeIfPresent absence) — the IopCatalog reflection
// guard compares the catalog key set against the DEFAULT-ENCODED key set,
// and the MCP apply_params path rejects unknown keys. The M5-1-02
// assetRef/assetHash keys are ADDITIVE omit-nil (encodeIfPresent — the
// M3-1-01 precedent): the default encoding and every P1-era blob
// re-encode byte-identically (the paramsHash zero-drift contract).
// Decode stays tolerant (missing/null keys decode nil; an unknown solver
// rawValue degrades to the default — never a throw into the sidecar
// loader).
//
// IDENTITY (L031 red line): `strength == 0` OR the unsolved state (the
// linear arm's missing hash pair / the LUT arm's missing assetRef) OR an
// asset DEGRADE → `makeRoutedCommandBuffer()` blit identity —
// cache-neutral, exposure-0EV style. The kernels dispatch ONLY in the
// non-identity states.
// ─────────────────────────────────────────────────────────────────────────────

public enum ColormatchKernel {
    /// MSL function names. `colormatch_linear` lives in
    /// `ColorMatchKernels.metal` (Plan M5-1-01 T6); the LUT arm reuses the
    /// SHARED `lut3d_tetrahedral` function from the same metallib (G2 —
    /// zero new sampling kernel; the parity face is Lut3dKernelTests').
    public static let linear = "colormatch_linear"
    public static let tetrahedral = Lut3dModule.Kernel.tetrahedral
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// The LUT arm's asset resolver injection seam (the Lut3dModule
/// `LutResolving` 同形): App installs a project-anchored resolver; Core
/// tests inject in-memory tables. The module NEVER touches disk itself.
public protocol ColormatchAssetResolving: Sendable {
    /// Load + verify the persisted `.cube` asset (the store's full
    /// verification — the degrade leg is a VALUE).
    func loadCube(assetRef: String, expectedHash: String?) -> ColormatchCubeAsset.LoadResult

    /// The session curve face for the α-into-bake live window (KD-3):
    /// the curves behind a solve, keyed by the params' stats-hash pair.
    /// nil = no curves in this session (the restore posture) — the caller
    /// falls back to the persisted asset verbatim (baked at the committed
    /// α, which the restored params.strength mirrors).
    func cdfSolution(sourceStatsHash: String, referenceStatsHash: String) -> ColorMatchCDFSolution?
}

/// The session resolver's shared holder + the registry factory's
/// long-lived forwarding face (the `LutLibraryStore.sharedResolver`/
/// SharedForwardingResolver 同形): boxes constructed by the factory read
/// THROUGH the forward to whatever session resolver is installed —
/// already-built boxes keep resolving the live instance after a swap.
public enum ColormatchResolverBox {
    /// The installed session resolver (nil = no session — every load
    /// degrades to the typed reason, the arm blits).
    public nonisolated(unsafe) static var shared: ColormatchAssetResolving?
}

/// The factory-facing forward: reads the box at CALL time (the registry
/// factory captures THIS value at populate time — never the session
/// resolver itself).
public struct ColormatchSharedResolverForward: ColormatchAssetResolving, @unchecked Sendable {
    public init() {}

    public func loadCube(
        assetRef: String, expectedHash: String?
    ) -> ColormatchCubeAsset.LoadResult {
        guard let shared = ColormatchResolverBox.shared else {
            return .degraded(reason: "colormatch resolver not installed")
        }
        return shared.loadCube(assetRef: assetRef, expectedHash: expectedHash)
    }

    public func cdfSolution(
        sourceStatsHash: String, referenceStatsHash: String
    ) -> ColorMatchCDFSolution? {
        ColormatchResolverBox.shared?.cdfSolution(
            sourceStatsHash: sourceStatsHash, referenceStatsHash: referenceStatsHash)
    }
}

public final class ColormatchModule: IOPModule {

    /// The colormatch params. `strength` defaults to 0 — the
    /// BYTE identity core (a fresh instance renders nothing).
    public struct Params: Codable, Hashable, Sendable {
        /// The user-selected solver (metadata for the re-solve face; the
        /// RENDER is driven by the arm: matrix/offset/strength for the
        /// linear arm, the baked asset for the LUT arm).
        public var solver: ColorMatchSolverKind
        /// Row-major 3×3 Oklab-domain map (the solved Float32 storage —
        /// the LINEAR arm only).
        public var matrix: [Float]
        /// The Oklab-domain offset c = μt − M·μs (the LINEAR arm only).
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
        /// The baked `.cube` derived asset (M5-1-02 T4, KD-4; OQ-3): the
        /// project(-image)-relative ref + the byte FNV (L013 decimal
        /// String). nil = no LUT-arm asset (the arm never renders). The
        /// table bytes NEVER ride here — the 3.3MB sidecar-bloat red line
        /// (the <8KB paramsData bound assertion pins it).
        ///
        /// ADDITIVE SERDE (the M3-1-01 inputEncoding precedent): these two
        /// keys encode via encodeIfPresent — ABSENT when nil — so the
        /// default Params() encoding and every P1-era blob re-encode
        /// BYTE-IDENTICALLY (the paramsHash zero-drift contract and the
        /// sidecar drift check both hold). Decode is tolerant.
        public var assetRef: String?
        public var assetHash: String?

        public init(
            solver: ColorMatchSolverKind = .gaussianOT,
            matrix: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1],
            offset: [Float] = [0, 0, 0],
            strength: Float = 0,
            sourceStatsHash: String? = nil,
            referenceStatsHash: String? = nil,
            effectiveSolver: ColorMatchSolverKind? = nil,
            assetRef: String? = nil,
            assetHash: String? = nil
        ) {
            self.solver = solver
            self.matrix = matrix
            self.offset = offset
            self.strength = strength
            self.sourceStatsHash = sourceStatsHash
            self.referenceStatsHash = referenceStatsHash
            self.effectiveSolver = effectiveSolver
            self.assetRef = assetRef
            self.assetHash = assetHash
        }

        private enum CodingKeys: String, CodingKey {
            case solver, matrix, offset, strength
            case sourceStatsHash, referenceStatsHash, effectiveSolver
            case assetRef, assetHash
        }

        /// EXPLICIT-null encode for the P1 key set (checker E2) + ADDITIVE
        /// omit-nil encode for the M5-1-02 keys (the zero-drift contract —
        /// the default encoding stays byte-identical to P1's).
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(solver, forKey: .solver)
            try c.encode(matrix, forKey: .matrix)
            try c.encode(offset, forKey: .offset)
            try c.encode(strength, forKey: .strength)
            try c.encode(sourceStatsHash, forKey: .sourceStatsHash)
            try c.encode(referenceStatsHash, forKey: .referenceStatsHash)
            try c.encode(effectiveSolver, forKey: .effectiveSolver)
            try c.encodeIfPresent(assetRef, forKey: .assetRef)
            try c.encodeIfPresent(assetHash, forKey: .assetHash)
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
            assetRef = try? c.decodeIfPresent(String.self, forKey: .assetRef)
            assetHash = try? c.decodeIfPresent(String.self, forKey: .assetHash)
        }

        /// The identity-blit gate (the unsolved face — the LINEAR arm's
        /// form; the LUT arm has its own gate checked in commitParams).
        public var isUnsolved: Bool {
            sourceStatsHash == nil || referenceStatsHash == nil
        }
    }

    /// The committed render arm (the process-time kernel selector).
    fileprivate enum Arm {
        case identity
        case linear
        case lut
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
    private let resolver: ColormatchAssetResolving?

    public init(
        device: (any MTLDevice)? = nil, resolver: ColormatchAssetResolving? = nil
    ) {
        self.device = device
        self.resolver = resolver
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    // MARK: - Commit (the L069 lock discipline — reference state guarded)

    private let stateLock = NSLock()
    private var uniformsBuffer: (any MTLBuffer)?
    private var committed: Params?
    private var committedArm: Arm = .identity
    private var lutTexture: (any MTLTexture)?
    /// The bake key the texture currently holds (skip redundant uploads).
    private var lutTextureKey: UInt64?
    /// The α-into-bake LRU (KD-3): key = fnv(solutionHash ⊕ α bits),
    /// capacity 16 — per-tick rebakes stay off the IO path and off the
    /// GPU for recently visited strengths.
    private var bakeCache: [UInt64: [SIMD3<Float>]] = [:]
    private var bakeOrder: [UInt64] = []
    private static let bakeCacheLimit = 16

    // The E5 extraction tap state (a separate lock — the capture faces are
    // service-driven one-shots orthogonal to the render reference state).
    private let captureLock = NSLock()
    private var captureArmed = false
    private var capturedStats: ColorMatchStats?

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        // The identity gate (L031): strength 0 always; the LINEAR arm's
        // unsolved face; the LUT arm's missing asset face. Each arm's
        // non-identity state packs its own uniforms below.
        guard params.strength != 0 else {
            _ = stateLock.withLock {
                committed = params
                committedArm = .identity
                uniformsBuffer = nil
            }
            piece.data = nil
            return
        }
        if params.solver == .cdf {
            commitLutArm(params, into: &piece)
            return
        }
        commitLinearArm(params, into: &piece)
    }

    /// The LINEAR arm commit (the M5-1-01 form verbatim).
    private func commitLinearArm(_ params: Params, into piece: inout IOPiece) {
        // The unsolved face: a hand-edited params blob cannot half-render.
        guard !params.isUnsolved, params.matrix.count == 9, params.offset.count == 3 else {
            _ = stateLock.withLock {
                committed = params
                committedArm = .identity
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
            committedArm = uniformsBuffer == nil ? .identity : .linear
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

    /// The LUT arm commit (M5-1-02 KD-3/KD-5): resolve the TABLE (the
    /// session curves baked at the CURRENT α — the live-tick path — or the
    /// persisted asset verbatim — the restore path), upload it, and pack
    /// the IDENTITY tetrahedral uniforms (the bake output IS the
    /// working-space map — the kernel's fwd/inv reduce to identity and its
    /// domain clamp IS the plateau policy).
    private func commitLutArm(_ params: Params, into piece: inout IOPiece) {
        guard let assetRef = params.assetRef else {
            // The G5 extension face: no asset → the blit identity.
            _ = stateLock.withLock {
                committed = params
                committedArm = .identity
                uniformsBuffer = nil
            }
            piece.data = nil
            return
        }
        let resolved = device ?? MTLCreateSystemDefaultDevice()
        guard let resolved else {
            _ = stateLock.withLock {
                committed = params
                committedArm = .identity
                uniformsBuffer = nil
            }
            piece.data = nil
            return
        }

        // Table assembly (bake + LRU + resolver + texture upload) under the
        // state lock — synchronous, no awaits (the L069/08dd061 shape).
        // The bake is the <50ms-budget leg; a first tick bakes, LRU hits
        // serve revisits (DECISIONS records the measured band).
        let failure: String? = stateLock.withLock {
            var table: [SIMD3<Float>]?
            var tableKey: UInt64?
            if let resolver,
                let source = params.sourceStatsHash, let reference = params.referenceStatsHash,
                let solution = resolver.cdfSolution(
                    sourceStatsHash: source, referenceStatsHash: reference)
            {
                // The live-tick path: bake at the CURRENT strength.
                let key = ColorMatchBake.bakeKey(
                    solutionHash: solution.solutionHash, strength: params.strength)
                if let cached = bakeCache[key] {
                    bakeOrder.removeAll { $0 == key }
                    bakeOrder.append(key)
                    table = cached
                } else {
                    let baked = ColorMatchBake.bake(
                        solution: solution, strength: params.strength)
                    bakeCache[key] = baked
                    bakeOrder.append(key)
                    while bakeOrder.count > Self.bakeCacheLimit {
                        bakeCache.removeValue(forKey: bakeOrder.removeFirst())
                    }
                    bakeCountStorage += 1
                    table = baked
                }
                tableKey = key
            } else if let loaded = resolver?.loadCube(
                assetRef: assetRef, expectedHash: params.assetHash)
            {
                // The restore path: the asset verbatim (baked at the
                // committed α — the restored params.strength mirrors it).
                switch loaded {
                case .loaded(let assetTable, _):
                    table = assetTable
                case .degraded(let reason):
                    AppError.logger.warning(
                        "colormatch LUT arm degrade: \(reason, privacy: .public)")
                }
            }
            guard let table, table.count == ColorMatchBake.latticeSize
                * ColorMatchBake.latticeSize * ColorMatchBake.latticeSize else {
                // Missing asset / degrade / curves-less restore without an
                // asset → the blit identity (the G5 extension state).
                committed = params
                committedArm = .identity
                uniformsBuffer = nil
                lutTexture = nil
                lutTextureKey = nil
                return "colormatch LUT arm table unavailable"
            }
            if uniformsBuffer == nil {
                uniformsBuffer = resolved.makeBuffer(
                    length: MemoryLayout<ColormatchLutUniforms>.stride,
                    options: .storageModeShared)
            }
            guard let buffer = uniformsBuffer else {
                committedArm = .identity
                return "uniform buffer allocation failed"
            }
            var uniforms = ColormatchLutUniforms()
            uniforms.level = UInt32(ColorMatchBake.latticeSize)
            withUnsafeBytes(of: &uniforms) {
                buffer.contents().copyMemory(
                    from: $0.baseAddress!, byteCount: MemoryLayout<ColormatchLutUniforms>.stride)
            }
            // Upload only when the table identity changed (per-tick α
            // changes rebake but the LRU may serve the same table).
            if lutTextureKey != tableKey || lutTexture == nil {
                ensureLutTexture(data: table, device: resolved)
                lutTextureKey = tableKey
            }
            committed = params
            committedArm = .lut
            piece.data = buffer
            return nil
        }
        if failure != nil { piece.data = nil }
    }

    /// Upload/refresh the 65³ table texture (rgba32Float texture3D — the
    /// Lut3dModule table posture). Caller holds stateLock.
    private func ensureLutTexture(data: [SIMD3<Float>], device: any MTLDevice) {
        let size = ColorMatchBake.latticeSize
        if lutTexture == nil || lutTexture!.width != size {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D
            descriptor.pixelFormat = .rgba32Float
            descriptor.width = size
            descriptor.height = size
            descriptor.depth = size
            descriptor.mipmapLevelCount = 1
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            lutTexture = device.makeTexture(descriptor: descriptor)
        }
        guard let texture = lutTexture else { return }
        var floats = [Float]()
        floats.reserveCapacity(data.count * 4)
        for v in data {
            floats.append(v.x)
            floats.append(v.y)
            floats.append(v.z)
            floats.append(1.0)
        }
        floats.withUnsafeBytes { raw in
            let bytesPerRow = size * 16
            let bytesPerImage = bytesPerRow * size
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: size, height: size, depth: size))
            texture.replace(
                region: region, mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                bytesPerRow: bytesPerRow, bytesPerImage: bytesPerImage)
        }
        lutTexture = texture
    }

    // MARK: - ROI (pointwise — tiling-safe, zero halo)

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
        // The E5 extraction tap (one-shot, service-armed): capture the
        // INPUT plane's statistics BEFORE this module's own state touches
        // anything — the in-point tap IS the bypass-by-construction (the
        // solve-twice stability lives here).
        let shouldCapture = captureLock.withLock {
            let armed = captureArmed
            captureArmed = false
            return armed
        }
        if shouldCapture {
            capturedStats = try? await Self.extractStats(from: input, metal: metal)
        }

        let (buffer, arm, table): ((any MTLBuffer)?, Arm, (any MTLTexture)?) =
            stateLock.withLock { (uniformsBuffer, committedArm, lutTexture) }
        guard let buffer, piece.data != nil else {
            // The identity state: the routed blit copy (L031).
            try blitIdentity(input: input, output: output, metal: metal)
            return
        }
        switch arm {
        case .identity:
            try blitIdentity(input: input, output: output, metal: metal)
        case .linear:
            try await metal.dispatch2DTexture(
                functionName: ColormatchKernel.linear,
                input: input,
                output: output
            ) { encoder in
                encoder.setBuffer(buffer, offset: 0, index: 0)
            }
        case .lut:
            guard let table else {
                try blitIdentity(input: input, output: output, metal: metal)
                return
            }
            // The SHARED tetrahedral kernel through this module's own PSO:
            // in/out/table textures + the identity-uniform buffer (the
            // Lut3dModule dispatch shape — the per-run width/height/level
            // stamp window is atomic per instance).
            let session = try await metal.makeEncoder(functionName: ColormatchKernel.tetrahedral)
            try stateLock.withLock {
                let uniforms = piece.data!.contents().assumingMemoryBound(
                    to: ColormatchLutUniforms.self)
                uniforms.pointee.width = UInt32(output.width)
                uniforms.pointee.height = UInt32(output.height)
                session.encoder.setTexture(input, index: 0)
                session.encoder.setTexture(output, index: 1)
                session.encoder.setTexture(table, index: 2)
                session.encoder.setBuffer(piece.data!, offset: 0, index: 0)
                session.encoder.dispatchThreads(
                    MTLSize(width: output.width, height: output.height, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                )
                session.encoder.endEncoding()  // L008: encode close precedes commit
            }
            session.commandBuffer.commit()
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

    // MARK: - The E5 extraction tap (the pipeline-level API's in-pipe leg)

    /// Test observability: the COMPOSITE bake counter (instance level —
    /// counts real bakes only; LRU hits never increment; the
    /// Lut3dModule.bakeCount 体例).
    public var bakeCountForTesting: Int {
        stateLock.withLock { bakeCountStorage }
    }

    private var bakeCountStorage = 0

    /// Arm the one-shot input-plane capture (the service's extraction
    /// render runs the chain with the box present; the capture consumes
    /// itself on the first dispatch).
    public func armStatsCapture() {
        captureLock.withLock { captureArmed = true }
    }

    /// Consume the captured statistics (nil = the armed render hasn't
    /// landed / nothing captured). Read-and-clear.
    public func consumeCapturedStats() -> ColorMatchStats? {
        captureLock.withLock {
            let stats = capturedStats
            capturedStats = nil
            return stats
        }
    }

    /// The plane → stats capture: L014 fence, the WHOLE plane readback
    /// (the extraction render pins the bucket ≤512 — the plane is small),
    /// the FIXED-ORDER strided sample grid (≤512² — the CPU-side contract),
    /// the Oklab conversion, and the P1 pure extraction.
    static func extractStats(
        from plane: any MTLTexture, metal: MetalContext
    ) async throws -> ColorMatchStats {
        let fence = try metal.makeRoutedCommandBuffer()
        fence.commit()
        _ = await fence.completed()
        let width = plane.width
        let height = plane.height
        guard width > 0, height > 0 else { throw ColorMatchStatsError.emptySampleSet }
        var floats = [Float](repeating: 0, count: width * height * 4)
        floats.withUnsafeMutableBytes { raw in
            plane.getBytes(
                raw.baseAddress!, bytesPerRow: width * 16,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        // The fixed-order strided grid: a deterministic subsample ≤512² in
        // row-major order (the same plane always yields the same samples).
        let strideX = max(1, (width + 511) / 512)
        let strideY = max(1, (height + 511) / 512)
        var samples: [SIMD3<Float>] = []
        samples.reserveCapacity(((width + strideX - 1) / strideX) * ((height + strideY - 1) / strideY))
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = (y * width + x) * 4
                samples.append(OklabMath.linearRec2020ToOklab(
                    SIMD3<Float>(floats[offset], floats[offset + 1], floats[offset + 2])))
                x += strideX
            }
            y += strideY
        }
        return try ColorMatchStats.extract(samples: samples)
    }
}

/// The MSL `Lut3dUniforms` mirror for the LUT arm (Lut3dKernels.metal —
/// field-for-field with Lut3dModule.Uniforms: the SHARED kernel's uniform
/// layout; the matrices stay IDENTITY and the domain [0,1] — the bake
/// output IS the working-space map). Scalar fields only (MSL float3 in
/// constant buffers is 16-byte aligned; the 9-tuples sidestep the padding
/// trap the same way).
struct ColormatchLutUniforms {
    var width: UInt32 = 0
    var height: UInt32 = 0
    var level: UInt32 = 0
    var domainMinX: Float = 0
    var domainMinY: Float = 0
    var domainMinZ: Float = 0
    var domainMaxX: Float = 1
    var domainMaxY: Float = 1
    var domainMaxZ: Float = 1
    var fwd: (Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (1, 0, 0, 0, 1, 0, 0, 0, 1)
    var inv: (Float, Float, Float, Float, Float, Float, Float, Float, Float) =
        (1, 0, 0, 0, 1, 0, 0, 0, 1)
}

// The params → solver-seam bridge (the module does not re-derive solutions;
// the solve flow ASSEMBLES params from a ColorMatchSolution).
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
