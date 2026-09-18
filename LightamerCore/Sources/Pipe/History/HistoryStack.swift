import Foundation

/// The non-destructive edit history (Plan 02-05-03; HIST-01/HIST-02) —
/// an ordered item list + a position pointer, Darktable `develop_t`'s
/// `history` list + `history_end` in value form:
///
/// - `position == -1` = PRISTINE (no effective entries — the default
///   chain renders untouched).
/// - `commit` = truncate everything after `position`, then append
///   (`position = count - 1`) — undo followed by an edit kills the redo
///   tail, exactly like every mainstream editor.
/// - `undo`/`redo`/`jump(to:)` move ONLY the pointer; items are never
///   rewritten, so jumping forward again restores the exact same states
///   (HIST-02's "jump to any point" — D-H3: named snapshots are Phase 6).
///
/// **D-H1 granularity (checkpoint lock #1):** one `commit` per drag-END.
/// The coordinator's `beginContinuousEdit → setLiveParams (preview only,
/// zero commits) → commitContinuousEdit` trio emits exactly one
/// `HistoryItem` per interaction; this stack never sees intermediates.
///
/// **Item shape (checkpoint lock #5):** `HistoryItem` inlines a FULL
/// `ModuleInstance` snapshot (not an id reference) so undo/jump restore
/// params AS THEY WERE and `effectiveInstances()` is a pure function of
/// `(items[...position])`. The `items[]` array maps 1:1 onto the sidecar
/// schema Plan 02-06 persists (D-H2: uncapped — items hold params bytes,
/// never textures, so memory stays negligible).
///
/// **Codable spelling (checkpoint lock #6 — FROZEN):** `{items,
/// position}` verbatim in the 02-06 sidecar.
///
/// Pure value semantics — no Metal, no actor, no I/O; the stack IS the
/// only mutation surface of the recorded history (HIST-01's "original
/// file untouched" is structural: nothing here touches a file).
public struct HistoryStack: Codable, Sendable, Equatable {

    /// Full edit log (D-H2: no cap). Entries at indices > `position` are
    /// the REDO tail (dropped by the next `commit`).
    public private(set) var items: [HistoryItem] = []

    /// Pointer into `items` (−1 = pristine; Darktable `history_end`
    /// semantics: entries ≤ position are the image's effective history).
    public private(set) var position: Int = -1

    /// Frozen CodingKeys — checkpoint 02-05-01 lock #6.
    private enum CodingKeys: String, CodingKey {
        case items, position
    }

    /// One committed edit step: the full instance snapshot + presentation
    /// metadata. `layerScope` is the Phase 6 forward-compatibility hook
    /// (D-H2 note: layer-scoped entries arrive with the adjustment-layer
    /// system; nil = image-global edit, the only kind Phase 2 produces).
    public struct HistoryItem: Codable, Sendable, Identifiable, Equatable {

        public let id: UUID

        /// The inline instance snapshot (checkpoint lock #5).
        public var snapshot: ModuleInstance

        /// UI-facing label ("Exposure", "testgain 2.0×", …).
        public var label: String

        public var timestamp: Date

        /// Phase 6 reservation: nil = image-global.
        public var layerScope: String?

        /// Frozen CodingKeys — checkpoint 02-05-01 lock #6.
        private enum CodingKeys: String, CodingKey {
            case id, snapshot, label, timestamp, layerScope
        }

        public init(
            id: UUID = UUID(),
            snapshot: ModuleInstance,
            label: String,
            timestamp: Date = Date(),
            layerScope: String? = nil
        ) {
            self.id = id
            self.snapshot = snapshot
            self.label = label
            self.timestamp = timestamp
            self.layerScope = layerScope
        }
    }

    public init() {}

