import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AIMaskEditing (Plan 07-3 T1/T2/T3) — the AI-mask → layer-mask-slot channel.
//
// The ONE seam every AI generation path (MaskToolbar subject/tap-to-segment,
// SkinSmoothPanel「定位皮肤」) funnels through: an `AIMaskPlane` goes
// upsample→bake→`MaskSpec.raster` on the SELECTED layer, landing as exactly
// ONE stackSnapshot history item (⌘Z removes it; the undo test pins this).
// After the commit the layer's mask edit mode auto-activates and the display
// tint re-issues — the AI-06 interaction form: the user sees an ORDINARY
// raster mask, never an "AI result" (07-RESEARCH §3/§4 非黑箱).
//
// D-07-CONTEXT-5 (same maskID overwrite re-bake): the fileName is derived
// from the layer UUID + the generation SOURCE, so a refine re-bake rewrites
// the same PNG → `RasterMaskRef.maskHash` flips → `MaskSpec.stableHash()`
// flips → the mask-plane/prefix caches invalidate through the Phase 6
// mechanism (no new cache class).
//
// AI GENERATION PARAMETERS NEVER PERSIST (07-CONTEXT 继承定案): quality
// levels / seeds / refine points stay UI state; only the baked PIXELS enter
// the edit semantics — the sidecar schema gains nothing (T4's zero-upgrade
// regression pins this).
// ─────────────────────────────────────────────────────────────────────────────

/// The generation-source prefix of a layer's AI mask file (the refine
/// session re-entry marker + the T2「已有层 B 蒙版」detection).
enum AIMaskSource: String, Sendable {
    /// Layer A subject mask (MaskToolbar「主体蒙版」).
    case subject = "ai-subject"
    /// Layer B tap-to-segment mask (MaskToolbar「点击选取」).
    case segment = "ai-segment"
    /// SkinRegionLocator skin mask (SkinSmoothPanel「定位皮肤」).
    case skin = "ai-skin"
    /// DepthMaskService near mask (MaskToolbar「深度」— M4-3-01). The
    /// `ai-depth` prefix stays disjoint from the segment marker, so the
    /// LayerEditingState segment discriminant is untouched.
    case depth = "ai-depth"
    /// Person instance mask (MaskToolbar「人物实例」— M6-4-02 KD-2/KD-5).
    /// The `ai-person` prefix stays disjoint from the segment marker for
    /// the same reason (a person re-bake must never seed a segment
    /// session — `armSegmentSession` keys on `.segment` only).
    case person = "ai-person"

    /// The stable per-layer mask file name (same name on every re-bake —
    /// D-07-CONTEXT-5 overwrite semantics).
    func fileName(forLayerID layerID: UUID) -> String {
        "\(rawValue)-\(layerID.uuidString).png"
    }

    /// True when `fileName` was produced by this source (the re-entry
    /// marker: re-arming the tap mode on a layer-B mask seeds a REFINE
    /// session pointing at the same file).
    static func source(ofFileName fileName: String) -> AIMaskSource? {
        for source in [AIMaskSource.subject, .segment, .skin, .depth, .person]
        where fileName.hasPrefix(source.rawValue + "-") {
            return source
        }
        return nil
    }
}

/// The layer-B entry gate — a PURE function of the asset phase (the
/// three-state + failure face D-07-CONTEXT-1 mandates; unit-tested without
/// touching the store).
enum AIMaskEntryGate {

    enum LayerBEntry: Equatable, Sendable {
        /// Assets present — the entry opens the tap-to-segment mode.
        case ready
        /// A download is in flight — the entry shows the spinner.
        case downloading
        /// Not downloaded (or never queried and absent) — the entry stays
        /// DISABLED but GUIDED: the adjacent download action offers the
        /// one-time fetch (declined-at-first-launch users re-enter here).
        case needsDownload
        /// The download/status failed — surfaced with its reason, retryable.
        case failed(String)
    }

    static func layerBEntry(for phase: AIAssetPhase) -> LayerBEntry {
        switch phase {
        case .ready:
            return .ready
        case .downloading:
            return .downloading
        case .notReady, .unknown:
            return .needsDownload
        case .failed(let reason):
            return .failed(reason)
        }
    }
}

/// The AI-mask commit channel (see the header note).
@MainActor
enum AIMaskEditing {

    /// The decode-frame inference input (pre-edit semantic anchoring,
    /// 07-CONTEXT 继承定案) + its pixel size. nil when nothing is loaded.
    /// Same read-only seam the ashift auto-detect uses (L014-clean by
    /// construction — the decoder's CIImage is a completed decode graph).
    static func decodeFrameInput(
        _ coordinator: PipeCoordinator
    ) -> (input: AIMaskInput, width: Int, height: Int)? {
        guard let decoded = coordinator.detectionSourceImage() else { return nil }
        let extent = decoded.ciImage.extent
        guard extent.width >= 1, extent.height >= 1 else { return nil }
        return (AIMaskInput(ciImage: decoded.ciImage), Int(extent.width), Int(extent.height))
    }

