import Foundation
import LightamerCore
import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────────
// MatchColorToolset (Plan M5-1-03 T1, KD-1; MCP-09 research item C) — the
// TRACK color-match orchestration tool: ONE tool, `match_color`, the OQ-6
// minimal face:
//
//   match_color(reference, targets?, strength?, solver?, attach?)
//
//   • reference = a library image id (digits → LibraryStore.image →
//     ImageLinker.resolve) or an open-session relPath (load_image 语义同源
//     resolveMember); v1 carries ONE reference per call (the OQ-6 ruling —
//     multi-reference pooling is the GUI panel face, M5-1-02).
//   • targets default = the editor's current image (the GUI-live judge);
//     an array = a batch (the tool fans out — N targets = N INDEPENDENT
//     solves, one per target's own source statistics against the SAME
//     reference statistics; differing solutions are the design semantic).
//   • attach = true (default) lands a colormatch instance per target via
//     the STORE-LEVEL projection seam (ColorMatchService.projectColormatch,
//     the apply_params projectInstances 同缝) + one SessionBatchApplier
//     write (the M5-1-02 handoff §9 shape); attach = false returns the
//     params group for the agent to land via apply_params.
//   • tuning/verification/metadata ride the EXISTING tools (apply_params /
//     render_preview / list_iops) — zero new face beyond this one tool.
//
// PURE CONSUMPTION FACE (the EditingToolset red line, transplanted):
//   • extraction = the M5-1-02 PIPELINE-LEVEL API `ColorMatchService
//     .extractStats(document:bucket:)` verbatim (in-pipe headless render +
//     readback + P1 pure functions) — zero new extraction path (checker E6);
//   • solve = the Core pure functions verbatim (ColorMatchSolver /
//     ColorMatchCDFSolver / ColorMatchPooling is unnecessary at N=1 — the
//     single-reference pool IS the identity pool); the `.cdf` asset commit
//     rides ColormatchCubeAsset exactly as the service's attach does;
//   • writes = SessionBatchApplier (the apply_params three-segment write —
//     sidecar bytes never touched here);
//   • concurrency 1 for the whole render-class call rides the SHARED
//     `McpRenderGate` (§RQ-14-13); the timeout is the render tier.
//
// DETERMINISM DISCLOSURE (G1, the agent-facing promise): the same
// reference + target + parameters produce the same solveHash — the tool
// returns it as a decimal string so a remote agent can re-verify.
//
// License red line: the tool text above is self-written; LumaRescue
// text/code is never copied (RESEARCH-NOTES §1.3).
// ─────────────────────────────────────────────────────────────────────────────

enum MatchColorToolset {

    /// The batch cap (the get_contact_sheet precedent — every target is a
    /// full decode + extraction render + solve + write; larger batches are
    /// the agent's job to split across calls).
    static let maxTargets = 30

    // MARK: - Descriptor

    static let descriptor = McpToolDescriptor(
        name: "match_color",
        description: String(localized: "mcp_tool_desc_match_color", defaultValue: String.LocalizationValue(
                    "Match ONE reference image's color distribution onto one or more "
                + "target images (the TRACK solve family): extract Oklab statistics "
                + "from the pristine reference and each target's current edit chain, "
                + "solve per target, and land a colormatch module instance per target "
                + "(one undoable write per target, before this tool returns). Batch "
                + "semantics: each target is solved INDEPENDENTLY against the same "
                + "reference statistics — the solutions legitimately differ per target. "
                + "reference: a library image id (digits) or an open-session relPath; "
                + "one reference per call. targets: one relPath or an array (max 30); "
                + "default = the editor's current image. solver: gaussian-ot (default) "
                + "| reinhard | cdf. strength: 0...1 (default 1) — the solve/identity "
                + "blend. attach: true (default) = land the colormatch instance and "
                + "return {instanceId, params summary, solveHash}; false = return the "
                + "params group only — land it yourself with apply_params (a cdf "
                + "solution carries assetRef/assetHash: the derived .cube asset is "
                + "written beside the TARGET image and the ref is only valid there). "
                + "Fine-tuning after attach = apply_params (e.g. params {\"strength\":"
                + "0.7}); visual check = render_preview; key reference = list_iops. "
                + "Deterministic: the same reference/target/parameters give the same "
                + "solveHash (decimal string) — re-call and compare. Errors: "
                + "notSessionMember (reference/target not addressable), "
                + "imageLiveInEditor (an attach target open in the editor), "
                + "invalidParams, renderFailed, renderTimeout.")),
        inputSchemaJSON:
            #"{"type":"object","properties":{"reference":{"type":"string","description":"Reference image: a library image id (digits) or an open-session relPath"},"targets":{"oneOf":[{"type":"string"},{"type":"array","items":{"type":"string"}}],"maxItems":30,"description":"Target relPath(s) relative to the session root; default = the editor's current image"},"strength":{"type":"number","minimum":0,"maximum":1,"default":1,"description":"The solve/identity blend"},"solver":{"type":"string","enum":["gaussian-ot","reinhard","cdf"],"default":"gaussian-ot"},"attach":{"type":"boolean","default":true,"description":"false = return the params for apply_params instead of writing"}},"required":["reference"]}"#,
        destructiveHint: true)

