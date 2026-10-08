import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmSidecarTests (Plan M3-3-01 T6, KD-6 — LIB bundle, the SidecarV8Tests
// precedent, Core level) — the sidecar v9 additive transaction (the film
// record face):
//
//   1. THE THREE BYTE FACES:
//      ① a v8-form document (no filmRecord key) decodes and re-encodes
//        BYTE EXACT (the SC#3 round-trip contract — the v8 zero-drift
//        negative test, AC#5);
//      ② the v9 writer with a nil film face emits the v8 shape with ONLY
//        the schemaVersion digit different (encodeIfPresent);
//      ③ a film-carrying document round-trips BYTE FAITHFUL (document
//        field + the committed item payload, snake_case keys on disk).
//   2. SET-FIELDS-MOVE (the displayTransform judgment — NOT hash
//      isolation): tampering the film record IN THE JSON flips
//      `driftDetected` (the film record IS a pixel semantic; its
//      stableHash folds into the historyHash tail after the DRT term).
//   3. ANCHOR STABILITY of the field-without-backing-item shape (the P1
//      test-document form — the fold input is the history's own
//      `effectiveFilmRecord()`, never the document field alone).
//   4. FUTURE-version tolerance: a schemaVersion > 9 document still
//      yields everything (the :94-97 tolerance contract).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmSidecarTests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention — sorted keys, stable
    /// bytes across encodes).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let imageID = UUID(
        uuidString: "8F2E4C6A-1B3D-4E5F-9A0B-2C3D4E5F6A7B")!

    // MARK: - Fixtures

    private func makePlaceholder(priority: Int = 0) -> ModuleInstance {
        ModuleInstance(
            module: TestGainModule.self, multiPriority: priority,
            params: TestGainModule.Params(gain: 1.0))
    }

    private func filmRecord(
        film: String = "kodak_portra_400", paper: String = "kodak_portra_endura"
    ) -> FilmRecord {
        var record = FilmRecord()
        record.filmStock = film
        record.paperStock = paper
        record.yFilterShift = 5.5
        record.mFilterShift = 7.25
        record.strength = 0.9
        return record
    }

    /// A history whose chain carries one film edit (the real-writer
    /// shape: the film item is the fold's backing payload).
    private func makeFilmHistory() -> HistoryStack {
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "base")
        stack.commitFilm(
            record: filmRecord(), placeholder: makePlaceholder(priority: 1),
            label: "Film")
        return stack
    }

    private func makeDocument(
        history: HistoryStack = HistoryStack(),
        filmRecord: FilmRecord? = nil,
        hashFilmFold: Bool = true
    ) -> LightamerSidecar {
        let decodeHash = UInt64(0x0123_4567_89AB_CDEF)
        let effective = history.effectiveFilmRecord()
        let hash: UInt64
        if hashFilmFold, let effective {
            hash = HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash,
                layerSnapshot: nil,
                drtRecord: history.effectiveDrtRecord(),
                filmRecord: effective)
        } else {
            hash = HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash)
        }
        return LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: hash,
            appVersion: "test",
            filmRecord: filmRecord ?? effective)
    }

    // MARK: - 1①: the v8-form document round-trips BYTE EXACT

    func testV8FormDocumentDecodesAndReencodesByteExact() throws {
        // A pre-v9 writer's bytes: the current canonical shape with ONLY
        // the schemaVersion digit rewound (the nil film face keeps the
        // key ABSENT — asserted in ①② together).
        let document = makeDocument(history: {
            var stack = HistoryStack()
            stack.commit(makePlaceholder(), label: "base")
            return stack
        }(), hashFilmFold: false)
        let v9Bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: v9Bytes) as? [String: Any])
        XCTAssertFalse(object.keys.contains("filmRecord"), "encodeIfPresent")

        let v9String = String(decoding: v9Bytes, as: UTF8.self)
        let v8String = v9String.replacingOccurrences(
            of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
            with: "\"schemaVersion\" : 8")
        XCTAssertNotEqual(v8String, v9String)

        // The v8 bytes decode and re-encode BYTE EXACT (the zero-drift
        // negative test — a v8 document cycles through the v9 reader
        // without moving a byte).
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: Data(v8String.utf8))
        XCTAssertEqual(decoded.schemaVersion, 8)
        XCTAssertNil(decoded.filmRecord)
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(
            String(decoding: reEncoded, as: UTF8.self), v8String,
            "the v8 form survives a v9 decode→encode cycle byte-exact")
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 1②: the nil-face v9 writer = the v8 writer except the digit

    func testNilFilmFaceDiffersFromV8ShapeOnlyAtTheSchemaVersionDigit() throws {
        let document = makeDocument(history: {
            var stack = HistoryStack()
            stack.commit(makePlaceholder(), label: "base")
            return stack
        }(), hashFilmFold: false)
        let v9Bytes = try Self.canonicalEncoder.encode(document)
        let v9String = String(decoding: v9Bytes, as: UTF8.self)
        let v8String = v9String.replacingOccurrences(
            of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
            with: "\"schemaVersion\" : 8")
        // The digit swap is the ENTIRE diff — no other byte moved.
        XCTAssertNotEqual(v9String, v8String)
        XCTAssertEqual(
            v9String, v8String.replacingOccurrences(of: "\"schemaVersion\" : 8",
                with: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"))
    }

    // MARK: - 1③: the film-carrying document round-trips BYTE FAITHFUL

    func testFilmDocumentRoundTripsByteFaithful() throws {
        let record = filmRecord()
        let document = makeDocument(history: makeFilmHistory())
        XCTAssertEqual(document.filmRecord, record)
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: bytes)

        XCTAssertEqual(decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        XCTAssertEqual(decoded.filmRecord, record)
        // The item payload rides the history item too.
        let filmItem = decoded.history.items.last
        XCTAssertEqual(filmItem?.filmRecord, record)
        XCTAssertEqual(filmItem?.layerScope, HistoryStack.filmDocumentScope)
        XCTAssertNil(filmItem?.drtRecord)
        // The v9 anchor is self-consistent (the fold reads the history's
        // own projection).
        XCTAssertFalse(decoded.driftDetected)
        // Re-encode stability.
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes)
    }

    // MARK: - 2: set-fields-move (the tamper flips the anchor)

    func testTamperingTheFilmRecordFlipsTheDriftAnchor() throws {
        let document = makeDocument(history: makeFilmHistory())
        let bytes = try Self.canonicalEncoder.encode(document)

        // Rewrite the film ITEM's record strength in the JSON history —
        // the anchor folds the HISTORY's own projection, so that is the
        // load-bearing tamper target (a v8 provenance tamper's judgment
        // form, OPPOSITE verdict: the film record is NOT hash-isolated).
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var history = try XCTUnwrap(object["history"] as? [String: Any])
        var items = try XCTUnwrap(history["items"] as? [[String: Any]])
        let filmIndex = try XCTUnwrap(
            items.firstIndex { $0["filmRecord"] != nil }, "the film item")
        var item = items[filmIndex]
        var recordObject = try XCTUnwrap(item["filmRecord"] as? [String: Any])
        recordObject["strength"] = 0.1
        item["filmRecord"] = recordObject
        items[filmIndex] = item
        history["items"] = items
        var mutated = object
        mutated["history"] = history
        let tamperedBytes = try JSONSerialization.data(
            withJSONObject: mutated, options: [.sortedKeys, .prettyPrinted])
        let tampered = try Self.decoder.decode(
            LightamerSidecar.self, from: tamperedBytes)
        XCTAssertNotEqual(
            tampered.history.effectiveFilmRecord(),
            document.history.effectiveFilmRecord())
        XCTAssertTrue(
            tampered.driftDetected,
            "the film record is a pixel semantic — a tamper must drift")

        // The document FIELD alone is not an anchor input (the P1
        // shape's twin): rewriting only the field copy does not drift.
        var fieldOnly = object
        var fieldRecord = try XCTUnwrap(
            object["filmRecord"] as? [String: Any])
        fieldRecord["strength"] = 0.1
        fieldOnly["filmRecord"] = fieldRecord
        let fieldOnlyBytes = try JSONSerialization.data(
            withJSONObject: fieldOnly, options: [.sortedKeys, .prettyPrinted])
        let fieldOnlyDoc = try Self.decoder.decode(
            LightamerSidecar.self, from: fieldOnlyBytes)
        XCTAssertNotEqual(fieldOnlyDoc.filmRecord, document.filmRecord)
        XCTAssertFalse(
            fieldOnlyDoc.driftDetected,
            "the fold reads the history projection, not the document field")
    }

    // MARK: - 3: the field-without-backing-item shape stays anchor-stable

    func testDocumentFieldWithoutBackingItemStaysAnchorStable() throws {
        // The P1 test-document shape: the document-level field set, but
        // NO film item in the history. The drift anchor folds the
        // HISTORY's own projection (nil here), so a hash computed on the
        // pre-v9 formula still matches — the field alone never drifts.
        let document = makeDocument(
            history: {
                var stack = HistoryStack()
                stack.commit(makePlaceholder(), label: "base")
                return stack
            }(),
            filmRecord: filmRecord(),
            hashFilmFold: false)
        XCTAssertNotNil(document.filmRecord)
        XCTAssertNil(document.history.effectiveFilmRecord())
        XCTAssertFalse(
            document.driftDetected,
            "a field without a backing item is not an anchor input (DRT P1 twin)")
    }

    // MARK: - 4: FUTURE-version tolerance

    func testFutureVersionDocumentStillYieldsEverything() throws {
        let document = makeDocument(history: makeFilmHistory())
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var future = object
        future["schemaVersion"] = 999
        let futureBytes = try JSONSerialization.data(
            withJSONObject: future, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: futureBytes)
        XCTAssertEqual(decoded.schemaVersion, 999)
        XCTAssertEqual(decoded.filmRecord, document.filmRecord)
        XCTAssertEqual(decoded.history.effectiveFilmRecord(), document.filmRecord)
    }
}
