import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PastePayload (Plan 09-04 T1; HIST-05 copy side).
//
// The copy = a FROZEN "effective instance set + layer-stack snapshot +
// skip-set record" carrier (09-RESEARCH §6.1, dt `dt_history_copy`
// proxy-role twin). The clipboard is PROCESS-INTERNAL memory + Codable —
// cross-session paste works within one process; a cross-process pasteboard
// is explicitly NOT v1 (09-CONTEXT deferred).
//
// **Skip set (D-09-CONTEXT-5, aligned with dt history.c:695-705):**
//   ① decode domain — instances in the RAW/sensor technical segment are
//     excluded: another camera's decode-side params (rawprepare/
//     temperature/demosaic/lens/…) must not transplant (废片 risk).
//     BOUNDARY NOTE (execution decision, 09-04-DECISIONS): the plan's
//     formula "V50Order < colorin 28.0" is UNUSABLE verbatim against the
//     verbatim v50 table — exposure (21.0), toneequal (24.0), crop (24.5)
//     sit below colorin by dt's own scene-referred design, and the same
//     plan's acceptance line says 创意域保留. dt's actual rule is
//     FLAG-based (`dt_history_module_skip_copy`, history.h:107-110 =
//     DEPRECATED|UNSAFE_COPY|HIDDEN) and copies exposure. We have no such
//     flags yet, so the decode domain is the ordered segment strictly
//     below `ashift` (15.0): rawprepare..hazeremoval (rawprep/WB/highlights/
//     demosaic/denoise/lens/CA — sensor- and lens-anchored values that
//     never cross images). ashift (15.0) and everything after copies.
//   ② unmodified identity-default instances are excluded (payload bloat):
//     an instance is "identity" when a `editingDefaultInstances` seed record
//     exists with the same (opName, multiPriority) AND identical paramsData
//     AND identical enabled-ness. multiName is deliberately NOT compared
//     (dt compares params, not names; a rename alone is not a modification).
//   ③ auto-detected geometry params copy VERBATIM (the detection result is
//     pinned in the instance's paramsData; paste never re-runs detection).
//   ④ borders/watermark (terminal tail ≥ 70.0) are CREATIVE modules —
//     copyable.
//
// **Multi-instance identity:** the semantic identity is the
// (opName, multiPriority, multiName) tuple (Phase 2 frozen identity);
// instance UUIDs are RECAST at paste time (cross-image UUID namespaces
// stay separate — `PasteSemantics` owns the recast).
//
// **Codable shape:** the runtime `ModuleInstance` spelling (paramsHash as
// a JSON number) is FINE here — the payload never crosses a process
// boundary, so the L013 decimal-String rule does not apply (that lock
// governs PERSISTED bytes; the sidecar keeps its own projections).
// `.sortedKeys` round-trips byte-deterministically (the test pins
// encode→decode→encode byte identity).
// ─────────────────────────────────────────────────────────────────────────────

/// One paste-clipboard entry (Plan 09-04 T1). `PasteSemantics` consumes it
/// against a target history; the partial-copy dialog consumes `InstanceKey`s.
public struct PastePayload: Codable, Sendable, Equatable {

    /// The paste-semantic identity of one payload instance — the Phase 2
    /// frozen tuple PLUS the user-visible name. Hashable/Codable so the
    /// partial-selection dialog can persist a checked subset in-process.
    public struct InstanceKey: Hashable, Codable, Sendable, Equatable {
        public var opName: String
        public var multiPriority: Int
        public var multiName: String

        public init(opName: String, multiPriority: Int, multiName: String) {
            self.opName = opName
            self.multiPriority = multiPriority
            self.multiName = multiName
        }

        public init(_ instance: ModuleInstance) {
            self.init(
                opName: instance.opName,
                multiPriority: instance.multiPriority,
                multiName: instance.multiName)
        }
    }

    /// The SOURCE image's cross-session identity (diagnostics + the
    /// "same image paste" fast path; never a cache key).
    public var sourceImageID: UUID

    /// The source image URL (diagnostics only — the payload survives the
    /// source file moving away).
    public var sourceURL: URL?

    /// The frozen EFFECTIVE instance set (skip set already applied, v50
    /// sorted). One entry per (opName, multiPriority) — the copy projects
    /// through the effective chain, never the raw history log (dt copies
    /// the history rows; our HistoryStack dedups identically at paste).
    public var instances: [ModuleInstance]

