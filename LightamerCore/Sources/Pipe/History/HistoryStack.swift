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
    /// system; nil = image-global edit).
    ///
    /// Codable spelling (checkpoint 02-05-01 lock #6 — FROZEN PREFIX):
    /// `{id, snapshot, label, timestamp, layerScope}`; Plan 06-01 T6 adds
    /// `stackSnapshot` as an OPTIONAL decodeIfPresent field — v1 documents
    /// decode unchanged, v2 writers omit it when nil. NOTE: this runtime
    /// Codable path is the IN-MEMORY shape (paramsHash as a JSON number);
    /// the sidecar projects through `SidecarHistoryItemRecord` (decimal
    /// String hashes), so precision never crosses a process boundary.
    public struct HistoryItem: Codable, Sendable, Identifiable, Equatable {

        public let id: UUID

        /// The inline instance snapshot (checkpoint lock #5).
        public var snapshot: ModuleInstance

        /// UI-facing label ("Exposure", "testgain 2.0×", …).
        public var label: String

        public var timestamp: Date

        /// Phase 6 reservation: nil = image-global.
        public var layerScope: String?

        /// Plan 06-01 T6: the full layer-stack snapshot for STRUCTURE edits
        /// (add/remove/reorder/duplicate/mergeDown/property changes) — a
        /// lightweight value copy (chain = param bytes, mask = the record
        /// shell; no textures), restorable wholesale. nil for param-scope
        /// items.
        public var stackSnapshot: LayerStackSnapshot?

        /// Frozen CodingKeys — checkpoint 02-05-01 lock #6 (+ the 06-01
        /// additive stackSnapshot field).
        private enum CodingKeys: String, CodingKey {
            case id, snapshot, label, timestamp, layerScope, stackSnapshot
        }

        public init(
            id: UUID = UUID(),
            snapshot: ModuleInstance,
            label: String,
            timestamp: Date = Date(),
            layerScope: String? = nil,
            stackSnapshot: LayerStackSnapshot? = nil
        ) {
            self.id = id
            self.snapshot = snapshot
            self.label = label
            self.timestamp = timestamp
            self.layerScope = layerScope
            self.stackSnapshot = stackSnapshot
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            snapshot = try container.decode(ModuleInstance.self, forKey: .snapshot)
            label = try container.decode(String.self, forKey: .label)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            layerScope = try container.decodeIfPresent(String.self, forKey: .layerScope)
            stackSnapshot = try container.decodeIfPresent(
                LayerStackSnapshot.self, forKey: .stackSnapshot)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(snapshot, forKey: .snapshot)
            try container.encode(label, forKey: .label)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encodeIfPresent(layerScope, forKey: .layerScope)
            try container.encodeIfPresent(stackSnapshot, forKey: .stackSnapshot)
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
    /// tail after `position`, append, point at the new entry. Structure
    /// edits (6-5 wiring) additionally pass `stackSnapshot` (Plan 06-01 T6).
    public mutating func commit(
        _ snapshot: ModuleInstance,
        label: String,
        layerScope: String? = nil,
        stackSnapshot: LayerStackSnapshot? = nil
    ) {
        if position + 1 < items.count {
            items.removeSubrange(items.index(items.startIndex, offsetBy: position + 1)...)
        }
        items.append(
            HistoryItem(
                snapshot: snapshot, label: label, layerScope: layerScope,
                stackSnapshot: stackSnapshot
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

    /// History → pipe state: the effective GLOBAL instance set at
    /// `position` — the DIRECT translation of the Darktable hash query
    /// (`history.c:1600-1607`):
    ///
    /// ```sql
    /// SELECT …, MAX(num) FROM history WHERE num <= history_end
    /// GROUP BY operation, multi_priority ORDER BY num
    /// ```
    ///
    /// **Scope (Plan 06-01 T2 — `layerScope` enabled):** only IMAGE-GLOBAL
    /// entries (`layerScope == nil`) project here. Layer-scoped entries
    /// (adjustment-layer edits) belong to their layer's chain, not the
    /// global pipe — mixing them in would leak layer instances into the
    /// base run. Use `effectiveInstances(layerScope:)` for a layer's set.
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
        effectiveInstances(layerScope: nil)
    }

    /// The effective instance set for ONE scope: `nil` = image-global (the
    /// `effectiveInstances()` default), a layer UUID string = that layer's
    /// chain. Same dedup tuple / newest-wins / v50-sort rule for both.
    public func effectiveInstances(layerScope scope: String?) -> [ModuleInstance] {
        guard position >= 0 else { return [] }
        return Self.effectiveChain(
            items[0...position].filter { $0.layerScope == scope }.map(\.snapshot)
        )
    }

    /// The shared dedup + sort rule (`GROUP BY (opName, multi_priority)`
    /// latest-wins, v50 ascending with the opName tiebreak) applied to an
    /// arbitrary record chain — `ModuleRegistry.effectiveInstances(layer:)`
    /// consumes this for adjustment-layer chains (Plan 06-01 T2).
    ///
    /// Array order is chronological: the LAST occurrence of a tuple wins
    /// (for history items that is the newest edit; for a layer chain the
    /// most recently appended record).
    public static func effectiveChain(_ records: [ModuleInstance]) -> [ModuleInstance] {
        var seen = Set<InstanceKey>()
        seen.reserveCapacity(records.count)
        var kept: [ModuleInstance] = []
        kept.reserveCapacity(records.count)
        for snapshot in records.reversed() {
            if seen.insert(
                InstanceKey(
                    opName: snapshot.opName,
                    multiPriority: snapshot.multiPriority
                )
            ).inserted {
                kept.append(snapshot)
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
