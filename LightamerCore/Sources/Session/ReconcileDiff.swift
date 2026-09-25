import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ReconcileDiff (Plan 09-02 T1; SESS-05) — the PURE directory-diff planner.
//
// FSEvents is hint-only (L007): events never edit rows — the reconcile diff
// is the ONLY arbiter of what the index should contain. This file holds the
// whole decision surface as a PURE FUNCTION over two in-memory snapshots:
//
//   previous = the index rows (the cached view)
//   current  = a fresh scan snapshot (the disk truth, captured by the caller)
//
// …producing a `ReconcilePlan` value. NO filesystem access, NO FSEvents
// import, NO actor state — every branch is testable as a golden (Plan 09-02
// T1 evidence) and the same input always yields the same plan.
//
// The five buckets (09-RESEARCH §4.3):
//   added / removed / changed  — the three-set difference (changed = mtime
//                                or size drift, §2.4 semantics)
//   renamedSurvived            — a removed×added candidate pair whose
//                                stat fingerprint (mtime AND size) matches
//                                EXACTLY: FSEvents reports a rename as two
//                                independent events (the known split), the
//                                stat ruling re-pairs them so the ROW
//                                SURVIVES a path update instead of being
//                                deleted + re-added (loss of backfilled
//                                columns). The unpaired remainder lands in
//                                added/removed as usual.
//   orphanSidecars             — `.lra` files whose original is gone
//                                (classification only — NEVER a hard
//                                failure, ROADMAP SC#2; the remove/ignore
//                                ACTIONS arrive via the store API)
//   externalEdits              — the `changed` subset whose SIDECAR mtime
//                                did NOT move: the original drifted under
//                                an untouched sidecar (edited/replaced
//                                outside the app) → decode-cache
//                                invalidation + thumb stale semantics for
//                                9-3/9-4 to consume.
//
// `subtreeFilter` (execution decision, 09-02-DECISIONS): an optional set of
// affected RELATIVE directories that restricts the REPORTED buckets to that
// subtree (the debounced event-batch leg). nil = full-tree plan — the mode
// every 9-2 caller uses (the apply leg is an idempotent full sync; the
// filter exists as the optimization seam, measured later in 9-3/9-4).
// ─────────────────────────────────────────────────────────────────────────────

/// The scan-side snapshot input (captured by the App layer; the pure
/// function never touches the filesystem itself).
public struct ReconcileScanSnapshot: Sendable, Equatable {
    /// Originals currently on disk (the scanner's stat triples).
    public var entries: [SessionScanEntry]
    /// relPath → sidecar mtime, where the co-located `.lra` exists.
    public var sidecarMtimes: [String: Double]
    /// `.lra` relPaths whose original is gone (the scanner's orphan lane).
    public var orphanSidecars: [String]

    public init(
        entries: [SessionScanEntry] = [],
        sidecarMtimes: [String: Double] = [:],
        orphanSidecars: [String] = []
    ) {
        self.entries = entries
        self.sidecarMtimes = sidecarMtimes
        self.orphanSidecars = orphanSidecars
    }
}

/// One rename-survival ruling: the row moves `fromPath` → `toPath` and
/// KEEPS its backfilled columns (path-update, not delete+insert).
public struct SessionReconcileRename: Sendable, Equatable {
    public var fromPath: String
    public var toPath: String

    public init(fromPath: String, toPath: String) {
        self.fromPath = fromPath
        self.toPath = toPath
    }
}

/// The pure diff output — a value the App layer logs, reports, and hands to
/// the store's single-transaction apply leg.
public struct ReconcilePlan: Sendable, Equatable {
    public var added: [String] = []
    public var removed: [String] = []
    public var changed: [String] = []
    public var renamedSurvived: [SessionReconcileRename] = []
    public var orphanSidecars: [String] = []
    public var externalEdits: [String] = []

    public init() {}

    /// True when the plan would change nothing (the reconciler uses this to
    /// skip empty applies — the anti-vacuous guard).
    public var isTrivial: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty
            && renamedSurvived.isEmpty && orphanSidecars.isEmpty
    }
}

public enum ReconcileDiff {

    /// The exact-match fingerprint for the rename-survival ruling
    /// (mtime AND size must both be equal — APFS renames preserve both).
    private struct StatFingerprint: Hashable, Sendable {
        var mtime: Double
        var size: Int64
    }

