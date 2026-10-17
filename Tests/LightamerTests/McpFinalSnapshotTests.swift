import LightamerCore
import MCP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// Plan 14-4 T3: the FINAL snapshot — the frozen closed set (research §A is
// the canonical table; D-14-CONTEXT-3③: the tool face IS a security face) +
// the whitelist negative + the SC#7 launcher end-to-end chain with the
// dual-entry coexistence proof. M5-1-03 (KD-1, checker E3): match_color
// joined the editing domain — the freeze grew to 20 (all19 → all20).
// M7-2-01 (the union snapshot conscious change): the search/state domain
// (3 read-only tools) joined as a THIRD domain — the freeze is the
// the 23-tool set (all20 → the 23-set; this file holds the M7-2..M7-5 serial
// snapshot-edit right; the per-domain snapshot files stay untouched).
// M7-3-01 (the union snapshot conscious change, THIS file's edit right
// exercised): list_luts joined the editing domain (6→7) and the project
// domain (3 tools) opened as the FOURTH domain — the freeze was the
// 27-tool set then (all29's predecessor identifier, one deliberate
// edit; 29 since M7-4-01, see below).
// M7-4-01 (the union snapshot conscious change, THIS file's edit right
// exercised again): the O4 pair copy_adjustments/paste_adjustments joins
// the editing domain (7→9) and apply_params gains the item-level note
// property — the freeze is the 29-tool set (the 27-set → all29, one
// deliberate edit; the M7-5 handoff note stands — M7-5 stays
// SERIAL-EXCLUDED while M7-4 holds the right).
//
// Snapshot layers (all must consciously change together):
//   - the editing domain (9)      → McpRegistrySnapshotTests (14-2)
//   - the culling domain (14)     → McpCullingToolsetTests (14-3)
//   - the search/state domain (3) → McpSearchStateToolsetTests (M7-2)
//   - the project domain (3)      → McpProjectToolsetTests (M7-3)
//   - THE UNION (29)              → this file (the final freeze)
// ─────────────────────────────────────────────────────────────────────────────

final class McpFinalSnapshotTests: XCTestCase {

    // MARK: - The frozen legacy tables (research §A verbatim + M5-1-03)

