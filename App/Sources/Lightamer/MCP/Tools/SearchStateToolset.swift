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

/// The get_state live-face snapshot carrier (D-M7-2-8): the object faces
/// the host closure assembles under a MainActor hop (the @Observable
/// reads stay inside the closure — the handler never touches an
/// @Observable type, the F-6 grep pins it). `nil` field = the host cannot
/// see that face → the tool renders JSON null (the honest absent face).
/// Per plan T3 action 3, the project face ALSO rides this seam (the GUI
/// assembles it from the project-controller state; the headless arms from
/// the arbitration outcome); `server` carries the host-mode and read-only
/// stance the handler cannot self-derive (the identity name/version is
/// the handler's own fallback when the face is absent).
public struct McpSearchStateLiveSnapshot: Sendable, Equatable {
    public var project: McpJSON?
    public var workspace: McpJSON?
    public var editor: McpJSON?
    public var tasks: McpJSON?
    public var server: McpJSON?

    public init(
        project: McpJSON? = nil, workspace: McpJSON? = nil,
        editor: McpJSON? = nil, tasks: McpJSON? = nil,
        server: McpJSON? = nil
    ) {
        self.project = project
        self.workspace = workspace
        self.editor = editor
        self.tasks = tasks
        self.server = server
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

    /// M7-5-01 (D-M7-5-8): the agent control state provider — get_state's
    /// `control.agent` face. nil = the JSON null honest face (the headless
    /// constant rides T4's assembly; the GUI arm MainActor.run-hops into
    /// the coordinator). Additive optional: every existing construction
    /// compiles zero-diff.
    public var agentControl: (@Sendable () async -> McpControlState?)?

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
        writeCallCount: (@Sendable () async -> Int?)? = nil,
        agentControl: (@Sendable () async -> McpControlState?)? = nil
    ) {
        self.library = library
        self.sessionPair = sessionPair
        self.semanticStore = semanticStore
        self.semantic = semantic
        self.fulltext = fulltext
        self.liveState = liveState
        self.projectWriteProbe = projectWriteProbe
        self.writeCallCount = writeCallCount
        self.agentControl = agentControl
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
                    #"{"type":"object","properties":{"query":{"type":"string","minLength":1,"description":"The search query (the EXIF grammar: plain words + structured tokens like iso800, f/2.8, 2024-06..2024-08)"},"mode":{"type":"string","enum":["exif","clip","fulltext"],"default":"exif","description":"The route (default exif)"},"limit":{"type":"integer","minimum":1,"maximum":500,"description":"Rows per call (exif default 200; clip/fulltext caps 256/500)"},"cursor":{"type":"string","description":"Opaque nextCursor token — EXIF mode ONLY (a token is only valid for its issuing sort and this tool)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength, ascending: bool} — EXIF mode ONLY; default filename ascending"}},"required":["query"]}"#,
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
                    #"{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeParams":{"type":"boolean","default":false,"description":"Add the per-item params face"},"limit":{"type":"integer","minimum":1,"maximum":500,"description":"Item cap (default 500); truncation keeps the NEWEST end — position/itemCount stay the true values, so truncation is detectable"}},"required":["image"]}"#,
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

    // MARK: - search_photos (MCP2-01) — the three routes

    /// The EXIF keyset cursor segment (E-2 两段走法 — the LibraryGridModel
    /// Segment twin): `main` walks `searchPage` (non-NULL-key rows, the
    /// row-value seek), `nullTail` walks `searchNullTail` (the NULL tier,
    /// image_path seek). The payload carries its own sort key + direction
    /// (a mismatched reuse is REJECTED, the PhotoProjection 换键失效 rule),
    /// the segment, and — for a main token — the last row's key value (the
    /// row-value seek's first leg). A token WITHOUT the segment field is a
    /// different tool's cursor (list_photos shares the {k,d,p,v} shape)
    /// and is rejected (R-3: a cursor is OUR token, cross-tool acceptance
    /// would be silent semantic confusion).
    struct SearchCursor: Equatable, Sendable {
        enum Segment: String, Sendable {
            case main
            case nullTail
        }

        /// The main segment's key value (JSON-exact kinds only; nil for a
        /// nullTail token — the image_path is the only seek there).
        enum KeyValue: Equatable, Sendable {
            case text(String)
            case int(Int)
            case double(Double)

            var bind: FilterSQLBind {
                switch self {
                case .text(let text): .text(text)
                case .int(let int): .int(Int64(int))
                case .double(let double): .double(double)
                }
            }
        }

        var sortKey: FilterSortKey
        var ascending: Bool
        var imagePath: String
        var segment: Segment
        var keyValue: KeyValue?

        func encode() -> String {
            struct Payload: Codable {
                var k: String
                var d: String
                var p: String
                var v: ValuePayload?
                var s: String
            }
            struct ValuePayload: Codable {
                var kind: String
                var text: String?
                var int: Int?
                var double: Double?
            }
            let value: ValuePayload?
            switch keyValue {
            case .text(let text):
                value = .init(kind: "text", text: text, int: nil, double: nil)
            case .int(let int):
                value = .init(kind: "int", text: nil, int: int, double: nil)
            case .double(let double):
                value = .init(kind: "double", text: nil, int: nil, double: double)
            case nil:
                value = nil
            }
            let payload = Payload(
                k: sortKey.rawValue,
                d: ascending ? "asc" : "desc",
                p: imagePath,
                v: value,
                s: segment.rawValue)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = (try? encoder.encode(payload)) ?? Data()
            return json.base64EncodedString()
        }

        static func decode(_ raw: String) throws -> SearchCursor {
            struct Payload: Codable {
                var k: String
                var d: String
                var p: String
                var v: ValuePayload?
                var s: String?
            }
            struct ValuePayload: Codable {
                var kind: String
                var text: String?
                var int: Int?
                var double: Double?
            }
            guard let outer = Data(base64Encoded: raw),
                let payload = try? JSONDecoder().decode(Payload.self, from: outer),
                let key = FilterSortKey(rawValue: payload.k),
                let segmentRaw = payload.s,
                let segment = Segment(rawValue: segmentRaw)
            else {
                throw McpToolError.invalidParams(
                    "cursor is not a valid search_photos token (a cursor is "
                        + "issued by this tool's previous page — tokens from "
                        + "other tools or hand-built strings are rejected)")
            }
            var value: KeyValue?
            switch payload.v?.kind {
            case "text": value = payload.v?.text.map { KeyValue.text($0) }
            case "int": value = payload.v?.int.map { KeyValue.int($0) }
            case "double": value = payload.v?.double.map { KeyValue.double($0) }
            default: value = nil
            }
            if segment == .main, value == nil {
                // A main token without its key value is garbage (the
                // row-value seek needs both legs).
                throw McpToolError.invalidParams(
                    "cursor is not a valid search_photos token")
            }
            return SearchCursor(
                sortKey: key, ascending: payload.d != "desc",
                imagePath: payload.p, segment: segment, keyValue: value)
        }

        /// The sort-match gate (the 换键/换向失效 negative): the token's
        /// key + direction must equal the REQUEST's effective sort.
        func validate(sort: FilterSort) throws {
            guard sortKey == sort.key, ascending == sort.ascending else {
                throw McpToolError.invalidParams(
                    "cursor was issued for sort \(sortKey.rawValue)/"
                        + "\(ascending ? "asc" : "desc") — pass the same sort "
                        + "or drop the cursor to restart paging")
            }
        }

        /// The main-segment row-value anchor (the seek's both legs).
        var mainAnchor: LibraryPageAnchor? {
            guard segment == .main, let keyValue else { return nil }
            return LibraryPageAnchor(
                keyValue: keyValue.bind, imagePath: imagePath)
        }

        /// The nullTail anchor (built BY HAND — `.anchor(of:key:)` answers
        /// nil for NULL-key rows, that is WHY the tail exists; the key
        /// value is unused, image_path is the only seek — the GUI
        /// advanceTail 形).
        var nullTailAnchor: LibraryPageAnchor {
            LibraryPageAnchor(keyValue: FilterSQLBind.int(nil), imagePath: imagePath)
        }
    }

    /// The typed rejection message for a missing library face.
    static let noOpenProjectMessage =
        "no open project — open a .lalb first"

    /// The search_photos body: EXIF (two-segment keyset walk) / CLIP
    /// (bounded top-K) / fulltext (bm25 rank) — the GUI three-segment
    /// search's exact single sources, nothing re-implemented.
    private static func searchPhotos(
        _ arguments: [String: McpJSON], context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        let query = try requiredString(arguments["query"], name: "query")
        let mode = try decodeMode(arguments["mode"])
        let limit = try decodeLimit(arguments["limit"], mode: mode)
        // 越臂组合 typed 拒 (N-4): cursor/sort are the EXIF arm's paging
        // face — clip/fulltext are bounded top-K, carrying them is a
        // protocol mistake, rejected at BOTH the schema and here.
        if mode != .exif {
            if arguments["cursor"] != nil, arguments["cursor"] != .null {
                throw McpToolError.invalidParams(
                    "cursor only applies to mode=exif (clip/fulltext are "
                        + "bounded top-K, no paging)")
            }
            if arguments["sort"] != nil, arguments["sort"] != .null {
                throw McpToolError.invalidParams(
                    "sort only applies to mode=exif (clip/fulltext return "
                        + "relevance order)")
            }
        }

        // The library face gates ALL routes (they evaluate the OPEN
        // library; nil = the honest no-project shape).
        guard let libraryProvider = context.library,
            let library = await libraryProvider() else {
            throw McpToolError.notSessionMember(noOpenProjectMessage)
        }
        let queries = LibraryQueries(store: library.store)

        switch mode {
        case .exif:
            return try await searchExif(
                query: query, limit: limit, arguments: arguments,
                queries: queries)
        case .clip:
            return try await searchClip(
                query: query, limit: limit, context: context)
        case .fulltext:
            return try await searchFulltext(
                query: query, limit: limit, context: context)
        }
    }

    // MARK: The EXIF route (two-segment walk, GUI 同源)

    private static func searchExif(
        query: String, limit: Int, arguments: [String: McpJSON],
        queries: LibraryQueries
    ) async throws -> McpToolOutput {
        // The parser is the SAME single source the GUI search box rides —
        // typed parser errors carry the offending token (the GUI
        // ErrorFamily's information, verbatim).
        let plan: ExifSearchPlan
        do {
            plan = try ExifSearchParser.parse(query)
        } catch let error as ExifSearchParserError {
            switch error {
            case .unrecognizedToken(let token):
                throw McpToolError.invalidParams(
                    "query token '\(token)' was not recognized — plain words "
                        + "search EXIF text; structured tokens follow the "
                        + "iso/f/aperture/date grammar")
            case .disjointDateRanges:
                throw McpToolError.invalidParams(
                    "the date terms select disjoint ranges — one date window "
                        + "at a time")
            }
        } catch {
            throw McpToolError.invalidParams("query parse failed: \(error)")
        }
        let filter = ExifSearchFilter(
            group: FilterPredicateGroup(rules: []), plan: plan)

        // The sort (default filename asc — the GUI 同源 default; scanEpoch
        // is explicitly rejected: a Session-domain concept, the library
        // `images` table has no such column).
        let sort = try decodeSort(arguments["sort"])
        guard LibraryQueries.sortableKeys.contains(sort.key) else {
            throw McpToolError.invalidParams(
                "sort.key '\(sort.key.rawValue)' is not a library sort key — "
                    + "one of \(LibraryQueries.sortableKeys.map(\.rawValue))")
        }

        // The cursor (segment-carrying; decode → sort-match gate).
        var cursor: SearchCursor?
        if let raw = arguments["cursor"]?.stringValue, !raw.isEmpty {
            let decoded = try SearchCursor.decode(raw)
            try decoded.validate(sort: sort)
            cursor = decoded
        }

        // The two-segment walk (E-2): main = searchPage (the row-value
        // seek over non-NULL keys), tail = searchNullTail (the NULL tier,
        // image_path seek — every library sort key is nullable). The GUI's
        // LibraryGridModel Segment{main, nullTail} 一一对应.
        let page: [LibraryImageRow]
        var nextCursor: String?
        switch cursor?.segment {
        case .main, .none:
            let main = try await queries.searchPage(
                filter: filter, sort: sort,
                anchor: cursor?.mainAnchor, limit: limit)
            (page, nextCursor) = advanceMain(
                rows: main, limit: limit, anchored: cursor != nil, sort: sort)
        case .nullTail:
            let tail = try await queries.searchNullTail(
                filter: filter, sort: sort,
                anchor: cursor.map { $0.nullTailAnchor }, limit: limit)
            if tail.count == limit, let last = tail.last {
                nextCursor = SearchCursor(
                    sortKey: sort.key, ascending: sort.ascending,
                    imagePath: last.imagePath, segment: .nullTail,
                    keyValue: nil).encode()
            }
            page = tail
        }

        let rows = page.map { row -> McpJSON in
            .object([
                "imageID": .int(Int(row.id)),
                "imagePath": .string(row.imagePath),
                "filename": row.filename.map { .string($0) } ?? .null,
                "dir": row.dir.map { .string($0) } ?? .null,
                "captureDate": row.captureDate.map { .double($0) } ?? .null,
                "rating": row.rating.map { .int(Int($0)) } ?? .null,
                "flag": row.flag.map { .int(Int($0)) } ?? .null,
                "colorLabel": row.colorLabel.map { .int(Int($0)) } ?? .null,
                "hasEdits": row.hasEdits.map { .int(Int($0)) } ?? .null,
            ])
        }
        var payload: [String: McpJSON] = [
            "results": .array(rows),
            "mode": .string("exif"),
            "nextCursor": nextCursor.map { .string($0) } ?? .null,
        ]
        payload["note"] = .string(
            "each call evaluates the query against the full library "
                + "(no layered session filter state); imagePath is a "
                + "project-relative path-kind form — address results by imageID")
        return .text(McpJSONSerialization.text(from: .object(payload)))
    }

    /// The main-segment advance (the E-2 flip rules; documented in
    /// DECISIONS): the anchored seek can never see NULL-key rows (a row
    /// value comparison with NULL is never true), so the segment flip is
    /// derivable from the page shape alone:
    ///   empty page, anchored  → keyed tier exhausted, NULL tier unseen →
    ///                           flip (tail anchor = tier head)
    ///   empty page, unanchored→ the whole library is empty → done
    ///   full page, keyed last → stay main (anchor the last row)
    ///   full page, NULL last  → the NULL tier STARTED inside this page →
    ///                           flip with the NULL-row path anchor (the
    ///                           tail seek continues AFTER it)
    ///   short page, anchored  → keyed tier exhausted, NULL tier unseen →
    ///                           flip (tier head)
    ///   short page, unanchored→ the whole library fit in one page (NULLs
    ///                           included — they sort last) → done
    /// A nullTail token with an empty path decodes as anchor nil (the tier
    /// head) — the tail query treats it as the first tail page.
    private static func advanceMain(
        rows: [LibraryImageRow], limit: Int, anchored: Bool,
        sort: FilterSort
    ) -> ([LibraryImageRow], String?) {
        guard let last = rows.last else {
            return (rows, anchored ? Self.tailToken(imagePath: nil, sort: sort) : nil)
        }
        let lastAnchor = LibraryPageAnchor.anchor(of: last, key: sort.key)
        if rows.count == limit {
            if let lastAnchor {
                return (rows, SearchCursor(
                    sortKey: sort.key, ascending: sort.ascending,
                    imagePath: last.imagePath, segment: .main,
                    keyValue: keyValue(of: lastAnchor.keyValue)).encode())
            }
            // NULL tier began inside this full page — continue it with the
            // NULL-row path anchor (the hand-built form).
            return (rows, Self.tailToken(imagePath: last.imagePath, sort: sort))
        }
        // Short page.
        if anchored {
            // The anchored page never sees NULL rows — the tier is still
            // fully pending.
            return (rows, Self.tailToken(imagePath: nil, sort: sort))
        }
        // Unanchored short page: the NULLs (if any) already rode THIS page.
        return (rows, nil)
    }

    /// The nullTail continuation token (nil path = the tier head — an
    /// empty path token decodes to anchor nil at the query site).
    private static func tailToken(
        imagePath: String?, sort: FilterSort
    ) -> String {
        SearchCursor(
            sortKey: sort.key, ascending: sort.ascending,
            imagePath: imagePath ?? "", segment: .nullTail,
            keyValue: nil).encode()
    }

    /// The key value a LibraryPageAnchor carries, in token kind form.
    private static func keyValue(
        of bind: FilterSQLBind
    ) -> SearchCursor.KeyValue? {
        switch bind {
        case .text(let text): text.map { SearchCursor.KeyValue.text($0) }
        case .int(let int): int.map { SearchCursor.KeyValue.int(Int($0)) }
        case .double(let double): double.map { SearchCursor.KeyValue.double($0) }
        }
    }

    // MARK: The CLIP route

    private static func searchClip(
        query: String, limit: Int, context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        guard let storeProvider = context.semanticStore,
            let store = await storeProvider() else {
            throw McpToolError.modelUnavailable(
                "no open project semantic index — the CLIP route evaluates "
                    + "the open library's embedding table")
        }
        guard let searcher = await context.semantic?() else {
            throw McpToolError.modelUnavailable(
                "bundled CLIP assets missing or failed to load")
        }
        let hits: [SemanticSearchHit]
        do {
            hits = try await searcher.search(query, limit: limit, in: store)
        } catch let error as AIWorkerClientError {
            // F-3: the worker family rides the modelUnavailable code — the
            // semantic runtime cannot serve THIS query (an absent/broken
            // worker process is not our bug; the message says which leg).
            throw McpToolError.modelUnavailable(
                "semantic worker unavailable: \(String(describing: error))")
        } catch SemanticSearchError.modelUnavailable {
            throw McpToolError.modelUnavailable(
                "bundled CLIP assets missing or failed to load")
        } catch let error as SemanticSearchError {
            // dimensionMismatch: the model/runner widths disagree — same
            // family, the message distinguishes mismatched from missing.
            throw McpToolError.modelUnavailable(
                "semantic model dimension mismatch: \(String(describing: error))")
        }
        let results = hits.enumerated().map { index, hit -> McpJSON in
            .object([
                "imageID": .int(Int(hit.imageID)),
                "score": .double(Double(hit.score)),
                "rank": .int(index),
            ])
        }
        return .text(McpJSONSerialization.text(from: .object([
            "results": .array(results),
            "mode": .string("clip"),
            "note": .string(
                "bounded top-K (no paging); score = cosine, best first; "
                    + "thumbnails ride get_thumbnails"),
        ])))
    }

    // MARK: The fulltext route

    private static func searchFulltext(
        query: String, limit: Int, context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        guard let fulltext = context.fulltext else {
            throw McpToolError.internalError(
                "the fulltext query face is not assembled on this host")
        }
        let ids = Array(try await fulltext(query).prefix(limit))
        let results = ids.enumerated().map { index, id -> McpJSON in
            .object([
                "imageID": .int(Int(id)),
                "rank": .int(index),
            ])
        }
        return .text(McpJSONSerialization.text(from: .object([
            "results": .array(results),
            "mode": .string("fulltext"),
            "note": .string(
                "bm25 rank order over the AI-understanding index (caption/"
                    + "tags/scene); bounded top-K (no paging)"),
        ])))
    }

    // MARK: Argument decoding

    enum SearchMode: String {
        case exif
        case clip
        case fulltext
    }

    private static func decodeMode(_ value: McpJSON?) throws -> SearchMode {
        guard let value, value != .null else { return .exif }
        guard let raw = value.stringValue else {
            throw McpToolError.invalidParams("mode must be a string")
        }
        guard let mode = SearchMode(rawValue: raw) else {
            throw McpToolError.invalidParams(
                "mode '\(raw)' is not one of exif|clip|fulltext")
        }
        return mode
    }

    private static func decodeLimit(
        _ value: McpJSON?, mode: SearchMode
    ) throws -> Int {
        let defaultLimit: Int
        switch mode {
        case .exif: defaultLimit = 200
        case .clip: defaultLimit = 256
        case .fulltext: defaultLimit = 500
        }
        guard let value, value != .null else { return defaultLimit }
        guard let limit = value.intValue, limit >= 1, limit <= 500 else {
            throw McpToolError.invalidParams(
                "limit must be an integer in 1...500 (mode defaults: "
                    + "exif 200 / clip 256 / fulltext 500)")
        }
        return limit
    }

    /// The EXIF sort decode (default filename asc — the GUI 同源 default;
    /// the key whitelist is the LIBRARY five, scanEpoch explicitly out).
    private static func decodeSort(_ value: McpJSON?) throws -> FilterSort {
        guard let value, value != .null else {
            return FilterSort(key: .filename, ascending: true)
        }
        guard case .object(let members) = value else {
            throw McpToolError.invalidParams("sort must be an object {key, ascending}")
        }
        guard let keyRaw = members["key"]?.stringValue,
            let key = FilterSortKey(rawValue: keyRaw)
        else {
            throw McpToolError.invalidParams(
                "sort.key must be one of \(LibraryQueries.sortableKeys.map(\.rawValue))")
        }
        var ascending = true
        if let flag = members["ascending"] {
            guard case .bool(let flagValue) = flag else {
                throw McpToolError.invalidParams("sort.ascending must be a boolean")
            }
            ascending = flagValue
        }
        return FilterSort(key: key, ascending: ascending)
    }

    /// A required non-empty string argument.
    private static func requiredString(
        _ value: McpJSON?, name: String
    ) throws -> String {
        guard let string = value?.stringValue, !string.isEmpty else {
            throw McpToolError.invalidParams(
                "\(name) (string) is required — an empty query has no MCP "
                    + "meaning (the GUI's empty-submit CLEARS the filter; "
                    + "this face has no filter state to clear)")
        }
        return string
    }

    // MARK: get_history (MCP2-02) — the read-only sidecar projection

    /// The item-kind classifier (D-M7-2-4, the five-arm pure function).
    /// Priority = payload specificity: a paste item's `pasteSet` wins over
    /// a coincident stack payload (the OVERWRITE paste carries the layer
    /// stack INSIDE the paste epoch — review N-5), then the document-level
    /// records, then the structure marker, else a param edit.
    static func historyKind(
        of item: HistoryStack.HistoryItem
    ) -> String {
        if item.pasteSet != nil { return "paste" }
        if item.drtRecord != nil { return "drt" }
        if item.filmRecord != nil { return "film" }
        if item.stackSnapshot != nil { return "structure" }
        return "param"
    }

    /// The F-5 cap: the whole history up to 500 items; truncation keeps
    /// the NEWEST end (the position side — the effective history), while
    /// `position` and `itemCount` stay the TRUE values, so an agent can
    /// always detect truncation and self-check its sequence.
    static let historyItemCap = 500

    private static func getHistory(
        _ arguments: [String: McpJSON], context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        let image = try requiredString(arguments["image"], name: "image")
        let includeParams = arguments["includeParams"]?.boolValue ?? false
        var limit = historyItemCap
        if let raw = arguments["limit"], raw != .null {
            guard let value = raw.intValue, value >= 1, value <= historyItemCap
            else {
                throw McpToolError.invalidParams(
                    "limit must be an integer in 1...\(historyItemCap)")
            }
            limit = value
        }

        let imageURL = try await resolveImageURL(image, context: context)
        // The disk truth (the same read seam the editing face rides);
        // nil = no readable sidecar = the PRISTINE honest face — not an
        // error (the plan's position=-1 contract).
        guard let document = ExportRenderer.readDocument(imageURL: imageURL)
        else {
            let payload = McpJSON.object([
                "image": .string(image),
                "position": .int(-1),
                "itemCount": .int(0),
                // N2-1 (M7-3): the shape-consistency key — the pristine face
                // carries the SAME keyset as the normal face (truncation is
                // vacuously false here; zero schema-semantics change).
                "truncated": .bool(false),
                "items": .array([]),
                "versions": .array([]),
                "activeVersionID": .null,
                "note": .null,
                "keywords": .null,
                "rating": .null,
                "flag": .null,
                "colorLabel": .null,
                "author": .null,
            ])
            return .text(McpJSONSerialization.text(from: payload))
        }

        let stack = document.history
        let trueCount = stack.items.count
        // Truncation keeps the NEWEST end (suffix); the red-tail case
        // (position below the kept window) stays detectable through the
        // true position/itemCount.
        let kept = trueCount > limit ? Array(stack.items.suffix(limit)) : stack.items
        let items = kept.map { item -> McpJSON in
            var dict: [String: McpJSON] = [
                "id": .string(item.id.uuidString),
                "label": .string(item.label),
                "timestamp": .string(Self.iso8601(item.timestamp)),
                "kind": .string(historyKind(of: item)),
                "layerScope": item.layerScope.map { .string($0) } ?? .null,
                // M7-4-01 (MCP2-09): the per-item note + author token —
                // absent field = .null (pre-M7-4 items decode nil).
                "note": item.note.map { .string($0) } ?? .null,
                "author": item.author.map { .string($0) } ?? .null,
            ]
            if includeParams {
                dict["params"] = Self.paramsFace(of: item)
            }
            return .object(dict)
        }
        let versions = (document.versions ?? []).map { record -> McpJSON in
            .object([
                "id": .string(record.id.uuidString),
                "name": .string(record.name),
                "createdAt": .string(Self.iso8601(record.createdAt)),
                "updatedAt": .string(Self.iso8601(record.updatedAt)),
                // chain == nil means ACTIVE (its items live in the
                // document's history key); the chain items themselves are
                // M7-3 list_versions' face, never repeated here.
                "active": .bool(record.chainStack == nil),
            ])
        }

        let payload = McpJSON.object([
            "image": .string(image),
            "position": .int(stack.position),
            "itemCount": .int(trueCount),
            "truncated": .bool(trueCount > kept.count),
            "items": .array(items),
            "versions": .array(versions),
            "activeVersionID": document.activeVersionID.map { .string($0) }
                ?? .null,
            "note": document.note.map { .string($0) } ?? .null,
            "keywords": document.keywords.map {
                .array($0.map { McpJSON.string($0) })
            } ?? .null,
            "rating": document.rating.map { .int($0) } ?? .null,
            "flag": document.flag.map { .int($0) } ?? .null,
            "colorLabel": document.colorLabel.map { .int($0) } ?? .null,
            // M7-4-01 (MCP2-09) fills the M7-2 placeholder: the CURRENT
            // position item's author (the truth-value form — with no
            // truncation this is the newest kept item; the kept-window
            // suffix case deliberately reads the POSITION item, not the
            // last kept row). Pristine/empty chain = .null.
            "author": stack.position >= 0 && stack.position < stack.items.count
                ? (stack.items[stack.position].author.map { .string($0) } ?? .null)
                : .null,
        ])
        return .text(McpJSONSerialization.text(from: payload))
    }

    /// The includeParams face (D-M7-2-4): param items expose the record's
    /// identity keys + the canonical params bytes; a paste item exposes
    /// its record set; the drt/film placeholder snapshots are DROPPED (the
    /// document-level payload rides dedicated records, not the snapshot
    /// slot — the HistoryStack scope-marker semantics), so their params
    /// face is null.
    private static func paramsFace(
        of item: HistoryStack.HistoryItem
    ) -> McpJSON {
        switch historyKind(of: item) {
        case "drt", "film":
            return .null
        case "paste":
            let records = (item.pasteSet ?? []).map { record -> McpJSON in
                .object(recordIdentity(record))
            }
            return .object([
                "records": .array(records),
            ])
        default:
            return .object(recordIdentity(item.snapshot))
        }
    }

    private static func recordIdentity(
        _ record: ModuleInstance
    ) -> [String: McpJSON] {
        [
            "opName": .string(record.opName),
            "multiPriority": .int(record.multiPriority),
            "multiName": .string(record.multiName),
            "enabled": .bool(record.enabled),
            "paramsBase64": .string(record.paramsData.base64EncodedString()),
        ]
    }

    /// The shared ISO-8601 rendering (internal since M7-3 — ProjectToolset's
    /// list_versions projection rides the SAME formatter).
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// The two-form addressing (the match_color shape): digits → the
    /// open library row + the linker's path-kind resolution; anything
    /// else → the open session pair (membership checked). Both arms
    /// unreachable = the typed `notSessionMember`.
    private static func resolveImageURL(
        _ image: String, context: McpSearchStateContext
    ) async throws -> URL {
        try await resolveImageURL(
            image,
            libraryProvider: context.library,
            sessionPairProvider: context.sessionPair)
    }

    /// The SHARED addressing core (M7-3 M3): the exact resolveImageURL
    /// logic lifted into a seam-parameterized form so ProjectToolset's
    /// list_versions can ride the SAME two-form resolution —
    /// SearchStateToolset passes its context's two seams, ProjectToolset
    /// passes its own same-shape pair (the assembly assigns the ONE closure
    /// variable to BOTH contexts, OQ-8). Pure extraction: zero behavior
    /// change, and the match_color provider is deliberately NOT touched
    /// (its anchor disease is the M7-4 route).
    static func resolveImageURL(
        _ image: String,
        libraryProvider: (@Sendable () async -> (
            store: ProjectFileStore, projectDirectory: URL
        )?)?,
        sessionPairProvider: (@Sendable () async -> (
            store: SessionIndexStore, root: URL
        )?)?
    ) async throws -> URL {
        if let id = Self.libraryImageID(image) {
            guard let libraryProvider else {
                throw McpToolError.notSessionMember(
                    "'\(image)' reads as a library image id but no library "
                        + "project is open on the server host — pass an "
                        + "open-session relPath instead")
            }
            guard let library = await libraryProvider() else {
                throw McpToolError.notSessionMember(noOpenProjectMessage)
            }
            let store = LibraryStore(store: library.store)
            let row: LibraryImage
            do {
                row = try await store.image(id: id)
            } catch {
                throw McpToolError.notSessionMember(
                    "library image id \(id) is not a row of the open library")
            }
            switch ImageLinker.resolve(
                imagePath: row.imagePath, pathKind: row.pathKind,
                volumeUUID: row.volumeUUID,
                projectDirectory: library.projectDirectory)
            {
            case .resolved(let url):
                return url
            case .stale(let reason):
                throw McpToolError.notSessionMember(
                    "library image id \(id) does not resolve (\(reason)) — "
                        + "relink the row in the GUI and retry")
            }
        }
        guard let sessionPairProvider else {
            throw McpToolError.notSessionMember(
                "'\(image)' is not addressable — no open session and it "
                    + "does not read as a library image id")
        }
        guard let (store, root) = await sessionPairProvider() else {
            throw McpToolError.notSessionMember(noOpenProjectMessage)
        }
        guard try await store.fetchRow(relPath: image) != nil else {
            throw McpToolError.notSessionMember(
                "'\(image)' is not a member of the open session")
        }
        return root.appendingPathComponent(image)
    }

    /// The digits-only id form (the match_color precedent).
    private static func libraryImageID(_ reference: String) -> Int64? {
        guard !reference.isEmpty, reference.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int64(reference)
    }

    // MARK: get_state (MCP2-03) — the one-shot snapshot

    private static func getState(
        _ arguments: [String: McpJSON], context: McpSearchStateContext
    ) async throws -> McpToolOutput {
        let snapshot = await context.liveState?()

        // The control face: the lock verdict (the SAME probe the write
        // faces gate on — read as DATA here) + the write-call counter
        // (nil provider / nil answer = the JSON null honest face —
        // F-4②: the headless and read-only faces have no exposed handle).
        var control: [String: McpJSON] = [:]
        if let probe = context.projectWriteProbe {
            let verdict = await probe()
            switch verdict {
            case .writable:
                control["lock"] = .string("writable")
            case .held(let holderSummary, _):
                control["lock"] = .string("held")
                control["holder"] = .string(holderSummary)
            }
        } else {
            control["lock"] = .null
        }
        let writeCount: McpJSON
        if let counter = context.writeCallCount {
            writeCount = await counter().map { McpJSON.int($0) } ?? .null
        } else {
            writeCount = .null
        }
        control["writeCallCount"] = writeCount

        // M7-5-01 (D-M7-5-8): the agent control state — the additive ONE
        // key. nil provider → the JSON null honest face; a provider answer
        // → the {held, revokedByUser, holder} sub-object. The three keys
        // above stay byte-identical (zero drift).
        if let agentControl = context.agentControl, let state = await agentControl() {
            control["agent"] = state.json
        } else {
            control["agent"] = .null
        }

        // The server face: the snapshot's host-derived stance when the
        // host supplied one; the identity is the handler's own fallback.
        let server: McpJSON
        if let face = snapshot?.server {
            server = face
        } else {
            server = .object([
                "name": .string(McpServerController.serverName),
                "version": .string(McpServerController.serverVersion),
                "hostMode": .null,
                "readOnly": .null,
            ])
        }

        let payload = McpJSON.object([
            "project": snapshot?.project ?? .null,
            "workspace": snapshot?.workspace ?? .null,
            "editor": snapshot?.editor ?? .null,
            "control": .object(control),
            "tasks": snapshot?.tasks ?? .null,
            "server": server,
        ])
        return .text(McpJSONSerialization.text(from: payload))
    }
}
