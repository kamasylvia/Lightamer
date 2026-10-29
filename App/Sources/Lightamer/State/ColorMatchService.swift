import Foundation
import LightamerCore
import LightamerIOP
import OSLog

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchService (Plan M5-1-02 T6, KD-6 + checker 回注 E5/E6) — the solve
// orchestration face of the TRACK color-match family: the PIPELINE-LEVEL
// statistics extraction, the pooling + solve fan, the `.cube` asset commit,
// and the store-level attach seam.
//
// E6 (the pipeline-level extraction): `extractStats(document:bucket:)` runs
// an IN-PIPE headless render into the requested bucket and taps the
// colormatch box's INPUT plane — it depends on NO GUI session state. The
// live editor's Solve button and a headless (MCP) caller feed the SAME API
// through the same `ColorMatchDocument` value face (the GUI PREVIEW
// completion point would be one call site of this API, not a second
// extraction path — P3's 零新提取路径 red line holds).
//
// E5 (the source-statistics plane): the tap fires at the colormatch box's
// INPUT plane — the in-point tap IS the bypass-by-construction. A first
// solve (no colormatch instance) injects an IDENTITY armed box at the v50
// slot; a re-solve (instance active) arms the REAL box's input. Both
// planes are the same chain position ⇒ the source statistics are decoupled
// from the instance's own output ⇒ a re-solve cannot fold the instance's
// own effect into the next solve (no feedback collapse; the G1 solve-twice
// byte-stability).
//
// REFERENCES (OQ-7): reference-side statistics = the reference image's
// PRISTINE render at the THUMBNAIL bucket through the SAME extractStats
// face (no region parameter — the full-image domain; edited-reference is
// the registered V2 note).
//
// ATTACH (the store-level seam): the solved params project onto the
// instance set through `projectColormatch` — the SAME
// (opName, multiPriority) upsert semantics `EditingToolset.projectInstances`
// runs for apply_params — then ONE discrete history commit on the live leg
// (the GUI panel) or the disk projection for headless targets (the MCP
// match_color consumer in M5-1-03 reuses the same seam).
// ─────────────────────────────────────────────────────────────────────────────

/// The renderable document face `extractStats` consumes — the live editor
/// and any headless caller produce the same value.
struct ColorMatchDocument: Sendable {
    let image: DecodedImage
    let instances: [ModuleInstance]
    let layerStack: LayerStack?
    /// The cache namespace (the live document's minted ID; headless
    /// callers mint a throwaway one — the extraction render uses a
    /// throwaway cache, the ID only namespaces it).
    let imageID: UUID
    /// M9-4 T2 (the threading face): the document's stored process —
    /// nil = headless/pristine callers (`.legacy` at the render entry,
    /// the correct value: a throwaway extraction has no stored carrier).
    /// Defaulted so the pre-M9-4 construction sites compile untouched.
    var renderProcess: RenderProcessVersion? = nil
}

/// The extraction bucket policy (E6): the source plane renders at the
/// PINNED 512 preview bucket (a re-solve at any zoom sees the same plane —
/// the solve-twice stability's resolution half); the reference plane at
/// the THUMBNAIL default (pristine, 360).
enum ColorMatchExtractBucket {
    static let sourcePreviewCap = 512
}

/// The session resolver — the module's `ColormatchAssetResolving`
/// injection (the LutLibraryStore.sharedResolver 同形, session-scoped):
/// curves from the service's solve store, assets resolved against the
/// CURRENT image anchor. `@unchecked Sendable` carries the lock contract.
final class ColorMatchSessionResolver: ColormatchAssetResolving, @unchecked Sendable {

    private let lock = NSLock()
    private var curves: [String: ColorMatchCDFSolution] = [:]
    private var imageURL: URL?
    /// The last load-degrade reason (the panel readout's probe face).
    private(set) var lastDegradeReason: String?

    func setCurrentImageURL(_ url: URL?) {
        lock.withLock { imageURL = url }
    }

    /// Store the curves behind one solve (keyed by the stats-hash pair —
    /// the module's lookup key).
    func storeCurves(_ solution: ColorMatchCDFSolution, sourceHash: UInt64, referenceHash: UInt64) {
        lock.withLock {
            curves["\(sourceHash)|\(referenceHash)"] = solution
        }
    }