    // MARK: - Host seams (the boxes the assemblies install; tests inject)

    /// The open-library seam for the id-form reference: the GUI assembly
    /// installs the open project's (store, package URL); nil = the id form
    /// answers the typed `notSessionMember` (ids address an OPEN library,
    /// the session-scope honesty). Lock-guarded (set once at assembly).
    private static let libraryLock = NSLock()
    nonisolated(unsafe) private static var libraryProviderBox:
        (@Sendable () async -> (library: LibraryStore, projectDirectory: URL)?)?

    static func installLibraryProvider(
        _ provider: (@Sendable () async -> (library: LibraryStore, projectDirectory: URL)?)?
    ) {
        libraryLock.lock()
        libraryProviderBox = provider
        libraryLock.unlock()
    }

    static func libraryProvider() async -> (
        library: LibraryStore, projectDirectory: URL
    )? {
        let provider = libraryLock.withLock { libraryProviderBox }
        return await provider?()
    }

    /// The colormatch service box (ONE per process — the
    /// `ColormatchResolverBox.shared` contract). The GUI assembly installs
    /// the app-scoped service; a headless host lazily builds a standalone
    /// one from the seams' pipe faces (and installs its resolver into the
    /// shared box — the CDF curves and asset recovery ride it at render
    /// time, in-process).
    private static let serviceLock = NSLock()
    nonisolated(unsafe) private static var installedService: ColorMatchService?
    nonisolated(unsafe) private static var standaloneService: ColorMatchService?

    static func installColorMatchService(_ service: ColorMatchService) {
        serviceLock.lock()
        installedService = service
        serviceLock.unlock()
    }

    @MainActor
    static func service(
        seams: EditingToolset.Seams
    ) async throws -> ColorMatchService {
        if let installed = serviceLock.withLock({ installedService }) {
            return installed
        }
        if let standalone = serviceLock.withLock({ standaloneService }) {
            return standalone
        }
        guard let metal = await seams.metal() else {
            throw McpToolError.renderFailed("renderer unavailable on this host")
        }
        let registry = await seams.modules()
        let service = ColorMatchService(metal: metal, registry: registry)
        // The headless posture: this process's ONE service — the resolver
        // goes into the shared box (the app assembly's configure() 同形).
        service.configure(metal: metal, registry: registry)
        serviceLock.withLock { standaloneService = service }
        return service
    }

    /// Test/QA reset (the boxes are process-wide; the suite isolates via
    /// explicit installs).
    static func resetForTesting() {
        libraryLock.withLock { libraryProviderBox = nil }
        serviceLock.withLock {
            installedService = nil
            standaloneService = nil
        }
    }

    // MARK: - Registration

    static func register(into registry: McpToolRegistry, seams: EditingToolset.Seams) async {
        await registry.register(
            descriptor, requiresWriter: true,
            handler: { arguments in
                try await body(arguments: arguments, seams: seams)
            })
    }

    // MARK: - Argument parsing

    /// A required non-empty string argument.
    private static func requiredString(
        _ value: McpJSON?, name: String
    ) throws -> String {
        guard let string = value?.stringValue, !string.isEmpty else {
            throw McpToolError.invalidParams(
                "\(name) (string) is required — match_color names its reference "
                    + "by library image id or open-session relPath")
        }
        return string
    }

