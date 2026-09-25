import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// BatchSidecarWriter (Plan 09-04 T4) — the segment-3 SERIAL sidecar write
// queue (dt `dt_image_synch_xmps(to_synch)` batch-sync AFTER the loop,
// control_jobs.c:1671-1675).
//
// **Serial, pinned:** concurrent writers are NEGATIVE on spinning disks
// (seek competition, L009) and pointless on APFS for this shape — one
// task, FIFO, no batching window (execution decision D5: the optional
// batch delay stays OFF by default; the sidecar-per-image format lock
// FORBIDS merging multiple images into one file either way).
//
// **Per-target write (L009):** JSON encode (pretty + sortedKeys, the D-S1
// readable format) → same-directory `.tmp-<uuid>` sibling →
// `replaceItemAt`/`moveItem` (the `SidecarStore.writeAtomic` shape — the
// rename is same-VOLUME atomic; a crash leaves at most the tmp sibling,
// never a half-written `.lra`). Every promotion is journaled
// (`SidecarWriteJournal`) so the FSEvents reconciler swallows the self-
// write events (the 09-02 defense ② — 10k un-journaled writes would storm
// the reconciler).
//
// **Dirty write-back:** each successful write flips the row's dirty=0 in
// an independent small transaction — the「待生效」badge lifts per image as
// the drain proceeds (the consistency window narrows monotonically).
//
// **Crash contract (D-09-CONTEXT-4):** a crash mid-drain leaves some rows
// dirty with their sidecars either old (write pending) or new (written,
// dirty not yet cleared). BOTH heal on the next session open: the heal
// leg re-reads the sidecar per dirty row and overwrites the index (the
// sidecar is the truth) — zero data loss, `SessionIndexStore
// .healDirtyRows`.
//
// **Teardown:** `flushForTeardown()` drains the remainder synchronously
// (bounded) — the SessionCoordinator teardown seam and the termination
// seam both call it (dt flushes its XMP sync before the job returns; we
// keep the window because the queue is async by design).
// ─────────────────────────────────────────────────────────────────────────────

public actor BatchSidecarWriter {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "batch-writer")

    /// One queued write.
    struct QueuedWrite: Sendable {
        var relPath: String
        var document: LightamerSidecar
    }

    /// The destination resolver (root + relPath → the `.lra` URL) and the
    /// index store (dirty=0 write-back).
    private let root: URL
    private let store: SessionIndexStore
    private let journal: SidecarWriteJournal

    /// FIFO queue (serial — see the header).
    private var queue: [QueuedWrite] = []
    private var draining = false

    /// The progress counters (completed/total of the CURRENT drain).
    public private(set) var completedCount = 0
    public private(set) var totalCount = 0

    /// Crash-injection seam (tests): when true, the drain stops after the
    /// CURRENT write — pending items stay queued, completed stay done.
    /// Production never sets it.
    private var failAfterNext = false

    public init(
        root: URL,
        store: SessionIndexStore,
        journal: SidecarWriteJournal = .shared
    ) {
        self.root = root
        self.store = store
        self.journal = journal
    }

    // MARK: - Queueing

    /// Enqueue a composed batch and start the drain. `progress` fires on
    /// every completed write (a @Sendable closure — the UI hops itself).
    public func enqueue(
        _ items: [(relPath: String, document: LightamerSidecar)],
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async {
        guard !items.isEmpty else { return }
        queue.append(contentsOf: items.map {
            QueuedWrite(relPath: $0.relPath, document: $0.document)
        })
        if !draining {
            await drain(progress: progress)
        }
    }

    /// The serial drain: FIFO, one atomic write + dirty=0 per item.
    private func drain(
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async {
        draining = true
        totalCount = queue.count
        completedCount = 0
        while !queue.isEmpty {
            let item = queue.removeFirst()
            do {
                try writeAtomic(item.document, relPath: item.relPath)
                try? await store.clearBatchDirty(relPath: item.relPath)
            } catch {
                // A failed write keeps the row dirty (the truth-claim
                // window stays open honestly) and logs — the heal leg
                // covers it on the next open; never a hard failure (SC#2).
                Self.logger.error(
                    "batch sidecar write failed (\(item.relPath, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                )
            }
            completedCount += 1
            progress?(completedCount, totalCount)
            if failAfterNext {
                // Crash injection: the CURRENT write completed (its row is
                // clean); everything pending stays queued exactly as a
                // process death would leave it. `draining` resets so a
                // re-enqueue can resume.
                failAfterNext = false
                draining = false
                return
            }
        }
        draining = false
    }

    // MARK: - Test seams (never called by app code)

    /// Arm the crash injection (the NEXT drain iteration stops).
    public func armCrashInjectionForTesting() {
        failAfterNext = true
    }

    /// The pending count (the crash-injection + teardown assertions).
    public var pendingCountForTesting: Int { queue.count }

    // MARK: - Teardown

    /// Drain the remainder NOW (session switch / termination seam).
    /// Bounded by the queue length itself; errors log per item (above).
    public func flushForTeardown() async {
        guard !queue.isEmpty else { return }
        await drain(progress: nil)
    }

    // MARK: - The atomic write (the SidecarStore.writeAtomic shape)

    /// Encode → same-directory tmp sibling → `replaceItemAt`/`moveItem`.
    /// The tmp is removed on the failure path (never leave debris).
    private func writeAtomic(_ document: LightamerSidecar, relPath: String) throws {
        let destination = LightamerSidecar.sidecarURL(for: root.appendingPathComponent(relPath))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw AppError.sidecarWriteFailed(destination.path)
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let tmp = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            // Plain write to the SAME-DIRECTORY tmp — the promotion below
            // is the atomic step (L009: never a cross-volume rename).
            try data.write(to: tmp)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp) // never leave debris
            throw AppError.sidecarWriteFailed(destination.path)
        }
        // Journal the promotion so the reconciler swallows the FSEvents
        // event it just caused (09-02 defense ②).
        journal.record(path: destination.path)
    }
}