    /// Upsample→bake→mask-slot commit for the SELECTED layer.
    ///
    /// Exactly ONE stackSnapshot history item (the label localizes through
    /// the caller's key). Returns the baked reference; throws before ANY
    /// state change when preconditions fail (no selection / no image).
    ///
    /// - `imageURL`: the masks-directory anchor; nil = the live session's
    ///   `loadedImageURL` (the production toolbar path). The explicit form
    ///   exists for the state-level tests (which drive the coordinator
    ///   directly, not `EditorState.load`).
    /// - `activateTool`: the mask tool to arm after the commit (nil = leave
    ///   the current mode) — the AI-06 "user lands in ordinary mask
    ///   editing" form.
    /// - `expectedRevision`: the optimistic-concurrency snapshot (KD-5,
    ///   D-M2-7-CONTEXT-9) — the caller's `MaskSpec.contentRevision` value
    ///   read when the bake was requested. nil = legacy callers (no gate).
    ///   A mismatch REFUSES the install (typed error along the 07 face —
    ///   no silent overwrite, no auto-rebake; the rebake decision is the
    ///   user's). The install itself is a history commit leg: it bumps the
    ///   revision exactly once before the commit.
    /// - `patchRebake`: M6-4-02 (KD-1) — TRUE for the patch pass's own
    ///   re-bake: it skips the livePlane capture and the debounce
    ///   re-schedule (otherwise the patch would loop itself). Existing
    ///   callers default false.
    ///
    /// SEGMENT-SESSION SIDES (M6-4-02, source == .segment only): (a) the
    /// session's `featherPercent` resolves the feather — positive → the
    /// GPU bake radius = `AIMaskFeather.sigma` (the existing
    /// `featherRadius` seam, passed value honored only at percent 0);
    /// negative → the CPU logit-gain leg AND the bake radius FORCED 0
    /// (the double-feather pin — one feather, one primitive); zero →
    /// byte-identical to the pre-M6-4-02 path. (b) A successful commit
    /// captures the upsampled (pre-feather) plane as the session's
    /// `livePlane` and schedules the 1s-debounced patch refine.
    @discardableResult
    static func commitRasterMask(
        plane: AIMaskPlane,
        source: AIMaskSource,
        invert: Bool = false,
        featherRadius: Float = 0,
        decodeWidth: Int? = nil,
        decodeHeight: Int? = nil,
        imageURL: URL? = nil,
        label: String,
        activateTool: MaskTool? = .brush,
        coordinator: PipeCoordinator,
        editorState: EditorState,
        editingState: LayerEditingState,
        metal: MetalContext,
        expectedRevision: Int? = nil,
        patchRebake: Bool = false
    ) async throws -> RasterMaskRef {
        guard let layerID = editingState.selectedLayerID,
              let layer = editorState.adjustmentLayer(id: layerID)
        else {
            throw AIMaskError.invalidInput("no selected layer for the AI mask")
        }
        guard let anchor = imageURL ?? editorState.loadedImageURL else {
            throw AIMaskError.invalidInput("no image session for the AI mask")
        }
        // Normalize to the decode frame (layer B's quality-level planes and
        // layer A's label map may be smaller — bilinear, never nearest).
        let upsampled: AIMaskPlane
        if let decodeWidth, let decodeHeight,
           plane.width < decodeWidth || plane.height < decodeHeight {
            upsampled = AIMaskResample.bilinear(
                plane, toWidth: decodeWidth, toHeight: decodeHeight)
        } else {
            upsampled = plane
        }
        // The segment-session feather resolution (KD-3/M5 — the double-
        // feather pin lives HERE: the negative leg's bake radius is 0).
        var bakePlane = upsampled
        var bakeRadius = featherRadius
        if source == .segment {
            (bakePlane, bakeRadius) = resolveFeather(
                plane: upsampled, percent: editingState.segmentSession.featherPercent,
                fallbackRadius: featherRadius)
        }
        let texture = try AIMaskResample.texture(from: bakePlane, metal: metal)
        let directory = RasterMaskStore.masksDirectory(forImageURL: anchor)
        let ref = try await RasterMaskStore.bake(
            plane: texture, directory: directory,
            fileName: source.fileName(forLayerID: layerID),
            invert: invert, featherRadius: bakeRadius, metal: metal)

        // The mask slot write: KEEP existing payloads (a refine/draw-patch
        // world — the raster ref joins drawn/parametric through the
        // assembler's intersect), swap in the fresh reference. The
        // optimistic-concurrency gate reads the layer's LIVE spec (the
        // reference is shared with the stack, so this is the post-await
        // state — a user edit landing during the bake fails the stale
        // expected value here): mismatch = refuse BEFORE any state change.
        if let expectedRevision,
            !MaskSpec.matchesExpected(expectedRevision, in: layer.mask ?? MaskSpec()) {
            let currentRevision = layer.mask?.contentRevision.map(String.init) ?? "0"
            throw AIMaskError.invalidInput(
                "mask content revision mismatch: expected \(expectedRevision), " +
                    "current \(currentRevision) — refusing the AI install")
        }
        var updated = layer
        var mask = layer.mask ?? MaskSpec()
        mask.raster = ref
        // The AI install is a history commit leg (KD-5's write-point table):
        // bump exactly once before the commit.
        mask.bumpContentRevision()
        updated.mask = mask
        editorState.commitLayerEdit(updated, label: label)

        // The AI-06 landing form: hot layer + display tint + the mask edit
        // mode armed (the user sees an ordinary raster mask).
        coordinator.setHotLayer(layerID)
        coordinator.setMaskOverlayRequest(
            (layerID, 0.85, editingState.maskOverlayStyle))
        if let activateTool {
            editingState.setTool(activateTool)
        }
        // The segment session sides (KD-1/M6): the base plane is held and
        // the 1s-debounced patch pass is armed — but NOT for the patch
        // pass's own re-bake (patchRebake breaks the loop).
        if source == .segment, !patchRebake {
            editingState.segmentSession.livePlane = upsampled
            let coordinator = coordinator
            let editorState = editorState
            let editingState = editingState
            let metal = metal
            schedulePatchRefine(session: editingState.segmentSession) {
                await runPatchRefine(
                    coordinator: coordinator, editorState: editorState,
                    editingState: editingState, metal: metal)
            }
        }
        return ref
    }