    /// The persistence restore path (Plan 02-06 sidecar projections):
    /// reconstructs a stack with EXACT items + position — the runtime
    /// mutation surface (`commit/undo/redo/jump`) cannot re-create
    /// historical item ids/timestamps, and a reloaded sidecar must be
    /// byte-faithful. Internal by design: `items`/`position` stay
    /// write-protected for app code (the projections live in Core).
    /// `position` clamps into `-1 ... count-1` (same contract as `jump`).
    init(items: [HistoryItem], position: Int) {
        self.items = items
        self.position = min(max(position, -1), items.count - 1)
    }

    // MARK: - Mutation (the only writers of items/position)

    /// Commit one edit step (D-H1 drag-end lands here): truncate the redo
    /// tail after `position`, append, point at the new entry.
    public mutating func commit(
        _ snapshot: ModuleInstance,
        label: String,
        layerScope: String? = nil
    ) {
        if position + 1 < items.count {
            items.removeSubrange(items.index(items.startIndex, offsetBy: position + 1)...)
        }
        items.append(
            HistoryItem(
                snapshot: snapshot, label: label, layerScope: layerScope
            )
        )
        position = items.count - 1
    }

    /// Step back one entry. nil at `position == -1` (nothing to undo).
    @discardableResult
    public mutating func undo() -> HistoryItem? {
        guard position >= 0 else { return nil }
        let item = items[position]
        position -= 1
        return item
    }

    /// Step forward one entry (only legal into an UNTRUNCATED tail).
    @discardableResult
    public mutating func redo() -> HistoryItem? {
        guard position + 1 < items.count else { return nil }
        position += 1
        return items[position]
    }

    /// Jump to an arbitrary point (HIST-02/D-H3). Out-of-range indices
    /// CLAMP into `-1 ... count-1` (−1 = pristine).
    public mutating func jump(to index: Int) {
        position = min(max(index, -1), items.count - 1)
    }

    // MARK: - Projection

    /// The snapshot at `position` (nil = pristine) — the "what did the
    /// user last touch" convenience.
    public var currentValue: ModuleInstance? {
        position >= 0 ? items[position].snapshot : nil
    }

    /// History → pipe state: the effective instance set at `position` —
    /// the DIRECT translation of the Darktable hash query
    /// (`history.c:1600-1607`):
    ///
    /// ```sql
    /// SELECT …, MAX(num) FROM history WHERE num <= history_end
    /// GROUP BY operation, multi_priority ORDER BY num
    /// ```
    ///
    /// Walk `items[0...position]` NEWEST-first and keep the FIRST
    /// occurrence per `(opName, multiPriority)` — the latest edit of each
    /// instance wins; earlier steps of the same instance are dead state.
    /// Then sort ascending by `iopOrder` (stable tiebreak
    /// `multiPriority`, then `opName` — the 28.5 order-collision cluster
    /// stays deterministic).
    ///
    /// Disabled instances are INCLUDED here (enabled-ness lives on the
    /// instance and is respected downstream: `HistoryHash` skips them,
    /// the pipe walk skips them) — dropping them would lose the fact
    /// that an instance EXISTS with those params (Darktable keeps the
    /// row; only the hash skips non-enabled entries).
    public func effectiveInstances() -> [ModuleInstance] {
        guard position >= 0 else { return [] }
        var seen = Set<InstanceKey>()
        seen.reserveCapacity(position + 1)
        var kept: [ModuleInstance] = []
        kept.reserveCapacity(position + 1)
        for item in items[0...position].reversed() {
            if seen.insert(
                InstanceKey(
                    opName: item.snapshot.opName,
                    multiPriority: item.snapshot.multiPriority
                )
            ).inserted {
                kept.append(item.snapshot)
            }
        }
        return kept.sorted {
            ($0.iopOrder, $0.multiPriority, $0.opName)
                < ($1.iopOrder, $1.multiPriority, $1.opName)
        }
    }

    /// The dedup tuple (`GROUP BY operation, multi_priority`).
    private struct InstanceKey: Hashable {
        let opName: String
        let multiPriority: Int
    }
}
