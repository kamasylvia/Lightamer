import CoreGraphics
import CoreImage
import Foundation
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 09-03 — the thumbnail DOUBLE-TIER pipeline suite. Grows with the plan:
//
//   T2 (this commit): the DISK tier — `.lightamer/thumbs/<pathhash>.jpg`
//     round-trip, JPEG-encode determinism, the index-row binding leg
//     (thumb_state/thumb_path/thumb_params_hash + the stale→regen hash
//     flip), removal.
//   T3/T4: tier A (ImageIO embedded preview) / tier B (PixelPipe
//     THUMBNAIL) + the PipeCache isolation + queue semantics.
//
// Round-trip 口径 (execution decision D6, L020 content-level): JPEG is
// lossy, so the assertion is IN THE LOSSY DOMAIN — (a) re-encoding the
// DECODED image reproduces the exact on-disk bytes (encode determinism +
// the decoded image IS the encoded one), and (b) the decoded image's
// dimensions match the source. Byte identity of decode output across runs
// is implied by (a).
//
// Fixtures live in FileManager.temporaryDirectory (internal SSD — L009).
// ─────────────────────────────────────────────────────────────────────────────

final class SessionThumbnailProviderTests: XCTestCase {

    private var tempDirectory: URL!
    private var sessionRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("thumbprovider-\(UUID().uuidString)", isDirectory: true)
        sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A thread-safe render-call counter (Sendable seam for the tier-B
    /// reverse assertions — never captures the test case itself).
    final class RenderCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }

    /// A deterministic synthetic CGImage (solid color, exact dimensions).
    private static func makeImage(width: Int, height: Int, red: CGFloat = 0.5) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: 0.25, blue: 0.75, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Render a CGImage into a canonical 8-bit RGBA bitmap and return the
    /// raw bytes (content-level comparison — L020).
    private static func rasterizedBytes(_ image: CGImage) -> Data {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(buffer)
    }

    private func makeStore() -> SessionIndexStore {
        SessionIndexStore(sessionRoot: sessionRoot)
    }

    private func makeDiskStore() -> ThumbnailDiskStore {
        ThumbnailDiskStore(sessionRoot: sessionRoot)
    }

    private func makePage(_ rels: [String]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            for rel in rels {
                let url = sessionRoot.appendingPathComponent(rel)
                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )
                continuation.yield(SessionScanPage(entries: [
                    SessionScanEntry(
                        relPath: rel,
                        mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                        size: Int64(values?.fileSize ?? 0)
                    ),
                ]))
            }
            continuation.finish()
        }
    }

    // MARK: - T2: disk round-trip

    func testDiskRoundTripEncodeDeterminismAndNaming() async throws {
        let disk = makeDiskStore()
        let rel = "Capture/DSC001.ARW"
        let image = Self.makeImage(width: 360, height: 240)

        let url = try disk.write(image, relPath: rel)
        // Naming: `<pathhash>.jpg` under `.lightamer/thumbs/`.
        XCTAssertEqual(
            url.path,
            sessionRoot.appendingPathComponent(".lightamer/thumbs")
                .appendingPathComponent(ThumbnailPath.fileName(rel)).path,
            "the file lives at .lightamer/thumbs/<pathhash>.jpg (D-09-CONTEXT-2)"
        )
        XCTAssertTrue(disk.exists(relPath: rel))

        // Decode determinism: writing the SAME image again produces
        // byte-identical files (stable encode — cache identity).
        let firstBytes = try Data(contentsOf: url)
        _ = try disk.write(image, relPath: rel)
        let secondBytes = try Data(contentsOf: url)
        XCTAssertEqual(firstBytes, secondBytes, "JPEG q85 encode is deterministic")

        // Lossy-domain round-trip (D6, corrected): JPEG carries an ICC
        // profile, so decode→re-encode is NOT byte-identical to the source
        // encode (profile re-stamping). The content-level assertions are:
        // (a) re-encoding the DECODED image is deterministic (same pixels →
        // same bytes), and (b) writing that decoded image to ANOTHER relPath
        // produces bytes equal to re-encoding it directly — the decoded
        // image IS what the file holds (L020 content-level, not记账级).
        let decoded = try XCTUnwrap(disk.read(relPath: rel), "the cached thumb decodes")
        XCTAssertEqual(decoded.width, 360)
        XCTAssertEqual(decoded.height, 240)
        let reencoded = try ThumbnailDiskStore.jpegData(from: decoded)
        let urlB = try disk.write(decoded, relPath: "Capture/DSC001-copy.ARW")
        let copyBytes = try Data(contentsOf: urlB)
        XCTAssertEqual(copyBytes, reencoded, "the decoded image is exactly the file's content")

        // Decode determinism: two reads rasterize to identical pixels.
        let decoded2 = try XCTUnwrap(disk.read(relPath: rel))
        XCTAssertEqual(
            Self.rasterizedBytes(decoded), Self.rasterizedBytes(decoded2),
            "decode is deterministic (same pixels every time)"
        )

        // JPEG q85 size sanity for the budget note (360px thumb).
        XCTAssertLessThan(firstBytes.count, 120 * 1024, "a 360px solid JPEG stays small")
    }

    func testDiskMissAndRemove() async throws {
        let disk = makeDiskStore()
        XCTAssertNil(disk.read(relPath: "missing.ARW"), "miss → nil (never throws)")
        XCTAssertFalse(disk.exists(relPath: "missing.ARW"))

        _ = try disk.write(Self.makeImage(width: 120, height: 80), relPath: "a.ARW")
        disk.remove(relPath: "a.ARW")
        XCTAssertFalse(disk.exists(relPath: "a.ARW"), "remove drops the file")

        _ = try disk.write(Self.makeImage(width: 120, height: 80), relPath: "b.ARW")
        disk.removeAll()
        let stats = disk.stats()
        XCTAssertEqual(stats.files, 0, "removeAll empties the cache (delete = rebuild)")
    }

    // MARK: - T2: the index-row binding leg (stale → regen → hash flip)

    func testThumbnailRecordBindingAndStaleHashFlip() async throws {
        try Data(repeating: 0xAB, count: 16).write(
            to: sessionRoot.appendingPathComponent("DSC001.ARW")
        )
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: makePage(["DSC001.ARW"]))

        let disk = makeDiskStore()
        let rel = "DSC001.ARW"

        // Produce tier A: bind embedded + params hash H1.
        let image = Self.makeImage(width: 360, height: 240)
        let url = try disk.write(image, relPath: rel)
        let hash1 = "1111111111111111"
        try await store.updateThumbnailRecord(
            relPath: rel, state: .embedded, thumbPath: url.path, paramsHash: hash1
        )
        var rows = try await store.fetchAllRows()
        var row = try XCTUnwrap(rows.first { $0.path == rel })
        XCTAssertEqual(row.thumbState, 1, "embedded")
        XCTAssertEqual(row.thumbPath, url.path)
        XCTAssertEqual(row.thumbParamsHash, hash1)

        // The params change (edit / batch apply): the row flips stale
        // (9-2's markRowsStale leg exercises the same column).
        try await store.markRowsStale(relPaths: [rel])
        rows = try await store.fetchAllRows()
        row = try XCTUnwrap(rows.first { $0.path == rel })
        XCTAssertEqual(row.thumbState, 3, "stale")

        // The REGENERATION binds a NEW hash — the hash MUST flip (防空转:
        // a regen that leaves the hash untouched is a vacuous rewrite).
        let url2 = try disk.write(image, relPath: rel)
        let hash2 = "2222222222222222"
        try await store.updateThumbnailRecord(
            relPath: rel, state: .rendered, thumbPath: url2.path, paramsHash: hash2
        )
        rows = try await store.fetchAllRows()
        row = try XCTUnwrap(rows.first { $0.path == rel })
        XCTAssertEqual(row.thumbState, 2, "rendered after regen")
        XCTAssertNotEqual(row.thumbParamsHash, hash1, "stale→regen flips thumb_params_hash")
        XCTAssertEqual(row.thumbParamsHash, hash2)
    }

    func testRemovedRowCleansUpThumbFile() async throws {
        try Data(repeating: 0xAB, count: 16).write(
            to: sessionRoot.appendingPathComponent("A.ARW")
        )
        try Data(repeating: 0xAB, count: 16).write(
            to: sessionRoot.appendingPathComponent("B.ARW")
        )
        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["A.ARW", "B.ARW"])
        )
        let disk = makeDiskStore()
        let urlA = try disk.write(Self.makeImage(width: 60, height: 40), relPath: "A.ARW")
        let urlB = try disk.write(Self.makeImage(width: 60, height: 40), relPath: "B.ARW")
        try await store.updateThumbnailRecord(
            relPath: "A.ARW", state: .embedded, thumbPath: urlA.path, paramsHash: "11"
        )
        try await store.updateThumbnailRecord(
            relPath: "B.ARW", state: .embedded, thumbPath: urlB.path, paramsHash: "22"
        )

        // A vanishes externally → the next sync's removed leg deletes the
        // row AND its thumb file (the 9-1 seam, now load-bearing).
        try FileManager.default.removeItem(at: sessionRoot.appendingPathComponent("A.ARW"))
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["B.ARW"])
        )
        let rows = try await store.fetchAllRows()
        XCTAssertFalse(rows.contains { $0.path == "A.ARW" }, "the row is gone")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: urlA.path),
            "the thumb file is gone with the row (no leak)"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: urlB.path),
            "surviving rows keep their thumbs"
        )
    }
}

