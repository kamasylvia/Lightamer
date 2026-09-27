import CoreImage
import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// CatalogThumbnailRouterTests (Plan 16-2 T5; RQ-16-9) — the cross-session
// thumbnail routing:
//
//   • POOL: the router lazily builds ONE provider per TOUCHED session over
//     the SINGLE shared memory LRU (zero new budget face); both providers
//     land in the same 384MB-class cache instance.
//   • NAMESPACED MEMORY KEYS (the correctness execution decision): the same
//     relPath in two sessions is two DIFFERENT files — each session gets
//     its own thumb (no cross-contamination), each rendered exactly once,
//     and repeat fetches ride the shared memory tier.
//   • OFFLINE: a session whose root is gone NEVER gets a provider — the
//     routed fetch returns nil with the pool untouched (零请求).
//   • LIFECYCLE: teardown drops the pool; the next fetch rebuilds lazily.
//
// Fixtures are REAL session folders with garbage RAW files (the embedded
// preview miss drives the tier-B fallback — the provider tests' pattern).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class CatalogThumbnailRouterTests: XCTestCase {

    private var tempDirectory: URL!
    private var catalogURL: URL!
    private var defaultsSuiteName: String!
    private var memory: ThumbnailMemoryCache!
    private var sessionRoots: [String: URL] = [:]
    private var renderCounter: RenderCallCounter!

    /// Thread-safe render-call counter (the provider tests' seam).
    final class RenderCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-thumbs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
        defaultsSuiteName = "catalog-thumbs-tests-\(UUID().uuidString)"
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuiteName)
        memory = ThumbnailMemoryCache(budgetBytes: 64 * 1024 * 1024) { image in
            image.width * image.height * 4
        }
        renderCounter = RenderCallCounter()

        // Two sessions, SAME relPath, DIFFERENT bytes (different files).
        for (name, fill) in [("sA", 0.2), ("sB", 0.8)] {
            let root = tempDirectory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true)
            try Data(repeating: UInt8(fill * 255), count: 4096).write(
                to: root.appendingPathComponent("IMG_0001.ARW"))
            sessionRoots[name] = root
            // The open+sync leg creates the lindex (the projector needs it).
            let store = SessionIndexStore(sessionRoot: root)
            _ = try await store.openSession(
                root: root, scan: Self.page(root: root, rels: ["IMG_0001.ARW"]))
            await store.close()
        }

        // Project both into the catalog (the registry the router reads).
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuiteName)
        for (_, root) in sessionRoots {
            _ = try await projector.project(sessionRoot: root)
        }
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private static func page(root: URL, rels: [String]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            for rel in rels {
                let url = root.appendingPathComponent(rel)
                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey])
                continuation.yield(SessionScanPage(entries: [
                    SessionScanEntry(
                        relPath: rel,
                        mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                        size: Int64(values?.fileSize ?? 0)),
                ]))
            }
            continuation.finish()
        }
    }

    private nonisolated static func makeImage(gray: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context.makeImage()!
    }

    private func makeRouter() -> CatalogThumbnailRouter {
        // Sendable-local captures only (the @Sendable legs never see the
        // test case itself — the provider tests' discipline).
        let counter = renderCounter!
        let catalogURL = self.catalogURL!
        let grayForURL: @Sendable (URL) -> CGFloat = { url in
            url.path.contains("/sA/") ? 0.2 : 0.8
        }
        return CatalogThumbnailRouter(
            memory: memory,
            registry: ModuleRegistry.makeDefault(),
            decoder: nil,
            decodeLeg: { _ in
                DecodedImage(
                    ciImage: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                        .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32)),
                    rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
                    segmentationSkyMatte: nil, decoderVersionUsed: .v8
                )
            },
            renderLeg: { request in
                // The stub tier-B leg counts every REAL production.
                counter.increment()
                return Self.makeImage(gray: grayForURL(request.url))
            },
            runContextInjector: nil,
            catalogStoreProvider: {
                CatalogIndexStore(databaseURL: catalogURL)
            }
        )
    }

    /// The registry's UUID session_id for a fixture folder name.
    private func registrySessionID(_ name: String) async throws -> String {
        let store = CatalogIndexStore(databaseURL: catalogURL!)
        let rows = try await store.fetchSessions()
        let row = try XCTUnwrap(
            rows.first { $0.rootPath.hasSuffix("/" + name) },
            "the fixture session \(name) must be registered")
        return row.sessionID
    }

    // MARK: - Pool routing + namespaced memory

    func testPoolRoutesBothSessionsWithNamespacedMemoryKeys() async throws {
        let router = makeRouter()
        let idA = try await registrySessionID("sA")
        let idB = try await registrySessionID("sB")

        // Session A produces (render #1).
        let thumbA = await router.thumbnail(sessionID: idA, relPath: "IMG_0001.ARW")
        XCTAssertNotNil(thumbA)
        XCTAssertEqual(renderCounter.count, 1)
        XCTAssertTrue(router.hasProvider(idA), "the pool lazily built A")

        // Session B, the SAME relPath, DIFFERENT file — its OWN thumb
        // (render #2; the namespaced keys prevent the cross-contamination
        // the naive shared relPath key would cause).
        let thumbB = await router.thumbnail(sessionID: idB, relPath: "IMG_0001.ARW")
        XCTAssertNotNil(thumbB)
        XCTAssertEqual(renderCounter.count, 2, "different file → own production")
        XCTAssertTrue(router.hasProvider(idB))

        // The shared pool: ONE memory cache instance serves both providers
        // (two namespaced keys), and repeat fetches ride the memory tier —
        // no extra productions.
        let memoryCount = await memory.count
        XCTAssertEqual(memoryCount, 2, "the shared LRU holds both sessions")
        let repeatA = await router.thumbnail(sessionID: idA, relPath: "IMG_0001.ARW")
        XCTAssertNotNil(repeatA)
        XCTAssertEqual(renderCounter.count, 2, "the repeat is a memory hit")
        XCTAssertEqual(router.poolCount, 2)
    }

    // MARK: - Offline: zero requests, zero providers

    func testOfflineSessionNeverCreatesProvider() async throws {
        // The session folder vanishes (unmounted volume / moved folder).
        let idB = try await registrySessionID("sB")
        let idA = try await registrySessionID("sA")
        try FileManager.default.removeItem(at: sessionRoots["sB"]!)
        let router = makeRouter()

        let thumb = await router.thumbnail(sessionID: idB, relPath: "IMG_0001.ARW")
        XCTAssertNil(thumb, "the offline route returns nil")
        XCTAssertFalse(router.hasProvider(idB), "NO provider for an offline session")
        XCTAssertTrue(router.isOffline(idB))

        // The online session is unaffected.
        let thumbA = await router.thumbnail(sessionID: idA, relPath: "IMG_0001.ARW")
        XCTAssertNotNil(thumbA)
        XCTAssertEqual(router.poolCount, 1, "only the online session is pooled")
    }

    // MARK: - Lifecycle: teardown drops the pool

    func testTeardownDropsPoolAndLazilyRebuilds() async throws {
        let router = makeRouter()
        let idA = try await registrySessionID("sA")
        let idB = try await registrySessionID("sB")
        _ = await router.thumbnail(sessionID: idA, relPath: "IMG_0001.ARW")
        _ = await router.thumbnail(sessionID: idB, relPath: "IMG_0001.ARW")
        XCTAssertEqual(router.poolCount, 2)

        // Leaving Catalogs mode: pending jobs drop, providers release.
        await router.teardown()
        XCTAssertEqual(router.poolCount, 0, "the pool is gone")

        // The next grid visit rebuilds lazily (the memory tier still serves
        // its namespaced keys — zero re-render for the still-cached row).
        let again = await router.thumbnail(sessionID: idA, relPath: "IMG_0001.ARW")
        XCTAssertNotNil(again)
        XCTAssertEqual(router.poolCount, 1, "the lazy rebuild")
        XCTAssertEqual(
            renderCounter.count, 2,
            "the rebuild rides the shared memory tier — no re-production")
    }
}
