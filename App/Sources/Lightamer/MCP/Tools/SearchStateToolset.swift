import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M7-2-01: the search/state domain toolset (3 read-only tools —
// `search_photos` / `get_history` / `get_state`, REQUIREMENTS MCP2-01..03;
// the Alcedo anchors are search.query / editor.history / state.get).
//
// DOMAIN BOUNDARY (D-M7-2-1): the retrieval face rides the OPEN LIBRARY
// (.lalb project) — the same single sources the GUI three-segment search
// rides (ExifSearchParser → LibraryQueries.searchPage + searchNullTail /
// SemanticEngine / AIDescriptionService.imageIDs; FilterSQL's "no second
// SQL face" red line covers every route here). `list_photos` addresses the
// open SESSION instead; the two never mix (the tool description says so in
// one sentence).
//
// READ-ONLY DISCIPLINE (the plan red line): every tool registers with the
// DEFAULT writer requirement (never spelled at the call site — the grep
// machine check keys on the absence) and carries the read-only hint. The
// writer gate, the write-call counter and the project probe are
// structurally untouched by this domain (the registry consults them only
// inside the writer branch); get_state reads the probe/count faces as DATA.
//
// SEAM SHAPE (D-M7-2-9): every data face is a provider closure on
// `McpSearchStateContext` — hosts assemble, tools never construct state.
// All seams are optional (default nil): a host that cannot see a face
// (headless, read-only arm before the store opens) gets the typed honest
// errors (`notSessionMember` / `modelUnavailable`), never a crash, never a
// silent empty result. The match_color static box is deliberately NOT
// reused (a single-tool special case, not a shared singleton).
// ─────────────────────────────────────────────────────────────────────────────

/// The get_state live-face snapshot carrier (D-M7-2-8): the workspace /
/// editor / tasks object faces the host closure assembles under a
/// MainActor hop (the @Observable reads stay inside the closure — the
/// handler never touches an @Observable type, the F-6 grep pins it).
/// `nil` field = the host cannot see that face → the tool renders JSON
/// null (the honest absent face).
public struct McpSearchStateLiveSnapshot: Sendable, Equatable {
    public var workspace: McpJSON?
    public var editor: McpJSON?
    public var tasks: McpJSON?

    public init(
        workspace: McpJSON? = nil, editor: McpJSON? = nil, tasks: McpJSON? = nil
    ) {
        self.workspace = workspace
        self.editor = editor
        self.tasks = tasks
    }
}

/// The host-injected environment for the search/state tools (every seam a
/// provider closure — the 14-1 discipline; all optional, default nil =
/// every existing construction zero-diff).
public struct McpSearchStateContext: Sendable {

    /// The open library's data face (E-1 修法甲: the ProjectFileStore
    /// DIRECTLY — the three route single sources LibraryQueries /
    /// SemanticStore / AIDescriptionService.imageIDs all take one) + the
    /// package URL (the ImageLinker path-kind resolution anchor). nil = no
    /// open project → the typed `notSessionMember`.
    public var library:
        (@Sendable () async -> (store: ProjectFileStore, projectDirectory: URL)?)?

    /// The open session pair (get_history's relPath addressing arm — the
    /// match_color two-form resolution shape). nil = the relPath form
    /// answers `notSessionMember`.
    public var sessionPair:
        (@Sendable () async -> (store: SessionIndexStore, root: URL)?)?

    /// The open package's semantic read face (the CLIP route's scan
    /// target). nil = the route answers `modelUnavailable`.
    public var semanticStore: (@Sendable () async -> SemanticStore?)?

    /// The semantic engine supplier (AIInferenceService.shared
    /// .semanticSearcher() 同源; nil answer = assets absent →
    /// `modelUnavailable`). Supplied per call so a late asset load lands.
    public var semantic:
        (@Sendable () async -> (any SemanticSearching)?)?

    /// The fulltext query seam (AIDescriptionService.imageIDs 同形 —
    /// FTS MATCH → JOIN active=1 → rank-ordered ids). The route requires
    /// the library seam first (no open project = `notSessionMember`).
    public var fulltext:
        (@Sendable (String) async throws -> [Int64])?

    /// The get_state workspace/editor/tasks faces (MainActor hop INSIDE
    /// the closure; nil = those faces render null — the headless honesty).
    public var liveState:
        (@Sendable () async -> McpSearchStateLiveSnapshot?)?

    /// The M6-1 lock verdict probe, read as get_state's control-face DATA
    /// (the SAME closure the write faces gate on — zero new plumbing).
    public var projectWriteProbe:
        (@Sendable () async -> McpProjectLockVerdict)?

    /// The write-call counter face (F-4② 终形): the GUI embedded host
    /// supplies `McpServerController.embeddedWriteCallCount()` 同源; the
    /// headless / read-only faces have no exposed handle → nil = the JSON
    /// null honest face (NO new plumbing — there is no consumer).
    public var writeCallCount: (@Sendable () async -> Int?)?

    public init(
        library: (@Sendable () async -> (
            store: ProjectFileStore, projectDirectory: URL
        )?)? = nil,
        sessionPair: (@Sendable () async -> (
            store: SessionIndexStore, root: URL
        )?)? = nil,
        semanticStore: (@Sendable () async -> SemanticStore?)? = nil,
        semantic: (@Sendable () async -> (any SemanticSearching)?)? = nil,
        fulltext: (@Sendable (String) async throws -> [Int64])? = nil,
        liveState: (@Sendable () async -> McpSearchStateLiveSnapshot?)? = nil,
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil,
        writeCallCount: (@Sendable () async -> Int?)? = nil
    ) {
        self.library = library
        self.sessionPair = sessionPair
        self.semanticStore = semanticStore
        self.semantic = semantic
        self.fulltext = fulltext
        self.liveState = liveState
        self.projectWriteProbe = projectWriteProbe
        self.writeCallCount = writeCallCount
    }
}

enum McpSearchStateToolset {

    // MARK: - Registration (the three read-only tools; grows additively)

    static func registerAll(
        on registry: McpToolRegistry, context: McpSearchStateContext
    ) async {
        await registerSearchPhotos(on: registry, context: context)
        await registerGetHistory(on: registry, context: context)
        await registerGetState(on: registry, context: context)
    }

    private static func registerSearchPhotos(
        on registry: McpToolRegistry, context: McpSearchStateContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "search_photos",
                description: String(
                    localized: "mcp_tool_desc_search_photos",
                    defaultValue: String.LocalizationValue(
                        "Search photos in the OPEN LIBRARY (.lalb project) — "
                            + "`list_photos` addresses the open session instead; "
                            + "the two never mix. Each call evaluates the query "
                            + "against the full library (no layered session filter "
                            + "state). Modes: `exif` (default) parses the query with "
                            + "the same grammar the GUI search box uses — plain words "
                            + "ride the EXIF text index, structured tokens (iso800, "
                            + "f/2.8, 2024-06..2024-08) ride typed columns; `clip` "
                            + "embeds the query with the local CLIP model and returns "
                            + "cosine-scored neighbors (best first); `fulltext` runs "
                            + "the AI-understanding full-text index (caption/tags/"
                            + "scene) in bm25 rank order. Pagination exists ONLY for "
                            + "mode=exif: pass back `nextCursor` as `cursor` (a short "
                            + "page means the end; a cursor is only valid for the "
                            + "same sort it was issued with and only for this tool). "
                            + "`sort` is {key: filename|rating|captureDate|iso|"
                            + "focalLength, ascending} (default filename ascending); "
                            + "cursor/sort are rejected for clip/fulltext (bounded "
                            + "top-K, no paging). Rows carry a narrow projection "
                            + "(imageID, imagePath — a project-relative path-kind "
                            + "form, address results by imageID — filename, dir, "
                            + "captureDate, rating, flag, colorLabel, hasEdits); "
                            + "thumbnails ride get_thumbnails. Errors: "
                            + "notSessionMember (no open project — open a .lalb "
                            + "first), invalidParams (empty query, unrecognized "
                            + "token, bad cursor/sort), modelUnavailable (the "
                            + "semantic model is not ready).")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{},"required":[]}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("search_photos timed out")
                ) {
                    try await searchPhotos(arguments, context: context)
                }
            })
    }

    private static func registerGetHistory(
        on registry: McpToolRegistry, context: McpSearchStateContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "get_history",
                description: String(
                    localized: "mcp_tool_desc_get_history",
                    defaultValue: String.LocalizationValue(
                        "Read the edit history of one image (READ-ONLY — no "
                            + "undo/redo verbs; this face never writes): the "
                            + "non-destructive edit log (param edits, layer-structure "
                            + "edits, paste epochs, document-level display-transform "
                            + "and film edits), the version-list metadata, the active "
                            + "version, and the metadata face (note/keywords/rating/"
                            + "flag/colorLabel). image: a library image id (digits) or "
                            + "an open-session relPath (the match_color addressing). "
                            + "Items default to summary form (id/label/timestamp/kind/"
                            + "layerScope); includeParams=true adds the per-item "
                            + "params. The list is capped at the 500 NEWEST items "
                            + "(itemCount stays the true total — truncation is "
                            + "detectable and the newest end is kept). author is "
                            + "reserved and always null for now. Full version chains "
                            + "(every version's own item list) are not part of this "
                            + "face. Errors: notSessionMember (image not addressable "
                            + "/ no open project), invalidParams.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{},"required":[]}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("get_history timed out")
                ) {
                    try await getHistory(arguments, context: context)
                }
            })
    }

    private static func registerGetState(
        on registry: McpToolRegistry, context: McpSearchStateContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "get_state",
                description: String(
                    localized: "mcp_tool_desc_get_state",
                    defaultValue: String.LocalizationValue(
                        "One-shot snapshot of this server's state, six field "
                            + "groups: project (the open .lalb — path / read-only "
                            + "stance), workspace (the library collection face: "
                            + "filter / selection / current image), editor (the live "
                            + "document: image URL / has-edits), control (the "
                            + "single-writer lock verdict + the write-call count), "
                            + "tasks (the export queue counts) and server (server "
                            + "name/version, host mode, read-only stance). Fields a "
                            + "host cannot see are null (e.g. workspace/editor/tasks "
                            + "on a headless host; project with no --project flag). "
                            + "This is a MOMENTARY snapshot — fields are not "
                            + "guaranteed consistent between calls; the face never "
                            + "writes.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{},"required":[]}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("get_state timed out")
                ) {
                    try await getState(arguments, context: context)
                }
            })
    }

    // MARK: - Bodies (the T2/T3 lands)

    private static func searchPhotos(
        _ arguments: [String: McpJSON], context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        throw McpToolError.internalError(
            "search_photos: the route bodies land in M7-2-01 T2")
    }

    private static func getHistory(
        _ arguments: [String: McpJSON], context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        throw McpToolError.internalError(
            "get_history: the projection body lands in M7-2-01 T3")
    }

    private static func getState(
        _ arguments: [String: McpJSON], context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        throw McpToolError.internalError(
            "get_state: the snapshot body lands in M7-2-01 T3")
    }
}