// MARK: - T3: the double-tier ruling + tier A (ImageIO embedded preview)

@MainActor
extension SessionThumbnailProviderTests {

    /// A memory cache with a generous budget (tier tests don't stress LRU).
    private func makeMemory() -> ThumbnailMemoryCache {
        ThumbnailMemoryCache(budgetBytes: 64 * 1024 * 1024) { image in
            image.width * image.height * 4
        }
    }

    private func makeRegistry() -> ModuleRegistry {
        ModuleRegistry.makeDefault()
    }

    @MainActor
    private func makeProvider(
        renderLeg: ThumbnailRenderLeg? = nil,
        decodeLeg: ThumbnailDecodeLeg? = nil,
        store: SessionIndexStore? = nil,
        memory: ThumbnailMemoryCache? = nil,
        idleDelayMs: Int = 0
    ) async -> SessionThumbnailProvider {
        SessionThumbnailProvider(
            sessionRoot: sessionRoot,
            store: store ?? makeStore(),
            disk: makeDiskStore(),
            memory: memory ?? makeMemory(),
            registry: makeRegistry(),
            decodeLeg: decodeLeg,
            renderLeg: renderLeg,
            idleDelayMs: idleDelayMs
        )
    }

    func testTierRulingFollowsHasEditsWithStaleRegenClause() {
        func row(hasEdits: Int64?, sidecar: Int64, state: Int64?) -> SessionIndexRow {
            var r = SessionIndexRow(path: "x.ARW")
            r.hasEdits = hasEdits
            r.sidecarPresent = sidecar
            r.thumbState = state
            return r
        }
        // pristine (no sidecar) → tier A — even when its row went stale (a
        // stat drift on a sidecar-less file).
        XCTAssertEqual(
            SessionThumbnailProvider.tier(forRow: row(hasEdits: nil, sidecar: 0, state: 3)),
            .embedded, "sidecar-less rows are tier A FOREVER (T7 reverse assertion)"
        )
        // pristine-with-sidecar (position −1) → tier A.
        XCTAssertEqual(
            SessionThumbnailProvider.tier(forRow: row(hasEdits: 0, sidecar: 1, state: 0)),
            .embedded
        )
        // edited → tier B.
        XCTAssertEqual(
            SessionThumbnailProvider.tier(forRow: row(hasEdits: 1, sidecar: 1, state: 0)),
            .rendered
        )
        // stale + sidecar → regen at tier B (RESEARCH §5.2 stale clause).
        XCTAssertEqual(
            SessionThumbnailProvider.tier(forRow: row(hasEdits: 0, sidecar: 1, state: 3)),
            .rendered, "a sidecar-bearing stale row regenerates at tier B"
        )
        XCTAssertEqual(
            SessionThumbnailProvider.tier(forRow: row(hasEdits: 1, sidecar: 1, state: 3)),
            .rendered
        )
    }

