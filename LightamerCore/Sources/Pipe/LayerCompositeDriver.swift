import Foundation
import Metal
import os

/// Swift mirror of the MSL `BlendOpUniforms` (32-byte stride; BlendOp
/// kernel ABI — the IOP side mirror is `BlendOpDispatchUniforms`, the MSL
/// struct the single source of the ABI; the identity/parity gates pin all
/// three together).
struct BlendCompositeUniforms {
    var opacity: Float      // CLIP'd gopacity — used when hasMask == 0
    var blendMode: UInt32   // BlendMode rawValue (dt slot)
    var reverse: UInt32     // DEVELOP_BLEND_REVERSE consumption
    var hasMask: UInt32     // 1 = mask plane carries the effective opacity
    var blendParam: Float   // exp2(blend_parameter) = 1 (no per-layer parameter in v1)
    var rowBegin: UInt32    // write band — whole plane for the driver path
    var rowEnd: UInt32
    private var _pad: UInt32 = 0

    init(
        opacity: Float, blendMode: BlendMode, reverse: Bool, hasMask: Bool,
        blendParam: Float = 1.0
    ) {
        self.opacity = opacity
        self.blendMode = UInt32(blendMode.rawValue)
        self.reverse = reverse ? 1 : 0
        self.hasMask = hasMask ? 1 : 0
        self.blendParam = blendParam
        self.rowBegin = 0
        self.rowEnd = UInt32.max
    }
}

/// One composited layer's per-leg accounting (SC#2-style verification
/// channel for the layer cache scenarios — `LayerCacheTests`).
public struct LayerCompositeLayerStats: Sendable {

    public let layerID: UUID

    /// The sub-run stats (cache probes for this layer's chain planes).
    public let run: RenderPipeline.PipeRunStats

    /// Whether the composite prefix probe HIT (C_k came from the cache —
    /// the blend pass never dispatched).
    public let prefixHit: Bool
}

/// The whole-composite result: the display plane + the negotiated window +
/// per-leg stats (the 06-01 verification channel; consumed by tests now,
/// by the coordinator in 6-5).
public struct LayerCompositeResult {

    /// The terminal-segment output (display format when the base chain
    /// carried gamma) — or the last composite plane without a terminal.
    public let output: any MTLTexture

    /// The negotiated composite window (base sub-run's final ROI = every
    /// layer sub-run's entry ROI = the terminal segment's input ROI).
    public let window: ROI

    public let baseStats: RenderPipeline.PipeRunStats
    public let layerStats: [LayerCompositeLayerStats]
    public let terminalStats: RenderPipeline.PipeRunStats?

    /// Composite kernel dispatches this run (the incremental-blend cost
    /// the accounting scenarios cross-check).
    public let blendPasses: Int
}

/// The 1 + N + 1 composite orchestrator (Plan 06-01 T4; 06-RESEARCH §2) —
/// the mixed model (c) engine skeleton:
///
/// ```
/// A. base sub-run   (base chain minus terminal colorout/gamma) → S
/// B. per layer      (bottom-up, skip !enabled):
///      layer sub-run (input = C_prev, roiHint = window) → L_k
///      degenerate blend  C_k = C_prev·(1−op) + L_k·op   (normal; mask = 1)
/// C. terminal seg   ([colorout, gamma], display-tail policy) → display
/// ```
///
/// **Zero walk change:** every leg IS a `PixelPipe` run (base via `run`,
/// layers/terminal via the `runSub` seam) — v50 sort, hash chain, ROI
/// negotiation, cache and tiling semantics are inherited, not reimplemented.
///
/// **L021 layer dimension (red lines, enforced here):**
/// - each layer sub-run stamps its OWN `bufInROI`/`dscIn`/`iscale` — the
///   driver asserts per layer `entry dscIn == bufInROI.first == window`;
///   there is NO code path handing base geometry to a layer;
/// - cross-layer ROI consistency is a precondition (the
///   `PixelPipe.swift` negotiated-ROI pattern applied across legs);
/// - geometry modules (V50Order slots lens 13 / ashift 15 / flip 16 /
///   clipping 17 — D-06-CONTEXT-5) are REJECTED in layer chains.
///
/// **Cache (T3):** layer chain planes key on the layer UUID; composite
/// prefixes C_k key on the OWNING layer at `compositePosition` with
/// `upstreamHash = ⊕(prefixHash_prev, chainHash_k, blendTripleHash_k)` —
/// editing layer K flips exactly K..N prefixes while every >K chain output
/// stays cached (the incremental-blend semantics `LayerCacheTests` pins).
enum LayerCompositeDriver {

    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer", category: "pixelpipe")

