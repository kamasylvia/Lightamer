import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Lightamer sidecar (`.lra`) — Plan 02-06-02; HIST-03; D-S1/D-S2.
//
// FORMAT LOCK (checkpoint 02-06-01, ONE-WAY): JSON, pretty-printed with
// `.sortedKeys` (git-diff-stable), `schemaVersion: 1` from day one (D-S1's
// migration escape hatch). LESSONS L003: this is Lightamer's OWN format —
// no Darktable XMP interop, now or ever (Phase 9 revisits .xmp COEXISTENCE
// only; we never read/write/delete a `.xmp`).
//
// UInt64-as-String rule (checkpoint lock #2, ONE-WAY): FNV-1a 64 hash
// values exceed 2^53, and JSON numbers round-tripped through non-Swift
// tools (JS `Number`, python `float`) lose precision — so
// `decodeParamsHash` / `historyHash` / every `paramsHash` serialize as
// decimal STRINGS via the public `UInt64String` property wrapper. Decoders
// additionally accept bare numbers (defensive: hand-edited files).
//
// `paramsData` stays Data→base64 — the verbatim 02-05 `ModuleInstance`
// Codable spelling (checkpoint lock #1). Byte-exactness is load-bearing:
// `HistoryHash` digests these bytes and unknown-op preservation must
// round-trip them untouched, so no re-pretty-printing of params into the
// outer document (the research §4.3 "inline JSON" sketch is superseded by
// the checkpoint's "verbatim 02-05 spelling" lock).
//
// Date encoding: `JSONEncoder`'s default (seconds since 1970, Double) —
// shortest-roundtrip Doubles decode-exactly, so document equality survives
// a write→read cycle (the SC#3 round-trip contract).
// ─────────────────────────────────────────────────────────────────────────────

/// Property wrapper serializing a `UInt64` as a decimal JSON String
/// (checkpoint 02-06-01 lock #2). Decode accepts BOTH the canonical String
/// and a bare JSON number (defensive decode of hand-edited/older files).
/// `public` per the plan artifacts list — reusable by future persisted
/// hashes (Phase 6 layer documents, Phase 11 export manifests).
@propertyWrapper public struct UInt64String: Codable, Sendable, Hashable {

    public var wrappedValue: UInt64

    public init(wrappedValue: UInt64) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let value = UInt64(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "UInt64String: '\(string)' is not a valid UInt64"
                )
            }
            self.wrappedValue = value
        } else {
            // Defensive: accept a bare number (other tools may emit one).
            self.wrappedValue = try container.decode(UInt64.self)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(wrappedValue))
    }
}

/// The persisted per-image document — `DSC09991.ARW.lra` beside the
/// original (D-S2). One document per image; the coordinator owns a
/// `SidecarStore` per loaded image and (re)writes it whenever the history
/// moves (2s throttled, D-S3).
///
/// Schema (checkpoint 02-06-01 lock #1 — the keys ARE the format):
///
/// ```jsonc
/// {
///   "appVersion" : "0.1.0",
///   "decoderVersionUsed" : "v8",
///   "decodeParamsHash" : "12345678901234567890",   // UInt64-as-String
///   "history" : { "items" : [ …HistoryItem spelling… ], "position" : 7 },
///   "historyHash" : "98765432109876543210",         // UInt64-as-String
///   "imageID" : "UUID-string",
///   "instances" : [ …ModuleInstance spelling, paramsHash as String… ],
///   "layerStack" : null,                            // Phase 6 reservation
///   "schemaVersion" : 1
/// }
/// ```
///
/// `instances`/`history` mirror the 02-05 frozen Codable spellings
/// (checkpoint lock #1) with the ONE lock-#2 deviation: `paramsHash`
/// values are decimal Strings (`SidecarInstanceRecord`). The runtime
/// surface stays `ModuleInstance`/`HistoryStack`; the on-disk spelling
/// lives in exactly one file (this one).
public struct LightamerSidecar: Codable, Sendable, Equatable {

