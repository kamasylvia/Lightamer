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
/// **Tiling (D-20 scaffolding):** the walk is deliberately WHOLE-PLANE —
/// 100MP float32 fits unified memory at pipe level (spike-b). When Phase
/// 5's denoise working sets need tile-wise execution, `TilingPlan.tiles`
/// supplies the grid and the recursion gains a tile driver here.
/// Phase 5: engage `TilingPlan` inside `processRec` (tile-wise recursion +
/// per-tile cache keys + halo stitching).
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

    /// Per-level upstream hashes: `levelHash[i]` = decodeParamsHash ⊕ every
    /// ENABLED module's `paramsHash` at indices ≤ i (disabled modules fold
    /// NOTHING in). Line i+1 (module i's output) keys on `levelHash[i]`, so
    /// a param change at module m flips EXACTLY the lines ≥ m — SC#2's
    /// invalidation semantics. Precomputed in `run()` (O(n) once) instead of
    /// threaded through the recursion.
    internal var levelHash: [UInt64] = []

    /// Forward-negotiated geometry (04-01; dt `get_dimensions` mirror,
    /// `pixelpipe_hb.c:3368-3405`): `bufInROI[i]` = piece i's input ROI
    /// (= dt `piece->buf_in`), `levelROI[i]` = piece i's OUTPUT ROI
    /// (= dt `piece->buf_out`). Walked in `run()` from the entry ROI:
    /// enabled pieces drive `modifyROIOutErased`, disabled pieces pass
    /// through (dt `:3378-3384`). All-identity modules → every entry
    /// equals the entry ROI (pass-through era byte-identical).
    internal var bufInROI: [ROI] = []
    internal var levelROI: [ROI] = []

    /// Cache namespace anchor (the sidecar-persisted image UUID).
    internal var imageID: UUID = UUID()

    /// The LAYER namespace for this run's cache keys (Plan 06-01 T3):
    /// base/terminal sub-runs stamp `baseLayer.id` (NDE-1 anchor); a layer
    /// sub-run (the `runSub` seam) stamps the layer's own UUID. The default
    /// is the fixed base sentinel — Phase 2-5 paths (no stack) keep today's
    /// key space byte-identical.
    internal private(set) var cacheLayerID: UUID = PipeCacheKey.baseLayerSentinelID

    /// The sub-run seam (Plan 06-01 T4): when set (by `runSub`), the
    /// recursion's BASE case returns this driver-managed plane instead of
    /// rendering a decode — the composite accumulator. Never cached; the
    /// caller owns its lifecycle. `run()` clears it.
    internal private(set) var subRunInput: (any MTLTexture)?

    /// True once THIS pipe auto-installed its default stack (no caller
    /// stack ever arrived). The auto-install is EPHEMERAL for cache naming:
    /// its fresh BackgroundLayer UUID must never enter the keys — every
    /// subsequent run on this pipe keeps the base sentinel (a repeat `run`
    /// would otherwise see `layerStack != nil` and stamp a new namespace
    /// per run, destroying the hit fast path).
    private var usesDefaultStack = false

    /// Entry-ROI override (04-01-T4 `roiHint`): when set, `run()` intersects
    /// it with the scale-at-entry ROI and negotiates that sub-window
    /// instead of the full frame. Test/probe seam only — nil in production.
    internal var entryROIHInt: ROI?

    /// Highest ENABLED index — that module's output is the pipe's final
    /// output (cached even in FULL mode). -1 = everything disabled.
    internal var topEnabledPosition = -1

    /// Decoded-frame ROI at entry scale (04-01-T4): the backward-negotiation
    /// clamp bound (halo wings may exceed the hinted/forward window but
    /// never the frame). Set in `run()` alongside `roi`.
    internal var frameROI: ROI = ROI()

    /// The ROI this pipe instance is running at — set by `run`/`runIfDirty`/
    /// `runOnce` from the image extent + the resolution's long edge (scale-
    /// at-entry, `pixelpipe_hb.c:1930-1999` mirror: the INPUT plane is
    /// rendered at the target size, modules see `roi.scale` but stay
    /// geometry-blind in the pass-through era). `scale < 1.0` on
    /// PREVIEW/THUMBNAIL runs; exactly 1.0 on FULL.
    internal private(set) var roi: ROI = ROI()

    /// THUMBNAIL lazy lifecycle (`PipeResolution.isLazy`): a fresh pipe is
    /// dirty (the first fetch renders); the coordinator re-arms the flag on
    /// param change WITHOUT rendering; `runIfDirty` renders only when armed
    /// and disarms itself. PREVIEW/FULL ignore the flag (their runs are
    /// driven explicitly).
    internal var isDirty = true

    /// Pipe-private ping-pong scratch (FULL/EXPORT intermediates) — NEVER
    /// cached, never handed out.
    private var scratchPlanes: [any MTLTexture] = []
    private var scratchFlip = false

    // ── Tile driver state (03-05-T6; TilingPlan's first engagement) ──

    /// Per-tile AUXILIARY working-set budget (the module's
    /// `tileWorkingSetBytesPerPixel` × tile area, D-C1 accounting: the
    /// toneequal auxiliary planes must stay an order below the pipe
    /// budget instead of the whole-plane ~1.9GB). Injected in tests to
    /// force tiling on small planes.
    internal var maxTileWorkingBytes: Int = 512 << 20

    /// The tile-execution scratch planes (read rect + write rect), cached
    /// per size — the tile size is uniform across a run's grid.
    private var tileReadSize = (width: 0, height: 0)
    private var tileReadPlane: (any MTLTexture)?
    private var tileWritePlane: (any MTLTexture)?

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

    /// Plane byte cost at an explicit pixel format (the display-tail plane
    /// is 4 bytes/px — `GammaModule.outputPixelFormat` — everything else
    /// stays float32).
    private static func planeBytes(_ roi: ROI, pixelFormat: MTLPixelFormat) -> Int {
        roi.width * roi.height * Self.bytesPerPixel(of: pixelFormat)
    }

    /// The two formats the pipe produces (exhaustive — FOUND-02 interior +
    /// the 02-04 display tail).
    private static func bytesPerPixel(of format: MTLPixelFormat) -> Int {
        switch format {
        case GammaModule.outputPixelFormat: return 4
        default: return WorkingSpace.bytesPerPixel
        }
    }

    /// Terminal-tail policy (Plan 02-04-04, research §3.3): when the TOP
    /// enabled module is `gamma`, its output plane is the DISPLAY HANDOFF —
    /// allocated `.bgra8Unorm` (GammaModule.outputPixelFormat), NOT
    /// float32. Cached planes at positions < gamma stay float32 linear
    /// (reusable across screens — a display change re-runs only the
    /// colorout+gamma segment). FULL gets the same treatment: its output
    /// is also display-format when run for 100% viewing.
    private func tailPixelFormat(at position: Int) -> MTLPixelFormat {
        if position == topEnabledPosition,
           pieces.indices.contains(position),
           pieces[position].box.opName == GammaModule.opName {
            return GammaModule.outputPixelFormat
        }
        return WorkingSpace.pixelFormat
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
    /// `pixelFormat` defaults to the FOUND-02 working format; the display
    /// tail passes `GammaModule.outputPixelFormat`.
    private static func allocatePlane(
        roiOut: ROI,
        metal: MetalContext,
        pixelFormat: MTLPixelFormat = WorkingSpace.pixelFormat
    ) throws -> any MTLTexture {
        let bytesPerPx = bytesPerPixel(of: pixelFormat)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: max(roiOut.width, 1),
            height: max(roiOut.height, 1),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(
                roiOut.width * roiOut.height * bytesPerPx
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

    // MARK: - Tile driver (Plan 03-05-T6)

    /// Whether THIS module execution must be tiled: FULL resolution only,
    /// module-declared auxiliary working set above the tile budget, and a
    /// float32 tail (the blit copy path requires matching formats; a
    /// toneequal-sized module at the gamma tail does not occur — the
    /// terminal trio follows every tone module).
    private func tileNeeded(
        box: any ModuleBoxing, roiOut: ROI, piece: IOPiece,
        outputFormat: MTLPixelFormat
    ) -> Bool {
        // The blit driver requires matching formats (float32 in/out).
        guard outputFormat == WorkingSpace.pixelFormat else { return false }
        guard resolution == .full else { return false }
        let bytesPerPixel = box.tileWorkingSetBytesPerPixelErased(piece: piece)
        guard bytesPerPixel > 0 else { return false }
        guard box.tileHaloErased(roi: roiOut, piece: piece) > 0 else { return false }
        return roiOut.width * roiOut.height * bytesPerPixel > maxTileWorkingBytes
    }

    /// Execute the module TILE-WISE over `input` into `output` (same size,
    /// float32): the upstream plane is rendered ONCE by the caller (the
    /// recursion above), then `TilingPlan.tiles` supplies the output grid;
    /// each tile's read rect is the tile widened by the module's halo, the
    /// module runs at read-rect extent (whole-plane semantics — the halo
    /// data is real, so border clamping matches the untiled run), and the
    /// tile's sub-rect is blitted into the plane. The module never knows
    /// it was tiled.
    private func executeTiled(
        box: any ModuleBoxing,
        piece: inout IOPiece,
        input: any MTLTexture,
        output: any MTLTexture,
        roiOut: ROI,
        metal: MetalContext
    ) async throws {
        let halo = box.tileHaloErased(roi: roiOut, piece: piece)
        let bytesPerPixel = box.tileWorkingSetBytesPerPixelErased(piece: piece)
        let tiles = TilingPlan.tiles(
            forWidth: roiOut.width, height: roiOut.height,
            maxTileBytes: maxTileWorkingBytes,
            bytesPerPixel: bytesPerPixel,
            overlap: halo
        )
        for tile in tiles where tile.width > 0 && tile.height > 0 {
            // The read rect: the output tile widened by the halo, clamped.
            let rx = max(0, tile.x - halo)
            let ry = max(0, tile.y - halo)
            let rw = min(input.width - rx, tile.width + (tile.x - rx) + halo)
            let rh = min(input.height - ry, tile.height + (tile.y - ry) + halo)

            // Uniform-size scratch (allocated once per run).
            if tileReadSize.width != rw || tileReadSize.height != rh {
                tileReadPlane = try Self.allocatePlane(
                    roiOut: ROI(width: rw, height: rh, scale: roiOut.scale), metal: metal)
                tileWritePlane = try Self.allocatePlane(
                    roiOut: ROI(width: rw, height: rh, scale: roiOut.scale), metal: metal)
                tileReadSize = (rw, rh)
            }
            guard let tileIn = tileReadPlane, let tileOut = tileWritePlane else {
                throw MetalError.bufferAllocationFailed(rw * rh * 16)
            }

            // input[readRect] → tileIn (blit, same format).
            try await blit(
                from: input,
                sourceOrigin: MTLOrigin(x: rx, y: ry, z: 0),
                size: MTLSize(width: rw, height: rh, depth: 1),
                to: tileIn, metal: metal)

            // The module executes at read-rect extent — the piece
            // geometry (dscIn) stays the PLANE extent, so whole-image
            // radius semantics hold (toneequal's dt piece->iwidth analog).
            let readROI = ROI(
                x: rx, y: ry, width: rw, height: rh, scale: roiOut.scale)
            try await box.processErased(
                input: tileIn, output: tileOut,
                roiIn: readROI, roiOut: readROI,
                piece: &piece, metal: metal)

            // tileOut[tile sub-rect] → output[tile rect].
            try await blit(
                from: tileOut,
                sourceOrigin: MTLOrigin(x: tile.x - rx, y: tile.y - ry, z: 0),
                size: MTLSize(width: tile.width, height: tile.height, depth: 1),
                to: output,
                destinationOrigin: MTLOrigin(x: tile.x, y: tile.y, z: 0),
                metal: metal)
        }
    }

    /// Negotiated-ROI tile driver (04-01): the tile grid spans the OUTPUT
    /// plane (`roiOut`), but read rects address the NEGOTIATED input plane
    /// (`roiIn`-sized — wider than output for halo-class modules). Tile
    /// `(x, y)` is output coords; the input sampling window is the same
    /// tile shifted by the ROI offset `(roiOut − roiIn)` and widened by
    /// the module halo, clamped to the input plane. Offsets cancel for
    /// identity modules (`roiIn == roiOut`), reducing exactly to
    /// `executeTiled`. `dscIn` stays the forward-pass plane extent
    /// (whole-image radius semantics — the tile must not change it).
    private func executeTiledNegotiated(
        box: any ModuleBoxing,
        piece: inout IOPiece,
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) async throws {
        let halo = box.tileHaloErased(roi: roiOut, piece: piece)
        let bytesPerPixel = box.tileWorkingSetBytesPerPixelErased(piece: piece)
        let tiles = TilingPlan.tiles(
            forWidth: roiOut.width, height: roiOut.height,
            maxTileBytes: maxTileWorkingBytes,
            bytesPerPixel: bytesPerPixel,
            overlap: halo
        )
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        for tile in tiles where tile.width > 0 && tile.height > 0 {
            // Output tile → input sampling window (offset + halo, clamped).
            let rx = max(0, tile.x + dx - halo)
            let ry = max(0, tile.y + dy - halo)
            let rw = min(input.width - rx, tile.width + (tile.x + dx - rx) + halo)
            let rh = min(input.height - ry, tile.height + (tile.y + dy - ry) + halo)

            if tileReadSize.width != rw || tileReadSize.height != rh {
                tileReadPlane = try Self.allocatePlane(
                    roiOut: ROI(width: rw, height: rh, scale: roiOut.scale), metal: metal)
                tileWritePlane = try Self.allocatePlane(
                    roiOut: ROI(width: rw, height: rh, scale: roiOut.scale), metal: metal)
                tileReadSize = (rw, rh)
            }
            guard let tileIn = tileReadPlane, let tileOut = tileWritePlane else {
                throw MetalError.bufferAllocationFailed(rw * rh * 16)
            }

            try await blit(
                from: input,
                sourceOrigin: MTLOrigin(x: rx, y: ry, z: 0),
                size: MTLSize(width: rw, height: rh, depth: 1),
                to: tileIn, metal: metal)

            let readROI = ROI(
                x: rx, y: ry, width: rw, height: rh, scale: roiOut.scale)
            try await box.processErased(
                input: tileIn, output: tileOut,
                roiIn: readROI, roiOut: readROI,
                piece: &piece, metal: metal)

            try await blit(
                from: tileOut,
                sourceOrigin: MTLOrigin(x: tile.x + dx - rx, y: tile.y + dy - ry, z: 0),
                size: MTLSize(width: tile.width, height: tile.height, depth: 1),
                to: output,
                destinationOrigin: MTLOrigin(x: tile.x, y: tile.y, z: 0),
                metal: metal)
        }
    }

    /// A same-format texture-to-texture blit on its own command buffer
    /// (same-queue FIFO keeps it ordered against the neighboring compute
    /// dispatches; explicit endEncoding before commit — L008).
    private func blit(
        from source: any MTLTexture,
        sourceOrigin: MTLOrigin,
        size: MTLSize,
        to destination: any MTLTexture,
        destinationOrigin: MTLOrigin = MTLOrigin(x: 0, y: 0, z: 0),
        metal: MetalContext
    ) async throws {
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer() else {
            throw MetalError.deviceUnavailable
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: source, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: sourceOrigin, sourceSize: size,
            to: destination, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: destinationOrigin)
        blit.endEncoding()
        commandBuffer.commit()
    }

    /// Run the pipe over a decoded image with the given (unsorted) module
    /// instances; returns the final plane + this run's stats delta.
    ///
    /// Scale-at-entry (Plan 02-03-03): `longEdge` (or the resolution's
    /// `defaultLongEdge` for THUMBNAIL) sizes the INPUT plane — `roi.scale
    /// = target/fullExtent` and the base case renders the decoded CIImage
    /// at the target long edge in ONE pass (`renderToTexture(_:longEdge:)`).
    /// nil long edge + no resolution default (FULL) = full extent, scale 1.0.
    /// PREVIEW re-renders through plain `run` on every params change.
    internal func run(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        metal: MetalContext,
        longEdge: Int?
    ) async throws -> (output: any MTLTexture, stats: RenderPipeline.PipeRunStats) {
        // EXPORT is a Phase 11 seam — typed placeholder, never a fatalError
        // (D-25 / Plan 02-03-03).
        if resolution == .export {
            throw AppError.notImplemented("Phase 11")
        }

        // Base layer invariant (D03a) — L005 field preserved. The AUTO-
        // INSTALLED default stack (no caller stack) is ephemeral: its fresh
        // BackgroundLayer UUID must NOT enter the cache namespace (keys
        // would differ every run) — those runs keep the base sentinel.
        if layerStack == nil {
            layerStack = LayerStack(baseLayer: BackgroundLayer())
            usesDefaultStack = true
        }
        // Layer namespace stamp (06-01 T3): caller-provided real stacks key
        // their base / terminal planes on baseLayer.id; default-stack pipes
        // keep the sentinel forever.
        cacheLayerID =
            usesDefaultStack ? PipeCacheKey.baseLayerSentinelID
            : (layerStack?.baseLayer.id ?? PipeCacheKey.baseLayerSentinelID)
        // A plain run renders the decode — clear any sub-run input.
        subRunInput = nil

        // v50 order: (iopOrder, multiPriority) — Darktable's module order.
        prepareChain(
            instances: instances,
            decodeHash: HistoryHash.decodeParamsHash(for: image)
        )
        decodedImage = image

        let statsBefore = await cache.stats
        // Scale-at-entry ROI (Plan 02-03-03): the effective long edge is
        // the explicit `longEdge` (PREVIEW's D-C3 bucket) or the
        // resolution's `defaultLongEdge` (THUMBNAIL 360); none → full
        // extent at scale 1.0 (FULL). Downscale-only: images smaller than
        // the target render at native size.
        let fullWidth = max(Int(image.ciImage.extent.width), 1)
        let fullHeight = max(Int(image.ciImage.extent.height), 1)
        let targetLongEdge = longEdge ?? resolution.defaultLongEdge
        if let targetLongEdge, targetLongEdge >= 1 {
            let scale = min(
                CGFloat(targetLongEdge) / CGFloat(fullWidth),
                CGFloat(targetLongEdge) / CGFloat(fullHeight),
                1.0
            )
            roi = ROI(
                x: 0, y: 0,
                width: max(1, Int((CGFloat(fullWidth) * scale).rounded())),
                height: max(1, Int((CGFloat(fullHeight) * scale).rounded())),
                scale: Float(scale)
            )
        } else {
            roi = ROI(width: fullWidth, height: fullHeight, scale: 1.0)
        }
        frameROI = roi // pre-hint full entry frame = the clamp bound
        // 04-01-T4 `roiHint`: intersect the caller-requested sub-window
        // with the entry ROI (clamped — hints outside the frame collapse
        // to the entry). The forward walk + recursion then negotiate the
        // hint as the pipeline's final output ROI.
        if let hint = entryROIHInt {
            roi = hint.clamped(to: roi)
        }
        // Forward ROI pre-computation (04-01; dt get_dimensions,
        // `pixelpipe_hb.c:3368-3405`) — the walk body shared with `runSub`
        // (only the entry-ROI derivation differs between the two shapes).
        let walked = forwardWalk(entry: roi, frame: frameROI)
        let final = try await processRec(
            position: pieces.count - 1,
            roiOut: walked,
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

    /// Shared chain preparation (Plan 06-01 T4 extraction): the piece
    /// array, the enabled-top mark, `decodeParamsHash` and the per-level
    /// hash chain — the exact statements `run()` has carried since 02-02,
    /// now shared with the `runSub` sub-run seam. Walk SEMANTICS untouched.
    private func prepareChain(instances: [any ModuleBoxing], decodeHash: UInt64) {
        // v50 order: (iopOrder, multiPriority) — Darktable's module order.
        pieces = instances
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            .map { Piece(box: $0, state: $0.makeRunPiece()) }
        topEnabledPosition = pieces.lastIndex(where: { $0.box.enabled }) ?? -1
        planesRendered = 0
        // §1.3: decodeParamsHash — the shared D-H4 atom.
        decodeParamsHash = decodeHash
        // Per-level chain: levelHash[i] = decode ⊕ (enabled hashes ≤ i).
        var running = decodeParamsHash
        levelHash = pieces.map { piece in
            if piece.box.enabled {
                running = Self.chain(running, piece.box.paramsHash)
            }
            return running
        }
    }

    /// The forward ROI walk (dt get_dimensions, `pixelpipe_hb.c:3368-3405`
    /// mirror) — verbatim the `run()` body, parameterized on the entry and
    /// clamp-frame ROIs so `runSub` reuses it unchanged.
    private func forwardWalk(entry: ROI, frame: ROI) -> ROI {
        roi = entry
        frameROI = frame
        var roiWalk = roi
        bufInROI = []
        levelROI = []
        bufInROI.reserveCapacity(pieces.count)
        levelROI.reserveCapacity(pieces.count)
        for index in pieces.indices {
            bufInROI.append(roiWalk)
            pieces[index].state.dscIn = IOPBufferDesc(
                width: roiWalk.width, height: roiWalk.height)
            // iscale stamp (05-01-T2; dt `piece->iscale`, `pixelpipe_hb.c:505`
            // mirror): the ENTRY scale of this run, same source as dscIn
            // (entry-ROI scale, roiHint applied — the hint is part of the
            // entry). Run-level constant: every piece gets the same value;
            // the TILE drivers (executeTiled/executeTiledNegotiated) MUST
            // NOT rewrite it (tile-local readROI.scale ≠ entry scale).
            pieces[index].state.iscale = roi.scale
            // pipeType stamp (05-06; dt `piece->pipe->type` mirror): the
            // nlmeans preview-downgrade lever reads it (K clamp + decimate
            // on PREVIEW/THUMBNAIL). Run-level constant — the TILE drivers
            // must not rewrite it (same contract as iscale).
            pieces[index].state.pipeType = resolution
            // Freeze the FORWARD piece state for the backward pass: the
            // miss closures capture `pieces[index].state` by value at
            // probe time (Swift copy), and `processRec` mutates the LIVE
            // array during recursion — without this, a module's
            // modifyROIIn would read the mutated processedROI stamps.
            // (No-op today: stamps live in distinct fields; kept explicit
            // for the 04-02/04-05 modules that read dscIn/process in hooks.)
            var out = roiWalk
            if pieces[index].box.enabled {
                pieces[index].box.modifyROIOutErased(
                    &out, input: roiWalk, piece: pieces[index].state)
            }
            levelROI.append(out)
            roiWalk = out
        }
        return roiWalk
    }

    // MARK: - Sub-run seam (Plan 06-01 T4 — the LayerCompositeDriver leg)

    /// Run this pipe as a SUB-RUN over a caller-provided input plane (the
    /// composite accumulator) instead of a decode. The forward walk, hash
    /// chain, ROI negotiation, cache semantics and recursion are byte-
    /// identical to `run()` — only the entry shape differs:
    /// - `input`/`inputROI`: the driver-managed plane + its ROI (the
    ///   composite window). The base case returns the plane as-is (never
    ///   cached, never counted).
    /// - `decodeHash`: the BASE run's decodeParamsHash — layer planes must
    ///   invalidate when the decode changes (their input C derives from it).
    /// - `layerID`: the cache namespace (the layer's UUID; base/terminal
    ///   legs pass `baseLayer.id`).
    internal func runSub(
        input: any MTLTexture,
        inputROI: ROI,
        instances: [any ModuleBoxing],
        decodeHash: UInt64,
        metal: MetalContext,
        layerID: UUID
    ) async throws -> (output: any MTLTexture, stats: RenderPipeline.PipeRunStats) {
        if resolution == .export {
            throw AppError.notImplemented("Phase 11")
        }
        decodedImage = nil
        subRunInput = input
        cacheLayerID = layerID
        prepareChain(instances: instances, decodeHash: decodeHash)
        let statsBefore = await cache.stats
        let walked = forwardWalk(entry: inputROI, frame: inputROI)
        let final = try await processRec(
            position: pieces.count - 1,
            roiOut: walked,
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

    /// THUMBNAIL lazy fetch (`PipeResolution.isLazy` lifecycle): renders
    /// ONLY when `isDirty` (a fresh pipe is dirty — the first fetch renders),
    /// then disarms. The coordinator re-arms the flag on param change
    /// WITHOUT rendering, so the plane rebuilds lazily on the next fetch
    /// (Phase 9 browser seam). Clean pipe → nil, zero work.
    internal func runIfDirty(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        metal: MetalContext
    ) async throws -> (output: any MTLTexture, stats: RenderPipeline.PipeRunStats)? {
        guard isDirty else { return nil }
        let result = try await run(image: image, instances: instances, metal: metal, longEdge: nil)
        isDirty = false
        return result
    }

    /// FULL on-demand entry (`PipeResolution.full` lifecycle): renders
    /// scale 1.0 ONCE per call and returns the plane to the caller — the
    /// pipe retains NO reference (only the cache's input + final lines
    /// survive, per lock #4), so the 1.55GB@100MP planes are evictable as
    /// soon as the caller drops the result. NEVER called on param change.
    internal func runOnce(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        metal: MetalContext
    ) async throws -> (output: any MTLTexture, stats: RenderPipeline.PipeRunStats) {
        try await run(image: image, instances: instances, metal: metal, longEdge: nil)
    }

    /// The recursive walk (`pixelpipe_hb.c:1838` direct translation).
    ///
    /// - Parameter position: chain index of the module whose OUTPUT is
    ///   requested; -1 = the input plane (cache line 0).
    ///
    /// Line identity: module i's output = cache line i+1, keyed on
    /// `levelHash[i]` (decode ⊕ enabled hashes ≤ i — see `levelHash`). The
    /// walk probes TOP-DOWN and a hit returns immediately WITHOUT probing
    /// further up — the fast path's whole point (upstream planes untouched).
    internal func processRec(
        position: Int,
        roiOut: ROI,
        metal: MetalContext
    ) async throws -> PipeCache.CachedPlane {
        // ═══ BASE (position -1): the input plane — cache line 0, keyed on
        // decodeParamsHash + the ROI (`pixelpipe_hb.c:1930-1999` entry).
        // Scale-at-entry (Plan 02-03-03): when `roiOut.scale < 1.0` the
        // decoded CIImage renders DIRECTLY at the target long edge (ONE
        // pass — never 100MP-then-downscale); scale 1.0 renders the full
        // extent. Either way the miss closure builds the plane ONCE; hits
        // skip the decode leg entirely. A scale-1.0 roi (FULL, or an image
        // smaller than its bucket) has a DIFFERENT cache key than any
        // scaled roi (the roi is part of the key), so the two never alias.
        // 04-01: `roiOut` here is the NEGOTIATED input ROI (offset window
        // after a crop's backward pass) — T4's sub-domain render consumes
        // it; until then the legacy full-extent/scaled legs run.
        guard position >= 0 else {
            // 06-01 T4 sub-run seam: the driver-managed accumulator plane.
            // Returned as-is — never cached, never counted; the sub-run's
            // cache lines start at position 1.
            if let external = subRunInput {
                return PipeCache.CachedPlane(texture: external, byteCount: 0, lastHit: .now)
            }
            guard let image = decodedImage else {
                throw MetalError.deviceUnavailable
            }
            // 04-01-T4: negotiated sub-domain render. `roiOut` is in
            // ENTRY-PIXEL coords, TOP-LEFT origin (scale-at-entry size
            // when scale < 1): the source region is `roiOut ÷ scale` in
            // DECODED pixels, flipped into CI's bottom-up coords below
            // (extent-relative — CIRAW extents need not start at zero).
            // Full-frame requests keep the legacy legs; everything else
            // renders exactly its source region (CI lazy: no full-frame
            // buffer, no window copy — the D-G2 read).
            let fullW = max(Int(image.ciImage.extent.width), 1)
            let fullH = max(Int(image.ciImage.extent.height), 1)
            let scale = max(CGFloat(roiOut.scale), 1e-6)
            let needsSubdomain =
                roiOut.width < fullW || roiOut.height < fullH
                || roiOut.x != 0 || roiOut.y != 0
            return try await cache.plane(
                for: PipeCacheKey(
                    imageID: imageID, pipeType: resolution, position: 0,
                    upstreamHash: decodeParamsHash, roi: roiOut,
                    layerID: cacheLayerID
                ),
                byteCount: Self.planeBytes(roiOut)
            ) { [self] in
                planesRendered += 1
                if needsSubdomain {
                    // ROI is top-left origin; CI extent is bottom-up
                    // (04-04-T4 lens-shrink postmortem: passing the ROI
                    // rect straight through renders file row H−M+r
                    // instead of region.y+r — a row shift invisible on
                    // y-invariant fixtures, fatal on checkerboard).
                    let ex = image.ciImage.extent
                    let rw = CGFloat(roiOut.width) / scale
                    let rh = CGFloat(roiOut.height) / scale
                    let rx = CGFloat(roiOut.x) / scale
                    let ryTop = CGFloat(roiOut.y) / scale
                    return try await metal.renderRegion(
                        image.ciImage,
                        region: CGRect(
                            x: rx,
                            y: ex.maxY - ryTop - rh,
                            width: rw,
                            height: rh),
                        scale: scale
                    )
                }
                if roiOut.scale < 1.0 {
                    return try await metal.renderToTexture(
                        image.ciImage, longEdge: max(roiOut.width, roiOut.height)
                    )
                }
                return try await metal.renderToTexture(image.ciImage)
            }
        }
        // 04-01: passes `roiOut` straight through (dt `:3378-3384`).
        guard pieces[position].box.enabled else {
            return try await processRec(
                position: position - 1,
                roiOut: roiOut,
                metal: metal
            )
        }

        // (b) cache line for this module's OUTPUT: position + 1 (position 0
        // is the input plane), keyed on levelHash[position] = decode ⊕ the
        // enabled hashes of modules ≤ this one.
        let key = PipeCacheKey(
            imageID: imageID,
            pipeType: resolution,
            position: position + 1,
            upstreamHash: levelHash[position],
            roi: roiOut,
            layerID: cacheLayerID
        )
        let isFinalOutput = position == topEnabledPosition
        let box = pieces[position].box
        var roiIn = roiOut
        box.modifyROIInErased(output: roiOut, input: &roiIn, piece: pieces[position].state)
        roiIn.scale = roiOut.scale
        // 04-03 rotation fix (L020 sequel): the bound legitimizes
        // downstream growth — a grow-module's output (rotation AABB 72 on
        // a 64 frame) is a contract, not an over-request. Clamping to the
        // bare frame erased it one level down (colorin passed 64 instead
        // of 72). Halo wings keep today's behavior (union == frame when
        // the request sits inside the frame).
        roiIn = roiIn.clamped(to: frameROI.union(roiOut))
        let negotiatedIn = roiIn // freeze for the @Sendable miss closure
        // (f) PER-PIPETYPE POLICY (lock #4): PREVIEW/THUMBNAIL cache every
        // plane; FULL caches input + final only (intermediates ping-pong);
        // EXPORT caches nothing. The tail plane's format follows the
        // terminal-tail policy (gamma tail → .bgra8Unorm).
        let tailFormat = tailPixelFormat(at: position)
        if resolution.cachesIntermediatePlanes || (isFinalOutput && resolution == .full) {
            return try await cache.plane(
                for: key,
                byteCount: Self.planeBytes(roiOut, pixelFormat: tailFormat)
            ) { [self] in
                // (d) MISS CLOSURE — recurse upstream with the negotiated
                // region, then execute.
                let upstream = try await processRec(
                    position: position - 1,
                    roiOut: negotiatedIn,
                    metal: metal
                )
                let upstreamW = upstream.texture.width
                let upstreamH = upstream.texture.height
                // 04-01-T4: exact — the base case now renders the negotiated
                // window (sub-domain), so upstream MUST match `negotiatedIn`
                // pixel-exact (Risk #7 retired; dt `processed_roi` mirror).
                precondition(
                    upstreamW == negotiatedIn.width && upstreamH == negotiatedIn.height,
                    "negotiated ROI violated at pos \(position): roiOut=\(roiOut) negotiatedIn=\(negotiatedIn) upstream=\(upstreamW)x\(upstreamH) bufIn=\(self.bufInROI[position])"
                )
                pieces[position].state.processedROIIn = negotiatedIn
                pieces[position].state.processedROIOut = roiOut
                let output = try Self.allocatePlane(
                    roiOut: roiOut, metal: metal, pixelFormat: tailFormat
                )
                // (g) TILE DRIVER (03-05-T6): large-working-set FULL
                // modules execute tile-wise (TilingPlan grid + module
                // halo); everything else is the plain whole-plane call.
                // The tile grid spans the module's OUTPUT plane; the read
                // rects address the negotiated input plane (`roiIn`-sized).
                if tileNeeded(box: box, roiOut: roiOut, piece: pieces[position].state,
                              outputFormat: tailFormat) {
                    try await executeTiledNegotiated(
                        box: box, piece: &pieces[position].state,
                        input: upstream.texture, output: output,
                        roiIn: negotiatedIn, roiOut: roiOut, metal: metal)
                } else {
                    try await box.processErased(
                        input: upstream.texture, output: output,
                        roiIn: negotiatedIn, roiOut: roiOut,
                        piece: &pieces[position].state, metal: metal
                    )
                }
                planesRendered += 1
                return output
            }
        }

        // Uncached leg (FULL intermediates — EXPORT never reaches the walk,
        // `run` throws first): ping-pong through pipe-private scratch —
        // never stored.
        let upstream = try await processRec(
            position: position - 1,
            roiOut: roiIn,
            metal: metal
        )
        precondition(
            upstream.texture.width == roiIn.width
                && upstream.texture.height == roiIn.height,
            "negotiated ROI violated (uncached) at pos \(position)"
        )
        pieces[position].state.processedROIIn = roiIn
        pieces[position].state.processedROIOut = roiOut
        // The FINAL output (FULL only — EXPORT finals are also uncached)
        // must not alias scratch the next run overwrites: allocate fresh.
        // The display tail format applies here too (FULL 100% viewing).
        let output: any MTLTexture =
            if isFinalOutput && resolution == .full {
                try Self.allocatePlane(roiOut: roiOut, metal: metal, pixelFormat: tailFormat)
            } else {
                try nextScratchPlane(roiOut: roiOut, metal: metal)
            }
        if tileNeeded(box: box, roiOut: roiOut, piece: pieces[position].state,
                      outputFormat: tailFormat) {
            try await executeTiledNegotiated(
                box: box, piece: &pieces[position].state,
                input: upstream.texture, output: output,
                roiIn: roiIn, roiOut: roiOut, metal: metal)
        } else {
            try await box.processErased(
                input: upstream.texture, output: output,
                roiIn: roiIn, roiOut: roiOut,
                piece: &pieces[position].state, metal: metal
            )
        }
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
    ///   - longEdge: scale-at-entry target for the INPUT plane (Plan 02-03):
    ///     the coordinator passes the D-C3 bucket for PREVIEW; nil resolves
    ///     to the resolution default (THUMBNAIL 360) or full extent (FULL).
    public static func process(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        imageID: UUID,
        resolution: PipeResolution,
        cache: PipeCache,
        metal: MetalContext,
        longEdge: Int? = nil,
        maxTileWorkingBytes: Int? = nil,
        roiHint: ROI? = nil
    ) async throws -> (any MTLTexture, PipeRunStats) {
        let interval = signposter.beginInterval("pixelpipe", id: signposter.makeSignpostID())
        defer { signposter.endInterval("pixelpipe", interval) }
        let pipe = PixelPipe(resolution: resolution, cache: cache)
        pipe.imageID = imageID
        if let maxTileWorkingBytes {
            // Test/parametric injection of the per-tile budget (03-05-T6).
            pipe.maxTileWorkingBytes = maxTileWorkingBytes
        }
        if let roiHint {
            // Test/probe seam only (04-01-T0 口径 2): clamp to the entry
            // ROI inside `run` — FULL zoom-ROI UI surface is a later call.
            pipe.entryROIHInt = roiHint
        }
        return try await pipe.run(
            image: image, instances: instances, metal: metal, longEdge: longEdge
        )
    }

    /// Run the LAYER COMPOSITE (Plan 06-05 — the coordinator's public
    /// entry for stacks with adjustment layers): the 1 + N + 1
    /// `LayerCompositeDriver` orchestration (base sub-run → per-layer
    /// sub-run + blendop composite → terminal segment), summing the per-leg
    /// stats into one `PipeRunStats` for the coordinator's logging.
    ///
    /// Empty adjustment layers → identical to `process` (the driver's base
    /// + terminal legs degenerate to the flat chain; callers should keep
    /// using `process` for that case to preserve the exact legacy key
    /// space — the coordinator branches on the stack).
    public static func processComposite(
        image: DecodedImage,
        instances: [any ModuleBoxing],
        layerStack: LayerStack,
        registry: ModuleRegistry,
        imageID: UUID,
        resolution: PipeResolution,
        cache: PipeCache,
        metal: MetalContext,
        longEdge: Int? = nil,
        roiHint: ROI? = nil,
        policy: LayerCachePolicy,
        hotLayerID: UUID? = nil,
        maskDirectory: URL? = nil
    ) async throws -> (any MTLTexture, PipeRunStats) {
        let interval = signposter.beginInterval("pixelpipe", id: signposter.makeSignpostID())
        defer { signposter.endInterval("pixelpipe", interval) }
        let result = try await LayerCompositeDriver.composite(
            image: image, imageID: imageID, baseInstances: instances,
            layerStack: layerStack, registry: registry, resolution: resolution,
            cache: cache, metal: metal, longEdge: longEdge, roiHint: roiHint,
            policy: policy, hotLayerID: hotLayerID, maskDirectory: maskDirectory)
        var stats = result.baseStats
        for layer in result.layerStats {
            stats.hits += layer.run.hits
            stats.misses += layer.run.misses
            stats.planesRendered += layer.run.planesRendered
        }
        if let terminal = result.terminalStats {
            stats.hits += terminal.hits
            stats.misses += terminal.misses
            stats.planesRendered += terminal.planesRendered
        }
        return (result.output, stats)
    }
}
