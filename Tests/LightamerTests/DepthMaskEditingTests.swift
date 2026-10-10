import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DepthMaskEditingTests (M4-3-01 T4, KD-5) — the App orchestration face:
// the pure gate mapping, the .depth source naming, the zip resolver, the
// float readback, the preview cap geometry, and the commit seam (race
// guard + exactly-one history item) through the coordinator-driven
// harness (the RasterEditFaceTests/AIMaskEditPathsTests form).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class DepthMaskEditingTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("depth-editing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - The gate (pure, four states)

    func testEntryGateFourStateMapping() {
        // installed + package → ready
        XCTAssertEqual(
            DepthEntryGate.entry(status: .installed, packagePresent: true), .ready)
        // installed but unextracted → download guidance (self-heals through
        // a re-download; the refresh() resolver normally closes this gap)
        XCTAssertEqual(
            DepthEntryGate.entry(status: .installed, packagePresent: false),
            .needsDownload(hasDigest: true))
        XCTAssertEqual(
            DepthEntryGate.entry(status: .notInstalled, packagePresent: false),
            .needsDownload(hasDigest: true))
        // digestUnpublished → needsDownload with the 「待发布」 marker
        XCTAssertEqual(
            DepthEntryGate.entry(status: .digestUnpublished, packagePresent: false),
            .needsDownload(hasDigest: false))
        XCTAssertEqual(
            DepthEntryGate.entry(status: .downloading(0.42), packagePresent: false),
            .downloading(0.42))
        // corrupt → failed with the self-heal note (a re-download replaces)
        XCTAssertEqual(
            DepthEntryGate.entry(status: .corrupt, packagePresent: false),
            .failed("re-download will self-heal"))
        // bundled is a depth-impossible tier, but the mapping stays total
        XCTAssertEqual(
            DepthEntryGate.entry(status: .bundled, packagePresent: true), .ready)
    }

    // MARK: - The .depth source naming

    func testDepthSourceNamingRoundTripAndSegmentUntouched() {
        let layerID = UUID()
        let fileName = AIMaskSource.depth.fileName(forLayerID: layerID)
        XCTAssertTrue(fileName.hasPrefix("ai-depth-"), "the disjoint prefix")
        XCTAssertTrue(fileName.hasSuffix("\(layerID.uuidString).png"))
        XCTAssertEqual(AIMaskSource.source(ofFileName: fileName), .depth)
        // The segment discriminant is untouched (LayerEditingState :278's
        // judge reads source(ofFileName:) == .segment — a depth-named file
        // must never arm the segment session).
        XCTAssertEqual(
            AIMaskSource.source(ofFileName: "ai-segment-\(layerID.uuidString).png"),
            .segment)
        XCTAssertNotEqual(
            AIMaskSource.source(ofFileName: fileName),
            AIMaskSource.source(ofFileName: "ai-segment-\(layerID.uuidString).png"))
        // The whole family round-trips.
        for source in [AIMaskSource.subject, .segment, .skin, .depth] {
            XCTAssertEqual(
                AIMaskSource.source(
                    ofFileName: source.fileName(forLayerID: layerID)),
                source)
        }
    }

    // MARK: - The resolver (zip → extracted package, idempotent)

    private var resolverLocator: ModelLocator {
        ModelLocator(installationRootOverride: tempDirectory)
    }

    /// A real zip: <dir>/<profile>/depth-anything-v2-small-f16.mlpackage.zip
    /// containing the renamed package with one stub file.
    private func installZipFixture() throws -> (locator: ModelLocator, zip: URL) {
        let locator = resolverLocator
        let manifest = ModelAssetCatalog.depthAnythingV2SmallF16
        let profileDir = try locator.installedProfileURL(manifest.profileID)
        let staging = tempDirectory.appendingPathComponent("stage-\(UUID().uuidString)")
        let packageDir = staging.appendingPathComponent("depth-anything-v2-small-f16.mlpackage")
        try FileManager.default.createDirectory(
            at: packageDir, withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: packageDir.appendingPathComponent("Manifest.json"))
        let zipURL = profileDir.appendingPathComponent(manifest.assetFileName)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", zipURL.path, "."]
        process.currentDirectoryURL = staging
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("zip fixture creation failed")
        }
        return (locator, zipURL)
    }

    func testResolverExtractsAndIsIdempotent() throws {
        let (locator, zipURL) = try installZipFixture()
        let manifest = ModelAssetCatalog.depthAnythingV2SmallF16
        let resolver = DepthPackageResolver(locator: locator)

        XCTAssertFalse(resolver.packagePresent(manifest), "zip-only start")
        try resolver.ensurePackage(manifest)
        let extracted = try XCTUnwrap(resolver.extractedPackageURL(manifest))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: extracted.appendingPathComponent("Manifest.json").path),
            "the stub file crossed the extraction")

        // Idempotent: a marker dropped INSIDE the extracted directory
        // survives the second ensurePackage (no re-extraction).
        let marker = extracted.appendingPathComponent("marker.txt")
        try Data("m".utf8).write(to: marker)
        try resolver.ensurePackage(manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        _ = zipURL
    }

    func testResolverTypedFailureOnCorruptZip() throws {
        let locator = resolverLocator
        let manifest = ModelAssetCatalog.depthAnythingV2SmallF16
        let profileDir = try locator.installedProfileURL(manifest.profileID)
        try Data("not-a-zip".utf8).write(
            to: profileDir.appendingPathComponent(manifest.assetFileName))
        let resolver = DepthPackageResolver(locator: locator)

        XCTAssertThrowsError(try resolver.ensurePackage(manifest)) { error in
            guard case DepthPackageResolver.ResolverError.extractionFailed = error else {
                return XCTFail("expected extractionFailed, got \(error)")
            }
        }
        XCTAssertNil(resolver.extractedPackageURL(manifest), "nothing landed")
    }

    // MARK: - The float readback (8-byte header)

    func testFloatReadbackRoundTripAndTypedHeaderMismatch() throws {
        let width = 6, height = 4
        let floats: [Float] = (0..<(width * height)).map { Float($0) / 100 }
        var data = Data(count: 8 + floats.count * 4)
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            raw.storeBytes(of: UInt32(width).littleEndian, toByteOffset: 0, as: UInt32.self)
            raw.storeBytes(of: UInt32(height).littleEndian, toByteOffset: 4, as: UInt32.self)
            floats.withUnsafeBytes { source in
                raw.baseAddress!.advanced(by: 8)
                    .copyMemory(from: source.baseAddress!, byteCount: floats.count * 4)
            }
        }
        let url = tempDirectory.appendingPathComponent("plane.f32")
        try data.write(to: url)

        let plane = try DepthMaskService.readDepthPlane(
            from: url, expectedWidth: width, expectedHeight: height)
        XCTAssertEqual(plane.floats, floats, "L048: F32 原值 read-back")

        // w/h mismatch → typed invalidInput (the m2 manifest-sourced check).
        XCTAssertThrowsError(
            try DepthMaskService.readDepthPlane(
                from: url, expectedWidth: height, expectedHeight: width)
        ) { error in
            guard case AIMaskError.invalidInput(let message) = error else {
                return XCTFail("expected invalidInput, got \(error)")
            }
            XCTAssertTrue(message.contains("shape"), message)
        }
        // Truncated file → typed.
        try Data(count: 4).write(to: url)
        XCTAssertThrowsError(
            try DepthMaskService.readDepthPlane(
                from: url, expectedWidth: width, expectedHeight: height)
        ) { error in
            XCTAssertEqual(
                error as? AIMaskError, .invalidInput(
                    "depth output truncated: 4 bytes"))
        }
    }

    // MARK: - The preview JPEG (long-edge 1040 cap)

    func testPreviewJPEGCapsLongEdge() throws {
        func gradient(_ width: Int, _ height: Int) -> AIMaskInput {
            let ramp = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            return AIMaskInput(ciImage: ramp)
        }
        // A 2000×1000 frame caps to 1040×520.
        let big = try DepthMaskService.writePreviewJPEG(from: gradient(2000, 1000))
        defer { try? FileManager.default.removeItem(at: big) }
        let bigSource = try XCTUnwrap(CGImageSourceCreateWithURL(big as CFURL, nil))
        let bigProps = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(bigSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(bigProps[kCGImagePropertyPixelWidth] as? Int, 1040)
        XCTAssertEqual(bigProps[kCGImagePropertyPixelHeight] as? Int, 520)

        // A small frame passes through untouched.
        let small = try DepthMaskService.writePreviewJPEG(from: gradient(500, 250))
        defer { try? FileManager.default.removeItem(at: small) }
        let smallSource = try XCTUnwrap(CGImageSourceCreateWithURL(small as CFURL, nil))
        let smallProps = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(smallSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(smallProps[kCGImagePropertyPixelWidth] as? Int, 500)
        XCTAssertEqual(smallProps[kCGImagePropertyPixelHeight] as? Int, 250)
    }

    // MARK: - The toolbar's visual fold (T5, KD-6)

    /// The five faces fold from the pure gate + the local phase; the
    /// disabled「待发布」arm comes from needsDownload(hasDigest: false).
    func testEntryGateVisualFold() {
        XCTAssertEqual(
            DepthEntryGate.map(service: .ready, running: false), .generate)
        XCTAssertEqual(
            DepthEntryGate.map(service: .ready, running: true), .generating,
            "the running phase wins over the gate (the spinner face)")
        XCTAssertEqual(
            DepthEntryGate.map(
                service: .needsDownload(hasDigest: true), running: false),
            .download(armed: true))
        XCTAssertEqual(
            DepthEntryGate.map(
                service: .needsDownload(hasDigest: false), running: false),
            .download(armed: false),
            "the fail-closed face renders the DISABLED download entry")
        XCTAssertEqual(
            DepthEntryGate.map(service: .downloading(0.3), running: false),
            .downloading(0.3))
        XCTAssertEqual(
            DepthEntryGate.map(
                service: .failed("re-download will self-heal"), running: false),
            .retry)
    }

    // MARK: - The commit seam (race guard + one history item)

    private static let fixtureDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Tests/Fixtures/TiffRaster", isDirectory: true)
    }()

    /// The commit writes the sidecar + the masks directory NEXT TO the
    /// loaded image URL — loading the SHARED repo fixture directly would
    /// pollute `Tests/Fixtures/TiffRaster/` and race the
    /// RasterEditFaceTests restore leg across bundles (the M4-1 ledger
    /// item #6 family). Every commit test loads a TEMP COPY.
    private func tempFixtureCopy(_ name: String) throws -> URL {
        let source = Self.fixtureDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("fixture missing: \(name)")
        }
        let destination = tempDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        metal: MetalContext, editingState: LayerEditingState
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let editingState = LayerEditingState()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        return (editorState, coordinator, metal, editingState)
    }

    private func nearAlpha(width: Int = 32, height: Int = 32) -> AIMaskPlane {
        AIMaskPlane(
            width: width, height: height,
            floats: (0..<(width * height)).map { $0 % width < width / 2 ? 1 : 0 })
    }

    /// Matched anchor: the depth plane lands as EXACTLY ONE history item
    /// with the depth label, the raster payload on the selected layer, and
    /// the brush tool armed (the AI-06 landing form).
    func testCommitLandsExactlyOneItemAndArmsBrush() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let (editorState, coordinator, metal, editingState) = try await makeAssembly()
        let url = try tempFixtureCopy("srgb-matrix-8.tif")
        editorState.load(
            url: url, decoder: RAWDecoder(), metal: metal,
            logger: EditorState.decodeLogger)
        let start = Date()
        while editorState.isDecoding, Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(for: .milliseconds(50))
        }
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        editingState.select(layer.id)
        XCTAssertEqual(editorState.loadedImageURL, url, "the race token")
        let itemsBefore = editorState.history.items.count

        try await DepthMaskService.commit(
            nearAlpha(), decodeWidth: 32, decodeHeight: 32, anchor: url,
            coordinator: coordinator, editorState: editorState,
            editingState: editingState, metal: metal)

        XCTAssertEqual(
            editorState.history.items.count - itemsBefore, 1,
            "exactly ONE stackSnapshot item")
        let layer2 = try XCTUnwrap(editorState.adjustmentLayer(id: layer.id))
        XCTAssertNotNil(layer2.mask?.raster, "the raster payload landed")
        XCTAssertNotNil(layer2.mask?.raster?.maskHash, "the baked reference")
        XCTAssertEqual(editingState.activeTool, .brush, "the landing form")
    }

    /// The race guard: an anchor captured before an image switch discards
    /// the result typed — zero history items, zero raster payloads.
    func testCommitDiscardsOnImageSwitch() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let (editorState, coordinator, metal, editingState) = try await makeAssembly()
        let first = try tempFixtureCopy("srgb-matrix-8.tif")
        editorState.load(
            url: first, decoder: RAWDecoder(), metal: metal,
            logger: EditorState.decodeLogger)
        let start = Date()
        while editorState.isDecoding, Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(for: .milliseconds(50))
        }
        _ = editorState.addAdjustmentLayer()
        let staleAnchor = first  // captured BEFORE the switch
        let depthLabel = String(localized: "history_depth_mask")

        // The switch: a second document loads over the session (a real
        // load RESETS the session state — history/stack included — which
        // is exactly why the stale result must never land).
        let second = try tempFixtureCopy("no-icc-8.tif")
        editorState.load(
            url: second, decoder: RAWDecoder(), metal: metal,
            logger: EditorState.decodeLogger)
        while editorState.isDecoding, Date().timeIntervalSince(start) < 30 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotEqual(editorState.loadedImageURL, staleAnchor)

        do {
            try await DepthMaskService.commit(
                nearAlpha(), decodeWidth: 32, decodeHeight: 32,
                anchor: staleAnchor,
                coordinator: coordinator, editorState: editorState,
                editingState: editingState, metal: metal)
            XCTFail("the stale anchor must be refused")
        } catch let error as AIMaskError {
            guard case .invalidInput(let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("switched"), message)
        }
        XCTAssertFalse(
            editorState.history.items.contains { $0.label == depthLabel },
            "the discarded result lands NOTHING in the new session")
    }
}
