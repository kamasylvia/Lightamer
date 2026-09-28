import CoreGraphics
import CoreImage
import CoreText
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-3: the culling-domain toolset (14 tools, research §A #5-10 + 11-15
// + 16-18). Pure-Swift handlers over the 14-1 registry seam — NO `import MCP`
// (the closed-set Core discipline reaches every tool file).
//
// Four "reuse black bodies" wired, never re-implemented (D-14-CONTEXT-8):
//   list_photos      = FilterSQL.translateConjoining + SessionIndexStore.query
//                      (the 25-column projection lives in PhotoProjection.swift;
//                      keyset cursor = caller-side ExtraPredicate, FilterSQL
//                      byte-identical)
//   write five       = MetadataService (the GUI/MCP single source) + claim
//                      face — MCP never touches sidecar bytes directly
//   preset trio      = PresetsStore read face + PresetApplier.apply (the
//                      live-soft-skip D8 half: skippedRelPaths report face)
//   image trio       = dual-tier thumbnail READ (09-期 appointment semantics),
//                      pure-CG contact sheet, RAWDecoder decode leg crop —
//                      render-class tools serialize on McpRenderGate
//   burst / faces    = in-memory clustering over one capture_date-ordered
//                      scan; VNDetectFaceLandmarksRequest direct (Vision),
//                      never the SkinSmooth hull orchestration
//
// v1 evaluation domain = the CURRENTLY OPEN session (D-14-CONTEXT-9 — the
// SQL domain-dispatch seam stays unconnected; the input schemas expose NO
// domain parameter). No open session → typed `notSessionMember` ("no open
// session…").
// ─────────────────────────────────────────────────────────────────────────────

/// The host-injected environment for the culling tools. Every seam is a
/// provider closure so the headless host (14-4 assembly) and the tests wire
/// their own — the tools never construct session state themselves.
struct McpCullingContext: Sendable {

    /// The open session's index (nil = no session — the honest no-session
    /// shape; the GUI host injects its live store).
    var store: @Sendable () async -> SessionIndexStore?

    /// The open session's root (nil = no session; file-IO legs need it).
    var sessionRoot: @Sendable () async -> URL?

    /// The metadata single source (MetadataService over the shared batch
    /// writer — the same instance the GUI uses).
    var metadata: @Sendable () async -> MetadataService?

    /// The segment-3 serial writer for the preset apply leg.
    var sidecarWriter: @Sendable () async -> BatchSidecarWriter?

    /// The app-level preset library.
    var presets: @Sendable () async -> PresetsStore?

    /// The GUI-live relPath set (PipeCoordinator's current image, App-side;
    /// headless = empty). apply_preset soft-skips these into the outcome.
    var liveRelPaths: @Sendable () async -> Set<String>

    /// The thumbnail provider (the 09-03 queue — the regenerate=true leg's
    /// ONLY route; nil = regenerate unavailable in this host).
    var thumbnailProvider: @Sendable () async -> SessionThumbnailProvider?

    /// The detail-crop/face decode leg: file URL → decoded CGImage. The
    /// production leg is `defaultDecodeImage` (RAWDecoder + CIContext);
    /// tests inject synthetic images.
    var decodeImage: @Sendable (URL) async throws -> CGImage

    /// The render-class serial gate (14-1 seam — concurrency 1).
    var renderGate: McpRenderGate

    init(
        store: @escaping @Sendable () async -> SessionIndexStore? = { nil },
        sessionRoot: @escaping @Sendable () async -> URL? = { nil },
        metadata: @escaping @Sendable () async -> MetadataService? = { nil },
        sidecarWriter: @escaping @Sendable () async -> BatchSidecarWriter? = { nil },
        presets: @escaping @Sendable () async -> PresetsStore? = { nil },
        liveRelPaths: @escaping @Sendable () async -> Set<String> = { [] },
        thumbnailProvider: @escaping @Sendable () async -> SessionThumbnailProvider? = { nil },
        decodeImage: @escaping @Sendable (URL) async throws -> CGImage,
        renderGate: McpRenderGate = McpRenderGate()
    ) {
        self.store = store
        self.sessionRoot = sessionRoot
        self.metadata = metadata
        self.sidecarWriter = sidecarWriter
        self.presets = presets
        self.liveRelPaths = liveRelPaths
        self.thumbnailProvider = thumbnailProvider
        self.decodeImage = decodeImage
        self.renderGate = renderGate
    }

    /// The production decode leg (the host assembly's default): RAWDecoder
    /// (D-24 unified RAW+raster entry) → CIContext render → CGImage. Not
    /// exercised by the unit tests (they inject synthetic images).
    static func defaultDecodeImage() -> @Sendable (URL) async throws -> CGImage {
        let decoder = RAWDecoder()
        let context = CIContext()
        return { url in
            let decoded = try await decoder.decode(url)
            let ciImage = decoded.ciImage
            guard let cgImage = context.createCGImage(
                ciImage, from: ciImage.extent)
            else {
                throw McpToolError.renderFailed(
                    "decode produced no CGImage for \(url.lastPathComponent)")
            }
            return cgImage
        }
    }
}

enum McpCullingToolset {

    // MARK: - Shared argument helpers

    /// Resolve (store, root) or fail with the honest no-session shape.
    static func requireSession(
        _ context: McpCullingContext
    ) async throws -> (SessionIndexStore, URL) {
        guard let store = await context.store() else {
            throw McpToolError.notSessionMember(
                "no open session — the culling tools evaluate against the "
                    + "currently open Lightamer session; open one in the app "
                    + "first")
        }
        guard let root = await context.sessionRoot() else {
            throw McpToolError.notSessionMember("no open session root")
        }
        return (store, root)
    }

    /// Decode `relPaths` (non-empty string array, ≤ max) or typed
    /// `invalidParams`.
    static func requireRelPaths(
        _ arguments: [String: McpJSON], max: Int
    ) throws -> [String] {
        guard let items = arguments["relPaths"]?.arrayValue, !items.isEmpty else {
            throw McpToolError.invalidParams("relPaths must be a non-empty array of strings")
        }
        guard items.count <= max else {
            throw McpToolError.invalidParams(
                "relPaths accepts at most \(max) entries per request; page the call")
        }
        let paths = items.map(\.stringValue)
        guard paths.allSatisfy({ $0 != nil }) else {
            throw McpToolError.invalidParams("relPaths entries must be strings")
        }
        return paths.map { $0! }
    }

    /// Session-membership pre-check — the notSessionMember negative lives
    /// HERE (once, before any write face composes documents).
    static func requireMembers(
        _ relPaths: [String], store: SessionIndexStore
    ) async throws {
        for relPath in relPaths {
            if try await store.fetchRow(relPath: relPath) == nil {
                throw McpToolError.notSessionMember(
                    "'\(relPath)' is not a member of the open session")
            }
        }
    }

    /// A bounded wait (the plan's McpTimeouts consumption): races the body
    /// against the timeout. The loser task is cancelled; the group's scope
    /// exit still awaits a cancellation-ignoring body (no void tasks — the
    /// honest v1 shape; a stuck body blocks rather than leaks).
    static func withTimeout<T: Sendable>(
        _ duration: Duration, _ code: McpToolError,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw code
            }
            let winner = try await group.next()!
            group.cancelAll()
            return winner
        }
    }

    // MARK: - Registration (grows per task; the snapshot rides each commit)

    /// Registers the culling-domain tools (the current task's face).
    static func registerAll(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        await registerListPhotos(on: registry, context: context)
        await registerWriteFive(on: registry, context: context)
        await registerPresetTrio(on: registry, context: context)
    }

    // MARK: - list_photos (§A #5)

    private static func registerListPhotos(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "list_photos",
                description:
                    "List photos of the CURRENTLY OPEN Lightamer session. `filter` "
                    + "is a FilterPredicateGroup JSON object "
                    + "({\"schemaVersion\":1,\"match\":\"all\"|\"any\",\"rules\":"
                    + "[{\"field\":…,\"op\":…,\"value\":{\"kind\":…}}]}); fields: "
                    + "rating, colorLabel, keywords, flag, note, cameraMake, "
                    + "cameraModel, lensModel, iso, focalLength, aperture, exposure, "
                    + "captureDate, hasEdits, filename, dir; ops: eq, neq, gt, gte, "
                    + "lt, lte, between, in, contains, startsWith, empty, notEmpty; "
                    + "values are tagged {\"kind\":\"text|int|double|textList|intRange|"
                    + "doubleRange|intList|doubleList\", …}. `sort` is "
                    + "{key: filename|rating|captureDate|iso|focalLength|scanEpoch, "
                    + "ascending}. Pagination: pass back `nextCursor` as `cursor`; "
                    + "a short page means the end (no total count is returned). "
                    + "Rows expose 25 columns (path/dir/filename, file_size/"
                    + "file_mtime, has_edits, layer_count/layer_summary, orientation/"
                    + "width/height, capture_date, thumb_state, rating/color_label/"
                    + "keywords/flag/note, camera_make/camera_model/lens_model, iso/"
                    + "focal_length/aperture/exposure); width/height are the pixel "
                    + "coordinate system get_detail_crop ROIs are validated against.",
                inputSchemaJSON:
                    #"{"type":"object","properties":{"cursor":{"type":"string","description":"Opaque nextCursor token from the previous page"},"filter":{"type":"object","description":"FilterPredicateGroup JSON: {schemaVersion:1, match:"all"|"any", rules:[{field, op, value:{kind, ...}}]}"},"limit":{"type":"integer","minimum":1,"maximum":1000,"description":"Rows per page (default 200)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength|scanEpoch, ascending: bool}"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("list_photos timed out")
                ) {
                    try await listPhotos(arguments, context: context)
                }
            })
    }

    /// The list_photos body: FilterPredicateGroup direct-decode →
    /// translateConjoining (inside query) → 25-column projection → keyset
    /// paging. NO total count (the COUNT second pass is deliberately absent).
    static func listPhotos(
        _ arguments: [String: McpJSON], context: McpCullingContext
    ) async throws -> McpToolOutput {
        let (store, _) = try await requireSession(context)
        let filter = try McpPhotoProjection.decodeFilter(arguments)
        let sort = try McpPhotoProjection.decodeSort(arguments)
        let limit = try McpPhotoProjection.decodeLimit(arguments)
        var extra: SessionIndexStore.ExtraPredicate?
        if let cursorRaw = arguments["cursor"]?.stringValue, !cursorRaw.isEmpty {
            extra = try McpPhotoProjection.cursorPredicate(cursorRaw, sort: sort)
        }
        let rows = try await store.query(
            groups: filter.map { [$0] } ?? [],
            sort: sort, limit: limit, extraPredicate: extra)
        let nextCursor = McpPhotoProjection.nextCursor(rows: rows, sort: sort, limit: limit)
        let projected = rows.map { row in
            McpJSON.object(McpPhotoProjection.rowDict(from: row))
        }
        let payload = McpJSON.object([
            "rows": .array(projected),
            "nextCursor": nextCursor.map { .string($0) } ?? .null,
        ])
        return .text(McpJSONSerialization.text(from: payload))
    }

    // MARK: - Write five (§A #11-15 — MetadataService, the GUI/MCP ONE source)

    /// The shared write-five registration frame: every tool is
    /// `destructiveHint` + `requiresWriter` (the registry pre-hook fails
    /// closed with `serverReadOnly` on a read-only instance). The write
    /// path IS MetadataService — the same three segments the GUI rides
    /// (D-14-CONTEXT-5①); MCP never touches sidecar bytes. NOTE the
    /// deliberate asymmetry with the params face: metadata writes do NOT
    /// reject GUI-live targets — the claim face has no live protection and
    /// a rating is not a parameter change (D-8: no history, no stale).
    private static func registerWriteFive(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        /// The common frame: timeout → metadata service → membership →
        /// per-tool body → outcome JSON.
        func registerOne(
            _ name: String, _ schema: String,
            _ body: @escaping @Sendable (MetadataService, [String], [String: McpJSON])
                async throws -> MetadataEditOutcome
        ) async {
            await registry.register(
                McpToolDescriptor(
                    name: name,
                    description:
                        "Write metadata on photos of the CURRENTLY OPEN Lightamer "
                            + "session (batch relPaths). One bulk change = one "
                            + "transaction; the write lands in the sidecar truth AND "
                            + "the session index (the GUI grid/filter face reads the "
                            + "same index). MODIFIES session metadata only — never "
                            + "pixels, never file delete/move.",
                    inputSchemaJSON: schema,
                    destructiveHint: true),
                requiresWriter: true,
                handler: { arguments in
                    try await withTimeout(
                        McpTimeouts.metadataWrite,
                        McpToolError.internalError("\(name) timed out")
                    ) {
                        guard let metadata = await context.metadata() else {
                            throw McpToolError.internalError(
                                "metadata service unavailable in this host")
                        }
                        let relPaths = try requireRelPaths(arguments, max: 1000)
                        let (store, _) = try await requireSession(context)
                        try await requireMembers(relPaths, store: store)
                        let outcome = try await body(metadata, relPaths, arguments)
                        return .text(
                            McpJSONSerialization.text(from: .object([
                                "appliedRelPaths": .array(
                                    outcome.appliedRelPaths.map { .string($0) }),
                                "skippedRelPaths": .array(
                                    outcome.skippedRelPaths.map { .string($0) }),
                            ])))
                    }
                })
        }

        // §A #11 set_rating
        await registerOne(
            "set_rating",
            #"{"type":"object","required":["relPaths","rating"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"rating":{"type":["integer","null"],"minimum":0,"maximum":5,"description":"0-5, or null to clear"}}}"#
        ) { metadata, relPaths, arguments in
            guard let ratingArg = arguments["rating"] else {
                throw McpToolError.invalidParams("rating is required (0-5 or null)")
            }
            let rating: Int?
            switch ratingArg {
            case .null: rating = nil
            case .int(let value) where (0...5).contains(value): rating = value
            default:
                throw McpToolError.invalidParams("rating must be an integer 0-5 or null")
            }
            return try await metadata.setRating(rating, relPaths: relPaths)
        }

        // §A #12 set_flag
        await registerOne(
            "set_flag",
            #"{"type":"object","required":["relPaths","flag"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"flag":{"type":["integer","null"],"minimum":0,"maximum":2,"description":"0 none / 1 pick / 2 reject, or null to clear"}}}"#
        ) { metadata, relPaths, arguments in
            guard let flagArg = arguments["flag"] else {
                throw McpToolError.invalidParams("flag is required (0/1/2 or null)")
            }
            let flag: Int?
            switch flagArg {
            case .null: flag = nil
            case .int(let value) where (0...2).contains(value): flag = value
            default:
                throw McpToolError.invalidParams("flag must be 0, 1, 2 or null")
            }
            return try await metadata.setFlag(flag, relPaths: relPaths)
        }

        // §A #13 set_color_label
        await registerOne(
            "set_color_label",
            #"{"type":"object","required":["relPaths","color"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"color":{"type":["integer","null"],"minimum":0,"maximum":6,"description":"0-6, or null to clear"}}}"#
        ) { metadata, relPaths, arguments in
            guard let colorArg = arguments["color"] else {
                throw McpToolError.invalidParams("color is required (0-6 or null)")
            }
            let color: Int?
            switch colorArg {
            case .null: color = nil
            case .int(let value) where (0...6).contains(value): color = value
            default:
                throw McpToolError.invalidParams("color must be an integer 0-6 or null")
            }
            return try await metadata.setColorLabel(color, relPaths: relPaths)
        }

        // §A #14 append_note
        await registerOne(
            "append_note",
            #"{"type":"object","required":["relPaths","note"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"note":{"type":"string","minLength":1,"description":"Appended as one line (a newline is inserted after an existing note)"}}}"#
        ) { metadata, relPaths, arguments in
            guard let note = arguments["note"]?.stringValue, !note.isEmpty else {
                throw McpToolError.invalidParams("note must be a non-empty string")
            }
            return try await metadata.appendNote(note, relPaths: relPaths)
        }

        // §A #15 set_keywords — WHOLE-GROUP replacement (MetadataService
        // setKeywords semantics); the `|` separator rides the typed
        // keywordContainsSeparator code.
        await registerOne(
            "set_keywords",
            #"{"type":"object","required":["relPaths","keywords"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"keywords":{"type":["array","null"],"items":{"type":"string"},"description":"Whole-group replacement; empty array = cleared state, null = never-tagged; entries must not contain '|'"}}}"#
        ) { metadata, relPaths, arguments in
            guard let keywordsArg = arguments["keywords"] else {
                throw McpToolError.invalidParams("keywords is required (array or null)")
            }
            let keywords: [String]?
            switch keywordsArg {
            case .null: keywords = nil
            case .array(let items):
                let values = items.map(\.stringValue)
                guard values.allSatisfy({ $0 != nil }) else {
                    throw McpToolError.invalidParams("keywords entries must be strings")
                }
                keywords = values.map { $0! }
            default:
                throw McpToolError.invalidParams("keywords must be an array of strings or null")
            }
            do {
                return try await metadata.setKeywords(keywords, relPaths: relPaths)
            } catch MetadataService.MetadataError.keywordContainsSeparator(let keyword) {
                throw McpToolError.keywordContainsSeparator(
                    "'\(keyword)' contains the hierarchical path separator '|'")
            }
        }
    }

    // MARK: - Preset trio (§A #16-18)

    private static func registerPresetTrio(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        // §A #16 list_presets
        await registry.register(
            McpToolDescriptor(
                name: "list_presets",
                description:
                    "List the app-level Lightamer presets (develop = adjustment "
                        + "recipes; export = output recipes). Filter by `kind` or "
                        + "omit it for all.",
                inputSchemaJSON:
                    #"{"type":"object","properties":{"kind":{"enum":["develop","export"],"description":"Filter by preset kind"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("list_presets timed out")
                ) {
                    guard let presets = await context.presets() else {
                        throw McpToolError.internalError(
                            "preset library unavailable in this host")
                    }
                    var kind: LightamerPreset.Kind?
                    if let kindRaw = arguments["kind"]?.stringValue {
                        guard let parsed = LightamerPreset.Kind(rawValue: kindRaw) else {
                            throw McpToolError.invalidParams(
                                "kind must be 'develop' or 'export'")
                        }
                        kind = parsed
                    }
                    let stored = kind.map { presets.presets(kind: $0) } ?? presets.presets()
                    let rows = stored.map { preset -> McpJSON in
                        .object([
                            "id": .string(preset.id),
                            "name": .string(preset.document.name),
                            "kind": .string(preset.document.kind.rawValue),
                            "category": preset.document.category.map { .string($0) } ?? .null,
                            "instanceCount": .int(preset.document.instances.count),
                        ])
                    }
                    return .text(McpJSONSerialization.text(from: .object([
                        "presets": .array(rows),
                    ])))
                }
            })

        // §A #17 apply_preset — the D8 half: GUI-live targets ride
        // PresetApplier's liveRelPaths skip and surface in
        // skippedRelPaths (soft skip — no error, no batch blockage).
        await registry.register(
            McpToolDescriptor(
                name: "apply_preset",
                description:
                    "Apply a develop preset to photos of the CURRENTLY OPEN Lightamer "
                        + "session (apply = paste semantics; mode 'merge' appends onto "
                        + "each target's history, 'overwrite' resets to the preset). "
                        + "Photos open in the GUI editor are SKIPPED and reported in "
                        + "skippedRelPaths (ask the user to close them there or pick "
                        + "other photos). Export-kind presets cannot be applied here.",
                inputSchemaJSON:
                    #"{"type":"object","required":["presetID","relPaths"],"properties":{"presetID":{"type":"string"},"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"mode":{"enum":["overwrite","merge"],"description":"Paste mode (default merge)"},"selection":{"type":"array","description":"Partial-apply subset of instances","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer"},"multiName":{"type":"string"}},"required":["opName","multiPriority","multiName"]}}}}"#,
                destructiveHint: true),
            requiresWriter: true,
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.apply,
                    McpToolError.internalError("apply_preset timed out")
                ) {
                    guard let presetID = arguments["presetID"]?.stringValue else {
                        throw McpToolError.invalidParams("presetID is required")
                    }
                    let relPaths = try requireRelPaths(arguments, max: 1000)
                    var mode = PasteMode.merge
                    if let modeRaw = arguments["mode"]?.stringValue {
                        switch modeRaw {
                        case "overwrite": mode = .overwrite
                        case "merge": mode = .merge
                        default:
                            throw McpToolError.invalidParams(
                                "mode must be 'overwrite' or 'merge'")
                        }
                    }
                    var selection: Set<PastePayload.InstanceKey>?
                    if let selectionArg = arguments["selection"]?.arrayValue {
                        var keys: Set<PastePayload.InstanceKey> = []
                        for item in selectionArg {
                            guard let opName = item["opName"]?.stringValue,
                                let multiPriority = item["multiPriority"]?.intValue,
                                let multiName = item["multiName"]?.stringValue
                            else {
                                throw McpToolError.invalidParams(
                                    "selection entries need opName/multiPriority/multiName")
                            }
                            keys.insert(
                                PastePayload.InstanceKey(
                                    opName: opName, multiPriority: multiPriority,
                                    multiName: multiName))
                        }
                        selection = keys
                    }
                    guard let presetsStore = await context.presets() else {
                        throw McpToolError.internalError(
                            "preset library unavailable in this host")
                    }
                    let (store, root) = try await requireSession(context)
                    try await requireMembers(relPaths, store: store)
                    guard let writer = await context.sidecarWriter() else {
                        throw McpToolError.internalError(
                            "sidecar writer unavailable in this host")
                    }
                    // The D8 soft-skip: the GUI-live subset rides the
                    // applier's existing skip (the report face), NOT a
                    // typed error (the apply_params hard-reject is the
                    // 14-2 half of the钉板).
                    let live = await context.liveRelPaths()
                    let liveTargets = Set(relPaths).intersection(live)
                    let outcome: BatchApplyOutcome
                    do {
                        outcome = try await PresetApplier.apply(
                            presetID: presetID, presetsStore: presetsStore,
                            root: root, relPaths: relPaths, mode: mode,
                            seed: [], selection: selection,
                            liveRelPaths: liveTargets,
                            indexStore: store, writer: writer,
                            label: "mcp-apply-preset")
                    } catch let error as PresetError {
                        // An id-addressed load whose FILE is missing is an
                        // unknown preset too (loadDocument surfaces the
                        // missing file as unreadableFile).
                        if case .notFound(let id) = error {
                            throw McpToolError.unknownPreset(
                                "no preset with id '\(id)'")
                        }
                        if case .unreadableFile(let name) = error {
                            throw McpToolError.unknownPreset(
                                "no preset file '\(name)' (unknown id)")
                        }
                        throw McpToolError.internalError("\(error)")
                    } catch let error as PresetApplier.ApplyError {
                        if case .exportPresetNotApplicable(let name) = error {
                            throw McpToolError.exportPresetNotApplicable(
                                "'\(name)' is an export preset — it cannot be "
                                    + "applied to photos (export presets fill the "
                                    + "export panel)")
                        }
                        throw McpToolError.internalError("\(error)")
                    }
                    return .text(
                        McpJSONSerialization.text(from: .object([
                            "appliedRelPaths": .array(
                                outcome.appliedRelPaths.map { .string($0) }),
                            "skippedRelPaths": .array(
                                outcome.skippedLiveRelPaths.map { .string($0) }),
                            "failedRelPaths": .array(
                                outcome.failedRelPaths.map { .string($0) }),
                        ])))
                }
            })

        // §A #18 diff_presets
        await registry.register(
            McpToolDescriptor(
                name: "diff_presets",
                description:
                    "Diff two presets by instance key (opName + multiPriority): "
                        + "which instances exist only in A, only in B, or in both "
                        + "with different parameters.",
                inputSchemaJSON:
                    #"{"type":"object","required":["presetIDA","presetIDB"],"properties":{"presetIDA":{"type":"string"},"presetIDB":{"type":"string"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("diff_presets timed out")
                ) {
                    guard let idA = arguments["presetIDA"]?.stringValue,
                        let idB = arguments["presetIDB"]?.stringValue
                    else {
                        throw McpToolError.invalidParams(
                            "presetIDA and presetIDB are required")
                    }
                    guard let presets = await context.presets() else {
                        throw McpToolError.internalError(
                            "preset library unavailable in this host")
                    }
                    func load(_ id: String) throws -> LightamerPreset {
                        do {
                            return try presets.loadDocument(id: id)
                        } catch PresetError.notFound {
                            throw McpToolError.unknownPreset("no preset with id '\(id)'")
                        } catch PresetError.unreadableFile {
                            // A missing FILE at the id-addressed path IS the
                            // unknown-preset face (the store only throws
                            // unreadableFile for absent/locked files here).
                            throw McpToolError.unknownPreset("no preset with id '\(id)'")
                        } catch {
                            throw McpToolError.internalError("\(error)")
                        }
                    }
                    let docA = try load(idA)
                    let docB = try load(idB)
                    func keys(_ doc: LightamerPreset) -> [String: Data] {
                        var map: [String: Data] = [:]
                        for instance in doc.instances {
                            map["\(instance.opName)#\(instance.multiPriority)"] =
                                instance.paramsData
                        }
                        return map
                    }
                    let a = keys(docA), b = keys(docB)
                    let onlyInA = a.keys.filter { b[$0] == nil }.sorted()
                    let onlyInB = b.keys.filter { a[$0] == nil }.sorted()
                    let differing = a.keys.filter { key in
                        guard let other = b[key] else { return false }
                        return a[key] != other
                    }.sorted()
                    func strings(_ values: [String]) -> McpJSON {
                        .array(values.map { .string($0) })
                    }
                    return .text(
                        McpJSONSerialization.text(from: .object([
                            "onlyInA": strings(onlyInA),
                            "onlyInB": strings(onlyInB),
                            "differing": strings(differing),
                        ])))
                }
            })
    }


}
