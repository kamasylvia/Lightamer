import CoreGraphics
import XCTest
import UniformTypeIdentifiers

import LightamerCore
import LightamerIOP

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// McpMatchColorToolsetTests (Plan M5-1-03 T1, KD-1) — the match_color tool
// face:
//
//   • SCHEMA: required reference, the solver enum, the batch cap, the
//     targets-required-when-no-current-image typed faces;
//   • REFERENCE RESOLUTION (checker m6, both forms): library image id →
//     LibraryStore.image(id:) → ImageLinker.resolve → URL; relPath →
//     resolveMember (load_image 语义同源); each typed-failure face;
//   • FAN-OUT + HEADLESS BATCH (checker E6): two non-open targets → two
//     INDEPENDENT solutions (per-target source statistics), the store-level
//     attach seam lands each (sidecar truth on disk);
//   • ATTACH=FALSE (checker m4): the params group rides apply_params back
//     (the explicit-null key set accepts it);
//   • strength/solver passthrough, the CDF asset arm, the GUI-live hard
//     rejection (write-only), the render-gate serialization, the
//     list_iops/apply_params metadata reuse, and the G1 determinism
//     disclosure (double call → same solveHash).
//
// Fixtures: synthetic TIFF sessions under NSTemporaryDirectory (L009) —
// deterministic decode, no RAW dependency (KD-2's synthetic-fixture rule).
// ─────────────────────────────────────────────────────────────────────────────

final class McpMatchColorToolsetTests: XCTestCase {

