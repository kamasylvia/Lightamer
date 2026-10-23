import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import UniformTypeIdentifiers
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryAnalysisServiceTests (Plan LUMEN-A T5, review M-2) — the analysis
// pass's Core face, every seam injected (no Vision, no real RAW):
//
//   ① scan/write faces: pendingAnalysisRows version discipline + id order;
//      setAnalysis writes the seven v6 columns with the COALESCE backfill
//      legs (a stored serial survives); the analysisEvents notify seam fires
//   ② the anti-retry-storm: an unresolvable row analyzes to the EMPTY
//      record (version stamped, products nil) — exactly-once per version
//   ③ the enabled gate: unset = true (默认开), stored false wins, the
//      injectable suite isolates the face
//   ④ the pause/resume state machine: the injected activity probe holds the
//      walk (nothing processes while busy); releasing it drains the batch
//      and the progress stream reports done/total
//   ⑤ the badge refresh event chain (LUMEN-A acceptance §八 major-1): the
//      persist hop lands the notify event on THE injected LibraryStore
//      instance the consumer subscribes (the per-row fresh-instance shape
//      — the §八 breakage — is red-proven dead)
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryAnalysisServiceTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: ProjectFileStore!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("analysis-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        store = ProjectFileStore(at: tempDirectory.appendingPathComponent("AnalyzeProj.lalb"))
        _ = try await store.create(name: "AnalyzeProj")
        defaultsSuiteName = "analysis-service-tests-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        try? await store.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// A real (tiny) JPEG on disk inside the package's Media/ directory —
    /// the analysis preview/sharpness legs run on it for real.
    private func writeFixtureJPEG(name: String) throws -> URL {
        let media = tempDirectory.appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let url = media.appendingPathComponent(name)
        let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = context.makeImage()!
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    @discardableResult
    private func insertRow(path: String) async throws -> Int64 {
        try await store.withWriteBatch { handle in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind, camera_serial)"
                    + " VALUES (?, 0, ?)")
            try insert.bindText(1, path)
            try insert.bindText(2, "SERIAL-A")
            _ = try insert.step()
            return handle.lastInsertRowID()
        }
    }

    private func readRow(
        _ id: Int64
    ) async throws -> (version: Int64?, sharpness: Double?, serial: String?) {
        try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT analysis_version, sharpness, camera_serial FROM images"
                    + " WHERE id = ?")
            try statement.bindInt(1, id)
            try XCTAssertTrue(statement.step())
            return (
                statement.columnInt(0),
                statement.columnDouble(1),
                statement.columnText(2)
            )
        }
    }

    private func makeService(
        libraryStore: LibraryStore? = nil
    ) async -> LibraryAnalysisService {
        await LibraryAnalysisService(
            store: store, queries: LibraryQueries(store: store),
            faceProvider: SyntheticEyeProvider(), defaultsSuiteName: defaultsSuiteName,
            libraryStore: libraryStore)
    }

    /// The no-Vision provider (never called on the missing-file paths).
    private struct SyntheticEyeProvider: FaceLandmarkProviding {
        func detectFaces(image: CGImage) throws -> [FaceLandmarkFace] { [] }
    }

    // MARK: - ① Scan + write faces + notify seam

    func testScanWriteFacesAndNotifySeam() async throws {
        let idA = try await insertRow(path: "Media/a.jpg")
        let idB = try await insertRow(path: "Media/b.jpg")
        let queries = LibraryQueries(store: store)

        // Scan: version 1 sees both rows, id-ordered.
        let pending = try await queries.pendingAnalysisRows(version: 1)
        XCTAssertEqual(pending.map(\.id), [idA, idB])
        XCTAssertEqual(pending.map(\.cameraSerial), ["SERIAL-A", "SERIAL-A"])

        // Write: the seven columns land; the COALESCE legs keep the stored
        // serial (the record's nil serial must NOT null it out).
        let store = LibraryStore(store: self.store)
        // Subscribe FIRST (unbounded buffering) — the event survives until
        // the iterator consumes it, so no concurrent collection Task needed.
        let stream = await store.analysisEvents()
        try await store.setAnalysis(LibraryAnalysisRecord(
            imageID: idA, analysisVersion: 1, sharpness: 55.5,
            faces: 2, eyesClosed: 1,
            signature: Data([1, 2, 3]),
            faceBoxes: "[[0.1,0.1,0.2,0.2,1,0.4,0.08]]",
            cameraSerial: nil, captureDate: nil))
        var received: [[Int64]] = []
        for await ids in stream {
            received.append(ids)
            break
        }
        XCTAssertEqual(received, [[idA]], "the notify seam fired with the written id")

        let row = try await readRow(idA)
        XCTAssertEqual(row.version, 1)
        XCTAssertEqual(row.sharpness ?? 0, 55.5, accuracy: 1e-6)
        XCTAssertEqual(row.serial, "SERIAL-A", "COALESCE keeps the stored serial")

        // Version discipline: the stamped row leaves the pending set; a
        // LOWER version scan still sees it (recompute semantics).
        let after = try await queries.pendingAnalysisRows(version: 1)
        XCTAssertEqual(after.map(\.id), [idB])
        let recount = try await queries.pendingAnalysisCount(version: 1)
        XCTAssertEqual(recount, 1)
        let stale = try await queries.pendingAnalysisRows(version: 2)
        XCTAssertEqual(stale.map(\.id), [idA, idB], "version bump = recompute")
    }

    // MARK: - ② The anti-retry-storm (empty analysis)

    func testUnresolvableRowWritesEmptyAnalysisOnce() async throws {
        let id = try await insertRow(path: "Media/missing.jpg")
        let row = try await LibraryQueries(store: store)
            .pendingAnalysisRows(version: 1).first
        let product = await LibraryAnalysisService.analyzeRow(
            row: try XCTUnwrap(row),
            projectDirectory: tempDirectory,
            faceProvider: SyntheticEyeProvider())
        XCTAssertNil(product.sharpness)
        XCTAssertNil(product.faces)
        XCTAssertNil(product.signature)
        XCTAssertEqual(product.analysisVersion, 1, "stamped — never retried")
        XCTAssertEqual(product.cameraSerial, nil)
        try await LibraryStore(store: store).setAnalysis(product)
        let after = try await LibraryQueries(store: store)
            .pendingAnalysisRows(version: 1)
        XCTAssertTrue(after.isEmpty, "the stamped row left the pending set")
    }

    // MARK: - ③ The enabled gate

    func testEnabledGateTypedReadAndInjection() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        // Unset = TRUE (默认开, D-LU-5).
        XCTAssertTrue(LibraryAnalysisService.isEnabled(defaults: suite))
        // Stored false wins; anything stored is the face.
        suite.set(false, forKey: LibraryAnalysisService.enabledKey)
        XCTAssertFalse(LibraryAnalysisService.isEnabled(defaults: suite))
        suite.set(true, forKey: LibraryAnalysisService.enabledKey)
        XCTAssertTrue(LibraryAnalysisService.isEnabled(defaults: suite))
        // The key spelling is the single source.
        XCTAssertEqual(LibraryAnalysisService.enabledKey, "library.analysis.enabled")
    }

    // MARK: - ⑤ The badge refresh event chain (LUMEN-A acceptance §八 major-1)

    /// The badge chain end-to-end: the analysis walk's persist hop must
    /// land the notify event on THE LibraryStore actor instance the
    /// consumer subscribes. The acceptance §八 breakage shape — a fresh
    /// `LibraryStore(store:)` per persisted row — yields the event into
    /// the fresh instance's empty continuation table; a subscriber on any
    /// other instance (the WorkspaceHostView badge loop, which creates
    /// its own) never sees it. This test pins the chain through the
    /// service's persist store.
    func testAnalysisEventReachesSubscriberThroughWalkPersist() async throws {
        _ = try writeFixtureJPEG(name: "badge.jpg")
        let id = try await insertRow(path: "Media/badge.jpg")

        // The consumer side subscribes its OWN instance (the
        // WorkspaceHostView badge loop shape) — post-fix this same
        // instance is INJECTED as the service's persist store, so one
        // actor owns the continuation table end to end.
        let subscriberStore = LibraryStore(store: store)
        let service = await makeService(libraryStore: subscriberStore)
        // The identity pin: the persist hop routes through the injected
        // store — a per-row fresh instance (the §八 shape, red-proven
        // pre-fix) fails this line first.
        let serviceStore = await service.libraryStore
        XCTAssertTrue(
            serviceStore === subscriberStore,
            "the service persists through the injected store instance")

        // Subscribe FIRST (unbounded buffering) — the event survives
        // until the collector consumes it.
        let stream = await subscriberStore.analysisEvents()
        let received = Locked(false)
        let collector = Task {
            for await _ in stream {
                received.set(true)
                break
            }
        }
        defer { collector.cancel() }

        await service.start()
        // The walk wrote the row once it leaves the pending set (the DB
        // leg rides the shared ProjectFileStore — it lands regardless of
        // the notify seam; this is exactly the §八 phenotype: data present,
        // badge never refreshed).
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if try await LibraryQueries(store: store)
                .pendingAnalysisRows(version: 1).isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let pending = try await LibraryQueries(store: store)
            .pendingAnalysisRows(version: 1)
        XCTAssertTrue(pending.isEmpty, "precondition: the walk stamped the row")
        await service.cancel()

        // THE CHAIN under test: the subscriber's continuation got the
        // event, and the analysis product landed with it.
        XCTAssertTrue(
            received.value,
            "the analysis event must reach the subscriber's store instance")
        let row = try await readRow(id)
        XCTAssertNotNil(row.sharpness, "the analysis product landed")
    }

    // MARK: - ④ The pause/resume state machine + progress

    func testPauseResumeAndProgress() async throws {
        _ = try writeFixtureJPEG(name: "shot.jpg")
        let id = try await insertRow(path: "Media/shot.jpg")
        // Drop the stored serial so the file's own EXIF (none) degrades —
        // irrelevant here; the point is the walk processes the row.
        try await store.withWriteBatch { handle in
            let update = try handle.prepare(
                "UPDATE images SET camera_serial = NULL WHERE id = ?")
            try update.bindInt(1, id)
            _ = try update.step()
        }

        let service = await makeService()
        let paused = await makePausedProbe()
        await service.setActivityProbe(paused.probe)

        // Subscribe first; the stream buffers the walk's emissions.
        let stream = await service.progressEvents()
        await service.start()
        // H-LU1 defense #3: while the probe reports busy, NOTHING processes.
        try await Task.sleep(nanoseconds: 700_000_000)
        let pendingWhilePaused = try await LibraryQueries(store: store)
            .pendingAnalysisRows(version: 1)
        XCTAssertEqual(pendingWhilePaused.map(\.id), [id], "paused = no writes")

        // Release: the walk drains the row and reports done==total (the
        // buffered stream terminates the iteration).
        paused.release()
        var last: LibraryAnalysisProgress?
        for await progress in stream {
            last = progress
            if progress.done >= progress.total { break }
        }
        let after = try await LibraryQueries(store: store)
            .pendingAnalysisRows(version: 1)
        XCTAssertTrue(after.isEmpty, "the walk completed the row")
        let final = try XCTUnwrap(last)
        XCTAssertEqual(final.done, 1)
        XCTAssertEqual(final.total, 1)
        await service.cancel()
    }

    private func makePausedProbe() async -> (
        probe: @Sendable () async -> Bool, release: @Sendable () -> Void
    ) {
        // The probe reports BUSY (true) until released — the walk must hold.
        let box = Locked(true)
        return (
            { await box.value },
            { box.set(false) }
        )
    }
}