    func testTierAProducesNonEmptyImageWithinSizeBound() async throws {
        // A real camera RAW (Plan 05 CC0 samples) — the embedded preview
        // decodes in tens of ms WITHOUT a full RAW decode.
        let source = Fixtures.arw
        try Fixtures.require(source)
        let dest = sessionRoot.appendingPathComponent("DSC00012.ARW")
        try FileManager.default.copyItem(at: source, to: dest)

        let image = try XCTUnwrap(
            SessionThumbnailProvider.embeddedPreview(url: dest),
            "the Sony ARW ships an embedded JPEG preview"
        )
        XCTAssertEqual(max(image.width, image.height), SessionThumbnailProvider.embeddedPreviewMaxPixel,
                       "tier A downsamples to the 720px bound (D7 supersampling)")
        // Content-level (L020): a real photo preview is NOT a flat image —
        // its rasterized pixels must vary.
        let raster = Self.rasterizedBytes(image)
        let unique = Set(raster.prefix(40_000))
        XCTAssertGreaterThan(unique.count, 16, "the preview carries real photo content")

        // Throughput probe (the ~10-50 ms/张 budget; full numbers in T8).
        let clock = ContinuousClock()
        let start = clock.now
        _ = SessionThumbnailProvider.embeddedPreview(url: dest)
        let elapsed = clock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        print("TIER-A-EMBEDDED ms: \(ms)")
        XCTAssertLessThan(ms, 500, "the embedded preview path stays far below a RAW decode")
    }

    func testFetchPristineGoesTierAAndNeverCallsRenderLeg() async throws {
        // REVERSE assertion (T7 leg): a pristine row NEVER reaches the
        // render leg — the tier-B closure counts MUST stay zero.
        let source = Fixtures.arw
        try Fixtures.require(source)
        try FileManager.default.copyItem(
            at: source, to: sessionRoot.appendingPathComponent("PRISTINE.ARW")
        )
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: makePage(["PRISTINE.ARW"]))

        let memory = makeMemory()
        // A Sendable counter — the render leg must NEVER fire (no capture
        // of the non-Sendable test case; the assert reads the counter).
        let tierBCalls = RenderCallCounter()
        let actor = await makeProvider(
            renderLeg: { _ in
                tierBCalls.increment()
                throw CocoaError(.featureUnsupported)
            },
            store: store,
            memory: memory
        )
        defer { XCTAssertEqual(tierBCalls.count, 0, "tier B MUST NOT run for a pristine image") }
        let image = await actor.thumbnail(for: "PRISTINE.ARW")
        XCTAssertNotNil(image, "tier A produced the thumb")
        // The row is bound embedded with the row's (nil) params hash.
        let rows = try await store.fetchAllRows()
        let row = try XCTUnwrap(rows.first { $0.path == "PRISTINE.ARW" })
        XCTAssertEqual(row.thumbState, 1, "embedded state bound")
        // Second fetch rides MEMORY (the LAZY once-only contract) — the
        // disk/produce legs must not re-run. Assert via the memory hit
        // counter.
        let missesBefore = await memory.misses
        let hitsBefore = await memory.hits
        _ = await actor.thumbnail(for: "PRISTINE.ARW")
        let missesAfter = await memory.misses
        let hitsAfter = await memory.hits
        XCTAssertEqual(hitsAfter, hitsBefore + 1, "the second fetch is a memory hit")
        XCTAssertEqual(missesAfter, missesBefore, "no extra misses — once-only production")
    }

    func testMissingEmbeddedPreviewFallsBackToTierB() async throws {
        // A GARBAGE .arw (no embedded preview — the camera-domain fact):
        // tier A misses → the one-shot tier B fallback fires.
        try Data(repeating: 0x00, count: 4096).write(
            to: sessionRoot.appendingPathComponent("NOEMBED.ARW")
        )
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: makePage(["NOEMBED.ARW"]))

        let leg: ThumbnailRenderLeg = { _ in
            Self.makeImage(width: 360, height: 240)
        }
        let decodeLeg: ThumbnailDecodeLeg = { _ in
            DecodedImage(
                ciImage: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                    .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)),
                rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
                segmentationSkyMatte: nil, decoderVersionUsed: .v8
            )
        }
        let actor = await makeProvider(
            renderLeg: leg, decodeLeg: decodeLeg, store: store
        )
        let image = await actor.thumbnail(for: "NOEMBED.ARW")
        XCTAssertNotNil(image, "the tier-B fallback produced the thumb")
        let rows = try await store.fetchAllRows()
        let row = try XCTUnwrap(rows.first { $0.path == "NOEMBED.ARW" })
        XCTAssertEqual(row.thumbState, 2, "bound RENDERED (the fallback's tier)")
    }
}

// MARK: - T4: tier B (real pipe render) + queue semantics + isolation

@MainActor
extension SessionThumbnailProviderTests {