    /// An optional number argument with a default and an inclusive range
    /// (the intArgument 体例, real-valued).
    static func doubleArgument(
        _ value: McpJSON?, name: String, default defaultValue: Double,
        range: ClosedRange<Double>
    ) throws -> Double {
        guard let value, value != .null else { return defaultValue }
        let number: Double?
        switch value {
        case .int(let int): number = Double(int)
        case .double(let double): number = double
        default: number = nil
        }
        guard let number else {
            throw McpToolError.invalidParams("\(name) must be a number")
        }
        guard number.isFinite, range.contains(number) else {
            throw McpToolError.invalidParams(
                "\(name)=\(number) outside \(range.lowerBound)...\(range.upperBound)")
        }
        return number
    }

    /// The solver face: the schema enum spelling (`gaussian-ot`) → the
    /// module's `ColorMatchSolverKind` raw values.
    static func parseSolver(_ value: McpJSON?) throws -> ColorMatchSolverKind {
        guard let name = value?.stringValue else { return .gaussianOT }
        switch name {
        case "gaussian-ot": return .gaussianOT
        case "reinhard": return .reinhard
        case "cdf": return .cdf
        default:
            throw McpToolError.invalidParams(
                "solver '\(name)' is not one of gaussian-ot|reinhard|cdf")
        }
    }

    /// `targets`: absent/null → nil (the current-image default); a string →
    /// one; an array of non-empty strings → the batch.
    static func parseTargets(_ value: McpJSON?) throws -> [String]? {
        switch value {
        case nil, .null:
            return nil
        case .string(let single):
            guard !single.isEmpty else {
                throw McpToolError.invalidParams("targets must be non-empty")
            }
            return [single]
        case .array(let items):
            let targets = try items.map { item -> String in
                guard case .string(let relPath) = item, !relPath.isEmpty else {
                    throw McpToolError.invalidParams(
                        "every target must be a non-empty string relPath")
                }
                return relPath
            }
            return targets
        default:
            throw McpToolError.invalidParams(
                "targets must be a string or an array of strings")
        }
    }

    /// The digits-only id form (everything else rides the relPath form —
    /// a non-member path then answers the typed `notSessionMember`).
    static func libraryImageID(_ reference: String) -> Int64? {
        guard !reference.isEmpty, reference.allSatisfy(\.isNumber) else { return nil }
        return Int64(reference)
    }

    // MARK: - The body

    private static func body(
        arguments: [String: McpJSON], seams: EditingToolset.Seams
    ) async throws -> McpToolOutput {
        let reference = try requiredString(arguments["reference"], name: "reference")
        let explicitTargets = try parseTargets(arguments["targets"])
        let strength = try doubleArgument(
            arguments["strength"], name: "strength", default: 1.0, range: 0...1)
        let solver = try parseSolver(arguments["solver"])
        let attach = arguments["attach"]?.boolValue ?? true

        // The targets (cheap, argument-level — before any GPU work):
        // explicit, or the editor's current image mapped to its session
        // relPath (the "缺省当前图" ruling; stateless D5 — no server-side
        // active handle beyond the GUI-live judge).
        let targetRelPaths: [String]
        if let explicitTargets {
            targetRelPaths = explicitTargets
        } else if let live = await seams.liveImageURL(),
            let session = await seams.session(),
            live.standardizedFileURL.path.hasPrefix(
                session.root.standardizedFileURL.path + "/")
        {
            let base = session.root.standardizedFileURL.path
            targetRelPaths = [String(live.standardizedFileURL.path.dropFirst(base.count + 1))]
        } else {
            throw McpToolError.invalidParams(
                "targets is required when no editor image is addressable — match_color "
                    + "is stateless (D5): name the target images by open-session relPath")
        }
        guard !targetRelPaths.isEmpty else {
            throw McpToolError.invalidParams("targets must not be empty")
        }
        guard targetRelPaths.count <= maxTargets else {
            throw McpToolError.invalidParams(
                "targets batch of \(targetRelPaths.count) exceeds the \(maxTargets) cap — "
                    + "split across calls (every target is a full decode + solve + write)")
        }

        // The render-class discipline (§RQ-14-13): the whole call — N
        // decodes, N extraction renders, the solves, the writes — serializes
        // on the shared gate under the render-tier bounded wait. Individual
        // target failures collect into the errors array (the partial-success
        // face); the hard timeout escapes typed (in-flight GPU work is not
        // cancelled mid-flight — the export_image 同形).
        return try await seams.gate.withRenderGate {
            let seconds = seams.renderTimeoutOverride
                ?? EditingToolset.durationSeconds(McpTimeouts.renderAndCrop)
            do {
                return try await QuickLookRenderer.boundedWait(seconds: seconds) {
                    try await runFanOut(
                        reference: reference, targetRelPaths: targetRelPaths,
                        strength: strength, solver: solver, attach: attach,
                        seams: seams)
                }
            } catch let timeout as QuickLookRenderer.RenderTimeout {
                throw McpToolError.renderTimeout(
                    "match_color exceeded the \(timeout.seconds)s bounded wait — the "
                        + "GPU work is not cancelled mid-flight; completed targets keep "
                        + "their writes (per-target truth on disk), retry the remainder "
                        + "in smaller batches")
            }
        }
    }

