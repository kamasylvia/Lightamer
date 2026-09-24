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
/// editing layer K flips exactly K..N prefixes; chain outputs above K MISS
/// (the seed folds the input accumulator identity — GUI-21 fix;
/// `LayerCacheTests` pins the corrected semantics).
enum LayerCompositeDriver {

    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer", category: "pixelpipe")

    /// Plan 08-01 T1: the terminal-segment floor — every base instance at
    /// or above this v50 position belongs to the display tail (the
    /// colorout..gamma window; yiyin `borders` 76.0 / `watermark` 77.0 are
    /// its new residents, D-08-CONTEXT "终端段落位"). Zero for the legacy
    /// chains: colorout 70.0 / gamma 78.0 keep their extraction, skinSmooth
    /// 66.5 stays base.
    static let terminalTailFloor: Float = 70.0

    /// The testable face of the tail-window extraction: base chain (v50
    /// order preserved as given) + the terminal tail (v50-sorted). The one
    /// pipeline change Plan 08-1 is allowed to make.
    static func splitTerminal(
        _ instances: [any ModuleBoxing]
    ) -> (base: [any ModuleBoxing], terminal: [any ModuleBoxing]) {
        let base = instances.filter { $0.iopOrder < terminalTailFloor }
        let terminal = instances
            .filter { $0.iopOrder >= terminalTailFloor }
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
        return (base, terminal)
    }

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