    private var tempDirectory: URL!
    private var libraryFileStores: [ProjectFileStore] = []

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-match-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        MatchColorToolset.resetForTesting()
    }

    override func tearDown() async throws {
        MatchColorToolset.resetForTesting()
        for store in libraryFileStores {
            try? await store.close()
        }
        libraryFileStores = []
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A deterministic vertical-gradient TIFF (8-bit sRGB — the M4-1 raster
    /// decode family; no CIRAW, no external fixture).
    nonisolated static func writeTIFF(
        _ url: URL, top: (Double, Double, Double), bottom: (Double, Double, Double),
        size: Int = 96
    ) throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw XCTSkip("bitmap context unavailable") }
        for y in 0..<size {
            let t = Double(y) / Double(size - 1)
            let r = top.0 + (bottom.0 - top.0) * t
            let g = top.1 + (bottom.1 - top.1) * t
            let b = top.2 + (bottom.2 - top.2) * t
            context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: size, height: 1))
        }
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

    /// Synthetic session with REAL decodable TIFF members.
    private func makeSession(
        _ files: [(name: String, top: (Double, Double, Double), bottom: (Double, Double, Double))]
    ) async throws -> (root: URL, store: SessionIndexStore, relPaths: [String]) {
        let root = tempDirectory.appendingPathComponent(
            "session-\(UUID().uuidString)", isDirectory: true)
        let capture = root.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        var entries: [SessionScanEntry] = []
        var relPaths: [String] = []
        for file in files {
            let url = capture.appendingPathComponent(file.name)
            try Self.writeTIFF(url, top: file.top, bottom: file.bottom)
            let relPath = "Capture/\(file.name)"
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

    private func makeMetal() async throws -> MetalContext {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ColormatchKernel.metalBundle)
        return metal
    }

    /// Seams over a POPULATED module registry (the extraction materializes
    /// boxes through it).
    private func makePopulatedSeams(
        session: (root: URL, store: SessionIndexStore, relPaths: [String]),
        metal: MetalContext?,
        liveImageURL: @escaping @Sendable () async -> URL? = { nil }
    ) async -> EditingToolset.Seams {
        let populated = ModuleRegistry()
        await LightamerIOPRegistry.populate(populated)
        var seams = EditingToolset.Seams(
            session: { (session.store, session.root) },
            metal: { metal },
            modules: { populated },
            gate: McpRenderGate(),
            liveImageURL: liveImageURL)
        seams.writeGate = McpRenderGate()
        return seams
    }

    private func makeRegistry(seams: EditingToolset.Seams) async -> McpToolRegistry {
        let registry = McpToolRegistry()
        await EditingToolset.register(into: registry, seams: seams)
        return registry
    }

    /// A library project fixture + one absolute-path image row (the id form's
    /// happy path).
    private func makeLibrary() async throws -> (
        store: LibraryStore, directory: URL, imageID: Int64, imageURL: URL
    ) {
        let packageURL = tempDirectory.appendingPathComponent("MatchLib.lalb")
        let fileStore = ProjectFileStore(at: packageURL)
        libraryFileStores.append(fileStore)
        _ = try await fileStore.create(name: "MatchLib")
        let store = LibraryStore(store: fileStore)
        let imageURL = tempDirectory.appendingPathComponent("lib-ref.tif")
        try Self.writeTIFF(
            imageURL, top: (0.85, 0.55, 0.30), bottom: (0.45, 0.25, 0.15))
        let id = try await store.insertImage(record: LibraryImageRecord(
            imagePath: imageURL.path, pathKind: .absolute))
        return (store, packageURL, id, imageURL)
    }

    /// Installs the (store, directory) provider (the GUI assembly 同形 —
    /// T5 勘正: the anchor is the package DIRECTORY, not the .lalb file
    /// url, the 20997721 precedent's third instance).
    private func installLibrary(_ library: (store: LibraryStore, directory: URL, imageID: Int64, imageURL: URL)) {
        MatchColorToolset.installLibraryProvider {
            (library.store, library.directory.deletingLastPathComponent())
        }
    }

    // MARK: - Call helpers

    private static func textPayload(_ output: McpToolOutput) throws -> String {
        for content in output.content {
            if case .text(let text) = content { return text }
        }
        throw McpToolError.internalError("expected a text payload")
    }

    private static func callMatchColor(
        _ registry: McpToolRegistry, _ arguments: [String: McpJSON]
    ) async throws -> [String: Any] {
        let output = try await registry.call(name: "match_color", arguments: arguments)
        let text = try textPayload(output)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8), options: [])
                as? [String: Any], text)
    }

    private static func results(_ answer: [String: Any]) -> [[String: Any]] {
        (answer["results"] as? [[String: Any]]) ?? []
    }

    private static func failures(_ answer: [String: Any]) -> [[String: Any]] {
        (answer["errors"] as? [[String: Any]]) ?? []
    }

    private static func sidecarColormatchParams(
        _ imageURL: URL
    ) throws -> [String: Any]? {
        guard let document = ExportRenderer.readDocument(imageURL: imageURL),
            let record = document.instances.first(where: {
                $0.opName == ColormatchModule.opName
            })
        else { return nil }
        return (try? JSONSerialization.jsonObject(
            with: record.paramsData, options: [])) as? [String: Any]
    }

    // MARK: - Schema / argument faces

    func testMissingReferenceIsInvalidParams() async throws {
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: nil))
        do {
            _ = try await registry.call(
                name: "match_color", arguments: ["targets": .string(session.relPaths[0])])
            XCTFail("missing reference must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }

    func testUnknownSolverIsInvalidParams() async throws {
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: nil))
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: ["reference": .string(session.relPaths[0]), "solver": .string("spectral")])
            XCTFail("unknown solver must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("gaussian-ot"))
        }
    }

    func testStrengthOutsideUnitRangeIsInvalidParams() async throws {
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: nil))
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: [
                    "reference": .string(session.relPaths[0]),
                    "strength": .double(1.5),
                ])
            XCTFail("strength > 1 must be invalidParams")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
        }
    }

    func testBatchOverCapIsInvalidParamsBeforeAnyGPUWork() async throws {
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        // NO metal on the seams: an over-cap batch must fail at the argument
        // layer (the cap guard precedes the gate/service, L050 fail-fast).
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: nil))
        let targets: [McpJSON] = Array(repeating: .string(session.relPaths[0]), count: 31)
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: ["reference": .string(session.relPaths[0]), "targets": .array(targets)])
            XCTFail("31 targets must exceed the 30 cap")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("30"))
        }
    }

    func testTargetsRequiredWithoutCurrentImage() async throws {
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        // No live image, no targets → the stateless D5 typed face.
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: nil))
        do {
            _ = try await registry.call(
                name: "match_color", arguments: ["reference": .string(session.relPaths[0])])
            XCTFail("targets must be required without a current image")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "invalidParams")
            XCTAssertTrue(error.message.contains("targets"))
        }
    }

    // MARK: - Reference resolution (checker m6, the two forms)

    func testRelPathReferenceSolvesAndAttachesWithDefaults() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let seams = await makePopulatedSeams(session: session, metal: metal)
        let registry = await makeRegistry(seams: seams)
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")

        // Defaults: strength 1.0, gaussian-ot, attach true.
        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        let result = try XCTUnwrap(Self.results(answer).first)
        XCTAssertEqual(result["target"] as? String, "Capture/target.tif")
        XCTAssertEqual(result["op"] as? String, "colormatch")
        XCTAssertEqual(result["status"] as? String, "attached")
        XCTAssertEqual(answer["solver"] as? String, "gaussianOT")
        XCTAssertEqual(answer["strength"] as? Double, 1.0)
        XCTAssertNotNil(result["instanceId"], "attach=true returns the instance id")
        XCTAssertNotNil(result["solveHash"])

        // The disk truth: the sidecar carries the colormatch instance with
        // the solved params (one undoable write per target, before return).
        let params = try XCTUnwrap(Self.sidecarColormatchParams(targetURL))
        XCTAssertNotNil(params["sourceStatsHash"])
        XCTAssertNotNil(params["referenceStatsHash"])
        let matrix = try XCTUnwrap(params["matrix"] as? [Double])
        XCTAssertEqual(matrix.count, 9)
    }

    func testLibraryIDReferenceResolvesThroughLinker() async throws {
        let metal = try await makeMetal()
        let library = try await makeLibrary()
        installLibrary(library)
        let session = try await makeSession([
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: metal))

        // Form ①: digits → LibraryStore.image(id:) → ImageLinker.resolve.
        let answer = try await Self.callMatchColor(registry, [
            "reference": .string(String(library.imageID)),
            "targets": .string(session.relPaths[0]),
            "attach": .bool(false),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        XCTAssertEqual(Self.results(answer).count, 1)
        XCTAssertEqual(Self.results(answer).first?["status"] as? String, "params-only")
    }

    /// T5 (M7-4-01; M7-2/M7-3 ledger 5): the PATH-KIND 0 anchor leg — a
    /// projectRelative row resolves against the package DIRECTORY anchor.
    /// Absolute-kind rows could never catch the diseased anchor (the
    /// historical provider passed the .lalb FILE url — the 20997721
    /// precedent's lesson); this fixture rides kind 0, so the corrected
    /// directory anchor is POSITIVE evidence: the id-form reference
    /// resolves to <projectDir>/Media/x.tif and the tool answers (with
    /// the diseased anchor the same row is stale → typed).
    func testProjectRelativeRowResolvesAgainstTheDirectoryAnchor() async throws {
        let metal = try await makeMetal()
        let packageURL = tempDirectory.appendingPathComponent("AnchorLib.lalb")
        let fileStore = ProjectFileStore(at: packageURL)
        libraryFileStores.append(fileStore)
        _ = try await fileStore.create(name: "AnchorLib")
        let store = LibraryStore(store: fileStore)
        // The kind0 row: a PROJECT-RELATIVE path (Media/x.tif under the
        // package's directory — never inside the package file).
        let mediaDirectory = tempDirectory
            .appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaDirectory, withIntermediateDirectories: true)
        let imageURL = mediaDirectory.appendingPathComponent("x.tif")
        try Self.writeTIFF(
            imageURL, top: (0.85, 0.55, 0.30), bottom: (0.45, 0.25, 0.15))
        let id = try await store.insertImage(record: LibraryImageRecord(
            imagePath: "Media/x.tif", pathKind: .projectRelative))
        let anchor = packageURL.deletingLastPathComponent()
        MatchColorToolset.installLibraryProvider { (store, anchor) }
        // The anchor's correctness, direct: kind0 resolve ==
        // <projectDir>/Media/x.tif (the absolute-kind goldens cannot see
        // this face).
        let resolved = ImageLinker.resolve(
            imagePath: "Media/x.tif", pathKind: .projectRelative,
            volumeUUID: nil, projectDirectory: anchor)
        guard case .resolved(let url) = resolved else {
            return XCTFail(
                "the directory anchor must resolve the kind0 row: \(resolved)")
        }
        XCTAssertEqual(
            url.standardizedFileURL.path, imageURL.standardizedFileURL.path,
            "kind0 resolve == <projectDir>/Media/x.tif")
        // The provider face end-to-end: the id-form reference ANSWERS
        // (the pre-fix .lalb-file anchor made this exact row stale →
        // typed notSessionMember).
        let session = try await makeSession([
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let registry = await makeRegistry(
            seams: await makePopulatedSeams(session: session, metal: metal))
        let answer = try await Self.callMatchColor(registry, [
            "reference": .string(String(id)),
            "targets": .string(session.relPaths[0]),
            "attach": .bool(false),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
    }

    func testLibraryIDWithoutOpenLibraryIsTyped() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: metal))
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: [
                    "reference": .string("7"),
                    "targets": .string(session.relPaths[0]),
                    "attach": .bool(false),
                ])
            XCTFail("an id form without an open library must be typed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
            XCTAssertTrue(error.message.contains("no library project"))
        }
    }

    func testUnknownLibraryIDIsTyped() async throws {
        let metal = try await makeMetal()
        let library = try await makeLibrary()
        installLibrary(library)
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: metal))
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: [
                    "reference": .string(String(library.imageID + 999)),
                    "targets": .string(session.relPaths[0]),
                    "attach": .bool(false),
                ])
            XCTFail("an unknown library id must be typed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }
    }

    func testStaleLibraryIDIsTyped() async throws {
        let metal = try await makeMetal()
        let packageURL = tempDirectory.appendingPathComponent("StaleLib.lalb")
        let fileStore = ProjectFileStore(at: packageURL)
        libraryFileStores.append(fileStore)
        _ = try await fileStore.create(name: "StaleLib")
        let store = LibraryStore(store: fileStore)
        // A row whose file does NOT exist → the linker's stale face.
        let id = try await store.insertImage(record: LibraryImageRecord(
            imagePath: tempDirectory.appendingPathComponent("gone.tif").path,
            pathKind: .absolute))
        MatchColorToolset.installLibraryProvider { (store, packageURL.deletingLastPathComponent()) }
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: metal))
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: [
                    "reference": .string(String(id)),
                    "targets": .string(session.relPaths[0]),
                    "attach": .bool(false),
                ])
            XCTFail("a stale library reference must be typed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
            XCTAssertTrue(error.message.contains("does not resolve"))
        }
    }

    func testPathReferenceOutsideSessionIsTyped() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: metal))
        do {
            _ = try await registry.call(
                name: "match_color",
                arguments: [
                    "reference": .string("Elsewhere/missing.tif"),
                    "targets": .string(session.relPaths[0]),
                    "attach": .bool(false),
                ])
            XCTFail("a non-member reference must be typed")
        } catch let error as McpToolError {
            XCTAssertEqual(error.code, "notSessionMember")
        }
    }

    // MARK: - Fan-out + headless batch (checker E6)

    /// TWO non-open targets (no GUI-live image anywhere in the test) → the
    /// headless extraction + the store-level attach: two INDEPENDENT
    /// solutions against the same reference statistics, each landed as its
    /// own sidecar instance.
    func testHeadlessBatchFanOutTwoTargetsTwoSolutions() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("cool.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
            ("warm.tif", (0.80, 0.60, 0.25), (0.55, 0.35, 0.15)),
        ])
        let seams = await makePopulatedSeams(session: session, metal: metal)
        let registry = await makeRegistry(seams: seams)

        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .array([.string("Capture/cool.tif"), .string("Capture/warm.tif")]),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        let results = Self.results(answer)
        XCTAssertEqual(results.count, 2)

        // Per-target independent solutions: different source statistics →
        // different offsets (the design semantic, KD-1).
        let hashA = try XCTUnwrap(results[0]["solveHash"] as? String)
        let hashB = try XCTUnwrap(results[1]["solveHash"] as? String)
        XCTAssertNotEqual(hashA, hashB, "independent per-target solves")
        for result in results {
            let params = try XCTUnwrap(result["params"] as? [String: Any])
            let offset = try XCTUnwrap(params["offset"] as? [Double])
            XCTAssertEqual(offset.count, 3)
            XCTAssertNotNil(result["instanceId"])
            XCTAssertEqual(result["status"] as? String, "attached")
        }

        // The disk truth rides BOTH sidecars (the store-level seam).
        for name in ["cool.tif", "warm.tif"] {
            let url = session.root.appendingPathComponent("Capture/\(name)")
            let params = try XCTUnwrap(Self.sidecarColormatchParams(url))
            XCTAssertNotNil(params["matrix"])
        }
    }

    // MARK: - strength / solver passthrough

    func testStrengthAndSolverPassThroughToTheSidecar() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let seams = await makePopulatedSeams(session: session, metal: metal)
        let registry = await makeRegistry(seams: seams)
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")

        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
            "strength": .double(0.5),
            "solver": .string("reinhard"),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        let params = try XCTUnwrap(Self.sidecarColormatchParams(targetURL))
        XCTAssertEqual(try XCTUnwrap(params["strength"] as? Double), 0.5, accuracy: 1e-6)
        XCTAssertEqual(params["solver"] as? String, "reinhard")
    }

    // MARK: - The CDF arm (asset commit)

    func testCDFArmWritesAssetAndParams() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let seams = await makePopulatedSeams(session: session, metal: metal)
        let registry = await makeRegistry(seams: seams)
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")

        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
            "solver": .string("cdf"),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        let result = try XCTUnwrap(Self.results(answer).first)
        let params = try XCTUnwrap(result["params"] as? [String: Any])
        let assetRef = try XCTUnwrap(params["assetRef"] as? String)
        XCTAssertTrue(assetRef.contains("target.tif.lra.colormatch/"), assetRef)
        XCTAssertNotNil(params["assetHash"])

        // The derived asset exists beside the target (the commit-time IO).
        let directory = ColormatchCubeAsset.directory(forImageURL: targetURL)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1, "one .cube asset landed")
        XCTAssertTrue(files[0].hasSuffix(".cube"))

        // The sidecar record carries the same asset identity.
        let sidecarParams = try XCTUnwrap(Self.sidecarColormatchParams(targetURL))
        XCTAssertEqual(sidecarParams["assetRef"] as? String, assetRef)
    }

    // MARK: - attach = false (checker m4: the apply_params round trip)

    func testAttachFalseParamsRideApplyParamsBack() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let seams = await makePopulatedSeams(session: session, metal: metal)
        let registry = await makeRegistry(seams: seams)
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")

        // The seed-absent face (M5-1-01): apply_params can only address an
        // EXISTING colormatch instance (no derivable default) — the agent
        // flow creates it once via attach=true, then re-lands parameter
        // groups via attach=false + apply_params. Create first:
        let create = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
        ])
        XCTAssertTrue(Self.failures(create).isEmpty, "\(create)")

        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
            "strength": .double(0.4),
            "attach": .bool(false),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        let result = try XCTUnwrap(Self.results(answer).first)
        XCTAssertEqual(result["status"] as? String, "params-only")
        XCTAssertNil(result["instanceId"], "no attach → no instance id")
        let group = try XCTUnwrap(result["params"] as? [String: Any])
        let solveHash = try XCTUnwrap(result["solveHash"] as? String)

        // The m4 round trip: the returned group feeds apply_params verbatim
        // (the explicit-null key set accepts it; matrix/offset are catalog
        // keys) → the instance is re-parameterized on disk.
        var paramsJSON: [String: McpJSON] = [:]
        for (key, value) in group {
            paramsJSON[key] = try Self.mcpJSON(value)
        }
        let applied = try await registry.call(
            name: "apply_params",
            arguments: [
                "relPath": .string("Capture/target.tif"),
                "ops": .array([.object([
                    "opName": .string("colormatch"),
                    "params": .object(paramsJSON),
                ])]),
            ])
        guard case .text(let appliedText) = applied.content.first else {
            return XCTFail("apply_params must answer text")
        }
        XCTAssertTrue(appliedText.contains("applied=Capture/target.tif"), appliedText)
        let landed = try XCTUnwrap(Self.sidecarColormatchParams(targetURL))
        XCTAssertEqual(landed["sourceStatsHash"] as? String, group["sourceStatsHash"] as? String)
        XCTAssertEqual(landed["referenceStatsHash"] as? String, group["referenceStatsHash"] as? String)
    }

    // MARK: - The GUI-live faces

    func testGUILiveAttachTargetIsHardRejected() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")
        final class Box: @unchecked Sendable {
            var url: URL?
        }
        let box = Box()
        box.url = targetURL
        let seams = await makePopulatedSeams(
            session: session, metal: metal, liveImageURL: { box.url })
        let registry = await makeRegistry(seams: seams)

        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
        ])
        let failures = Self.failures(answer)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?["code"] as? String, "imageLiveInEditor")
        XCTAssertTrue(Self.results(answer).isEmpty)
        // The disk truth is untouched.
        XCTAssertNil(try Self.sidecarColormatchParams(targetURL))
    }

    func testGUILiveAttachFalseIsAReadOnlySolve() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")
        final class Box: @unchecked Sendable {
            var url: URL?
        }
        let box = Box()
        box.url = targetURL
        let seams = await makePopulatedSeams(
            session: session, metal: metal, liveImageURL: { box.url })
        let registry = await makeRegistry(seams: seams)

        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
            "attach": .bool(false),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        XCTAssertEqual(Self.results(answer).first?["status"] as? String, "params-only")
    }

    /// The default-target face: targets omitted + the editor's current image
    /// (a session member) → the current image is the target.
    func testDefaultTargetIsTheEditorCurrentImage() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let targetURL = session.root.appendingPathComponent("Capture/target.tif")
        final class Box: @unchecked Sendable {
            var url: URL?
        }
        let box = Box()
        box.url = targetURL
        let seams = await makePopulatedSeams(
            session: session, metal: metal, liveImageURL: { box.url })
        let registry = await makeRegistry(seams: seams)

        // attach=false so the live target is not write-rejected.
        let answer = try await Self.callMatchColor(registry, [
            "reference": .string("Capture/ref.tif"),
            "attach": .bool(false),
        ])
        XCTAssertTrue(Self.failures(answer).isEmpty, "\(answer)")
        XCTAssertEqual(
            Self.results(answer).first?["target"] as? String, "Capture/target.tif")
    }

    // MARK: - Determinism (G1, the agent-facing disclosure)

    func testDeterministicDoubleCallSameSolveHash() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let seams = await makePopulatedSeams(session: session, metal: metal)
        let registry = await makeRegistry(seams: seams)
        let arguments: [String: McpJSON] = [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
            "strength": .double(0.7),
            "attach": .bool(false),
        ]
        let first = try await Self.callMatchColor(registry, arguments)
        let second = try await Self.callMatchColor(registry, arguments)
        XCTAssertEqual(
            try XCTUnwrap(Self.results(first).first?["solveHash"] as? String),
            try XCTUnwrap(Self.results(second).first?["solveHash"] as? String),
            "same reference/target/parameters → same solveHash (G1)")
        // The matrix identity rides too (bit-stable solve).
        let matrixA = try XCTUnwrap(
            (Self.results(first).first?["params"] as? [String: Any])?["matrix"] as? [Double])
        let matrixB = try XCTUnwrap(
            (Self.results(second).first?["params"] as? [String: Any])?["matrix"] as? [Double])
        XCTAssertEqual(matrixA, matrixB)
    }

    // MARK: - The render gate (§RQ-14-13)

    func testMatchColorSerializesOnTheRenderGate() async throws {
        let metal = try await makeMetal()
        let session = try await makeSession([
            ("ref.tif", (0.85, 0.55, 0.30), (0.45, 0.25, 0.15)),
            ("target.tif", (0.30, 0.50, 0.80), (0.20, 0.30, 0.60)),
        ])
        let gate = McpRenderGate()
        let populated = ModuleRegistry()
        await LightamerIOPRegistry.populate(populated)
        var seams = EditingToolset.Seams(
            session: { (session.store, session.root) },
            metal: { metal },
            modules: { populated },
            gate: gate,
            liveImageURL: { nil })
        seams.writeGate = McpRenderGate()
        let registry = await makeRegistry(seams: seams)

        // HOLD the shared gate → the call may not complete → release → it
        // completes (the render-class consumption proof).
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var doneState = false
            func markDone() { lock.withLock { doneState = true } }
            var done: Bool { lock.withLock { doneState } }
        }
        let flag = Flag()
        let arguments: [String: McpJSON] = [
            "reference": .string("Capture/ref.tif"),
            "targets": .string("Capture/target.tif"),
            "attach": .bool(false),
        ]
        await gate.acquire()
        let task = Task {
            _ = try? await Self.callMatchColor(registry, arguments)
            flag.markDone()
        }
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(flag.done, "match_color must wait for the render gate")
        await gate.release()
        await task.value
        XCTAssertTrue(flag.done, "the call completes once the gate frees")
    }

    // MARK: - The metadata reuse (list_iops / apply_params)

    func testColormatchMetadataRidesListIopsAndApplyParams() async throws {
        let session = try await makeSession([("a.tif", (0.3, 0.5, 0.8), (0.2, 0.3, 0.6))])
        let registry = await makeRegistry(seams: await makePopulatedSeams(session: session, metal: nil))

        // Seed an EXISTING colormatch instance (apply_params can only
        // re-parameterize — the M5-1-01 seed-absent face; the instance
        // creation is the GUI add face / match_color attach).
        let url = session.root.appendingPathComponent("Capture/a.tif")
        let seed = ModuleInstance(
            module: ColormatchModule.self, multiPriority: 0,
            multiName: "colormatch", params: ColormatchModule.Params())
        let payload = PastePayload(
            sourceImageID: UUID(), sourceURL: nil, instances: [seed],
            layerStack: nil, copiedAt: Date())
        let writer = BatchSidecarWriter(root: session.root, store: session.store)
        let outcome = await SessionBatchApplier.apply(
            root: session.root, relPaths: [session.relPaths[0]], payload: payload,
            mode: .overwrite, seed: [], liveRelPaths: [], store: session.store,
            writer: writer, timestamp: Date(), label: "fixture seed")
        XCTAssertTrue(outcome.appliedRelPaths.contains(session.relPaths[0]))
        await writer.flushForTeardown()

        // list_iops carries the colormatch key reference (the existing
        // machinery — zero new metadata face).
        let catalog = try await registry.call(name: "list_iops", arguments: [:])
        guard case .text(let catalogText) = catalog.content.first else {
            return XCTFail("list_iops must answer text")
        }
        XCTAssertTrue(catalogText.contains("colormatch"), "the colormatch row rides")
        XCTAssertTrue(catalogText.contains("strength") && catalogText.contains("matrix"))

        // apply_params addresses colormatch (the tuning face).
        let applied = try await registry.call(
            name: "apply_params",
            arguments: [
                "relPath": .string(session.relPaths[0]),
                "ops": .array([.object([
                    "opName": .string("colormatch"),
                    "params": .object(["strength": .double(0.25)]),
                ])]),
            ])
        guard case .text(let appliedText) = applied.content.first else {
            return XCTFail("apply_params must answer text")
        }
        XCTAssertTrue(appliedText.contains("applied="), appliedText)
        let params = try XCTUnwrap(Self.sidecarColormatchParams(url))
        XCTAssertEqual(try XCTUnwrap(params["strength"] as? Double), 0.25, accuracy: 1e-6)
    }

    // MARK: - McpJSON bridging (the m4 group → apply_params overlay)

    private static func mcpJSON(_ value: Any) throws -> McpJSON {
        if value is NSNull { return .null }
        if let number = value as? NSNumber {
            // Bool rides NSNumber too — the group carries none, but stay honest.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if Double(number.intValue) == number.doubleValue {
                return .int(number.intValue)
            }
            return .double(number.doubleValue)
        }
        if let string = value as? String { return .string(string) }
        if let array = value as? [Any] {
            return .array(try array.map(mcpJSON))
        }
        if let object = value as? [String: Any] {
            return .object(try object.mapValues(mcpJSON))
        }
        throw McpToolError.internalError("unbridged JSON value: \(type(of: value))")
    }
}