    // MARK: - The fan-out (INSIDE the gate)

    private static func runFanOut(
        reference: String, targetRelPaths: [String], strength: Double,
        solver: ColorMatchSolverKind, attach: Bool, seams: EditingToolset.Seams
    ) async throws -> McpToolOutput {
        // The decode leg: the seams' shared leg when assembled (the parity
        // discipline), else the culling face's default decoder (the same
        // RAWDecoder/raster path every other face rides).
        let decode: QuickLookRenderer.DecodeLeg =
            seams.decodeLeg ?? defaultDecodeLeg()

        // ① The reference (ONE per call — the OQ-6 ruling): id form → the
        // library row + linker; path form → the load_image membership. The
        // typed resolution failures answer BEFORE any GPU work (the
        // service/pipe faces come up only once a reference resolves).
        let referenceURL = try await resolveReference(reference, seams: seams)
        let service = try await Self.service(seams: seams)
        let referenceDecoded = try await decode(referenceURL)
        // The pristine reference semantics (OQ-7): instances [] at the
        // THUMBNAIL bucket through the SAME extractStats face.
        let referenceStats = try await service.extractStats(
            document: ColorMatchDocument(
                image: referenceDecoded, instances: [], layerStack: nil,
                imageID: UUID()),
            bucket: nil)

        // ③ The fan-out: N targets = N independent (source stats, shared
        // reference stats) solves. Individual failures degrade to typed
        // error entries; the batch answer carries both arrays.
        var results: [[String: Any]] = []
        var failures: [[String: Any]] = []
        for relPath in targetRelPaths {
            do {
                results.append(
                    try await solveAndAttachOne(
                        relPath: relPath, referenceStats: referenceStats,
                        strength: strength, solver: solver, attach: attach,
                        service: service, decode: decode, seams: seams))
            } catch let error as McpToolError {
                failures.append([
                    "target": relPath, "code": error.code, "message": error.message,
                ])
            } catch {
                failures.append([
                    "target": relPath, "code": McpToolError.internalError("").code,
                    "message": String(describing: error),
                ])
            }
        }

        var answer: [String: Any] = [
            "reference": reference,
            "solver": solver.rawValue,
            "strength": strength,
            "attach": attach,
            "results": results,
            "errors": failures,
            "note": "tune with apply_params (params keys per list_iops), verify with "
                + "render_preview; same reference/target/parameters → same solveHash",
        ]
        if !failures.isEmpty {
            answer["partialFailure"] = true
        }
        let data = try JSONSerialization.data(
            withJSONObject: answer, options: [.sortedKeys, .prettyPrinted])
        return McpToolOutput(
            [.text(String(decoding: data, as: UTF8.self))],
            isError: failures.contains { !$0.isEmpty })
    }

