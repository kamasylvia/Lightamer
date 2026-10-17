import CoreGraphics
import CoreImage
import CoreText
import Foundation
import LightamerCore
import Vision

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

    /// M6-1-01 T7 (KD-5, OQ-5): the project-lock probe — consulted after
    /// `requireMembers` on the write-five and the apply_preset frame (the
    /// metadata face's no-live-judge asymmetry, D-8, stays). nil (the
    /// default) = no gate — every existing construction zero-diff.
    var projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)?

    init(
        store: @escaping @Sendable () async -> SessionIndexStore? = { nil },
        sessionRoot: @escaping @Sendable () async -> URL? = { nil },
        metadata: @escaping @Sendable () async -> MetadataService? = { nil },
        sidecarWriter: @escaping @Sendable () async -> BatchSidecarWriter? = { nil },
        presets: @escaping @Sendable () async -> PresetsStore? = { nil },
        liveRelPaths: @escaping @Sendable () async -> Set<String> = { [] },
        thumbnailProvider: @escaping @Sendable () async -> SessionThumbnailProvider? = { nil },
        decodeImage: @escaping @Sendable (URL) async throws -> CGImage,
        renderGate: McpRenderGate = McpRenderGate(),
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil
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
        self.projectWriteProbe = projectWriteProbe
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

/// The inline-image budget table (research §RQ-14-8, probe-verified) —
    /// ONE constants site for the Phase 14 image tools (the plan's shared
    /// seam: 14-2's render_preview consumes the renderPreview row; the
    /// budget tests assert every number verbatim, so drifting a value here
    /// turns the suite red by construction).
enum McpImageBudget {
        // render_preview (14-2 half — constants live HERE).
        static let renderPreviewLongEdge = 1024
        static let renderPreviewQuality = 85
        static let renderPreviewMaxLongEdge = 2048
        static let renderPreviewMaxQuality = 90
        // get_thumbnails.
        static let thumbnailsMaxPerRequest = 20
        // get_contact_sheet.
        static let contactSheetCellSize = 256
        static let contactSheetQuality = 80
        static let contactSheetMaxCols = 6
        static let contactSheetMaxRows = 5
        /// cells × rows ≤ 30 (6×5).
        static let contactSheetMaxCells = contactSheetMaxCols * contactSheetMaxRows
        static let contactSheetCaptionHeight = 24
        /// The single-composite base64 ceiling.
        static let contactSheetMaxBase64Bytes = 2_000_000
        // get_detail_crop.
        static let detailCropLongEdge = 1024
        static let detailCropQuality = 85
        static let detailCropMaxLongEdge = 1536
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
        await registerImageTrio(on: registry, context: context)
        await registerBurstAndFaces(on: registry, context: context)
    }

    // MARK: - list_photos (§A #5)

    private static func registerListPhotos(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "list_photos",
                description: String(localized: "mcp_tool_desc_list_photos", defaultValue: String.LocalizationValue(
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
                    + "coordinate system get_detail_crop ROIs are validated against.")),
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
                    description: String(localized: "mcp_tool_desc_write_metadata", defaultValue: String.LocalizationValue(
                                            "Write metadata on photos of the CURRENTLY OPEN Lightamer "
                            + "session (batch relPaths). One bulk change = one "
                            + "transaction; the write lands in the sidecar truth AND "
                            + "the session index (the GUI grid/filter face reads the "
                            + "same index). MODIFIES session metadata only — never "
                            + "pixels, never file delete/move.")),
                    inputSchemaJSON: schema,
                    destructiveHint: true),
                requiresWriter: true,
                // M7-5-01 (D-M7-5-3): ONE gate site covers the metadata
                // write face's five tools (set_rating/set_flag/
                // set_color_label/append_note/set_keywords ride this
                // helper — never split into separate registers).
                requiresControl: true,
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
                        // M6-1-01 (KD-5/OQ-5): the project-lock probe after
                        // membership (the frame-wide insertion — all five
                        // tools inherit it; nil = no gate).
                        try await EditingToolset.rejectIfProjectReadOnly(
                            context.projectWriteProbe)
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
                description: String(localized: "mcp_tool_desc_list_presets", defaultValue: String.LocalizationValue(
                                    "List the app-level Lightamer presets (develop = adjustment "
                        + "recipes; export = output recipes). Filter by `kind` or "
                        + "omit it for all.")),
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
                description: String(localized: "mcp_tool_desc_apply_preset", defaultValue: String.LocalizationValue(
                                    "Apply a develop preset to photos of the CURRENTLY OPEN Lightamer "
                        + "session (apply = paste semantics; mode 'merge' appends onto "
                        + "each target's history, 'overwrite' resets to the preset). "
                        + "Photos open in the GUI editor are SKIPPED and reported in "
                        + "skippedRelPaths (ask the user to close them there or pick "
                        + "other photos). Export-kind presets cannot be applied here.")),
                inputSchemaJSON:
                    #"{"type":"object","required":["presetID","relPaths"],"properties":{"presetID":{"type":"string"},"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"mode":{"enum":["overwrite","merge"],"description":"Paste mode (default merge)"},"selection":{"type":"array","description":"Partial-apply subset of instances","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer"},"multiName":{"type":"string"}},"required":["opName","multiPriority","multiName"]}}}}"#,
                destructiveHint: true),
            requiresWriter: true,
            requiresControl: true,
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
                    // M6-1-01 (KD-5/OQ-5): the preset-trio's write member
                    // probe (after membership; list_presets stays probe-free).
                    try await EditingToolset.rejectIfProjectReadOnly(
                        context.projectWriteProbe)
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
                description: String(localized: "mcp_tool_desc_diff_presets", defaultValue: String.LocalizationValue(
                                    "Diff two presets by instance key (opName + multiPriority): "
                        + "which instances exist only in A, only in B, or in both "
                        + "with different parameters.")),
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

    // MARK: - Image trio (§A #6-8) + the base64 budget constants

        private static func registerImageTrio(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        // §A #6 get_thumbnails
        await registry.register(
            McpToolDescriptor(
                name: "get_thumbnails",
                description: String(localized: "mcp_tool_desc_get_thumbnails", defaultValue: String.LocalizationValue(
                                    "Fetch INLINE thumbnails for up to 20 photos of the CURRENTLY "
                        + "OPEN Lightamer session. The tier follows the browser "
                        + "pipeline: unedited photos serve the RAW's embedded preview, "
                        + "edited photos serve the rendered cache. A stale row returns "
                        + "its cached image with stale:true; pass regenerate:true to "
                        + "re-render that one image first (blocking). The payload is a "
                        + "JSON manifest (relPath, stale, missing, byteLength, index) "
                        + "followed by one JPEG image block per non-missing photo, in "
                        + "order.")),
                inputSchemaJSON:
                    #"{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"regenerate":{"type":"boolean","description":"Re-render stale thumbnails before returning (default false — stale rows are only marked)"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.thumbnailsAndContact,
                    McpToolError.internalError("get_thumbnails timed out")
                ) {
                    let relPaths = try requireRelPaths(
                        arguments, max: McpImageBudget.thumbnailsMaxPerRequest)
                    var regenerate = false
                    if case .bool(let flag) = arguments["regenerate"] ?? .null {
                        regenerate = flag
                    }
                    let (store, root) = try await requireSession(context)
                    try await requireMembers(relPaths, store: store)
                    let disk = ThumbnailDiskStore(sessionRoot: root)
                    var manifest: [McpJSON] = []
                    var images: [McpToolOutput.Content] = []
                    for (index, relPath) in relPaths.enumerated() {
                        var row = try await store.fetchRow(relPath: relPath)
                        var stale = row?.thumbState
                            == SessionIndexSchema.ThumbState.stale.rawValue
                        // The regenerate leg rides the provider's OWN queue
                        // route (the L031 red line: no new command queue, no
                        // private render path — the browser pipeline rerun).
                        if regenerate, stale, row != nil {
                            if let provider = await context.thumbnailProvider() {
                                _ = await provider.thumbnail(for: relPath, visible: true)
                                row = try await store.fetchRow(relPath: relPath)
                                stale = row?.thumbState
                                    == SessionIndexSchema.ThumbState.stale.rawValue
                            } else {
                                throw McpToolError.internalError(
                                    "regenerate requested but this host has no "
                                        + "thumbnail provider wired")
                            }
                        }
                        guard let currentRow = row else {
                            manifest.append(.object([
                                "relPath": .string(relPath), "missing": .bool(true),
                                "index": .int(index),
                            ]))
                            continue
                        }
                        if let read = readThumbnail(
                            row: currentRow, root: root, disk: disk)
                        {
                            manifest.append(.object([
                                "relPath": .string(relPath),
                                "stale": .bool(stale),
                                "missing": .bool(false),
                                "byteLength": .int(read.bytes.count),
                                "index": .int(index),
                            ]))
                            images.append(
                                .imageBase64(
                                    read.bytes.base64EncodedString(),
                                    mimeType: "image/jpeg"))
                        } else {
                            manifest.append(.object([
                                "relPath": .string(relPath),
                                "missing": .bool(true),
                                "index": .int(index),
                            ]))
                        }
                    }
                    return McpToolOutput(
                        [.text(McpJSONSerialization.text(from: .object([
                            "results": .array(manifest),
                        ])))] + images)
                }
            })

        // §A #7 get_contact_sheet — the pure-CG composite (no Metal touch).
        await registry.register(
            McpToolDescriptor(
                name: "get_contact_sheet",
                description: String(localized: "mcp_tool_desc_get_contact_sheet", defaultValue: String.LocalizationValue(
                                    "Render ONE composite contact-sheet JPEG for photos of the "
                        + "CURRENTLY OPEN Lightamer session: a cols×rows grid (max "
                        + "6×5=30 cells, 256px cells) with a 24px caption bar per cell "
                        + "(filename + rating stars + a pick/reject color bar). "
                        + "Provide exactly ONE of relPaths (explicit list) or filter "
                        + "(a FilterPredicateGroup; rows in sort order). Missing "
                        + "thumbnails render as placeholder cells.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":30},"filter":{"type":"object","description":"FilterPredicateGroup JSON (same shape as list_photos.filter)"},"sort":{"type":"object","description":"Row order when filter is used (same shape as list_photos.sort)"},"cols":{"type":"integer","minimum":1,"maximum":6},"rows":{"type":"integer","minimum":1,"maximum":5}},"oneOf":[{"required":["relPaths"]},{"required":["filter"]}]}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.thumbnailsAndContact,
                    McpToolError.internalError("get_contact_sheet timed out")
                ) {
                    try await context.renderGate.withRenderGate {
                        try await contactSheet(arguments, context: context)
                    }
                }
            })

        // §A #8 get_detail_crop
        await registry.register(
            McpToolDescriptor(
                name: "get_detail_crop",
                description: String(localized: "mcp_tool_desc_get_detail_crop", defaultValue: String.LocalizationValue(
                                    "Crop ONE photo of the CURRENTLY OPEN Lightamer session and "
                        + "return an inline JPEG. `roi` is {x, y, w, h} in the photo's "
                        + "DECODED pixel coordinates (the same coordinate face "
                        + "list_photos' orientation/width/height columns report; "
                        + "origin top-left). Output is downscaled to longEdge "
                        + "(default 1024, max 1536, q85). Reads the photo's pixels "
                        + "(RAW decode) — it does NOT reflect saved edits; use "
                        + "render_preview for the edited look. Face ROIs come from "
                        + "get_face_regions.")),
                inputSchemaJSON:
                    #"{"type":"object","required":["relPath","roi"],"properties":{"relPath":{"type":"string"},"roi":{"type":"object","properties":{"x":{"type":"integer","minimum":0},"y":{"type":"integer","minimum":0},"w":{"type":"integer","exclusiveMinimum":0},"h":{"type":"integer","exclusiveMinimum":0}},"required":["x","y","w","h"]},"longEdge":{"type":"integer","minimum":64,"maximum":1536,"description":"Output long edge (default 1024)"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.renderAndCrop,
                    McpToolError.renderTimeout("get_detail_crop timed out")
                ) {
                    try await context.renderGate.withRenderGate {
                        try await detailCrop(arguments, context: context)
                    }
                }
            })
    }

    /// The dual-tier READ (no production): tier-B rows read the rendered
    /// disk cache (raw JPEG bytes passthrough); tier-A rows read the RAW's
    /// embedded preview (re-encoded q85). The tier follows the 09-03
    /// appointment ruling (has_edits ONLY + the stale-regen clause).
    private static func readThumbnail(
        row: SessionIndexRow, root: URL, disk: ThumbnailDiskStore
    ) -> (bytes: Data, width: Int, height: Int)? {
        let tier = SessionThumbnailProvider.tier(forRow: row)
        if tier == .rendered {
            guard let image = disk.read(relPath: row.path) else { return nil }
            guard let bytes = try? Data(
                contentsOf: disk.fileURL(forRelPath: row.path))
            else { return nil }
            return (bytes, image.width, image.height)
        }
        let url = root.appendingPathComponent(row.path)
        guard let image = SessionThumbnailProvider.embeddedPreview(url: url),
            let bytes = try? ThumbnailDiskStore.jpegData(from: image)
        else { return nil }
        return (bytes, image.width, image.height)
    }

    static func contactSheet(
        _ arguments: [String: McpJSON], context: McpCullingContext
    ) async throws -> McpToolOutput {
        let (store, root) = try await requireSession(context)
        let cols = arguments["cols"]?.intValue ?? McpImageBudget.contactSheetMaxCols
        let rowsArg = arguments["rows"]?.intValue ?? McpImageBudget.contactSheetMaxRows
        guard (1...McpImageBudget.contactSheetMaxCols).contains(cols),
            (1...McpImageBudget.contactSheetMaxRows).contains(rowsArg)
        else {
            throw McpToolError.invalidParams(
                "cols must be 1...\(McpImageBudget.contactSheetMaxCols), rows "
                    + "1...\(McpImageBudget.contactSheetMaxRows)")
        }
        let cell = McpImageBudget.contactSheetCellSize
        let maxCells = cols * rowsArg
        guard maxCells <= McpImageBudget.contactSheetMaxCells else {
            throw McpToolError.invalidParams(
                "the grid is capped at \(McpImageBudget.contactSheetMaxCells) cells")
        }
        let hasPaths = !(arguments["relPaths"]?.isNull ?? true)
            && arguments["relPaths"] != nil
        let hasFilter = !(arguments["filter"]?.isNull ?? true)
            && arguments["filter"] != nil
        guard hasPaths != hasFilter else {
            throw McpToolError.invalidParams(
                "provide exactly ONE of relPaths or filter")
        }
        var rows: [SessionIndexRow]
        if hasPaths {
            let relPaths = try requireRelPaths(arguments, max: maxCells)
            try await requireMembers(relPaths, store: store)
            rows = []
            for relPath in relPaths {
                if let row = try await store.fetchRow(relPath: relPath) {
                    rows.append(row)
                }
            }
        } else {
            let filter = try McpPhotoProjection.decodeFilter(arguments)
            let sort = try McpPhotoProjection.decodeSort(arguments)
            rows = try await store.query(
                groups: filter.map { [$0] } ?? [], sort: sort, limit: maxCells)
        }
        let disk = ThumbnailDiskStore(sessionRoot: root)
        var images: [CGImage?] = []
        for row in rows {
            images.append(readThumbnailImage(row: row, root: root, disk: disk))
        }
        let sheet = try Self.drawContactSheet(
            cells: images, rows: rows,
            cols: cols, rowsCount: rowsArg, cell: cell,
            captionHeight: McpImageBudget.contactSheetCaptionHeight)
        let jpeg = try Self.jpegData(from: sheet, quality: Double(McpImageBudget.contactSheetQuality) / 100)
        let base64 = jpeg.base64EncodedString()
        guard base64.utf8.count <= McpImageBudget.contactSheetMaxBase64Bytes else {
            throw McpToolError.renderFailed(
                "contact sheet exceeds the \(McpImageBudget.contactSheetMaxBase64Bytes) "
                    + "byte base64 budget — shrink the grid")
        }
        let manifest = McpJSON.object([
            "cols": .int(cols),
            "rows": .int(rowsArg),
            "cells": .int(rows.count),
            "width": .int(sheet.width),
            "height": .int(sheet.height),
            "byteLength": .int(base64.utf8.count),
        ])
        return McpToolOutput([
            .text(McpJSONSerialization.text(from: manifest)),
            .imageBase64(base64, mimeType: "image/jpeg"),
        ])
    }

    private static func readThumbnailImage(
        row: SessionIndexRow, root: URL, disk: ThumbnailDiskStore
    ) -> CGImage? {
        let tier = SessionThumbnailProvider.tier(forRow: row)
        if tier == .rendered {
            return disk.read(relPath: row.path)
        }
        return SessionThumbnailProvider.embeddedPreview(
            url: root.appendingPathComponent(row.path))
    }

    /// The pure CoreGraphics/CoreText composite: cells scaled aspect-fit on
    /// a dark ground + a 24px caption (filename, rating stars, pick/reject
    /// color bar). NO Metal anywhere.
    static func drawContactSheet(
        cells: [CGImage?], rows: [SessionIndexRow],
        cols: Int, rowsCount: Int, cell: Int, captionHeight: Int
    ) throws -> CGImage {
        let width = cols * cell
        let height = rowsCount * (cell + captionHeight)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw McpToolError.renderFailed("contact sheet CGContext failed")
        }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let starFont = CTFontCreateUIFontForLanguage(.system, 12, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for (index, image) in cells.enumerated() {
            let gridCol = index % cols
            let gridRow = index / cols
            // CG origin is bottom-left; row 0 renders at the TOP.
            let bandHeight = cell + captionHeight
            let cellOrigin = CGPoint(
                x: CGFloat(gridCol * cell),
                y: CGFloat(height - (gridRow + 1) * bandHeight + captionHeight))
            let cellRect = CGRect(origin: cellOrigin, size: CGSize(width: cell, height: cell))
            if let image {
                // Aspect-fit inside the cell.
                let scale = min(
                    cellRect.width / CGFloat(image.width),
                    cellRect.height / CGFloat(image.height))
                let drawW = CGFloat(image.width) * scale
                let drawH = CGFloat(image.height) * scale
                let drawRect = CGRect(
                    x: cellRect.midX - drawW / 2, y: cellRect.midY - drawH / 2,
                    width: drawW, height: drawH)
                context.draw(image, in: drawRect)
            } else {
                context.setFillColor(CGColor(gray: 0.2, alpha: 1))
                context.fill(cellRect)
            }
            // ── The caption bar ──
            let captionRect = CGRect(
                x: cellOrigin.x, y: cellOrigin.y - CGFloat(captionHeight),
                width: CGFloat(cell), height: CGFloat(captionHeight))
            context.setFillColor(CGColor(gray: 0.08, alpha: 1))
            context.fill(captionRect)

            let row = index < rows.count ? rows[index] : nil
            // The flag color bar (1 pick = green, 2 reject = red).
            if let flag = row?.flag, flag == 1 || flag == 2 {
                context.setFillColor(
                    flag == 1 ? CGColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
                        : CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
                context.fill(CGRect(
                    x: captionRect.minX + 2, y: captionRect.minY + 4,
                    width: 8, height: CGFloat(captionHeight - 8)))
            }
            // Filename + rating stars via CoreText (CJK-safe cascade).
            let filename = row?.filename ?? "?"
            let stars = row?.rating.map { rating in String(repeating: "★", count: Int(rating)) }
            let text = stars.map { "\(filename)  \($0)" } ?? filename
            guard let attributed = CFAttributedStringCreate(
                kCFAllocatorDefault, text as CFString,
                [
                    kCTFontAttributeName: starFont,
                    kCTForegroundColorAttributeName: CGColor(gray: 0.95, alpha: 1),
                ] as CFDictionary)
            else {
                throw McpToolError.renderFailed("caption attributed string failed")
            }
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(
                x: captionRect.minX + 14, y: captionRect.minY + 5)
            CTLineDraw(line, context)
        }
        guard let output = context.makeImage() else {
            throw McpToolError.renderFailed("contact sheet makeImage failed")
        }
        return output
    }

    /// JPEG encode with an explicit quality (the ImageIO face; the disk
    /// store's fixed q85 does not fit the contact-sheet q80 row).
    static func jpegData(from image: CGImage, quality: Double) throws -> Data {
        let mutable = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutable, "public.jpeg" as CFString, 1, nil)
        else {
            throw McpToolError.renderFailed("CGImageDestination(jpeg) failed")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw McpToolError.renderFailed("CGImageDestinationFinalize failed")
        }
        return mutable as Data
    }

    static func detailCrop(
        _ arguments: [String: McpJSON], context: McpCullingContext
    ) async throws -> McpToolOutput {
        guard let relPath = arguments["relPath"]?.stringValue else {
            throw McpToolError.invalidParams("relPath is required")
        }
        guard let roiArg = arguments["roi"]?.objectValue else {
            throw McpToolError.invalidParams("roi must be an object {x, y, w, h}")
        }
        guard let x = roiArg["x"]?.intValue, let y = roiArg["y"]?.intValue,
            let w = roiArg["w"]?.intValue, let h = roiArg["h"]?.intValue,
            x >= 0, y >= 0, w > 0, h > 0
        else {
            throw McpToolError.invalidParams(
                "roi needs non-negative x/y and positive w/h integers")
        }
        var longEdge = McpImageBudget.detailCropLongEdge
        if let requested = arguments["longEdge"]?.intValue {
            guard (64...McpImageBudget.detailCropMaxLongEdge).contains(requested) else {
                throw McpToolError.invalidParams(
                    "longEdge must be 64...\(McpImageBudget.detailCropMaxLongEdge)")
            }
            longEdge = requested
        }
        let (store, root) = try await requireSession(context)
        try await requireMembers([relPath], store: store)
        let image = try await context.decodeImage(root.appendingPathComponent(relPath))
        // The bounds check consumes the DECODED extent (the same pixel face
        // list_photos' geometry columns report).
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let roi = CGRect(x: x, y: y, width: w, height: h)
        guard bounds.contains(roi) else {
            throw McpToolError.roiOutOfBounds(
                "roi \(roi) is outside the \(image.width)×\(image.height) "
                    + "decoded frame of '\(relPath)'")
        }
        guard let cropped = image.cropping(to: roi) else {
            throw McpToolError.renderFailed("cropping failed for '\(relPath)'")
        }
        // Downsample to the long edge (no upscale).
        let scale = min(
            Double(longEdge) / Double(max(cropped.width, cropped.height)), 1.0)
        let targetW = max(Int((Double(cropped.width) * scale).rounded()), 1)
        let targetH = max(Int((Double(cropped.height) * scale).rounded()), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context2d = CGContext(
            data: nil, width: targetW, height: targetH, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw McpToolError.renderFailed("crop CGContext failed")
        }
        context2d.interpolationQuality = .high
        context2d.draw(
            cropped, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let scaled = context2d.makeImage() else {
            throw McpToolError.renderFailed("crop makeImage failed")
        }
        let jpeg = try jpegData(
            from: scaled, quality: Double(McpImageBudget.detailCropQuality) / 100)
        let base64 = jpeg.base64EncodedString()
        let manifest = McpJSON.object([
            "relPath": .string(relPath),
            "roi": .object([
                "x": .int(x), "y": .int(y), "w": .int(w), "h": .int(h),
            ]),
            "outputWidth": .int(scaled.width),
            "outputHeight": .int(scaled.height),
            "byteLength": .int(base64.utf8.count),
        ])
        return McpToolOutput([
            .text(McpJSONSerialization.text(from: manifest)),
            .imageBase64(base64, mimeType: "image/jpeg"),
        ])
    }

    // MARK: - Burst + faces (§A #9-10)

    /// Vision normalized bottom-left → decoded pixel top-left (the ONE
    /// conversion face; unit-tested per value).
    static func facePixelRect(
        boundingBox: CGRect, imageWidth: Int, imageHeight: Int
    ) -> (x: Int, y: Int, w: Int, h: Int) {
        let x = Int((boundingBox.origin.x * CGFloat(imageWidth)).rounded())
        let y = Int(
            ((1 - boundingBox.origin.y - boundingBox.height)
                * CGFloat(imageHeight)).rounded())
        let w = Int((boundingBox.width * CGFloat(imageWidth)).rounded())
        let h = Int((boundingBox.height * CGFloat(imageHeight)).rounded())
        return (x, y, w, h)
    }

    /// A landmark's face-box-relative normalized point → pixel top-left
    /// (the FaceLandmarkSet.init conversion shape, pixel output).
    static func landmarkPixelPoint(
        point: CGPoint, faceBox: CGRect, imageWidth: Int, imageHeight: Int
    ) -> (x: Int, y: Int) {
        let nx = faceBox.origin.x + point.x * faceBox.width
        let ny = 1 - (faceBox.origin.y + point.y * faceBox.height)
        return (
            Int((nx * CGFloat(imageWidth)).rounded()),
            Int((ny * CGFloat(imageHeight)).rounded())
        )
    }

    private static func registerBurstAndFaces(
        on registry: McpToolRegistry, context: McpCullingContext
    ) async {
        // §A #9 list_bursts — pure query-layer clustering (万张级 <1ms,
        // ZERO pixel rendering).
        await registry.register(
            McpToolDescriptor(
                name: "list_bursts",
                description: String(localized: "mcp_tool_desc_list_bursts", defaultValue: String.LocalizationValue(
                                    "Group the CURRENTLY OPEN Lightamer session's photos into "
                        + "burst sequences: consecutive shots within gapSeconds "
                        + "(default 2.0) taken with the same camera_model form one "
                        + "burst; single photos land in singles. Cross-day gaps "
                        + "naturally split. Rows carry capture_date/filename/relPath "
                        + "— filter the members with list_photos afterwards (the "
                        + "relPaths are session keys). Pure index query: no pixels "
                        + "are decoded or rendered.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"gapSeconds":{"type":"number","exclusiveMinimum":0,"description":"Max gap between consecutive shots of one burst (default 2.0)"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("list_bursts timed out")
                ) {
                    var gapSeconds = 2.0
                    if let gap = arguments["gapSeconds"]?.doubleValue {
                        guard gap > 0 else {
                            throw McpToolError.invalidParams(
                                "gapSeconds must be > 0")
                        }
                        gapSeconds = gap
                    }
                    let (store, _) = try await requireSession(context)
                    // One ordered scan over the SAME query face (the same
                    // actor handle — zero new locking; no FilterSQL
                    // predicates: burst grouping is a dedicated read).
                    let rows = try await store.query(
                        groups: [],
                        sort: FilterSort(key: .captureDate, ascending: true),
                        limit: nil)
                    // In-memory O(n) clustering. Rows with a NULL
                    // capture_date cannot cluster — honest singles.
                    struct Burst {
                        var id: String
                        var camera: String?
                        var lastDate: Double
                        var members: [McpJSON]
                    }
                    var bursts: [Burst] = []
                    var singles: [String] = []
                    for row in rows {
                        guard let date = row.captureDate else {
                            singles.append(row.path)
                            continue
                        }
                        let camera = row.cameraModel
                        // Same burst = same camera class AND within the gap.
                        if let last = bursts.last,
                            last.camera == camera,
                            date - last.lastDate <= gapSeconds
                        {
                            bursts[bursts.count - 1].lastDate = date
                            bursts[bursts.count - 1].members.append(.object([
                                "relPath": .string(row.path),
                                "filename": row.filename.map { .string($0) } ?? .null,
                                "captureDate": .double(date),
                            ]))
                        } else {
                            // L013: the burst id is the FIRST member's path
                            // hashed with the cross-process StableHash,
                            // spelled as the full DECIMAL string.
                            let id = "burst-\(StableHash.hash(row.path))"
                            bursts.append(Burst(
                                id: id, camera: camera, lastDate: date,
                                members: [.object([
                                    "relPath": .string(row.path),
                                    "filename": row.filename.map { .string($0) } ?? .null,
                                    "captureDate": .double(date),
                                ])]))
                        }
                    }
                    var burstRows: [McpJSON] = []
                    for var burst in bursts {
                        if burst.members.count < 2 {
                            guard case .object(let only) = burst.members[0],
                                case .string(let path) = only["relPath"]
                            else { continue }
                            singles.append(path)
                            continue
                        }
                        // Drop the id from the per-burst payload face? No —
                        // id stays; members keep their objects.
                        burstRows.append(.object([
                            "id": .string(burst.id),
                            "count": .int(burst.members.count),
                            "members": .array(burst.members),
                        ]))
                    }
                    let payload = McpJSON.object([
                        "bursts": .array(burstRows),
                        "singles": .array(singles.sorted().map { .string($0) }),
                    ])
                    return .text(McpJSONSerialization.text(from: payload))
                }
            })

        // §A #10 get_face_regions — VNDetectFaceLandmarksRequest direct
        // (the SkinSmooth hull orchestration is NOT consumed); per-request
        // no cache (~4ms/image measured), request-internal serial.
        await registry.register(
            McpToolDescriptor(
                name: "get_face_regions",
                description: String(localized: "mcp_tool_desc_get_face_regions", defaultValue: String.LocalizationValue(
                                    "Detect faces in up to 20 photos of the CURRENTLY OPEN "
                        + "Lightamer session. Returns each photo's face bounding "
                        + "boxes in DECODED PIXEL coordinates (the same face the "
                        + "get_detail_crop ROI consumes; origin top-left) — an EMPTY "
                        + "array means no face was found, not an error. Optional "
                        + "landmark point sets (same pixel space). Vision runs "
                        + "per-request with no caching (~4ms per image); requests "
                        + "are serialized internally.")),
                inputSchemaJSON:
                    #"{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"includeLandmarks":{"type":"boolean","description":"Also return per-face landmark point sets (default false)"}}}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await withTimeout(
                    // Plan 14-4: the 20s image slot, not the 10s list slot —
                    // the decode leg (RAW) rides this handler (the 14-3
                    // acceptance note: 10s is tight for large RAWs).
                    McpTimeouts.thumbnailsAndContact,
                    McpToolError.internalError("get_face_regions timed out")
                ) {
                    let relPaths = try requireRelPaths(arguments, max: 20)
                    var includeLandmarks = false
                    if case .bool(let flag) = arguments["includeLandmarks"] ?? .null {
                        includeLandmarks = flag
                    }
                    let (store, root) = try await requireSession(context)
                    try await requireMembers(relPaths, store: store)
                    var results: [McpJSON] = []
                    for relPath in relPaths {
                        let image = try await context.decodeImage(
                            root.appendingPathComponent(relPath))
                        let request = VNDetectFaceLandmarksRequest()
                        let handler = VNImageRequestHandler(
                            cgImage: image, options: [:])
                        do {
                            try handler.perform([request])
                        } catch {
                            throw McpToolError.internalError(
                                "face detection failed for '\(relPath)': \(error)")
                        }
                        var faces: [McpJSON] = []
                        for observation in request.results ?? [] {
                            let box = observation.boundingBox
                            let pixel = Self.facePixelRect(
                                boundingBox: box, imageWidth: image.width,
                                imageHeight: image.height)
                            var face: [String: McpJSON] = [
                                "x": .int(pixel.x), "y": .int(pixel.y),
                                "w": .int(pixel.w), "h": .int(pixel.h),
                            ]
                            if includeLandmarks, let set = observation.landmarks {
                                var points: [McpJSON] = []
                                let bb = box
                                func add(_ region: VNFaceLandmarkRegion2D?) {
                                    guard let region else { return }
                                    for index in 0..<region.pointCount {
                                        let p = region.normalizedPoints[index]
                                        let pt = Self.landmarkPixelPoint(
                                            point: p, faceBox: bb,
                                            imageWidth: image.width,
                                            imageHeight: image.height)
                                        points.append(.object([
                                            "x": .int(pt.x), "y": .int(pt.y),
                                        ]))
                                    }
                                }
                                add(set.faceContour)
                                add(set.leftEye)
                                add(set.rightEye)
                                add(set.leftEyebrow)
                                add(set.rightEyebrow)
                                add(set.outerLips)
                                add(set.nose)
                                face["landmarks"] = .array(points)
                            }
                            faces.append(.object(face))
                        }
                        results.append(.object([
                            "relPath": .string(relPath),
                            "faces": .array(faces),
                        ]))
                    }
                    return .text(McpJSONSerialization.text(from: .object([
                        "results": .array(results),
                    ])))
                }
            })
    }
}