        // ── Terminal-segment extraction — Plan 08-01 T1: the display tail
        //    window widened from the `{colorout, gamma}` op-name set to the
        //    whole `iopOrder ≥ 70.0` tail (colorout 70.0 → … → borders 76.0
        //    → watermark 77.0 → gamma 78.0 — the display-referred seam, dt
        //    `iop_order.c` positions verbatim; colorin 28.0 stays base).
        //    Segment-internal order stays v50 `(iopOrder, multiPriority)`.
        let (baseChain, terminalChain) = Self.splitTerminal(baseInstances)

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
        // Plan 06-07 T2: the retouch SOURCE ∪ TARGET AABB extension — a
        // clone/heal stroke may sample OUTSIDE the requested window (its
        // source patch lives elsewhere in the frame); the base sub-run must
        // render the covering region or the paste reads invented pixels
        // (the 源区黑边 red line). The walk clamps the union into the frame.
        let basePipe = PixelPipe(resolution: resolution, cache: cache)
        basePipe.imageID = imageID
        basePipe.layerStack = layerStack
        if let roiHint {
            basePipe.entryROIHInt = Self.expandedHint(
                hint: roiHint, layerStack: layerStack, baseChain: baseChain,
                image: image, longEdge: longEdge, resolution: resolution)
            if basePipe.entryROIHInt != roiHint {
                AppError.logger.info(
                    "retouch ROI extension: window widened for stroke source patches")
            }
        } else {
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

        // The content-anchored point mapper, built ONCE from the base walk's
        // authoritative frame (the retouch strokes AND every mask leg share
        // it — the per-layer construction below was redundant work).
        let geometryMapper = GeometryPointMapper.compose(
            boxes: baseChain,
            frameSize: SIMD2(
                Double(basePipe.frameROI.width), Double(basePipe.frameROI.height)))

        // ── B. per-layer composite (bottom-up, BOTH kinds since 06-07).
        for layer in layerStack.adjustmentLayers {
            // ── ① the retouch kind (Plan 06-07): the stroke leg replaces
            // the chain sub-run; the blend triple is unchanged (NO_MASKS —
            // maskHash 0, the stroke shapes carried their own mask).
            if let retouch = layer as? RetouchLayer {
                guard retouch.enabled else { continue }
                let strokeHash = RetouchEngine.strokeListHash(retouch.strokes)

                // isVisible=false: nothing to keep warm (the stroke leg owns
                // no chain planes) — skip at composite, no prefix fold.
                guard retouch.isVisible else {
                    layerStats.append(LayerCompositeLayerStats(
                        layerID: retouch.id, run: RenderPipeline.PipeRunStats(
                            hits: 0, misses: 0, planesRendered: 0),
                        prefixHit: false))
                    continue
                }

                // The stroke leg: cached at (input prefix ⊕ stroke hash) —
                // editing a HIGHER layer leaves this leg's input untouched
                // and the cached stroke output survives (the incremental
                // model extends to the retouch dimension).
                var strokeOutput = accumulator
                var legHit = false
                if !retouch.strokes.isEmpty {
                    let legUpstream = fold(prefixHash, strokeHash)
                    let legBytes = window.width * window.height * WorkingSpace.bytesPerPixel
                    if policy.cachesAllLayerOutputs || retouch.id == hotLayerID {
                        let key = PipeCacheKey(
                            imageID: imageID, pipeType: resolution,
                            position: PipeCacheKey.retouchPosition,
                            upstreamHash: legUpstream, roi: window, layerID: retouch.id)
                        let statsBefore = await cache.stats
                        let inputBox = TextureBox(texture: accumulator)
                        let cached = try await cache.plane(for: key, byteCount: legBytes) {
                            [inputBox] in
                            try await RetouchEngine.applyStrokes(
                                retouch, input: inputBox.texture, window: window,
                                mapper: geometryMapper, cache: cache, imageID: imageID,
                                pipeType: resolution, metal: metal
                            ).output
                        }
                        strokeOutput = cached.texture
                        let delta = (await cache.stats) - statsBefore
                        legHit = delta.hits > 0
                    } else {
                        let computed = try await RetouchEngine.applyStrokes(
                            retouch, input: accumulator, window: window,
                            mapper: geometryMapper, cache: cache, imageID: imageID,
                            pipeType: resolution, metal: metal)
                        strokeOutput = computed.output
                    }
                }

                // The blend triple — same composite path as every layer.
                let tripleHash = blendTripleHash(
                    opacity: retouch.opacity, blendMode: retouch.blendMode,
                    blendOptions: retouch.blendOptions, maskHash: 0)
                prefixHash = fold(fold(prefixHash, strokeHash), tripleHash)
                let prefixKey = PipeCacheKey(
                    imageID: imageID, pipeType: resolution,
                    position: PipeCacheKey.compositePosition,
                    upstreamHash: prefixHash, roi: window, layerID: retouch.id)
                let planeBytes = window.width * window.height * WorkingSpace.bytesPerPixel

                var prefixHit = false
                let statsBefore = await cache.stats
                let blended: any MTLTexture
                if policy.cachesAllPrefixes {
                    let belowBox = TextureBox(texture: accumulator)
                    let topBox = TextureBox(texture: strokeOutput)
                    let triple = BlendTriple(
                        opacity: retouch.opacity, mode: retouch.blendMode,
                        reverse: retouch.blendOptions.contains(.reverse))
                    let cachedBlend = try await cache.plane(
                        for: prefixKey, byteCount: planeBytes) { [belowBox, topBox, triple] in
                        try await Self.blend(
                            below: belowBox.texture, top: topBox.texture, mask: nil,
                            triple: triple, metal: metal)
                    }
                    blended = cachedBlend.texture
                    let blendDelta = (await cache.stats) - statsBefore
                    prefixHit = blendDelta.hits > 0
                    blendPasses += blendDelta.misses > 0 ? 1 : 0
                } else {
                    blended = try await Self.blend(
                        below: accumulator, top: strokeOutput, mask: nil,
                        triple: BlendTriple(
                            opacity: retouch.opacity, mode: retouch.blendMode,
                            reverse: retouch.blendOptions.contains(.reverse)),
                        metal: metal)
                    blendPasses += 1
                }
                accumulator = blended

                if !policy.cachesAllLayerOutputs && retouch.id != hotLayerID {
                    await cache.invalidateLayer(imageID: imageID, layerID: retouch.id)
                }
                layerStats.append(LayerCompositeLayerStats(
                    layerID: retouch.id,
                    run: RenderPipeline.PipeRunStats(
                        hits: legHit ? 1 : 0, misses: legHit ? 0 : 1,
                        planesRendered: retouch.strokes.isEmpty ? 0 : 1),
                    prefixHit: prefixHit))
                continue
            }

            // ── ② the adjustment kind (the 06-01..06-05 path, unchanged).
            guard let adjustment = layer as? AdjustmentLayer else { continue }
            // enabled=false: REMOVED from processing entirely (no sub-run,
            // no blend, no prefix fold — the semantic opposite of hidden).
            guard adjustment.enabled else { continue }

            // The layer's own sub-run (independent params — LAYER-02).
            let (boxes, _) = await registry.materializeBoxes(for: adjustment.chain)
            let layerPipe = PixelPipe(resolution: resolution, cache: cache)
            layerPipe.imageID = imageID
            // GUI-21 (2026-09-24): the sub-run's hash seed is the INPUT
            // accumulator's composite identity (`prefixHash` — it folds the
            // base levelHash and every lower layer's chain/blend/mask
            // hashes), NOT the bare decode hash. The old decode-only seed
            // made the layer's cache lines BLIND to their input: an edit
            // below (base param change or a lower layer) left the lines
            // keyed unchanged → stale HIT → the freshly blended accumulator
            // was discarded by an old L_k. Self-edits stay incremental
            // (seed unchanged, the chain's own paramsHash flips).
            let (layerPlane, runStats) = try await layerPipe.runSub(
                input: accumulator, inputROI: window,
                instances: boxes, decodeHash: prefixHash,
                metal: metal, layerID: adjustment.id)

            // L021 layer-dimension assertions (resident): this layer's
            // entry geometry is ITS OWN sub-run's stamp — window-shaped,
            // never borrowed from the base walk.
            if let first = layerPipe.pieces.first {
                let entryDscIn = first.state.dscIn
                let entryBufIn = layerPipe.bufInROI.first
                precondition(
                    entryDscIn.width == entryBufIn?.width
                        && entryDscIn.height == entryBufIn?.height,
                    "L021: layer '\(adjustment.name)' entry dscIn != its own bufInROI.first")
                precondition(
                    entryBufIn?.width == window.width && entryBufIn?.height == window.height,
                    "L021: layer '\(adjustment.name)' entry ROI deviates from the negotiated composite window (\(String(describing: entryBufIn)) vs \(window))")
            }
            // Cross-layer ROI consistency (the negotiated-ROI precondition
            // pattern, applied across legs): identity-ROI layer chains end
            // exactly on the window.
            if let lastROI = layerPipe.levelROI.last {
                precondition(
                    lastROI.width == window.width && lastROI.height == window.height
                        && lastROI.x == window.x && lastROI.y == window.y,
                    "composite window violated by layer '\(adjustment.name)': \(lastROI) vs \(window)")
            }
            precondition(
                layerPlane.width == window.width && layerPlane.height == window.height,
                "layer '\(adjustment.name)' plane \(layerPlane.width)x\(layerPlane.height) != window \(window.width)x\(window.height)")

            // isVisible=false: still PROCESSED (sub-run above — its chain
            // planes stay warm) but SKIPPED at composite (no blend, no
            // prefix fold — C_k ≡ C_prev content and hash).
            guard adjustment.isVisible else {
                layerStats.append(LayerCompositeLayerStats(
                    layerID: adjustment.id, run: runStats, prefixHit: false))
                continue
            }

            // Degenerate blend: C_k = C_prev·(1−op) + L_k·op. The prefix
            // key folds chain ⊕ blend-triple ⊕ (REAL) mask-version hash —
            // a mask edit flips ONLY the prefix + the mask plane while the
            // layer's chain planes stay cached (T6 incremental semantics).
            let maskHash = adjustment.mask?.stableHash() ?? 0
            let tripleHash = blendTripleHash(
                opacity: adjustment.opacity, blendMode: adjustment.blendMode,
                blendOptions: adjustment.blendOptions, maskHash: maskHash)
            let chainHash = layerPipe.levelHash.last ?? basePipe.decodeParamsHash
            prefixHash = fold(fold(prefixHash, chainHash), tripleHash)
            let prefixKey = PipeCacheKey(
                imageID: imageID, pipeType: resolution,
                position: PipeCacheKey.compositePosition,
                upstreamHash: prefixHash, roi: window, layerID: adjustment.id)
            let planeBytes = window.width * window.height * WorkingSpace.bytesPerPixel

            // ── The MASK leg (plan 06-04 T5): the THREE payload classes
            // (drawn ⊗ parametric ⊓ raster) assemble into ONE effective
            // plane through MaskCombiner, cached at the mask-version key.
            // nil = the constant-1 uniform path. Raster loading needs the
            // sidecar's masks directory (nil → the documented degrade).
            var maskPlane: (any MTLTexture)?
            var maskDegradeReason: String?
            if let mask = adjustment.mask, mask.hasAnyPayload {
                let (plane, _, reason) = try await MaskCombiner.effectivePlane(
                    spec: mask, layerOpacity: max(0, min(1, adjustment.opacity)),
                    window: window, below: accumulator, top: layerPlane,
                    mapper: geometryMapper, metal: metal, cache: cache,
                    imageID: imageID, pipeType: resolution, layerID: adjustment.id,
                    maskDirectory: maskDirectory,
                    upstreamHash: prefixHash) // GUI-21: parametric masks SAMPLE
                    // the accumulator — the key must fold its identity or a
                    // below-edit reuses a stale parametric plane.
                maskPlane = plane
                maskDegradeReason = reason
            }
            if let reason = maskDegradeReason {
                AppError.logger.error(
                    "raster mask degraded for layer '\(adjustment.name, privacy: .public)': \(reason, privacy: .public)")
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
                let triple = BlendTriple(
                    opacity: adjustment.opacity, mode: adjustment.blendMode,
                    reverse: adjustment.blendOptions.contains(.reverse))
                let cached = try await cache.plane(for: prefixKey, byteCount: planeBytes) {
                    [belowBox, topBox, maskBox, triple] in
                    try await Self.blend(
                        below: belowBox.texture, top: topBox.texture,
                        mask: maskBox?.texture, triple: triple, metal: metal)
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
                    triple: BlendTriple(
                        opacity: adjustment.opacity, mode: adjustment.blendMode,
                        reverse: adjustment.blendOptions.contains(.reverse)),
                    metal: metal)
                blendPasses += 1
            }
            accumulator = blended

            // D-06-CONTEXT-8 cold-layer leg: drop this layer's chain-output
            // lines after the blend (prefixes survive). The hot layer keeps
            // its chain planes.
            if !policy.cachesAllLayerOutputs && adjustment.id != hotLayerID {
                await cache.invalidateLayer(imageID: imageID, layerID: adjustment.id)
            }

            layerStats.append(LayerCompositeLayerStats(
                layerID: adjustment.id, run: runStats, prefixHit: prefixHit))
        }

        // ── C. terminal segment (the display tail, policy unchanged).
        var terminalStats: RenderPipeline.PipeRunStats?
        var output = accumulator
        if !terminalChain.isEmpty {
            let terminalPipe = PixelPipe(resolution: resolution, cache: cache)
            terminalPipe.imageID = imageID
            terminalPipe.layerStack = layerStack // baseLayer.id namespace
            // GUI-21 (2026-09-24): the terminal's hash seed is the FINAL
            // composite prefix identity — NOT the bare decode hash. The
            // decode-only seed made the terminal's cache lines blind to
            // the accumulator: ANY upstream content edit (base param,
            // lower layer, mask, opacity, stroke) left the colorout/gamma
            // keys unchanged → stale HIT → the composite returned the OLD
            // display plane (the viewport-froze family: base-chain param
            // commits rendered max|Δ|=0 with history/sidecar correct).
            let (terminalPlane, stats) = try await terminalPipe.runSub(
                input: accumulator, inputROI: window,
                instances: terminalChain, decodeHash: prefixHash,
                metal: metal, layerID: layerStack.baseLayer.id)
            output = terminalPlane
            terminalStats = stats
        }

        return LayerCompositeResult(
            output: output, window: window, baseStats: baseStats,
            layerStats: layerStats, terminalStats: terminalStats,
            blendPasses: blendPasses)
    }