/// A tiny locked box (the probe's cross-actor flag; no Swift Concurrency
/// atomics dependency in tests).
private final class Locked: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    init(_ initial: Bool) { stored = initial }
    var value: Bool {
        lock.lock(); defer { lock.unlock() }; return stored
    }
    func set(_ newValue: Bool) {
        lock.lock(); stored = newValue; lock.unlock()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LUMEN-B T6: the analysis queue-jump seam — the cull face's ±window rows
// head the next batch (the Lumen first=True 直译). The pure partition face
// pinned here; the APP side asserts the ROUTE invocation with a synthetic
// service (its own suite — the domain table keeps Library coverage here).
// ─────────────────────────────────────────────────────────────────────────────

extension LibraryAnalysisServiceTests {

    func testPriorityPartitionPutsWindowRowsFirstStable() {
        let rows = (1...6).map {
            PendingAnalysisRow(
                id: Int64($0), imagePath: "Media/img\($0).jpg",
                pathKind: .projectRelative, volumeUUID: nil, cameraSerial: nil)
        }
        let partitioned = LibraryAnalysisService.partitionByPriority(
            rows, priority: [4, 2])
        // The queued rows first (their queue order — here the SCAN order),
        // then the rest in id order; stable within each partition.
        XCTAssertEqual(partitioned.map(\.id), [2, 4, 1, 3, 5, 6])
        // An empty priority set = the scan order untouched.
        XCTAssertEqual(
            LibraryAnalysisService.partitionByPriority(rows, priority: [])
                .map(\.id),
            [1, 2, 3, 4, 5, 6])
        // A priority id outside the batch is simply absent.
        XCTAssertEqual(
            LibraryAnalysisService.partitionByPriority(rows, priority: [99])
                .map(\.id),
            [1, 2, 3, 4, 5, 6])
    }
}