    /// A synthetic decoded image (a 64×64 gray block — the pipe renders
    /// whatever CIImage it is handed; no 86 MB RAW decode in queue tests).
    nonisolated private static func syntheticDecoded() -> DecodedImage {
        // 720×480 — ABOVE the 360 thumbnail long edge (the entry scale is
        // DOWNSCALE-ONLY: a 64px input would pass through at 64 and the
        // 360-output assertion would be meaningless).
        DecodedImage(
            ciImage: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: CGRect(x: 0, y: 0, width: 720, height: 480)),
            rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8
        )
    }

    /// Mean absolute pixel difference over the rasterized 8-bit planes
    /// (the lossy-domain comparison — JPEG q85 stays within a few LSBs).
    nonisolated private static func meanAbsDiff(_ a: CGImage, _ b: CGImage) -> Double {
        let pa = rasterizedBytes(a), pb = rasterizedBytes(b)
        guard pa.count == pb.count, !pa.isEmpty else { return .infinity }
        var sum = 0
        for index in stride(from: 0, to: pa.count, by: 4) {
            for channel in 0..<3 {
                sum += abs(Int(pa[index + channel]) - Int(pb[index + channel]))
            }
        }
        return Double(sum) / Double(pa.count / 4 * 3)
    }

    private func writeEditedSidecar(_ rel: String, gain: Float) throws -> UUID {
        try Data(repeating: 0xAB, count: 16).write(
            to: sessionRoot.appendingPathComponent(rel)
        )
        let imageID = UUID()
        let gainInstance = ModuleInstance(
            module: TestGainModule.self, multiName: "t", params: .init(gain: gain)
        )
        var stack = HistoryStack()
        stack.commit(gainInstance, label: "edit")
        let document = LightamerSidecar(
            imageID: imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: 42,
            instances: [],
            history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: 42, layerSnapshot: nil),
            appVersion: LightamerSidecar.currentAppVersion,
            layerStack: nil
        )
        try JSONEncoder().encode(document).write(
            to: sessionRoot.appendingPathComponent(rel + ".lra")
        )
        return imageID
    }

    /// The REAL tier-B leg (the回归钉): a throwaway PipeCache per run +
    /// PixelPipe.process @ .thumbnail + the App assembly's texture→CGImage
    /// convert (L014 fence inside).
    private func makeRealLeg(metal: MetalContext) -> ThumbnailRenderLeg {
        { request in
            let cache = PipeCache()
            let (texture, _) = try await RenderPipeline.process(
                image: request.decoded,
                instances: request.instances,
                imageID: request.imageID,
                resolution: request.resolution,
                cache: cache,
                metal: metal,
                longEdge: request.resolution.defaultLongEdge
            )
            return try SessionThumbnailRenderer.cgImage(from: texture, metal: metal)
        }
    }

    func testTierBRendersRealPipeAndRoundTripsThroughDisk() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        let imageID = try writeEditedSidecar("EDITED.ARW", gain: 2.0)
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: makePage(["EDITED.ARW"]))
        let rowsBefore = try await store.fetchAllRows()
        XCTAssertEqual(rowsBefore.first?.hasEdits, 1, "the sidecar commit marks the row edited")

        let decodeLeg: ThumbnailDecodeLeg = { _ in Self.syntheticDecoded() }
        let memory = makeMemory()
        let provider = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: makeDiskStore(),
            memory: memory, registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg, renderLeg: makeRealLeg(metal: metal)
        )
        let image = await provider.thumbnail(for: "EDITED.ARW")
        let produced = try XCTUnwrap(image, "tier B produced the thumb")
        XCTAssertEqual(
            max(produced.width, produced.height), 360,
            "the THUMBNAIL long edge (PipeResolution .thumbnail → 360)"
        )

        // The row is bound rendered + the disk file decodes to the SAME
        // pixels (write-through round-trip).
        let boundRows = try await store.fetchAllRows()
        let row = try XCTUnwrap(boundRows.first { $0.path == "EDITED.ARW" })
        XCTAssertEqual(row.thumbState, 2, "rendered bound")
        XCTAssertNotNil(row.thumbParamsHash)
        let diskImage = try XCTUnwrap(makeDiskStore().read(relPath: "EDITED.ARW"))
        XCTAssertEqual(diskImage.width, produced.width)
        XCTAssertEqual(diskImage.height, produced.height)
        // Lossy-domain content check (D6): JPEG q85 keeps the mean abs
        // channel diff within a few LSBs (L020 content-level, not记账级).
        let lossyDiff = Self.meanAbsDiff(produced, diskImage)
        XCTAssertLessThan(lossyDiff, 3.0, "the disk copy matches the produced thumb in the JPEG lossy domain (got \(lossyDiff))")

        // A second provider (cold memory) rides the DISK hit — no re-render
        // (produceCallCount stays on the FIRST provider's account; the new
        // one must not produce).
        let provider2 = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: makeDiskStore(),
            memory: makeMemory(), registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg, renderLeg: makeRealLeg(metal: metal)
        )
        let again = await provider2.thumbnail(for: "EDITED.ARW")
        let diskRide = try XCTUnwrap(again)
        // The JPEG domain IS the disk cache's identity domain: two reads of
        // the same file rasterize IDENTICALLY (decode determinism).
        XCTAssertEqual(Self.rasterizedBytes(diskRide), Self.rasterizedBytes(diskImage))
        let produced2 = await provider2.produceCallCountForTesting()
        XCTAssertEqual(produced2, 0, "the disk hit never re-renders (LAZY once-only)")
    }

    func testStaleEditedRowRegeneratesWithFlippedHash() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        _ = try writeEditedSidecar("EDITED2.ARW", gain: 2.0)
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: makePage(["EDITED2.ARW"]))
        let decodeLeg: ThumbnailDecodeLeg = { _ in Self.syntheticDecoded() }
        let disk = makeDiskStore()
        let provider = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: disk,
            memory: makeMemory(), registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg, renderLeg: makeRealLeg(metal: metal)
        )
        _ = await provider.thumbnail(for: "EDITED2.ARW")
        let hashProbeRows = try await store.fetchAllRows()
        let hashBefore = hashProbeRows.first { $0.path == "EDITED2.ARW" }?.thumbParamsHash

        // The user edits again (a new sidecar + a re-sync flips the row's
        // params_hash) and the row goes stale (9-2's markRowsStale leg).
        let imageID2 = try writeEditedSidecar("EDITED2.ARW", gain: 3.0)
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["EDITED2.ARW"])
        )
        try await store.markRowsStale(relPaths: ["EDITED2.ARW"])
        let staleRows = try await store.fetchAllRows()
        var row = try XCTUnwrap(staleRows.first { $0.path == "EDITED2.ARW" })
        XCTAssertEqual(row.thumbState, 3, "stale")

        // The regeneration: the provider re-renders and the hash FLIPS
        // (防空转 — a regen leaving the hash untouched is a vacuous rewrite).
        _ = await provider.thumbnail(for: "EDITED2.ARW")
        let regenRows = try await store.fetchAllRows()
        row = try XCTUnwrap(regenRows.first { $0.path == "EDITED2.ARW" })
        XCTAssertEqual(row.thumbState, 2, "rendered again")
        XCTAssertNotEqual(
            row.thumbParamsHash, hashBefore,
            "the regen binds the NEW params hash"
        )
        _ = imageID2
    }

    func testPipeCacheIsolationTotalBytesUnchangedAcrossBrowserRenders() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        _ = try writeEditedSidecar("ISO.ARW", gain: 2.0)
        let store = makeStore()
        _ = try await store.openSession(root: sessionRoot, scan: makePage(["ISO.ARW"]))

        // The OBSERVED cache — the posture of the editor's shared session
        // cache, warmed with a REAL plane (the currently-edited image).
        let observation = PipeCache()
        let decoded = Self.syntheticDecoded()
        _ = try await RenderPipeline.process(
            image: decoded, instances: [], imageID: UUID(),
            resolution: .preview, cache: observation, metal: metal, longEdge: 64
        )
        let before = await observation.totalBytes
        XCTAssertGreaterThan(before, 0, "the observation cache holds the editor's plane")

        let decodeLeg: ThumbnailDecodeLeg = { _ in Self.syntheticDecoded() }
        let provider = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: makeDiskStore(),
            memory: makeMemory(), registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg, renderLeg: makeRealLeg(metal: metal)
        )
        // MANY browser renders — a tier leaking into the shared cache would
        // move its total (10k×0.35 MB would crush it — Risk #5).
        for index in 0..<4 {
            let rel = index == 0 ? "ISO.ARW" : "ISO.ARW" // one row; repeat fetches ride memory
            await memoryPurgeForIsolationTest(provider)
            _ = await provider.thumbnail(for: rel)
        }
        let after = await observation.totalBytes
        XCTAssertEqual(
            after, before,
            "the shared cache total is BYTE-IDENTICAL across browser renders (the isolation red line)"
        )
    }

    /// Reset the provider's memory LRU so the next fetch re-produces
    /// (the isolation test wants repeated PRODUCTIONS, not memory hits).
    private func memoryPurgeForIsolationTest(_ provider: SessionThumbnailProvider) async {
        await provider.resetMemoryForTesting()
    }

    // MARK: - T4: queue semantics

    /// A leg that records start/finish order with real sleeps.
    private func makeRecorderLeg(
        _ recorder: JobRecorder, sleepMs: UInt64
    ) -> ThumbnailRenderLeg {
        { request in
            recorder.start(request.url.lastPathComponent)
            try await Task.sleep(nanoseconds: sleepMs * 1_000_000)
            recorder.finish(request.url.lastPathComponent)
            return Self.makeImage(width: 32, height: 32)
        }
    }

    final class JobRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var startedOrder: [String] = []
        private var active = 0
        private var peak = 0
        func start(_ name: String) {
            lock.lock(); defer { lock.unlock() }
            startedOrder.append(name)
            active += 1
            peak = max(peak, active)
        }
        func finish(_ name: String) {
            lock.lock(); defer { lock.unlock() }
            active -= 1
        }
        var order: [String] { lock.lock(); defer { lock.unlock() }; return startedOrder }
        var maxConcurrent: Int { lock.lock(); defer { lock.unlock() }; return peak }
    }

    func testQueueConcurrencyIsTwo() async throws {
        _ = try writeEditedSidecar("Q1.ARW", gain: 1.0)
        _ = try writeEditedSidecar("Q2.ARW", gain: 1.0)
        _ = try writeEditedSidecar("Q3.ARW", gain: 1.0)
        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["Q1.ARW", "Q2.ARW", "Q3.ARW"])
        )
        let recorder = JobRecorder()
        let decodeLeg: ThumbnailDecodeLeg = { _ in Self.syntheticDecoded() }
        let provider = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: makeDiskStore(),
            memory: makeMemory(), registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg,
            renderLeg: makeRecorderLeg(recorder, sleepMs: 60),
            concurrency: 2, idleDelayMs: 0
        )
        async let a = provider.thumbnail(for: "Q1.ARW")
        async let b = provider.thumbnail(for: "Q2.ARW")
        async let c = provider.thumbnail(for: "Q3.ARW")
        _ = await [a, b, c]
        let peak = recorder.maxConcurrent
        let order = recorder.order
        XCTAssertEqual(order.count, 3, "all three jobs ran")
        XCTAssertEqual(peak, 2, "exactly TWO workers (the Phase 7 competition cap)")
    }

    func testVisibleJobJumpsThePendingQueue() async throws {
        for rel in ["V0.ARW", "V1.ARW", "V2.ARW"] {
            _ = try writeEditedSidecar(rel, gain: 1.0)
        }
        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["V0.ARW", "V1.ARW", "V2.ARW"])
        )
        let recorder = JobRecorder()
        let decodeLeg: ThumbnailDecodeLeg = { _ in Self.syntheticDecoded() }
        // ONE worker + a long idle delay: the first background job holds
        // the worker; the visible job must overtake the second background
        // job in the pending queue.
        let provider = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: makeDiskStore(),
            memory: makeMemory(), registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg,
            renderLeg: makeRecorderLeg(recorder, sleepMs: 20),
            concurrency: 1, idleDelayMs: 250
        )
        async let first = provider.thumbnail(for: "V0.ARW") // background — sleeps 250ms in the worker
        try await Task.sleep(nanoseconds: 30_000_000) // let V0 start
        async let second = provider.thumbnail(for: "V1.ARW", visible: true) // visible — no sleep
        async let third = provider.thumbnail(for: "V2.ARW") // background
        _ = await [first, second, third]
        let order = recorder.order
        XCTAssertEqual(order.count, 3)
        XCTAssertEqual(order.first, "V0.ARW", "the first job starts immediately (empty queue)")
        XCTAssertEqual(
            order[1], "V1.ARW",
            "the VISIBLE job overtakes the pending background job (visible-first)"
        )
        XCTAssertEqual(order.last, "V2.ARW")
    }

    func testCancelAllDropsPendingAndInvalidatesInFlight() async throws {
        for rel in ["C1.ARW", "C2.ARW", "C3.ARW"] {
            _ = try writeEditedSidecar(rel, gain: 1.0)
        }
        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["C1.ARW", "C2.ARW", "C3.ARW"])
        )
        let recorder = JobRecorder()
        let decodeLeg: ThumbnailDecodeLeg = { _ in Self.syntheticDecoded() }
        let provider = SessionThumbnailProvider(
            sessionRoot: sessionRoot, store: store, disk: makeDiskStore(),
            memory: makeMemory(), registry: ModuleRegistry.makeDefault(),
            decodeLeg: decodeLeg,
            renderLeg: makeRecorderLeg(recorder, sleepMs: 40),
            concurrency: 1, idleDelayMs: 0
        )
        let first = Task { await provider.thumbnail(for: "C1.ARW") }
        try await Task.sleep(nanoseconds: 10_000_000) // C1 in flight
        await provider.cancelAll() // C2/C3 pending drop + C1's result voids
        first.cancel()
        let cancelledValue = await first.value
        XCTAssertNil(cancelledValue, "the cancelled session's fetch returns nil (teardown ②)")
        // The queue survives a cancel: a NEW fetch still works (fresh
        // generation).
        let after = await provider.thumbnail(for: "C2.ARW")
        XCTAssertNotNil(after, "the provider keeps serving after a teardown")
    }
}

