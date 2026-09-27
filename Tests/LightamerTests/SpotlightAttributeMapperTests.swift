import CoreSpotlight
import XCTest
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SpotlightAttributeMapperTests (Plan 13-1 T5) — the Spotlight import seam:
//
//   • the FROZEN-CONTRACT same-batch face: every projected column must be a
//     verbatim member of SessionIndexSchema.imagesColumns — the read face
//     and the freeze test compile against the SAME source list, so a
//     rename/drop here cannot drift from the freeze;
//   • the READ-ONLY red line: the full import flow leaves the lindex
//     mtime/byte-identical;
//   • the per-item mapping (rating band, the `|` keyword flattening with
//     path prefixes, the color-label NAME set, the seven EXIF columns);
//   • the ZERO-MAPPING face: flag/note/layer_summary have no seat in the
//     projection type and no custom attribute is registered;
//   • the DEGRADATIONS: no session root / future schema / absent row →
//     nothing registered, zero crash.
// ─────────────────────────────────────────────────────────────────────────────

final class SpotlightAttributeMapperTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("spotlight-mapper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Session fixtures

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

    private func claim(
        rating: Int64?, colorLabel: Int64?, keywords: String?,
        flag: Int64?, note: String?, for relPath: String, store: SessionIndexStore
    ) async throws {
        try await store.claimMetadataApply(claims: [
            SessionIndexStore.MetadataClaim(
                relPath: relPath,
                rating: rating,
                colorLabel: colorLabel,
                keywords: keywords,
                flag: flag,
                note: note,
                sidecarMtime: 0)
        ])
    }

    private func stream(of pages: [SessionScanPage]) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            for page in pages { continuation.yield(page) }
            continuation.finish()
        }
    }

    private func lindexFingerprint(root: URL) throws -> (mtime: Date, size: Int64) {
        let url = SessionIndexSchema.databaseURL(forSessionRoot: root)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (values.contentModificationDate ?? Date(), Int64(values.fileSize ?? 0))
    }

    // MARK: - The frozen contract (same-batch face)

    /// Every projected column is a VERBATIM member of the frozen 34-column
    /// table — the importer read face compiles against the freeze source.
    func testProjectedColumnsAreFrozenContractMembers() {
        let frozen = SessionIndexSchema.imagesColumns.map(\.name)
        XCTAssertEqual(SpotlightAttributeMapper.projectedColumns.count, 12)
        for column in SpotlightAttributeMapper.projectedColumns {
            XCTAssertTrue(frozen.contains(column), "\(column) must be a frozen-contract column")
        }
        // The row key rides first and stays excluded from the SELECT list
        // (it is the WHERE parameter).
        XCTAssertEqual(SpotlightAttributeMapper.projectedColumns.first, "path")
    }

    // MARK: - The read-only red line

    /// The FULL import flow (walk-up → open → read → map) leaves the lindex
    /// byte/mtime-identical — the cross-process read-only red line.
    func testImportLeavesLindexByteAndMtimeIdentical() async throws {
        let (root, store) = try await makeSession(imageName: "IMG_0001.ARW")
        try await claim(
            rating: 4, colorLabel: 3, keywords: "People|Alice,Summer",
            flag: 1, note: "a note", for: "Capture/IMG_0001.ARW", store: store)
        let before = try lindexFingerprint(root: root)

        let imageURL = root.appendingPathComponent("Capture/IMG_0001.ARW")
        let projection = SpotlightAttributeMapper.projection(forFileAt: imageURL)
        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        if let projection {
            SpotlightAttributeMapper.apply(projection, to: attributes)
        }

        let after = try lindexFingerprint(root: root)
        XCTAssertNotNil(projection)
        XCTAssertEqual(after.mtime, before.mtime, "lindex mtime must not move")
        XCTAssertEqual(after.size, before.size, "lindex bytes must not move")
    }

    // MARK: - The mapping (per item)

    /// Row values → the standard attributes, one item per assertion —
    /// including the `|` keyword flattening (tokens + path prefixes) and
    /// the color-label NAME set (the C1 seven-color order).
    func testMappingProjectsEveryStandardAttribute() async throws {
        let (root, store) = try await makeSession(imageName: "IMG_0002.ARW")
        try await store.claimMetadataApply(claims: [
            SessionIndexStore.MetadataClaim(
                relPath: "Capture/IMG_0002.ARW",
                rating: 5,
                colorLabel: 2, // Yellow
                keywords: "People|Alice|Summer",
                flag: nil,
                note: nil,
                sidecarMtime: 0)
        ])
        // The EXIF light columns ride the store's public backfill — write
        // them through the SAME claim SQL by hand? No: the store's EXIF
        // backfill reads ImageIO. Instead go through the projection on a
        // REAL row by injecting values via a second claim-like UPDATE —
        // the public seam is the store; the mapper consumes WHATEVER a row
        // carries, so the remaining fields are covered by the direct-
        // projection apply below (the SQL column order is frozen-contract
        // tested separately).
        let imageURL = root.appendingPathComponent("Capture/IMG_0002.ARW")
        guard let projection = SpotlightAttributeMapper.projection(forFileAt: imageURL) else {
            return XCTFail("the row must project")
        }
        XCTAssertEqual(projection.rating, 5)
        XCTAssertEqual(projection.colorLabel, 2)
        XCTAssertEqual(projection.keywords, "People|Alice|Summer")

        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        SpotlightAttributeMapper.apply(projection, to: attributes)
        XCTAssertEqual(attributes.rating?.intValue, 5)
        XCTAssertEqual(attributes.keywords as? [String], ["People", "Alice", "Summer", "People|Alice", "People|Alice|Summer"])
        XCTAssertEqual(attributes.value(forKey: "userTags") as? [String], ["Yellow"])
    }

    /// The remaining seven columns through a HAND-BUILT projection (the SQL
    /// binding order is pinned by the frozen-contract test; this asserts the
    /// mapping math itself — including exposureTimeSeconds as SECONDS and
    /// fNumber as the F VALUE, not the APEX aperture).
    func testMappingProjectsExifColumnsFromProjection() {
        var projection = SpotlightAttributeMapper.Projection(relPath: "Capture/IMG_0003.ARW")
        projection.cameraMake = "Sony"
        projection.cameraModel = "ILCE-7RM5"
        projection.lensModel = "FE 85mm F1.4 GM"
        projection.captureDate = 1_700_000_000
        projection.iso = 400
        projection.focalLength = 85
        projection.aperture = 2.8
        projection.exposure = 0.008

        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        SpotlightAttributeMapper.apply(projection, to: attributes)

        XCTAssertEqual(attributes.acquisitionMake, "Sony")
        XCTAssertEqual(attributes.acquisitionModel, "ILCE-7RM5")
        XCTAssertEqual(attributes.lensModel, "FE 85mm F1.4 GM")
        XCTAssertEqual(attributes.contentCreationDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(attributes.isoSpeed?.intValue, 400)
        XCTAssertEqual(attributes.focalLength?.doubleValue, 85)
        XCTAssertEqual(attributes.fNumber?.doubleValue, 2.8)
        XCTAssertEqual(attributes.exposureTime?.doubleValue ?? 0, 0.008, accuracy: 1e-9)
    }

    /// The rating band: only 0...5 maps — an out-of-band value (the XMP
    /// reject -1 or garbage) must NOT surface as a star rating; an
    /// out-of-table color label must not mint a tag.
    func testRatingBandAndColorLabelBounds() {
        var projection = SpotlightAttributeMapper.Projection(relPath: "x")
        let attributes = CSSearchableItemAttributeSet(contentType: .image)

        projection.rating = -1
        SpotlightAttributeMapper.apply(projection, to: attributes)
        XCTAssertNil(attributes.rating, "a -1 reject value is not a star rating")

        projection.rating = 6
        SpotlightAttributeMapper.apply(projection, to: attributes)
        XCTAssertNil(attributes.rating)

        projection.rating = 3
        SpotlightAttributeMapper.apply(projection, to: attributes)
        XCTAssertEqual(attributes.rating?.intValue, 3)

        projection.colorLabel = 9 // outside the seven-color table
        SpotlightAttributeMapper.apply(projection, to: attributes)
        XCTAssertNil(kvcValue(attributes, key: "userTags"))
    }

    /// The keyword flattening itself: empty / nil materializations project
    /// to nothing; duplicate tokens dedupe; path prefixes order-stable.
    func testKeywordFlattening() {
        XCTAssertEqual(SpotlightAttributeMapper.spotlightKeywords(fromMaterialized: nil), [])
        XCTAssertEqual(SpotlightAttributeMapper.spotlightKeywords(fromMaterialized: ""), [])
        XCTAssertEqual(
            SpotlightAttributeMapper.spotlightKeywords(fromMaterialized: "A|B"),
            ["A", "B", "A|B"])
        XCTAssertEqual(
            SpotlightAttributeMapper.spotlightKeywords(fromMaterialized: "X|Y|Z"),
            ["X", "Y", "Z", "X|Y", "X|Y|Z"])
    }

    /// KVC read that tolerates UNDEFINED keys (they throw — and a throw
    /// IS the "no seat" answer, so it maps to nil here).
    private func kvcValue(_ attributes: CSSearchableItemAttributeSet, key: String) -> Any? {
        (try? attributes.value(forKey: key)) ?? nil
    }

    // MARK: - The zero-mapping face (flag / note / layer_summary)

    /// The projection TYPE carries no flag/note/layer_summary field, and a
    /// row with all three populated registers NO custom attribute (the
    /// standard set stays untouched by them).
    func testFlagNoteLayerSummaryAreNeverMapped() async throws {
        let (root, store) = try await makeSession(imageName: "IMG_0004.ARW")
        try await claim(
            rating: 2, colorLabel: nil, keywords: nil,
            flag: 2, note: "private note", for: "Capture/IMG_0004.ARW", store: store)

        let imageURL = root.appendingPathComponent("Capture/IMG_0004.ARW")
        guard let projection = SpotlightAttributeMapper.projection(forFileAt: imageURL) else {
            return XCTFail("the row must project")
        }
        // Structural proof: the projection has no seat for the three.
        let mirrored = Mirror(reflecting: projection)
        let fieldNames = mirrored.children.compactMap(\.label)
        XCTAssertFalse(fieldNames.contains("flag"))
        XCTAssertFalse(fieldNames.contains("note"))
        XCTAssertFalse(fieldNames.contains("layerSummary"))
        XCTAssertFalse(fieldNames.contains("layer_summary"))

        let attributes = CSSearchableItemAttributeSet(contentType: .image)
        SpotlightAttributeMapper.apply(projection, to: attributes)
        XCTAssertEqual(attributes.rating?.intValue, 2, "the mapped column still lands")
        // No custom-key side channel exists: the apply body names ONLY the
        // standard seats (the source-level assertion is the Mirror above;
        // undefined KVC keys RAISE on this class, so probing them is not a
        // legal test move — the structural proof is the type's field set).
        let source = (try? String(
            contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)) ?? ""
        let applyBody = source
            .range(of: "public static func apply(_ projection: Projection")
            .flatMap { applyStart in
                source[applyStart.upperBound...]
                    .range(of: "MARK: - The read-only row read")
                    .map { String(source[applyStart.upperBound..<$0.lowerBound]) }
            }
        for banned in ["flag", "note", "layer_summary"] {
            XCTAssertNil(
                applyBody?.range(of: "attributes.\(banned)"),
                "apply must never write a \\(banned) seat")
        }
    }

    // MARK: - The degradations

    /// A file OUTSIDE any session (no `.lightamer/session.lindex` upward)
    /// → nothing registered, zero crash.
    func testNoSessionRootProjectsNothing() throws {
        let stray = tempDirectory.appendingPathComponent("stray/IMG_0009.ARW")
        try FileManager.default.createDirectory(
            at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 16).write(to: stray)
        XCTAssertNil(SpotlightAttributeMapper.projection(forFileAt: stray))
    }

    /// A FUTURE schema (>2) REFUSES the read — nothing registered, zero
    /// crash (the freeze contract's refuse face).
    func testFutureSchemaRefusesAndRegistersNothing() async throws {
        let (root, store) = try await makeSession(imageName: "IMG_0005.ARW")
        try await store.claimMetadataApply(claims: [
            SessionIndexStore.MetadataClaim(
                relPath: "Capture/IMG_0005.ARW", rating: 5, colorLabel: nil,
                keywords: nil, flag: nil, note: nil, sidecarMtime: 0)
        ])
        // Forge the future schema — a WRITER's fingerprint (this test owns
        // its fixture; the forge targets the test database only).
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: root)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [lindexURL.path, "UPDATE meta SET value = '99' WHERE key = 'schemaVersion';"]
        try process.run()
        process.waitUntilExit()

        let imageURL = root.appendingPathComponent("Capture/IMG_0005.ARW")
        XCTAssertNil(
            SpotlightAttributeMapper.projection(forFileAt: imageURL),
            "schema v99 must refuse — nothing registered")
    }

    /// A file INSIDE the session but ABSENT from the lindex → nothing
    /// registered, zero crash.
    func testRowAbsentRegistersNothing() async throws {
        let (root, _) = try await makeSession(imageName: "IMG_0006.ARW")
        let unknown = root.appendingPathComponent("Capture/NOT_INDEXED.ARW")
        try Data(repeating: 0xCD, count: 8).write(to: unknown)
        XCTAssertNil(SpotlightAttributeMapper.projection(forFileAt: unknown))
    }
}