    /// D-06-CONTEXT-5: geometric V50Order slots forbidden INSIDE a layer
    /// chain (base-only). Derived from the slot table, not string lists.
    private static let layerForbiddenGeometryOps: Set<String> = {
        let forbiddenSlots: Set<Float> = [13.0, 15.0, 16.0, 17.0]
        return Set(V50Order.entries.filter { forbiddenSlots.contains($0.order) }.map(\.opName))
    }()

    /// The kernel function name (`BlendOpKernels.metal`, LightamerIOP's
    /// metallib — resolved via the registered-library lookup; the 6-1
    /// degenerate `layer_composite_normal` pass is RETIRED, plan 06-02 T2.3).
    internal static let compositeKernel = "compositeLayer"

    /// The 6-1 mask-version placeholder is RETIRED (plan 06-03 T6): the
    /// real `MaskSpec.stableHash()` folds through `blendTripleHash` and
    /// keys the mask plane at `maskPosition`.

    /// The testable face of the D-06-CONTEXT-5 geometry rejection: returns
    /// the offending op name, or nil when the (effective) chain is legal.
    /// `composite` turns a non-nil verdict into a fatal error BEFORE any
    /// GPU work; the UI hides layer-internal geometry in 6-5.
    internal static func layerGeometryViolation(
        _ effectiveChain: [ModuleInstance]
    ) -> String? {
        let effective = effectiveChain
        return effective.first { layerForbiddenGeometryOps.contains($0.opName) }?.opName
    }

    // MARK: - Hash composition (StableHash ONLY — L013)

    private static func fold(_ seed: UInt64, _ value: UInt64) -> UInt64 {
        var v = value
        return withUnsafeBytes(of: &v) { StableHash.combine(seed, $0) }
    }

    /// The blend triple (opacity, blend mode, option flags, MASK VERSION) —
    /// folded into every composite-prefix key so a blend-attribute OR MASK
    /// edit invalidates exactly the prefixes at and above that layer
    /// without touching any chain hash (the maskVersion ⊥ chainHash
    /// independence, plan 06-03 T6 / METAL-8 double insurance).
    internal static func blendTripleHash(
        opacity: Float, blendMode: BlendMode, blendOptions: BlendOptions,
        maskHash: UInt64 = 0
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        h = fold(h, UInt64(bitPattern: Int64(opacity.bitPattern)))
        h = fold(h, UInt64(bitPattern: Int64(blendMode.rawValue)))
        h = fold(h, UInt64(blendOptions.rawValue))
        h = fold(h, maskHash)
        return h
    }

    // MARK: - Entry