    /// §A #1 load_image … #4 list_iops, #3 render_preview, #19 export_image
    /// (the 14-2 face; schemas byte-equal the registration source), plus
    /// #20 match_color (M5-1-03 — checker E3: the descriptor rides the
    /// frozen table, the count assertions 19→20, NOT an executor side edit).
    static let editingTools: [McpToolDescriptor] = [
        McpToolDescriptor(
            // M7-4-01: apply_params gains the item-level note property
            // (MCP2-09 — this schema row edits consciously, the same batch
            // the editing-layer file edits).
            name: "apply_params",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"ops":{"type":"array","minItems":1,"description":"Module-level upserts","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer","default":0},"params":{"type":"object","description":"Partial params JSON overlaid on the instance (keys per list_iops)"},"enabled":{"type":"boolean"},"remove":{"type":"boolean","default":false}},"required":["opName"]}},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to the history commit (distinct from the document-level note set via append_note)"}},"required":["relPath","ops"]}"#,
            destructiveHint: true),
        McpToolDescriptor(
            // M7-4-01 (MCP2-08): copy_adjustments joins the editing domain
            // (7→9 — this union snapshot edits consciously; the O4 pair).
            name: "copy_adjustments",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath"}},"required":["source"]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "export_image",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"format":{"type":"string","enum":["jpeg","png","tiff","heic","avif","webp"],"default":"jpeg"},"quality":{"type":"integer","minimum":1,"maximum":100,"default":90,"description":"Lossy formats only"},"sizing":{"type":"object","properties":{"mode":{"type":"string","enum":["original","longEdge","shortEdge"],"default":"original"},"px":{"type":"integer","minimum":1,"description":"Required for longEdge/shortEdge"}}},"colorSpace":{"type":"string","enum":["sRGB","displayP3","adobeRGB","proPhoto","rec2020"],"default":"sRGB"},"yiyin":{"type":"boolean","default":false,"description":"Render through the image's existing yiyin frame/watermark configuration"}},"required":["relPath"]}"#,
            destructiveHint: true),
        McpToolDescriptor(
            name: "list_iops",
            description: "snapshot",
            inputSchemaJSON: #"{"type":"object","properties":{},"required":[]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "load_image",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"}},"required":["relPath"]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "render_preview",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"},"region":{"type":"object","properties":{"x":{"type":"number","minimum":0,"maximum":1},"y":{"type":"number","minimum":0,"maximum":1},"w":{"type":"number","exclusiveMinimum":0,"maximum":1},"h":{"type":"number","exclusiveMinimum":0,"maximum":1}},"required":["x","y","w","h"],"description":"Normalized 0..1 ROI {x,y,w,h} relative to the RENDERED output frame (orientation already normalized); cropped after the render, decoupled from longEdge"},"compare":{"type":"string","enum":["none","root"],"default":"root","description":"none = the edited image only; root (default) = the pristine (edit-free) image rides along for the before/after loop"}},"required":["relPath"]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            // M7-3 (MCP2-05): list_luts joins the editing domain (6→7,
            // D-M7-3-4 — this domain snapshot edits consciously).
            name: "list_luts",
            description: "snapshot",
            inputSchemaJSON: #"{"type":"object","properties":{},"required":[]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "match_color",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"reference":{"type":"string","description":"Reference image: a library image id (digits) or an open-session relPath"},"targets":{"oneOf":[{"type":"string"},{"type":"array","items":{"type":"string"}}],"maxItems":30,"description":"Target relPath(s) relative to the session root; default = the editor's current image"},"strength":{"type":"number","minimum":0,"maximum":1,"default":1,"description":"The solve/identity blend"},"solver":{"type":"string","enum":["gaussian-ot","reinhard","cdf"],"default":"gaussian-ot"},"attach":{"type":"boolean","default":true,"description":"false = return the params for apply_params instead of writing"}},"required":["reference"]}"#,
            destructiveHint: true),
        McpToolDescriptor(
            // M7-4-01 (MCP2-08): paste_adjustments joins the editing domain
            // (the O4 pair's write face — destructiveHint rides the set).
            name: "paste_adjustments",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath (the copy_adjustments addressing)"},"targets":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":1000,"description":"Open-session relPaths to paste onto"},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to each history commit (distinct from the document-level note set via append_note)"},"include":{"type":"array","items":{"type":"string","format":"uuid"},"description":"instanceId subset from copy_adjustments (default: every transferable instance)"},"includeDrt":{"type":"boolean","default":true,"description":"false drops the source's DRT row"},"version":{"type":"string","description":"A copy_adjustments versions[] id (default: the active chain)"}},"required":["source","targets"]}"#,
            destructiveHint: true),
    ]

    /// §A #5-10 + #11-18: the 14-tool culling face (schemas byte-equal the
    /// registration source in CullingToolset.swift).
    static let cullingTools: [McpToolDescriptor] = [
        McpToolDescriptor(
            name: "append_note",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths","note"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"note":{"type":"string","minLength":1,"description":"Appended as one line (a newline is inserted after an existing note)"}}}"#,
            destructiveHint: true),
        McpToolDescriptor(
            name: "apply_preset",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["presetID","relPaths"],"properties":{"presetID":{"type":"string"},"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"mode":{"enum":["overwrite","merge"],"description":"Paste mode (default merge)"},"selection":{"type":"array","description":"Partial-apply subset of instances","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer"},"multiName":{"type":"string"}},"required":["opName","multiPriority","multiName"]}}}}"#,
            destructiveHint: true),
        McpToolDescriptor(
            name: "diff_presets",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["presetIDA","presetIDB"],"properties":{"presetIDA":{"type":"string"},"presetIDB":{"type":"string"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "get_contact_sheet",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":30},"filter":{"type":"object","description":"FilterPredicateGroup JSON (same shape as list_photos.filter)"},"sort":{"type":"object","description":"Row order when filter is used (same shape as list_photos.sort)"},"cols":{"type":"integer","minimum":1,"maximum":6},"rows":{"type":"integer","minimum":1,"maximum":5}},"oneOf":[{"required":["relPaths"]},{"required":["filter"]}]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "get_detail_crop",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPath","roi"],"properties":{"relPath":{"type":"string"},"roi":{"type":"object","properties":{"x":{"type":"integer","minimum":0},"y":{"type":"integer","minimum":0},"w":{"type":"integer","exclusiveMinimum":0},"h":{"type":"integer","exclusiveMinimum":0}},"required":["x","y","w","h"]},"longEdge":{"type":"integer","minimum":64,"maximum":1536,"description":"Output long edge (default 1024)"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "get_face_regions",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"includeLandmarks":{"type":"boolean","description":"Also return per-face landmark point sets (default false)"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "get_thumbnails",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":20},"regenerate":{"type":"boolean","description":"Re-render stale thumbnails before returning (default false — stale rows are only marked)"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "list_bursts",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"gapSeconds":{"type":"number","exclusiveMinimum":0,"description":"Max gap between consecutive shots of one burst (default 2.0)"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "list_photos",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"cursor":{"type":"string","description":"Opaque nextCursor token from the previous page"},"filter":{"type":"object","description":"FilterPredicateGroup JSON: {schemaVersion:1, match:"all"|"any", rules:[{field, op, value:{kind, ...}}]}"},"limit":{"type":"integer","minimum":1,"maximum":1000,"description":"Rows per page (default 200)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength|scanEpoch, ascending: bool}"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "list_presets",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"kind":{"enum":["develop","export"],"description":"Filter by preset kind"}}}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "set_color_label",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths","color"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"color":{"type":["integer","null"],"minimum":0,"maximum":6,"description":"0-6, or null to clear"}}}"#,
            destructiveHint: true),
        McpToolDescriptor(
            name: "set_flag",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths","flag"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"flag":{"type":["integer","null"],"minimum":0,"maximum":2,"description":"0 none / 1 pick / 2 reject, or null to clear"}}}"#,
            destructiveHint: true),
        McpToolDescriptor(
            name: "set_keywords",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths","keywords"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"keywords":{"type":["array","null"],"items":{"type":"string"},"description":"Whole-group replacement; empty array = cleared state, null = never-tagged; entries must not contain '|'"}}}"#,
            destructiveHint: true),
        McpToolDescriptor(
            name: "set_rating",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","required":["relPaths","rating"],"properties":{"relPaths":{"type":"array","items":{"type":"string"},"maxItems":1000},"rating":{"type":["integer","null"],"minimum":0,"maximum":5,"description":"0-5, or null to clear"}}}"#,
            destructiveHint: true),
    ]

    /// M7-2-01: the third domain — three READ-ONLY tools (their schemas
    /// byte-equal the registration source in SearchStateToolset.swift; the
    /// descriptions live in the registration site + the zh catalog).
    static let searchStateTools: [McpToolDescriptor] = [
        McpToolDescriptor(
            name: "get_history",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeParams":{"type":"boolean","default":false,"description":"Add the per-item params face"},"limit":{"type":"integer","minimum":1,"maximum":500,"description":"Item cap (default 500); truncation keeps the NEWEST end — position/itemCount stay the true values, so truncation is detectable"}},"required":["image"]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "get_state",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{},"required":[]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "search_photos",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"query":{"type":"string","minLength":1,"description":"The search query (the EXIF grammar: plain words + structured tokens like iso800, f/2.8, 2024-06..2024-08)"},"mode":{"type":"string","enum":["exif","clip","fulltext"],"default":"exif","description":"The route (default exif)"},"limit":{"type":"integer","minimum":1,"maximum":500,"description":"Rows per call (exif default 200; clip/fulltext caps 256/500)"},"cursor":{"type":"string","description":"Opaque nextCursor token — EXIF mode ONLY (a token is only valid for its issuing sort and this tool)"},"sort":{"type":"object","description":"{key: filename|rating|captureDate|iso|focalLength, ascending: bool} — EXIF mode ONLY; default filename ascending"}},"required":["query"]}"#,
            readOnlyHint: true),
    ]

    /// M7-3-01: the FOURTH domain — the project family (their schemas
    /// byte-equal the registration source in ProjectToolset.swift; the
    /// open/create pair rides requiresWriter at the register call site,
    /// list_versions is readOnlyHint).
    static let projectTools: [McpToolDescriptor] = [
        McpToolDescriptor(
            name: "list_versions",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeItems":{"type":"boolean","default":false,"description":"Attach each version's own item list (capped at the 500 NEWEST; the truncated flag rides per version)"}},"required":["image"]}"#,
            readOnlyHint: true),
        McpToolDescriptor(
            name: "project_create",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"folder":{"type":"string","description":"An EXISTING directory the package is created in"},"name":{"type":"string","minLength":1,"description":"The package name (folder/<name>.lalb; no path separators / colons / leading dots)"}},"required":["folder","name"]}"#),
        McpToolDescriptor(
            name: "project_open",
            description: "snapshot",
            inputSchemaJSON:
                #"{"type":"object","properties":{"path":{"type":"string","description":"The absolute path of the .lalb package to open"}},"required":["path"]}"#),
    ]

    static var all29: [McpToolDescriptor] {
        editingTools + cullingTools + searchStateTools + projectTools
    }

    // MARK: - The assembly

    private func makeUnionRegistry() async -> McpToolRegistry {
        await McpServerController.makeRegistry(
            editing: EditingToolset.Seams(
                session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
                gate: McpRenderGate(), liveImageURL: { nil }),
            culling: McpServerController.makeCullingContext(session: { nil }),
            // M7-2-01: without the context the union stays short of the
            // search/state domain — the all-nil fixture context registers
            // the three tools (the registration consumes no provider; only
            // handler calls do).
            searchState: McpSearchStateContext(),
            // M7-3-01: same discipline for the project domain — the all-nil
            // fixture context registers the three project tools (27 is
            // unreachable without this argument).
            project: McpProjectContext())
    }

    /// THE final freeze: every host assembles exactly these 27 descriptors —
    /// names, VERBATIM inputSchema JSON and the §A annotation column.
    func testFinalSnapshotUnion29Verbatim() async throws {
        let registry = await makeUnionRegistry()
        try await McpRegistrySnapshotTests.assertSnapshot(
            registry: registry, expected: Self.all29)
        let descriptors = await registry.descriptors()
        XCTAssertEqual(descriptors.count, 29,
                       "D3: the final count is 29 (M7-4-01: the O4 pair "
                           + "joined the editing domain)")
        // §A annotations at a glance: exactly 10 destructive tools — the §A
        // write face + match_color + paste_adjustments (M7-4-01); the
        // remainder are read-only or non-destructive state-changing
        // (project_open/project_create).
        let destructive = descriptors.filter { $0.destructiveHint == true }.map(\.name)
        XCTAssertEqual(
            Set(destructive),
            ["apply_params", "export_image", "match_color", "set_rating", "set_flag",
                "set_color_label", "append_note", "set_keywords", "apply_preset",
                "paste_adjustments"],
            "the write face is the §A destructive column + match_color + "
                + "paste_adjustments (M5-1-03 + M7-4-01)")
    }

    /// Domain consistency: the per-domain assemblies are DISJOINT and their
    /// union is exactly the final face (the 14-2/14-3/M7-2/M7-3 per-domain
    /// snapshots compose into this freeze with no overlap).
    func testDomainSnapshotsComposeIntoTheUnion() async throws {
        let editing = EditingToolset.Seams(
            session: { nil }, metal: { nil }, modules: { ModuleRegistry() },
            gate: McpRenderGate(), liveImageURL: { nil })
        let editingOnly = await McpServerController.makeRegistry(editing: editing)
        let cullingOnly = await McpServerController.makeRegistry(
            culling: McpServerController.makeCullingContext(session: { nil }))
        let searchStateOnly = await McpServerController.makeRegistry(
            searchState: McpSearchStateContext())
        let projectOnly = await McpServerController.makeRegistry(
            project: McpProjectContext())
        let union = await makeUnionRegistry()
        let e = await editingOnly.descriptors().map(\.name)
        let c = await cullingOnly.descriptors().map(\.name)
        let s = await searchStateOnly.descriptors().map(\.name)
        let p = await projectOnly.descriptors().map(\.name)
        let u = await union.descriptors().map(\.name)
        XCTAssertEqual(Set(e), Set(Self.editingTools.map(\.name)))
        XCTAssertEqual(Set(c), Set(Self.cullingTools.map(\.name)))
        XCTAssertEqual(Set(s), Set(Self.searchStateTools.map(\.name)))
        XCTAssertEqual(Set(p), Set(Self.projectTools.map(\.name)))
        XCTAssertTrue(Set(e).isDisjoint(with: Set(c)), "no tool rides two domains")
        XCTAssertTrue(Set(e).isDisjoint(with: Set(s)), "no tool rides two domains")
        XCTAssertTrue(Set(c).isDisjoint(with: Set(s)), "no tool rides two domains")
        XCTAssertTrue(Set(e).isDisjoint(with: Set(p)), "no tool rides two domains")
        XCTAssertTrue(Set(c).isDisjoint(with: Set(p)), "no tool rides two domains")
        XCTAssertTrue(Set(s).isDisjoint(with: Set(p)), "no tool rides two domains")
        // The search/state tools ride a NEW domain (not folded into an
        // existing one — the M5-1-03 match_color precedent folded INTO
        // editing; M7-2 opened its own layer); M7-3 opened the project
        // layer the same way.
        XCTAssertEqual(
            Set(u), Set(e).union(Set(c)).union(Set(s)).union(Set(p)))
        XCTAssertEqual(u.count, 29, "M7-4-01: the union grew to 29")
    }

    /// The whitelist negative: a 21st tool does NOT exist. `match_color` WAS
    /// the named zero-occupancy case until M5-1-03 landed it (the closed
    /// enumeration grew by one deliberate edit — this snapshot); a random
    /// name rides the same error.
    func testPostUnionToolIsWhitelistNegative() async throws {
        let registry = await makeUnionRegistry()
        let pair = await InMemoryTransport.createConnectedPair()
        let server = await McpAdapters.makeServer(registry: registry)
        try await server.start(transport: pair.server)
        let client = MCP.Client(name: "whitelist-negative", version: "0.0.1")
        try await client.connect(transport: pair.client)
        defer {
            Task { await client.disconnect(); await server.stop() }
        }
        for name in ["delete_file", "run_shell"] {
            do {
                _ = try await client.callTool(name: name)
                XCTFail("'\(name)' must NOT exist (tool face = security face)")
            } catch let error as MCPError {
                let text = String(describing: error)
                XCTAssertTrue(text.contains("[internalError]"), "got: \(text)")
                XCTAssertTrue(text.contains("unknownTool"), "got: \(text)")
            }
        }
        let tools = try await client.listTools().tools
        XCTAssertEqual(tools.count, 29, "no 30th tool rides the list either")
    }

    // MARK: - zh/en description keys (D-14-CONTEXT-3②: the L025 face)

    /// tool name → its description catalog key (the write-five share ONE
    /// frame description — D-14-4-T3-2).
    static let descriptionKeys: [String: String] = [
        "load_image": "mcp_tool_desc_load_image",
        "apply_params": "mcp_tool_desc_apply_params",
        "render_preview": "mcp_tool_desc_render_preview",
        "list_iops": "mcp_tool_desc_list_iops",
        "export_image": "mcp_tool_desc_export_image",
        "list_photos": "mcp_tool_desc_list_photos",
        "set_rating": "mcp_tool_desc_write_metadata",
        "set_flag": "mcp_tool_desc_write_metadata",
        "set_color_label": "mcp_tool_desc_write_metadata",
        "append_note": "mcp_tool_desc_write_metadata",
        "set_keywords": "mcp_tool_desc_write_metadata",
        "list_presets": "mcp_tool_desc_list_presets",
        "apply_preset": "mcp_tool_desc_apply_preset",
        "diff_presets": "mcp_tool_desc_diff_presets",
        "get_thumbnails": "mcp_tool_desc_get_thumbnails",
        "get_contact_sheet": "mcp_tool_desc_get_contact_sheet",
        "get_detail_crop": "mcp_tool_desc_get_detail_crop",
        "list_bursts": "mcp_tool_desc_list_bursts",
        "get_face_regions": "mcp_tool_desc_get_face_regions",
        "match_color": "mcp_tool_desc_match_color",
        "search_photos": "mcp_tool_desc_search_photos",
        "get_history": "mcp_tool_desc_get_history",
        "get_state": "mcp_tool_desc_get_state",
        "list_luts": "mcp_tool_desc_list_luts",
        "project_open": "mcp_tool_desc_project_open",
        "project_create": "mcp_tool_desc_project_create",
        "list_versions": "mcp_tool_desc_list_versions",
        "copy_adjustments": "mcp_tool_desc_copy_adjustments",
        "paste_adjustments": "mcp_tool_desc_paste_adjustments",
    ]

    /// Every final tool has a zh description key with a non-empty value AND
    /// a non-empty runtime description (the en defaultValue is embedded at
    /// the registration site — zero drift from the reviewed text).
    func testToolDescriptionsCarryZhCatalogKeys() async throws {
        let zhPath = try XCTUnwrap(
            Bundle.main.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: "zh"),
            "the zh localization must exist in the app bundle")
        let zh = try XCTUnwrap(
            NSDictionary(contentsOfFile: zhPath) as? [String: String])
        let registry = await makeUnionRegistry()
        let descriptors = await registry.descriptors()
        XCTAssertEqual(
            Set(Self.descriptionKeys.keys), Set(descriptors.map(\.name)),
            "the key map must cover exactly the final face")
        for (tool, key) in Self.descriptionKeys {
            let value = try XCTUnwrap(zh[key], "missing zh key \(key) for \(tool)")
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, key)
        }
        for descriptor in descriptors {
            XCTAssertFalse(descriptor.description.isEmpty, descriptor.name)
        }
    }

    // MARK: - SC#7: the launcher chain end-to-end + dual entry

    private struct ChainFixture {
        let store: SessionIndexStore
        let root: URL
        let sessionRoot: URL
        func cleanup() {
            Task { await store.close() }
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// A real session (files on disk + indexed rows + a REAL sidecar writer):
    /// one STALE-thumb row (the GUI stale face) and one plain row.
    private func makeChainFixture() async throws -> ChainFixture {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-sc7-\(UUID().uuidString)", isDirectory: true)
        let sessionRoot = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent("Capture", isDirectory: true),
            withIntermediateDirectories: true)
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.reconcile(
            root: sessionRoot, scan: AsyncStream { $0.finish() })
        for name in ["chain-a.arw", "chain-b.arw"] {
            try Data(repeating: 0xAB, count: 32).write(
                to: sessionRoot.appendingPathComponent("Capture/\(name)"))
        }
        try await McpCullingToolsetTests.seedRow(
            store, path: "Capture/chain-a.arw", hasEdits: 1, thumbState: 3)
        try await McpCullingToolsetTests.seedRow(store, path: "Capture/chain-b.arw")
        // A REAL tier-B cache image: has_edits + a stale marker + a rendered
        // cache file → get_thumbnails serves it with stale:true (the fake
        // RAW bytes have no embedded preview, so the stale face needs the
        // rendered tier to be demonstrable at all).
        let gradient = McpCullingImageBudgetTests.makeGradientCGImage(width: 64, height: 48)
        _ = try ThumbnailDiskStore(sessionRoot: sessionRoot)
            .write(gradient, relPath: "Capture/chain-a.arw")
        return ChainFixture(store: store, root: root, sessionRoot: sessionRoot)
    }

    /// The SC#7 literal chain: HTTP host up → the launcher pulls a sentinel
    /// agent (a REAL child process over /bin/zsh -c + curl) which discovers
    /// the endpoint from the discovery file, connects, lists photos, reads
    /// the stale thumbnail face, writes rating=4 and exits — the write lands
    /// in the sidecar truth AND the index row, the agent's words land in the
    /// launcher log ring, the stop face is the honest not-running, and a
    /// DIRECT SDK client (entry 1, connected before the agent) shares the
    /// same host within the session cap — the dual-entry coexistence.
    func testSC7LauncherChainEndToEndWithDualEntry() async throws {
        let fixture = try await makeChainFixture()
        defer { fixture.cleanup() }
        let paths = McpEndpointPaths(
            directory: fixture.root.appendingPathComponent("endpoint"))
        let agentDir = fixture.root.appendingPathComponent("agent")
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        let writer = BatchSidecarWriter(root: fixture.sessionRoot, store: fixture.store)
        let metadata = MetadataService(
            root: fixture.sessionRoot, store: fixture.store, writer: writer)
        let context = McpCullingContext(
            store: { [store = fixture.store] in store },
            sessionRoot: { [sessionRoot = fixture.sessionRoot] in sessionRoot },
            metadata: { metadata },
            sidecarWriter: { writer },
            presets: { nil },
            liveRelPaths: { [] },
            thumbnailProvider: { nil },
            decodeImage: { _ in
                throw McpToolError.renderFailed("no decode leg in the chain test")
            },
            renderGate: McpRenderGate())
        let seams = EditingToolset.Seams(
            session: { [store = fixture.store, sessionRoot = fixture.sessionRoot] in
                (store, sessionRoot)
            },
            metal: { nil }, modules: { ModuleRegistry() },
            gate: McpRenderGate(), liveImageURL: { nil })
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, editing: seams, culling: context,
            searchState: McpSearchStateContext(),
            project: McpProjectContext())
        defer { Task { await handle.stop() } }

        // ── Entry 1: the DIRECT SDK client (already inside the cap). ──
        let endpoint = URL(string: "http://127.0.0.1:\(handle.port)/mcp")!
        let directTransport = HTTPClientTransport(endpoint: endpoint)
        let direct = MCP.Client(name: "direct-entry", version: "0.0.1")
        try await direct.connect(transport: directTransport)
        let directTools = try await direct.listTools().tools.map(\.name)
        XCTAssertEqual(directTools.count, 29, "the direct entry sees the full face")

        // ── Entry 2: the LAUNCHER pulls the sentinel agent. ──
        let script = Self.agentScript(agentDir: agentDir.path)
        let rendered = McpLauncherTemplate.render(
            command: script, prompt: nil, endpointPath: paths.jsonURL.path)
        let launcher = McpLauncher()
        let exitBox = ExitBox()
        launcher.onExit = { exitBox.set($0) }
        let pid = try launcher.start(
            renderedCommand: rendered.command,
            environment: ["LIGHTAMER_MCP": paths.jsonURL.path])
        XCTAssertEqual(launcher.runningPID, pid)

        // Cancellation-immune bounded wait (the pipe-pump pattern — a
        // Task.sleep-based wait would surface any spurious task
        // cancellation as a red test).
        let exited = Self.boundedWait(until: { exitBox.value != nil }, timeout: 60)
        XCTAssertTrue(exited, "the sentinel agent must exit on its own")
        XCTAssertEqual(exitBox.value, 0, "the agent chain must succeed end-to-end")
        XCTAssertFalse(launcher.isRunning)
        // The stop-button face after a finished session: honest no-op.
        XCTAssertEqual(launcher.stop(), .notRunning)

        // The log panel face: the agent's words rode the merged ring.
        let log = launcher.logBuffer.snapshot().joined(separator: "\n")
        XCTAssertTrue(log.contains("agent: discovered"), String(log.suffix(400)))
        XCTAssertTrue(log.contains("agent: listed"), String(log.suffix(400)))
        XCTAssertTrue(log.contains("AGENT-DONE"), String(log.suffix(400)))

        // The write landed in the sidecar truth AND the index row.
        let sidecarURL = LightamerSidecar.sidecarURL(
            for: fixture.sessionRoot.appendingPathComponent("Capture/chain-b.arw"))
        let document = try JSONDecoder().decode(
            LightamerSidecar.self, from: Data(contentsOf: sidecarURL))
        XCTAssertEqual(document.rating, 4, "sidecar truth")
        let row = try await fixture.store.fetchRow(relPath: "Capture/chain-b.arw")
        XCTAssertEqual(row?.rating, 4, "the index row (the GUI grid face reads it)")

        // The agent's captured responses carry the chain's semantics.
        let rateBody: String
        do {
            rateBody = try Self.sseJSONPayload(at: agentDir.appendingPathComponent("rate.sse"))
        } catch {
            throw error
        }
        XCTAssertTrue(
            rateBody.contains("appliedRelPaths") && rateBody.contains("chain-b"),
            "set_rating outcome: \(rateBody.prefix(300))")
        let thumbsBody: String
        do {
            thumbsBody = try Self.sseJSONPayload(
                at: agentDir.appendingPathComponent("thumbs.sse"))
        } catch {
            throw error
        }
        XCTAssertTrue(
            thumbsBody.contains("\"stale\" : true") || thumbsBody.contains("\"stale\":true")
                || thumbsBody.contains("stale"),
            "the stale marker rides get_thumbnails: \(thumbsBody.prefix(300))")
        let listBody: String
        do {
            listBody = try Self.sseJSONPayload(at: agentDir.appendingPathComponent("list.sse"))
        } catch {
            throw error
        }
        XCTAssertTrue(listBody.contains("chain-a") && listBody.contains("chain-b"))

        // The stale row itself (the GUI would show the stale badge; the
        // regenerate leg rides the provider queue — 14-3's tests).
        let staleRow: SessionIndexRow?
        do {
            staleRow = try await fixture.store.fetchRow(relPath: "Capture/chain-a.arw")
        } catch {
            throw error
        }
        XCTAssertEqual(
            staleRow?.thumbState,
            SessionIndexSchema.ThumbState.stale.rawValue)

        // Dual entry coexistence: the DIRECT client (still connected, the
        // launcher's agent session having come and gone INSIDE the cap of 4)
        // sees the agent's write — one server, two entries, one truth.
        let seen = try await direct.callTool(
            name: "list_photos",
            arguments: ["filter": .object([
                "schemaVersion": .int(1), "match": .string("all"),
                "rules": .array([.object([
                    "field": .string("rating"), "op": .string("eq"),
                    "value": .object(["kind": .string("int"), "value": .int(4)]),
                ])]),
            ])])
        XCTAssertNil(seen.isError)
        guard case .text(let directText) = McpAdapters.outputContent(from: seen.content[0]) else {
            return XCTFail("expected text")
        }
        // The MCP-side serializer escapes "/" — normalize before matching.
        let plain = directText.replacingOccurrences(of: "\\/", with: "/")
        XCTAssertTrue(
            plain.contains("Capture/chain-b.arw") && plain.contains("\"rating\":4"),
            "the direct entry sees the agent's write: \(plain)")
        await direct.disconnect()
    }

    /// The sentinel agent: a REAL user-side command (curl over the
    /// Streamable HTTP endpoint) — the exact shape the template placeholder
    /// flow produces for an external agent. Every curl is max-time bounded;
    /// `set -e` makes any failed leg a non-zero exit (the red face).
    private static func agentScript(agentDir: String) -> String {
        // NOTE: the child is zsh — NO implicit word splitting, so every
        // -H is spelled out per curl (no $JSON variable trick).
        let json = "-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream'"
        let session = "-H \"mcp-session-id: $SID\""
        return """
        set -e
        EP='{{LIGHTAMER_MCP}}'
        A='\(agentDir)'
        PORT=$(tr -d '[:space:]' < "$EP" | grep -o '"port":[0-9]*' | grep -o '[0-9]*$')
        URL="http://127.0.0.1:$PORT/mcp"
        echo "agent: discovered endpoint $URL"
        curl -s --max-time 20 -D "$A/h.ini" -o "$A/init.sse" -X POST "$URL" \(json) \
          -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"sentinel-agent","version":"0"}}}'
        SID=$(grep -i '^mcp-session-id:' "$A/h.ini" | tr -d '\\r' | awk '{print $2}')
        test -n "$SID"
        curl -s --max-time 20 -o /dev/null -X POST "$URL" \(json) \(session) \
          -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
        curl -s --max-time 20 -o "$A/list.sse" -X POST "$URL" \(json) \(session) \
          -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_photos","arguments":{"limit":10}}}'
        echo "agent: listed"
        curl -s --max-time 20 -o "$A/thumbs.sse" -X POST "$URL" \(json) \(session) \
          -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_thumbnails","arguments":{"relPaths":["Capture/chain-a.arw"]}}}'
        curl -s --max-time 20 -o "$A/rate.sse" -X POST "$URL" \(json) \(session) \
          -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"set_rating","arguments":{"relPaths":["Capture/chain-b.arw"],"rating":4}}}'
        echo "agent: rated"
        echo "AGENT-DONE"
        """
    }

    /// The first parseable `data:` JSON payload of an SSE response body
    /// (the request-scoped stream shape — one message per POST). Tolerant:
    /// empty payload lines are skipped and an unparseable body returns RAW
    /// (the assertions speak, the helper never red-herrings).
    private static func sseJSONPayload(at url: URL) throws -> String {
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count)
                .trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty,
                let object = try? JSONSerialization.jsonObject(
                    with: Data(payload.utf8), options: [.fragmentsAllowed])
            else { continue }
            // Re-render with sorted keys so the assertions survive the
            // encoder's key order.
            if let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys]) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return text
    }

    // MARK: - The 14-3 acceptance pin: the burst 2.0s boundary is INCLUSIVE

    /// The `<=` boundary: a gap of EXACTLY gapSeconds stays in one burst
    /// (the acceptance note — the old golden cut at 2.1s; 2.0 rides the
    /// inclusive comparison in the clustering code).
    func testBurstGapExactlyAtThresholdStays() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-burst-\(UUID().uuidString)", isDirectory: true)
        let sessionRoot = root.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await store.reconcile(
            root: sessionRoot, scan: AsyncStream { $0.finish() })
        defer { Task { await store.close() } }
        try await McpCullingToolsetTests.seedRow(
            store, path: "first.arw", cameraModel: "Canon", captureDate: 1_000)
        try await McpCullingToolsetTests.seedRow(
            store, path: "edge.arw", cameraModel: "Canon", captureDate: 1_002)

        let context = McpCullingContext(
            store: { store }, sessionRoot: { sessionRoot },
            decodeImage: { _ in
                throw McpToolError.renderFailed("no decode leg")
            })
        let registry = McpToolRegistry()
        await McpCullingToolset.registerAll(on: registry, context: context)
        let payload = try await McpCullingToolsetTests.callJSON(
            registry, name: "list_bursts", arguments: [:])
        let bursts = try XCTUnwrap(payload["bursts"] as? [[String: Any]])
        XCTAssertEqual(bursts.count, 1, "2.0s = exactly the default gap → stays")
        XCTAssertEqual(bursts.first?["count"] as? Int, 2)
    }

    // MARK: - helpers

    private static func waitUntil(
        timeout: TimeInterval, _ condition: @escaping @Sendable () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// The bounded poll on a plain loop (no sleep, no throws — immune to
    /// task cancellation).
    private static func boundedWait(
        until condition: @escaping @Sendable () -> Bool, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(50_000)
        }
        return condition()
    }

    private final class ExitBox: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        var value: Int32? {
            lock.lock(); defer { lock.unlock() }
            return status
        }
        func set(_ status: Int32) {
            lock.lock()
            self.status = status
            lock.unlock()
        }
    }
}
