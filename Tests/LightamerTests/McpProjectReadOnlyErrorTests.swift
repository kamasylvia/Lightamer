import CoreGraphics
import Foundation
import LightamerCore
import LightamerIOP
import UniformTypeIdentifiers
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T7 (KD-8 golden gate 5): the MCP write-face typed
// `projectReadOnly` — probe `.held` → the typed rejection with the copy
// carrying the holder summary + guidance, the `imageLiveInEditor` FIRST
// order (the 生效值 hard constraint), the read-class tools unaffected, the
// `serverReadOnly` legacy semantics + registry gate order preserved, the
// probe-nil zero-behavior gate, the self-held exemption shape and the
// five write-face call sites. The 20-tool closed set rides the existing
// snapshot suites (run untouched in the same bundle).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class McpProjectReadOnlyErrorTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-ro-err-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Harness (the McpEditingToolsetTests shape)

    private func makeSession(
        imageName: String = "DSC00012.ARW"
    ) async throws -> (root: URL, imageURL: URL, store: SessionIndexStore) {
        let root = tempDirectory.appendingPathComponent(
            "session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        let imageURL = capture.appendingPathComponent(imageName)
        try Data(repeating: 0xCD, count: 64).write(to: imageURL)
        let store = SessionIndexStore(sessionRoot: root)
        let entry = SessionScanEntry(
            relPath: "Capture/\(imageName)",
            mtime: (try? imageURL.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate)?.timeIntervalSince1970 ?? 0,
            size: 64)
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: [entry]))
                continuation.finish()
            })
        return (root, imageURL, store)
    }

    private func makeSeams(
        session: (store: SessionIndexStore, root: URL)? = nil,
        liveImageURL: @escaping @Sendable () async -> URL? = { nil },
        projectWriteProbe: (@Sendable () async -> McpProjectLockVerdict)? = nil
    ) async -> EditingToolset.Seams {
        let populated = await populatedModules()
        var seams = EditingToolset.Seams(
            session: { session },
            metal: { nil },
            modules: { populated },
            gate: McpRenderGate(),
            liveImageURL: liveImageURL)
        seams.writeGate = McpRenderGate()
        seams.projectWriteProbe = projectWriteProbe
        return seams
    }

    private func populatedModules() async -> ModuleRegistry {
        let registry = ModuleRegistry()
        await LightamerIOPRegistry.populate(registry)
        return registry
    }

    private func makeEditingRegistry(
        seams: EditingToolset.Seams, writerCheck: (@Sendable () async -> Bool)? = nil
    ) async -> McpToolRegistry {
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        await registry.setWriterCheck(writerCheck)
        return registry
    }

    private static func applyOp(
        _ registry: McpToolRegistry, relPath: String
    ) async throws -> String {
        let output = try await registry.call(
            name: "apply_params",
            arguments: [
                "relPath": .string(relPath),
                "ops": .array([.object([
                    "opName": .string("exposure"),
                    "params": .object(["exposure": .double(0.3)]),
                ])]),
            ])
        guard case .text(let text) = output.content.first else {
            throw McpToolError.internalError("test harness: expected text content")
        }
        return text
    }

    private func heldProbe() -> (@Sendable () async -> McpProjectLockVerdict) {
        { .held(holderSummary: "role=gui pid=4321", guidance: "connect 127.0.0.1:59999") }
    }

    // MARK: - Gate 5

    /// The core negative: probe `.held` → apply_params typed-rejects
    /// `projectReadOnly`, the copy carries the holder summary + guidance.
    func testApplyParamsProbeHeldThrowsTypedProjectReadOnly() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeEditingRegistry(
            seams: await makeSeams(
                session: (store, root), projectWriteProbe: heldProbe()))
        do {
            _ = try await Self.applyOp(registry, relPath: "Capture/DSC00012.ARW")
            XCTFail("a held project must reject the write face")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "projectReadOnly")
            XCTAssertTrue(error.message.contains("role=gui pid=4321"))
            XCTAssertTrue(error.message.contains("connect 127.0.0.1:59999"))
        }
    }

    /// The 生效值 hard order: a GUI-live target + a held project →
    /// `imageLiveInEditor` (the finer criterion hits FIRST).
    func testLiveJudgeBeatsProjectProbe() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeEditingRegistry(
            seams: await makeSeams(
                session: (store, root), liveImageURL: { imageURL },
                projectWriteProbe: heldProbe()))
        do {
            _ = try await Self.applyOp(registry, relPath: "Capture/DSC00012.ARW")
            XCTFail("the live judge must hit first")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "imageLiveInEditor")
        }
    }

    /// The probe-nil zero-behavior gate: no probe → apply_params runs the
    /// pre-M6-1 face (the write lands; no new rejection exists).
    func testProbeNilKeepsLegacyFace() async throws {
        let (root, imageURL, store) = try await makeSession()
        let registry = await makeEditingRegistry(
            seams: await makeSeams(session: (store, root)))
        _ = try await Self.applyOp(registry, relPath: "Capture/DSC00012.ARW")
        let sidecarURL = imageURL.appendingPathExtension("lra")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sidecarURL.path),
            "the unwired seam keeps the legacy write behavior")
    }

    /// The registry gate order: `serverReadOnly` (the endpoint writer gate)
    /// fires BEFORE the project probe — the two lock layers stay orthogonal.
    func testServerReadOnlyFiresBeforeProjectProbe() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeEditingRegistry(
            seams: await makeSeams(
                session: (store, root), projectWriteProbe: heldProbe()),
            writerCheck: { false })
        do {
            _ = try await Self.applyOp(registry, relPath: "Capture/DSC00012.ARW")
            XCTFail("a read-only server must reject at the endpoint gate")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "serverReadOnly")
        }
    }

    /// The self-held exemption shape: a writer-arm-style closure answers
    /// `.writable` → the write proceeds (the negative against the flock
    /// same-process false negative rejecting our own writes).
    func testSelfHeldExemptionLetsWritesThrough() async throws {
        let (root, imageURL, store) = try await makeSession()
        let writableProbe: @Sendable () async -> McpProjectLockVerdict = { .writable }
        let registry = await makeEditingRegistry(
            seams: await makeSeams(
                session: (store, root), projectWriteProbe: writableProbe))
        _ = try await Self.applyOp(registry, relPath: "Capture/DSC00012.ARW")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: imageURL.appendingPathExtension("lra").path),
            "the writable verdict must not block the write")
    }

    /// export_image probes at the write body's HEAD — even a malformed
    /// call sees `projectReadOnly` before any argument validation.
    func testExportImageProbeHeldAtBodyHead() async throws {
        let (root, _, store) = try await makeSession()
        let registry = await makeEditingRegistry(
            seams: await makeSeams(
                session: (store, root), projectWriteProbe: heldProbe()))
        do {
            _ = try await registry.call(name: "export_image", arguments: [:])
            XCTFail("the export body must probe first")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "projectReadOnly")
        }
    }

    /// The culling write-five frame: set_rating with a held probe → typed
    /// `projectReadOnly` after membership (the read-class list_presets in
    /// the SAME context answers normally — the read face is the point).
    func testCullingWriteFiveProbeHeldAndReadClassUnaffected() async throws {
        let (root, _, store) = try await makeSession()
        var context = McpCullingContext(
            store: { [store] in store },
            sessionRoot: { [root] in root },
            metadata: { [store, root] in
                MetadataService(
                    root: root, store: store,
                    writer: BatchSidecarWriter(root: root, store: store),
                    seed: [])
            },
            sidecarWriter: { [store, root] in
                BatchSidecarWriter(root: root, store: store)
            },
            presets: { PresetsStore() },
            decodeImage: McpCullingContext.defaultDecodeImage())
        context.projectWriteProbe = heldProbe()
        let registry = McpToolRegistry()
        await McpCullingToolset.registerAll(on: registry, context: context)

        // Write face: held → typed.
        do {
            _ = try await registry.call(
                name: "set_rating",
                arguments: [
                    "relPaths": .array([.string("Capture/DSC00012.ARW")]),
                    "rating": .int(4),
                ])
            XCTFail("a held project must reject the metadata write")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "projectReadOnly")
        }

        // Read face (list_presets, the probe-free class): the nil presets
        // store is its honest face — NOT a projectReadOnly rejection.
        let output = try await registry.call(name: "list_presets", arguments: [:])
        guard case .text = output.content.first else {
            return XCTFail("the read face must answer normally")
        }
    }

    /// The match_color write leg: the probe rides the same attach gate as
    /// the live judge — attach=true with a held project lands
    /// `projectReadOnly` in the per-target failure face; attach=false (the
    /// read-only solve) never carries it.
    func testMatchColorProbeRidesAttachGate() async throws {
        MatchColorToolset.resetForTesting()
        // The reference extraction precedes the per-target probe, so the
        // service needs the REAL pipe (the McpMatchColorToolsetTests
        // makeMetal shape; the solid-TIFF extraction is that suite's
        // proven path).
        let service = try await makeConfiguredColorMatchService()
        MatchColorToolset.installColorMatchService(service)
        let (root, store) = try await makeMatchColorSession()
        let registry = await makeEditingRegistry(
            seams: await makeSeams(
                session: (store, root), projectWriteProbe: heldProbe()))

        // attach=true (the write leg): the held project lands in the
        // per-target failures.
        let attachOutput = try await registry.call(
            name: "match_color",
            arguments: [
                "reference": .string("Capture/Ref.tif"),
                "targets": .array([.string("Capture/Tgt.tif")]),
                "attach": .bool(true),
            ])
        guard case .text(let attachText) = attachOutput.content.first else {
            return XCTFail("expected text content")
        }
        XCTAssertTrue(
            attachText.contains("projectReadOnly"),
            "the write leg must carry the typed rejection: \(attachText)")

        // The attach gate is structural: the probe call sits under
        // `if attach` beside the live judge.
        MatchColorToolset.resetForTesting()
    }

    /// The configured-service builder (the McpMatchColorToolsetTests
    /// makeMetal shape — skips honestly on a GPU-less host).
    private func makeConfiguredColorMatchService() async throws -> ColorMatchService {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
        let registry = ModuleRegistry()
        await LightamerIOPRegistry.populate(registry)
        let service = ColorMatchService(metal: metal, registry: registry)
        service.configure(metal: metal, registry: registry)
        return service
    }

    /// A synthetic session with REAL decodable TIFF members (the
    /// McpMatchColorToolsetTests writer shape).
    private func makeMatchColorSession() async throws
        -> (root: URL, store: SessionIndexStore)
    {
        let root = tempDirectory.appendingPathComponent(
            "mc-session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        var entries: [SessionScanEntry] = []
        for name in ["Ref.tif", "Tgt.tif"] {
            let url = capture.appendingPathComponent(name)
            try Self.writeSolidTIFF(url)
            entries.append(SessionScanEntry(
                relPath: "Capture/\(name)",
                mtime: (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate)?.timeIntervalSince1970 ?? 0,
                size: Int64((try? Data(contentsOf: url).count) ?? 0)))
        }
        let store = SessionIndexStore(sessionRoot: root)
        _ = try await store.openSession(
            root: root,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: entries))
                continuation.finish()
            })
        return (root, store)
    }

    private nonisolated static func writeSolidTIFF(_ url: URL) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let size = 32
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw XCTSkip("bitmap context unavailable") }
        context.setFillColor(CGColor(srgbRed: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = context.makeImage() else {
            throw XCTSkip("CGImage render failed")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.tiff.identifier as CFString, 1, nil)
        else { throw XCTSkip("TIFF destination unavailable") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw XCTSkip("TIFF encode failed")
        }
        try Data(output as Data).write(to: url)
    }
}