    // MARK: - M6-4-02: hi-res patch refine + Edge feather (KD-1/KD-3)

    /// The feather RESOLUTION face (the double-feather pin's parameter
    /// surface): percent > 0 → the plane unchanged + the GPU bake radius =
    /// sigma (the CPU face untouched); percent < 0 → the CPU logit-gain
    /// plane + radius FORCED 0; percent == 0 → both legs inert (the
    /// fallback radius — 0 at every existing call site — passes through,
    /// byte-identical to the pre-M6-4-02 path).
    static func resolveFeather(
        plane: AIMaskPlane, percent: Float, fallbackRadius: Float = 0
    ) -> (plane: AIMaskPlane, radius: Float) {
        if percent > 0 {
            let longEdge = max(plane.width, plane.height)
            return (plane, AIMaskFeather.sigma(percent: percent, longEdgePixels: longEdge))
        }
        if percent < 0 {
            return (AIMaskFeather.applyFeatherNegative(plane: plane, percent: percent), 0)
        }
        return (plane, fallbackRadius)
    }

    /// The patch-refine DEBOUNCE (KD-1: 1s after the LAST interaction —
    /// each schedule cancels the previous task, so a burst of interactions
    /// collapses into ONE pass; the last scheduled operation is the one
    /// that runs). `delay` is the injected clock seam (tests shrink it).
    static func schedulePatchRefine(
        session: SegmentSession,
        delay: Duration = .seconds(1),
        operation: @escaping @MainActor () async -> Void
    ) {
        session.patchDebounceTask?.cancel()
        session.patchDebounceTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    /// ONE patch pass (KD-1): plan on the current composed state → patch
    /// re-analysis through `segmentPatch` (the ROI leg, quality .accurate)
    /// → FIFO-cap → recompose → feather-resolved re-bake (same maskID
    /// overwrite, D-07-CONTEXT-5). The skip gates (empty/oversized/min-
    /// side) leave the session plane untouched; ANY failure = the typed
    /// toast + the session plane unchanged (generation failure ≠ load
    /// failure — never an all-ones fallback).
    static func runPatchRefine(
        coordinator: PipeCoordinator,
        editorState: EditorState,
        editingState: LayerEditingState,
        metal: MetalContext
    ) async {
        let session = editingState.segmentSession
        guard session.hasSeed, !session.isGenerating, let base = session.livePlane
        else { return }
        session.patchState = .refining
        defer { session.patchState = .done(count: session.patches.count) }
        do {
            guard let (input, width, height) = decodeFrameInput(coordinator) else {
                return
            }
            // Plan on the CURRENT state (base + already-held patches).
            let current = AIPatchComposer.compose(base: base, patches: session.patches)
            guard let rect = AIPatchPlanner.planPatch(plane: current) else {
                return // a skip gate — legitimately no patch this pass
            }
            let normalized = rect.normalized(
                imageWidth: current.width, imageHeight: current.height)
            guard case let seed? = session.seed else { return }
            let plane = try await AIMaskService.segmentPatch(
                input: input, seed: seed, refine: session.refinePoints,
                patchRect: normalized)
            session.patches = AIPatchComposer.capped(
                session.patches + [AIPatch(rect: rect, plane: plane)])
            let composed = AIPatchComposer.compose(
                base: base, patches: session.patches)
            _ = try await commitRasterMask(
                plane: composed, source: .segment,
                decodeWidth: width, decodeHeight: height,
                label: String(localized: "history_ai_mask"),
                activateTool: nil,
                coordinator: coordinator, editorState: editorState,
                editingState: editingState, metal: metal,
                patchRebake: true)
        } catch {
            editorState.presentToast(
                String(localized: "ai_toast_generate_failed") + " (\(error))")
        }
    }
}
