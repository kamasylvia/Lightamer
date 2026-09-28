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

        /// The WRITE serial gate: apply_params runs under a FIFO mutex so
        /// two concurrent MCP writes never interleave their three segments
        /// (§RQ-14-14: write-face requests queue, they do not reject).
        var writeGate: McpRenderGate?

        init(
            session: @escaping @Sendable () async -> (store: SessionIndexStore, root: URL)?,
            metal: @escaping @Sendable () async -> MetalContext?,
            modules: @escaping @Sendable () async -> ModuleRegistry,
            gate: McpRenderGate = McpRenderGate(),
            liveImageURL: @escaping @Sendable () async -> URL? = { nil }
        ) {
            self.session = session
            self.metal = metal
            self.modules = modules
            self.gate = gate
            self.liveImageURL = liveImageURL
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
    }

    // MARK: - Shared argument faces

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
        description:
            "Read an open-session image's SAVED edit state as a JSON view: the module "
                + "instance summary (opName/multiPriority/enabled per instance), layer "
                + "count, dimensions and orientation. STATELESS by design: no server-side "
                + "session handle is created — every tool names its image with relPath, "
                + "so multiple clients can interleave safely. The view reflects the last "
                + "SAVED sidecar state; and render_preview equally reflects the SAVED "
                + "edit state (GUI edits carry a ~2s debounce). Membership: relPath must "
                + "be an indexed member of the open session. Errors: notSessionMember.",
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

    // MARK: - apply_params (T2 — module-level upsert, three segments)

    private static let applyParamsDescriptor = McpToolDescriptor(
        name: "apply_params",
        description:
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
                + "或改用 GUI 操作). Params key reference: list_iops.",
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
            if let live = await seams.liveImageURL(),
                live.standardizedFileURL.path
                    == member.imageURL.standardizedFileURL.path
            {
                throw McpToolError.imageLiveInEditor(
                    "图像在 Lightamer 编辑器中打开；请让用户关闭后重试，或改用 GUI 操作"
                        + " / The image is open in the Lightamer editor; ask the "
                        + "user to close it and retry, or edit in the GUI instead")
            }

            // The upsert projection off the DISK truth (pristine = the
            // editing seed — the editor's own fresh-load convention).
            let modules = await seams.modules()
            let document = ExportRenderer.readDocument(imageURL: member.imageURL)
            let current: [ModuleInstance]
            if let document {
                current = document.instances
            } else {
                current = await Self.editingSeed(modules: modules)
            }
            let desired = try await Self.projectInstances(
                current: current, ops: ops, modules: modules)

            // Idempotence: an apply whose projection equals the current
            // document writes NOTHING (byte-identical retries are safe,
            // §RQ-14-5②).
            if desired == current {
                return .text(
                    "applied=nothing (already in the requested state) relPath=\(relPath)")
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
            // The write lands BEFORE the tool returns (the agent's next
            // render_preview reads the new state, not a drain race).
            await writer.flushForTeardown()
            return .text(
                "applied=\(relPath) ops=\(ops.count) "
                    + "(one undoable commit; render_preview now reflects it)")
        }
    }

    /// The pristine-load seed (the editor's own fresh-load convention —
    /// `LightamerApp.seedInstances`), v50-sorted.
    static func editingSeed(modules: ModuleRegistry) async -> [ModuleInstance] {
        let defaults = await modules.makeDefaultInstances()
            + LightamerIOPRegistry.editingDefaultInstances()
        return defaults.sorted {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
    }

    // MARK: - The upsert projection

    /// Projects `ops` onto `current`: same-key params replacement (merged
    /// over the CURRENT/default params), optional enable flip, optional
    /// removal, append for missing keys. The result is the DESIRED full
    /// instance set, v50-sorted.
    static func projectInstances(
        current: [ModuleInstance], ops: [ParamOp], modules: ModuleRegistry
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
                    modules: modules)
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
    /// seed), or nil when the op ships no derivable defaults.
    static func defaultRecord(
        opName: String, multiPriority: Int, modules: ModuleRegistry
    ) async -> ModuleInstance? {
        let defaults = await modules.makeDefaultInstances()
            + LightamerIOPRegistry.editingDefaultInstances()
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
                description:
                    "Render an open-session image's SAVED edit state (the disk sidecar) "
                        + "and return it as an inline JPEG image (base64). The preview is "
                        + "the sRGB-encoded EDIT state — no yiyin frame/watermark, and NOT "
                        + "the GUI's EDR display domain. It reflects the last SAVED edit: "
                        + "edits saved by the GUI carry a ~2s debounce. Bounds: longEdge "
                        + "1...2048 (default 1024), quality 1...90 (default 85); for "
                        + "anything larger or for files on disk use export_image. Fails "
                        + "typed: renderFailed, renderTimeout (30s), notSessionMember, "
                        + "invalidParams. Errors for read-only hosts: serverReadOnly.",
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
