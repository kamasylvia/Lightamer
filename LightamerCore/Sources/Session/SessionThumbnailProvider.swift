import CoreGraphics
import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// SessionThumbnailProvider (Plan 09-03 T3/T4) — the DOUBLE-TIER thumbnail
// pipeline (RESEARCH §5.2; the throughput-critical decision):
//
//   • Tier A (embedded): ImageIO `CGImageSourceCreateThumbnailAtIndex` — the
//     RAW file's embedded JPEG preview, ~10–50 ms/image. Appointed when
//     `has_edits` is FALSE (pristine rows).
//   • Tier B (rendered): a REAL pipe run — decode → materialize the sidecar
//     instances → `PixelPipe.process`/`processComposite` @ `.thumbnail`
//     (360px) → CGImage. ~0.5–2 s/image. Appointed when `has_edits` is TRUE,
//     or when a STALE row regenerates (RESEARCH §5.2 — the stale regen row's
//     params changed; the embedded preview would lie about the render).
//
// **The tier ruling red line**: the tier is decided by `has_edits` (+ the
// stale-regen clause) ONLY — never by "did the render look right". The
// A→B upgrade happens exactly when the image is edited; T7 pins this with
// render-count reverse assertions.
//
// **The PipeCache isolation red line (review checkpoint)**: the browser
// tier NEVER touches the shared plane cache. This Core file does not even
// NAME the cache type: the tier-B GPU leg is an INJECTED closure
// (`ThumbnailRenderLeg`) that the App assembly wires with its own throwaway
// per-run cache instance — `grep -rn PipeCache Core/Session App/Session`
// stays ZERO-HIT by construction, and the resident regression asserts the
// observed cache total is unchanged across browser renders.
//
// Embedded-preview fallback: a missing/undecodable embedded preview is a
// CAMERA-DOMAIN FACT (some RAWs ship none), not an error — tier A falls
// back to a one-shot tier B render for that image (recorded in DECISIONS).
//
// **Phase 8 contract (禁改)**: tier B rides the SAME
// `LayerCompositeDriver`/`terminalTailFloor` split and the yiyin per-run
// context injection CONTRACT as the coordinator's `renderCurrentChain` —
// the injection itself is re-implemented here against the same atoms
// (watermark captureExif/logo faces + the borders joint layout record)
// while the coordinator's `injectYiyinRunContext` stays byte-identical.
// ─────────────────────────────────────────────────────────────────────────────

/// The double-tier appointment (RESEARCH §5.2). `embedded` = tier A,
/// `rendered` = tier B. Mirrors `SessionIndexSchema.ThumbState`'s
/// produced-state values (1/2).
public enum SessionThumbnailTier: String, Sendable {
    case embedded
    case rendered

    /// The `thumb_state` column value a produced thumb of this tier binds.
    public var producedState: SessionIndexSchema.ThumbState {
        switch self {
        case .embedded: .embedded
        case .rendered: .rendered
        }
    }
}

/// The tier-B GPU render request — everything the injected leg needs. The
/// instances/layerStack are ALREADY MATERIALIZED by the provider (the
/// sidecar-truth rebuild, same merge semantics as the coordinator's
/// restore); the leg only runs the pipe.
public struct ThumbnailRenderRequest: Sendable {
    public let url: URL
    public let imageID: UUID
    public let decoded: DecodedImage
    public let instances: [any ModuleBoxing]
    public let layerStack: LayerStack?
    /// Always `.thumbnail` today (360px); the ladder stays explicit for the
    /// culling sub-pipe's future reuse.
    public let resolution: PipeResolution

    public init(
        url: URL, imageID: UUID, decoded: DecodedImage,
        instances: [any ModuleBoxing], layerStack: LayerStack?,
        resolution: PipeResolution
    ) {
        self.url = url
        self.imageID = imageID
        self.decoded = decoded
        self.instances = instances
        self.layerStack = layerStack
        self.resolution = resolution
    }
}

/// The injected tier-B leg: request → display CGImage. The App assembly
/// implements it with a throwaway per-run plane cache + the SAME
/// process/processComposite branching as `renderCurrentChain` + a
/// ColorSync conversion to sRGB. Tests wire the REAL leg (真渲染回归钉).
public typealias ThumbnailRenderLeg = @Sendable (ThumbnailRenderRequest) async throws -> CGImage

/// The injected yiyin per-run context injector — the CONTRACT twin of the
/// coordinator's `injectYiyinRunContext(longEdge:resolution:)` (which is
/// 禁改): watermark captureExif/logo faces + the borders joint layout
/// record, computed once per run, riding the run's entry scale. Optional:
/// images without watermark/borders boxes need nothing.
public typealias ThumbnailRunContextInjector = @Sendable (
    _ instances: [any ModuleBoxing], _ decoded: DecodedImage,
    _ resolution: PipeResolution, _ longEdge: Int?
) -> Void

/// The injected decode leg (test seam): the provider decodes via the app
/// `RAWDecoder` by default; tests inject a synthetic `DecodedImage` so the
/// QUEUE-semantics tests stay millisecond-cheap.
public typealias ThumbnailDecodeLeg = @Sendable (URL) async throws -> DecodedImage