    /// Run the composite over `image` with the base instance boxes (the
    /// global set, terminal segment included — the driver extracts it) and
    /// the stack's adjustment layers (records → boxes per sub-run).
    ///
    /// - `policy`: the T3 cache policy (PREVIEW → `.preview`, FULL →
    ///   `.fullColdLayer` with `hotLayerID` = the layer under edit).
    /// - `roiHint`: optional sub-window (FULL zoom; test seam).
    static func composite(
        image: DecodedImage,
        imageID: UUID,
        baseInstances: [any ModuleBoxing],
        layerStack: LayerStack,
        registry: ModuleRegistry,
        resolution: PipeResolution,
        cache: PipeCache,
        metal: MetalContext,
        longEdge: Int? = nil,
        roiHint: ROI? = nil,
        policy: LayerCachePolicy = .preview,
        hotLayerID: UUID? = nil,
        maskDirectory: URL? = nil
    ) async throws -> LayerCompositeResult {
        let interval = signposter.beginInterval("composite", id: signposter.makeSignpostID())
        defer { signposter.endInterval("composite", interval) }

        // ── Terminal-segment extraction (the colorout→gamma display tail;
        //    colorin stays in the base chain — 28.0 < 70.0 < 78.0).
        let terminalOps: Set<String> = ["colorout", GammaModule.opName]
        let baseChain = baseInstances.filter { !terminalOps.contains($0.opName) }
        let terminalChain = baseInstances
            .filter { terminalOps.contains($0.opName) }
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        // ── Layer records → effective chains up front; geometry rejection
        //    BEFORE any GPU work (D-06-CONTEXT-5, fatal semantics).
        let layers = layerStack.compositeLayers
        for layer in layers {
            if let violation = layerGeometryViolation(
                HistoryStack.effectiveChain(layer.chain)) {
                fatalError(
                    "LayerCompositeDriver: geometric module '\(violation)' in adjustment layer '\(layer.name)' — layer-internal geometry is forbidden in v1 (D-06-CONTEXT-5); it belongs to the base chain only")
            }
        }

        // ── A. base sub-run → the composite input plane S.
        let basePipe = PixelPipe(resolution: resolution, cache: cache)
        basePipe.imageID = imageID
        basePipe.layerStack = layerStack
        if let roiHint {
            basePipe.entryROIHInt = roiHint
        }
        let (basePlane, baseStats) = try await basePipe.run(
            image: image, instances: baseChain, metal: metal, longEdge: longEdge)
        // The composite window: the base forward walk's final ROI — every
        // downstream leg (layer entries + terminal input) consumes exactly
        // this (cross-layer ROI one-shot negotiation, 06-RESEARCH §2.3).
        let window = basePipe.roi
        var accumulator = basePlane
        // The prefix-hash seed: the base chain's terminal level hash — a
        // base edit flips EVERY prefix, a layer edit flips only its own.
        var prefixHash = basePipe.levelHash.last ?? basePipe.decodeParamsHash

        var layerStats: [LayerCompositeLayerStats] = []
        var blendPasses = 0

        // ── B. per-layer composite (bottom-up).
        for layer in layers {
            // enabled=false: REMOVED from processing entirely (no sub-run,
            // no blend, no prefix fold — the semantic opposite of hidden).
            guard layer.enabled else { continue }

            // The layer's own sub-run (independent params — LAYER-02).
            let (boxes, _) = await registry.materializeBoxes(for: layer.chain)
            let layerPipe = PixelPipe(resolution: resolution, cache: cache)
            layerPipe.imageID = imageID
            let (layerPlane, runStats) = try await layerPipe.runSub(
                input: accumulator, inputROI: window,
                instances: boxes, decodeHash: basePipe.decodeParamsHash,
                metal: metal, layerID: layer.id)

            // L021 layer-dimension assertions (resident): this layer's
            // entry geometry is ITS OWN sub-run's stamp — window-shaped,
            // never borrowed from the base walk.
            if let first = layerPipe.pieces.first {
                let entryDscIn = first.state.dscIn
                let entryBufIn = layerPipe.bufInROI.first
                precondition(
                    entryDscIn.width == entryBufIn?.width
                        && entryDscIn.height == entryBufIn?.height,
                    "L021: layer '\(layer.name)' entry dscIn != its own bufInROI.first")
                precondition(
                    entryBufIn?.width == window.width && entryBufIn?.height == window.height,
                    "L021: layer '\(layer.name)' entry ROI deviates from the negotiated composite window (\(String(describing: entryBufIn)) vs \(window))")
            }
            // Cross-layer ROI consistency (the negotiated-ROI precondition
            // pattern, applied across legs): identity-ROI layer chains end
            // exactly on the window.
            if let lastROI = layerPipe.levelROI.last {
                precondition(
                    lastROI.width == window.width && lastROI.height == window.height
                        && lastROI.x == window.x && lastROI.y == window.y,
                    "composite window violated by layer '\(layer.name)': \(lastROI) vs \(window)")
            }
            precondition(
                layerPlane.width == window.width && layerPlane.height == window.height,
                "layer '\(layer.name)' plane \(layerPlane.width)x\(layerPlane.height) != window \(window.width)x\(window.height)")

            // isVisible=false: still PROCESSED (sub-run above — its chain
            // planes stay warm) but SKIPPED at composite (no blend, no
            // prefix fold — C_k ≡ C_prev content and hash).
            guard layer.isVisible else {
                layerStats.append(LayerCompositeLayerStats(
                    layerID: layer.id, run: runStats, prefixHit: false))
                continue
            }

            // Degenerate blend: C_k = C_prev·(1−op) + L_k·op. The prefix
            // key folds chain ⊕ blend-triple ⊕ (REAL) mask-version hash —
            // a mask edit flips ONLY the prefix + the mask plane while the
            // layer's chain planes stay cached (T6 incremental semantics).
            let maskHash = layer.mask?.stableHash() ?? 0
            let tripleHash = blendTripleHash(
                opacity: layer.opacity, blendMode: layer.blendMode,
                blendOptions: layer.blendOptions, maskHash: maskHash)
            let chainHash = layerPipe.levelHash.last ?? basePipe.decodeParamsHash
            prefixHash = fold(fold(prefixHash, chainHash), tripleHash)
            let prefixKey = PipeCacheKey(
                imageID: imageID, pipeType: resolution,
                position: PipeCacheKey.compositePosition,
                upstreamHash: prefixHash, roi: window, layerID: layer.id)
            let planeBytes = window.width * window.height * WorkingSpace.bytesPerPixel

            // ── The MASK leg (plan 06-04 T5): the THREE payload classes
            // (drawn ⊗ parametric ⊓ raster) assemble into ONE effective
            // plane through MaskCombiner, cached at the mask-version key.
            // nil = the constant-1 uniform path. Raster loading needs the
            // sidecar's masks directory (nil → the documented degrade).
            var maskPlane: (any MTLTexture)?
            var maskDegradeReason: String?
            if let mask = layer.mask, mask.hasAnyPayload {
                let mapper = GeometryPointMapper.compose(
                    boxes: baseChain,
                    frameSize: SIMD2(
                        Double(basePipe.frameROI.width),
                        Double(basePipe.frameROI.height)))
                let (plane, _, reason) = try await MaskCombiner.effectivePlane(
                    spec: mask, layerOpacity: max(0, min(1, layer.opacity)),
                    window: window, below: accumulator, top: layerPlane,
                    mapper: mapper, metal: metal, cache: cache,
                    imageID: imageID, pipeType: resolution, layerID: layer.id,
                    maskDirectory: maskDirectory)
                maskPlane = plane
                maskDegradeReason = reason
            }
            if let reason = maskDegradeReason {
                AppError.logger.error(
                    "raster mask degraded for layer '\(layer.name, privacy: .public)': \(reason, privacy: .public)")
            }

            var prefixHit = false
            let statsBefore = await cache.stats
            let blended: any MTLTexture
            if policy.cachesAllPrefixes {
                // TextureBox: the @unchecked-Sendable ownership wrapper (the
                // planes are built once and read-only inside the closure).
                let belowBox = TextureBox(texture: accumulator)
                let topBox = TextureBox(texture: layerPlane)
                let maskBox = maskPlane.map { TextureBox(texture: $0) }
                let hasMask = maskPlane != nil
                let cached = try await cache.plane(for: prefixKey, byteCount: planeBytes) {
                    [belowBox, topBox, maskBox, layer] in
                    try await Self.blend(
                        below: belowBox.texture, top: topBox.texture,
                        mask: maskBox?.texture, layer: layer, metal: metal)
                }
                blended = cached.texture
                let delta = (await cache.stats) - statsBefore
                prefixHit = delta.hits > 0
                // The dispatch counter counts KERNEL dispatches only — a
                // prefix hit short-circuits the blend entirely (its purpose).
                blendPasses += delta.misses > 0 ? 1 : 0
            } else {
                // The no-prefix policy (a future FULL variant): compute
                // without caching.
                blended = try await Self.blend(
                    below: accumulator, top: layerPlane, mask: maskPlane,
                    layer: layer, metal: metal)
                blendPasses += 1
            }
            accumulator = blended

            // D-06-CONTEXT-8 cold-layer leg: drop this layer's chain-output
            // lines after the blend (prefixes survive). The hot layer keeps
            // its chain planes.
            if !policy.cachesAllLayerOutputs && layer.id != hotLayerID {
                await cache.invalidateLayer(imageID: imageID, layerID: layer.id)
            }

            layerStats.append(LayerCompositeLayerStats(
                layerID: layer.id, run: runStats, prefixHit: prefixHit))
        }

        // ── C. terminal segment (the display tail, policy unchanged).
        var terminalStats: RenderPipeline.PipeRunStats?
        var output = accumulator
        if !terminalChain.isEmpty {
            let terminalPipe = PixelPipe(resolution: resolution, cache: cache)
            terminalPipe.imageID = imageID
            terminalPipe.layerStack = layerStack // baseLayer.id namespace
            let (terminalPlane, stats) = try await terminalPipe.runSub(
                input: accumulator, inputROI: window,
                instances: terminalChain, decodeHash: basePipe.decodeParamsHash,
                metal: metal, layerID: layerStack.baseLayer.id)
            output = terminalPlane
            terminalStats = stats
        }

        return LayerCompositeResult(
            output: output, window: window, baseStats: baseStats,
            layerStats: layerStats, terminalStats: terminalStats,
            blendPasses: blendPasses)
    }

