import CoreGraphics
import CoreImage
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
}