    /// Drop every stored curve (the re-solve edge — the FilmSolveCache
    /// invalidateAll 体例; value-invisible: a re-solve recomputes bytes).
    func invalidateCurves() {
        lock.withLock { curves.removeAll() }
        lock.withLock { lastDegradeReason = nil }
    }

    // MARK: ColormatchAssetResolving

    func loadCube(
        assetRef: String, expectedHash: String?
    ) -> ColormatchCubeAsset.LoadResult {
        let anchor: URL? = lock.withLock { imageURL }
        guard let anchor else {
            return .degraded(reason: "colormatch asset unresolvable (no image anchor)")
        }
        let result = ColormatchCubeAsset.load(
            assetRef: assetRef, forImageURL: anchor, expectedHash: expectedHash)
        if case .degraded(let reason) = result {
            lock.withLock { lastDegradeReason = reason }
        } else {
            lock.withLock { lastDegradeReason = nil }
        }
        return result
    }

    func cdfSolution(
        sourceStatsHash: String, referenceStatsHash: String
    ) -> ColorMatchCDFSolution? {
        lock.withLock { curves["\(sourceStatsHash)|\(referenceStatsHash)"] }
    }
}

@MainActor
@Observable
final class ColorMatchService {

    static let logger = Logger(subsystem: "com.kamasylvia.lightamer", category: "colormatch")

    /// The pipe primitives the extraction render consumes (the composition
    /// root injects; tests inject their own). nil = not yet configured —
    /// extraction throws typed.
    private var metal: MetalContext?
    private var registry: ModuleRegistry?

    /// The composition-root configuration (the app's `.task` calls it once
    /// after the registry population; idempotent). Installs the session
    /// resolver into the SHARED box (the registry factory's forward reads
    /// it — the live pipe's colormatch boxes get the curves + assets).
    func configure(metal: MetalContext, registry: ModuleRegistry) {
        self.metal = metal
        self.registry = registry
        ColormatchResolverBox.replaceShared(resolver)
    }

    /// The session resolver (installed into every colormatch box the
    /// extraction and the live pipe materialize).
    let resolver = ColorMatchSessionResolver()

    /// The last SOURCE statistics this service extracted (the panel
    /// readout's support-width face — session state, never persisted).
    private(set) var lastSourceStats: ColorMatchStats?

    /// The last reference statistics per image URL (the pooled re-solve's
    /// extraction cache — session state; the Solve button's invalidateAll
    /// drops it).
    private var referenceStatsCache: [URL: ColorMatchStats] = [:]

    init(metal: MetalContext? = nil, registry: ModuleRegistry? = nil) {
        self.metal = metal
        self.registry = registry
    }

    // MARK: - Extraction (the E6 pipeline-level API)

    /// Extract the colormatch input-plane statistics of `document` via an
    /// in-pipe headless render at `bucket` (nil = the THUMBNAIL default).
    /// No GUI session state involved — the live editor and MCP callers
    /// feed the same face.
    func extractStats(
        document: ColorMatchDocument, bucket: Int?
    ) async throws -> ColorMatchStats {
        guard let registry, let metal else {
            throw AppError.decodeFailed("colormatch: the pipe faces are not configured")
        }
        // The armed box: the REAL colormatch record when present (its
        // input plane), else an IDENTITY record injected at the v50 slot
        // (the first-solve posture — nothing to bypass yet, the tap plane
        // is identical by construction).
        var records = document.instances
        let existing = records.first { $0.opName == ColormatchModule.opName }
        let armedInstanceID: UUID
        if let existing {
            armedInstanceID = existing.id
        } else {
            let synthetic = ModuleInstance(
                module: ColormatchModule.self, multiPriority: 0,
                multiName: "colormatch-extract", params: ColormatchModule.Params())
            records.append(synthetic)
            records.sort {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            }
            armedInstanceID = synthetic.id
        }
        let (boxes, _) = await registry.materializeBoxes(for: records)
        guard let box = boxes.first(where: {
            $0.opName == ColormatchModule.opName && $0.instanceID == armedInstanceID
        }) as? ModuleBox<ColormatchModule> else {
            throw AppError.decodeFailed("colormatch extraction: the armed box did not materialize")
        }
        box.module.armStatsCapture()

        // The headless render: a THROWAWAY cache keeps the extraction
        // hermetic (no live-cache coupling); the terminal tail is inert
        // for the tap (the capture fires at the colormatch slot, upstream
        // of the display legs).
        let cache = PipeCache()
        let resolution: PipeResolution = bucket == nil ? .thumbnail : .preview
        if let stack = document.layerStack, !stack.compositeLayers.isEmpty {
            _ = try await RenderPipeline.processComposite(
                image: document.image, instances: boxes, layerStack: stack,
                registry: registry, imageID: document.imageID,
                resolution: resolution, cache: cache, metal: metal,
                longEdge: bucket, roiHint: nil,
                policy: resolution == .full ? .fullColdLayer : .preview,
                hotLayerID: nil, maskDirectory: nil,
                terminalTail: .sdrGamma, filmTail: nil,
                renderProcess: document.renderProcess ?? .legacy)
        } else {
            _ = try await RenderPipeline.process(
                image: document.image, instances: boxes, imageID: document.imageID,
                resolution: resolution, cache: cache, metal: metal,
                longEdge: bucket, terminalTail: .sdrGamma, filmTail: nil,
                renderProcess: document.renderProcess ?? .legacy)
        }
        guard let stats = box.module.consumeCapturedStats() else {
            throw AppError.decodeFailed("colormatch extraction: the armed tap never fired")
        }
        Self.logger.info(
            "colormatch extractStats: \(stats.sampleCount) samples, hash \(stats.statsHash)")
        return stats
    }

