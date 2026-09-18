import Metal
import os

/// `@unchecked Sendable` box for the one texture a cache miss closure needs
/// (the pipe's input plane). `MTLTexture` is a non-Sendable protocol handle;
/// the wrapper carries the ownership contract — the plane is built once by
/// the pipe run and only read afterwards (write-once-then-readonly, lock #7).
internal struct TextureBox: @unchecked Sendable {
    let texture: any MTLTexture
}

/// The image-processing pipeline (FOUND-03/04) — the recursive Darktable
/// pixelpipe with the per-module per-ROI cache and the hash-chain hit fast
/// path (SC#2's mechanism, `pixelpipe_hb.c:1838-1999`).
///
/// **Recursion (processRec):** walk from the chain top toward the input —
/// disabled pieces are skipped with no cache-key step and no process call
/// (`:1875-1881`); an enabled piece probes `PipeCache` at its position
/// FIRST (`:1892-1921` hit fast path — upstream zero-computation); on miss
/// the closure recurses one level up, then executes the module into a fresh
/// plane which the cache stores. `upstreamHash` threads incrementally
/// (O(1)/level): position 0 (the input plane) is keyed on `decodeParamsHash`
/// alone, each enabled module folds its `paramsHash` in below its own
/// position. Changing module m's params flips exactly the keys at positions
/// ≥ m — invalidation semantics for free from the chain (SC#2).
///
/// **Per-pipeType policy (checkpoint lock #4):** PREVIEW/THUMBNAIL cache
/// every module plane; FULL caches the input plane + the final output and
/// ping-pongs intermediates through pipe-private scratch (spike-b §4: three
/// 100MP planes ≈ 4.7GB busts the budget); EXPORT caches nothing (Darktable
/// parity, `pixelpipe_hb.h:346-355`).
///
/// **decodeParamsHash (§1.3 gotcha):** folded into position-0 keys from day
/// one, so a Phase 3 WB change that re-decodes invalidates EVERYTHING, not
/// just the input plane — no silent cache staleness.
///
/// **Layers (L005):** `layerStack` is held from the Phase 1 shape onward;
/// the Phase 6 composite attaches here without changing this file's pipe
/// walk contract.
///
/// **Concurrency:** `@unchecked Sendable` carries the ownership contract —
/// one pipe run is driven by ONE task (the cache's `make` closures run
/// inside that task's suspension tree); nothing else touches the pipe.
internal final class PixelPipe: @unchecked Sendable {

    internal struct Piece {
        let box: any ModuleBoxing
        var state: IOPiece
    }

    /// The layer stack being processed (D-03a: layer-aware from line one).
    internal var layerStack: LayerStack?

    let resolution: PipeResolution
    let cache: PipeCache

    /// One piece per module instance, v50-ordered (iopOrder, multiPriority).
    internal var pieces: [Piece] = []

    /// FNV-1a over `(decoderVersionUsed, RAWTechnicalParams JSON)` — mixed
    /// into position-0 keys (§1.3). Computed once per pipe run.
    internal var decodeParamsHash: UInt64 = StableHash.fnvOffsetBasis

    /// Cache namespace anchor (the sidecar-persisted image UUID).
    internal var imageID: UUID = UUID()

    /// Highest ENABLED index — that module's output is the pipe's final
    /// output (cached even in FULL mode). -1 = everything disabled.
    internal var topEnabledPosition = -1

    /// Pipe-private ping-pong scratch (FULL/EXPORT intermediates) — NEVER
    /// cached, never handed out.
    private var scratchPlanes: [any MTLTexture] = []
    private var scratchFlip = false

    /// SC#2 instrumentation: process dispatches this run.
    internal private(set) var planesRendered = 0

    /// The decoded source for this run (base-case input plane builder).
    private var decodedImage: DecodedImage?

    internal init(resolution: PipeResolution, cache: PipeCache) {
        self.resolution = resolution
        self.cache = cache
    }

