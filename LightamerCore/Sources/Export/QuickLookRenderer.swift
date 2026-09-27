import CoreGraphics
import Foundation
import ImageIO
import Metal
import SQLite3
import os

// ─────────────────────────────────────────────────────────────────────────────
// QuickLookRenderer (Plan 13-1 T3) — the headless Quick Look render seam,
// the REDUCTION TWIN of `ExportRenderer` (D-13-CONTEXT-2). Same verified
// atoms, three deliberate SUBTRACTIONS:
//
//   disk sidecar → instances + layer record   (ExportRenderer.readDocument —
//                                              the DISK document is the truth;
//                                              09-4 reading method)
//   → ExportChainBuilder                      (gamma stripped + the colorout
//                                              target overridden to sRGB —
//                                              the DISPLAY TERMINAL)
//   → registry.materializeBoxes               (identity-preserving records)
//   → routed pipe render                      ($routesToExportQueue — L031:
//                                              the whole task tree lands on
//                                              exportCommandQueue; no
//                                              identity blit is built HERE,
//                                              the pipe owns its buffers)
//   → exit leg                                (fresh CIContextPool on the
//                                              export queue — R8 fence —
//                                              renderToEncodedBitmap)
//   → packedRGBA8 → CGImage                   (NO quantize-to-file, NO
//                                              encode, NO yiyin injection,
//                                              NO export sizing — the three
//                                              subtractions; the终点 is a
//                                              CGImage, not a file)
//
// QL PREVIEW SEMANTICS (the explicit boundary): the Quick Look pane shows
// the EDITED STATE — the editor viewport's offscreen twin (no yiyin
// framing, no export sizing/quantize/encode). It is NOT an export preview.
//
// THREE-PROBE THUMBNAIL CHAIN (the `thumbnail` face):
//   a. `thumb_state` fresh AND `thumbs/<pathhash>.jpg` present (read-only
//      lindex row probe + ThumbnailDiskStore.read) → direct JPEG read,
//      ZERO render (counted via `ThumbnailSource.thumbsCache`);
//   b. stale/missing thumb but a READABLE sidecar → headless render at the
//      requested size (the real edited state — the thumb cache would lie);
//   c. no sidecar (pristine) OR every earlier probe failed → the tier-A
//      embedded preview (ImageIO; 09-CONTEXT:77 double-tier semantics).
// Every level degrades to the next; a total failure returns nil (the QL
// process falls back to the system's own probe) — QL NEVER crashes.
//
// BOUNDED RENDERING: every render path waits at most `renderTimeout`
// (the T2 perf.md verdict); on timeout the tier-A preview answers instead.
// The timeout is an upper bound on WAITING — the render task finishes into
// the void (no GPU mid-flight cancellation; the SessionThumbnailProvider
// cancelAll generation-gate posture).
//
// READ-ONLY discipline: this renderer never writes sidecar, lindex or
// thumbs — the lindex probe opens with SQLITE_OPEN_READONLY and refuses a
// future schema (>2, the SessionIndexSchema freeze contract).
// ─────────────────────────────────────────────────────────────────────────────

