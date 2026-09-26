import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LightamerPreset — the `.lightamer-preset` container (Plan 12-4 T1;
// D-12-CONTEXT-5). ONE preset = ONE file under
// `~/Library/Application Support/Lightamer/Presets/<uuid>.lightamer-preset`.
//
// FORMAT LOCK (ONE-WAY, `LightamerSidecar.swift:7-8` pattern): JSON with
// `.prettyPrinted + .sortedKeys` (git-diff-stable), `schemaVersion: 1` from
// day one; readers MUST tolerate `schemaVersion > 1` by degrading (the
// D-S1 posture — never a hard failure).
//
// The container is a DISK PERSISTED byte format, so the L013 decimal-String
// rule applies: `instances` ride the SAME `SidecarInstanceRecord` spelling
// the sidecar uses (identical keys, `paramsHash` as a decimal String) —
// verbatim reuse, zero second spelling to migrate (the plan's projection
// ruling; the record is internal to Core, this file is in Core).
//
// A develop preset is a PastePayload TWIN on disk: `instances` = the
// compose产物 of the copy path (skip set ALREADY applied — decode domain
// boundary 15.0 / identity defaults / auto-detect verbatim, D-09-CONTEXT-5
// 正本 reused, never re-implemented). `layerStack` is an additive
// RESERVATION (mask semantics undefined, D-12-CONTEXT deferred) — v1 keeps
// it nil and never writes the key. `exportRecipe` (the Phase 11 移交①)
// mounts `ExportRecipe`/`ExportVariant` verbatim — they are Codable with
// ZERO hash fields (L013-clean by construction), so mounting is wiring,
// not migration.
//
// Date encoding: JSONEncoder's default (seconds since 1970, Double) — the
// sidecar convention; document equality survives a write→read cycle.
// ─────────────────────────────────────────────────────────────────────────────

/// The `.lightamer-preset` document (the persisted body).
public struct LightamerPreset: Codable, Sendable, Equatable {

    /// The current schema version (the D-S1 migration anchor; readers
    /// tolerate `> 1` by degrading, writers always emit 1).
    public static let schemaVersionCurrent = 1

    /// The preset kind (additive enum): `develop` presets carry the paste-
    /// twin instance snapshot; `export` presets carry the export recipe.
    public enum Kind: String, Codable, Sendable, Equatable {
        case develop
        case export
    }

    /// The typed mutual-exclusion violation (the plan's pinned vector: a
    /// develop preset must never carry an export recipe).
    public enum ValidationError: Error, Equatable, Sendable {
        case developCarriesExportRecipe(name: String)
    }

    public var schemaVersion: Int

    public var kind: Kind

    /// The user-visible name (the manager's rename face; duplicate display
    /// names are allowed — the file stem is the identity).
    public var name: String

    /// The free-form grouping key (the manager's sidebar sections). nil =
    /// uncategorized.
    public var category: String?

    /// Producing app version (diagnostics — never validated).
    public var appVersion: String

    public var createdAt: Date

    /// The frozen develop-instance snapshot (skip set already applied).
    /// Runtime face = `ModuleInstance`; the PERSISTED spelling is the
    /// sidecar's `SidecarInstanceRecord` (L013 decimal-String paramsHash).
    public var instances: [ModuleInstance]

    /// The additive reservation for the layer-stack snapshot (D-12-CONTEXT
    /// deferred — mask semantics undefined). v1 keeps this nil and NEVER
    /// writes the key (encodeIfPresent — the absent form is the golden).
    public var layerStack: SidecarLayerStackRecord?

    /// The export face (kind == .export only). develop presets must leave
    /// this nil (the typed mutual-exclusion check); encode omits the key
    /// when nil (the plan's 「恒 nil/省略」 form).
    public var exportRecipe: ExportRecipe?

    public init(
        kind: Kind,
        name: String,
        category: String? = nil,
        appVersion: String = LightamerSidecar.currentAppVersion,
        createdAt: Date = Date(),
        instances: [ModuleInstance] = [],
        layerStack: SidecarLayerStackRecord? = nil,
        exportRecipe: ExportRecipe? = nil
    ) {
        self.schemaVersion = Self.schemaVersionCurrent
        self.kind = kind
        self.name = name
        self.category = category
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.instances = instances
        self.layerStack = layerStack
        self.exportRecipe = exportRecipe
    }

    // MARK: - Validation (the kind/recipe mutual exclusion)

    /// The format-level validity face (called by `PresetsStore` on every
    /// scan/create/import — a violation is a TYPED error, the store then
    /// degrades the file to its skipped list, never a crash).
    public func validate() throws {
        if kind == .develop, exportRecipe != nil {
            throw ValidationError.developCarriesExportRecipe(name: name)
        }
    }

    // MARK: - Codable (the on-disk spelling)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, name, category, appVersion, createdAt
        case instances, layerStack, exportRecipe
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(Kind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // L013: the persisted spelling is the sidecar's record (decimal-
        // String paramsHash); the runtime face converts back.
        instances = try container.decode([SidecarInstanceRecord].self, forKey: .instances)
            .map(\.instance)
        // Additive reservations: decodeIfPresent — a v1 file without the
        // keys reads with both nil; a FUTURE version's extra keys are
        // ignored by the keyed decoder (the tolerance posture).
        layerStack = try container.decodeIfPresent(
            SidecarLayerStackRecord.self, forKey: .layerStack)
        exportRecipe = try container.decodeIfPresent(ExportRecipe.self, forKey: .exportRecipe)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(instances.map(SidecarInstanceRecord.init), forKey: .instances)
        try container.encodeIfPresent(layerStack, forKey: .layerStack)
        try container.encodeIfPresent(exportRecipe, forKey: .exportRecipe)
    }
}
