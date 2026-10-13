import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import LightamerIOP
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// EditingToolset (Plan 14-2) — the MCP editing face, five tools:
//
//   render_preview  (T1)  renderedPlane → inline JPEG base64 (§RQ-14-4/8)
//   load_image      (T2)  stateless read view (planner ruling D5)
//   apply_params    (T2)  module-level upsert, three segments, GUI-live hard
//                         rejection
//   list_iops       (T3)  the handwritten per-op catalog (IopCatalog.swift)
//   export_image    (T4)  direct render → Session/Output (§RQ-14-11)
//
// PURE SWIFT CONSUMPTION FACE — zero new render code, zero new write paths,
// zero new queues (the plan's 接线 phase discipline):
//   • renders consume `QuickLookRenderer.renderedPlane` / `ExportRenderer
//     .render` verbatim (the L031 routed-queue + L014 fence discipline is
//     FIXED IN THE SOURCE; this file cannot even build a command queue);
//   • writes consume the `SessionBatchApplier` three segments (PresetApplier
//     :105-117 同构) — the sidecar bytes are never touched here;
//   • concurrency 1 for every render-class call rides the SHARED
//     `McpRenderGate` (14-1 base).
//
// Statelessness (D5, planner ruling): every tool carries its own `relPath`
// argument — the server holds NO session-level active handle, which dissolves
// the two-client load_image context-stomping problem wholesale (§RQ-14-14).
// ─────────────────────────────────────────────────────────────────────────────

enum EditingToolset {

    // MARK: - Constants (§RQ-14-8 budget table + D7; one place each)

    /// render_preview defaults (the budget table row: 1024px/q85 ≈ 1.5MB
    /// base64 — the token-efficiency line).
    static let previewDefaultLongEdge = 1024
    static let previewDefaultQuality = 85
    /// D7 (planner, 2026-09-28): the 4096 cap is CUT to 2048 — 4096/q90 =
    /// 5.5MB base64 / ~22K visual tokens per call; anything larger belongs
    /// to export_image (落盘), which the tool description says verbatim.
    static let previewMaxLongEdge = 2048
    static let previewMaxQuality = 90

    // MARK: - Seams (the App-layer reality, injected for tests)

    /// Everything the editing face consumes from the host process. The
    /// headless host, the GUI-embedded host and the tests assemble the SAME
    /// struct (the single-kernel × multi-host red line).
    struct Seams: Sendable {

        /// The open session (index store + ROOT URL). `nil` = no session —
        /// every tool answers `notSessionMember` (nothing is a member of a
        /// session that is not open).
        let session: @Sendable () async -> (store: SessionIndexStore, root: URL)?

        /// The GPU context (lazy — render-class tools only). `nil` answer =
        /// `renderFailed` ("renderer unavailable"), never a crash.
        let metal: @Sendable () async -> MetalContext?

        /// The POPULATED module registry (terminal trio + LightamerIOP —
        /// `LightamerIOPRegistry.populate` ran before this seam is built).
        let modules: @Sendable () async -> ModuleRegistry

        /// The render serial gate (concurrency 1, shared with 14-3's render
        /// class — ONE gate instance per server kernel).
        let gate: McpRenderGate

        /// The GUI-live judge (§RQ-14-3①): the editor's current image URL
        /// (MainActor hop inside the closure; nil headless). apply_params
        /// HARD-REJECTS a matching target (`imageLiveInEditor`).
        let liveImageURL: @Sendable () async -> URL?

        /// M2-1: the editing FACE the seams' registry was populated with
        /// (KD-1/KD-3) — `true` = the default face (the D1/D2 disable set
        /// is unregistered, so list_iops drops the 3 cataloged disabled
        /// entries and the pristine seed used by apply_params narrows with
        /// it). The production assembly (`McpServerController
        /// .makeEditingSeams`) derives this from the same
        /// `isFullFaceRequested` read that populated the registry — ONE
        /// switch, same source. Default `false` = full face: test seams
        /// and every existing construction keep the pre-M2-1 behavior
        /// (KD-2).
        var defaultFace: Bool = false

        /// The production yiyin injector seam (export_image `yiyin: true`).
        /// nil (headless/tests) + yiyin:true → `exportFailed` (the honest
        /// typed face — no silent degradation).
        var yiyinInjector: (@Sendable () async -> ExportYiyinInjector?)?

        /// Test seam: the shared decode leg (parity legs share ONE CIRAW
        /// decode — the speckle discipline). nil = `RAWDecoder`.
        var decodeLeg: QuickLookRenderer.DecodeLeg?

        /// Test seam: render-class timeout override (seconds). nil = the
        /// `McpTimeouts` production constants.
        var renderTimeoutOverride: Double?

        /// Test seam: apply_params timeout override (seconds). nil = the
        /// `McpTimeouts.apply` production constant (D-14-2-T6-1).
        var applyTimeoutOverride: Double?

