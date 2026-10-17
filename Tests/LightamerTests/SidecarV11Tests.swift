import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV11Tests (Plan M7-4-01 T6/F1 — the SidecarV10Tests precedent shape,
// same bundle slot) — the sidecar v11 additive transaction (the per-item
// note/author attribution face, MCP2-09):
//
//   1. THE THREE BYTE FACES:
//      ① a v10-form document (no note/author keys) decodes and re-encodes
//        BYTE EXACT (the v10 zero-drift negative — the SC#3 round-trip
//        contract);
//      ② the v11 writer with nil note/author emits the v10 shape with
//        ONLY the schemaVersion digit different (encodeIfPresent — nil
//        never enters the bytes);
//      ③ a note/author-carrying document round-trips BYTE FAITHFUL.
//   2. HASH ISOLATION (M7-4-01): ± note/author on the SAME editing state
//      → the SAME historyHash bytes (item metadata never enters the fold;
//      the HistoryHash mechanism's negative test).
//   3. FUTURE-version tolerance (schemaVersion 12 reads everything) —
//      the CHECKER C1 migration guard: the V10 file's future-tolerance
//      method hardcodes `schemaVersion = 11`, which the v11 bump turned
//      into "current readable" — THIS file re-arms the forward guard at
//      12 (the V10 file stays byte-untouched by design; its semantic
//      shift is declared in the M7-4-01 DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV11Tests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention — sorted keys, stable
    /// bytes across encodes).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let imageID = UUID(
        uuidString: "C2D3E4F5-2C4E-5F6A-8B1C-3D4E5F6A7B8D")!

    // MARK: - Fixtures

    private func makePlaceholder(priority: Int = 0) -> ModuleInstance {
        ModuleInstance(
            module: TestGainModule.self, multiPriority: priority,
            params: TestGainModule.Params(gain: 1.0))
    }

    /// A stack whose top item is an MCP-shaped PASTE commit (the note/
    /// author carrier shape).
    private func makePasteHistory(
        note: String?, author: String?
    ) -> HistoryStack {
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "base")
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        stack.commitPaste(
            records: [makePlaceholder(priority: 1)],
            label: "MCP paste_adjustments", timestamp: stamp,
            scope: HistoryStack.pasteEpochScope, note: note, author: author)
        return stack
    }

    private func makeDocument(history: HistoryStack) -> LightamerSidecar {
        let decodeHash = UInt64(0x0123_4567_89AB_CDEF)
        return LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash),
            appVersion: "test")
    }

    /// Digit-rewound form (the FilmSidecarTests mechanics): the canonical
    /// bytes with ONLY the schemaVersion digit swapped.
    private func rewindToV10(_ document: LightamerSidecar) throws -> String {
        let currentBytes = try Self.canonicalEncoder.encode(document)
        let currentString = String(decoding: currentBytes, as: UTF8.self)
        let v10String = currentString.replacingOccurrences(
            of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
            with: "\"schemaVersion\" : 10")
        XCTAssertNotEqual(v10String, currentString)
        return v10String
    }

    // MARK: - 1①: the v10-form document round-trips BYTE EXACT

    func testV10FormDocumentDecodesAndReencodesByteExact() throws {
        let document = makeDocument(history: makePasteHistory(
            note: nil, author: nil))
        XCTAssertNil(document.history.items.last?.note)
        XCTAssertNil(document.history.items.last?.author)
        let v10String = try rewindToV10(document)

        // The v10 bytes decode (note/author = nil = pre-M7-4) and
        // re-encode BYTE EXACT — the keys ABSENT on the write side (never
        // passively upgraded).
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: Data(v10String.utf8))
        XCTAssertEqual(decoded.schemaVersion, 10)
        XCTAssertNil(decoded.history.items.last?.note)
        XCTAssertNil(decoded.history.items.last?.author)
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(
            String(decoding: reEncoded, as: UTF8.self), v10String,
            "the v10 form survives a v11 decode→encode cycle byte-exact")
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 1②: the nil-face v11 writer = the v10 shape minus the digit

    func testNilNoteAuthorFaceDiffersFromV10ShapeOnlyAtTheSchemaVersionDigit()
        throws {
        let document = makeDocument(history: makePasteHistory(
            note: nil, author: nil))
        let v11Bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: v11Bytes) as? [String: Any])
        let history = try XCTUnwrap(object["history"] as? [String: Any])
        let items = try XCTUnwrap(history["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        for item in items {
            XCTAssertFalse(
                item.keys.contains("note"),
                "encodeIfPresent — the nil face keeps the key ABSENT")
            XCTAssertFalse(
                item.keys.contains("author"),
                "encodeIfPresent — the nil face keeps the key ABSENT")
        }
        let v11String = String(decoding: v11Bytes, as: UTF8.self)
        let v10String = v11String.replacingOccurrences(
            of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
            with: "\"schemaVersion\" : 10")
        // The digit swap is the ENTIRE diff — no other byte moved.
        XCTAssertNotEqual(v11String, v10String)
        XCTAssertEqual(
            v11String, v10String.replacingOccurrences(
                of: "\"schemaVersion\" : 10",
                with: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"))
    }

    // MARK: - 1③: the stamped document round-trips BYTE FAITHFUL

    func testStampedDocumentRoundTripsByteFaithful() throws {
        let document = makeDocument(history: makePasteHistory(
            note: "pasted by the agent", author: "mcp"))
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: bytes)

        XCTAssertEqual(
            decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        let top = try XCTUnwrap(decoded.history.items.last)
        XCTAssertEqual(top.note, "pasted by the agent")
        XCTAssertEqual(top.author, "mcp")
        XCTAssertFalse(decoded.driftDetected)
        // The MIRROR read-back face: the sidecar record's `item`
        // reconstruction carries the two fields (F1 — init carries on
        // write, `item` restores on read; four pieces or the face dies).
        XCTAssertEqual(
            decoded.history.items.map(\.id),
            document.history.items.map(\.id))
        // Re-encode stability (byte-faithful round trip).
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes)
    }

    // MARK: - 2: the HistoryHash negative (note/author never fold)

    func testNoteAuthorAreHistoryHashIsolated() throws {
        let decodeHash = UInt64(0x0123_4567_89AB_CDEF)
        let plain = makeDocument(history: makePasteHistory(
            note: nil, author: nil))
        let stamped = makeDocument(history: makePasteHistory(
            note: "pasted by the agent", author: "mcp"))
        // The SAME editing state (identical records/labels/scope) ± the
        // attribution fields → the SAME anchor bytes.
        XCTAssertEqual(plain.historyHash, stamped.historyHash)
        // And the recompute face agrees (the drift judgment stays clean).
        XCTAssertEqual(
            stamped.historyHash,
            HistoryHash.hash(
                stack: stamped.history, decodeParamsHash: decodeHash),
            "the written hash recomputes identically (no drift)")
        XCTAssertFalse(stamped.driftDetected)
    }

    // MARK: - 3: FUTURE-version tolerance (CHECKER C1's migration guard)

    func testFutureVersionTwelveDocumentStillYieldsEverything() throws {
        let document = makeDocument(history: makePasteHistory(
            note: "pasted by the agent", author: "mcp"))
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var future = object
        future["schemaVersion"] = 12
        let futureBytes = try JSONSerialization.data(
            withJSONObject: future, options: [.sortedKeys, .prettyPrinted])
        // The forward-tolerant degrade: a LATER version reads everything
        // (LightamerSidecar's schemaVersion > current tolerance note —
        // the guard re-armed here after the v11 bump).
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: futureBytes)
        XCTAssertEqual(decoded.schemaVersion, 12)
        let top = try XCTUnwrap(decoded.history.items.last)
        XCTAssertEqual(top.note, "pasted by the agent")
        XCTAssertEqual(top.author, "mcp")
        XCTAssertFalse(decoded.driftDetected)
    }
}