    /// The current schema version (D-S1 migration anchor). Readers MUST
    /// tolerate `schemaVersion > schemaVersionCurrent` by degrading (the
    /// coordinator's drift/unknown-op paths); writers always emit the
    /// current version.
    ///
    /// v2 (Plan 06-01 T6): `layerStack` upgrades from the String reservation
    /// to the typed `SidecarLayerStackRecord` (frozen layer spelling). v1
    /// documents (the key was always null) decode with `layerStack == nil`.
    public static let schemaVersionCurrent = 2

    /// On-disk schema version of this document.
    public var schemaVersion: Int

    /// Producing app version (`Bundle.main` short version; injectable for
    /// tests). Diagnostics only — never hashed.
    public var appVersion: String

    /// The image's cross-session identity (NDE-1 anchor): cache namespace
    /// (`PipeCacheKey.imageID`) + future layer/mask references. Minted once
    /// at first open and persisted forever after (checkpoint lock #7).
    public var imageID: UUID

    /// Which CIRAW decoder produced the image when this document was
    /// written (`DecodedImage.decoderVersionUsed` — RAW 9 changes output
    /// vs RAW 8, so the stamp records what happened).
    public var decoderVersionUsed: String

    /// The decode-side D-H4 atom at write time (`HistoryHash
    /// .decodeParamsHash(for:)`). The drift recompute seeds with THIS value
    /// (the file's own), not the live one — a decoder upgrade must not
    /// false-positive as user-data drift.
    @UInt64String public var decodeParamsHash: UInt64

    /// The full live instance set at write time (the `base ∪ effective`
    /// projection EditorState holds — includes disabled instances and
    /// degraded unknown ops; user data is never dropped).
    public var instances: [ModuleInstance]

    /// The uncapped edit log + position pointer (D-H2; verbatim
    /// `HistoryStack` shape `{items, position}`).
    public var history: HistoryStack

    /// The drift anchor (HIST-04/SC#5): `HistoryHash.hash(stack:
    /// decodeParamsHash:)` at write time; recomputed at load and compared —
    /// mismatch = external edit → log + toast, memory wins, NO write-back.
    @UInt64String public var historyHash: UInt64

    /// The typed adjustment-layer stack (v2 — the frozen 06-01 layer
    /// spelling; always nil in v1 documents).
    public var layerStack: SidecarLayerStackRecord?

    // MARK: - Paths (D-S2)

    /// `…/DSC09991.ARW` → `…/DSC09991.ARW.lra` — the FULL original name
    /// plus the `.lra` suffix (avoids same-stem different-extension
    /// collisions), co-located with the original (Capture/ convention).
    public static func sidecarURL(for imageURL: URL) -> URL {
        URL(fileURLWithPath: imageURL.path + ".lra")
    }

    /// `…/DSC09991.ARW.lra` → `…/DSC09991.ARW`; nil when the URL does not
    /// end in `.lra` (the inverse is total only over real sidecar names).
    public static func imageURL(for sidecarURL: URL) -> URL? {
        guard sidecarURL.pathExtension == "lra" else { return nil }
        let original = String(sidecarURL.path.dropLast(4))
        guard !original.isEmpty, original != "/" else { return nil }
        return URL(fileURLWithPath: original)
    }