    /// The LIVE document face (the editor's call shape): the coordinator's
    /// decoded image + the current instance set + layer stack. A nil
    /// decoded state throws typed (the panel disables Solve without an
    /// image anyway).
    func liveDocument(
        coordinator: PipeCoordinator, editorState: EditorState
    ) throws -> ColorMatchDocument {
        guard let image = coordinator.detectionSourceImage() else {
            throw AppError.decodeFailed("colormatch: no image loaded")
        }
        return ColorMatchDocument(
            image: image, instances: editorState.instances,
            layerStack: editorState.layerStack,
            imageID: coordinator.currentImageID ?? UUID(),
            renderProcess: coordinator.documentProcessVersion)
    }

    /// The SOURCE statistics of the live document (the pinned 512 preview
    /// bucket — E5's plane + the solve-twice resolution half). Refreshes
    /// the panel readout's support face.
    func extractSourceStats(
        coordinator: PipeCoordinator, editorState: EditorState
    ) async throws -> ColorMatchStats {
        let document = try liveDocument(coordinator: coordinator, editorState: editorState)
        let stats = try await extractStats(
            document: document, bucket: ColorMatchExtractBucket.sourcePreviewCap)
        lastSourceStats = stats
        resolver.setCurrentImageURL(coordinator.liveImageURL)
        return stats
    }

    /// The REFERENCE statistics of an image file: the PRISTINE decode +
    /// THUMBNAIL-bucket render through the SAME extractStats face (OQ-7:
    /// the full-image domain; edits never influence the statistics — the
    /// pristine semantics). Session-cached per URL.
    func extractReferenceStats(imageURL: URL, decoder: RAWDecoder) async throws -> ColorMatchStats {
        if let cached = referenceStatsCache[imageURL] { return cached }
        let decoded = try await decoder.decode(imageURL, technicalOverrides: .init())
        let document = ColorMatchDocument(
            image: decoded, instances: [], layerStack: nil, imageID: UUID(),
            renderProcess: nil)
        let stats = try await extractStats(document: document, bucket: nil)
        referenceStatsCache[imageURL] = stats
        return stats
    }

    // MARK: - Solve + attach

