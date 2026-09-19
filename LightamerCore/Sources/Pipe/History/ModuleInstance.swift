import Foundation

/// One persisted module instance — the identity + params RECORD (Plan
/// 02-05-02; HIST-01). The Swift composite of Darktable's runtime module
/// instance and `dt_dev_history_item_t` (`develop.h:34-49`:
/// `op_name` / `iop_order` / `multi_priority` / `multi_name` / `params` /
/// `blend_params`).
///
/// **Identity semantics (NDE-1 — load-bearing, Phase 6 masks depend on
/// it):**
/// - The DEDUP tuple is `(opName, multiPriority)` — `effectiveInstances()`
///   groups by it (`history.c:1600-1607`'s `GROUP BY operation,
///   multi_priority` translation); the latest entry at-or-before
///   `position` wins.
/// - REFERENCES go through `id` (UUID), never an ordinal — a reloaded
///   sidecar resurrects the SAME UUID (`ModuleBox`'s identity-restoring
///   init consumes it), so masks/history anchored to an instance survive
///   reloads and reorders.
/// - ORDER is `iopOrder` (the instance's v50 position; user reordering is
///   Phase 6+ and would mutate this per instance, Darktable custom-order
///   style).
///
/// This is deliberately a plain VALUE record, NOT a module — the runtime
/// `ModuleBox` (02-02) is manufactured from it via `ModuleRegistry`
/// (02-04). `any IOPModule` cannot be formed (`associatedtype Params`),
/// so the history layer speaks in these records and materializes boxes
/// on demand.
///
/// **Params payload:** `paramsData` is the AUTHORITATIVE params encoding
/// — canonical JSON via `ParamsCoding.encode` (`.sortedKeys`; LESSONS
/// L013: unsorted keyed emission order is not stable even within one
/// process, which would split cache keys and false-positive drift
/// checks). `paramsHash = StableHash.hash(paramsData)` is the D-H4 atom
/// shared by the pipe-cache chain and `HistoryHash`.
///
/// **Codable spelling (checkpoint 02-05-01 lock #6 — FROZEN):** Plan
/// 02-06 persists these keys verbatim as the sidecar's `instances[]`
/// schema; renames after 02-06 ships are migrations.
///
/// Concurrency: a value record — trivially `Sendable`. `Hashable` is
/// synthesized (Swift `Hasher`) and legal because it is IN-MEMORY ONLY
/// (process-local sets/dictionaries); nothing here ever crosses a
/// persistence boundary — those bytes are `StableHash` territory.
public struct ModuleInstance: Codable, Sendable, Equatable, Hashable {

    /// Instance-stable identity — the reference anchor (NDE-1).
    public var id: UUID

    /// Darktable-style op string (`IOPModule.opName`); the v50 table key
    /// and the `ModuleRegistry` lookup key.
    public var opName: String

    /// Same-op multi-instance ordinal (Darktable `multi_instance`); half
    /// of the dedup tuple.
    public var multiPriority: Int

    /// User-visible instance name (Darktable `multi_name`).
    public var multiName: String

    /// The instance's v50 position (per-instance; custom ordering rewrites
    /// this, Phase 6+).
    public var iopOrder: Float

    /// Module params schema version (Darktable `modversion` analog; 1
    /// until a module migrates its Params shape).
    public var version: Int

    /// Disabled instances stay in history/effective sets but contribute
    /// NOTHING to `HistoryHash` and are SKIPPED by the pipe walk.
    public var enabled: Bool

    /// The canonical params encoding (`ParamsCoding.encode`) — the
    /// authoritative payload the sidecar round-trips and the hash digests.
    public var paramsData: Data

    /// `StableHash.hash(paramsData)` — derived, stored for cheap
    /// comparison and sidecar readability (02-06).
    public var paramsHash: UInt64

    /// Frozen CodingKeys — checkpoint 02-05-01 lock #6 (the 02-06 sidecar
    /// `instances[]` schema).
    public enum CodingKeys: String, CodingKey {
        case id, opName, multiPriority, multiName, iopOrder
        case version, enabled, paramsData, paramsHash
    }

    /// The typed constructor — history/app code mints records from a
    /// module METATYPE + params; params are canonically encoded and hashed
    /// here (the only two places `paramsData`/`paramsHash` are derived
    /// from live params; `setParams` is the mutation path).
    public init<M: IOPModule>(
        id: UUID = UUID(),
        module: M.Type,
        multiPriority: Int = 0,
        multiName: String = "",
        params: M.Params,
        version: Int = 1,
        enabled: Bool = true
    ) {
        self.id = id
        self.opName = M.opName
        self.multiPriority = multiPriority
        self.multiName = multiName
        self.iopOrder = M.iopOrder
        self.version = version
        self.enabled = enabled
        let encoded = ParamsCoding.encode(params)
        self.paramsData = encoded
        self.paramsHash = StableHash.hash(encoded)
    }

    /// The persistence restore initializer (Plan 02-06 sidecar decode):
    /// constructs a record from RAW persisted fields — `paramsData` and
    /// `paramsHash` are adopted VERBATIM (no re-encode, no re-hash). This
    /// bypasses the derived-from-params invariant deliberately: unknown-op
    /// preservation (checkpoint 02-06-01 lock #4) must round-trip bytes
    /// the current binary cannot even decode. Internal: app code reaches
    /// records through `LightamerSidecar`'s projections, never through
    /// this constructor.
    init(
        id: UUID,
        opName: String,
        multiPriority: Int,
        multiName: String,
        iopOrder: Float,
        version: Int,
        enabled: Bool,
        paramsData: Data,
        paramsHash: UInt64
    ) {
        self.id = id
        self.opName = opName
        self.multiPriority = multiPriority
        self.multiName = multiName
        self.iopOrder = iopOrder
        self.version = version
        self.enabled = enabled
        self.paramsData = paramsData
        self.paramsHash = paramsHash
    }

    /// Decode the params payload against a concrete module's Params type.
    /// A mismatched type (or corrupt bytes) surfaces as a typed
    /// `AppError` (D-25) — never a crash; the 02-06 unknown-op degrade
    /// path consumes decode failures.
    public func params<M: IOPModule>(of type: M.Type) throws -> M.Params {
        do {
            return try JSONDecoder().decode(M.Params.self, from: paramsData)
        } catch {
            throw AppError(error)
        }
    }

    /// Re-parameterize the record: re-encode canonically + re-hash (the
    /// D-H4 atom flips, which is what invalidates the pipe-cache chain
    /// and the history hash).
    public mutating func setParams<M: IOPModule>(
        _ params: M.Params,
        as type: M.Type
    ) throws {
        let encoded = ParamsCoding.encode(params)
        paramsData = encoded
        paramsHash = StableHash.hash(encoded)
    }
}
