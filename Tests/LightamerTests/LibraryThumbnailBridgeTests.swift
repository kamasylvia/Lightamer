import CoreGraphics
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryThumbnailBridgeTests (Plan M2-3-1 T3, AC #5) — the dual-tier
// thumbnail bridge over REAL image files in a temp directory:
//
//   • the tier decision rides `hasEdits` — tier A never touches the render
//     leg, tier B never falls back to the embedded preview
//   • a fresh disk hit produces ZERO new productions (the `.lathumbs`
//     write-through is the authoritative cache); a stale thumb (source mtime
//     newer) regenerates
//   • the memory LRU evicts least-recently-used deterministically
//   • the global production cap holds under a fan-out
//   • same-id in-flight requests MERGE onto one production
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryThumbnailBridgeTests: XCTestCase {

    // MARK: - Fixture

    private var tempDirectory: URL!
    private var thumbsDirectory: URL!
    private var sources: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("thumb-bridge-\(UUID().uuidString)", isDirectory: true)
        thumbsDirectory = tempDirectory.appendingPathComponent(".Proj.lathumbs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: thumbsDirectory, withIntermediateDirectories: true)
        sources = []
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// An 8×8 opaque CGImage (any deterministic raster the tiers can return).
    private static func makeImage() -> CGImage {
        let width = 8, height = 8
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Write one real JPEG source file; returns its URL.
    private func makeSource(_ name: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        let data = try ThumbnailDiskStore.jpegData(from: Self.makeImage())
        try data.write(to: url)
        sources.append(url)
        return url
    }

    /// A library row pointing at a source path (pathKind 2 = absolute; the
    /// internal memberwise init is @testable-visible — Core stays zero-diff).
    private func makeRow(
        id: Int64, sourceURL: URL, hasEdits: Int64? = 0
    ) -> LibraryImageRow {
        LibraryImageRow(
            id: id, imagePath: sourceURL.path, pathKind: 2, volumeUUID: nil,
            cameraMake: nil, cameraModel: nil, lensModel: nil, iso: nil,
            focalLength: nil, aperture: nil, exposure: nil, captureDate: nil,
            fileStem: nil, fileExt: nil, exifSearchText: nil,
            exifSearchWords: nil, rating: nil, colorLabel: nil, keywords: nil,
            filename: nil, dir: nil, flag: nil, note: nil, hasEdits: hasEdits,
            paramsHash: nil, refCount: 0, addedTime: nil, modifiedTime: nil)
    }

    private func makeBridge(
        renderLeg: LibraryThumbnailBridge.RenderLeg? = nil,
        maxConcurrency: Int = 4,
        memoryCapacity: Int = 64
    ) -> LibraryThumbnailBridge {
        LibraryThumbnailBridge(
            thumbsDirectory: thumbsDirectory,
            renderLeg: renderLeg,
            resolveURL: { row in URL(fileURLWithPath: row.imagePath) },
            maxConcurrency: maxConcurrency,
            memoryCapacity: memoryCapacity)
    }

    /// The locked concurrency/entry observer the render legs report into.
    private final class ObservationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private(set) var maxActive = 0
        private(set) var entered = 0
        private var productionOrder: [Int64] = []

        func enter() {
            lock.lock(); defer { lock.unlock() }
            entered += 1
            active += 1
            maxActive = max(maxActive, active)
        }

        func exit() {
            lock.lock(); defer { lock.unlock() }
            active -= 1
        }

        func record(_ id: Int64) {
            lock.lock(); defer { lock.unlock() }
            productionOrder.append(id)
        }

        func snapshot() -> (entered: Int, maxActive: Int, order: [Int64]) {
            lock.lock(); defer { lock.unlock() }
            return (entered, maxActive, productionOrder)
        }
    }

    // MARK: - AC #5: the dual-tier decision (has_edits)

    func testTierAUsesTheEmbeddedPreviewAndNeverTheRenderLeg() async throws {
        let url = try makeSource("a.jpg")
        let box = ObservationBox()
        let leg: LibraryThumbnailBridge.RenderLeg = { _ in
            box.enter()
            defer { box.exit() }
            return Self.makeImage()
        }
        let bridge = makeBridge(renderLeg: leg)
        let image = await bridge.thumbnail(for: makeRow(id: 1, sourceURL: url, hasEdits: 0))
        XCTAssertNotNil(image, "tier A produces the ImageIO embedded preview")
        XCTAssertEqual(box.snapshot().entered, 0, "tier A never touches the render leg")
        let actual0 = await bridge.productionCount
        XCTAssertEqual(actual0, 1)
    }

    func testTierBRoutesThroughTheRenderLegSeam() async throws {
        let url = try makeSource("b.jpg")
        let box = ObservationBox()
        let leg: LibraryThumbnailBridge.RenderLeg = { _ in
            box.enter()
            try? await Task.sleep(nanoseconds: 30_000_000)
            box.exit()
            return Self.makeImage()
        }
        let bridge = makeBridge(renderLeg: leg)
        let image = await bridge.thumbnail(for: makeRow(id: 2, sourceURL: url, hasEdits: 1))
        XCTAssertNotNil(image, "tier B produces through the injected leg")
        XCTAssertEqual(box.snapshot().entered, 1)
        let actual1 = await bridge.productionCount
        XCTAssertEqual(actual1, 1)
    }

    func testTierBWithoutAWiredRenderLegMisses() async throws {
        let url = try makeSource("c.jpg")
        let bridge = makeBridge(renderLeg: nil)
        let image = await bridge.thumbnail(for: makeRow(id: 3, sourceURL: url, hasEdits: 1))
        XCTAssertNil(image, "no production leg wired → the row misses")
        let tierA = await bridge.thumbnail(for: makeRow(id: 4, sourceURL: url, hasEdits: 0))
        XCTAssertNotNil(tierA, "tier A is independent of the leg")
    }

    // MARK: - AC #5: disk cache hit = zero reproduction; staleness regenerates

    func testDiskCacheHitNeverReproduces() async throws {
        let url = try makeSource("d.jpg")
        let bridge = makeBridge()
        _ = await bridge.thumbnail(for: makeRow(id: 42, sourceURL: url, hasEdits: 0))
        let actual2 = await bridge.productionCount
        XCTAssertEqual(actual2, 1)

        // The write-through landed in the injected `.lathumbs` directory.
        let disk = ThumbnailDiskStore(directory: thumbsDirectory)
        XCTAssertTrue(disk.exists(relPath: "42"))

        // A fresh bridge over the SAME directory rides the disk tier.
        let second = makeBridge()
        _ = await second.thumbnail(for: makeRow(id: 42, sourceURL: url, hasEdits: 0))
        let secondCount = await second.productionCount
        XCTAssertEqual(secondCount, 0, "the disk hit produced nothing")
    }

    func testStaleDiskThumbRegenerates() async throws {
        let url = try makeSource("e.jpg")
        let bridge = makeBridge()
        _ = await bridge.thumbnail(for: makeRow(id: 43, sourceURL: url, hasEdits: 0))
        let actual3 = await bridge.productionCount
        XCTAssertEqual(actual3, 1)

        // The source outruns the thumb → the cache is stale → regenerate.
        // (The memory tier serves hits before the freshness probe by design —
        // staleness detection is the DISK tier's job; a fresh bridge mirrors
        // the relaunch/session-switch state where memory is empty.)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: url.path)
        let relaunched = makeBridge()
        _ = await relaunched.thumbnail(for: makeRow(id: 43, sourceURL: url, hasEdits: 0))
        let staleRegenerations = await relaunched.productionCount
        XCTAssertEqual(staleRegenerations, 1, "the stale thumb was regenerated")
        // And a follow-up request rides the fresh thumb without producing.
        _ = await relaunched.thumbnail(for: makeRow(id: 43, sourceURL: url, hasEdits: 0))
        let settled = await relaunched.productionCount
        XCTAssertEqual(settled, 1)
    }

    // MARK: - AC #5: the memory LRU

    func testMemoryLRUEvictsLeastRecentlyUsed() async throws {
        let url = try makeSource("f.jpg")
        let bridge = makeBridge(memoryCapacity: 2)
        let rowA = makeRow(id: 60, sourceURL: url)
        let rowB = makeRow(id: 61, sourceURL: url)
        let rowC = makeRow(id: 62, sourceURL: url)

        _ = await bridge.thumbnail(for: rowA)
        _ = await bridge.thumbnail(for: rowB)
        let lru0 = await bridge.memoryOrderForTesting()
        XCTAssertEqual(lru0, [60, 61])

        // Inserting the third thumb evicts the LRU entry (60).
        _ = await bridge.thumbnail(for: rowC)
        let lru1 = await bridge.memoryOrderForTesting()
        XCTAssertEqual(lru1, [61, 62])
        let actual5 = await bridge.productionCount
        XCTAssertEqual(actual5, 3)

        // Accessing 61 refreshes it — the next eviction takes 62.
        _ = await bridge.thumbnail(for: rowB)
        let lru2 = await bridge.memoryOrderForTesting()
        XCTAssertEqual(lru2, [62, 61])

        let rowD = makeRow(id: 63, sourceURL: url)
        _ = await bridge.thumbnail(for: rowD)
        let lru3 = await bridge.memoryOrderForTesting()
        XCTAssertEqual(lru3, [61, 63])
        // 62 was evicted from memory — but the disk tier catches it, so no
        // new production happens for it (only D produced).
        let actual6 = await bridge.productionCount
        XCTAssertEqual(actual6, 4)
    }

    // MARK: - AC #5: the concurrency cap + in-flight merge

    func testGlobalConcurrencyCapHoldsUnderFanOut() async throws {
        let box = ObservationBox()
        let leg: LibraryThumbnailBridge.RenderLeg = { _ in
            box.enter()
            try? await Task.sleep(nanoseconds: 60_000_000)
            box.exit()
            return Self.makeImage()
        }
        let bridge = makeBridge(renderLeg: leg, maxConcurrency: 2)
        let rows = try (0..<8).map { index -> LibraryImageRow in
            let url = try makeSource("fan-\(index).jpg")
            return makeRow(id: Int64(100 + index), sourceURL: url, hasEdits: 1)
        }
        let images = await withTaskGroup(
            of: CGImage?.self, returning: [CGImage?].self
        ) { group in
            for row in rows {
                group.addTask { await bridge.thumbnail(for: row) }
            }
            var collected: [CGImage?] = []
            for await image in group { collected.append(image) }
            return collected
        }
        XCTAssertEqual(images.count, 8)
        XCTAssertTrue(images.allSatisfy { $0 != nil })
        let stats = box.snapshot()
        XCTAssertEqual(stats.entered, 8, "every fan-out branch produced exactly once")
        XCTAssertLessThanOrEqual(
            stats.maxActive, 2, "the global cap holds under fan-out")
        let actual7 = await bridge.productionCount
        XCTAssertEqual(actual7, 8)
    }

    func testInFlightRequestsMergeOntoOneProduction() async throws {
        let url = try makeSource("g.jpg")
        let box = ObservationBox()
        let leg: LibraryThumbnailBridge.RenderLeg = { _ in
            box.enter()
            try? await Task.sleep(nanoseconds: 120_000_000)
            box.exit()
            return Self.makeImage()
        }
        let bridge = makeBridge(renderLeg: leg)
        let row = makeRow(id: 200, sourceURL: url, hasEdits: 1)

        let images = await withTaskGroup(
            of: CGImage?.self, returning: [CGImage?].self
        ) { group in
            for _ in 0..<6 {
                group.addTask { await bridge.thumbnail(for: row) }
            }
            var collected: [CGImage?] = []
            for await image in group { collected.append(image) }
            return collected
        }
        XCTAssertEqual(images.count, 6)
        let mergedCount = await bridge.productionCount
        XCTAssertEqual(
            mergedCount, 1,
            "same-id requests merge onto the one in-flight production")
    }

    func testCancelAllDropsTheRegistryAndRequestsReproduce() async throws {
        let url = try makeSource("h.jpg")
        let leg: LibraryThumbnailBridge.RenderLeg = { _ in
            try? await Task.sleep(nanoseconds: 120_000_000)
            return Self.makeImage()
        }
        let bridge = makeBridge(renderLeg: leg)
        let row = makeRow(id: 300, sourceURL: url, hasEdits: 1)

        let first = Task { await bridge.thumbnail(for: row) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await bridge.cancelAll()
        let second = await bridge.thumbnail(for: row)
        let firstImage = await first.value
        // The dropped production finishes into the void; the new request
        // produced its own thumb (the provider cancelAll twin semantics).
        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(second)
        let actual8 = await bridge.productionCount
        XCTAssertEqual(actual8, 2)
    }

    func testPrioritizeReordersQueuedProductions() async throws {
        let box = ObservationBox()
        let leg: LibraryThumbnailBridge.RenderLeg = { [weak box] source in
            box?.enter()
            try? await Task.sleep(nanoseconds: 250_000_000)
            box?.exit()
            let stem = source.deletingPathExtension().lastPathComponent
            box?.record(Int64(stem) ?? -1)
            return Self.makeImage()
        }
        let bridge = makeBridge(renderLeg: leg, maxConcurrency: 1)

        // A (running) → B, C queue behind it. Promoting C must land it
        // BEFORE B when A's slot hands over.
        let a = try makeSource("1.jpg")
        let b = try makeSource("2.jpg")
        let c = try makeSource("3.jpg")
        let rowA = makeRow(id: 1, sourceURL: a, hasEdits: 1)
        let rowB = makeRow(id: 2, sourceURL: b, hasEdits: 1)
        let rowC = makeRow(id: 3, sourceURL: c, hasEdits: 1)

        async let resultA = bridge.thumbnail(for: rowA)
        async let resultB = bridge.thumbnail(for: rowB)
        async let resultC = bridge.thumbnail(for: rowC)
        // Deterministic readiness: poll until BOTH B and C sit in the gate
        // queue (a wall-clock sleep races under full-suite load — the
        // 15:42 run proved it), then promote C.
        let deadline = Date().addingTimeInterval(10)
        while await bridge.queuedCountForTesting() < 2 {
            if Date() > deadline {
                XCTFail("B and C never queued behind A")
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await bridge.prioritize([3])

        _ = await (resultA, resultB, resultC)
        let order = box.snapshot().order
        XCTAssertEqual(order.first, 1, "A ran first (it held the slot)")
        XCTAssertEqual(order.last, 2, "the unpromoted B ran last")
        XCTAssertEqual(order.dropFirst().first, 3, "the promoted C jumped the queue")
    }
}