public actor SessionThumbnailProvider {

    private static let logger = AppError.logger

    // MARK: - Dependencies

    private let sessionRoot: URL
    private let store: SessionIndexStore
    private let disk: ThumbnailDiskStore
    private let memory: ThumbnailMemoryCache
    private let registry: ModuleRegistry
    private let decoder: RAWDecoder?
    private let decodeLeg: ThumbnailDecodeLeg?
    private let renderLeg: ThumbnailRenderLeg?
    private let runContextInjector: ThumbnailRunContextInjector?

    /// Tier A downsampling target (execution decision D7): 720px — 2× the
    /// 360 display size, the same supersampling headroom the coordinator's
    /// D-C3 ladder uses for sub-360 cells.
    public static let embeddedPreviewMaxPixel = 720

    // MARK: - Init

    public init(
        sessionRoot: URL,
        store: SessionIndexStore,
        disk: ThumbnailDiskStore,
        memory: ThumbnailMemoryCache,
        registry: ModuleRegistry,
        decoder: RAWDecoder? = nil,
        decodeLeg: ThumbnailDecodeLeg? = nil,
        renderLeg: ThumbnailRenderLeg?,
        runContextInjector: ThumbnailRunContextInjector? = nil
    ) {
        self.sessionRoot = sessionRoot
        self.store = store
        self.disk = disk
        self.memory = memory
        self.registry = registry
        self.decoder = decoder
        self.decodeLeg = decodeLeg
        self.renderLeg = renderLeg
        self.runContextInjector = runContextInjector
    }

    // MARK: - The fetch path (LAZY — render only when needed)

    /// The cell-facing fetch: memory → disk → produce (T4 adds the queue in
    /// front of produce; the tiers and binding below are the contract).
    ///
    /// LAZY semantics (the `fetchThumbnail` model): a valid disk hit or a
    /// produced thumb renders EXACTLY ONCE — repeat fetches ride memory.
    public func thumbnail(for relPath: String) async -> CGImage? {
        // ① Memory (LRU hit refreshes recency).
        if let image = await memory.image(for: relPath) {
            return image
        }
        guard let row = await fetchRow(relPath) else { return nil }

        // ② Disk hit — only when the row's binding says the file is CURRENT
        // (state produced AND the params hash matches). A stale row's file
        // is a lie about the render; it regenerates below.
        if let state = row.thumbState,
           state == SessionIndexSchema.ThumbState.embedded.rawValue
               || state == SessionIndexSchema.ThumbState.rendered.rawValue,
           row.thumbParamsHash == row.paramsHash,
           let image = disk.read(relPath: relPath) {
            await memory.insert(image, for: relPath)
            return image
        }

        // ③ Produce (double-tier ruling inside).
        return await produce(relPath: relPath, row: row)
    }

    /// The DOUBLE-TIER RULING (the red line): tier = has_edits ONLY, plus
    /// the stale-regen clause (a sidecar-bearing stale row regenerates at
    /// tier B — RESEARCH §5.2). A row without a sidecar is pristine and is
    /// tier A FOREVER (the T7 reverse assertion pins: no tier-B render for
    /// pristine images).
    public static func tier(forRow row: SessionIndexRow) -> SessionThumbnailTier {
        if row.hasEdits == 1 {
            return .rendered
        }
        let sidecarPresent = row.sidecarPresent == 1
        let stale = row.thumbState == SessionIndexSchema.ThumbState.stale.rawValue
        if sidecarPresent && stale {
            return .rendered
        }
        return .embedded
    }

    // MARK: - Produce

    /// Produce the thumb at the ruled tier, write it through, and bind the
    /// row. Returns nil only when production is genuinely impossible
    /// (missing file / no render leg for a tier-B image).
    func produce(relPath: String, row: SessionIndexRow) async -> CGImage? {
        let url = sessionRoot.appendingPathComponent(relPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let tier = Self.tier(forRow: row)

        // ── Tier A: the embedded preview (ImageIO). ──
        if tier == .embedded {
            if let image = Self.embeddedPreview(url: url) {
                await bind(tier: .embedded, image: image, relPath: relPath, row: row)
                return image
            }
            // FALLBACK (camera-domain fact — some RAWs ship no embedded
            // preview): one-shot tier B. See the header note.
            Self.logger.info(
                "thumb tier A miss (no embedded preview): \(relPath, privacy: .public) — falling back to tier B"
            )
        }

        // ── Tier B: the real pipe render (injected leg). ──
        guard let renderLeg else { return nil }
        do {
            let request = try await buildRenderRequest(url: url, row: row)
            let image = try await renderLeg(request)
            await bind(tier: .rendered, image: image, relPath: relPath, row: row)
            return image
        } catch {
            // A failed thumb never blocks the browser — it just misses
            // again next fetch (SC#2 posture).
            Self.logger.error(
                "thumb tier B render failed: \(relPath, privacy: .public) — \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Write-through + bind: disk file + memory LRU + the index row
    /// (state/path/params_hash — the T2 binding leg).
    private func bind(
        tier: SessionThumbnailTier, image: CGImage, relPath: String, row: SessionIndexRow
    ) async {
        do {
            let url = try disk.write(image, relPath: relPath)
            await memory.insert(image, for: relPath)
            try await store.updateThumbnailRecord(
                relPath: relPath,
                state: tier.producedState,
                thumbPath: url.path,
                paramsHash: row.paramsHash
            )
        } catch {
            Self.logger.error(
                "thumb bind failed: \(relPath, privacy: .public) — \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Tier A: ImageIO embedded preview

    /// `CGImageSourceCreateThumbnailAtIndex` over the RAW's embedded JPEG.
    /// nil = the file has no usable embedded preview (camera-domain fact —
    /// the tier-B fallback covers it).
    public nonisolated static func embeddedPreview(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // kCGImageSourceThumbnailMaxPixelSize 720 (D7): supersample the 360
        // display size; `CreateThumbnailAtIndex` prefers the embedded JPEG
        // when it is large enough — full decode is NOT paid for a preview
        // thumb.
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: embeddedPreviewMaxPixel,
            // Prefer the embedded preview; a FULL decode only if absent.
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Tier B: the render-request build (sidecar-truth materialize)

    /// Decode + materialize: the SAME instance-merge semantics as the
    /// coordinator's sidecar restore (effective chain latest-wins over the
    /// persisted base set, v50-ordered), the SAME unknown-op degrade, the
    /// SAME layer-stack rebuild — but WITHOUT touching any coordinator
    /// state (the per-image isolation: the editor's current-image pipeline
    /// is never consulted or disturbed).
    func buildRenderRequest(url: URL, row: SessionIndexRow) async throws
        -> ThumbnailRenderRequest
    {
        // Decode (injectable for the queue-semantics tests; the app wires
        // its RAWDecoder).
        let decoded: DecodedImage
        if let decodeLeg {
            decoded = try await decodeLeg(url)
        } else if let decoder {
            decoded = try await decoder.decode(url)
        } else {
            throw AppError.decodeFailed("thumbnail tier B: no decode leg wired")
        }

        // Sidecar document (真身恒 sidecar). A tier-B image without a
        // readable sidecar renders the DEFAULT chain (the same degrade the
        // load path applies to a vanished sidecar — never a crash).
        let sidecarURL = LightamerSidecar.sidecarURL(for: url)
        let document = try? JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL)
        )

        // The stable imageID: sidecar truth → the index row's anchor → a
        // freshly MINTED UUID (the load path's pristine-mint semantics: a
        // never-edited image has no sidecar anchor; the mint is per-render
        // only — the cache key needs A uuid, nothing persists it).
        let fallbackID = row.imageID.flatMap(UUID.init(uuidString:))
        let imageID = document?.imageID ?? fallbackID ?? UUID()

        // Unknown-op degrade (checkpoint lock #4) + the base-set merge
        // (EditorState.restoreFromSidecar semantics, inlined — Core has no
        // EditorState).
        var unknownFreeHistory = HistoryStack()
        if let document {
            let (degraded, _) = await document.degradedForUnknownOps(registry: registry)
            unknownFreeHistory = degraded
        }
        let effective = unknownFreeHistory.effectiveInstances()
        var records = effective
        if let persisted = document?.instances {
            for record in persisted
            where !effective.contains(where: {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }) {
                records.append(record)
            }
        }
        records.sort {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }

        // Materialize boxes via the registry (the coordinator's
        // rematerializeInstances shape).
        var boxes: [any ModuleBoxing] = []
        boxes.reserveCapacity(records.count)
        for record in records {
            if let box = await registry.makeBox(
                opName: record.opName, instanceID: record.id
            ) {
                do {
                    try box.apply(record)
                } catch {
                    Self.logger.error(
                        "thumb instance apply failed (\(record.opName, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                    )
                    continue
                }
                boxes.append(box)
            }
        }

        // The layer stack (06-05): degraded record → runtime layers → a
        // fresh stack. nil = no composite (the flat process path preserves
        // the exact legacy key space — the Phase 8 contract).
        var layerStack: LayerStack?
        if let document {
            let (layerRecord, _) = await document.degradedLayerStack(registry: registry)
            if let layerRecord, !layerRecord.layers.isEmpty {
                var stack = LayerStack(baseLayer: BackgroundLayer())
                for layer in layerRecord.runtimeLayers {
                    stack.addAdjustment(layer)
                }
                layerStack = stack.compositeLayers.isEmpty ? nil : stack
            }
        }

        // The yiyin per-run context (the CONTRACT twin — see the header).
        runContextInjector?(boxes, decoded, .thumbnail, PipeResolution.thumbnail.defaultLongEdge)

        return ThumbnailRenderRequest(
            url: url,
            imageID: imageID,
            decoded: decoded,
            instances: boxes,
            layerStack: layerStack,
            resolution: .thumbnail
        )
    }

    // MARK: - Row access

    private func fetchRow(_ relPath: String) async -> SessionIndexRow? {
        (try? await store.fetchRow(relPath: relPath)) ?? nil
    }
}