    /// The frozen layer-stack snapshot (nil = the source had no adjustment
    /// layers). Overwrite installs it wholesale; merge v1 does NOT merge
    /// layer STRUCTURE (execution decision — global instances only).
    public var layerStack: SidecarLayerStackRecord?

    /// When the copy was taken (diagnostics/UI freshness hint).
    public var copiedAt: Date

    /// Producing app version (parity with the sidecar's diagnostics stamp).
    public var appVersion: String

    public init(
        sourceImageID: UUID,
        sourceURL: URL?,
        instances: [ModuleInstance],
        layerStack: SidecarLayerStackRecord?,
        copiedAt: Date = Date(),
        appVersion: String = LightamerSidecar.currentAppVersion
    ) {
        self.sourceImageID = sourceImageID
        self.sourceURL = sourceURL
        self.instances = instances
        self.layerStack = layerStack
        self.copiedAt = copiedAt
        self.appVersion = appVersion
    }

    // MARK: - Partial-selection face

    /// The distinct module keys in payload order (the dialog's tree rows —
    /// one row per (opName, multiPriority, multiName) instance).
    public var instanceKeys: [InstanceKey] {
        instances.map(InstanceKey.init)
    }

    /// Filter the payload down to a checked subset (partial copy / paste).
    /// Order and records are preserved; an empty selection yields an empty
    /// payload (the paste then commits nothing — the caller no-ops).
    public func filtered(by selection: Set<InstanceKey>) -> PastePayload {
        var payload = self
        payload.instances = instances.filter { selection.contains(InstanceKey($0)) }
        return payload
    }
}

// MARK: - Copy composition (the skip set lives here — D-09-CONTEXT-5)

public extension PastePayload {

    /// The decode-domain boundary: the v50 position of `ashift`. Everything
    /// STRICTLY BELOW is the raw/sensor technical segment (rawprepare,
    /// temperature, highlights, demosaic, denoiseprofile, lens, …) and
    /// never copies. `ashift` itself and every later module (exposure,
    /// toneequal, crop, …, the terminal tail) are copyable — see the
    /// header's boundary note.
    public static let decodeDomainBoundary: Float = 15.0

    /// Compose a payload from a source image's live state (the ⌘C leg).
    ///
    /// - Parameters:
    ///   - sourceInstances: the source's FULL live instance set (base ∪
    ///     effective — exactly `EditorState.instances` / a sidecar doc's
    ///     `instances`).
    ///   - sourceEffective: the source history's effective chain at the
    ///     current position (`HistoryStack.effectiveInstances()`). Only
    ///     instances the HISTORY owns are copy candidates (base records
    ///     are pristine seeds by construction).
    ///   - seed: the identity-default seed (`ModuleRegistry
    ///     .makeDefaultInstances() + LightamerIOPRegistry
    ///     .editingDefaultInstances()` sorted) — the identity comparison
    ///     table for skip rule ②.
    static func compose(
        sourceImageID: UUID,
        sourceURL: URL?,
        sourceInstances: [ModuleInstance],
        sourceEffective: [ModuleInstance],
        seed: [ModuleInstance],
        layerStack: SidecarLayerStackRecord?,
        copiedAt: Date = Date()
    ) -> PastePayload {
        // The copy candidates = the effective chain (history-owned, deduped,
        // v50-sorted). A base record that the history shadows is fully
        // represented by its history twin.
        let candidates = sourceEffective
        // Skip ② table: seed records by (opName, multiPriority).
        var seedByTuple: [String: [Int: ModuleInstance]] = [:]
        seedByTuple.reserveCapacity(seed.count)
        for record in seed {
            seedByTuple[record.opName, default: [:]][record.multiPriority] = record
        }
        let copied = candidates.filter { instance in
            // Skip ① decode domain.
            guard instance.iopOrder >= Self.decodeDomainBoundary else { return false }
            // Skip ② identity default (params + enabled identical to the
            // seed record; name NOT compared — dt compares params only).
            if let seedRecord = seedByTuple[instance.opName]?[instance.multiPriority],
               seedRecord.paramsData == instance.paramsData,
               seedRecord.enabled == instance.enabled {
                return false
            }
            return true
        }
        return PastePayload(
            sourceImageID: sourceImageID,
            sourceURL: sourceURL,
            instances: copied,
            layerStack: layerStack,
            copiedAt: copiedAt)
    }
}