    /// One target: extract → solve → (attach | params-only). Returns the
    /// per-target summary dict.
    private static func solveAndAttachOne(
        relPath: String, referenceStats: ColorMatchStats, strength: Double,
        solver: ColorMatchSolverKind, attach: Bool, service: ColorMatchService,
        decode: @escaping QuickLookRenderer.DecodeLeg, seams: EditingToolset.Seams
    ) async throws -> [String: Any] {
        let member = try await EditingToolset.resolveMember(
            relPath: relPath, seams: seams)

        // The GUI-live HARD rejection rides the WRITE only (the apply_params
        // single-image semantics; attach=false is a read-only solve).
        if attach, let live = await seams.liveImageURL(),
            live.standardizedFileURL.path == member.imageURL.standardizedFileURL.path
        {
            throw McpToolError.imageLiveInEditor(
                "图像在 Lightamer 编辑器中打开；请让用户关闭后重试，或改用 GUI 操作"
                    + " / The target image is open in the Lightamer editor; ask the "
                    + "user to close it and retry, or edit in the GUI instead")
        }

        // M6-1-01 (KD-5/OQ-5): the project-lock probe — the same attach gate
        // as the live judge (per-target, the finer criterion first).
        if attach {
            try await EditingToolset.rejectIfProjectReadOnly(seams.projectWriteProbe)
        }

        // The source statistics: the target's CURRENT edit chain tapped at
        // the colormatch input plane (E5) at the pinned 512 preview bucket
        // (E6) — the pipeline-level API, headless.
        let decoded = try await decode(member.imageURL)
        let sidecar = ExportRenderer.readDocument(imageURL: member.imageURL)
        let sourceStats = try await service.extractStats(
            document: ColorMatchDocument(
                image: decoded, instances: sidecar?.instances ?? [],
                layerStack: Self.layerStack(from: sidecar?.layerStack),
                imageID: UUID()),
            bucket: ColorMatchExtractBucket.sourcePreviewCap)

        // The solve (the Core pure functions verbatim) + the params record.
        var params = ColormatchModule.Params()
        params.solver = solver
        params.strength = Float(strength)
        params.sourceStatsHash = String(sourceStats.statsHash)
        params.referenceStatsHash = String(referenceStats.statsHash)
        let solveHash: UInt64
        switch solver {
        case .gaussianOT, .reinhard:
            let solution = ColorMatchSolver.solve(
                source: sourceStats, reference: referenceStats, solver: solver)
            params.matrix = solution.matrix
            params.offset = solution.offset
            params.effectiveSolver = solution.effectiveSolver
            ColorMatchSolveCache.shared.invalidateAll()
            solveHash = ColorMatchSolveCache.cacheKey(
                sourceStatsHash: sourceStats.statsHash,
                referenceStatsHash: referenceStats.statsHash, solver: solver)
        case .cdf:
            // The session-curve route (the service attach 同形): the shared
            // box safety net + the curve store + the COMMIT-time asset write
            // (the params carry {assetRef, assetHash}; the solve identity is
            // the shared cache-key fold).
            ColormatchResolverBox.replaceShared(service.resolver)
            let solution = ColorMatchCDFSolver.solve(
                source: sourceStats, reference: referenceStats)
            service.resolver.storeCurves(
                solution, sourceHash: sourceStats.statsHash,
                referenceHash: referenceStats.statsHash)
            service.resolver.setCurrentImageURL(member.imageURL)
            let table = ColorMatchBake.bake(
                solution: solution, strength: Float(strength))
            let directory = ColormatchCubeAsset.directory(forImageURL: member.imageURL)
            let bytesHash = try ColormatchCubeAsset.write(
                table: table, solutionHash: solution.solutionHash,
                strength: Float(strength), directory: directory)
            params.assetRef = ColormatchCubeAsset.assetRef(
                solutionHash: solution.solutionHash, strength: Float(strength),
                forImageURL: member.imageURL)
            params.assetHash = String(bytesHash)
            ColormatchCubeAsset.cleanupSameSolution(
                solutionHash: solution.solutionHash,
                keepFileName: ColormatchCubeAsset.fileName(
                    solutionHash: solution.solutionHash, strength: Float(strength)),
                directory: directory)
            solveHash = solution.solutionHash
        }

        // ④ The landing: the store-level projection seam (E6 — the
        // apply_params projectInstances 同缝) + ONE SessionBatchApplier
        // write; idempotent (an identical projection writes nothing).
        var instanceID: String?
        var status = "params-only"
        if attach {
            let modules = await seams.modules()
            let current: [ModuleInstance]
            if let sidecarInstances = sidecar?.instances {
                current = sidecarInstances
            } else {
                current = await EditingToolset.editingSeed(
                    modules: modules, defaultFace: seams.defaultFace)
            }
            // The pure projection hops the service's MainActor (a value-only
            // call — the store-level seam's core).
            let desired = await MainActor.run {
                ColorMatchService.projectColormatch(
                    current: current, params: params)
            }
            if let record = desired.first(where: {
                $0.opName == ColormatchModule.opName && $0.multiPriority == 0
            }) {
                instanceID = record.id.uuidString
            }
            if desired != current {
                let payload = PastePayload(
                    sourceImageID: UUID(), sourceURL: nil, instances: desired,
                    layerStack: sidecar?.layerStack, copiedAt: Date())
                let writer = BatchSidecarWriter(root: member.root, store: member.store)
                let outcome = await SessionBatchApplier.apply(
                    root: member.root, relPaths: [relPath], payload: payload,
                    mode: .overwrite, seed: [], liveRelPaths: [],
                    store: member.store, writer: writer,
                    timestamp: Date(), label: "MCP match_color")
                guard outcome.appliedRelPaths.contains(relPath) else {
                    throw McpToolError.internalError(
                        "match_color attach did not land for '\(relPath)'")
                }
                await writer.flushForTeardown()
                status = "attached"
            } else {
                status = "unchanged"
            }
        }

        // The summary (the attach=true face; the params dict doubles as the
        // attach=false group — every key is a list_iops colormatch key, so
        // apply_params accepts it verbatim, explicit nulls included).
        var summary: [String: Any] = [
            "target": relPath,
            "status": status,
            "op": ColormatchModule.opName,
            "solveHash": String(solveHash),
            "params": paramsSummary(params),
        ]
        if let instanceID { summary["instanceId"] = instanceID }
        return summary
    }

