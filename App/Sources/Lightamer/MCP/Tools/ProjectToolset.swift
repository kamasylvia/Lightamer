import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M7-3-01 T4 — the project domain toolset (3 tools —
// `project_open` / `project_create` / `list_versions`, REQUIREMENTS
// MCP2-06..07; the Alcedo anchors are project.open / project.create /
// versions.list, read-only compared against the local source — GPL zero
// copy, all names/schemas/copy self-authored).
//
// DOMAIN BOUNDARY (D-M7-3-4): the fourth domain, self-contained — the lock
// arbitration semantics form a family of their own (editing 7 + culling 14 +
// searchstate 3 + project 3 = the 27 union).
//
// HOST-FORM ROUTING (D-M7-3-1): the routing single source is the ASSEMBLY
// point — the headless arm injects Core-direct open/create providers (the
// current-project box parks the store), the GUI-embedded arm injects
// controller-hop providers (MainActor inside the closure). The tool body
// never references a controller type (the F-6 source-isolation discipline).
//
// ERROR FACE (red line): every typed failure rides the EXISTING 16-value
// closed table — invalidParams / projectReadOnly / internalError /
// serverReadOnly (the registry writer gate) / notSessionMember. Zero new
// error codes.
//
// TRUTH DISCIPLINE (D-M7-3-8): list_versions reads the SIDECAR document
// (`readDocument` single source) — the library's version-reference projection is
// NEVER consulted (projection ≠ truth, M2-8 KD-3: reading both = the
// double-truth violation).
// ─────────────────────────────────────────────────────────────────────────────

/// The open/create outcome (D-M7-3-6): the four-field summary — NO
/// photo_count (the open answer stays fast; the agent takes counts through
/// search_photos/list_photos). `name` derives from the on-disk stem single
/// source (`url.deletingPathExtension().lastPathComponent`) — Core exposes
/// no name read face and the project file stem IS the name both routes
/// store, the same display form the GUI recent list shows (L3).
public struct ProjectOpenOutcome: Sendable, Equatable {
    public let url: URL
    public let readOnly: Bool
    public let heldByOther: Bool

    public init(url: URL, readOnly: Bool = false, heldByOther: Bool = false) {
        self.url = url
        self.readOnly = readOnly
        self.heldByOther = heldByOther
    }

    public var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The tool-face JSON projection (the four-field summary).
    public var summaryJSON: McpJSON {
        .object([
            "path": .string(url.path),
            "name": .string(name),
            "readOnly": .bool(readOnly),
            "heldByOther": .bool(heldByOther),
        ])
    }
}

/// The host-injected environment for the project tools (every seam a
/// provider closure — the 14-1 discipline; all optional, default nil =
/// every existing construction compiles zero-diff and the absent face is
/// the typed honest arm).
public struct McpProjectContext: Sendable {

    /// Open an existing `.lalb` package as the host's current project.
    /// Host form injected: the headless arm = the Core-direct open (the
    /// current-project box parks the store); the GUI arm = the controller
    /// hop (held targets are the typed projectReadOnly answer — the
    /// pre-check and the before/after conflict diff live INSIDE this
    /// closure, never in the tool body).
    public var openProject:
        (@Sendable (URL) async throws -> ProjectOpenOutcome)?

    /// Create a NEW `.lalb` package (`folder/<name>.lalb`) and open it.
    /// Same host-form routing as openProject.
    public var createProject:
        (@Sendable (URL, String) async throws -> ProjectOpenOutcome)?

    /// The open library's data face (list_versions' digits-arm addressing —
    /// the SAME closure form the search/state context carries; OQ-8: the
    /// assembly assigns the ONE closure variable to BOTH contexts, provider
    /// logic is never duplicated).
    public var library:
        (@Sendable () async -> (
            store: ProjectFileStore, projectDirectory: URL
        )?)?

    /// The open session pair (the relPath addressing arm). Same OQ-8 shape.
    public var sessionPair:
        (@Sendable () async -> (store: SessionIndexStore, root: URL)?)?

    /// The lock-verdict probe (symmetry with the search/state context —
    /// list_versions is read-only and never consumes it; the face exists so
    /// a host assembling one context assembles the other the same way).
    public var projectWriteProbe:
        (@Sendable () async -> McpProjectLockVerdict)?

    public init(
        openProject: (@Sendable (URL) async throws -> ProjectOpenOutcome)? = nil,
        createProject: (@Sendable (URL, String) async throws -> ProjectOpenOutcome)? = nil,
        library: (@Sendable () async -> (
            store: ProjectFileStore, projectDirectory: URL
        )?)? = nil,
        sessionPair: (@Sendable () async -> (
            store: SessionIndexStore, root: URL
        )?)? = nil,
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil
    ) {
        self.openProject = openProject
        self.createProject = createProject
        self.library = library
        self.sessionPair = sessionPair
        self.projectWriteProbe = projectWriteProbe
    }
}

enum McpProjectToolset {

    // MARK: - Registration (the three tools; grows additively)

    static func registerAll(
        on registry: McpToolRegistry, context: McpProjectContext
    ) async {
        await registerProjectOpen(on: registry, context: context)
        await registerProjectCreate(on: registry, context: context)
        await registerListVersions(on: registry, context: context)
    }

    // MARK: - project_open (MCP2-06)

    private static func registerProjectOpen(
        on registry: McpToolRegistry, context: McpProjectContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "project_open",
                description: String(
                    localized: "mcp_tool_desc_project_open",
                    defaultValue: String.LocalizationValue(
                        "Open an existing .lalb project package as this server's "
                            + "project context (WRITER HOST REQUIRED — a read-only "
                            + "host answers serverReadOnly at the gate first). path: "
                            + "the ABSOLUTE .lalb package path; a wrong path leaves "
                            + "the current project untouched (check-before-open — "
                            + "Alcedo 同构). An already-held project closes first "
                            + "(its checkpoint rides close) and the target opens; "
                            + "when the TARGET is held by another instance the typed "
                            + "projectReadOnly answer carries the holder summary and "
                            + "the current project state stays honest (the headless "
                            + "arm's failed-open-after-close leaves NO project open — "
                            + "retry the open). The summary is {path, name, readOnly, "
                            + "heldByOther} — photo counts ride search_photos/"
                            + "list_photos. Errors: invalidParams (missing path/bad "
                            + "suffix), projectReadOnly (held target), "
                            + "internalError (open I/O failure), serverReadOnly.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"path":{"type":"string","description":"The absolute path of the .lalb package to open"}},"required":["path"]}"#),
            requiresWriter: true,
            handler: { arguments in
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.apply,
                    McpToolError.internalError("project_open timed out")
                ) {
                    try await projectOpen(arguments, context: context)
                }
            })
    }

    private static func projectOpen(
        _ arguments: [String: McpJSON], context: McpProjectContext
    ) async throws -> McpToolOutput {
        let path = try requiredString(arguments["path"], name: "path")
        let url = URL(fileURLWithPath: path)
        // 先检后开 (Alcedo 同构): a wrong path NEVER touches the current
        // project — the typed invalidParams carries the path.
        guard url.pathExtension.lowercased() == LibrarySchema.fileExtension else {
            throw McpToolError.invalidParams(
                "path is not a .\(LibrarySchema.fileExtension) package: \(path)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw McpToolError.invalidParams(
                "no .\(LibrarySchema.fileExtension) package at \(path)")
        }
        guard let open = context.openProject else {
            throw McpToolError.internalError(
                "the project open face is not assembled on this host")
        }
        let outcome = try await open(url)
        return .text(McpJSONSerialization.text(from: outcome.summaryJSON))
    }

    // MARK: - project_create (MCP2-06)

    private static func registerProjectCreate(
        on registry: McpToolRegistry, context: McpProjectContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "project_create",
                description: String(
                    localized: "mcp_tool_desc_project_create",
                    defaultValue: String.LocalizationValue(
                        "Create a NEW .lalb project package and open it as this "
                            + "server's project context (WRITER HOST REQUIRED — a "
                            + "read-only host answers serverReadOnly at the gate "
                            + "first). folder: an EXISTING directory path; name: the "
                            + "package name (no path separators / colons / leading "
                            + "dots). The package lands at folder/<name>.lalb; an "
                            + "existing package is REFUSED, never overwritten. An "
                            + "already-held project closes first (checkpoint rides "
                            + "close). The summary is {path, name, readOnly, "
                            + "heldByOther} — photo counts ride search_photos/"
                            + "list_photos. Errors: invalidParams (folder missing / "
                            + "bad name / package exists), projectReadOnly (held "
                            + "target), internalError (create I/O failure), "
                            + "serverReadOnly.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"folder":{"type":"string","description":"An EXISTING directory the package is created in"},"name":{"type":"string","minLength":1,"description":"The package name (folder/<name>.lalb; no path separators / colons / leading dots)"}},"required":["folder","name"]}"#),
            requiresWriter: true,
            handler: { arguments in
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.apply,
                    McpToolError.internalError("project_create timed out")
                ) {
                    try await projectCreate(arguments, context: context)
                }
            })
    }

    /// The package-name sanitize (the minimal blacklist — the export naming
    /// sanitize is heavier than v1 needs): reject separators, NUL, colon,
    /// dot-only and leading-dot forms.
    static func sanitizePackageName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw McpToolError.invalidParams("name must be non-empty")
        }
        let blacklist: Set<Character> = ["/", "\0", ":"]
        guard !trimmed.contains(where: { blacklist.contains($0) }) else {
            throw McpToolError.invalidParams(
                "name must not contain path separators or colons: \(trimmed)")
        }
        guard !trimmed.hasPrefix(".") else {
            throw McpToolError.invalidParams(
                "name must not start with a dot: \(trimmed)")
        }
        return trimmed
    }

    private static func projectCreate(
        _ arguments: [String: McpJSON], context: McpProjectContext
    ) async throws -> McpToolOutput {
        let folderRaw = try requiredString(arguments["folder"], name: "folder")
        let name = try sanitizePackageName(
            try requiredString(arguments["name"], name: "name"))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: folderRaw, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw McpToolError.invalidParams(
                "folder is not an existing directory: \(folderRaw)")
        }
        let folder = URL(fileURLWithPath: folderRaw, isDirectory: true)
        let packageURL = folder.appendingPathComponent(
            name + "." + LibrarySchema.fileExtension)
        // 已存在拒 (never overwrite — Alcedo create semantics).
        guard FileManager.default.fileExists(atPath: packageURL.path) == false
        else {
            throw McpToolError.invalidParams(
                "a package already exists at \(packageURL.path) — creating "
                    + "never overwrites")
        }
        guard let create = context.createProject else {
            throw McpToolError.internalError(
                "the project create face is not assembled on this host")
        }
        let outcome = try await create(packageURL, name)
        return .text(McpJSONSerialization.text(from: outcome.summaryJSON))
    }

    // MARK: - list_versions (MCP2-07, read-only)

    private static func registerListVersions(
        on registry: McpToolRegistry, context: McpProjectContext
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "list_versions",
                description: String(
                    localized: "mcp_tool_desc_list_versions",
                    defaultValue: String.LocalizationValue(
                        "List the VERSION TREE of one image's sidecar document "
                            + "(READ-ONLY — this face never writes): per version the "
                            + "id, name, createdAt/updatedAt, the active flag, the "
                            + "chain position/itemCount truth values and — with "
                            + "includeItems=true — each version's own item list (the "
                            + "ACTIVE version reads the document history; non-active "
                            + "versions read their frozen chains; every list caps at "
                            + "the 500 NEWEST items with a per-version truncated flag "
                            + "— position/itemCount stay true, truncation is "
                            + "detectable). image: a library image id (digits) or an "
                            + "open-session relPath (the get_history addressing). "
                            + "SIDECAR TRUTH only — the library's version-reference "
                            + "projection is never consulted (projection ≠ truth). "
                            + "No sidecar "
                            + "document = the pristine honest face (versions: [], "
                            + "activeVersionID null — NOT an error). Division of "
                            + "labor: get_history stays the ACTIVE chain + the "
                            + "metadata face (note/keywords/rating); list_versions is "
                            + "the tree + the non-active-chains channel. Errors: "
                            + "notSessionMember (image not addressable / no open "
                            + "project), invalidParams.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeItems":{"type":"boolean","default":false,"description":"Attach each version's own item list (capped at the 500 NEWEST; the truncated flag rides per version)"}},"required":["image"]}"#,
                readOnlyHint: true),
            handler: { arguments in
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("list_versions timed out")
                ) {
                    try await listVersions(arguments, context: context)
                }
            })
    }

    private static func listVersions(
        _ arguments: [String: McpJSON], context: McpProjectContext
    ) async throws -> McpToolOutput {
        let image = try requiredString(arguments["image"], name: "image")
        let includeItems = arguments["includeItems"]?.boolValue ?? false
        // The shared addressing core (OQ-8/M3): the same helper get_history
        // rides, fed this context's same-shape two seams.
        let imageURL = try await McpSearchStateToolset.resolveImageURL(
            image,
            libraryProvider: context.library,
            sessionPairProvider: context.sessionPair)
        // The single source of truth: the sidecar document (readDocument) —
        // the library's version-reference projection is NEVER read (D-M7-3-8).
        guard let document = ExportRenderer.readDocument(imageURL: imageURL)
        else {
            // The pristine honest face — not an error arm.
            let payload = McpJSON.object([
                "image": .string(image),
                "activeVersionID": .null,
                "versions": .array([]),
            ])
            return .text(McpJSONSerialization.text(from: payload))
        }

        let versions: [McpJSON] = (document.versions ?? []).map { record in
            // ACTIVE = chain nil (its items live in the document history
            // key); non-active chains ride the record's frozen stack.
            let isActive = record.chainStack == nil
            let stack = record.chainStack ?? document.history
            let trueCount = stack.items.count
            let kept = trueCount > McpSearchStateToolset.historyItemCap
                ? Array(stack.items.suffix(McpSearchStateToolset.historyItemCap))
                : stack.items
            var dict: [String: McpJSON] = [
                "id": .string(record.id.uuidString),
                "name": .string(record.name),
                "createdAt": .string(
                    McpSearchStateToolset.iso8601(record.createdAt)),
                "updatedAt": .string(
                    McpSearchStateToolset.iso8601(record.updatedAt)),
                "active": .bool(isActive),
                "position": .int(stack.position),
                "itemCount": .int(trueCount),
                "truncated": .bool(trueCount > kept.count),
            ]
            if includeItems {
                let items = kept.map { item -> McpJSON in
                    .object([
                        "id": .string(item.id.uuidString),
                        "label": .string(item.label),
                        "timestamp": .string(
                            McpSearchStateToolset.iso8601(item.timestamp)),
                        "kind": .string(
                            McpSearchStateToolset.historyKind(of: item)),
                        "layerScope": item.layerScope.map { .string($0) } ?? .null,
                    ])
                }
                dict["items"] = .array(items)
            }
            return .object(dict)
        }
        let payload = McpJSON.object([
            "image": .string(image),
            "activeVersionID": document.activeVersionID.map { .string($0) }
                ?? .null,
            "versions": .array(versions),
        ])
        return .text(McpJSONSerialization.text(from: payload))
    }

    // MARK: - Argument helpers

    /// A required non-empty string argument (the SearchStateToolset shape).
    private static func requiredString(
        _ value: McpJSON?, name: String
    ) throws -> String {
        guard let string = value?.stringValue, !string.isEmpty else {
            throw McpToolError.invalidParams("\(name) (string) is required")
        }
        return string
    }
}
