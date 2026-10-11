import CoreGraphics
import CoreImage
import XCTest
import LightamerCore
import LightamerIOP

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// McpMatchColorParityTests (Plan M5-1-03 T2, KD-2; OQ-8 G4) — the MCP
// end-to-end parity, the Phase 14 SC#3 同型:
//
//   match_color (attach=true) → apply_params (the strength-0.7 tuning leg,
//   the "事后微调走既有 apply_params" closure, REAL) → render_preview →
//   byte-identical to the LOCAL render of the same saved state (the same
//   renderedPlane + JPEG encode over ONE shared decode — the speckle
//   discipline).
//
// Plus the batch parity leg (two targets through one fan-out call) and the
// solveHash disclosure (the G1 agent face through the registry).
//
// Fixtures: synthetic TIFF sessions (deterministic decode, no RAW dependency
// — KD-2's synthetic-fixture rule); L031's routed-queue discipline rides the
// source of QuickLookRenderer/RenderPipeline (fixed in the source).
// ─────────────────────────────────────────────────────────────────────────────

/// ONE decode shared by every leg (two decodes differ — the GUI-22 lesson).
private actor MatchParityDecodeMemo {
    private var cache: [URL: DecodedImage] = [:]
    func decoded(for url: URL) async throws -> DecodedImage {
        if let cached = cache[url] { return cached }
        let decoded = try await RAWDecoder().decode(url)
        cache[url] = decoded
        return decoded
    }
}