    /// Plane byte cost at the working format (FOUND-02 float32 RGBA).
    private static func planeBytes(_ roi: ROI) -> Int {
        roi.width * roi.height * WorkingSpace.bytesPerPixel
    }

    /// One fold of the upstream chain: `seed` ⊕ `paramsHash` (raw little-
    /// endian UInt64 bytes — the SAME encoding `PipeHash.upstream` uses, so
    /// the incremental thread and the test-side recompute agree).
    private static func chain(_ seed: UInt64, _ paramsHash: UInt64) -> UInt64 {
        var hash = paramsHash
        return withUnsafeBytes(of: &hash) { StableHash.combine(seed, $0) }
    }

    /// Allocate a fresh output plane at the ROI (shared storage, UMA —
    /// METAL-4; shaderRead+shaderWrite during processing, read-only after).
    private static func allocatePlane(roiOut: ROI, metal: MetalContext) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: max(roiOut.width, 1),
            height: max(roiOut.height, 1),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(
                roiOut.width * roiOut.height * WorkingSpace.bytesPerPixel
            )
        }
        return texture
    }

    /// Next ping-pong scratch plane at the ROI (FULL/EXPORT intermediates).
    private func nextScratchPlane(roiOut: ROI, metal: MetalContext) throws -> any MTLTexture {
        if scratchPlanes.count < 2 {
            let texture = try Self.allocatePlane(roiOut: roiOut, metal: metal)
            scratchPlanes.append(texture)
            return texture
        }
        scratchFlip.toggle()
        return scratchPlanes[scratchFlip ? 1 : 0]
    }

    /// Run the pipe over a decoded image with the given (unsorted) module
    /// instances; returns the final plane + this run's stats delta.
    /// `longEdge` is reserved for Plan 02-03's scale-at-entry (this plan
    /// renders the full extent — pass-through era).
    internal func run(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        metal: MetalContext,
        longEdge: Int?
    ) async throws -> (output: any MTLTexture, stats: RenderPipeline.PipeRunStats) {
        // Base layer invariant (D-03a) — L005 field preserved.
        if layerStack == nil {
            layerStack = LayerStack(baseLayer: BackgroundLayer())
        }

        // v50 order: (iopOrder, multiPriority) — Darktable's module order.
        pieces = instances
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            .map { Piece(box: $0, state: $0.makeRunPiece()) }
        topEnabledPosition = pieces.lastIndex(where: { $0.box.enabled }) ?? -1
        decodedImage = image
        planesRendered = 0

        // §1.3: decodeParamsHash = FNV(decoderVersion ⊕ rawTech JSON) — the
        // position-0 seed. Recompute per run; stable via StableHash.
        var seed = StableHash.hash(image.decoderVersionUsed.rawValue)
        let techBytes = (try? JSONEncoder().encode(image.rawTech)) ?? Data()
        seed = techBytes.withUnsafeBytes { StableHash.combine(seed, $0) }
        decodeParamsHash = seed

        let statsBefore = await cache.stats
        let final = try await processRec(
            position: pieces.count - 1,
            roiOut: ROI(), // stamped by the base case from the decoded extent
            upstreamHash: decodeParamsHash,
            metal: metal
        )
        let statsDelta = (await cache.stats) - statsBefore
        return (
            final.texture,
            RenderPipeline.PipeRunStats(
                hits: statsDelta.hits,
                misses: statsDelta.misses,
                planesRendered: planesRendered
            )
        )
    }

    /// The recursive walk (`pixelpipe_hb.c:1838` direct translation).
    ///
    /// - Parameter position: chain index of the module whose OUTPUT is
    ///   requested; -1 = the input plane (cache line 0).
    /// - Parameter upstreamHash: running FNV chain over the ENABLED pieces'
    ///   `paramsHash` at positions < `position`, seeded with
    ///   `decodeParamsHash` — threaded incrementally, O(1)/level.
    internal func processRec(
        position: Int,
        roiOut: ROI,
        upstreamHash: UInt64,
        metal: MetalContext
    ) async throws -> PipeCache.CachedPlane {
        // ═══ BASE (position -1): the input plane — cache line 0, keyed on
        // decodeParamsHash ONLY (pixelpipe_hb.c:1930-1999 entry; this plan
        // renders the full extent from the decoded CIImage, scale-at-entry
        // is Plan 02-03). EXPORT bypasses the cache entirely (lock #4).
        guard position >= 0 else {
            let roi = ROI(
                width: Int(decodedImage?.ciImage.extent.width ?? 0),
                height: Int(decodedImage?.ciImage.extent.height ?? 0),
                scale: 1.0
            )
            if resolution == .export {
                guard let image = decodedImage else {
                    throw MetalError.deviceUnavailable
                }
                planesRendered += 1
                let texture = try await metal.renderToTexture(image.ciImage)
                return PipeCache.CachedPlane(texture: texture, byteCount: 0, lastHit: .now)
            }
            return try await cache.plane(
                for: PipeCacheKey(
                    imageID: imageID, pipeType: resolution, position: 0,
                    upstreamHash: upstreamHash, roi: roi
                ),
                byteCount: Self.planeBytes(roi)
            ) { [self] in
                // Miss closure: build the input plane ONCE; hits skip this
                // entirely (no decode-leg render on a cache hit).
                guard let image = decodedImage else {
                    throw MetalError.deviceUnavailable
                }
                planesRendered += 1
                let texture = try await metal.renderToTexture(image.ciImage)
                return texture
            }
        }

        let piece = pieces[position]

        // (a) DISABLED SKIP — no cache-key step, no process call
        // (Darktable `_skip_piece_on_tags`, pixelpipe_hb.c:1875-1881).
        guard piece.box.enabled else {
            return try await processRec(
                position: position - 1,
                roiOut: roiOut,
                upstreamHash: upstreamHash, // disabled pieces fold NOTHING in
                metal: metal
            )
        }

        // (b) cache line for this module's OUTPUT: position + 1 (position 0
        // is the input plane), upstreamHash covers enabled pieces BELOW us.
        let key = PipeCacheKey(
            imageID: imageID,
            pipeType: resolution,
            position: position + 1,
            upstreamHash: upstreamHash,
            roi: roiOut
        )
        let isFinalOutput = position == topEnabledPosition
        let box = piece.box

        // (f) PER-PIPETYPE POLICY (lock #4): PREVIEW/THUMBNAIL cache every
        // plane; FULL caches input + final only (intermediates ping-pong);
        // EXPORT caches nothing.
        if resolution.cachesIntermediatePlanes || (isFinalOutput && resolution == .full) {
            return try await cache.plane(for: key, byteCount: Self.planeBytes(roiOut)) { [self] in
                // (d) MISS CLOSURE — recurse upstream, then execute.
                let upstream = try await processRec(
                    position: position - 1,
                    roiOut: roiOut,
                    upstreamHash: Self.chain(upstreamHash, box.paramsHash),
                    metal: metal
                )
                // Risk #7 invariant: pass-through era ROI identity — the
                // input plane must match the ROI we are producing (Phase 4's
                // ROI negotiation replaces this assert with real geometry).
                assert(
                    upstream.texture.width == roiOut.width
                        && upstream.texture.height == roiOut.height,
                    "pass-through-era ROI identity violated"
                )
                let output = try Self.allocatePlane(roiOut: roiOut, metal: metal)
                try await box.processErased(
                    input: upstream.texture, output: output,
                    roiIn: roiOut, roiOut: roiOut,
                    piece: &pieces[position].state, metal: metal
                )
                planesRendered += 1
                return output
            }
        }

        // Uncached leg (FULL intermediates / all EXPORT positions):
        // ping-pong through pipe-private scratch — never stored.
        let upstream = try await processRec(
            position: position - 1,
            roiOut: roiOut,
            upstreamHash: Self.chain(upstreamHash, box.paramsHash),
            metal: metal
        )
        assert(
            upstream.texture.width == roiOut.width
                && upstream.texture.height == roiOut.height,
            "pass-through-era ROI identity violated"
        )
        // The FINAL output (FULL only — EXPORT finals are also uncached)
        // must not alias scratch the next run overwrites: allocate fresh.
        let output: any MTLTexture =
            if isFinalOutput && resolution == .full {
                try Self.allocatePlane(roiOut: roiOut, metal: metal)
            } else {
                try nextScratchPlane(roiOut: roiOut, metal: metal)
            }
        try await box.processErased(
            input: upstream.texture, output: output,
            roiIn: roiOut, roiOut: roiOut,
            piece: &pieces[position].state, metal: metal
        )
        planesRendered += 1
        return PipeCache.CachedPlane(texture: output, byteCount: 0, lastHit: .now)
    }
}