    /// The blend-triple VALUE face (06-07: both layer kinds blend through
    /// one signature — the layer object no longer crosses into the kernel
    /// dispatch or its cache closure).
    struct BlendTriple: @unchecked Sendable {
        let opacity: Float
        let mode: BlendMode
        let reverse: Bool
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
        triple: BlendTriple,
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
            opacity: max(0, min(1, triple.opacity)),
            blendMode: triple.mode,
            reverse: triple.reverse,
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

    // MARK: - 06-07: the retouch ROI extension seam

    /// The entry-frame size at the run's scale (the `PixelPipe.run`
    /// scale-at-entry math, mirrored for the pre-run mapper construction).
    private static func entryFrameSize(
        image: DecodedImage, longEdge: Int?, resolution: PipeResolution
    ) -> SIMD2<Double> {
        let fullWidth = max(Int(image.ciImage.extent.width), 1)
        let fullHeight = max(Int(image.ciImage.extent.height), 1)
        let targetLongEdge = longEdge ?? resolution.defaultLongEdge
        if let targetLongEdge, targetLongEdge >= 1 {
            let scale = min(
                CGFloat(targetLongEdge) / CGFloat(fullWidth),
                CGFloat(targetLongEdge) / CGFloat(fullHeight),
                1.0)
            return SIMD2(
                Double((CGFloat(fullWidth) * scale).rounded()),
                Double((CGFloat(fullHeight) * scale).rounded()))
        }
        return SIMD2(Double(fullWidth), Double(fullHeight))
    }

