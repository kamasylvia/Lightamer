import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// StackClustering (Plan M6-4-01 T3, KD-4) — the capture-time auto-stack
// clustering, a PURE function (zero IO, zero store knowledge) + the
// LibraryStore commit face.
//
// SEMANTICS = LightCraft `auto_stack_groups` (OQ-M6-4-2 = A, RESEARCH A1):
// capture-time ASCENDING walk (stable — ties break by id ASC, determinism
// self-held), ADJACENT gap ≤ `gap` joins one cluster, a cluster only lands
// when it holds ≥2 members, rows without a capture time never cluster.
// Bracket/burst have NO special detection — a pure time threshold, the
// Lightroom shape. No auto-provenance is stored anywhere (the only reverse
// move is a manual ungroup — the KD-3 no-undo posture).
//
// The threshold-semantics port is idea-level (RESEARCH A4 permission note);
// this file is an independent implementation with no LightCraft lineage.
// ─────────────────────────────────────────────────────────────────────────────

public enum StackClustering {

    /// The LightCraft UI default (seconds).
    public static let defaultGapSeconds: Double = 60

    /// Cluster the given rows by capture-time adjacency.
    ///
    /// - Parameters:
    ///   - items: the candidate pool as `(id, capture)` pairs; rows with a
    ///     nil capture are skipped (the caller MAY pre-filter — the function
    ///     defends anyway, KD-4's double defense).
    ///   - gap: the maximum adjacent capture delta (seconds, inclusive).
    /// - Returns: the clusters, each member list ascending by id; singleton
    ///     runs never cluster (runs ≥ 2).
    public static func clusters(
        _ items: [(id: Int64, capture: Double?)],
        gap: Double = defaultGapSeconds
    ) -> [[Int64]] {
        // The defensible ordering: capture ASC, ties by id ASC (stable,
        // deterministic — the auto-stack output never depends on input order).
        let dated = items.compactMap { item -> (id: Int64, capture: Double)? in
            guard let capture = item.capture else { return nil }
            return (item.id, capture)
        }
        let sorted = dated.sorted { lhs, rhs in
            lhs.capture == rhs.capture ? lhs.id < rhs.id : lhs.capture < rhs.capture
        }
        var clusters: [[Int64]] = []
        var current: [Int64] = []
        var previous: Double?
        for item in sorted {
            if let previous, item.capture - previous <= gap {
                current.append(item.id)
            } else {
                if current.count >= 2 { clusters.append(current) }
                current = [item.id]
            }
            previous = item.capture
        }
        if current.count >= 2 { clusters.append(current) }
        // The contract is clusters ASCENDING BY ID (KD-4) — the walk order
        // is capture-monotone, which does NOT imply id order (id 9 may be
        // captured before id 3); the explicit sort keeps the contract.
        return clusters.map { $0.sorted() }
    }
}