final class McpMatchColorParityTests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-match-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Session: a warm reference + two differently-cast targets (real
    /// decodable TIFFs — the McpMatchColorToolsetTests writer).
    private func makeSession() async throws -> (
        root: URL, store: SessionIndexStore, relPaths: [String]
    ) {
        let root = tempDirectory.appendingPathComponent(
            "session", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        let files: [(String, (Double, Double, Double), (Double, Double, Double))] = [
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("cool.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
            ("warm.tif", (0.80, 0.60, 0.25), (0.55, 0.35, 0.15)),
        ]
        var entries: [SessionScanEntry] = []
        var relPaths: [String] = []
        for (name, top, bottom) in files {
            let url = capture.appendingPathComponent(name)
            try McpMatchColorToolsetTests.writeTIFF(url, top: top, bottom: bottom)
            let relPath = "Capture/\(name)"
            entries.append(SessionScanEntry(
                relPath: relPath,
                mtime: (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate)?.timeIntervalSince1970 ?? 0,
                size: Int64((try? Data(contentsOf: url).count) ?? 0)))
            relPaths.append(relPath)
        }
        let store = SessionIndexStore(sessionRoot: root)
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: entries))
                continuation.finish()
            })
        return (root, store, relPaths)
    }

    private func makeSeamsAndRegistry(
        session: (root: URL, store: SessionIndexStore, relPaths: [String]),
        decodeLeg: @escaping QuickLookRenderer.DecodeLeg
    ) async -> (EditingToolset.Seams, McpToolRegistry) {
        let populated = ModuleRegistry()
        await LightamerIOPRegistry.populate(populated)
        let metal = self.metal
        var seams = EditingToolset.Seams(
            session: { (session.store, session.root) },
            metal: { metal },
            modules: { populated },
            gate: McpRenderGate(),
            liveImageURL: { nil })
        seams.writeGate = McpRenderGate()
        seams.decodeLeg = decodeLeg
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        return (seams, registry)
    }

    private static func textPayload(_ output: McpToolOutput) throws -> String {
        for content in output.content {
            if case .text(let text) = content { return text }
        }
        throw McpToolError.internalError("expected a text payload")
    }

    private static func callJSON(
        _ registry: McpToolRegistry, name: String, arguments: [String: McpJSON]
    ) async throws -> [String: Any] {
        let output = try await registry.call(name: name, arguments: arguments)
        let text = try textPayload(output)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8), options: []) as? [String: Any],
            text)
    }

    private static func callPreview(
        _ registry: McpToolRegistry, relPath: String
    ) async throws -> Data {
        let output = try await registry.call(
            name: "render_preview",
            arguments: ["relPath": .string(relPath), "longEdge": .int(1024)])
        for content in output.content {
            if case .imageBase64(let base64, _) = content,
                let jpeg = Data(base64Encoded: base64) {
                return jpeg
            }
        }
        throw McpToolError.internalError("render_preview must answer an inline image")
    }

    /// The LOCAL reference leg: the same renderedPlane → JPEG q85 shape the
    /// render_preview body runs (the SC#3 level-2 parity, byte-identical).
    private func localPreview(
        imageURL: URL, decodeLeg: @escaping QuickLookRenderer.DecodeLeg
    ) async throws -> Data {
        let modules = ModuleRegistry()
        await LightamerIOPRegistry.populate(modules)
        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: imageURL, targetLongEdge: 1024,
            metal: metal, registry: modules, decodeLeg: decodeLeg)
        return try XCTUnwrap(
            EditingToolset.encodeJPEG(
                try QuickLookRenderer.image(from: rendered), quality: 0.85))
    }

    // MARK: - G4: the end-to-end parity chain

    func testMatchColorApplyParamsRenderPreviewParity() async throws {
        let session = try await makeSession()
        let memo = MatchParityDecodeMemo()
        let (_, registry) = await makeSeamsAndRegistry(
            session: session, decodeLeg: { try await memo.decoded(for: $0) })

        // ① match_color: attach the solve (strength 1.0 gaussian-ot).
        let answer = try await Self.callJSON(registry, name: "match_color", arguments: [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/cool.tif"),
        ])
        XCTAssertTrue(((answer["errors"] as? [[String: Any]]) ?? []).isEmpty, "\(answer)")
        let solveHash = try XCTUnwrap(
            (answer["results"] as? [[String: Any]])?.first?["solveHash"] as? String)
        XCTAssertFalse(solveHash.isEmpty)

        // ② apply_params: the tuning leg (strength 0.7 — one undoable commit
        // on top of the attached instance).
        let applied = try await registry.call(
            name: "apply_params",
            arguments: [
                "relPath": .string("Capture/cool.tif"),
                "ops": .array([.object([
                    "opName": .string("colormatch"),
                    "params": .object(["strength": .double(0.7)]),
                ])]),
            ])
        guard case .text(let appliedText) = applied.content.first else {
            return XCTFail("apply_params must answer text")
        }
        XCTAssertTrue(appliedText.contains("applied=Capture/cool.tif"), appliedText)

        // ③ render_preview vs the LOCAL render of the same saved state.
        let remote = try await Self.callPreview(registry, relPath: "Capture/cool.tif")
        let targetURL = session.root.appendingPathComponent("Capture/cool.tif")
        let local = try await localPreview(
            imageURL: targetURL, decodeLeg: { try await memo.decoded(for: $0) })
        // SC#3 precedent: byte-identical. The measured band pins here (a
        // nonzero band would need a DECISIONS entry — L048 compare-domain
        // check first).
        XCTAssertEqual(remote, local, "G4: remote view == local view (byte-identical)")
    }

    /// The batch parity: ONE fan-out call over two targets; each target's
    /// preview matches its local render (the fan-out lands per-target truth,
    /// and each render rides its own solve).
    func testBatchDoubleTargetParity() async throws {
        let session = try await makeSession()
        let memo = MatchParityDecodeMemo()
        let (_, registry) = await makeSeamsAndRegistry(
            session: session, decodeLeg: { try await memo.decoded(for: $0) })

        let answer = try await Self.callJSON(registry, name: "match_color", arguments: [
            "reference": .string("Capture/ref.tif"),
            "targets": .array([.string("Capture/cool.tif"), .string("Capture/warm.tif")]),
        ])
        XCTAssertTrue(((answer["errors"] as? [[String: Any]]) ?? []).isEmpty, "\(answer)")
        let results = try XCTUnwrap(answer["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 2)

        for relPath in ["Capture/cool.tif", "Capture/warm.tif"] {
            let remote = try await Self.callPreview(registry, relPath: relPath)
            let local = try await localPreview(
                imageURL: session.root.appendingPathComponent(relPath),
                decodeLeg: { try await memo.decoded(for: $0) })
            XCTAssertEqual(remote, local, "G4 batch: \(relPath) remote == local")
        }
    }

    /// The G1 disclosure through the MCP face: two identical calls → the
    /// same solveHash (the agent re-verifies determinism unaided).
    func testDoubleCallDisclosesTheSameSolveHash() async throws {
        let session = try await makeSession()
        let memo = MatchParityDecodeMemo()
        let (_, registry) = await makeSeamsAndRegistry(
            session: session, decodeLeg: { try await memo.decoded(for: $0) })
        let arguments: [String: McpJSON] = [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/cool.tif"),
            "strength": .double(0.7),
            "attach": .bool(false),
        ]
        let first = try await Self.callJSON(registry, name: "match_color", arguments: arguments)
        let second = try await Self.callJSON(registry, name: "match_color", arguments: arguments)
        let hashA = try XCTUnwrap(
            (first["results"] as? [[String: Any]])?.first?["solveHash"] as? String)
        let hashB = try XCTUnwrap(
            (second["results"] as? [[String: Any]])?.first?["solveHash"] as? String)
        XCTAssertEqual(hashA, hashB, "G1 via the tool face: same inputs → same solveHash")
    }
}