    /// The producing app's version (`CFBundleShortVersionString`, fallback
    /// `CFBundleVersion`, fallback "0.0.0") — the default `appVersion` for
    /// production writes; tests inject explicit values.
    public static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        if let short = info?["CFBundleShortVersionString"] as? String, !short.isEmpty {
            return short
        }
        if let build = info?["CFBundleVersion"] as? String, !build.isEmpty {
            return build
        }
        return "0.0.0"
    }

    // MARK: - Init

    public init(
        imageID: UUID,
        decoderVersionUsed: String,
        decodeParamsHash: UInt64,
        instances: [ModuleInstance],
        history: HistoryStack,
        historyHash: UInt64,
        appVersion: String = LightamerSidecar.currentAppVersion,
        layerStack: SidecarLayerStackRecord? = nil
    ) {
        self.schemaVersion = Self.schemaVersionCurrent
        self.appVersion = appVersion
        self.imageID = imageID
        self.decoderVersionUsed = decoderVersionUsed
        self._decodeParamsHash = UInt64String(wrappedValue: decodeParamsHash)
        self.instances = instances
        self.history = history
        self._historyHash = UInt64String(wrappedValue: historyHash)
        self.layerStack = layerStack
    }

    // MARK: - Codable (projection through the String-hash records)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, appVersion, imageID, decoderVersionUsed
        case decodeParamsHash, instances, history, historyHash, layerStack
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        imageID = try container.decode(UUID.self, forKey: .imageID)
        decoderVersionUsed = try container.decode(String.self, forKey: .decoderVersionUsed)
        _decodeParamsHash = try container.decode(UInt64String.self, forKey: .decodeParamsHash)
        instances = try container.decode([SidecarInstanceRecord].self, forKey: .instances)
            .map(\.instance)
        history = try container.decode(SidecarHistoryRecord.self, forKey: .history).stack
        _historyHash = try container.decode(UInt64String.self, forKey: .historyHash)
        // Schema-dependent projection of the layerStack key (06-01 T6):
        // v1 carried the String reservation (always null); v2 carries the
        // typed record. Unknown FUTURE versions degrade the field to nil
        // rather than failing the whole document (D-S1 tolerance).
        if schemaVersion >= 2 {
            layerStack = try container.decodeIfPresent(
                SidecarLayerStackRecord.self, forKey: .layerStack)
        } else {
            _ = try container.decodeIfPresent(String.self, forKey: .layerStack)
            layerStack = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(imageID, forKey: .imageID)
        try container.encode(decoderVersionUsed, forKey: .decoderVersionUsed)
        try container.encode(_decodeParamsHash, forKey: .decodeParamsHash)
        try container.encode(instances.map(SidecarInstanceRecord.init), forKey: .instances)
        try container.encode(SidecarHistoryRecord(stack: history), forKey: .history)
        try container.encode(_historyHash, forKey: .historyHash)
        try container.encodeIfPresent(layerStack, forKey: .layerStack)
    }
}

// MARK: - Private projections (the on-disk spelling, checkpoint locks #1+#2)

/// `ModuleInstance` → on-disk record: identical keys, `paramsHash` as a
/// decimal String (checkpoint lock #2). Every other key reuses the frozen
/// 02-05 spelling verbatim. Internal (not private) since Plan 06-01 T6 —
/// the layer-record spelling (`SidecarLayerRecord`) embeds the same
/// instance spelling, and duplicated keys would be two formats to migrate.
internal struct SidecarInstanceRecord: Codable, Sendable, Equatable {

    /// The keys mirror `ModuleInstance.CodingKeys` (frozen checkpoint lock
    /// #6 of 02-05) — duplicated here because the projection must stay in
    /// exactly one file and never drift silently (a rename here = a
    /// migration, same as a rename there).
    private enum Keys: String, CodingKey {
        case id, opName, multiPriority, multiName, iopOrder
        case version, enabled, paramsData, paramsHash
    }

    var instance: ModuleInstance {
        ModuleInstance(
            id: id, opName: opName, multiPriority: multiPriority,
            multiName: multiName, iopOrder: iopOrder, version: version,
            enabled: enabled, paramsData: paramsData,
            paramsHash: paramsHash
        )
    }

    private var id: UUID
    private var opName: String
    private var multiPriority: Int
    private var multiName: String
    private var iopOrder: Float
    private var version: Int
    private var enabled: Bool
    private var paramsData: Data
    @UInt64String private var paramsHash: UInt64

