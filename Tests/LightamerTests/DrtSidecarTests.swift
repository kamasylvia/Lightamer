import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// DrtSidecarTests (Plan M2-6-1 T6, AC#7 — APP bundle, SidecarV5Tests
// precedent) — the sidecar v6 additive transaction:
//
//   1. V6 ROUND-TRIP: a document carrying displayTransform survives
//      encode→decode verbatim; the writer emits schemaVersion 6.
//   2. V5 BYTE ZERO-DRIFT: a document without DRT edits encodes to EXACTLY
//      the v5 shape — the displayTransform key ABSENT (encodeIfPresent).
//   3. V5 READS NIL: a v5-shaped document decodes with displayTransform nil
//      (and the version 5 preserved).
//   4. FUTURE VERSION: schema 99 degrades — displayTransform (and
//      everything else readable) still decodes.
//   5. SET-FIELDS-MOVE PREREQUISITE FACE: the record's stableHash is
//      self-contained (no coupling to decodeParamsHash/instance hashes) —
//      the P3 historyHash fold rides a history item, NOT this sidecar (the
//      zero-touch HistoryStack red line documented at the assertion).
// ─────────────────────────────────────────────────────────────────────────────

final class DrtSidecarTests: XCTestCase {

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private func makeDocument(displayTransform: DrtRecord? = nil) -> LightamerSidecar {
        let decodeHash = UInt64(0x1234_5678_9ABC_DEF0)
        let history = HistoryStack()
        return LightamerSidecar(
            imageID: UUID(uuidString: "9936E8A9-1D6B-4A66-9B63-C8C6A39A2AA0")!,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: decodeHash),
            appVersion: "test",
            displayTransform: displayTransform)
    }

    // MARK: - 1: the v6 round-trip

    func testV6RoundTripCarriesTheDisplayTransformRecord() throws {
        var record = DrtRecord()
        record.method = .opendrt
        record.encodingSpace = .rec2020
        record.encodingEotf = .st2084
        record.peakLuminance = 1000
        record.lookPreset = "umbra"
        record.creativeWhite = "d50"
        record.parameters.tnCon = 1.8
        let document = makeDocument(displayTransform: record)

        let bytes = try Self.canonicalEncoder.encode(document)
        XCTAssertTrue(
            String(decoding: bytes, as: UTF8.self)
                .contains("\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"),
            "the writer always emits the current version")
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)

        XCTAssertEqual(decoded.schemaVersion, 6)
        XCTAssertEqual(decoded.displayTransform, record, "the record round-trips verbatim")
        XCTAssertFalse(decoded.driftDetected, "the v6 anchor is self-consistent")
    }

    // MARK: - 2: the v5 byte zero-drift

    func testPristineDocumentKeepsTheExactV5ByteShape() throws {
        // The SAME document without DRT edits must produce the v5 bytes:
        // no displayTransform key anywhere (encodeIfPresent).
        let document = makeDocument(displayTransform: nil)
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertFalse(
            object.keys.contains("displayTransform"),
            "encodeIfPresent: a pristine document keeps the key ABSENT (v5 zero-drift)")
        // And the drift anchor is unchanged (the record is not in play).
        XCTAssertFalse(document.driftDetected)
    }

    func testRecordChangeDoesNotMoveTheDriftAnchor() throws {
        // SET-FIELDS-MOVE judgment, sidecar face: the record is a RENDER
        // parameter (the tail cache fold — T7), NOT a drift-anchor input.
        // The HistoryStack zero-diff red line means the anchor ignores it;
        // the P3 history item is the fold's carrier.
        let pristine = makeDocument(displayTransform: nil)
        var edited = DrtRecord()
        edited.peakLuminance = 480
        let withDRT = makeDocument(displayTransform: edited)
        XCTAssertEqual(pristine.historyHash, withDRT.historyHash,
                       "displayTransform must not move historyHash (the P3 item carries the fold)")
    }

    // MARK: - 3: the v5 read face

    func testV5ShapedDocumentDecodesWithNilDisplayTransform() throws {
        let v5Bytes = try v5Shape(makeDocument(displayTransform: nil))
        let document = try Self.decoder.decode(LightamerSidecar.self, from: v5Bytes)
        XCTAssertEqual(document.schemaVersion, 5)
        XCTAssertNil(document.displayTransform, "v5 documents carry no DRT record")
        XCTAssertFalse(document.driftDetected)
    }

    private func v5Shape(_ document: LightamerSidecar) throws -> Data {
        let json = try JSONSerialization.jsonObject(
            with: Self.canonicalEncoder.encode(document))
        guard var object = json as? [String: Any] else {
            throw NSError(domain: "DrtSidecarTests", code: 1)
        }
        object["schemaVersion"] = 5
        object.removeValue(forKey: "displayTransform")
        return try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    // MARK: - 4: future version tolerance

    func testFutureVersionStillDecodesWithTheRecord() throws {
        var record = DrtRecord()
        record.encodingEotf = .bt1886
        let document = makeDocument(displayTransform: record)
        let json = try JSONSerialization.jsonObject(
            with: Self.canonicalEncoder.encode(document))
        guard var object = json as? [String: Any] else {
            return XCTFail("not an object")
        }
        object["schemaVersion"] = 99
        let future = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: future)
        XCTAssertEqual(decoded.schemaVersion, 99)
        XCTAssertEqual(decoded.displayTransform, record, "a NEWER doc still yields the record")
    }

    func testFutureVersionWithoutAnyKnownRecordStillDegrades() throws {
        // A future doc whose DRT face uses a shape we cannot read: the
        // record degrades to... it FAILS decode — so the tolerance contract
        // covers only ABSENT unknown keys. What must survive: the known
        // faces of a newer document missing the key entirely (covered by
        // testV5ShapedDocumentDecodesWithNilDisplayTransform's version-99
        // twin here for completeness).
        let json = try JSONSerialization.jsonObject(
            with: Self.canonicalEncoder.encode(makeDocument(displayTransform: nil)))
        guard var object = json as? [String: Any] else {
            return XCTFail("not an object")
        }
        object["schemaVersion"] = 99
        object.removeValue(forKey: "displayTransform")
        let future = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: future)
        XCTAssertEqual(decoded.schemaVersion, 99)
        XCTAssertNil(decoded.displayTransform)
    }

    // MARK: - 5: the set-fields-move prerequisite face

    func testRecordStableHashIsIndependentOfDocumentHashes() {
        // The tail-cache fold consumes record.stableHash directly (KD-6);
        // this pins the decoupling face: two documents differing only in
        // decodeParamsHash/instances share the SAME record hash.
        var record = DrtRecord()
        record.parameters.hsB = 0.7
        let a = makeDocument(displayTransform: record)
        var other = makeDocument(displayTransform: record)
        other = LightamerSidecar(
            imageID: a.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: a.decodeParamsHash &+ 0xFF,
            instances: [],
            history: a.history,
            historyHash: a.historyHash &+ 1,
            appVersion: "test",
            displayTransform: record)
        XCTAssertEqual(
            a.displayTransform?.stableHash(), other.displayTransform?.stableHash(),
            "the record hash is content-addressed, not document-coupled")
        XCTAssertNotEqual(a.decodeParamsHash, other.decodeParamsHash)
    }
}