    /// The hint widened by every enabled+visible retouch layer's stroke
    /// SOURCE ∪ TARGET extent (composite px via the content-anchored
    /// mapper). The pipe walk clamps the union into the frame; when no
    /// stroke exits the hint this returns the hint verbatim (zero change
    /// for retouch-free stacks — D-06-07-T2-2).
    static func expandedHint(
        hint: ROI, layerStack: LayerStack, baseChain: [any ModuleBoxing],
        image: DecodedImage, longEdge: Int?, resolution: PipeResolution
    ) -> ROI {
        let retouchLayers = layerStack.adjustmentLayers.compactMap { $0 as? RetouchLayer }
        guard retouchLayers.contains(where: { $0.enabled && $0.isVisible && !$0.strokes.isEmpty })
        else { return hint }
        let frame = entryFrameSize(image: image, longEdge: longEdge, resolution: resolution)
        let mapper = GeometryPointMapper.compose(boxes: baseChain, frameSize: frame)
        var extent: ROI?
        for layer in retouchLayers where layer.enabled && layer.isVisible {
            guard let e = RetouchEngine.strokeExtent(strokes: layer.strokes, mapper: mapper)
            else { continue }
            let x0 = Int(e.min.x.rounded(.down)), y0 = Int(e.min.y.rounded(.down))
            let x1 = Int(e.max.x.rounded(.up)), y1 = Int(e.max.y.rounded(.up))
            let r = ROI(
                x: x0, y: y0,
                width: max(1, x1 - x0), height: max(1, y1 - y0),
                scale: hint.scale)
            extent = extent?.union(r) ?? r
        }
        guard let extent else { return hint }
        return hint.union(extent)
    }
}