public enum QuickLookRenderer {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "quicklook-render")

    /// The bounded-render wait (Plan 13-1 T2 verdict, perf.md): the worst
    /// observed cold render was 5.44s (one-time compilations included);
    /// ×5.5 safety factor. Warm steady state (≤2.1s at the 2560 fit edge)
    /// never triggers.
    public static let renderTimeout: TimeInterval = 30

    /// A render exceeded the bounded wait — the thumbnail chain degrades to
    /// the tier-A preview (QL-facing typed face; log-only by contract).
    public struct RenderTimeout: Error, Sendable {
        public let seconds: Double
    }

    /// Where a thumbnail answer came from (the parity/fallback test seam).
    public enum ThumbnailSource: String, Sendable {
        /// Probe a: the committed thumbs cache, read directly (zero render).
        case thumbsCache
        /// Probe b: the headless edited-state render.
        case rendered
        /// Probe c: the tier-A embedded preview (ImageIO).
        case embeddedPreview
    }

    public struct ThumbnailOutcome: Sendable {
        public let image: CGImage
        public let source: ThumbnailSource
    }

    /// The injected decode leg (test seam — synthetic `DecodedImage`s keep
    /// the fallback-chain tests millisecond-cheap). nil = `RAWDecoder`.
    public typealias DecodeLeg = @Sendable (URL) async throws -> DecodedImage

    /// The injected render leg (test seam — the fake-slow render for the
    /// bounded-timeout test and the zero-render counters for probe a).
    /// `targetLongEdge → image`. nil = the real path.
    public typealias RenderLeg = @Sendable (Int) async throws -> CGImage

    // MARK: - Preview (the edited state at the QL fit size)

    /// The QL full preview: sidecar truth → sRGB display-terminal CGImage at
    /// `targetLongEdge` (NEVER the native 100 MP full frame). Bounded by
    /// `renderTimeout`; a failed/timed-out render degrades to the tier-A
    /// embedded preview; only a total failure (no embedded preview either)
    /// throws — the QL process then falls back to the system probe.
    public static func preview(
        imageURL: URL,
        targetLongEdge: Int,
        metal: MetalContext,
        registry: ModuleRegistry,
        decodeLeg: DecodeLeg? = nil,
        renderLeg: RenderLeg? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> CGImage {
        let wait = timeout ?? renderTimeout
        do {
            let op: @Sendable () async throws -> CGImage = { [targetLongEdge] in
                if let renderLeg {
                    return try await renderLeg(targetLongEdge)
                }
                let rendered = try await renderedPlane(
                    imageURL: imageURL, targetLongEdge: targetLongEdge,
                    metal: metal, registry: registry, decodeLeg: decodeLeg)
                return try image(from: rendered)
            }
            return try await boundedWait(seconds: wait, op)
        } catch {
            logger.error(
                "ql preview render degraded for \(imageURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public) — falling back to the tier-A preview"
            )
            if let fallback = SessionThumbnailProvider.embeddedPreview(url: imageURL) {
                return fallback
            }
            throw error
        }
    }

    // MARK: - Thumbnail (the three-probe chain)

    /// The QL thumbnail: three probes, degrading in order (see the header).
    /// `nil` = every probe missed — the caller shows the system fallback.
    public static func thumbnail(
        imageURL: URL,
        requestedLongEdge: Int,
        metal: MetalContext,
        registry: ModuleRegistry,
        decodeLeg: DecodeLeg? = nil,
        renderLeg: RenderLeg? = nil,
        timeout: TimeInterval? = nil
    ) async -> ThumbnailOutcome? {
        let wait = timeout ?? renderTimeout
        // ── Probe a: the FRESH thumbs cache, read directly (zero render). ──
        if let cache = freshThumb(imageURL: imageURL),
           let image = ThumbnailDiskStore(sessionRoot: cache.sessionRoot)
               .read(relPath: cache.relPath) {
            return ThumbnailOutcome(image: image, source: .thumbsCache)
        }

        // ── Probe b: the sidecar truth → headless render @ requested size.
        // A readable sidecar = the image HAS a Lightamer state; the rendered
        // thumbnail must show it (the embedded preview would lie about the
        // render). Pristine (no sidecar) skips straight to probe c.
        if ExportRenderer.readDocument(imageURL: imageURL) != nil {
            do {
                let op: @Sendable () async throws -> CGImage = { [requestedLongEdge] in
                    if let renderLeg {
                        return try await renderLeg(requestedLongEdge)
                    }
                    let rendered = try await renderedPlane(
                        imageURL: imageURL, targetLongEdge: requestedLongEdge,
                        metal: metal, registry: registry, decodeLeg: decodeLeg)
                    return try image(from: rendered)
                }
                let image = try await boundedWait(seconds: wait, op)
                return ThumbnailOutcome(image: image, source: .rendered)
            } catch {
                // The level-by-level degrade (T3): a failed/timed-out render
                // falls through to the tier-A preview — QL never blocks on a
                // bad sidecar or a hung GPU.
                logger.error(
                    "ql thumbnail render degraded for \(imageURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public) — falling back to the tier-A preview"
                )
            }
        }

        // ── Probe c: the tier-A embedded preview (pristine + the degrade
        // target for every earlier probe).
        if let image = SessionThumbnailProvider.embeddedPreview(url: imageURL) {
            return ThumbnailOutcome(image: image, source: .embeddedPreview)
        }
        return nil
    }

    // MARK: - The render body (the reduction twin)

    /// The rendered product at the plane boundary (the parity-test seam):
    /// quantized packedRGBA8 + the color space the pixels are encoded in.
    /// `@unchecked` — `CGColorSpace` is an immutable CF type (the
    /// `ExportRenderStage` posture).
    struct RenderedPlane: @unchecked Sendable {
        let plane: ExportQuantizedPlane
        let colorSpace: CGColorSpace
    }

    /// Decode → sRGB display-terminal chain → routed pipe run → export-queue
    /// exit leg → packedRGBA8. The ExportRenderer.renderStage shape with the
    /// three subtractions (no yiyin injection, no variant sizing — the
    /// caller's long edge IS the render target, no encode naming/writing).
    static func renderedPlane(
        imageURL: URL,
        targetLongEdge: Int,
        metal: MetalContext,
        registry: ModuleRegistry,
        decodeLeg: DecodeLeg?
    ) async throws -> RenderedPlane {
        // ── 1. decode leg (full frame, once — the export discipline). ─────
        let decoded: DecodedImage
        if let decodeLeg {
            decoded = try await decodeLeg(imageURL)
        } else {
            decoded = try await RAWDecoder().decode(imageURL)
        }

        // ── 2. the document (disk sidecar truth; nil = pristine chain). ───
        let document = ExportRenderer.readDocument(imageURL: imageURL)
        let records = document?.instances ?? []
        let imageID = document?.imageID ?? UUID()

        // ── 3. the sRGB display-terminal chain (gamma stripped; the colorout
        // record's target rewritten — the display face of the export-chain
        // assembler, D-13-CONTEXT-2 ①). ────────────────────────────────────
        let built = try ExportChainBuilder.exportChain(
            from: records, target: .sRGB, linearVariant: false)
        let (boxes, unknownOps) = await registry.materializeBoxes(for: built.instances)
        if !unknownOps.isEmpty {
            logger.info(
                "ql render: unknown ops degraded \(unknownOps.joined(separator: ","), privacy: .public)")
        }
        for box in boxes {
            guard let colorout = box as? ModuleBox<ColorOutModule> else { continue }
            colorout.module.exportTargetOverride = built.exportTargetOverride
            if let coloroutRecord = built.instances.first(where: {
                $0.opName == ColorOutModule.opName && $0.id == box.instanceID
            }) {
                let params = (try? coloroutRecord.params(of: ColorOutModule.self))
                    ?? ColorOutModule.Params()
                colorout.setParams(params)
            }
        }

        // ── 4. the layer stack rebuild (the ExportRenderer shape). ────────
        let layerStack: LayerStack?
        if let layerRecord = document?.layerStack, !layerRecord.layers.isEmpty {
            var rebuilt = LayerStack(baseLayer: BackgroundLayer())
            for layer in layerRecord.snapshot.makeLayers() {
                rebuilt.addAdjustment(layer)
            }
            layerStack = rebuilt.compositeLayers.isEmpty ? nil : rebuilt
        } else {
            layerStack = nil
        }

        // ── 5. the routed render (L031: the whole tree on the export
        // queue; the long edge = the QL target — no export sizing math). ──
        let cache = PipeCache()
        let outputTexture: any MTLTexture
        if let layerStack {
            let (texture, _) = try await MetalContext.$routesToExportQueue.withValue(true) {
                try await RenderPipeline.processComposite(
                    image: decoded, instances: boxes, layerStack: layerStack,
                    registry: registry, imageID: imageID, resolution: .export,
                    cache: cache, metal: metal, longEdge: targetLongEdge,
                    roiHint: nil, policy: .export)
            }
            outputTexture = texture
        } else {
            let (texture, _) = try await MetalContext.$routesToExportQueue.withValue(true) {
                try await RenderPipeline.process(
                    image: decoded, instances: boxes, imageID: imageID,
                    resolution: .export, cache: cache, metal: metal,
                    longEdge: targetLongEdge)
            }
            outputTexture = texture
        }

        // ── 6. the exit leg (fresh pool on the export queue; the E3 identity
        // contract: sourceColorSpace = what the arriving plane already is).
        let pool = CIContextPool(device: metal.device, commandQueue: metal.exportCommandQueue)
        let sourceColorSpace =
            built.coloroutOverridden ? built.exportTargetOverride : WorkingSpace.colorSpace
        let encoded = try await pool.renderToEncodedBitmap(
            TextureBox(texture: outputTexture),
            sourceColorSpace: sourceColorSpace,
            toSpace: built.exportTargetOverride)

        // ── 7. quantize (the 8-bit display tier — a CGImage, not a file).
        let samples = encoded.data.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        let packed = try ExportQuantizer.packedRGBA8(
            rgba: samples, width: encoded.width, height: encoded.height)
        let plane = ExportQuantizedPlane(
            data: packed, width: encoded.width, height: encoded.height, layout: .rgba8)
        return RenderedPlane(plane: plane, colorSpace: built.exportTargetOverride)
    }

    /// The CGImage face of a rendered plane (the `ImageIOEncodeCore`
    /// premultiplied-last RGBA8 posture; the target space rides the bitmap).
    static func image(from rendered: RenderedPlane) throws -> CGImage {
        try ImageIOEncodeCore.makeCGImage(
            from: rendered.plane, colorSpace: rendered.colorSpace)
    }

    // MARK: - Probe a: the fresh-thumbs lindex probe (READ-ONLY)

    struct FreshThumbHit {
        let sessionRoot: URL
        let relPath: String
    }

    /// Walk up from the image to the nearest session root, open the lindex
    /// READ-ONLY (schema-gated: >2 or unparsable REFUSES — the freeze
    /// contract), and check the row's thumb binding: state produced (1/2)
    /// AND `thumb_params_hash == params_hash` (the L020 freshness pair —
    /// a stale thumb is a lie about the render). nil = no fresh binding.
    static func freshThumb(imageURL: URL) -> FreshThumbHit? {
        guard var dir = directory(of: imageURL) else { return nil }
        while true {
            let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: dir)
            if FileManager.default.fileExists(atPath: lindexURL.path) {
                let relPath = relPath(of: imageURL, under: dir)
                guard let hit = probeThumbsRow(lindexURL: lindexURL, relPath: relPath) else {
                    return nil
                }
                return hit ? FreshThumbHit(sessionRoot: dir, relPath: relPath) : nil
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    /// The row probe: read-only handle, schema gate, the freshness pair.
    /// `nil` = the lindex refused (open/schema failure); `false` = row not
    /// fresh; `true` = fresh.
    ///
    /// The two-open posture (the WAL reality): a live main app keeps the
    /// `-shm`/`-wal` pair, and a plain SQLITE_OPEN_READONLY connection reads
    /// through it. With the app CLOSED the checkpointed library carries no
    /// sidecar files and a readonly open FAILS (unable to open database
    /// file) — the `immutable=1` URI retry then reads exactly the committed
    /// main database (the checkpoint IS the commit). During an in-flight
    /// checkpoint the immutable read may see a slightly OLDER committed
    /// state — the safe direction for QL (a stale probe only falls through
    /// to the render leg; the answer is still a disk-committed one).
    private static func probeThumbsRow(lindexURL: URL, relPath: String) -> Bool? {
        if let result = readThumbsRow(
            path: lindexURL.path,
            flags: SQLiteHandle.readOnlyFlags,
            relPath: relPath)
        {
            return result
        }
        let encodedPath = lindexURL.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? lindexURL.path
        let uri = "file://" + encodedPath + "?immutable=1"
        return readThumbsRow(path: uri, flags: immutableReadFlags, relPath: relPath)
    }

    private static let immutableReadFlags =
        SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX

    private static func readThumbsRow(path: String, flags: Int32, relPath: String) -> Bool? {
        guard let handle = try? SQLiteHandle(path: path, flags: flags) else {
            return nil
        }
        defer { handle.close() }
        do {
            // The schema gate — refuse a FUTURE schema (never guess).
            let versionStatement = try handle.prepare(
                "SELECT value FROM meta WHERE key = ?")
            try versionStatement.bindText(1, SessionIndexSchema.MetaKey.schemaVersion)
            guard try versionStatement.step(),
                  let stored = versionStatement.columnText(0),
                  let version = Int(stored) else {
                return nil
            }
            guard version <= SessionIndexSchema.schemaVersion else { return nil }

            let statement = try handle.prepare(
                "SELECT thumb_state, thumb_params_hash, params_hash "
                    + "FROM images WHERE path = ?")
            try statement.bindText(1, relPath)
            guard try statement.step() else { return false }
            let state = statement.columnInt(0)
            let thumbHash = statement.columnText(1)
            let paramsHash = statement.columnText(2)
            let produced = state == SessionIndexSchema.ThumbState.embedded.rawValue
                || state == SessionIndexSchema.ThumbState.rendered.rawValue
            // The binding pair: equal hashes = fresh. A pristine row (no
            // sidecar) carries NULL on BOTH sides — that IS a consistent
            // binding (the thumb was committed against the no-params state).
            let consistent = (thumbHash == nil && paramsHash == nil)
                || (thumbHash != nil && thumbHash == paramsHash)
            return produced && consistent
        } catch {
            return nil
        }
    }

    private static func directory(of url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? url.standardized : url.deletingLastPathComponent().standardized
    }

    /// POSIX rel-path of `url` under `root` (the lindex `path` column's
    /// spelling — rel TO the session root; SessionIndexStore.swift:29-31).
    private static func relPath(of url: URL, under root: URL) -> String {
        let urlPath = url.standardized.path
        let rootPath = root.standardized.path
        if urlPath.hasPrefix(rootPath + "/") {
            return String(urlPath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    // MARK: - The bounded wait

    /// Race the operation against the timeout (the T2 verdict constant).
    /// The winner answers; the loser's task is cancelled — a render that
    /// already reached the GPU finishes into the void (no mid-flight GPU
    /// cancellation; the generation-gate posture).
    static func boundedWait<T: Sendable>(
        seconds: Double, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw RenderTimeout(seconds: seconds)
            }
            guard let winner = try await group.next() else {
                throw RenderTimeout(seconds: seconds)
            }
            group.cancelAll()
            return winner
        }
    }
}
