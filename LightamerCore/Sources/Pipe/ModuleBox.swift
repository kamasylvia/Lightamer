import Foundation
import Metal

/// The type-erased pipe citizen (02-02 checkpoint lock #6). `IOPModule` has
/// `associatedtype Params`, so `any IOPModule` cannot be formed (Phase 1
/// gotcha) — the pixelpipe therefore drives modules through THIS erased
/// surface. It is also the object the history layer materializes:
/// `ModuleRegistry` (02-04) manufactures boxes from registered metatypes
/// and `effectiveInstances()` (02-05) mirrors its identity fields.
public protocol ModuleBoxing: AnyObject, Sendable {

    /// Instance-stable identity (NDE-1: masks/history reference instances
    /// by UUID, never by ordinal).
    var instanceID: UUID { get }

    /// Darktable-style op string (`IOPModule.opName` of the wrapped module).
    var opName: String { get }

    /// Same-op multi-instance ordinal (Darktable `multi_instance`).
    var multiPriority: Int { get }

    /// User-visible instance name.
    var multiName: String { get }

    /// The instance's v50 position (`IOPModule.iopOrder`; per-instance
    /// override arrives with custom ordering, Phase 6+).
    var iopOrder: Float { get }

    /// Disabled pieces are skipped by the pipe walk — no cache-key step, no
    /// `process` call (Darktable `_skip_piece_on_tags`, `pixelpipe_hb.c:1875-1881`).
    var enabled: Bool { get }

    /// The committed params' JSON encoding (the authoritative payload the
    /// sidecar round-trips; 02-05 mirrors it into `ModuleInstance`).
    var paramsData: Data { get }

    /// `StableHash.hash(paramsData)` — the D-H4 atom shared by the pipe
    /// cache chain and the history identity. `StableHash` is the only legal
    /// generator.
    var paramsHash: UInt64 { get }

    /// A fresh per-run `IOPiece` seeded from the committed state (uniforms
    /// buffer + paramsHash shared in; per-run geometry is stamped by the
    /// pipe). One per (module instance × pipe run) — `dt_iop_piece_t`.
    func makeRunPiece() -> IOPiece

    /// Re-materialize the box's committed state from an instance record
    /// (Plan 02-05; the history → pipe seam). The caller guarantees
    /// `record.id == instanceID` (identity is NEVER touched — records and
    /// boxes are two views of the same instance). Syncs `enabled`/
    /// `multiName`, then decodes `record.paramsData` against the wrapped
    /// module's Params type and re-commits (uniforms + hash). Fast path:
    /// byte-identical params leave the committed piece untouched
    /// (uniforms survive; the cache chain sees the same hashes).
    /// Decode failure throws typed `AppError` — the 02-06 degrade policy
    /// is the caller's business, not the box's.
    func apply(_ record: ModuleInstance) async throws

    /// Dispatch the wrapped module's `process` (texture in/out, 02-02 lock
    /// #1). The pipe calls this from the cache miss closure.
    func processErased(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws
}

/// The generic box: wraps one concrete `IOPModule` instance + its committed
/// piece state.
///
/// `@unchecked Sendable` carries the OWNERSHIP contract (not free sharing):
/// a box belongs to the single task that materialized it (pipe run or the
/// 02-05 coordinator); `enabled`/`multiName`/params mutate only through that
/// owner. Identity fields are immutable after init.
public final class ModuleBox<M: IOPModule>: ModuleBoxing, @unchecked Sendable {

    /// Instance-stable identity (NDE-1: masks/history reference instances
    /// by UUID, never by ordinal). Minted fresh by the convenience init;
    /// injected (persisted sidecar UUID) by the identity-restoring init.
    public let instanceID: UUID

    /// Darktable-style op string — forwarded from the wrapped module's
    /// static (`M.opName`).
    public var opName: String { M.opName }

    /// The instance's v50 position — forwarded from `M.iopOrder` (per-
    /// instance override arrives with custom ordering, Phase 6+).
    public var iopOrder: Float { M.iopOrder }

    /// The wrapped module instance (owned by this box's isolation domain).
    public let module: M

    public let multiPriority: Int

    public var multiName: String

    public var enabled: Bool

    public private(set) var paramsData: Data = Data()

    public private(set) var paramsHash: UInt64 = 0

    /// The committed piece — `setParams` runs `module.commitParams` into
    /// this (uniforms buffer + paramsHash). `makeRunPiece()` hands copies to
    /// pipe runs.
    private var committedPiece = IOPiece()

    public convenience init(
        module: M,
        multiPriority: Int = 0,
        multiName: String = "",
        enabled: Bool = true
    ) {
        self.init(
            module: module, instanceID: UUID(),
            multiPriority: multiPriority, multiName: multiName, enabled: enabled
        )
    }

    /// The identity-restoring initializer: `ModuleRegistry.makeBox` (02-04)
    /// and the 02-05 sidecar loader inject the PERSISTED instance UUID —
    /// masks/history reference instances by UUID, so a reloaded sidecar
    /// must resurrect the SAME identity, not mint a fresh one.
    public init(
        module: M,
        instanceID: UUID,
        multiPriority: Int = 0,
        multiName: String = "",
        enabled: Bool = true
    ) {
        self.instanceID = instanceID
        self.module = module
        self.multiPriority = multiPriority
        self.multiName = multiName
        self.enabled = enabled
    }

    /// Re-parameterize the instance: re-encode, re-hash (the D-H4 atom),
    /// and re-commit the piece (uniforms). This is the pipe-facing mutation
    /// behind a slider drag — the cache chain does the rest (SC#2: every
    /// key at or below this module flips, everything upstream survives).
    ///
    /// Hash authority (02-04 fix): the box ADOPTS the module-committed
    /// piece hash after `commitParams`. For every standard module the
    /// piece hash IS `StableHash.hash(paramsData)` (the D-H4 reference
    /// shape), so adoption is a no-op — but terminal modules may fold
    /// extra identity into the committed hash (colorout folds the resolved
    /// `DisplayProfile.stableID`, the terminal-segment invalidation atom),
    /// and the CACHE chain reads the BOX hash. Without adoption that fold
    /// would be invisible to the cache.
    public func setParams(_ params: M.Params) async {
        let encoded = ParamsCoding.encode(params)
        paramsData = encoded
        paramsHash = StableHash.hash(encoded)
        await module.commitParams(params, into: &committedPiece)
        paramsHash = committedPiece.paramsHash
    }

    public func makeRunPiece() -> IOPiece {
        committedPiece
    }

    public func apply(_ record: ModuleInstance) async throws {
        precondition(
            record.id == instanceID,
            "ModuleBox.apply: record identity mismatch (\(record.id) ≠ \(instanceID))"
        )
        enabled = record.enabled
        multiName = record.multiName
        // Byte-identical params: keep the committed piece exactly as-is
        // (uniforms survive; hashes unchanged → cache chain unaffected).
        guard record.paramsData != paramsData else { return }
        let params: M.Params
        do {
            params = try JSONDecoder().decode(M.Params.self, from: record.paramsData)
        } catch {
            throw AppError(error)
        }
        await setParams(params)
    }

    public func processErased(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        try await module.process(
            input: input,
            output: output,
            roiIn: roiIn,
            roiOut: roiOut,
            piece: &piece,
            metal: metal
        )
    }
}
