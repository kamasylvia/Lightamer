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
            // M7-5-01 (D-M7-5-3): state-changing (switches the editor
            // document) — the control gate applies despite requiresWriter:
            // false.
            requiresControl: true,
            handler: { arguments in
                try await loadImageBody(arguments: arguments, seams: seams)
            })
        await registry.register(
            applyParamsDescriptor, requiresWriter: true,
            requiresControl: true,
            handler: { arguments in
                try await applyParamsBody(arguments: arguments, seams: seams)
            })
        // M7-4-01 (MCP2-08): the cross-image copy/paste pair — copy = the
        // read-only enumeration preview, paste = the batch overwrite write
        // (the shared AdjustmentTransferCatalog face; the M2-8 dialog
        // model consumes the same Catalog).
        await registry.register(
            copyAdjustmentsDescriptor, requiresWriter: false,
            handler: { arguments in
                try await copyAdjustmentsBody(arguments: arguments, seams: seams)
            })
        await registry.register(
            pasteAdjustmentsDescriptor, requiresWriter: true,
            requiresControl: true,
            handler: { arguments in
                try await pasteAdjustmentsBody(arguments: arguments, seams: seams)
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
            listLutsDescriptor, requiresWriter: false,
            handler: { _ in
                // M7-3 (MCP2-05): the LUT library read face — the lut3d
                // module's library projection, list_iops 同族 (the
                // parameter-catalog family). LutLibraryStore.shared direct
                // read (the IOP-layer public singleton; the editing seams
                // need no new face). The in-memory projection under the
                // McpTimeouts.list window (a rescan is never triggered —
                // the tool projects the in-memory registry only).
                try await McpCullingToolset.withTimeout(
                    McpTimeouts.list,
                    McpToolError.internalError("list_luts timed out")
                ) {
                    let store = LutLibraryStore.shared
                    let keys = store.installedNames
                    let luts: [McpJSON] = keys.map { key in
                        var dict: [String: McpJSON] = [:]
                        let entry = store.entry(named: key)
                        dict["key"] = .string(key)
                        dict["name"] = .string(entry?.name ?? key)
                        dict["hash"] = .string(entry?.hash ?? "")
                        dict["is1D"] = .bool(entry?.is1D ?? false)
                        dict["size"] = .int(entry?.size ?? 0)
                        if let title = entry?.title { dict["title"] = .string(title) }
                        if let subdirectory = entry?.subdirectory {
                            dict["subdirectory"] = .string(subdirectory)
                        }
                        if let remembered = entry?.rememberedEncodings {
                            dict["rememberedEncodings"] = .object([
                                "input": .string(remembered.input.rawValue),
                                "output": .string(remembered.output.rawValue),
                            ])
                        }
                        return .object(dict)
                    }
                    let payload = McpJSON.object([
                        "libraryRoot": .string(store.lutsDirectory.path),
                        "total": .int(keys.count),
                        "luts": .array(luts),
                    ])
                    return McpToolOutput(
                        [.text(McpJSONSerialization.text(from: payload))])
                }
            })
        await registry.register(
            exportImageDescriptor, requiresWriter: true,
            requiresControl: true,
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

    /// M7-3 (MCP2-05): the LUT library read face — zero-input, read-only.
    /// The `key` IS the lut3d module params `lutName` addressing key for
    /// NEW writes (KD-1: root-relative POSIX).
    private static let listLutsDescriptor = McpToolDescriptor(
        name: "list_luts",
        description: String(localized: "mcp_tool_desc_list_luts", defaultValue: String.LocalizationValue(
                    "List the installed LUT library (READ-ONLY, flat list — no group "
                + "filtering in v1): per LUT the key, file name, content hash, "
                + "is1D, lattice size, optional title/subdirectory and the "
                + "remembered authoring-encoding pair. The key is the ADDRESSING "
                + "value: pass it as the lut3d module's params `lutName` for NEW "
                + "writes. libraryRoot is the library root the keys are relative "
                + "to. In a FRESH host the first call may block up to ~50s while "
                + "the LUT library preheats in the background — clients with "
                + "short timeouts should retry. Read-only, stateless, no errors "
                + "beyond internalError.")),
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
            #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"ops":{"type":"array","minItems":1,"description":"Module-level upserts","items":{"type":"object","properties":{"opName":{"type":"string"},"multiPriority":{"type":"integer","default":0},"params":{"type":"object","description":"Partial params JSON overlaid on the instance (keys per list_iops)"},"enabled":{"type":"boolean"},"remove":{"type":"boolean","default":false}},"required":["opName"]}},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to the history commit (distinct from the document-level note set via append_note)"}},"required":["relPath","ops"]}"#,
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
        // M7-4-01 (MCP2-09): the optional ITEM-level note rides the paste
        // commit (minLength 1 — the append_note face); author stamps "mcp".
        let note = try optionalNoteArgument(arguments)
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
                        timestamp: Date(), label: "MCP apply_params",
                        note: note, author: Self.mcpAuthorToken)
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

    // MARK: - copy_adjustments / paste_adjustments (M7-4-01, MCP2-08)

    /// D-M7-4-4: the fixed author token every MCP write commit stamps.
    static let mcpAuthorToken = "mcp"

    /// The per-target rejection reason tokens (M7-4-01 F7 — the FIXED
    /// token set; these are response-JSON strings, not the 16-case
    /// McpToolError table).
    private enum PasteRejectionReason {
        static let notSessionMember = "notSessionMember"
        static let imageLiveInEditor = "imageLiveInEditor"
        static let unreadableSidecar = "unreadableSidecar"
        static let internalError = "internalError"
    }

    /// An optional note argument (minLength 1 — the append_note face;
    /// nil/absent = no note field enters the commit bytes).
    private static func optionalNoteArgument(
        _ arguments: [String: McpJSON]
    ) throws -> String? {
        guard let value = arguments["note"], value != .null else { return nil }
        guard let string = value.stringValue, !string.isEmpty else {
            throw McpToolError.invalidParams(
                "note must be a non-empty string (minLength 1) — omit it to "
                    + "attach no item-level note")
        }
        return string
    }

    /// The `targets` argument (paste_adjustments): non-empty string array,
    /// ≤1000 (the write-five cap), DUPLICATES REJECTED (F10 — explicit >
    /// implicit: silent dedup would mask a caller bug).
    private static func pasteTargetsArgument(
        _ arguments: [String: McpJSON]
    ) throws -> [String] {
        guard let items = arguments["targets"]?.arrayValue, !items.isEmpty else {
            throw McpToolError.invalidParams(
                "targets must be a non-empty array of session relPaths")
        }
        guard items.count <= 1000 else {
            throw McpToolError.invalidParams(
                "targets accepts at most 1000 entries per request; page the call")
        }
        let paths = items.map(\.stringValue)
        guard paths.allSatisfy({ $0 != nil }) else {
            throw McpToolError.invalidParams("targets entries must be strings")
        }
        let targets = paths.map { $0! }
        if Set(targets).count != targets.count {
            throw McpToolError.invalidParams(
                "targets contains duplicate entries — each target must appear "
                    + "exactly once")
        }
        return targets
    }

    /// The optional `include` argument (paste_adjustments): instanceId
    /// UUID strings; nil/absent = every transferable instance.
    private static func pasteIncludeArgument(
        _ arguments: [String: McpJSON]
    ) throws -> Set<UUID>? {
        guard let items = arguments["include"]?.arrayValue else { return nil }
        var ids = Set<UUID>()
        for item in items {
            guard let raw = item.stringValue,
                let id = UUID(uuidString: raw)
            else {
                throw McpToolError.invalidParams(
                    "include entries must be instanceId UUID strings (the "
                        + "copy_adjustments answer's items[].instanceId)")
            }
            ids.insert(id)
        }
        return ids.isEmpty ? nil : ids
    }

    private static let copyAdjustmentsDescriptor = McpToolDescriptor(
        name: "copy_adjustments",
        description: String(localized: "mcp_tool_desc_copy_adjustments",
            defaultValue: String.LocalizationValue(
                "Read ONE source image's grade adjustments as a transfer "
            + "PREVIEW (READ-ONLY — no state is stored, no clipboard exists; "
            + "feed the answer's instanceIds to paste_adjustments' include "
            + "parameter). source: a library image id (digits) or an "
            + "open-session relPath. The answer enumerates the source's "
            + "ACTIVE chain (version picks go through paste_adjustments' "
            + "version parameter — versions[] lists the ids): every Grade "
            + "layer with its instances {instanceId, opName, multiPriority, "
            + "enabled, transferable}, the greyed non-transferable rows "
            + "VISIBLE (never silently swallowed), the DRT row presence and "
            + "the summary counts. NOTE LEVEL: the note field on "
            + "paste_adjustments is an ITEM-level edit note on the history "
            + "commit — distinct from the document-level note set via "
            + "append_note. Errors: notSessionMember (unknown id / no open "
            + "session), invalidParams.")),
        inputSchemaJSON:
            #"{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath"}},"required":["source"]}"#,
        readOnlyHint: true)

    private static let pasteAdjustmentsDescriptor = McpToolDescriptor(
        name: "paste_adjustments",
        description: String(localized: "mcp_tool_desc_paste_adjustments",
            defaultValue: String.LocalizationValue(
                "Paste ONE source image's grade adjustments onto MANY "
            + "open-session targets in ONE call (each target = one undoable "
            + "overwrite-paste commit; write lands BEFORE this tool returns). "
            + "source: a library image id (digits) or an open-session relPath "
            + "(the copy_adjustments addressing; re-read STATELESSLY — no "
            + "server clipboard). targets: 1...1000 open-session relPaths. "
            + "include: instanceId subset (default ALL transferable); "
            + "includeDrt: false drops the DRT row (default true); version: "
            + "a copy_adjustments versions[] id (default the active chain). "
            + "Masks restart their epoch on paste (source in-flight mask "
            + "writers never validate against pasted masks). Live targets "
            + "(open in the editor) are PER-TARGET REJECTED, never skipped. "
            + "The answer is a per-target ledger {relPath, status: "
            + "applied|rejected(reason)} — an all-rejected batch answers "
            + "appliedCount=0 honestly instead of throwing. NOTE LEVEL: the "
            + "note field is an ITEM-level edit note on each history commit "
            + "— distinct from the document-level note set via append_note. "
            + "Errors: invalidParams, notSessionMember, imageLiveInEditor, "
            + "projectReadOnly, serverReadOnly, internalError.")),
        inputSchemaJSON:
            #"{"type":"object","properties":{"source":{"type":"string","description":"A library image id (digits) or an open-session relPath (the copy_adjustments addressing)"},"targets":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":1000,"description":"Open-session relPaths to paste onto"},"note":{"type":"string","minLength":1,"description":"ITEM-level edit note attached to each history commit (distinct from the document-level note set via append_note)"},"include":{"type":"array","items":{"type":"string","format":"uuid"},"description":"instanceId subset from copy_adjustments (default: every transferable instance)"},"includeDrt":{"type":"boolean","default":true,"description":"false drops the source's DRT row"},"version":{"type":"string","description":"A copy_adjustments versions[] id (default: the active chain)"}},"required":["source","targets"]}"#,
        destructiveHint: true)

    /// copy_adjustments body: the source chain's enumeration PREVIEW (the
    /// shared Catalog face; no server state is written anywhere).
    private static func copyAdjustmentsBody(
        arguments: [String: McpJSON], seams: Seams
    ) async throws -> McpToolOutput {
        guard let source = arguments["source"]?.stringValue, !source.isEmpty else {
            throw McpToolError.invalidParams(
                "source (string) is required — a library image id (digits) or "
                    + "an open-session relPath")
        }
        return try await McpCullingToolset.withTimeout(
            McpTimeouts.list,
            McpToolError.internalError("copy_adjustments timed out")
        ) {
            let sourceURL = try await MatchColorToolset.resolveReference(
                source, seams: seams)
            let document = ExportRenderer.readDocument(imageURL: sourceURL)
            let chain = document?.history ?? HistoryStack()
            let snapshot = AdjustmentTransferCatalog.enumerateSnapshot(chain: chain)
            let drtRecord = chain.effectiveDrtRecord()

            let versions: [McpJSON] = (document?.versions ?? []).map { record in
                .object([
                    "id": .string(record.id.uuidString),
                    "name": .string(record.name),
                    "createdAt": .string(McpSearchStateToolset.iso8601(record.createdAt)),
                    "updatedAt": .string(McpSearchStateToolset.iso8601(record.updatedAt)),
                    // chain == nil means ACTIVE (its items ride the
                    // document's history key).
                    "active": .bool(record.chainStack == nil),
                ])
            }

            let grades: [McpJSON] = snapshot.nodes.map { node in
                let items: [McpJSON] = (snapshot.items[node.id] ?? []).map { item in
                    .object([
                        "instanceId": .string(item.instance.id.uuidString),
                        "opName": .string(item.instance.opName),
                        "multiPriority": .int(item.instance.multiPriority),
                        "enabled": .bool(item.instance.enabled),
                        "transferable": .bool(item.transferable),
                    ] as [String: McpJSON])
                }
                return .object([
                    "id": .string(node.id.uuidString),
                    "name": .string(node.name),
                    "chainCount": .int(node.chainCount),
                    "transferableCount": .int(node.transferableCount),
                    "items": .array(items),
                ] as [String: McpJSON])
            }
            let transferable = snapshot.nodes.reduce(0) { $0 + $1.transferableCount }
            let payload = McpJSON.object([
                "source": .string(source),
                "versions": .array(versions),
                "selectedVersion": document?.activeVersionID.map { .string($0) }
                    ?? .null,
                "grades": .array(grades),
                "drt": .object([
                    "present": .bool(drtRecord != nil),
                    "eligible": .bool(drtRecord != nil),
                ]),
                "summary": .object([
                    "grades": .int(snapshot.nodes.count),
                    "transferableItems": .int(transferable),
                    "drt": .bool(drtRecord != nil),
                ]),
            ])
            return McpToolOutput(
                [.text(McpJSONSerialization.text(from: payload))])
        }
    }

    /// paste_adjustments body: per-target prechecks in the gate, the
    /// stateless source re-read + payload build + the three-segment batch
    /// apply inside the applyBatch budget, flush BEFORE the answer (the
    /// apply_params write-lands-before-return contract, batch form).
    private static func pasteAdjustmentsBody(
        arguments: [String: McpJSON], seams: Seams
    ) async throws -> McpToolOutput {
        guard let source = arguments["source"]?.stringValue, !source.isEmpty else {
            throw McpToolError.invalidParams(
                "source (string) is required — a library image id (digits) or "
                    + "an open-session relPath")
        }
        let targets = try pasteTargetsArgument(arguments)
        let note = try optionalNoteArgument(arguments)
        let include = try pasteIncludeArgument(arguments)
        let includeDrt = arguments["includeDrt"]?.boolValue ?? true
        let version = arguments["version"]?.stringValue

        let gate = seams.writeGate ?? McpRenderGate()
        return try await gate.withRenderGate {
            // Per-target prechecks — fast local reads, OUTSIDE the apply
            // budget (the apply_params ordering: judge → probe → budget).
            var rejected: [String: String] = [:]
            var members: [String: (imageURL: URL, root: URL, store: SessionIndexStore)] = [:]
            for relPath in targets {
                do {
                    members[relPath] = try await resolveMember(
                        relPath: relPath, seams: seams)
                } catch {
                    // The membership miss is the per-target honest row (a
                    // batch never throws away the whole answer for one bad
                    // address).
                    rejected[relPath] = PasteRejectionReason.notSessionMember
                }
            }
            // GUI-live HARD rejection per target (NOT a skip — the MCP face
            // has no interactive layer to hand a live image to).
            let live = await seams.liveImageURL()?.standardizedFileURL.path
            for relPath in targets where members[relPath] != nil {
                if live == members[relPath]!.imageURL.standardizedFileURL.path {
                    rejected[relPath] = PasteRejectionReason.imageLiveInEditor
                    members[relPath] = nil
                }
            }
            let cleanTargets = targets.filter { members[$0] != nil }
            // Sendable-closure freeze: the budget window's body reads
            // SNAPSHOT values (the prechecks are done mutating by then).
            let rejectedSnapshot = rejected
            let membersSnapshot = members

            // The project-lock probe (whole call — a held project refuses
            // the entire paste, the apply_params semantics).
            try await EditingToolset.rejectIfProjectReadOnly(seams.projectWriteProbe)

            guard !cleanTargets.isEmpty else {
                return Self.pasteLedgerAnswer(
                    targets: targets, rejected: rejectedSnapshot, applied: [],
                    failed: [:], note: note)
            }

            let seconds = durationSeconds(McpTimeouts.applyBatch)
            do {
                return try await QuickLookRenderer.boundedWait(seconds: seconds) {
                    // The source chain: STATELESS re-read (no copy-answer
                    // cache — multi-client interleave safe).
                    let sourceURL = try await MatchColorToolset.resolveReference(
                        source, seams: seams)
                    guard let document = ExportRenderer.readDocument(
                        imageURL: sourceURL)
                    else {
                        // The source sidecar is unreadable — every compose
                        // would fail; the honest face is the all-rejected
                        // ledger.
                        var reasons = rejectedSnapshot
                        for relPath in cleanTargets {
                            reasons[relPath] =
                                PasteRejectionReason.unreadableSidecar
                        }
                        return Self.pasteLedgerAnswer(
                            targets: targets, rejected: reasons, applied: [],
                            failed: [:], note: note)
                    }
                    let chain = try Self.selectSourceChain(document, version: version)
                    let snapshot = AdjustmentTransferCatalog.enumerateSnapshot(
                        chain: chain)
                    var items = snapshot.items
                    if let include {
                        for (nodeID, list) in items {
                            items[nodeID] = list.map { item in
                                var item = item
                                if !include.contains(item.instance.id) {
                                    item.checked = false
                                }
                                return item
                            }
                        }
                    }
                    guard let transfer = AdjustmentTransferCatalog.buildPayload(
                        layerSnapshots: snapshot.layerSnapshots, items: items,
                        drtRecord: chain.effectiveDrtRecord(),
                        includeDrt: includeDrt)
                    else {
                        throw McpToolError.invalidParams(
                            "the source carries no transferable grade adjustments "
                                + "under the current selection — run "
                                + "copy_adjustments for the enumeration face")
                    }
                    let payload = PastePayload(
                        sourceImageID: UUID(), sourceURL: nil,
                        instances: transfer.records,
                        layerStack: transfer.snapshot.map(SidecarLayerStackRecord.init),
                        copiedAt: Date())

                    // The seed rides the editing face (the same switch that
                    // populated the registry — the「默认种子 + 载荷实例」
                    // overwrite acceptance).
                    let modules = await seams.modules()
                    let seed = await Self.editingSeed(
                        modules: modules, defaultFace: seams.defaultFace)
                    let first = membersSnapshot[cleanTargets[0]]!
                    let writer = BatchSidecarWriter(
                        root: first.root, store: first.store)
                    let outcome = await SessionBatchApplier.apply(
                        root: first.root, relPaths: cleanTargets,
                        payload: payload, mode: .overwrite, seed: seed,
                        liveRelPaths: [], store: first.store, writer: writer,
                        timestamp: Date(), label: "MCP paste_adjustments",
                        note: note, author: Self.mcpAuthorToken)
                    // The write lands BEFORE the tool returns (the agent's
                    // next get_history/render_preview reads the new state).
                    await writer.flushForTeardown()

                    var failed: [String: String] = [:]
                    for relPath in outcome.failedRelPaths {
                        failed[relPath] = Self.pasteFailureReason(
                            relPath: relPath, root: first.root)
                    }
                    return Self.pasteLedgerAnswer(
                        targets: targets, rejected: rejectedSnapshot,
                        applied: outcome.appliedRelPaths, failed: failed,
                        note: note)
                }
            } catch let timeout as QuickLookRenderer.RenderTimeout {
                throw McpToolError.internalError(
                    "paste_adjustments timed out after \(timeout.seconds)s — "
                        + "the compose/claim/write pipeline did not answer; pastes "
                        + "are idempotent, check get_history and retry once")
            }
        }
    }

    /// The source chain pick: absent/null version = the active chain (the
    /// document's history key); otherwise the matching version record's
    /// frozen chain. Unknown id = typed invalidParams.
    private static func selectSourceChain(
        _ document: LightamerSidecar, version: String?
    ) throws -> HistoryStack {
        guard let version, version != TransferSourceVersion.activeChainID else {
            return document.history
        }
        guard let record = document.versions?.first(where: {
            $0.id.uuidString == version
        }) else {
            throw McpToolError.invalidParams(
                "version '\(version)' is not a version of the source document — "
                    + "copy_adjustments lists the ids")
        }
        return record.chainStack ?? document.history
    }

    /// A compose/claim failure row's reason: an unreadable target sidecar
    /// = `unreadableSidecar`; anything else (the claim rollback face) =
    /// the `internalError` bucket (F7's fixed token set).
    private static func pasteFailureReason(relPath: String, root: URL) -> String {
        let sidecarURL = LightamerSidecar.sidecarURL(
            for: root.appendingPathComponent(relPath))
        if (try? Data(contentsOf: sidecarURL)) == nil {
            return PasteRejectionReason.unreadableSidecar
        }
        return PasteRejectionReason.internalError
    }

    /// The per-target ledger answer: {targets: [{relPath, status,
    /// reason?}], appliedCount, note, author} — an all-rejected batch is
    /// an honest appliedCount=0 answer, never a throw.
    private static func pasteLedgerAnswer(
        targets: [String],
        rejected: [String: String],
        applied: [String],
        failed: [String: String],
        note: String?
    ) -> McpToolOutput {
        let appliedSet = Set(applied)
        let rows: [McpJSON] = targets.map { relPath in
            var row: [String: McpJSON] = [
                "relPath": .string(relPath),
                "status": appliedSet.contains(relPath)
                    ? .string("applied") : .string("rejected"),
            ]
            if !appliedSet.contains(relPath) {
                row["reason"] = .string(
                    failed[relPath] ?? rejected[relPath]
                        ?? PasteRejectionReason.internalError)
            }
            return .object(row)
        }
        var payload: [String: McpJSON] = [
            "targets": .array(rows),
            "appliedCount": .int(applied.count),
            "author": .string(Self.mcpAuthorToken),
        ]
        payload["note"] = note.map { .string($0) } ?? .null
        return McpToolOutput(
            [.text(McpJSONSerialization.text(from: .object(payload)))])
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
                                    "Render an open-session image's SAVED edit state "
                        + "(the disk sidecar) and return it as an inline JPEG image "
                        + "(base64). The preview is the sRGB-encoded EDIT state — no "
                        + "yiyin frame/watermark, and NOT the GUI's EDR display domain. "
                        + "It reflects the last SAVED edit: edits saved by the GUI carry "
                        + "a ~2s debounce. Bounds: longEdge 1...2048 (default 1024), "
                        + "quality 1...90 (default 85); for anything larger or for files "
                        + "on disk use export_image. region (optional, normalized 0..1 "
                        + "{x,y,w,h}) crops the RENDERED output frame (orientation "
                        + "already normalized) AFTER the render — decoupled from "
                        + "longEdge; unlike get_detail_crop (the source-detail "
                        + "inspection: an absolute-pixel ROI at NATIVE resolution), "
                        + "region is a rendered-appearance ROI. compare (enum none|root, "
                        + "DEFAULT root) rides the pristine (edit-free) render along for "
                        + "the before/after loop: the content order is [current, root, "
                        + "text] — the summary JSON rides last. Both arms share the same "
                        + "region rect and the same 30s window. Payload budget: each arm "
                        + "≈1.5MB at 1024/q85 (dual-arm ≈3MB; the 2048/q90 cap dual-arm "
                        + "≈11MB — the typed cap holds, there is NO automatic downgrade; "
                        + "pass compare:none to halve). Fails typed: renderFailed, "
                        + "renderTimeout (30s), notSessionMember, invalidParams, "
                        + "roiOutOfBounds. Errors for read-only hosts: serverReadOnly.")),
                inputSchemaJSON:
                    #"{"type":"object","properties":{"relPath":{"type":"string","description":"Image path relative to the session root"},"longEdge":{"type":"integer","minimum":1,"maximum":2048,"default":1024,"description":"Output long edge in px (rendered in-pipe at this size)"},"quality":{"type":"integer","minimum":1,"maximum":90,"default":85,"description":"JPEG quality (percent)"},"region":{"type":"object","properties":{"x":{"type":"number","minimum":0,"maximum":1},"y":{"type":"number","minimum":0,"maximum":1},"w":{"type":"number","exclusiveMinimum":0,"maximum":1},"h":{"type":"number","exclusiveMinimum":0,"maximum":1}},"required":["x","y","w","h"],"description":"Normalized 0..1 ROI {x,y,w,h} relative to the RENDERED output frame (orientation already normalized); cropped after the render, decoupled from longEdge"},"compare":{"type":"string","enum":["none","root"],"default":"root","description":"none = the edited image only; root (default) = the pristine (edit-free) image rides along for the before/after loop"}},"required":["relPath"]}"#,
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
                let region = try PreviewRegion.decode(arguments["region"])
                let compare = try PreviewCompare.decode(arguments["compare"])
                let member = try await resolveMember(relPath: relPath, seams: seams)

                return try await seams.gate.withRenderGate {
                    try await renderPreviewBody(
                        imageURL: member.imageURL, longEdge: longEdge,
                        quality: quality, region: region, compare: compare,
                        seams: seams)
                }
            })
    }

    // MARK: - render_preview parameter faces (M7-3 T2/T3)

    /// The normalized 0..1 ROI (D-M7-3-2): object {x, y, w, h} all double,
    /// relative to the RENDERED output frame. nil = the parameter is absent
    /// (the pre-M7-3 single-image behavior, byte-identical).
    struct PreviewRegion: Equatable, Sendable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double

        static func decode(_ value: McpJSON?) throws -> PreviewRegion? {
            guard let value, !value.isNull else { return nil }
            guard case .object(let members) = value else {
                throw McpToolError.invalidParams(
                    "region must be an object {x, y, w, h} normalized 0..1")
            }
            func component(_ key: String) throws -> Double {
                guard let v = members[key]?.doubleValue else {
                    throw McpToolError.invalidParams(
                        "region.\(key) (double, normalized 0..1) is required")
                }
                return v
            }
            let x = try component("x")
            let y = try component("y")
            let w = try component("w")
            let h = try component("h")
            guard w > 0, h > 0 else {
                throw McpToolError.invalidParams(
                    "region needs positive w/h (got w=\(w), h=\(h) on the "
                        + "normalized 0..1 domain)")
            }
            guard x >= 0, y >= 0, x + w <= 1, y + h <= 1 else {
                throw McpToolError.roiOutOfBounds(
                    "region (\(x), \(y), \(w), \(h)) is outside the normalized "
                        + "0..1 domain (x ≥ 0, y ≥ 0, x+w ≤ 1, y+h ≤ 1 — the rect "
                        + "is relative to the rendered output frame)")
            }
            return PreviewRegion(x: x, y: y, w: w, h: h)
        }

        /// The crop pixel frame (M2 ruling): the normalized rect × the
        /// rendered plane's pixel size, ROUNDED, then intersected with the
        /// plane bounds (the round can push an exact x+w==1.0 edge one pixel
        /// past on non-power-of-two widths). A post-clamp zero-area frame is
        /// the typed invalidParams CARRYING the normalized values — a legal
        /// normalized input must never fall into the cropping-nil
        /// renderFailed fallback silently (detailCrop's renderFailed is the
        /// bail-out, not the spec).
        func croppingPixelRect(of image: CGImage) throws -> CGRect {
            let px = min(max((x * Double(image.width)).rounded(), 0),
                         Double(image.width))
            let py = min(max((y * Double(image.height)).rounded(), 0),
                         Double(image.height))
            let pw = min((w * Double(image.width)).rounded(),
                         Double(image.width) - px)
            let ph = min((h * Double(image.height)).rounded(),
                         Double(image.height) - py)
            guard pw >= 1, ph >= 1 else {
                throw McpToolError.invalidParams(
                    "region (\(x), \(y), \(w), \(h)) rounds to a zero-area pixel "
                        + "frame on the \(image.width)×\(image.height) render — "
                        + "widen the rect")
            }
            return CGRect(x: px, y: py, width: pw, height: ph)
        }

        /// The region crop of one rendered frame (the shared arm leg — the
        /// SAME rect rides both arms, Alcedo 同构). The cropping-nil
        /// renderFailed here is the bail-out, never the spec.
        static func cropped(_ image: CGImage, region: PreviewRegion) throws -> CGImage {
            let rect = try region.croppingPixelRect(of: image)
            guard let cropped = image.cropping(to: rect) else {
                throw McpToolError.renderFailed("region crop failed")
            }
            return cropped
        }
    }

    /// The compare arm (D-M7-3-3): enum none|root, DEFAULT root — the
    /// feedback loop's semantics IS the comparison, so a bare call carries
    /// the pristine arm along; `none` is the explicit payload-saving form
    /// (the pre-M7-3 single-image face, byte-identical).
    enum PreviewCompare: String, Sendable {
        case none
        case root

        static func decode(_ value: McpJSON?) throws -> PreviewCompare {
            guard let value, !value.isNull else { return .root }
            guard let raw = value.stringValue,
                let decoded = PreviewCompare(rawValue: raw)
            else {
                throw McpToolError.invalidParams(
                    "compare must be one of none|root (default root — the "
                        + "pristine arm rides along for the before/after loop)")
            }
            return decoded
        }
    }

    /// The render body (INSIDE the gate): bounded wait → renderedPlane →
    /// CGImage → region crop → JPEG → base64. Typed failures, never the QL
    /// embedded-preview fallback (the MCP face has no preview to lie with).
    /// M7-3 T3 (OQ-M7-3-3/OQ-M7-3-5): compare:root runs the SAME boundedWait
    /// window TWICE — the edited arm first, the pristine arm second, each a
    /// full renderedPlane decode-to-quantize pass (no shared decode) — and
    /// returns [current, root, text] with the summary JSON last.
    private static func renderPreviewBody(
        imageURL: URL, longEdge: Int, quality: Int,
        region: PreviewRegion?, compare: PreviewCompare,
        seams: Seams
    ) async throws -> McpToolOutput {
        let seconds = seams.renderTimeoutOverride
            ?? durationSeconds(McpTimeouts.renderAndCrop)
        do {
            let output = try await QuickLookRenderer.boundedWait(seconds: seconds) {
                guard let metal = await seams.metal() else {
                    throw McpToolError.renderFailed("renderer unavailable on this host")
                }
                let registry = await seams.modules()
                // The edited arm (the pre-M7-3 face verbatim).
                let rendered = try await QuickLookRenderer.renderedPlane(
                    imageURL: imageURL, targetLongEdge: longEdge,
                    metal: metal, registry: registry, decodeLeg: seams.decodeLeg)
                var currentImage = try QuickLookRenderer.image(from: rendered)
                if let region {
                    currentImage = try PreviewRegion.cropped(currentImage, region: region)
                }
                guard let currentJPEG = Self.encodeJPEG(
                        currentImage, quality: Double(quality) / 100.0),
                    !currentJPEG.isEmpty
                else {
                    throw McpToolError.renderFailed(
                        "JPEG encode failed for '\(imageURL.lastPathComponent)'")
                }
                var contents: [McpToolOutput.Content] = [
                    .imageBase64(currentJPEG.base64EncodedString(),
                                 mimeType: "image/jpeg")
                ]

                // The pristine arm (the D-M7-3-3 default): the SAME renderer
                // verbatim with the pristine-only flag, its OWN decode.
                if compare == .root {
                    let pristine = try await QuickLookRenderer.renderedPlane(
                        imageURL: imageURL, targetLongEdge: longEdge,
                        metal: metal, registry: registry,
                        decodeLeg: seams.decodeLeg, pristineOnly: true)
                    var rootImage = try QuickLookRenderer.image(from: pristine)
                    if let region {
                        rootImage = try PreviewRegion.cropped(rootImage, region: region)
                    }
                    guard let rootJPEG = Self.encodeJPEG(
                            rootImage, quality: Double(quality) / 100.0),
                        !rootJPEG.isEmpty
                    else {
                        throw McpToolError.renderFailed(
                            "JPEG encode failed for the pristine arm of "
                                + "'\(imageURL.lastPathComponent)'")
                    }
                    contents.append(
                        .imageBase64(rootJPEG.base64EncodedString(),
                                     mimeType: "image/jpeg"))
                    contents.append(.text(McpJSONSerialization.text(from: .object([
                        "current": .object([
                            "width": .int(currentImage.width),
                            "height": .int(currentImage.height),
                        ]),
                        "root": .object([
                            "width": .int(rootImage.width),
                            "height": .int(rootImage.height),
                        ]),
                        "compare": .string("root"),
                    ]))))
                }
                return McpToolOutput(contents)
            }
            return output
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