    /// Compute the reconcile plan. Deterministic: bucket members are sorted
    /// lexicographically and rename pairing iterates in sorted order, so the
    /// same input snapshots ALWAYS yield an equal plan (purity assertion).
    ///
    /// - Parameters:
    ///   - previousRows: the current index rows (orphan classification rows
    ///     — `orphan_sidecar == 1` — are excluded from the file math; the
    ///     orphan legs own them).
    ///   - current: the fresh scan snapshot.
    ///   - subtreeFilter: optional affected-directory restriction (see the
    ///     file header); nil = full-tree plan.
    public static func diff(
        previousRows: [SessionIndexRow],
        current: ReconcileScanSnapshot,
        subtreeFilter: Set<String>? = nil
    ) -> ReconcilePlan {
        var plan = ReconcilePlan()

        // ── Index side (previous): path → (mtime, size), non-orphan rows only.
        var previous: [String: (mtime: Double, size: Int64, sidecarMtime: Double?)] = [:]
        for row in previousRows where row.orphanSidecar != 1 {
            previous[row.path] = (
                row.fileMtime ?? 0, row.fileSize ?? 0, row.sidecarMtime
            )
        }

        // ── Disk side (current): relPath → stat triple.
        var currentEntries: [String: (mtime: Double, size: Int64)] = [:]
        for entry in current.entries {
            currentEntries[entry.relPath] = (entry.mtime, entry.size)
        }

        // ── Raw candidate sets (sorted for determinism).
        let rawAdded = currentEntries.keys.filter { previous[$0] == nil }.sorted()
        let rawRemoved = previous.keys.filter { currentEntries[$0] == nil }.sorted()
        let common = currentEntries.keys.filter { previous[$0] != nil }.sorted()

        // ── Rename-survival pairing (the FSEvents-split remedy): a removed
        // candidate and an added candidate whose stat fingerprints match
        // EXACTLY are the two halves of one rename. Pool the added
        // candidates by fingerprint; each removed candidate consumes the
        // lexicographically-first unconsumed match (deterministic).
        var addedPool: [StatFingerprint: [String]] = [:]
        for rel in rawAdded {
            let stat = currentEntries[rel]!
            addedPool[StatFingerprint(mtime: stat.mtime, size: stat.size), default: []]
                .append(rel)
        }
        var pairedDestinations = Set<String>()
        for removedRel in rawRemoved {
            let stat = previous[removedRel]!
            let key = StatFingerprint(mtime: stat.mtime, size: stat.size)
            guard var candidates = addedPool[key], !candidates.isEmpty else { continue }
            let destination = candidates.removeFirst()
            addedPool[key] = candidates.isEmpty ? nil : candidates
            plan.renamedSurvived.append(
                SessionReconcileRename(fromPath: removedRel, toPath: destination)
            )
            pairedDestinations.insert(destination)
        }

        // ── Final added/removed (the unpaired remainder).
        plan.added = rawAdded.filter { !pairedDestinations.contains($0) }
        plan.removed = rawRemoved.filter { removedRel in
            !plan.renamedSurvived.contains { $0.fromPath == removedRel }
        }

        // ── changed (mtime/size drift) + externalEdits (sidecar untouched).
        for rel in common {
            let before = previous[rel]!
            let after = currentEntries[rel]!
            guard before.mtime != after.mtime || before.size != after.size else {
                continue
            }
            plan.changed.append(rel)
            // External edit semantics: the ORIGINAL moved while the
            // sidecar's mtime did not — the outside world edited the image,
            // the sidecar knowledge is stale.
            if let previousSidecarMtime = before.sidecarMtime,
               current.sidecarMtimes[rel] == previousSidecarMtime {
                plan.externalEdits.append(rel)
            }
        }

        // ── Orphans: the scan lane, verbatim (all current orphans — the
        // ignore-set filtering is an apply/UI concern, not a diff concern).
        plan.orphanSidecars = current.orphanSidecars.sorted()

        // ── Subtree restriction (reporting only — the apply leg stays an
        // idempotent full sync; see the file header).
        if let subtreeFilter {
            func belongs(_ rel: String) -> Bool {
                let directory = (rel as NSString).deletingLastPathComponent
                return subtreeFilter.contains(directory)
            }
            plan.added = plan.added.filter(belongs)
            plan.removed = plan.removed.filter(belongs)
            plan.changed = plan.changed.filter(belongs)
            plan.externalEdits = plan.externalEdits.filter(belongs)
            plan.orphanSidecars = plan.orphanSidecars.filter(belongs)
            plan.renamedSurvived = plan.renamedSurvived.filter { belongs($0.toPath) }
        }

        return plan
    }
}
