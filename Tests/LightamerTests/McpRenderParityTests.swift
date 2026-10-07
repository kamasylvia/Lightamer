import CoreGraphics
import CoreImage
import XCTest
import LightamerCore
import LightamerIOP
import MCP

typealias MCPValue = MCP.Value

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// McpRenderParityTests (Plan 14-2 T1) — the MCP-03 parity 专项 + the
// render_preview tool face:
//
//   • PARITY (the soul assertion): same sidecar, same params → the
//     render_preview plane IS the ExportRenderer plane. Two levels:
//       1. plane-level byte-identical (the 13-1 QL template — shared decode,
//          renderedPlane vs ExportRenderer.renderStage);
//       2. inline-level: the tool's base64 payload decodes to the SAME JPEG
//          bytes a local encode of the golden plane produces — the "remote
//          view" is pixel-identical to the local view in the sRGB-encoded
//          domain (D-14-CONTEXT-7 诚实条款: the EDR display domain is
//          explicitly NOT the alignment target).
//   • BOUNDS (D7): longEdge > 2048 and quality > 90 are `invalidParams`.
//   • TIMEOUT: a stalled render answers the typed `renderTimeout` (no QL
//     embedded-preview fallback — the MCP face has no preview to lie with).
//   • GATE: concurrent render_preview calls serialize (concurrency 1).
//   • SNAPSHOT: the editing domain pins render_preview verbatim (atomic
//     evolution across T1..T4).
//
// Fixtures: the repo RAW pair (input/RAW/DSC00012.ARW + .lra, skipped when a
// checkout lacks it) and synthetic sessions under NSTemporaryDirectory (L009
// — never an external volume).
// ─────────────────────────────────────────────────────────────────────────────

/// ONE CIRAW decode shared by parity legs (two decodes differ — the speckle
/// discipline, the GUI-22 lesson).
private actor ParityDecodeMemo {
    private var value: DecodedImage?
    func decoded(for url: URL) async throws -> DecodedImage {
        if let value { return value }
        let decoded = try await RAWDecoder().decode(url)
        if value == nil { value = decoded }
        return value ?? decoded
    }
}

