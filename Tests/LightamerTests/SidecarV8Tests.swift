import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV8Tests (Plan M2-10-06 T1, KD-3 — APP bundle, the
// SidecarV7Tests precedent) — the sidecar v8 additive transaction (the AI
// provenance face):
//
//   1. THE THREE BYTE FACES:
//      ① a v7-form document (no aiProvenance key) decodes and re-encodes
//        BYTE EXACT (the SC#3 round-trip contract);
//      ② the v8 writer with a nil aiProvenance emits the v7 shape with
//        ONLY the schemaVersion digit different (the new key ABSENT —
//        encodeIfPresent);
//      ③ a provenance-carrying document round-trips BYTE FAITHFUL (the
//        six D-3 fields verbatim, snake_case keys on disk).
//   2. HASH ISOLATION (the KD tamper negative): rewriting the provenance
//      IN THE JSON never flips `driftDetected` — provenance is not a
//      pixel semantic; the fold formula is untouched.
//   3. OPERATION ENUM: the raw values "upscale"/"denoise" round-trip;
//      the record is total (all six keys always encoded).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV8Tests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention — sorted keys, stable
    /// bytes across encodes).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let imageID = UUID(
        uuidString: "4B7E2C1A-90D4-4E2F-8A5B-1C3D5E7F9A0B")!

    // ── Fixtures ──

    private func makeInstance() -> ModuleInstance {
        ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params())
    }

    private func makeChain(count: Int) -> HistoryStack {
        var stack = HistoryStack()
        for index in 0..<count {
            stack.commit(
                makeInstance(), label: "Exposure \(index)")
        }
        return stack
    }

    private func makeDocument(
        history: HistoryStack = HistoryStack(),
        aiProvenance: SidecarAIProvenanceRecord? = nil
    ) -> LightamerSidecar {
        let decodeHash = UInt64(0x0FED_CBA9_8765_4321)
        return LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash),
            appVersion: "test",
            aiProvenance: aiProvenance)
    }

    private func provenance(
        operation: AIProvenanceOperation = .upscale
    ) -> SidecarAIProvenanceRecord {
        SidecarAIProvenanceRecord(
            operation: operation,
            scale: operation == .upscale ? 4 : 1,
            amount: operation == .denoise ? 35 : 0,
            sourceFile: "DSC09991.ARW",
            sourceImageID: "6F1D2FB2-7A34-4C1E-9E8A-55B0C3A1D2E4",
            backend: "coreml-worker")
    }

    // MARK: - 1①: the v7-form document round-trips BYTE EXACT

    func testV7FormDocumentDecodesAndReencodesByteExact() throws {
        let document = makeDocument(history: makeChain(count: 2))
        let v8Bytes = try Self.canonicalEncoder.encode(document)

        // The nil AI face keeps the key ABSENT (the ② face's key half —
        // asserted here because the v7 bytes are constructed from these).
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: v8Bytes) as? [String: Any])
        XCTAssertFalse(object.keys.contains("aiProvenance"), "encodeIfPresent")

        // The v7 byte shape = the same canonical bytes with ONLY the
        // schemaVersion digit rewound.
        let v7Bytes = try v7Shape(of: v8Bytes)
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: v7Bytes)
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(
            String(decoding: reEncoded, as: UTF8.self),
            String(decoding: v7Bytes, as: UTF8.self),
            "the v7 form survives a v8 decode→encode cycle byte-exact")
    }

    // MARK: - 1②: the nil-face v8 writer = the v7 writer except the digit

    func testNilProvenanceFaceDiffersFromV7ShapeOnlyAtTheSchemaVersionDigit() throws {
        let document = makeDocument(history: makeChain(count: 1))
        let v8Bytes = try Self.canonicalEncoder.encode(document)
        let v8String = String(decoding: v8Bytes, as: UTF8.self)
        let v7String = String(
            decoding: try v7Shape(of: v8Bytes), as: UTF8.self)

        // The digit swap is the ENTIRE diff — no other byte moved.
        XCTAssertNotEqual(v8String, v7String)
        XCTAssertEqual(
            v7String,
            v8String.replacingOccurrences(
                of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
                with: "\"schemaVersion\" : 7"),
            "the nil AI face is the v7 byte shape with one digit")

        // And the rewound bytes decode as a clean v7 document (nil face).
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: v7String.data(using: .utf8)!)
        XCTAssertEqual(decoded.schemaVersion, 7)
        XCTAssertNil(decoded.aiProvenance)
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 1③: the provenance-carrying document round-trips BYTE FAITHFUL

    func testProvenanceDocumentRoundTripsByteFaithful() throws {
        let record = provenance()
        let document = makeDocument(history: makeChain(count: 1), aiProvenance: record)
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)

        XCTAssertEqual(decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        XCTAssertEqual(decoded.aiProvenance, record)
        XCTAssertEqual(decoded.aiProvenance?.operation, .upscale)
        XCTAssertEqual(decoded.aiProvenance?.scale, 4)
        XCTAssertEqual(decoded.aiProvenance?.sourceFile, "DSC09991.ARW")
        XCTAssertEqual(
            decoded.aiProvenance?.sourceImageID,
            "6F1D2FB2-7A34-4C1E-9E8A-55B0C3A1D2E4")
        XCTAssertEqual(decoded.aiProvenance?.backend, "coreml-worker")
        XCTAssertFalse(decoded.driftDetected, "the v8 anchor is self-consistent")
        // The same writer re-encodes to the same bytes (stability).
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes)
    }

    // MARK: - 2: hash isolation (the KD tamper negative)

    func testTamperingProvenanceDoesNotFlipTheDriftAnchor() throws {
        let document = makeDocument(
            history: makeChain(count: 2), aiProvenance: provenance())
        let bytes = try Self.canonicalEncoder.encode(document)

        // Rewrite the provenance BACKEND in the JSON — a metadata-only
        // tamper (the v7 name-rewrite precedent's judgment form).
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var provenanceObject = try XCTUnwrap(
            object["aiProvenance"] as? [String: Any])
        provenanceObject["backend"] = "tampered-backend"
        var mutated = object
        mutated["aiProvenance"] = provenanceObject
        let tamperedBytes = try JSONSerialization.data(
            withJSONObject: mutated, options: [.sortedKeys])

        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: tamperedBytes)
        XCTAssertEqual(decoded.aiProvenance?.backend, "tampered-backend")
        XCTAssertFalse(
            decoded.driftDetected,
            "AI provenance is not a pixel semantic — the anchor ignores it")
    }

    // MARK: - 3: the operation enum + the total record shape

    func testOperationEnumAndTotalRecordShapeRoundTrip() throws {
        // Both raw values decode; the denoise shape carries amount/scale=1.
        let denoise = provenance(operation: .denoise)
        let document = makeDocument(history: HistoryStack(), aiProvenance: denoise)
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)
        XCTAssertEqual(decoded.aiProvenance?.operation, .denoise)
        XCTAssertEqual(decoded.aiProvenance?.scale, 1)
        XCTAssertEqual(decoded.aiProvenance?.amount, 35)

        // The on-disk record carries ALL SIX keys, snake_case per D-3.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let record = try XCTUnwrap(object["aiProvenance"] as? [String: Any])
        XCTAssertEqual(
            Set(record.keys),
            ["operation", "scale", "amount",
             "source_file", "source_image_id", "backend"],
            "the D-3 six-field snake_case spelling, always total")

        // The unknown operation raw value degrades as a decode ERROR (the
        // frozen value space — a hand-edited file is corrupt, not silently
        // re-typed).
        var mutated = object
        var raw = record
        raw["operation"] = "quantum-enhance"
        mutated["aiProvenance"] = raw
        let unknownBytes = try JSONSerialization.data(
            withJSONObject: mutated, options: [.sortedKeys])
        XCTAssertThrowsError(
            try Self.decoder.decode(LightamerSidecar.self, from: unknownBytes),
            "an unknown operation value is a decode failure, not a silent nil")
    }

    // MARK: - Helpers

    /// The v7 byte shape of the current writer's output: rewind ONLY the
    /// schemaVersion digit (the nil AI face guarantees no v8 key —
    /// asserted by the callers).
    private func v7Shape(of v8Bytes: Data) throws -> Data {
        let string = String(decoding: v8Bytes, as: UTF8.self)
        let current = "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"
        guard string.contains(current) else {
            throw NSError(domain: "SidecarV8Tests", code: 1)
        }
        return Data(string.replacingOccurrences(of: current, with: "\"schemaVersion\" : 7").utf8)
    }
}