    init(_ instance: ModuleInstance) {
        id = instance.id
        opName = instance.opName
        multiPriority = instance.multiPriority
        multiName = instance.multiName
        iopOrder = instance.iopOrder
        version = instance.version
        enabled = instance.enabled
        paramsData = instance.paramsData
        _paramsHash = UInt64String(wrappedValue: instance.paramsHash)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        id = try container.decode(UUID.self, forKey: .id)
        opName = try container.decode(String.self, forKey: .opName)
        multiPriority = try container.decode(Int.self, forKey: .multiPriority)
        multiName = try container.decode(String.self, forKey: .multiName)
        iopOrder = try container.decode(Float.self, forKey: .iopOrder)
        version = try container.decode(Int.self, forKey: .version)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        paramsData = try container.decode(Data.self, forKey: .paramsData)
        _paramsHash = try container.decode(UInt64String.self, forKey: .paramsHash)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(opName, forKey: .opName)
        try container.encode(multiPriority, forKey: .multiPriority)
        try container.encode(multiName, forKey: .multiName)
        try container.encode(iopOrder, forKey: .iopOrder)
        try container.encode(version, forKey: .version)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(paramsData, forKey: .paramsData)
        try container.encode(_paramsHash, forKey: .paramsHash)
    }

    static func == (lhs: SidecarInstanceRecord, rhs: SidecarInstanceRecord) -> Bool {
        lhs.id == rhs.id && lhs.opName == rhs.opName
            && lhs.multiPriority == rhs.multiPriority && lhs.multiName == rhs.multiName
            && lhs.iopOrder == rhs.iopOrder && lhs.version == rhs.version
            && lhs.enabled == rhs.enabled && lhs.paramsData == rhs.paramsData
            && lhs.paramsHash == rhs.paramsHash
    }
}

/// `HistoryStack.HistoryItem` → on-disk record: `{id, snapshot, label,
/// timestamp, layerScope}` with the inline snapshot's `paramsHash` as a
/// String; 06-01 T6 adds `stackSnapshot` (the layer-stack snapshot through
/// the same frozen layer spelling), optional + decodeIfPresent — v1
/// documents decode with nil.
private struct SidecarHistoryItemRecord: Codable, Sendable, Equatable {

    private enum Keys: String, CodingKey {
        case id, snapshot, label, timestamp, layerScope, stackSnapshot
    }

    var item: HistoryStack.HistoryItem {
        HistoryStack.HistoryItem(
            id: id, snapshot: snapshot.instance, label: label,
            timestamp: timestamp, layerScope: layerScope,
            stackSnapshot: stackSnapshot?.snapshot
        )
    }

    private var id: UUID
    private var snapshot: SidecarInstanceRecord
    private var label: String
    private var timestamp: Date
    private var layerScope: String?
    private var stackSnapshot: SidecarLayerStackRecord?

    init(_ item: HistoryStack.HistoryItem) {
        id = item.id
        snapshot = SidecarInstanceRecord(item.snapshot)
        label = item.label
        timestamp = item.timestamp
        layerScope = item.layerScope
        stackSnapshot = item.stackSnapshot.map(SidecarLayerStackRecord.init)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        id = try container.decode(UUID.self, forKey: .id)
        snapshot = try container.decode(SidecarInstanceRecord.self, forKey: .snapshot)
        label = try container.decode(String.self, forKey: .label)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        layerScope = try container.decodeIfPresent(String.self, forKey: .layerScope)
        stackSnapshot = try container.decodeIfPresent(
            SidecarLayerStackRecord.self, forKey: .stackSnapshot)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encode(label, forKey: .label)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(layerScope, forKey: .layerScope)
        try container.encodeIfPresent(stackSnapshot, forKey: .stackSnapshot)
    }
}

/// `HistoryStack` → on-disk record: `{items, position}` verbatim (frozen
/// 02-05 spelling).
private struct SidecarHistoryRecord: Codable, Sendable, Equatable {

    private enum Keys: String, CodingKey {
        case items, position
    }

    var stack: HistoryStack {
        HistoryStack(items: items.map(\.item), position: position)
    }

    private var items: [SidecarHistoryItemRecord]
    private var position: Int