    /// One blendop composite pass into a fresh plane — the FULL mode table
    /// (mask × blend × opacity triple, plan 06-02 T2). `mask` = the
    /// pre-multiplied effective-opacity plane from the 06-03 rasterizer
    /// (red channel consumed directly, D-06-02-T5-3); nil = the uniform
    /// path (`blendop_set_mask` equivalence, the constant-1 leg).
    private static func blend(
        below: any MTLTexture,
        top: any MTLTexture,
        mask: (any MTLTexture)?,
        layer: AdjustmentLayer,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        precondition(
            below.width == top.width && below.height == top.height,
            "blend plane mismatch: \(below.width)x\(below.height) vs \(top.width)x\(top.height)")
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: below.width, height: below.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let output = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(below.width * below.height * WorkingSpace.bytesPerPixel)
        }
        var uniforms = BlendCompositeUniforms(
            opacity: max(0, min(1, layer.opacity)),
            blendMode: layer.blendMode,
            reverse: layer.blendOptions.contains(.reverse),
            hasMask: mask != nil)
        let session = try await metal.makeEncoder(functionName: compositeKernel)
        session.encoder.setTexture(below, index: 0)
        session.encoder.setTexture(top, index: 1)
        session.encoder.setTexture(mask, index: 2)
        session.encoder.setTexture(output, index: 3)
        session.encoder.setBytes(&uniforms, length: MemoryLayout<BlendCompositeUniforms>.stride, index: 0)
        let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
        precondition(
            threadsPerGroup.width * threadsPerGroup.height
                <= session.pipelineState.maxTotalThreadsPerThreadgroup,
            "composite kernel threadgroup exceeds the PSO budget")
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: threadsPerGroup)
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }
}
