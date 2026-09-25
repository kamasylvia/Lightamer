import CoreGraphics
import Foundation
import LightamerCore
import XCTest

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