    /// The params summary/group (the wire face; L013 decimal strings).
    static func paramsSummary(_ params: ColormatchModule.Params) -> [String: Any] {
        var summary: [String: Any] = [
            "solver": params.solver.rawValue,
            "strength": Double(params.strength),
            "sourceStatsHash": params.sourceStatsHash ?? NSNull(),
            "referenceStatsHash": params.referenceStatsHash ?? NSNull(),
        ]
        if params.assetRef != nil {
            summary["assetRef"] = params.assetRef ?? NSNull()
            summary["assetHash"] = params.assetHash ?? NSNull()
        } else {
            summary["matrix"] = params.matrix
            summary["offset"] = params.offset
            if let effective = params.effectiveSolver {
                summary["effectiveSolver"] = effective.rawValue
            }
        }
        return summary
    }

    // MARK: - The reference resolution (the m6 two forms)

    /// ① Digits → the library row (`LibraryStore.image(id:)`) + the linker
    /// (`ImageLinker.resolve`, PathKind 0/1/2) → URL; no open library or an
    /// unknown/stale id = typed `notSessionMember`. ② Everything else = the
    /// load_image membership (`EditingToolset.resolveMember`).
    static func resolveReference(
        _ reference: String, seams: EditingToolset.Seams
    ) async throws -> URL {
        if let id = libraryImageID(reference) {
            guard let provider = await libraryProvider() else {
                throw McpToolError.notSessionMember(
                    "'\(reference)' reads as a library image id but no library project "
                        + "is open on the server host — pass an open-session relPath "
                        + "instead")
            }
            let row: LibraryImage
            do {
                row = try await provider.library.image(id: id)
            } catch {
                throw McpToolError.notSessionMember(
                    "library image id \(id) is not a row of the open library")
            }
            switch ImageLinker.resolve(
                imagePath: row.imagePath, pathKind: row.pathKind,
                volumeUUID: row.volumeUUID, projectDirectory: provider.projectDirectory)
            {
            case .resolved(let url):
                return url
            case .stale(let reason):
                throw McpToolError.notSessionMember(
                    "library image id \(id) does not resolve (\(reason)) — relink "
                        + "the row in the GUI and retry")
            }
        }
        let member = try await EditingToolset.resolveMember(
            relPath: reference, seams: seams)
        return member.imageURL
    }

    /// The default decode leg (the culling face's decoder family — one
    /// RAWDecoder actor per call site, raster UTIs included since M4-1).
    private static func defaultDecodeLeg() -> QuickLookRenderer.DecodeLeg {
        let decoder = RAWDecoder()
        return { url in
            try await decoder.decode(url)
        }
    }

    /// The sidecar record → live LayerStack rebuild (the QuickLookRenderer/
    /// ExportRenderer shape verbatim — the extraction renders the SAME
    /// composite the viewport does; empty stack = nil).
    private static func layerStack(
        from record: SidecarLayerStackRecord?
    ) -> LayerStack? {
        guard let record, !record.layers.isEmpty else { return nil }
        var rebuilt = LayerStack(baseLayer: BackgroundLayer())
        for layer in record.snapshot.makeLayers() {
            rebuilt.addAdjustment(layer)
        }
        return rebuilt.compositeLayers.isEmpty ? nil : rebuilt
    }
}