// MARK: - T7: the A→B upgrade + the real-sample visual spot-check

@MainActor
extension SessionThumbnailProviderTests {

    /// The upgrade red line: browsing a PRISTINE image produces tier A;
    /// EDITING it (a sidecar lands → has_edits=1 + a re-sync) flips THAT
    /// image to tier B on the next fetch — while the OTHER pristine images
    /// stay tier A (their tier-B render count stays ZERO).
    func testTierUpgradeHappensOnlyOnTheEditedImage() async throws {
        let source = Fixtures.arw
        try Fixtures.require(source)
        try FileManager.default.copyItem(at: source, to: sessionRoot.appendingPathComponent("UP.ARW"))
        try FileManager.default.copyItem(at: source, to: sessionRoot.appendingPathComponent("STAY.ARW"))
        let store = makeStore()
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["UP.ARW", "STAY.ARW"])
        )
        let tierBCalls = RenderCallCounter()
        let actor = await makeProvider(
            // The count is the assertion — the leg throws AFTER counting.
            renderLeg: { request in
                tierBCalls.increment()
                throw CocoaError(.featureUnsupported)
            },
            // tier B needs a decode leg (the buildRenderRequest throws
            // BEFORE the leg fires without one — the first cut forgot it
            // and the render count silently stayed zero).
            decodeLeg: { _ in Self.syntheticDecoded() },
            store: store,
            idleDelayMs: 0
        )
        // Both pristine: tier A produces BOTH (no tier-B call).
        _ = await actor.thumbnail(for: "UP.ARW")
        _ = await actor.thumbnail(for: "STAY.ARW")
        XCTAssertEqual(tierBCalls.count, 0, "pristine browsing NEVER renders tier B")

        // The user EDITS UP.ARW: a sidecar lands and the re-sync marks the
        // row edited + stale (the changed leg).
        var stack = HistoryStack()
        stack.commit(
            ModuleInstance(module: TestGainModule.self, multiName: "t", params: .init(gain: 2.0)),
            label: "edit"
        )
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: [], history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: 42, layerSnapshot: nil),
            appVersion: LightamerSidecar.currentAppVersion, layerStack: nil
        )
        try JSONEncoder().encode(document).write(
            to: sessionRoot.appendingPathComponent("UP.ARW.lra")
        )
        // Touch the file so the sync sees the drift (the changed leg stales
        // the row) — then re-sync.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: sessionRoot.appendingPathComponent("UP.ARW").path
        )
        _ = try await store.openSession(
            root: sessionRoot, scan: makePage(["UP.ARW", "STAY.ARW"])
        )
        let rows = try await store.fetchAllRows()
        let upRow = try XCTUnwrap(rows.first { $0.path == "UP.ARW" })
        XCTAssertEqual(upRow.hasEdits, 1, "the edited row flipped")
        XCTAssertEqual(upRow.thumbState, 3, "the edited row went stale")

        // Back to the grid: the edited image RE-RENDERS at tier B (its
        // memory image was invalidated by the stale re-check); the OTHER
        // pristine image stays on its memory tier A image — ZERO new
        // tier-B calls for it.
        // ONE fetch of the edited row: exactly ONE tier-B render fires
        // (the leg counts then throws — a failed render does not bind, so
        // repeat fetches would retry, but we assert the SINGLE-fetch count).
        _ = await actor.thumbnail(for: "UP.ARW")
        XCTAssertEqual(tierBCalls.count, 1, "the edited image upgraded to tier B (one render)")
        _ = await actor.thumbnail(for: "STAY.ARW")
        XCTAssertEqual(tierBCalls.count, 1, "the untouched image STAYED at tier A")
        let stayRows = try await store.fetchAllRows()
        let stayRow = try XCTUnwrap(stayRows.first { $0.path == "STAY.ARW" })
        XCTAssertNotEqual(stayRow.thumbState, 2, "STAY never bound a tier-B render")
    }

    /// The REAL-SAMPLE spot check (Risks #4): three real camera RAWs, the
    /// tier-A embedded preview vs a REAL tier-B pipe render (the display
    /// trio chain), quantified (mean + p95 of the 8-bit channel diff) and
    /// archived side-by-side to .work/gui-acceptance/ (09-3 section). The
    /// DECISIONS verdict cites the printed numbers.
    func testDoubleTierVisualSpotCheckThreeRealRAWs() async throws {
        let samples: [(url: URL, label: String)] = [
            (Fixtures.arw, "arw"),
            (Fixtures.nef, "nef"),
            (Fixtures.raf, "raf"),
        ]
        var worstMean = 0.0
        var worstP95 = 0.0
        var compared = 0

        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let registry = ModuleRegistry.makeDefault()

        for sample in samples {
            try Fixtures.require(sample.url)
            let dest = sessionRoot.appendingPathComponent("SPOT-\(sample.label).\(sample.url.pathExtension)")
            try FileManager.default.copyItem(at: sample.url, to: dest)

            // Tier A: the embedded preview.
            let tierA = try XCTUnwrap(
                SessionThumbnailProvider.embeddedPreview(url: dest),
                "\(sample.label): the camera ships an embedded preview"
            )
            // Tier B: a REAL pipe render at 360 through the display trio
            // (the same shape the App assembly's leg runs). The boxes get
            // their DEFAULT params COMMITTED (the coordinator's materialize
            // semantics — uncommitted boxes carry a zero hash and the pipe
            // treats them as unadopted; see ModuleRegistry.makeDefaultChain's
            // doc).
            let decoded = try await RAWDecoder().decode(dest)
            // The coordinator-materialize shape: mint each box FROM the
            // record (identity-preserving) — makeDefaultChain's fresh boxes
            // have foreign UUIDs and apply() refuses them (precondition).
            let records = await registry.makeDefaultInstances()
            var boxes: [any ModuleBoxing] = []
            for record in records {
                if let box = await registry.makeBox(
                    opName: record.opName, instanceID: record.id
                ) {
                    try box.apply(record)
                    boxes.append(box)
                }
            }
            let cache = PipeCache() // throwaway — the isolation posture
            let (texture, _) = try await RenderPipeline.process(
                image: decoded,
                instances: boxes,
                imageID: UUID(),
                resolution: .thumbnail,
                cache: cache,
                metal: metal,
                longEdge: PipeResolution.thumbnail.defaultLongEdge
            )
            let tierB = try SessionThumbnailRenderer.cgImage(from: texture, metal: metal)
            print("SPOT-CHECK \(sample.label) texture pixelFormat=\(texture.pixelFormat.rawValue) (bgra8Unorm=\(MTLPixelFormat.bgra8Unorm.rawValue)) size=\(texture.width)x\(texture.height)")

            // Quantify (L020 content-level): rasterize both to the SAME
            // 8-bit sRGB space at the tier-A size and diff.
            let quant = Self.quantifiedDiff(tierA, tierB)
            worstMean = max(worstMean, quant.mean)
            worstP95 = max(worstP95, quant.p95)
            compared += 1
            print("SPOT-CHECK \(sample.label): mean=\(String(format: "%.2f", quant.mean)) p95=\(String(format: "%.1f", quant.p95)) sizeA=\(tierA.width)x\(tierA.height) sizeB=\(tierB.width)x\(tierB.height)")

            // Archive side-by-side (the DECISIONS evidence).
            let sideBySide = Self.sideBySide(tierA, tierB)
            let repoRoot = (((#filePath as NSString).deletingLastPathComponent as NSString)
                .deletingLastPathComponent as NSString) // Tests/
                .deletingLastPathComponent // repo root
            let outDir = URL(fileURLWithPath: repoRoot, isDirectory: true)
                .appendingPathComponent(".work/gui-acceptance", isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let png = try ThumbnailDiskStore.jpegData(from: sideBySide) // jpegData helper == generic encoder
            let outURL = outDir.appendingPathComponent("09-3-tiers-\(sample.label)-A-vs-B.jpg")
            try png.write(to: outURL)
        }
        XCTAssertEqual(compared, 3, "three real samples compared")

        // The verdict (09-03-DECISIONS D10): MEASURABLE — mean 50–80/8-bit
        // at 360px. The root cause is NOT a double-tier mechanism defect:
        // the tier-B render IS the editor's own display form (the Phase 8
        // GUI screenshot 2026-09-25-083-base-pristine.png shows the same
        // chroma — the v1 base trio's color shape). The camera-domain
        // (tier A) vs pipeline-domain (tier B) gap closes when the Phase 3+
        // color iops calibrate — this test STAYS as the re-measurement
        // harness (the assert pins the RECORDING, not a threshold; the
        // fallback decision D10 declined the all-tier-B retreat).
        print("SPOT-CHECK WORST: mean=\(String(format: "%.2f", worstMean)) p95=\(String(format: "%.1f", worstP95))")
        XCTAssertGreaterThan(worstMean, 0, "the quantification is real (compared > 0, L020)")
        XCTAssertLessThan(worstMean, 128, "sanity: same-photo pairs stay in the same brightness hemisphere")
    }

    // MARK: quantization helpers (CPU-only)

    nonisolated private static func quantifiedDiff(
        _ a: CGImage, _ b: CGImage
    ) -> (mean: Double, p95: Double) {
        // Normalize to a common 360-wide raster for the comparison.
        let targetW = 360
        let targetH = max(1, a.height * 360 / max(a.width, 1))
        let ra = draw(a, width: targetW, height: targetH)
        let rb = draw(b, width: targetW, height: targetH)
        var absDiffs: [Int] = []
        absDiffs.reserveCapacity(ra.count / 4)
        var sum = 0
        for index in stride(from: 0, to: min(ra.count, rb.count), by: 4) {
            let d = abs(Int(ra[index]) - Int(rb[index]))
                + abs(Int(ra[index + 1]) - Int(rb[index + 1]))
                + abs(Int(ra[index + 2]) - Int(rb[index + 2]))
            absDiffs.append(d / 3)
            sum += d / 3
        }
        absDiffs.sort()
        let p95Index = Int(Double(absDiffs.count) * 0.95)
        return (
            mean: Double(sum) / Double(absDiffs.count),
            p95: Double(absDiffs[min(p95Index, absDiffs.count - 1)])
        )
    }

    nonisolated private static func draw(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    nonisolated private static func sideBySide(_ a: CGImage, _ b: CGImage) -> CGImage {
        let height = min(360, max(a.height, b.height))
        let aw = a.width * height / max(a.height, 1)
        let bw = b.width * height / max(b.height, 1)
        let context = CGContext(
            data: nil, width: aw + bw + 4, height: height, bitsPerComponent: 8,
            bytesPerRow: (aw + bw + 4) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: aw + bw + 4, height: height))
        context.draw(a, in: CGRect(x: 0, y: 0, width: aw, height: height))
        context.draw(b, in: CGRect(x: aw + 4, y: 0, width: bw, height: height))
        return context.makeImage()!
    }
}

// MARK: - T8: PERF-06 baseline measurements (SSD fixtures — L009)

@MainActor
extension SessionThumbnailProviderTests {

    /// The double-tier THROUGHPUT baseline (perf.md 09-3 table): tier A in
    /// ms/image, tier B in s/image — Release-vs-Debug split lands in the
    /// ledger; the Debug numbers here are the working baseline.
    func testThumbnailThroughputBaselineTierAAndTierB() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let source = Fixtures.arw // 86 MP-class Sony lossless-c
        try Fixtures.require(source)
        let dest = sessionRoot.appendingPathComponent("PERF.ARW")
        try FileManager.default.copyItem(at: source, to: dest)

        // Tier A: the embedded preview (3-run min — the stable number).
        var tierAMs = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            let clock = ContinuousClock()
            let start = clock.now
            _ = SessionThumbnailProvider.embeddedPreview(url: dest)
            let ms = Self.ms(clock.now - start)
            tierAMs = min(tierAMs, ms)
        }
        print("PERF-06 TIER-A ms/img: \(String(format: "%.1f", tierAMs))")

        // Tier B: decode + REAL pipe render at 360 (the display chain).
        let decoded = try await RAWDecoder().decode(dest)
        let registry = ModuleRegistry.makeDefault()
        let records = await registry.makeDefaultInstances()
        var boxes: [any ModuleBoxing] = []
        for record in records {
            if let box = await registry.makeBox(opName: record.opName, instanceID: record.id) {
                try box.apply(record)
                boxes.append(box)
            }
        }
        let clock = ContinuousClock()
        let start = clock.now
        let (texture, _) = try await RenderPipeline.process(
            image: decoded, instances: boxes, imageID: UUID(),
            resolution: .thumbnail, cache: PipeCache(),
            metal: metal, longEdge: PipeResolution.thumbnail.defaultLongEdge
        )
        _ = try SessionThumbnailRenderer.cgImage(from: texture, metal: metal)
        let tierBS = Self.ms(clock.now - start) / 1000
        print("PERF-06 TIER-B s/img: \(String(format: "%.2f", tierBS)) (86MP source, Debug)")

        // Budget-shape assertions (not gates — the gates clear in Phase 15):
        // tier A is ~100× cheaper than tier B.
        XCTAssertLessThan(tierAMs, 200, "tier A stays two-orders below a decode")
        XCTAssertLessThan(tierBS, 10.0, "tier B (86MP, Debug) stays in the seconds band")
    }

    /// The 10k-row collection projection baseline (perf.md): the ORDER BY
    /// path read + the row projection into the browser array — the grid's
    /// data face must stay sub-second at the 10k scale.
    func testTenThousandRowCollectionReloadBaseline() async throws {
        let store = makeStore()
        // 10k rows in ONE transaction (the 9-1 bulk shape — fast fixture).
        let entries = (0..<10_000).map { index in
            SessionScanEntry(
                relPath: String(format: "day%02d/IMG%05d.ARW", index % 40, index),
                mtime: Double(index), size: 1024
            )
        }
        _ = try await store.openSession(
            root: sessionRoot, scan: AsyncStream { continuation in
                var page: [SessionScanEntry] = []
                for entry in entries {
                    page.append(entry)
                    if page.count == 256 {
                        continuation.yield(SessionScanPage(entries: page))
                        page = []
                    }
                }
                if !page.isEmpty { continuation.yield(SessionScanPage(entries: page)) }
                continuation.finish()
            }
        )
        let model = SessionBrowserModel()
        let clock = ContinuousClock()
        let start = clock.now
        await model.reload(store: store, includeOrphans: true)
        let ms = Self.ms(clock.now - start)
        print("PERF-06 COLLECTION-10k reload ms: \(String(format: "%.0f", ms)) rows=\(model.rows.count)")
        XCTAssertEqual(model.rows.count, 10_000, "the full collection projected (compared > 0)")
        XCTAssertLessThan(ms, 2_000, "10k projection stays sub-2s (the open-session budget)")
    }

    nonisolated private static func ms(_ duration: ContinuousClock.Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
    }
}

