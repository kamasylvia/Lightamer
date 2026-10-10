import CryptoKit
import Foundation
import LightamerCore
import XCTest

/// ModelAssetStore state-machine tests (plan M2-10-01 T3 / AC #2 #3).
/// URLProtocol mock + temporary-directory injection; every digest is the
/// REAL CryptoKit SHA-256 of the served payload bytes (checker E1 — no mock
/// hashes). Source order, atomic promotion, fail-closed and self-heal are
/// asserted at their observable faces (request sequence, filesystem final
/// state, typed errors).
final class ModelAssetStoreTests: XCTestCase {

    // MARK: URLProtocol mock

    enum MockResponse {
        /// Full payload in one load.
        case success(status: Int, data: Data)
        /// Chunked payload with inter-chunk delay (progress/cancel legs).
        case stream(status: Int, data: Data, chunkSize: Int, delay: TimeInterval)
        case failure(Error)
    }

    final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> MockResponse)?
        nonisolated(unsafe) static var requestOrder: [URL] = []
        private static let lock = NSLock()

        // Per-INSTANCE stop flag: URLSession calls stopLoading when a task
        // is torn down — including when the CONSUMER ABANDONS the response
        // body (the store drops 404 bodies after reading the status). A
        // static flag here poisoned every later task in the same test.
        private let stopLock = NSLock()
        private var wasStopped = false

        static func reset() {
            lock.lock()
            handler = nil
            requestOrder = []
            lock.unlock()
        }

        static func record(_ url: URL) {
            lock.lock()
            requestOrder.append(url)
            lock.unlock()
        }

        static func requestHosts() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return requestOrder.compactMap { $0.host }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        private func setStopped() {
            stopLock.lock()
            wasStopped = true
            stopLock.unlock()
        }

        private func isStopped() -> Bool {
            stopLock.lock()
            defer { stopLock.unlock() }
            return wasStopped
        }

        override func startLoading() {
            Self.record(request.url!)
            guard let handler = Self.handler, let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            switch handler(request) {
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            case .success(let status, let data):
                deliver(status: status, data: data, chunkSize: nil, delay: 0)
            case .stream(let status, let data, let chunkSize, let delay):
                deliver(status: status, data: data, chunkSize: chunkSize, delay: delay)
            }
        }

        private func deliver(status: Int, data: Data, chunkSize: Int?, delay: TimeInterval) {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if status >= 400 {
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let chunks: [Data]
            if let chunkSize {
                chunks = stride(from: 0, to: data.count, by: chunkSize).map {
                    data.subdata(in: $0..<min($0 + chunkSize, data.count))
                }
            } else {
                chunks = [data]
            }
            for chunk in chunks {
                if isStopped() { return }
                client?.urlProtocol(self, didLoad: chunk)
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {
            setStopped()
        }
    }

    // MARK: Fixture

    private var root: URL!
    private var locator: ModelLocator!
    private var session: URLSession!
    /// 64 KiB of deterministic payload — digests always computed for real.
    private var payload: Data!

    override func setUpWithError() throws {
        try super.setUpWithError()
        MockURLProtocol.reset()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-tests-\(UUID().uuidString)", isDirectory: true)
        locator = ModelLocator(installationRootOverride: root)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        payload = Data((0..<(64 * 1024)).map { UInt8(truncatingIfNeeded: ($0 &+ ($0 >> 8)) & 0xFF) })
    }

    override func tearDownWithError() throws {
        session.invalidateAndCancel()
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func makeDigest(for data: Data) -> ModelAssetDigestEntry {
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ModelAssetDigestEntry(
            sha256Hex: hex, byteCount: data.count, auxiliaryFiles: [], generatedAt: "test"
        )
    }

    /// Store bound to the REAL jina-clip-v2-int8 release manifest with an
    /// INJECTED digest (the real one is nil — fail-closed until upload).
    private func makeStore(
        digest: ModelAssetDigestEntry?,
        locator overrideLocator: ModelLocator? = nil,
        onProgress: (@Sendable (String, Double) -> Void)? = nil
    ) -> ModelAssetStore {
        ModelAssetStore(
            manifestProvider: { ModelAssetCatalog.manifest(for: $0) },
            digestProvider: { profileID in
                profileID == "jina-clip-v2-int8" ? digest : ModelAssetDigests.digest(for: profileID)
            },
            locator: overrideLocator ?? self.locator,
            session: session,
            onProgress: onProgress
        )
    }

    private func makeSlowStore(
        digest: ModelAssetDigestEntry,
        onProgress: (@Sendable (String, Double) -> Void)? = nil
    ) -> ModelAssetStore {
        ModelAssetStore(
            manifestProvider: { ModelAssetCatalog.manifest(for: $0) },
            digestProvider: { profileID in
                profileID == "jina-clip-v2-int8" ? digest : ModelAssetDigests.digest(for: profileID)
            },
            locator: self.locator,
            session: self.session,
            onProgress: onProgress
        )
    }

    private func tmpDir(for profileID: String) -> URL {
        root.appendingPathComponent("\(profileID).tmp", isDirectory: true)
    }

    private func finalFile() -> URL {
        root
            .appendingPathComponent("jina-clip-v2-int8", isDirectory: true)
            .appendingPathComponent("jina-clip-v2-int8.mlpackage.zip")
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return }
            usleep(20_000)
        }
        XCTFail("condition not reached within \(timeout)s")
    }

    private func serve() {
        let bytes = payload!
        MockURLProtocol.handler = { request in
            switch request.url?.host {
            case "github.com":
                .success(status: 404, data: Data("nope".utf8))
            case "hf-mirror.com":
                .success(status: 200, data: bytes)
            default:
                .failure(URLError(.notConnectedToInternet))
            }
        }
    }

    // MARK: Status machine

    func testUnknownProfileStatusAndDownload() async throws {
        let store = makeStore(digest: makeDigest(for: payload))
        let status = await store.status(for: "no-such-profile")
        XCTAssertEqual(status, .notInstalled)
        await assertStoreError(.unknownProfile("no-such-profile")) {
            try await store.download("no-such-profile")
        }
    }

    /// AC #2: digest == nil → download refused with typed error and the
    /// status face reports .digestUnpublished (fail-closed).
    func testDigestUnpublishedFailClosed() async throws {
        let store = makeStore(digest: nil)
        let status = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(status, .digestUnpublished)
        await assertStoreError(.digestUnpublished("jina-clip-v2-int8")) {
            try await store.download("jina-clip-v2-int8")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir(for: "jina-clip-v2-int8").path))
    }

    func testBundledNotDownloadable() async throws {
        let store = makeStore(digest: makeDigest(for: payload))
        await assertStoreError(.bundledNotDownloadable("chinese-clip-vitb16-int8")) {
            try await store.download("chinese-clip-vitb16-int8")
        }
    }

    func testBundledShortCircuitsStatusAndModelURL() async throws {
        let bundleRoot = try ModelAssetCatalogTests.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: bundleRoot) }
        let profileDir = bundleRoot.appendingPathComponent("jina-clip-v2-int8", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        // Even WITH an installed copy present, bundled wins (KD-3).
        try FileManager.default.createDirectory(
            at: finalFile().deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.write(to: finalFile())

        let overridden = ModelLocator(
            bundledRootOverride: bundleRoot,
            installationRootOverride: root
        )
        let store = makeStore(digest: makeDigest(for: payload), locator: overridden)
        let status = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(status, .bundled)
        let url = await store.modelURL(for: "jina-clip-v2-int8")
        XCTAssertEqual(url, profileDir)
    }

    // MARK: Download happy path + source order

    /// AC #3: Release 404 → hf-mirror takes over → verify → same-parent
    /// promote → tmp gone, final present, status .installed.
    func testDownloadPromotesAndStatusInstalled() async throws {
        serve()
        let store = makeStore(digest: makeDigest(for: payload))
        try await store.download("jina-clip-v2-int8")

        XCTAssertEqual(MockURLProtocol.requestHosts(), ["github.com", "hf-mirror.com"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalFile().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir(for: "jina-clip-v2-int8").path))
        let status = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(status, .installed)
        let url = await store.modelURL(for: "jina-clip-v2-int8")
        XCTAssertEqual(url, finalFile())
    }

    // MARK: Depth profile (M4-3-01 T1) — the depth-shaped release manifest
    // flows the SAME store chain; the in-repo digest makes these REAL
    // (no injection needed beyond the payload serve).

    private func finalDepthFile() -> URL {
        root
            .appendingPathComponent("depth-anything-v2-small-f16", isDirectory: true)
            .appendingPathComponent("depth-anything-v2-small-f16.mlpackage.zip")
    }

    /// The depth release manifest downloads → promotes → .installed. The
    /// digest is INJECTED (the real in-repo digest pins the 45MB zip; the
    /// 64KiB served payload here stands in for the network bytes).
    func testDepthManifestDownloadPromotes() async throws {
        serve()
        let injected = makeDigest(for: payload)
        let store = ModelAssetStore(
            manifestProvider: { ModelAssetCatalog.manifest(for: $0) },
            digestProvider: { $0 == "depth-anything-v2-small-f16" ? injected : ModelAssetDigests.digest(for: $0) },
            locator: self.locator,
            session: session
        )
        try await store.download("depth-anything-v2-small-f16")

        XCTAssertTrue(FileManager.default.fileExists(atPath: finalDepthFile().path))
        let status = await store.status(for: "depth-anything-v2-small-f16")
        XCTAssertEqual(status, .installed)
        let url = await store.modelURL(for: "depth-anything-v2-small-f16")
        XCTAssertEqual(url, finalDepthFile())
    }

    /// Depth digest absent → fail-closed typed refusal (the depth face of
    /// the AC#2 semantic).
    func testDepthDigestAbsentFailClosed() async throws {
        let store = ModelAssetStore(
            manifestProvider: { ModelAssetCatalog.manifest(for: $0) },
            digestProvider: { _ in nil },
            locator: self.locator,
            session: session
        )
        let status = await store.status(for: "depth-anything-v2-small-f16")
        XCTAssertEqual(status, .digestUnpublished)
        await assertStoreError(.digestUnpublished("depth-anything-v2-small-f16")) {
            try await store.download("depth-anything-v2-small-f16")
        }
    }

    /// Depth checksum mismatch → typed, tmp removed, nothing promoted.
    func testDepthChecksumMismatchDeletesTmp() async throws {
        serve()
        let wrongDigest = makeDigest(for: payload + Data([0xAA]))
        let store = ModelAssetStore(
            manifestProvider: { ModelAssetCatalog.manifest(for: $0) },
            digestProvider: { $0 == "depth-anything-v2-small-f16" ? wrongDigest : nil },
            locator: self.locator,
            session: session
        )
        do {
            try await store.download("depth-anything-v2-small-f16")
            XCTFail("expected checksumMismatch")
        } catch let error as ModelAssetStoreError {
            guard case .checksumMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalDepthFile().path))
    }

    func testSourceOrderAllThreeSourcesExhausted() async throws {
        MockURLProtocol.handler = { _ in .success(status: 404, data: Data()) }
        let store = makeStore(digest: makeDigest(for: payload))
        await assertStoreError(.allSourcesFailed) {
            try await store.download("jina-clip-v2-int8")
        }
        XCTAssertEqual(
            MockURLProtocol.requestHosts(),
            ["github.com", "hf-mirror.com", "huggingface.co"],
            "source order must be Release → hf-mirror → HF"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir(for: "jina-clip-v2-int8").path))
    }

    /// AC #3: served bytes not matching the digest → typed error, tmp
    /// directory removed, final artifact absent.
    func testChecksumMismatchDeletesTmp() async throws {
        serve()
        let wrongDigest = makeDigest(for: payload + Data([0xFF]))
        let store = makeStore(digest: wrongDigest)
        do {
            try await store.download("jina-clip-v2-int8")
            XCTFail("expected checksumMismatch")
        } catch let error as ModelAssetStoreError {
            guard case .checksumMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir(for: "jina-clip-v2-int8").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalFile().path))
    }

    // MARK: Cancellation / corruption / removal / progress

    func testCancellationRemovesTmp() async throws {
        let bytes = payload!
        MockURLProtocol.handler = { _ in
            .stream(status: 200, data: bytes, chunkSize: 4096, delay: 0.02)
        }
        let store = makeSlowStore(digest: makeDigest(for: payload))
        let task = Task { try await store.download("jina-clip-v2-int8") }
        try await waitUntil {
            if case .downloading = await store.status(for: "jina-clip-v2-int8") { return true }
            return false
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tmpDir(for: "jina-clip-v2-int8").path),
            "cancelled download must leave no tmp residue"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalFile().path))
    }

    /// Tamper with the installed artifact → .corrupt → redownload heals.
    func testCorruptStatusSelfHealsByRedownload() async throws {
        serve()
        let store = makeStore(digest: makeDigest(for: payload))
        try await store.download("jina-clip-v2-int8")
        let statusInstalled = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(statusInstalled, .installed)

        let handle = try FileHandle(forWritingTo: finalFile())
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xDE, 0xAD]))
        try handle.close()

        let statusCorrupt = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(statusCorrupt, .corrupt)
        let url = await store.modelURL(for: "jina-clip-v2-int8")
        XCTAssertNil(url, "corrupt artifact is not returned as a model URL")

        serve()
        try await store.download("jina-clip-v2-int8")
        let statusHealed = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(statusHealed, .installed)
    }

    func testRemoveDeletesInstalled() async throws {
        serve()
        let store = makeStore(digest: makeDigest(for: payload))
        try await store.download("jina-clip-v2-int8")
        try await store.remove("jina-clip-v2-int8")
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalFile().path))
        let status = await store.status(for: "jina-clip-v2-int8")
        XCTAssertEqual(status, .notInstalled)
    }

    func testProgressReportedMonotonic() async throws {
        let bytes = payload!
        MockURLProtocol.handler = { _ in
            .stream(status: 200, data: bytes, chunkSize: 8192, delay: 0.005)
        }
        let sink = ProgressBox()
        let store = makeSlowStore(digest: makeDigest(for: payload)) { _, fraction in
            sink.record(fraction)
        }
        try await store.download("jina-clip-v2-int8")
        let values = sink.snapshot()
        XCTAssertGreaterThan(values.count, 1, "progress must report in multiple steps")
        XCTAssertEqual(values, values.sorted(), "progress must be monotonic")
        XCTAssertEqual(values.last ?? 0, 1.0, accuracy: 0.0001)
    }

    /// Concurrent second download of the same profile is rejected typed.
    func testSecondConcurrentDownloadRejected() async throws {
        let bytes = payload!
        MockURLProtocol.handler = { _ in
            .stream(status: 200, data: bytes, chunkSize: 4096, delay: 0.02)
        }
        let store = makeSlowStore(digest: makeDigest(for: payload))
        let first = Task { try await store.download("jina-clip-v2-int8") }
        try await waitUntil {
            if case .downloading = await store.status(for: "jina-clip-v2-int8") { return true }
            return false
        }
        await assertStoreError(.alreadyDownloading("jina-clip-v2-int8")) {
            try await store.download("jina-clip-v2-int8")
        }
        _ = try await first
    }

    // MARK: Helpers

    /// L038: typed-error assertions cannot live in XCTest autoclosures —
    /// do/catch helper with Equatable comparison.
    private func assertStoreError(
        _ expected: ModelAssetStoreError,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected error \(expected)")
        } catch let error as ModelAssetStoreError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}

/// Thread-safe ordered progress recorder (synchronous record preserves the
/// call order — an actor + per-call Task would race the ordering).
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func record(_ fraction: Double) {
        lock.lock()
        values.append(fraction)
        lock.unlock()
    }

    func snapshot() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
