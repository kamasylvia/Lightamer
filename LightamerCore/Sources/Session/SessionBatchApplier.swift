import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionBatchApplier (Plan 09-04 T3) — the LAZY three-segment batch apply
// (dt `_control_paste_history_job_run`, control_jobs.c:1607-1676, structure
// twin):
//
//   段1  MEMORY compose (ZERO render, ZERO decode, ZERO pixel I/O): for
//        each target, read its DISK SIDECAR (真身恒 sidecar — the D-
//        09-CONTEXT-4 contract's first scene: the index column is NEVER
//        consulted for parameters) and compose the new document through
//        `PasteSemantics.paste`. The live target (currently edited) is
//        SKIPPED here — the interactive layer pastes it itself (dt
//        `_safe_history_job_on_imgid`, control_jobs.c:1600-1607).
//   段2  INDEX single transaction: claim the new state for ALL targets in
//        ONE txn (params_hash marked「待生效」via dirty=1, has_edits,
//        layer summary, thumb stale). 10k rows = one txn (the 9-1
//        discipline; the PERF-07 gate body).
//   段3  SIDECAR serial write queue (BatchSidecarWriter, T4): background,
//        per-target atomic promotion, dirty=0 write-back, progress. A
//        crash in the window heals from the sidecars (the D-09-CONTEXT-4
//        contract; the heal leg rides the 9-1 open sync).
//
// **Lazy-render red line (review checkpoint):** this type has NO decode
// leg, NO pipe reference, NO Metal type in its signature set — a pixel
// cannot be rendered by construction. Thumbnails are only stale-marked
// (dt history.c:997 只失效不重渲); the 9-3 background queue regenerates.
// ─────────────────────────────────────────────────────────────────────────────

/// The batch apply bookkeeping (the test + UI assertion face).
public struct BatchApplyOutcome: Sendable, Equatable {
    /// relPaths whose documents were composed + claimed (segment 1+2).
    public var appliedRelPaths: [String]
    /// The live target(s) skipped by the batch loop (the interactive layer
    /// pastes them itself).
    public var skippedLiveRelPaths: [String]
    /// relPaths with an UNREADABLE sidecar (skipped, never a hard failure —
    /// the row keeps its old state; SC#2 posture).
    public var failedRelPaths: [String]

    public init(
        appliedRelPaths: [String] = [],
        skippedLiveRelPaths: [String] = [],
        failedRelPaths: [String] = []
    ) {
        self.appliedRelPaths = appliedRelPaths
        self.skippedLiveRelPaths = skippedLiveRelPaths
        self.failedRelPaths = failedRelPaths
    }
}