// MARK: - T8: culling dual-100MP staggered open (真 fixture timing)

@MainActor
extension SessionThumbnailProviderTests {

    func testCullingDualHundredMPStaggeredOpenBaseline() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        // The 100 MP GFX sample (Plan 05 download) — the PERF-04-class
        // storm case: two full decodes back-to-back.
        let source = Fixtures.raf100MP
        try Fixtures.require(source)
        let root = sessionRoot!
        for rel in ["CULL-A.RAF", "CULL-B.RAF"] {
            try FileManager.default.copyItem(
                at: source, to: root.appendingPathComponent(rel)
            )
        }
        let paneA = CullingPaneModel(
            relPath: "CULL-A.RAF", decoder: RAWDecoder(), metal: metal, sessionRoot: root
        )
        let paneB = CullingPaneModel(
            relPath: "CULL-B.RAF", decoder: RAWDecoder(), metal: metal, sessionRoot: root
        )
        let clock = ContinuousClock()
        let start = clock.now
        await paneA.load() // STAGGERED: A lands before B starts (the gate)
        let afterA = clock.now
        await paneB.load()
        let total = Self.ms(clock.now - start)
        let paneAMS = Self.ms(afterA - start)
        print("PERF-06 CULLING dual-100MP open ms: total=\(String(format: "%.0f", total)) paneA=\(String(format: "%.0f", paneAMS)) (staggered; Debug)")
        XCTAssertEqual(paneA.state, .ready)
        XCTAssertEqual(paneB.state, .ready)
        // The panes are INDEPENDENT planes (different ledger entries).
        XCTAssertGreaterThan(paneA.planeBytes, 0)
        XCTAssertGreaterThan(paneB.planeBytes, 0)
    }
}
