import CoreGraphics
import CoreImage
import XCTest
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// QuickLookRendererTests (Plan 13-1 T3) — the QL render seam suite:
//
//   • PARITY: the QL preview plane vs the ExportRenderer.renderStage plane
//     under a SHARED decode (CIRAW speckle-nondeterminism — the GUI-22
//     contentDedupeID lesson — forbids comparing two decodes; the chain
//     itself is deterministic). Byte-identical expectation; a documented
//     ≤1/255 relax domain stays available but is NOT needed here.
//   • the three-probe thumbnail chain, level by level: fresh thumbs direct
//     read (render-count = 0) → stale falls to the render leg → pristine
//     / corrupt sidecar fall to the tier-A embedded preview;
//   • the BOUNDED render: a fake-slow render degrades to the tier-A answer
//     within a tiny injected timeout (the 30 s production constant rides
//     the T2 perf.md verdict and is never waited on in tests).
//
// Fixtures: a synthetic session under NSTemporaryDirectory (L009 — never
// external volume); the real-RAW parity sample is the input/RAW pair DSC00012.ARW +
// .lra (skipped when a checkout lacks it).
// ─────────────────────────────────────────────────────────────────────────────

final class QuickLookRendererTests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var registry: ModuleRegistry!

    override func setUpWithError() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ql-renderer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        metal = try MetalContext()
        registry = ModuleRegistry.makeDefault()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Sendable test atoms (@Sendable render legs cannot touch self)

    /// The render-leg spy counter (lock-protected — the legs run detached).
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    /// A decode memo so the parity legs share ONE CIRAW decode (the speckle
    /// discipline — two decodes differ; one decode makes the comparison a
    /// pure chain statement). An actor: the legs call in serially.
    private actor DecodeMemo {
        private var value: DecodedImage?
        func decoded(for url: URL) async throws -> DecodedImage {
            if let value { return value }
            let decoded = try await RAWDecoder().decode(url)
            if value == nil { value = decoded }
            return value ?? decoded
        }
    }

    private static func makeSolidImage(width: Int = 64, height: Int = 48) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: - Session fixtures

    private func repoSample() throws -> (url: URL, sidecar: URL) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
        try Fixtures.require(url)
        return (url, URL(fileURLWithPath: url.path + ".lra"))
    }

    private func syntheticDecoded(width: Int, height: Int) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: gradient, rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    /// Build a synthetic session: root/Capture/<name> + an open+synced
    /// lindex row (via the REAL SessionIndexStore open path).
    private func makeSession(imageName: String) async throws -> (root: URL, store: SessionIndexStore) {
        let root = tempDirectory.appendingPathComponent("session-\(UUID().uuidString)", isDirectory: true)
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
        _ = try await store.openSession(root: root, scan: stream(of: [.init(entries: [entry])]))
        return (root, store)
    }

    /// Copy a REAL raster over the placeholder so the embedded (tier-A)
    /// preview exists, and optionally graft a READABLE sidecar (a copy of
    /// the repo sample's) so probe b engages.
    private func installRasterAndSidecar(imageURL: URL, rasterName: String, rasterExt: String)
        async throws
    {
        try FileManager.default.removeItem(at: imageURL)
        let raster = try Fixtures.raster(rasterName, rasterExt)
        try FileManager.default.copyItem(at: raster, to: imageURL)
    }

    private func stream(of pages: [SessionScanPage]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            for page in pages { continuation.yield(page) }
            continuation.finish()
        }
    }

    /// Bind the row's thumb record the way the browser producer would
    /// (state + params-hash pair — the freshness binding the probe checks).
    /// `stale` writes a DRIFTED thumb_params_hash (a lie about the render).
    private func bindThumb(
        relPath: String, sessionRoot: URL, store: SessionIndexStore,
        image: CGImage, stale: Bool
    ) async throws {
        // The OPEN store from makeSession (a fresh instance carries no
        // handle, and an EMPTY-scan reopen would diff-delete every row).
        let row = try await store.fetchRow(relPath: relPath)
        let disk = ThumbnailDiskStore(sessionRoot: sessionRoot)
        let url = try disk.write(image, relPath: relPath)
        try await store.updateThumbnailRecord(
            relPath: relPath,
            state: .rendered,
            thumbPath: url.path,
            paramsHash: stale ? "1234567890-drift" : row?.paramsHash)
    }

    private func lindexFingerprint(root: URL) throws -> (mtime: Date, size: Int64) {
        let url = SessionIndexSchema.databaseURL(forSessionRoot: root)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (values.contentModificationDate ?? Date(), Int64(values.fileSize ?? 0))
    }

    // MARK: - Parity (the专项)

    /// Same sidecar, same records, ONE shared decode → the QL preview plane
    /// and the ExportRenderer.renderStage plane must agree BYTE-IDENTICALLY
    /// (the reduction twin: only yiyin/sizing/encode are subtracted, and
    /// this configuration exercises none of them — percent-100 sizing IS
    /// the full-frame render).
    func testPreviewPlaneParityByteIdenticalSharedDecode() async throws {
        let sample = try repoSample()
        guard FileManager.default.fileExists(atPath: sample.sidecar.path) else {
            throw XCTSkip("parity sidecar missing: \(sample.sidecar.path)")
        }
        // Copy the pair into the temp workspace (never touch input/).
        let imageURL = tempDirectory.appendingPathComponent("parity.ARW")
        try FileManager.default.copyItem(at: sample.url, to: imageURL)
        try FileManager.default.copyItem(at: sample.sidecar, to: imageURL.appendingPathExtension("lra"))

        let memo = DecodeMemo()
        let decodeLeg: QuickLookRenderer.DecodeLeg = { try await memo.decoded(for: $0) }

        // The reference leg: the full export render stage (decode → chain →
        // routed render → exit → quantize), percent-100 → full-frame.
        let variant = ExportVariant(
            scalePercent: 100, format: .jpeg(quality: 0.9),
            colorSpace: .sRGB, yiyin: false)
        let request = ExportRenderer.Request(
            imageURL: imageURL,
            destinationDirectory: tempDirectory,
            occupiedNames: [],
            variant: variant)
        let stage = try await ExportRenderer.renderStage(
            request: request, metal: metal, registry: registry, decodeLeg: decodeLeg)

        // The QL leg: the preview plane at the FULL long edge (the decoded
        // extent is known only after the shared decode — the stage's output
        // size IS the full long edge by the percent-100 fold).
        let fullLongEdge = max(stage.outputWidth, stage.outputHeight)
        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: imageURL, targetLongEdge: fullLongEdge,
            metal: metal, registry: registry, decodeLeg: decodeLeg)

        XCTAssertEqual(rendered.plane.width, stage.plane.width)
        XCTAssertEqual(rendered.plane.height, stage.plane.height)
        XCTAssertEqual(rendered.plane.data, stage.plane.data,
                       "QL preview plane must be BYTE-IDENTICAL to the same-chain export render")
    }

    // MARK: - The render target size

    /// The QL render honors the REQUESTED long edge (no export sizing math:
    /// the caller's number IS the target — the 800×600 synthetic renders at
    /// long edge 400 → 400×300).
    func testRenderedPlaneHonorsRequestedLongEdge() async throws {
        let url = tempDirectory.appendingPathComponent("synthetic.ARW")
        try Data().write(to: url)
        let decoded = syntheticDecoded(width: 800, height: 600)
        let decodeLeg: QuickLookRenderer.DecodeLeg = { _ in decoded }

        let rendered = try await QuickLookRenderer.renderedPlane(
            imageURL: url, targetLongEdge: 400,
            metal: metal, registry: registry, decodeLeg: decodeLeg)
        XCTAssertEqual(rendered.plane.width, 400)
        XCTAssertEqual(rendered.plane.height, 300)

        let image = try QuickLookRenderer.image(from: rendered)
        XCTAssertEqual(image.width, 400)
        XCTAssertEqual(image.height, 300)
    }

    // MARK: - The three probes

    /// Probe a: fresh thumbs binding → the committed JPEG read, ZERO render
    /// (the render-leg spy must never fire) — and the WHOLE flow leaves the
    /// lindex byte/mtime-identical (the read-only red line).
    func testThumbnailFreshThumbsDirectReadZeroRender() async throws {
        let (root, store) = try await makeSession(imageName: "IMG_0001.ARW")
        let imageURL = root.appendingPathComponent("Capture/IMG_0001.ARW")
        try await bindThumb(relPath: "Capture/IMG_0001.ARW", sessionRoot: root,
                            store: store, image: Self.makeSolidImage(), stale: false)
        let before = try lindexFingerprint(root: root)

        let renderCalls = Counter()
        let renderLeg: QuickLookRenderer.RenderLeg = { _ in
            renderCalls.bump()
            return QuickLookRendererTests.makeSolidImage()
        }

        let outcome = await QuickLookRenderer.thumbnail(
            imageURL: imageURL, requestedLongEdge: 512,
            metal: metal, registry: registry, renderLeg: renderLeg)

        let after = try lindexFingerprint(root: root)
        XCTAssertEqual(outcome?.source, .thumbsCache, "fresh binding must answer from the thumbs cache")
        XCTAssertEqual(renderCalls.value, 0, "probe a must render NOTHING (the zero-render counter)")
        XCTAssertEqual(after.mtime, before.mtime, "lindex mtime must not move (read-only)")
        XCTAssertEqual(after.size, before.size, "lindex bytes must not move (read-only)")
    }

    /// Probe b: a STALE binding (hash drift) is a lie about the render —
    /// with a READABLE sidecar the chain falls to the headless render leg
    /// (probe b's gate is the sidecar truth, not the thumb state).
    func testThumbnailStaleThumbFallsToRenderLeg() async throws {
        let (root, store) = try await makeSession(imageName: "IMG_0002.ARW")
        let imageURL = root.appendingPathComponent("Capture/IMG_0002.ARW")
        // A REAL sidecar so probe b engages (the render leg answers).
        let sample = try repoSample()
        try FileManager.default.copyItem(
            at: sample.sidecar, to: imageURL.appendingPathExtension("lra"))
        try await bindThumb(relPath: "Capture/IMG_0002.ARW", sessionRoot: root,
                            store: store, image: Self.makeSolidImage(), stale: true)

        let answer = Self.makeSolidImage(width: 32, height: 32)
        let renderCalls = Counter()
        let renderLeg: QuickLookRenderer.RenderLeg = { _ in
            renderCalls.bump()
            return answer
        }

        let outcome = await QuickLookRenderer.thumbnail(
            imageURL: imageURL, requestedLongEdge: 512,
            metal: metal, registry: registry, renderLeg: renderLeg)
        XCTAssertEqual(outcome?.source, .rendered)
        XCTAssertEqual(renderCalls.value, 1)
    }

    /// Probe c: pristine (no sidecar) → the tier-A embedded preview —
    /// never a render (the 09-CONTEXT:77 double-tier ruling, QL face).
    func testThumbnailPristineFallsToEmbeddedPreview() async throws {
        let (root, _) = try await makeSession(imageName: "IMG_0003.jpg")
        let imageURL = root.appendingPathComponent("Capture/IMG_0003.jpg")
        // A REAL raster so the embedded preview exists (JPEG carries its own
        // full image as the embedded preview).
        try await installRasterAndSidecar(imageURL: imageURL, rasterName: "sample-gradient", rasterExt: "jpg")

        let renderCalls = Counter()
        let renderLeg: QuickLookRenderer.RenderLeg = { _ in
            renderCalls.bump()
            return QuickLookRendererTests.makeSolidImage()
        }

        let outcome = await QuickLookRenderer.thumbnail(
            imageURL: imageURL, requestedLongEdge: 512,
            metal: metal, registry: registry, renderLeg: renderLeg)
        XCTAssertEqual(outcome?.source, .embeddedPreview, "pristine must answer tier A")
        XCTAssertEqual(renderCalls.value, 0, "pristine must never render")
    }

    /// The level-by-level degrade: a CORRUPT sidecar (present, undecodable —
    /// readDocument nil's it) degrades to the tier-A preview; a THROWING
    /// render leg never crashes the chain either. QL never crashes.
    func testThumbnailCorruptSidecarDegradesToEmbeddedPreview() async throws {
        let (root, _) = try await makeSession(imageName: "IMG_0004.jpg")
        let imageURL = root.appendingPathComponent("Capture/IMG_0004.jpg")
        try await installRasterAndSidecar(imageURL: imageURL, rasterName: "sample-gradient", rasterExt: "jpg")
        // A garbage sidecar: present on disk, undecodable.
        try Data(repeating: 0xFF, count: 128).write(to: imageURL.appendingPathExtension("lra"))

        let outcome = await QuickLookRenderer.thumbnail(
            imageURL: imageURL, requestedLongEdge: 512,
            metal: metal, registry: registry,
            renderLeg: { _ in throw AppError.decodeFailed("injected") })
        XCTAssertEqual(outcome?.source, .embeddedPreview)
    }

    // MARK: - The bounded render

    /// A fake-slow render behind a READABLE sidecar (probe b engages) must
    /// NOT block: the typed timeout fires within a bounded wall clock and
    /// the thumbnail degrades to the tier-A answer.
    func testThumbnailRenderTimeoutDegradesBounded() async throws {
        let (root, _) = try await makeSession(imageName: "IMG_0005.jpg")
        let imageURL = root.appendingPathComponent("Capture/IMG_0005.jpg")
        try await installRasterAndSidecar(imageURL: imageURL, rasterName: "sample-gradient", rasterExt: "jpg")
        // A REAL sidecar document so probe b (the render leg) engages —
        // graft the repo sample's readable .lra under the new full name.
        let sample = try repoSample()
        try FileManager.default.copyItem(
            at: sample.sidecar, to: imageURL.appendingPathExtension("lra"))

        let start = DispatchTime.now()
        let outcome = await QuickLookRenderer.thumbnail(
            imageURL: imageURL, requestedLongEdge: 512,
            metal: metal, registry: registry,
            renderLeg: { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 s fake-slow
                return QuickLookRendererTests.makeSolidImage()
            },
            timeout: 0.3)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9

        XCTAssertLessThan(elapsed, 2.0, "the degrade must be bounded by the injected timeout")
        XCTAssertEqual(outcome?.source, .embeddedPreview, "a timed-out render degrades to tier A")
    }

    /// The boundedWait primitive itself: the winner answers; the slow leg
    /// surfaces the typed `RenderTimeout`.
    func testBoundedWaitSurfacesTypedTimeout() async throws {
        do {
            _ = try await QuickLookRenderer.boundedWait(seconds: 0.2, {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            })
            XCTFail("expected RenderTimeout")
        } catch let timeout as QuickLookRenderer.RenderTimeout {
            XCTAssertEqual(timeout.seconds, 0.2, accuracy: 0.01)
        }
    }

    /// The preview face: a failed render degrades to the tier-A embedded
    /// preview (QL never surfaces a hard failure for a previewable file).
    func testPreviewRenderFailureDegradesToEmbeddedPreview() async throws {
        let raster = try Fixtures.raster("sample-gradient", "jpg")
        let imageURL = tempDirectory.appendingPathComponent("preview-degrade.jpg")
        try FileManager.default.copyItem(at: raster, to: imageURL)

        let image = try await QuickLookRenderer.preview(
            imageURL: imageURL, targetLongEdge: 512,
            metal: metal, registry: registry,
            renderLeg: { _ in throw AppError.decodeFailed("injected") },
            timeout: 1.0)
        XCTAssertGreaterThan(image.width, 0)
    }

    /// The production constant: the T2 verdict (30 s) — pinned so a tuning
    /// change is a deliberate, recorded act (perf.md is the source).
    func testProductionTimeoutConstantMatchesPerfVerdict() {
        XCTAssertEqual(QuickLookRenderer.renderTimeout, 30)
    }
}