final class McpRenderParityTests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var modules: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        modules = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Fixture atoms

    /// A synthetic gradient decode (millisecond-cheap handler tests).
    private static func syntheticDecoded(width: Int, height: Int) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: gradient, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// Synthetic session: root/Capture/<name> + an open+synced lindex row.
    private func makeSession(
        imageName: String, rasterData: Data
    ) async throws -> (root: URL, imageURL: URL, store: SessionIndexStore) {
        let root = tempDirectory.appendingPathComponent(
            "session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        let imageURL = capture.appendingPathComponent(imageName)
        try rasterData.write(to: imageURL)

        let store = SessionIndexStore(sessionRoot: root)
        let entry = SessionScanEntry(
            relPath: "Capture/\(imageName)",
            mtime: (try? imageURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate)?.timeIntervalSince1970 ?? 0,
            size: Int64(rasterData.count))
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: [entry]))
                continuation.finish()
            })
        return (root, imageURL, store)
    }

    private func repoSample() throws -> (url: URL, sidecar: URL) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
        try Fixtures.require(url)
        return (url, URL(fileURLWithPath: url.path + ".lra"))
    }

    private func repoSampleSidecarIfPresent() -> URL {
        (try? repoSample())?.sidecar ?? URL(fileURLWithPath: "/dev/null")
    }

    /// Seams over one fixture session (locals only — @Sendable closures never
    /// capture the test-case self).
    private func makeSeams(
        session: (store: SessionIndexStore, root: URL),
        metal metalContext: MetalContext?,
        modules moduleRegistry: ModuleRegistry,
        decodeLeg: QuickLookRenderer.DecodeLeg? = nil,
        timeout: Double? = nil,
        liveImageURL: @escaping @Sendable () async -> URL? = { nil }
    ) -> EditingToolset.Seams {
        var seams = EditingToolset.Seams(
            session: { session },
            metal: { metalContext },
            modules: { moduleRegistry },
            gate: McpRenderGate(),
            liveImageURL: liveImageURL)
        seams.decodeLeg = decodeLeg
        seams.renderTimeoutOverride = timeout
        return seams
    }

    private func makeEditingRegistry(seams: EditingToolset.Seams) async -> McpToolRegistry {
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        return registry
    }

    /// Calls render_preview through the registry and returns the decoded
    /// JPEG payload bytes (static: no test-case self capture).
    private static func callRenderPreview(
        registry: McpToolRegistry, relPath: String,
        longEdge: Int? = nil, quality: Int? = nil
    ) async throws -> Data {
        var arguments: [String: McpJSON] = ["relPath": .string(relPath)]
        if let longEdge { arguments["longEdge"] = .int(longEdge) }
        if let quality { arguments["quality"] = .int(quality) }
        let output = try await registry.call(name: "render_preview", arguments: arguments)
        guard case .imageBase64(let base64, let mime) = output.content.first else {
            throw McpToolError.renderFailed("test harness: expected image content")
        }
        XCTAssertEqual(mime, "image/jpeg")
        guard let data = Data(base64Encoded: base64) else {
            throw McpToolError.renderFailed("test harness: base64 payload undecodable")
        }
        return data
    }

    /// Max per-channel byte difference between two same-size planes.
    private static func planeMaxDiff(_ a: Data, _ b: Data) -> Int {
        precondition(a.count == b.count)
        var result = 0
        a.withUnsafeBytes { pa in
            b.withUnsafeBytes { pb in
                let va = pa.bindMemory(to: UInt8.self)
                let vb = pb.bindMemory(to: UInt8.self)
                for i in 0..<va.count {
                    result = max(result, abs(Int(va[i]) - Int(vb[i])))
                }
            }
        }
        return result
    }

    // MARK: - MCP-03 parity (the soul assertion)

    /// Level 1 (the 13-1 template, re-asserted as the MCP-03 plane gate):
    /// the renderedPlane body and the ExportRenderer.renderStage body agree
    /// BYTE-IDENTICALLY at the same size under the same sidecar + params.
    func testParityPlaneByteIdenticalToExportRenderStage() async throws {
        let sample = try repoSample()
        guard FileManager.default.fileExists(atPath: sample.sidecar.path) else {
            throw XCTSkip("parity sidecar missing: \(sample.sidecar.path)")
        }
        let imageURL = tempDirectory.appendingPathComponent("parity.ARW")
        try FileManager.default.copyItem(at: sample.url, to: imageURL)
        try FileManager.default.copyItem(at: sample.sidecar, to: imageURL.appendingPathExtension("lra"))

        let memo = ParityDecodeMemo()
        let decodeLeg: QuickLookRenderer.DecodeLeg = { try await memo.decoded(for: $0) }
        let metal: MetalContext = self.metal
        let modules: ModuleRegistry = self.modules

        // The export reference: percent-100, sRGB, JPEG q0.9, no yiyin —
        // the golden-family assembly (the export chain verbatim).
        let variant = ExportVariant(
            scalePercent: 100, format: .jpeg(quality: 0.9),
            colorSpace: .sRGB, yiyin: false)
        let stage = try await ExportRenderer.renderStage(
            request: ExportRenderer.Request(
                imageURL: imageURL, destinationDirectory: tempDirectory,
                occupiedNames: [], variant: variant),
            metal: metal, registry: modules, decodeLeg: decodeLeg)

        // The MCP leg: renderedPlane at the stage's OWN long edge (the
        // same-size same-params gate, §RQ-14-4②).
        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: imageURL, targetLongEdge: max(stage.outputWidth, stage.outputHeight),
            metal: metal, registry: modules, decodeLeg: decodeLeg)

        XCTAssertEqual(rendered.plane.width, stage.plane.width, "same size gate")
        XCTAssertEqual(rendered.plane.height, stage.plane.height, "same size gate")
        // The parity NUMBER (maxDiff in 1/255 units; byte-identical = 0).
        let diff = Self.planeMaxDiff(rendered.plane.data, stage.plane.data)
        XCTAssertEqual(diff, 0, "MCP-03 parity: renderedPlane vs Export golden plane")
    }

    /// Level 2 (the inline leg): render_preview's base64 payload decodes to
    /// the SAME JPEG bytes a local encode of the same plane produces (shared
    /// decode → the remote view is pixel-identical to the local view).
    func testParityInlineJPEGMatchesLocalEncodeOfGoldenPlane() async throws {
        let sample = try repoSample()
        guard FileManager.default.fileExists(atPath: sample.sidecar.path) else {
            throw XCTSkip("parity sidecar missing: \(sample.sidecar.path)")
        }
        // The session fixture carries the REAL RAW + sidecar under a
        // session-relative name (the index row is the membership gate).
        let (root, imageURL, store) = try await makeSession(
            imageName: "DSC00012.ARW", rasterData: try Data(contentsOf: sample.url))
        try FileManager.default.copyItem(
            at: sample.sidecar, to: imageURL.appendingPathExtension("lra"))

        let memo = ParityDecodeMemo()
        let decodeLeg: QuickLookRenderer.DecodeLeg = { try await memo.decoded(for: $0) }
        let metal: MetalContext = self.metal
        let modules: ModuleRegistry = self.modules
        let seams = makeSeams(
            session: (store, root), metal: metal, modules: modules, decodeLeg: decodeLeg)
        let registry = await makeEditingRegistry(seams: seams)
        let inline = try await Self.callRenderPreview(
            registry: registry, relPath: "Capture/DSC00012.ARW",
            longEdge: 1024, quality: 85)

        // The local reference: the SAME renderedPlane → CGImage → JPEG q85.
        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: imageURL, targetLongEdge: 1024,
            metal: metal, registry: modules, decodeLeg: decodeLeg)
        let local = try XCTUnwrap(
            EditingToolset.encodeJPEG(
                try QuickLookRenderer.image(from: rendered), quality: 0.85))

        XCTAssertEqual(inline, local, "MCP-03 inline parity: remote view == local view")
    }

    // MARK: - Bounds (D7) + membership errors

    func testLongEdgeAbove2048IsInvalidParams() async throws {
        let (root, _, store) = try await makeSession(
            imageName: "a.ARW", rasterData: Data(repeating: 0xCD, count: 64))
        let seams = makeSeams(session: (store, root), metal: metal, modules: modules)
        let registry = await makeEditingRegistry(seams: seams)
        do {
            _ = try await Self.callRenderPreview(
                registry: registry, relPath: "Capture/a.ARW", longEdge: 2049)
            XCTFail("longEdge 2049 must be invalidParams (D7 cap)")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("export_image"))
        }
    }

    func testQualityAbove90IsInvalidParams() async throws {
        let (root, _, store) = try await makeSession(
            imageName: "a.ARW", rasterData: Data(repeating: 0xCD, count: 64))
        let seams = makeSeams(session: (store, root), metal: metal, modules: modules)
        let registry = await makeEditingRegistry(seams: seams)
        do {
            _ = try await Self.callRenderPreview(
                registry: registry, relPath: "Capture/a.ARW", quality: 91)
            XCTFail("quality 91 must be invalidParams (D7 cap)")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }

    func testNotSessionMemberAndNoSessionAreTyped() async throws {
        // No session open on the host.
        let metal: MetalContext = self.metal
        let modules: ModuleRegistry = self.modules
        let noSession = EditingToolset.Seams(
            session: { nil }, metal: { metal }, modules: { modules },
            gate: McpRenderGate(), liveImageURL: { nil })
        let empty = await makeEditingRegistry(seams: noSession)
        do {
            _ = try await Self.callRenderPreview(registry: empty, relPath: "x.ARW")
            XCTFail("no-session must be notSessionMember")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }

        // An open session, but the relPath is not an indexed row.
        let (root, _, store) = try await makeSession(
            imageName: "a.ARW", rasterData: Data(repeating: 0xCD, count: 64))
        let seams = makeSeams(session: (store, root), metal: metal, modules: modules)
        let registry = await makeEditingRegistry(seams: seams)
        do {
            _ = try await Self.callRenderPreview(
                registry: registry, relPath: "Capture/missing.ARW")
            XCTFail("a foreign relPath must be notSessionMember")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }
    }

    // MARK: - Timeout + failure semantics (no silent degradation)

    /// A stalled render surfaces the typed `renderTimeout` — NEVER the QL
    /// embedded-preview fallback (the MCP face reports, it does not lie).
    func testStalledRenderSurfacesTypedRenderTimeout() async throws {
        let (root, imageURL, store) = try await makeSession(
            imageName: "slow.ARW", rasterData: Data(repeating: 0xCD, count: 64))
        try FileManager.default.copyItem(
            at: repoSampleSidecarIfPresent(), to: imageURL.appendingPathExtension("lra"))

        let stalledDecode: QuickLookRenderer.DecodeLeg = { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return Self.syntheticDecoded(width: 320, height: 240)
        }
        let seams = makeSeams(
            session: (store, root), metal: metal, modules: modules,
            decodeLeg: stalledDecode, timeout: 0.3)
        let registry = await makeEditingRegistry(seams: seams)
        let start = DispatchTime.now()
        do {
            _ = try await Self.callRenderPreview(
                registry: registry, relPath: "Capture/slow.ARW")
            XCTFail("a stalled render must surface renderTimeout")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "renderTimeout")
            let elapsed = Double(
                DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            XCTAssertLessThan(elapsed, 2.0, "the timeout must be bounded")
        }
    }

    /// A THROWING render surfaces `renderFailed` (typed; never a crash, never
    /// a fallback).
    func testFailingRenderSurfacesTypedRenderFailed() async throws {
        let (root, _, store) = try await makeSession(
            imageName: "bad.ARW", rasterData: Data(repeating: 0xCD, count: 64))
        let failingDecode: QuickLookRenderer.DecodeLeg = { _ in
            throw AppError.decodeFailed("injected decode failure")
        }
        let seams = makeSeams(
            session: (store, root), metal: metal, modules: modules,
            decodeLeg: failingDecode)
        let registry = await makeEditingRegistry(seams: seams)
        do {
            _ = try await Self.callRenderPreview(
                registry: registry, relPath: "Capture/bad.ARW")
            XCTFail("a failing render must surface renderFailed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "renderFailed")
        }
    }

    // MARK: - The render gate

    /// Concurrent render_preview calls serialize on the shared gate — the
    /// render bodies never overlap (concurrency 1, §RQ-14-13).
    func testConcurrentRenderPreviewsSerializeOnTheGate() async throws {
        let (root, imageURL, store) = try await makeSession(
            imageName: "gate.ARW", rasterData: Data(repeating: 0xCD, count: 64))
        try FileManager.default.copyItem(
            at: repoSampleSidecarIfPresent(), to: imageURL.appendingPathExtension("lra"))

        final class OverlapProbe: @unchecked Sendable {
            private let lock = NSLock()
            private var current = 0
            private(set) var maxSeen = 0
            func enter() {
                lock.lock(); current += 1
                maxSeen = Swift.max(maxSeen, current)
                lock.unlock()
            }
            func exit() { lock.lock(); current -= 1; lock.unlock() }
        }
        let overlap = OverlapProbe()
        let slowish: QuickLookRenderer.DecodeLeg = { _ in
            overlap.enter()
            try? await Task.sleep(nanoseconds: 80_000_000)
            overlap.exit()
            return Self.syntheticDecoded(width: 320, height: 240)
        }
        let seams = makeSeams(
            session: (store, root), metal: metal, modules: modules, decodeLeg: slowish)
        let registry = await makeEditingRegistry(seams: seams)

        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await Self.callRenderPreview(
                        registry: registry, relPath: "Capture/gate.ARW", longEdge: 256)
                }
            }
            for try await _ in group {}
        }
        XCTAssertLessThanOrEqual(
            overlap.maxSeen, 1, "render gate: render_preview bodies never overlap")
    }


    // MARK: - T5: the SC#3 end-to-end chain (the字面 SC)

    /// A live-image provider the test drives AT runtime (the registered
    /// handlers read the box on every call — a struct seam copies by value,
    /// so the插步 needs an indirection the closure consults live).
    private final class LiveImageBox: @unchecked Sendable {
        private let lock = NSLock()
        private var url: URL?
        func set(_ newValue: URL?) { lock.lock(); url = newValue; lock.unlock() }
        func get() -> URL? { lock.lock(); defer { lock.unlock() }; return url }
    }

    /// SC#3: load (membership) → apply ≥3 iops (with a GUI-live hard-
    /// rejection insert in the middle) → render_preview → the remote view
    /// is BYTE-IDENTICAL to the local render of the same saved state —
    /// across BOTH hosts (InMemory + Streamable HTTP over the SAME seams:
    /// one shared decode memo makes the two legs' pixels directly
    /// comparable).
    func testSC3EndToEndAcrossBothHosts() async throws {
        let sample = try repoSample()
        guard FileManager.default.fileExists(atPath: sample.sidecar.path) else {
            throw XCTSkip("SC#3 sidecar missing: \(sample.sidecar.path)")
        }
        let (root, imageURL, store) = try await makeSession(
            imageName: "DSC00012.ARW", rasterData: try Data(contentsOf: sample.url))
        try FileManager.default.copyItem(
            at: sample.sidecar, to: imageURL.appendingPathExtension("lra"))

        // The kernel: populated modules + the IOP metallib (the app's
        // launch discipline) + ONE shared decode for both legs.
        let populated = ModuleRegistry()
        await LightamerIOPRegistry.populate(populated)
        let metal: MetalContext = self.metal
        try await metal.registerDefaultLibrary(in: ExposureKernel.metalBundle)
        let memo = ParityDecodeMemo()
        let decodeLeg: QuickLookRenderer.DecodeLeg = { try await memo.decoded(for: $0) }
        let liveBox = LiveImageBox()
        let seams = makeSeams(
            session: (store, root), metal: metal, modules: populated,
            decodeLeg: decodeLeg, liveImageURL: { liveBox.get() })
        let relPathArg: MCPValue = .string("Capture/DSC00012.ARW")

        // ── Host 1: InMemoryTransport (the in-process leg). ─────────────
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        let server = await McpAdapters.makeServer(registry: registry)
        let pair = await InMemoryTransport.createConnectedPair()
        try await server.start(transport: pair.server)
        let client = MCP.Client(name: "sc3-inmemory", version: "0.0.1")
        try await client.connect(transport: pair.client)

        // ① load_image: the membership gate + the saved-state view.
        let (load, loadError) = try await client.callTool(
            name: "load_image", arguments: ["relPath": relPathArg])
        XCTAssertNil(loadError)
        guard case .text(let loadView, _, _) = load.first else {
            return XCTFail("load_image must answer text")
        }
        XCTAssertTrue(loadView.contains("\"stateless\""), "the stateless declaration rides")

        // ② THE GUI-LIVE INSERT: the editor opens the image → apply_params
        //    is HARD-REJECTED (typed, bilingual) → close → retry succeeds.
        let threeOps: MCPValue = .array([
            .object(["opName": .string("exposure"),
                     "params": .object(["exposure": .double(0.3)])]),
            .object(["opName": .string("colisa"),
                     "params": .object(["contrast": .double(0.25)])]),
            .object(["opName": .string("velvia"),
                     "params": .object(["strength": .double(0.5)])]),
        ])
        let applyArguments = ["relPath": relPathArg, "ops": threeOps]
        liveBox.set(imageURL)
        do {
            _ = try await client.callTool(
                name: "apply_params", arguments: applyArguments)
            XCTFail("a GUI-live image must be hard-rejected mid-chain")
        } catch let error as MCPError {
            let text = String(describing: error)
            XCTAssertTrue(text.contains("[imageLiveInEditor]"), "got: \(text)")
            XCTAssertTrue(text.contains("图像在 Lightamer 编辑器中打开"))
        }
        liveBox.set(nil)
        let (applied, applyError) = try await client.callTool(
            name: "apply_params", arguments: applyArguments)
        XCTAssertNil(applyError)
        guard case .text(let appliedText, _, _) = applied.first else {
            return XCTFail("apply_params must answer text")
        }
        XCTAssertTrue(appliedText.contains("applied=Capture/DSC00012.ARW"))

        // ③ render_preview through the SAME transport.
        let (preview, previewError) = try await client.callTool(
            name: "render_preview",
            arguments: ["relPath": relPathArg, "longEdge": .int(1024)])
        XCTAssertNil(previewError)
        guard let previewContent = preview.first,
            case .imageBase64(let inMemoryBase64, _) =
                McpAdapters.outputContent(from: previewContent)
        else {
            return XCTFail("render_preview must answer an image")
        }
        guard let inMemoryJPEG = Data(base64Encoded: inMemoryBase64) else {
            return XCTFail("the inline payload must decode")
        }
        await client.disconnect()
        await server.stop()

        // ── The LOCAL reference: the same renderedPlane + JPEG encode over
        // the SHARED decode — the saved state the agent just wrote. ──────
        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: imageURL, targetLongEdge: 1024,
            metal: metal, registry: populated, decodeLeg: decodeLeg)
        let localJPEG = try XCTUnwrap(
            EditingToolset.encodeJPEG(
                try QuickLookRenderer.image(from: rendered), quality: 0.85))
        XCTAssertEqual(
            inMemoryJPEG, localJPEG,
            "SC#3: the remote preview is byte-identical to the local render")

        // ── Host 2: Streamable HTTP over the SAME seams. ────────────────
        let paths = McpEndpointPaths(
            directory: tempDirectory.appendingPathComponent("endpoint"))
        let handle = try await McpServerController.startHTTPHost(
            paths: paths, editing: seams)
        let endpoint = URL(string: "http://127.0.0.1:\(handle.port)/mcp")!
        let httpTransport = HTTPClientTransport(endpoint: endpoint)
        let httpClient = MCP.Client(name: "sc3-http", version: "0.0.1")
        try await httpClient.connect(transport: httpTransport)
        let tools = try await httpClient.listTools()
        // The five editing tools ALL ride the second host (the closed
        // 19-tool face — Plan 14-4 retired the probe pair).
        let httpNames = Set(tools.0.map(\.name))
        XCTAssertTrue(
            ["load_image", "apply_params", "render_preview", "list_iops", "export_image"]
                .allSatisfy(httpNames.contains),
            "the same closed editing face rides both hosts")
        let (httpPreview, httpError) = try await httpClient.callTool(
            name: "render_preview",
            arguments: ["relPath": relPathArg, "longEdge": .int(1024)])
        XCTAssertNil(httpError)
        guard let httpContent = httpPreview.first,
            case .imageBase64(let httpBase64, _) =
                McpAdapters.outputContent(from: httpContent)
        else {
            return XCTFail("the HTTP leg must answer an image")
        }
        guard let httpJPEG = Data(base64Encoded: httpBase64) else {
            return XCTFail("the HTTP inline payload must decode")
        }
        XCTAssertEqual(
            httpJPEG, inMemoryJPEG,
            "dual-host consistency: both hosts answer byte-identically")
        await httpClient.disconnect()
        await handle.stop()
    }
}