/// The app ↔ Core render bridge (Plan 04): `PixelPipe` itself is internal
/// to Core, so the app calls THESE entry points.
public enum RenderPipeline {

    /// Signpost category for the pipe leg of the vertebra (D-31, visible in
    /// Instruments next to "decode" and "render").
    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer", category: "pixelpipe"
    )

    /// Pipe-run stats (SC#2 verification channel + 02-03 coordinator /
    /// 02-04 golden harness consumer): THIS RUN's hit/miss delta and the
    /// number of planes actually rendered (dispatches + decode leg).
    public struct PipeRunStats: Sendable {
        public var hits: Int
        public var misses: Int
        public var planesRendered: Int

        public init(hits: Int, misses: Int, planesRendered: Int) {
            self.hits = hits
            self.misses = misses
            self.planesRendered = planesRendered
        }
    }

    /// Run the Phase 1 no-op pixelpipe over `image` with `layerStack` and
    /// return the display texture (float32 linear Rec2020, FOUND-02).
    /// Delegates to a pipe with EMPTY instances — identical behavior to the
    /// Phase 1 shape (the base-layer invariant + a `renderToTexture` leg).
    /// `layerStack` may be nil — the pipe installs a default
    /// `BackgroundLayer` stack (D-03a invariant).
    public static func render(
        image: DecodedImage,
        layerStack: LayerStack?,
        metal: MetalContext
    ) async throws -> sending any MTLTexture {
        let interval = signposter.beginInterval("pixelpipe", id: signposter.makeSignpostID())
        defer { signposter.endInterval("pixelpipe", interval) }
        let pipe = PixelPipe(resolution: .preview, cache: PipeCache()) // throwaway: no-op path keeps no state
        pipe.layerStack = layerStack
        let (texture, _) = try await pipe.run(image: image, instances: [], metal: metal, longEdge: nil)
        return texture
    }

    /// Run the REAL pixelpipe: decoded image → input plane → v50-ordered
    /// module chain (per-module per-ROI cache, hash-chain fast path) →
    /// output plane. **The app/tests entry for plan 02-02 onward** — 02-03's
    /// coordinator and 02-04's golden harness consume `PipeRunStats`.
    ///
    /// - Parameters:
    ///   - imageID: the image's stable UUID (sidecar anchor) — the cache
    ///     namespace; pass the SAME UUID across runs to prove hits.
    ///   - cache: INJECTED pipe cache (tests share one actor across runs).
    ///   - longEdge: reserved for Plan 02-03's scale-at-entry; nil/ignored
    ///     in this plan (full-extent render, pass-through era).
    public static func process(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        imageID: UUID,
        resolution: PipeResolution,
        cache: PipeCache,
        metal: MetalContext,
        longEdge: Int? = nil
    ) async throws -> (any MTLTexture, PipeRunStats) {
        let interval = signposter.beginInterval("pixelpipe", id: signposter.makeSignpostID())
        defer { signposter.endInterval("pixelpipe", interval) }
        let pipe = PixelPipe(resolution: resolution, cache: cache)
        pipe.imageID = imageID
        return try await pipe.run(
            image: image, instances: instances, metal: metal, longEdge: longEdge
        )
    }
}