    init(stack: HistoryStack) {
        items = stack.items.map(SidecarHistoryItemRecord.init)
        position = stack.position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        items = try container.decode([SidecarHistoryItemRecord].self, forKey: .items)
        position = try container.decode(Int.self, forKey: .position)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(items, forKey: .items)
        try container.encode(position, forKey: .position)
    }
}

// MARK: - Restore helpers (Core-level, testable; the App coordinator consumes)

public extension LightamerSidecar {

    /// The drift verdict (HIST-04/SC#5; checkpoint lock #5): recompute
    /// `HistoryHash.hash` from the RESTORED stack seeded with the FILE's
    /// OWN `decodeParamsHash` — a mismatch means the document's
    /// params/history were edited out-of-band after the write. Layer-aware
    /// since 06-01 T6: the document's own layer records are folded in
    /// explicitly (L013 — field folds, never JSON bytes), so a
    /// layer-param/structure tamper is drift too; v1 documents (nil layer
    /// stack) hash exactly as the 02-06 form did. Seeding with the file's
    /// own decode hash (not the live one) keeps a decoder upgrade from
    /// false-positive as user drift.
    var driftDetected: Bool {
        HistoryHash.hash(
            stack: history, decodeParamsHash: decodeParamsHash,
            layerSnapshot: layerStack?.snapshot)
            != historyHash
    }

    /// The unknown-op degrade pass (checkpoint lock #4; research Risk #10):
    /// every snapshot whose `opName` the CURRENT binary cannot build
    /// (`registry.makeBox` nil) is kept VERBATIM except `enabled = false`
    /// — user data is never dropped, and the pipe walk skips disabled
    /// instances. Applied to the history items so a later
    /// `rebuildInstances()` cannot resurrect enabled-ness.
    ///
    /// Returns the degraded stack + the unknown op names (first-occurrence
    /// order, deduplicated) for the toast ("未知模块 <op> 已停用（数据已保留）").
    func degradedForUnknownOps(registry: ModuleRegistry) async
        -> (history: HistoryStack, unknownOps: [String])
    {
        var degradedItems = history.items
        var unknown: [String] = []
        var seen = Set<String>()
        for index in degradedItems.indices {
            let snapshot = degradedItems[index].snapshot
            if await registry.makeBox(opName: snapshot.opName, instanceID: snapshot.id) == nil {
                degradedItems[index].snapshot.enabled = false
                if seen.insert(snapshot.opName).inserted {
                    unknown.append(snapshot.opName)
                }
            }
        }
        return (HistoryStack(items: degradedItems, position: history.position), unknown)
    }

    /// The unknown-op degrade pass over the LAYER chains (Plan 06-01 T6 —
    /// the 02-06 mechanism applied per layer): a record whose op the
    /// current binary cannot build is kept VERBATIM except the whole layer
    /// flips `enabled = false` (the layer drops out of the composite; its
    /// chain bytes survive for a future binary).
    ///
    /// Returns the degraded records + unknown op names (first occurrence).
    func degradedLayerStack(registry: ModuleRegistry) async
        -> (layerStack: SidecarLayerStackRecord?, unknownOps: [String])
    {
        guard let layerStack else { return (nil, []) }
        var degradedLayers: [SidecarLayerRecord] = []
        var unknown: [String] = []
        var seen = Set<String>()
        for layer in layerStack.layers {
            var degradedLayer = layer
            var layerHasUnknownOp = false
            for record in layer.chain {
                let instance = record.instance
                if await registry.makeBox(opName: instance.opName, instanceID: instance.id) == nil {
                    layerHasUnknownOp = true
                    if seen.insert(instance.opName).inserted {
                        unknown.append(instance.opName)
                    }
                }
            }
            if layerHasUnknownOp {
                degradedLayer = layer.degraded()
            }
            degradedLayers.append(degradedLayer)
        }
        return (SidecarLayerStackRecord(layers: degradedLayers), unknown)
    }
}
