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

    /// The stable per-layer mask file name (same name on every re-bake —
    /// D-07-CONTEXT-5 overwrite semantics).
    func fileName(forLayerID layerID: UUID) -> String {
        "\(rawValue)-\(layerID.uuidString).png"
    }

    /// True when `fileName` was produced by this source (the re-entry
    /// marker: re-arming the tap mode on a layer-B mask seeds a REFINE
    /// session pointing at the same file).
    static func source(ofFileName fileName: String) -> AIMaskSource? {
        for source in [AIMaskSource.subject, .segment, .skin]
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
        metal: MetalContext
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
        let texture = try AIMaskResample.texture(from: upsampled, metal: metal)
        let directory = RasterMaskStore.masksDirectory(forImageURL: anchor)
        let ref = try await RasterMaskStore.bake(
            plane: texture, directory: directory,
            fileName: source.fileName(forLayerID: layerID),
            invert: invert, featherRadius: featherRadius, metal: metal)

        // The mask slot write: KEEP existing payloads (a refine/draw-patch
        // world — the raster ref joins drawn/parametric through the
        // assembler's intersect), swap in the fresh reference.
        var updated = layer
        var mask = layer.mask ?? MaskSpec()
        mask.raster = ref
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
        return ref
    }
}