public enum SessionBatchApplier {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "batch-apply")

    /// 段1: compose the new documents for every target from its DISK
    /// sidecar. Pure over the filesystem's `.lra` bytes — no index reads.
    ///
    /// - Parameters:
    ///   - skipRelPaths: the live target(s) (skipped — live protection).
    ///   - seed: the identity-default seed (the compose base).
    ///   - label: the paste commit label (caller-localized).
    public static func composeSegment(
        root: URL,
        relPaths: [String],
        skipRelPaths: Set<String>,
        payload: PastePayload,
        mode: PasteMode,
        seed: [ModuleInstance],
        selection: Set<PastePayload.InstanceKey>? = nil,
        timestamp: Date = Date(),
        label: String
    ) -> (composed: [(relPath: String, document: LightamerSidecar)], skippedLive: [String], failed: [String]) {
        var composed: [(String, LightamerSidecar)] = []
        var skipped: [String] = []
        var failed: [String] = []
        composed.reserveCapacity(relPaths.count)

        for relPath in relPaths {
            // LIVE PROTECTION (dt `_safe_history_job_on_imgid`): the image
            // being edited never enters the batch loop.
            if skipRelPaths.contains(relPath) {
                skipped.append(relPath)
                continue
            }
            let imageURL = root.appendingPathComponent(relPath)
            let sidecarURL = LightamerSidecar.sidecarURL(for: imageURL)
            let decoder = JSONDecoder()

            // 真身恒 sidecar: the DISK document is the compose input — the
            // index row's parameter columns are NEVER read here (D-
            // 09-CONTEXT-4's contract, first scene).
            let targetHistory: HistoryStack
            let targetInstances: [ModuleInstance]
            let decodeParamsHash: UInt64
            let imageID: UUID
            let decoderVersion: String
            if let data = try? Data(contentsOf: sidecarURL),
               let document = try? decoder.decode(LightamerSidecar.self, from: data) {
                targetHistory = document.history
                targetInstances = document.instances
                decodeParamsHash = document.decodeParamsHash
                imageID = document.imageID
                decoderVersion = document.decoderVersionUsed
            } else {
                // A pristine target (no readable sidecar) composes from the
                // empty stack + the seed. The decode stamp is unknowable
                // without a decode (never paid in the batch — the lazy red
                // line), so the minted doc carries 0/0 SELF-CONSISTENTLY:
                // `driftDetected` recomputes from the file's OWN two fields,
                // so the later load never false-positives (the live-decode
                // diff is informational in the restore path).
                targetHistory = HistoryStack()
                targetInstances = seed
                decodeParamsHash = 0
                imageID = UUID()
                decoderVersion = "unknown-batch"
            }

            guard let result = PasteSemantics.paste(
                targetHistory: targetHistory,
                targetInstances: targetInstances,
                payload: payload, mode: mode, seed: seed,
                selection: selection, timestamp: timestamp, label: label)
            else {
                // An empty effective payload pastes nothing (dt posture).
                skipped.append(relPath)
                continue
            }

            let historyHash = HistoryHash.hash(
                stack: result.history, decodeParamsHash: decodeParamsHash,
                layerSnapshot: result.layerStack?.snapshot)
            let document = LightamerSidecar(
                imageID: imageID,
                decoderVersionUsed: decoderVersion,
                decodeParamsHash: decodeParamsHash,
                instances: result.instances,
                history: result.history,
                historyHash: historyHash,
                appVersion: LightamerSidecar.currentAppVersion,
                layerStack: result.layerStack)
            composed.append((relPath, document))
        }
        return (composed, skipped, failed)
    }

    /// 段1+段2 (+ 段3 when a writer is supplied): the full apply.
    ///
    /// - Parameters:
    ///   - store: the session index (segment 2's single transaction).
    ///   - writer: the segment-3 serial queue (nil = index+memory only —
    ///     the PERF-07 gate measures 1+2 with this nil).
    ///   - progress: `(completed, total)` on the writer's drain (UI face).
    @discardableResult
    public static func apply(
        root: URL,
        relPaths: [String],
        payload: PastePayload,
        mode: PasteMode,
        seed: [ModuleInstance],
        selection: Set<PastePayload.InstanceKey>? = nil,
        liveRelPaths: Set<String> = [],
        store: SessionIndexStore,
        writer: BatchSidecarWriter?,
        timestamp: Date = Date(),
        label: String,
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async -> BatchApplyOutcome {
        let segment1 = composeSegment(
            root: root, relPaths: relPaths, skipRelPaths: liveRelPaths,
            payload: payload, mode: mode, seed: seed, selection: selection,
            timestamp: timestamp, label: label)

        guard !segment1.composed.isEmpty else {
            return BatchApplyOutcome(
                appliedRelPaths: [],
                skippedLiveRelPaths: segment1.skippedLive,
                failedRelPaths: segment1.failed)
        }

        // 段2: the index claim — ONE transaction for ALL targets (10k rows
        // = one txn). The claimed params_hash is「待生效」until the writer
        // clears each row's dirty flag (the consistency-window contract).
        let claims: [SessionIndexStore.BatchApplyClaim] = segment1.composed.map { relPath, document in
            SessionIndexStore.BatchApplyClaim(
                relPath: relPath,
                paramsHash: String(document.historyHash), // L013 decimal TEXT
                hasEdits: document.history.position >= 0 ? 1 : 0,
                layerCount: document.layerStack.map { Int64($0.layers.count) },
                layerSummary: document.layerStack.map(SessionIndexStore.layerSummaryJSON))
        }
        do {
            try await store.claimBatchApply(claims: claims)
        } catch {
            // The claim transaction rolled back — the rows keep their old
            // state; the sidecars were NOT written (segment 3 never runs).
            // Surfaced as failures, never a hard crash (SC#2 posture).
            Self.logger.error(
                "batch claim failed: \(error.localizedDescription, privacy: .public)")
            return BatchApplyOutcome(
                appliedRelPaths: [],
                skippedLiveRelPaths: segment1.skippedLive,
                failedRelPaths: segment1.composed.map(\.relPath))
        }

        // 段3: the serial sidecar write queue (background from the
        // caller's perspective — apply returns after ENQUEUE, the drain
        // proceeds with progress; flushForTeardown covers the leftovers).
        if let writer {
            await writer.enqueue(segment1.composed, progress: progress)
        } else {
            progress?(segment1.composed.count, segment1.composed.count)
        }

        return BatchApplyOutcome(
            appliedRelPaths: segment1.composed.map(\.relPath),
            skippedLiveRelPaths: segment1.skippedLive,
            failedRelPaths: segment1.failed)
    }
}
