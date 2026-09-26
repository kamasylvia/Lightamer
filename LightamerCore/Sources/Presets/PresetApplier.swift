import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PresetApplier (Plan 12-4 T2; PRES-04; D-12-CONTEXT-5) — the preset apply
// leg: apply = PASTE, by construction.
//
// A develop preset is a PastePayload twin on disk (the copy's compose产物 —
// skip set already applied), so the apply path REUSES the 9-4 batch face
// verbatim (D-09-CONTEXT-5 正本; the plan's 复用清单):
//
//   load     PresetsStore.loadDocument (typed errors; the disk truth read)
//   payload  PastePayload 直构 (records → runtime instances, fresh
//            sourceImageID, file mtime as copiedAt)
//   段1      SessionBatchApplier.composeSegment — memory merge off the DISK
//            sidecar (真身恒 sidecar), live targets skipped
//            (dt _safe_history_job_on_imgid), empty payload no-ops
//   段2      SessionIndexStore.claimBatchApply — ONE transaction; THIS is
//            the semantically-correct seam: a preset FLIPS params, so
//            params_hash flips AND the thumbnails go stale (只失效不重渲
//            — the 9-3 queue regenerates). The 12-1 metadata claim
//            (claimMetadataApply) is the OPPOSITE semantics by design —
//            a rating must not stale anything. The contrast is the core
//            test face (PresetApplierTests).
//   段3      BatchSidecarWriter's serial queue + per-row dirty=0 write-back
//
// ZERO new merge/index/render code: the whole body delegates to
// `SessionBatchApplier.apply` with a payload built from the preset
// document. The lazy-render red line, the live protection, the failure
// degradation and the 万张 ≤5s gate all inherit from the 9-4 face.
//
// An export preset does NOT enter the pipeline (its face is the export
// panel filling ExportState — T4): applying one is the TYPED
// exportPresetNotApplicable error.
// ─────────────────────────────────────────────────────────────────────────────

public enum PresetApplier {

    /// The typed apply-entry rejection (the store's load errors surface
    /// verbatim as `PresetError` — typed, never a silent fallback).
    public enum ApplyError: Error, Equatable, Sendable {
        /// An export preset was routed into the develop-apply face.
        case exportPresetNotApplicable(name: String)
    }

    /// The disk-time of a preset file (the payload's copiedAt diagnostics
    /// stamp). Fallback = now (the stamp is informational only).
    public static func fileTime(store: PresetsStore, presetID: String) -> Date {
        let fileURL = store.directory.appendingPathComponent(
            presetID + "." + PresetsStore.fileExtension)
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL.path)
        return (attributes?[.modificationDate] as? Date) ?? Date()
    }

    /// The PastePayload twin construction: the persisted document → the
    /// 9-4 clipboard shape. `sourceImageID` is FRESH (a preset has no
    /// source image); the layer stack rides the document's (v1: nil — the
    /// additive reservation).
    public static func makePayload(
        from document: LightamerPreset, copiedAt: Date
    ) -> PastePayload {
        PastePayload(
            sourceImageID: UUID(),
            sourceURL: nil,
            instances: document.instances,
            layerStack: document.layerStack,
            copiedAt: copiedAt)
    }

    /// The full apply: load → payload → `SessionBatchApplier.apply`
    /// (segments 1+2+3, verbatim reuse). Returns the 9-4 outcome shape.
    ///
    /// - Parameters:
    ///   - presetsStore: the preset library (the load's truth read).
    ///   - indexStore / writer: the session's segment-2/3 pair (nil writer
    ///     = the gate shape — segments 1+2 only).
    ///   - seed: the identity-default seed (the compose base).
    ///   - selection: optional partial-apply subset (the PRES-04 checked
    ///     keys; rides `payload.filtered(by:)` inside the paste).
    ///   - liveRelPaths: the live target(s) — the batch loop skips them
    ///     and the INTERACTIVE layer pastes them (the caller routes the
    ///     live leg through EditorState, exactly like ⌘⇧V).
    @discardableResult
    public static func apply(
        presetID: String,
        presetsStore: PresetsStore,
        root: URL,
        relPaths: [String],
        mode: PasteMode,
        seed: [ModuleInstance],
        selection: Set<PastePayload.InstanceKey>? = nil,
        liveRelPaths: Set<String> = [],
        indexStore: SessionIndexStore,
        writer: BatchSidecarWriter?,
        timestamp: Date = Date(),
        label: String,
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> BatchApplyOutcome {
        let document = try presetsStore.loadDocument(id: presetID)
        guard document.kind == .develop else {
            throw ApplyError.exportPresetNotApplicable(name: document.name)
        }
        let payload = makePayload(
            from: document, copiedAt: fileTime(store: presetsStore, presetID: presetID))
        return await SessionBatchApplier.apply(
            root: root,
            relPaths: relPaths,
            payload: payload,
            mode: mode,
            seed: seed,
            selection: selection,
            liveRelPaths: liveRelPaths,
            store: indexStore,
            writer: writer,
            timestamp: timestamp,
            label: label,
            progress: progress)
    }
}