    /// Solve source → pooled references with `solver` and land the result
    /// on the live document (ONE discrete commit). Returns the attached
    /// params (the panel's readout face).
    ///
    /// - For the linear arms the params carry the matrix/offset (no asset).
    /// - For `.cdf` the curves ride the session resolver and the baked
    ///   table lands as a `.cube` asset beside the image (the commit-time
    ///   IO — KD-3); the params carry `{assetRef, assetHash}`.
    @discardableResult
    func solveAndAttach(
        source: ColorMatchStats, references: [ColorMatchPoolEntry],
        solver: ColorMatchSolverKind, strength: Float,
        editorState: EditorState, coordinator: PipeCoordinator
    ) async throws -> ColormatchModule.Params {
        let pooled = try ColorMatchPooling.pool(references)
        var params = ColormatchModule.Params()
        params.solver = solver
        params.strength = strength
        params.sourceStatsHash = String(source.statsHash)
        params.referenceStatsHash = String(pooled.statsHash)

        switch solver {
        case .gaussianOT, .reinhard:
            let solution = ColorMatchSolver.solve(
                source: source, reference: pooled, solver: solver)
            params.matrix = solution.matrix
            params.offset = solution.offset
            params.effectiveSolver = solution.effectiveSolver
            ColorMatchSolveCache.shared.invalidateAll()
        case .cdf:
            guard let imageURL = coordinator.liveImageURL else {
                throw AppError.decodeFailed("colormatch: no image anchor for the asset")
            }
            // The shared-box safety net: any solve wires THIS session's
            // resolver into the factory forward (the app holds ONE service;
            // idempotent with configure()).
            ColormatchResolverBox.replaceShared(resolver)
            let solution = ColorMatchCDFSolver.solve(source: source, reference: pooled)
            resolver.storeCurves(
                solution, sourceHash: source.statsHash, referenceHash: pooled.statsHash)
            resolver.setCurrentImageURL(imageURL)
            // The COMMIT-time asset write (the tick path never touches IO).
            let table = ColorMatchBake.bake(solution: solution, strength: strength)
            let directory = ColormatchCubeAsset.directory(forImageURL: imageURL)
            let bytesHash = try ColormatchCubeAsset.write(
                table: table, solutionHash: solution.solutionHash,
                strength: strength, directory: directory)
            params.assetRef = ColormatchCubeAsset.assetRef(
                solutionHash: solution.solutionHash, strength: strength, forImageURL: imageURL)
            params.assetHash = String(bytesHash)
            // The same-solution old-alpha siblings go (best-effort).
            ColormatchCubeAsset.cleanupSameSolution(
                solutionHash: solution.solutionHash,
                keepFileName: ColormatchCubeAsset.fileName(
                    solutionHash: solution.solutionHash, strength: strength),
                directory: directory)
        }

        // The store-level projection seam (E6): the SAME (opName,
        // multiPriority) upsert apply_params runs; then ONE discrete
        // history commit (the per-instance params channel — zero new
        // history key family).
        let current = editorState.instances
        let desired = Self.projectColormatch(current: current, params: params)
        guard desired != current else { return params }
        if let index = current.firstIndex(where: {
            $0.opName == ColormatchModule.opName && $0.multiPriority == 0
        }) {
            editorState.recordChange(
                desired[index], label: String(localized: "history_colormatch"))
        } else {
            // The CREATE face: the record lands through the base-chain add
            // (fresh identity minted there — one "add module" item).
            guard let template = desired.first(where: {
                $0.opName == ColormatchModule.opName && $0.multiPriority == 0
            }) else {
                throw AppError.decodeFailed("colormatch attach: the projection lost the record")
            }
            _ = editorState.addModuleToBaseChain(template: template)
        }
        return params
    }

    /// The pure projection (the store-level seam's core): upsert the
    /// colormatch record (multiPriority 0) over `current` — replace in
    /// place (identity + iopOrder preserved), append (sorted in) when
    /// absent. The apply_params projectInstances 同缝.
    static func projectColormatch(
        current: [ModuleInstance], params: ColormatchModule.Params
    ) -> [ModuleInstance] {
        var instances = current
        if let index = instances.firstIndex(where: {
            $0.opName == ColormatchModule.opName && $0.multiPriority == 0
        }) {
            var record = instances[index]
            try? record.setParams(params, as: ColormatchModule.self)
            instances[index] = record
        } else {
            let record = ModuleInstance(
                module: ColormatchModule.self, multiPriority: 0,
                multiName: "colormatch", params: params)
            instances.append(record)
            instances.sort {
                ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
            }
        }
        return instances
    }

    /// The re-solve edge (the panel's Solve button): drop the session
    /// curves + the reference cache + the linear solve cache — the next
    /// solve re-extracts and re-runs everything (the G1 re-solve closure:
    /// same inputs → byte-identical products).
    func invalidateAll() {
        resolver.invalidateCurves()
        referenceStatsCache.removeAll()
        ColorMatchSolveCache.shared.invalidateAll()
        lastSourceStats = nil
    }
}