        /// M6-1-01 T7 (KD-5, OQ-5): the project-lock probe — consulted
        /// AFTER the live-image judge on every write face (apply_params /
        /// export_image bodies; the culling write-five/preset frames and
        /// match_color carry their own on the context/seams). nil (the
        /// default) = no gate: every existing construction and test is
        /// zero-diff. NON-HOLDING by contract (`McpProjectLockVerdict`);
        /// the self-held exemption lives in the assembly closure.
        var projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)?

        /// The WRITE serial gate: apply_params runs under a FIFO mutex so
        /// two concurrent MCP writes never interleave their three segments
        /// (§RQ-14-14: write-face requests queue, they do not reject).
        var writeGate: McpRenderGate?

        init(
            session: @escaping @Sendable () async -> (store: SessionIndexStore, root: URL)?,
            metal: @escaping @Sendable () async -> MetalContext?,
            modules: @escaping @Sendable () async -> ModuleRegistry,
            gate: McpRenderGate = McpRenderGate(),
            liveImageURL: @escaping @Sendable () async -> URL? = { nil },
            defaultFace: Bool = false
        ) {
            self.session = session
            self.metal = metal
            self.modules = modules
            self.gate = gate
            self.liveImageURL = liveImageURL
            self.defaultFace = defaultFace
        }
    }

    // MARK: - Registration

    /// Registers the editing tools into `registry`. Each plan task extends
    /// this body; the snapshot tests pin every addition (the tool face IS a
    /// security face).
    static func register(into registry: McpToolRegistry, seams: Seams) async {
        await registry.register(
            loadImageDescriptor, requiresWriter: false,
            handler: { arguments in
                try await loadImageBody(arguments: arguments, seams: seams)
            })
        await registry.register(
            applyParamsDescriptor, requiresWriter: true,
            handler: { arguments in
                try await applyParamsBody(arguments: arguments, seams: seams)
            })
        await registerRenderPreview(into: registry, seams: seams)
        await registry.register(
            listIopsDescriptor, requiresWriter: false,
            handler: { [seams] _ in
                // M2-1: the catalog face rides the seams' editing face —
                // the SAME switch that populated the registry (KD-1), so
                // the agent's key reference never lists a key the write
                // face would reject.
                .text(try IopCatalog.catalogJSON(defaultFace: seams.defaultFace))
            })
        await registry.register(
            exportImageDescriptor, requiresWriter: true,
            handler: { arguments in
                try await exportImageBody(arguments: arguments, seams: seams)
            })
        await MatchColorToolset.register(into: registry, seams: seams)  // M5-1-03 T1: the whole implementation is MatchColorToolset.swift (sealed-face minimal diff — this file's only edit)
    }

    // MARK: - Shared argument faces

    /// The project-probe → typed-rejection hop (M6-1-01 KD-5; the copy
    /// single source is the verdict's `errorMessage`). A nil probe = no
    /// gate (every existing construction).
    static func rejectIfProjectReadOnly(
        _ probe: (@Sendable () async -> McpProjectLockVerdict)?
    ) async throws {
        guard let probe else { return }
        let verdict = await probe()
        if case .held = verdict {
            throw McpToolError.projectReadOnly(verdict.errorMessage)
        }
    }

    /// The required `relPath` argument (D5: every tool carries it).
    static func requiredRelPath(
        _ arguments: [String: McpJSON]
    ) throws -> String {
        guard let relPath = arguments["relPath"]?.stringValue, !relPath.isEmpty else {
            throw McpToolError.invalidParams(
                "relPath (string) is required — the editing tools are stateless "
                    + "(D5): every call names its image relative to the session root")
        }
        return relPath
    }

    /// Resolves the session + membership for `relPath` and returns the ABSOLUTE
    /// image URL. Not open → `notSessionMember`; not an indexed row →
    /// `notSessionMember` (the load_image scope is open-session members only,
    /// D-14-CONTEXT-6③).
    static func resolveMember(
        relPath: String, seams: Seams
    ) async throws -> (imageURL: URL, root: URL, store: SessionIndexStore) {
        guard let session = await seams.session() else {
            throw McpToolError.notSessionMember(
                "no Lightamer session is open on the server host")
        }
        let row = try await session.store.fetchRow(relPath: relPath)
        guard row != nil else {
            throw McpToolError.notSessionMember(
                "'\(relPath)' is not a member of the open session — load_image and "
                    + "every editing tool address open-session members by relPath only")
        }
        return (session.root.appendingPathComponent(relPath), session.root, session.store)
    }

    // MARK: - load_image (T2 — the stateless read view, planner ruling D5)

    private static let loadImageDescriptor = McpToolDescriptor(
        name: "load_image",
        description: String(localized: "mcp_tool_desc_load_image", defaultValue: String.LocalizationValue(
                    "Read an open-session image's SAVED edit state as a JSON view: the module "
                + "instance summary (opName/multiPriority/enabled per instance), layer "
                + "count, dimensions and orientation. STATELESS by design: no server-side "
                + "session handle is created — every tool names its image with relPath, "
                + "so multiple clients can interleave safely. The view reflects the last "
                + "SAVED sidecar state; and render_preview equally reflects the SAVED "
                + "edit state (GUI edits carry a ~2s debounce). Membership: relPath must "
                + "be an indexed member of the open session. Errors: notSessionMember.")),
        inputSchemaJSON:
            #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"}},"required":["relPath"]}"#,
        readOnlyHint: true)

    private static func loadImageBody(
        arguments: [String: McpJSON], seams: Seams
    ) async throws -> McpToolOutput {
        let relPath = try requiredRelPath(arguments)
        let member = try await resolveMember(relPath: relPath, seams: seams)
        let row = try await member.store.fetchRow(relPath: relPath)
        let document = ExportRenderer.readDocument(imageURL: member.imageURL)

        // The read view (§RQ-14-5②): the sidecar's instance summary — ids
        // and raw paramsData stay internal (cross-process meaningless).
        let instances: [[String: Any]] = (document?.instances ?? []).map { record in
            [
                "opName": record.opName,
                "multiPriority": record.multiPriority,
                "enabled": record.enabled,
            ]
        }
        var view: [String: Any] = [
            "relPath": relPath,
            "filename": member.imageURL.lastPathComponent,
            "instances": instances,
            "stateless": true,
            "note": "render_preview reflects the SAVED edit state (last sidecar write)",
        ]
        if let row {
            if let width = row.width { view["width"] = Int(width) }
            if let height = row.height { view["height"] = Int(height) }
            if let orientation = row.orientation { view["orientation"] = Int(orientation) }
            if let hasEdits = row.hasEdits { view["hasEdits"] = hasEdits != 0 }
            if let layerCount = row.layerCount { view["layerCount"] = Int(layerCount) }
        }
        let data = try JSONSerialization.data(
            withJSONObject: view, options: [.sortedKeys, .prettyPrinted])
        return .text(String(decoding: data, as: UTF8.self))
    }

    // MARK: - list_iops (T3 — the agent's params-key reference channel)

    private static let listIopsDescriptor = McpToolDescriptor(
        name: "list_iops",
        description: String(localized: "mcp_tool_desc_list_iops", defaultValue: String.LocalizationValue(
                    "List the cataloged iop modules with their parameter key schema: per op "
                + "the opName, display name, v50 iopOrder, a VERSION (refresh your "
                + "cache when it changes), the applicable domain and the params keys "
                + "with types. apply_params validates its params JSON against the "
                + "module's real Codable schema at call time — this catalog is the "
                + "runtime key REFERENCE that keeps that validation predictable. "
                + "Read-only, stateless, no errors beyond internalError.")),
        inputSchemaJSON: #"{"type":"object","properties":{},"required":[]}"#,
        readOnlyHint: true)

    // MARK: - export_image (T4 — direct render, Output pinned, §RQ-14-11)

    private static let exportImageDescriptor = McpToolDescriptor(
        name: "export_image",
        description: String(localized: "mcp_tool_desc_export_image", defaultValue: String.LocalizationValue(
                    "Export ONE open-session image to a FILE (the only tool that writes an "
                + "image to disk). The destination is SERVER-PINNED to the session's "
                + "Output/ directory — there is intentionally NO path argument; naming "
                + "derives from the source stem with -1/-2 collision increments (the "
                + "file lands atomically). Returns the ABSOLUTE path as text plus a "
                + "note: a remote client cannot read this machine's paths — use "
                + "render_preview for an inline view or reach the file via GUI/file "
                + "sharing. format: jpeg|png|tiff|heic|avif|webp (default jpeg; "
                + "quality applies to the lossy formats, 1...100 default 90). sizing: "
                + "{\"mode\":\"original\"} or {\"mode\":\"longEdge\"|\"shortEdge\","
                + "\"px\":N} (never upscaled). colorSpace: sRGB|displayP3|adobeRGB|"
                + "proPhoto|rec2020 (default sRGB). yiyin (default false) renders "
                + "through the image's existing yiyin panel configuration. Renders "
                + "the SAVED sidecar state. Errors: exportFailed, invalidParams, "
                + "notSessionMember, serverReadOnly.")),
        inputSchemaJSON:
            #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"format":{"type":"string","enum":["jpeg","png","tiff","heic","avif","webp"],"default":"jpeg"},"quality":{"type":"integer","minimum":1,"maximum":100,"default":90,"description":"Lossy formats only"},"sizing":{"type":"object","properties":{"mode":{"type":"string","enum":["original","longEdge","shortEdge"],"default":"original"},"px":{"type":"integer","minimum":1,"description":"Required for longEdge/shortEdge"}}},"colorSpace":{"type":"string","enum":["sRGB","displayP3","adobeRGB","proPhoto","rec2020"],"default":"sRGB"},"yiyin":{"type":"boolean","default":false,"description":"Render through the image's existing yiyin frame/watermark configuration"}},"required":["relPath"]}"#,
        destructiveHint: true)

    private static func exportImageBody(
        arguments: [String: McpJSON], seams: Seams
    ) async throws -> McpToolOutput {
        // M6-1-01 (KD-5): the project-lock probe at the write body's head
        // (export_image carries no live judge — the D8 asymmetry note).
        try await EditingToolset.rejectIfProjectReadOnly(seams.projectWriteProbe)
        let relPath = try requiredRelPath(arguments)
        let member = try await resolveMember(relPath: relPath, seams: seams)

        // Format + quality (v1: one knob per format — the six-format
        // registry's per-format parameter face, bit depths at their defaults).
        let formatName = arguments["format"]?.stringValue ?? "jpeg"
        let quality = try intArgument(
            arguments["quality"], name: "quality", default: 90, range: 1...100,
            overMessage: "quality is a percentage for the lossy formats")
        let format: ExportFormatSpec
        switch formatName {
        case "jpeg": format = .jpeg(quality: Double(quality) / 100.0)
        case "png": format = .png(bitDepth: .eight)
        case "tiff": format = .tiff(bitDepth: .eight, compression: .zip)
        case "heic": format = .heic(quality: Double(quality) / 100.0, bitDepth: .eight)
        case "avif": format = .avif(quality: Double(quality) / 100.0, bitDepth: .eight)
        case "webp": format = .webp(quality: Double(quality) / 100.0, lossless: false)
        default:
            throw McpToolError.invalidParams(
                "format '\(formatName)' is not one of jpeg|png|tiff|heic|avif|webp")
        }

        // Color space.
        let colorSpaceName = arguments["colorSpace"]?.stringValue ?? "sRGB"
        guard let colorSpace = ExportColorSpace(rawValue: colorSpaceName) else {
            throw McpToolError.invalidParams(
                "colorSpace '\(colorSpaceName)' is not one of "
                    + ExportColorSpace.allCases.map(\.rawValue).joined(separator: "|"))
        }

        // Sizing: original (default) or a never-upscaled long/short edge.
        var sizing = YiyinExportSettings()
        if let sizingArg = arguments["sizing"], sizingArg != .null {
            guard case .object(let sizingObject) = sizingArg else {
                throw McpToolError.invalidParams("sizing must be an object")
            }
            let mode = sizingObject["mode"]?.stringValue ?? "original"
            let px = sizingObject["px"]?.intValue
            switch mode {
            case "original": sizing = YiyinExportSettings()
            case "longEdge", "shortEdge":
                guard let px, px >= 1 else {
                    throw McpToolError.invalidParams(
                        "sizing mode '\(mode)' requires a positive px value")
                }
                sizing = YiyinExportSettings(
                    mode: mode == "longEdge"
                        ? .longEdge(px: px) : .shortEdge(px: px))
            default:
                throw McpToolError.invalidParams(
                    "sizing mode '\(mode)' is not one of original|longEdge|shortEdge")
            }
        }

        // The yiyin switch (EXP-05 shared configuration — ONE semantic: use
        // the image's existing panel configuration, no border detail params).
        let wantsYiyin = arguments["yiyin"]?.boolValue == true
        var variant = ExportVariant(
            sizing: sizing, format: format, colorSpace: colorSpace, yiyin: wantsYiyin)
        do {
            try variant.validate()
        } catch {
            throw McpToolError.invalidParams(String(describing: error))
        }
        // M2-9-03 (OQ-6): the metadata-policy default no longer mounts the
        // editing-summary XMP packet. THIS tool's interop contract pins the
        // packet (the toolset's behavior spec: "export lands in Output WITH
        // XMP" — the mount has ridden encodeStage since 14-2) — so the MCP
        // face opts in explicitly; the OQ-6 narrowing keeps applying to
        // paths that do not opt in (the GUI export faces, wired in M2-9-04).
        variant.metadataPolicy = ExportMetadataPolicy(editingHistory: true)
        let exportVariant = variant

        // The landing zone is SERVER-PINNED: Session/Output/ — the input
        // schema carries no path argument by construction (the negative test
        // self-proves the closed face).
        let outputDirectory = SessionLayout.outputDirectory(for: member.root)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true)
        let occupied = Set(
            (try? FileManager.default.contentsOfDirectory(
                atPath: outputDirectory.path)) ?? [])

        // The production injector seam (yiyin:true only). nil without the
        // seam = the typed exportFailed face — no silent degradation.
        let resolvedInjector: ExportYiyinInjector?
        if wantsYiyin {
            guard let provider = seams.yiyinInjector else {
                throw McpToolError.exportFailed(
                    "yiyin export is unavailable on this host (no injector seam)")
            }
            guard let injector = await provider() else {
                throw McpToolError.exportFailed(
                    "yiyin export is unavailable on this host (injector build failed)")
            }
            resolvedInjector = injector
        } else {
            resolvedInjector = nil
        }

        // DIRECT render (§RQ-14-11①): the ExportQueue's progress/cancel
        // semantics are too heavy for a single MCP export — concurrency
        // rides the render gate, atomic promotion rides encodeStage (L009),
        // and the XMP mount rides encodeStage with it.
        let modules = await seams.modules()
        return try await seams.gate.withRenderGate {
            let seconds = durationSeconds(McpTimeouts.export)
            do {
                let outcome = try await QuickLookRenderer.boundedWait(seconds: seconds) {
                    guard let metal = await seams.metal() else {
                        throw McpToolError.exportFailed(
                            "renderer unavailable on this host")
                    }
                    let request = ExportRenderer.Request(
                        imageURL: member.imageURL, destinationDirectory: outputDirectory,
                        occupiedNames: occupied, variant: exportVariant)
                    return try await ExportRenderer.render(
                        request: request, metal: metal, registry: modules,
                        decodeLeg: seams.decodeLeg, yiyinInjector: resolvedInjector)
                }
                let note =
                    "note: a remote client cannot read this machine's paths — use "
                    + "render_preview for an inline view, or reach the file via "
                    + "GUI/文件共享 (file sharing)"
                return .text(
                    "exported=\(outcome.destination.path) "
                        + "\(outcome.outputWidth)x\(outcome.outputHeight)\n\(note)")
            } catch let timeout as QuickLookRenderer.RenderTimeout {
                throw McpToolError.renderTimeout(
                    "export exceeded the \(timeout.seconds)s bounded wait — the GPU "
                        + "work is not cancelled mid-flight; the file lands only via "
                        + "the atomic promote, so a timed-out export leaves nothing")
            } catch let error as McpToolError {
                throw error
            } catch {
                throw McpToolError.exportFailed(
                    "export failed for '\(relPath)': \(error)")
            }
        }
    }


    // MARK: - apply_params (T2 — module-level upsert, three segments)

    private static let applyParamsDescriptor = McpToolDescriptor(
        name: "apply_params",
        description: String(localized: "mcp_tool_desc_apply_params", defaultValue: String.LocalizationValue(
                    "Apply module parameter edits to ONE open-session image (module-level "
                + "upsert, non-destructive: one undoable history commit on top). Each "
                + "op addresses an instance by (opName, multiPriority — default 0) and "
                + "may set `params` (partial JSON overlaid on the module's params), "
                + "flip `enabled`, or delete the instance with `\"remove\": true`. "
                + "Unknown op → unknownOp; unknown/mistyped key → invalidParams; "
                + "reset one module = apply its default params. The write lands BEFORE "
                + "this tool returns. HARD REJECTION: an image open in the Lightamer "
                + "editor answers imageLiveInEditor — ask the user to close it and "
                + "retry, or edit in the GUI (图像在编辑器中打开；请让用户关闭后重试，"
                + "或改用 GUI 操作). Params key reference: list_iops.")),
        inputSchemaJSON:
            #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"ops":{"type":"array","minItems":1,"description":"Module-level upserts","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer","default":0},"params":{"type":"object","description":"Partial params JSON overlaid on the instance (keys per list_iops)"},"enabled":{"type":"boolean"},"remove":{"type":"boolean","default":false}},"required":["opName"]}}},"required":["relPath","ops"]}"#,
        destructiveHint: true)

    /// One parsed `ops[]` entry.
    struct ParamOp: Sendable {
        var opName: String
        var multiPriority: Int
        var params: [String: McpJSON]?
        var enabled: Bool?
        var remove: Bool
    }

    private static func parseParamOps(_ arguments: [String: McpJSON]) throws -> [ParamOp] {
        guard case .array(let items)? = arguments["ops"], !items.isEmpty else {
            throw McpToolError.invalidParams(
                "ops (non-empty array of {opName, ...}) is required")
        }
        return try items.map { item in
            guard case .object(let object) = item else {
                throw McpToolError.invalidParams("each op must be an object")
            }
            guard let opName = object["opName"]?.stringValue, !opName.isEmpty else {
                throw McpToolError.invalidParams("each op requires a non-empty opName")
            }
            if object["remove"]?.boolValue == true, object["params"] != nil {
                throw McpToolError.invalidParams(
                    "op '\(opName)': remove and params are mutually exclusive")
            }
            let enabled: Bool?
            if case .bool(let value)? = object["enabled"] {
                enabled = value
            } else if object["enabled"] == nil || object["enabled"] == .null {
                enabled = nil
            } else {
                throw McpToolError.invalidParams(
                    "op '\(opName)': enabled must be a boolean")
            }
            let params: [String: McpJSON]?
            if let value = object["params"], value != .null {
                guard case .object(let members) = value else {
                    throw McpToolError.invalidParams(
                        "op '\(opName)': params must be an object")
                }
                params = members
            } else {
                params = nil
            }
            return ParamOp(
                opName: opName,
                multiPriority: object["multiPriority"]?.intValue ?? 0,
                params: params,
                enabled: enabled,
                remove: object["remove"]?.boolValue == true)
        }
    }

    private static func applyParamsBody(
        arguments: [String: McpJSON], seams: Seams
    ) async throws -> McpToolOutput {
        let relPath = try requiredRelPath(arguments)
        let ops = try parseParamOps(arguments)
        let member = try await resolveMember(relPath: relPath, seams: seams)

        // The WRITE gate: apply_params calls serialize against each other.
        let gate = seams.writeGate ?? McpRenderGate()
        return try await gate.withRenderGate {
            // GUI-live HARD rejection (single-image semantics — the 14-3
            // apply_preset batch face is the SOFT skip; D8 keeps them apart).
            // Deliberately OUTSIDE the apply budget: the judge is a fast
            // MainActor read, and the rejection must not race a timer.
            if let live = await seams.liveImageURL(),
                live.standardizedFileURL.path
                    == member.imageURL.standardizedFileURL.path
            {
                throw McpToolError.imageLiveInEditor(
                    "图像在 Lightamer 编辑器中打开；请让用户关闭后重试，或改用 GUI 操作"
                        + " / The image is open in the Lightamer editor; ask the "
                        + "user to close it and retry, or edit in the GUI instead")
            }

            // M6-1-01 (KD-5/OQ-5): the project-lock probe — AFTER the live
            // judge (the finer-grained criterion hits first; the生效值 hard
            // order). Still inside the gate, outside the apply budget.
            try await EditingToolset.rejectIfProjectReadOnly(seams.projectWriteProbe)

            // The apply body races the §RQ-14-14 timeout (`McpTimeouts.apply`
            // = 10s; D-14-2-T6-1): compose + claim + write + flush is all
            // local-disk work with a large margin — a timeout is the
            // internal-exception face (the 14-1 frozen error table is not
            // extended for it).
            let seconds = seams.applyTimeoutOverride
                ?? durationSeconds(McpTimeouts.apply)
            do {
                return try await QuickLookRenderer.boundedWait(seconds: seconds) {
                    // The upsert projection off the DISK truth (pristine =
                    // the editing seed — the editor's own fresh-load
                    // convention).
                    let modules = await seams.modules()
                    let document = ExportRenderer.readDocument(imageURL: member.imageURL)
                    let current: [ModuleInstance]
                    if let document {
                        current = document.instances
                    } else {
                        // The pristine seed rides the seams' editing face —
                        // the same switch that populated the registry
                        // (KD-1; the face itself is KD-3's
                        // isFullFaceRequested read in makeEditingSeams).
                        current = await Self.editingSeed(
                            modules: modules, defaultFace: seams.defaultFace)
                    }
                    let desired = try await Self.projectInstances(
                        current: current, ops: ops, modules: modules,
                        defaultFace: seams.defaultFace)

                    // Idempotence: an apply whose projection equals the
                    // current document writes NOTHING (byte-identical retries
                    // are safe, §RQ-14-5②).
                    if desired == current {
                        return McpToolOutput([.text(
                            "applied=nothing (already in the requested state) "
                                + "relPath=\(relPath)")])
                    }

                    let payload = PastePayload(
                        sourceImageID: UUID(), sourceURL: nil, instances: desired,
                        layerStack: document?.layerStack, copiedAt: Date())
                    let writer = BatchSidecarWriter(root: member.root, store: member.store)
                    let outcome = await SessionBatchApplier.apply(
                        root: member.root, relPaths: [relPath], payload: payload,
                        mode: .overwrite, seed: [], liveRelPaths: [],
                        store: member.store, writer: writer,
                        timestamp: Date(), label: "MCP apply_params")
                    guard outcome.appliedRelPaths.contains(relPath) else {
                        throw McpToolError.internalError(
                            "apply_params compose/claim did not land for '\(relPath)'")
                    }
                    // The write lands BEFORE the tool returns (the agent's
                    // next render_preview reads the new state, not a drain
                    // race).
                    await writer.flushForTeardown()
                    return McpToolOutput([.text(
                        "applied=\(relPath) ops=\(ops.count) "
                            + "(one undoable commit; render_preview now reflects it)")])
                }
            } catch let timeout as QuickLookRenderer.RenderTimeout {
                throw McpToolError.internalError(
                    "apply_params timed out after \(timeout.seconds)s for '\(relPath)' "
                        + "— the compose/claim/write pipeline did not answer; applies "
                        + "are idempotent, check load_image and retry once")
            }
        }
    }

    /// The pristine-load seed (the editor's own fresh-load convention —
    /// `LightamerApp.seedInstances`), v50-sorted. M2-1: `defaultFace: true`
    /// drops the D1/D2 disable set (KD-1); default `false` = full face
    /// (KD-2).
    static func editingSeed(
        modules: ModuleRegistry, defaultFace: Bool = false
    ) async -> [ModuleInstance] {
        let defaults = await modules.makeDefaultInstances()
            + LightamerIOPRegistry.editingDefaultInstances(
                defaultFace: defaultFace)
        return defaults.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    // MARK: - The upsert projection

    /// Projects `ops` onto `current`: same-key params replacement (merged
    /// over the CURRENT/default params), optional enable flip, optional
    /// removal, append for missing keys. The result is the DESIRED full
    /// instance set, v50-sorted. M2-1: `defaultFace` only shapes the
    /// CREATE merge base (the seed lookup) — a disabled op never reaches
    /// it (the makeBox addressing guard rejects the upsert first).
    static func projectInstances(
        current: [ModuleInstance], ops: [ParamOp], modules: ModuleRegistry,
        defaultFace: Bool = false
    ) async throws -> [ModuleInstance] {
        var instances = current
        for op in ops {
            // Addressability FIRST (a remove of an unknown op is still an
            // unknown op to the agent's mental model).
            let registered = await modules.makeBox(opName: op.opName) != nil
            guard registered || op.remove else {
                throw McpToolError.unknownOp(
                    "'\(op.opName)' is not a registered module — see list_iops")
            }
            let index = instances.firstIndex {
                $0.opName == op.opName && $0.multiPriority == op.multiPriority
            }
            if op.remove {
                if let index {
                    instances.remove(at: index)
                }
                continue
            }
            guard let index else {
                // CREATE: the module's default record is the merge base.
                guard var record = await Self.defaultRecord(
                    opName: op.opName, multiPriority: op.multiPriority,
                    modules: modules, defaultFace: defaultFace)
                else {
                    throw McpToolError.invalidParams(
                        "op '\(op.opName)' has no derivable default params — only an "
                            + "existing instance can be re-parameterized")
                }
                if let params = op.params {
                    try await Self.overlayParams(
                        onto: &record, overlay: params, modules: modules)
                }
                if let enabled = op.enabled { record.enabled = enabled }
                instances.append(record)
                continue
            }
            var record = instances[index]
            if let params = op.params {
                try await Self.overlayParams(
                    onto: &record, overlay: params, modules: modules)
            }
            if let enabled = op.enabled { record.enabled = enabled }
            instances[index] = record
        }
        return instances.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    /// The default instance record for `opName` (terminal trio + editing
    /// seed), or nil when the op ships no derivable defaults. M2-1: the
    /// face rides through to `editingDefaultInstances` (KD-2 default
    /// false = full face).
    static func defaultRecord(
        opName: String, multiPriority: Int, modules: ModuleRegistry,
        defaultFace: Bool = false
    ) async -> ModuleInstance? {
        let defaults = await modules.makeDefaultInstances()
            + LightamerIOPRegistry.editingDefaultInstances(
                defaultFace: defaultFace)
        guard let base = defaults.first(where: {
            $0.opName == opName && $0.multiPriority == 0
        }) else { return nil }
        var record = base
        record.id = UUID()
        record.multiPriority = multiPriority
        return record
    }

    /// Merges `overlay` onto the record's CURRENT params JSON and commits
    /// the result through the module's own Codable decode (the box is the
    /// typed decode authority — a decode failure is the typed
    /// `invalidParams` face with the op named).
    static func overlayParams(
        onto record: inout ModuleInstance, overlay: [String: McpJSON],
        modules: ModuleRegistry
    ) async throws {
        // Unknown-key rejection rides the catalog when the op is cataloged
        // (T3); the decode itself rejects mistyped values.
        let baseObject = (try? JSONSerialization.jsonObject(
            with: record.paramsData,
            options: [.fragmentsAllowed]) as? [String: Any]) ?? [:]
        var merged = baseObject
        for (key, value) in overlay {
            merged[key] = Self.jsonSerializationValue(value)
        }
        let data = try JSONSerialization.data(withJSONObject: merged, options: [])
        var candidate = record
        candidate.paramsData = data
        guard let box = await modules.makeBox(opName: record.opName, instanceID: record.id)
        else {
            throw McpToolError.unknownOp(
                "'\(record.opName)' is not a registered module — see list_iops")
        }
        do {
            try box.apply(candidate)
        } catch {
            throw McpToolError.invalidParams(
                "op '\(record.opName)': params decode failed (\(overlay.keys.joined(separator: ", "))) — "
                    + String(describing: error))
        }
        record.paramsData = box.paramsData
        record.paramsHash = box.paramsHash
    }

    /// `McpJSON` → a JSONSerialization-compatible value.
    static func jsonSerializationValue(_ value: McpJSON) -> Any {
        switch value {
        case .null: NSNull()
        case .bool(let b): NSNumber(value: b)
        case .int(let i): NSNumber(value: i)
        case .double(let d): NSNumber(value: d)
        case .string(let s): s
        case .array(let items): items.map(jsonSerializationValue)
        case .object(let members):
            members.mapValues(jsonSerializationValue)
        }
    }


    private static func registerRenderPreview(
        into registry: McpToolRegistry, seams: Seams
    ) async {
        await registry.register(
            McpToolDescriptor(
                name: "render_preview",
                description: String(localized: "mcp_tool_desc_render_preview", defaultValue: String.LocalizationValue(
                                    "Render an open-session image's SAVED edit state (the disk sidecar) "
                        + "and return it as an inline JPEG image (base64). The preview is "
                        + "the sRGB-encoded EDIT state — no yiyin frame/watermark, and NOT "
                        + "the GUI's EDR display domain. It reflects the last SAVED edit: "
                        + "edits saved by the GUI carry a ~2s debounce. Bounds: longEdge "
                        + "1...2048 (default 1024), quality 1...90 (default 85); for "
                        + "anything larger or for files on disk use export_image. Fails "
                        + "typed: renderFailed, renderTimeout (30s), notSessionMember, "
                        + "invalidParams. Errors for read-only hosts: serverReadOnly.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"}},"required":["relPath"]}"#,
                readOnlyHint: true
            ),
            handler: { arguments in
                let relPath = try requiredRelPath(arguments)
                let longEdge = try intArgument(
                    arguments["longEdge"], name: "longEdge",
                    default: previewDefaultLongEdge,
                    range: 1...previewMaxLongEdge,
                    overMessage:
                        "longEdge > \(previewMaxLongEdge) would inline a multi-megabyte "
                        + "base64 payload (D7); use export_image to land a larger file "
                        + "in Session/Output/")
                let quality = try intArgument(
                    arguments["quality"], name: "quality",
                    default: previewDefaultQuality,
                    range: 1...previewMaxQuality,
                    overMessage:
                        "quality > \(previewMaxQuality) — the inline preview cap is 90 "
                        + "(D7); use export_image for quality-critical output")
                let member = try await resolveMember(relPath: relPath, seams: seams)

                return try await seams.gate.withRenderGate {
                    try await renderPreviewBody(
                        imageURL: member.imageURL, longEdge: longEdge,
                        quality: quality, seams: seams)
                }
            })
    }

    /// The render body (INSIDE the gate): bounded wait → renderedPlane →
    /// CGImage → JPEG → base64. Typed failures, never the QL embedded-
    /// preview fallback (the MCP face has no preview to lie with).
    private static func renderPreviewBody(
        imageURL: URL, longEdge: Int, quality: Int, seams: Seams
    ) async throws -> McpToolOutput {
        let seconds = seams.renderTimeoutOverride
            ?? durationSeconds(McpTimeouts.renderAndCrop)
        do {
            let base64 = try await QuickLookRenderer.boundedWait(seconds: seconds) {
                guard let metal = await seams.metal() else {
                    throw McpToolError.renderFailed("renderer unavailable on this host")
                }
                let registry = await seams.modules()
                let rendered = try await QuickLookRenderer.renderedPlane(
                    imageURL: imageURL, targetLongEdge: longEdge,
                    metal: metal, registry: registry, decodeLeg: seams.decodeLeg)
                let image = try QuickLookRenderer.image(from: rendered)
                guard let jpeg = Self.encodeJPEG(image, quality: Double(quality) / 100.0),
                    !jpeg.isEmpty
                else {
                    throw McpToolError.renderFailed(
                        "JPEG encode failed for '\(imageURL.lastPathComponent)'")
                }
                return jpeg.base64EncodedString()
            }
            return McpToolOutput([.imageBase64(base64, mimeType: "image/jpeg")])
        } catch let timeout as QuickLookRenderer.RenderTimeout {
            throw McpToolError.renderTimeout(
                "render exceeded the \(timeout.seconds)s bounded wait for "
                    + "'\(imageURL.lastPathComponent)' — the GPU work is not cancelled "
                    + "mid-flight; retry once before giving up")
        } catch let error as McpToolError {
            throw error
        } catch {
            throw McpToolError.renderFailed(
                "render failed for '\(imageURL.lastPathComponent)': \(error)")
        }
    }

    // MARK: - Argument helpers

    /// `Duration` → seconds (the `boundedWait` TimeInterval face).
    static func durationSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    /// An optional integer argument with a default and an inclusive range.
    /// Out-of-range → `invalidParams` with the tool-facing guidance.
    static func intArgument(
        _ value: McpJSON?, name: String, default defaultValue: Int,
        range: ClosedRange<Int>, overMessage: String
    ) throws -> Int {
        guard let value, value != .null else { return defaultValue }
        guard let int = value.intValue else {
            throw McpToolError.invalidParams("\(name) must be an integer")
        }
        guard range.contains(int) else {
            throw McpToolError.invalidParams(
                "\(name)=\(int) outside \(range.lowerBound)...\(range.upperBound): "
                    + overMessage)
        }
        return int
    }

    // MARK: - JPEG encode (the inline leg's only new bytes)

    /// CGImage → JPEG Data via ImageIO (the same encoder family the thumbs
    /// cache uses). nil = the encode failed (caller → `renderFailed`).
    static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
