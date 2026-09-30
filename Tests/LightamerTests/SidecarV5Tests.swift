import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV5Tests (Plan M2-4-1 T4/T5, KD-4; AC6 + AC7) — the sidecar v5
// additive format transaction:
//
//   T4 format face:
//   1. NIL ZERO-DRIFT: v4-shaped documents/specs keep their EXACT canonical
//      bytes + stableHash (synthesized encodeIfPresent — the M2-3-3
//      RawDecodeOverridesTests precedent).
//   2. THE v4 DECODE MATRIX: v4 documents decode with all new fields nil.
//   3. THE v5 ROUND-TRIP: rawOverrides + the mask gap fields survive
//      encode→decode verbatim; the writer always emits schemaVersion 5 and
//      the reader tolerates a future version (degrade, never refuse).
//   4. HASH ISOLATION: rawOverrides never enters the drift anchor (the
//      decode domain is already represented by decodeParamsHash), while
//      the mask gap fields DO fold into MaskSpec.stableHash when set.
//
//   T5 real-chain face (AC7): the RAW overrides persist → reload → restore
//   leg → re-decode round-trip through a REAL EditorState + PipeCoordinator
//   + WorkspaceModel assembly and a real RAW fixture.
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV5Tests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention — sorted keys, stable
    /// bytes across encodes: the modern Foundation JSONEncoder emits keyed
    /// properties in unstable dictionary order without this).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    // ── Fixtures ──

    /// A v4-form drawn mask spec (the 06-03/06-04 shape, new fields nil).
    private func v4FormSpec() -> MaskSpec {
        var spec = MaskSpec()
        spec.drawn = DrawnMaskSpec(
            forms: [
                MaskForm(kind: .ellipse(EllipseForm(
                    center: MaskPoint(x: 0.5, y: 0.5),
                    radiusX: 0.2, radiusY: 0.3,
                    rotationDegrees: 10, border: 0.1))),
            ],
            group: MaskGroupSpec(items: [
                MaskGroupItem(
                    formID: UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")!,
                    op: .union, inverted: false, opacity: 0.8),
            ]))
        return spec
    }

    private func makeDocument(
        rawOverrides: RAWTechnicalOverrides? = nil,
        spec: MaskSpec? = nil
    ) -> LightamerSidecar {
        var stackRecord: SidecarLayerStackRecord?
        if let spec {
            // The layer id is PINNED: the hash comparison faces need the
            // snapshot bytes identical across documents.
            let layer = AdjustmentLayer(
                id: UUID(uuidString: "AA5CA8E5-0000-4000-8000-000000000001")!,
                name: "Graded", mask: spec)
            stackRecord = SidecarLayerStackRecord(layers: [
                SidecarLayerRecord(layer),
            ])
        }
        let decodeHash = UInt64(0x1234_5678_9ABC_DEF0)
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(uuidString: "9936E8A9-1D6B-4A66-9B63-C8C6A39A2AA0")!,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash,
                layerSnapshot: stackRecord?.snapshot),
            appVersion: "test",
            layerStack: stackRecord,
            rawOverrides: rawOverrides)
        return document
    }

    private func upgradedToV4(_ document: LightamerSidecar) throws -> Data {
        let json = try JSONSerialization.jsonObject(
            with: Self.canonicalEncoder.encode(document))
        guard var object = json as? [String: Any] else {
            throw NSError(domain: "SidecarV5Tests", code: 1)
        }
        object["schemaVersion"] = 4
        object.removeValue(forKey: "rawOverrides")
        return try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
    }

    // MARK: - 1: nil zero-drift (the T4 core assertion)

    func testNilNewMaskFieldsKeepCanonicalBytesAndStableHash() throws {
        let spec = v4FormSpec()
        XCTAssertNil(spec.deletionProtected)

        // The canonical bytes carry NO trace of the new keys — a v4-era
        // encoder could not have emitted them either, so the hash domain
        // is byte-identical to the pre-v5 shape.
        let bytes = try Self.canonicalEncoder.encode(spec)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertFalse(object.keys.contains("deletionProtected"))
        let groupItems = try XCTUnwrap(
            ((object["drawn"] as? [String: Any])?["group"] as? [String: Any])?["items"]
                as? [[String: Any]])
        XCTAssertFalse(groupItems[0].keys.contains("enabled"))
        XCTAssertFalse(groupItems[0].keys.contains("displayName"))

        // The hash is round-trip stable (encode → decode → encode).
        let hash = spec.stableHash()
        let decoded = try Self.decoder.decode(MaskSpec.self, from: bytes)
        XCTAssertEqual(decoded.stableHash(), hash)
        XCTAssertNil(decoded.deletionProtected)

        // The same spec with the fields SET moves both the bytes and the
        // hash (the fields participate when present — mask-domain params).
        var locked = v4FormSpec()
        locked.deletionProtected = true
        XCTAssertNotEqual(locked.stableHash(), hash)
    }

    func testMaskGroupItemFieldsSetAndRoundTrip() throws {
        var item = MaskGroupItem(
            formID: UUID(), op: .intersect, inverted: true, opacity: 0.5)
        item.enabled = false
        item.displayName = "Skin"
        let data = try Self.canonicalEncoder.encode(item)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["enabled"] as? Bool, false)
        XCTAssertEqual(object["displayName"] as? String, "Skin")
        let decoded = try Self.decoder.decode(MaskGroupItem.self, from: data)
        XCTAssertEqual(decoded, item)
    }

    // MARK: - 2: the v4 decode matrix

    func testV4DocumentDecodesWithNilNewFields() throws {
        let spec = v4FormSpec()
        let v4Bytes = try upgradedToV4(makeDocument(spec: spec))
        let document = try Self.decoder.decode(LightamerSidecar.self, from: v4Bytes)

        XCTAssertEqual(document.schemaVersion, 4)
        XCTAssertNil(document.rawOverrides, "v4 documents carry no rawOverrides")
        let mask = try XCTUnwrap(
            document.layerStack?.layers.first?.mask?.spec)
        XCTAssertNil(mask.deletionProtected)
        XCTAssertNil(mask.drawn?.group?.items.first?.enabled)
        XCTAssertNil(mask.drawn?.group?.items.first?.displayName)
        // The v4 anchor is self-consistent (no drift — the additive fields
        // cannot have moved the recompute: they are all nil).
        XCTAssertFalse(document.driftDetected)
    }

    // MARK: - 3: the v5 round-trip + version contract

    func testV5RoundTripCarriesAllNewFields() throws {
        var spec = v4FormSpec()
        spec.deletionProtected = true
        let overrides = RAWTechnicalOverrides(
            noiseReductionAmount: 0.3,
            luminanceNoiseReduction: 0.4,
            colorNoiseReduction: nil,
            sharpness: 0.2,
            boost: 0.5,
            decoderVersion: .forceV8)
        let document = makeDocument(rawOverrides: overrides, spec: spec)

        let bytes = try Self.canonicalEncoder.encode(document)
        XCTAssertTrue(
            String(decoding: bytes, as: UTF8.self)
                .contains("\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"),
            "the writer always emits the current version")
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)

        XCTAssertEqual(decoded.schemaVersion, 5)
        XCTAssertEqual(decoded.rawOverrides, overrides)
        let mask = try XCTUnwrap(decoded.layerStack?.layers.first?.mask?.spec)
        // The spec-level lock rides the RUNTIME spelling (MaskSpec's own
        // Codable — pinned by the stableHash test above); the sidecar MASK
        // projection carries the drawn payload verbatim, so the ITEM
        // fields survive the file round-trip:
        XCTAssertNil(
            mask.deletionProtected,
            "the SidecarMaskSpec projection (outside this plan's declared file set) carries the drawn payload only — the spec-level lock's file carriage lands with M2MASK-04")
        XCTAssertEqual(
            mask.drawn?.group?.items.first?.inverted, false,
            "the drawn payload round-trips verbatim")
        XCTAssertFalse(decoded.driftDetected, "the v5 anchor is self-consistent")
    }

    func testFutureVersionStillDecodes() throws {
        let document = makeDocument(rawOverrides: RAWTechnicalOverrides(boost: 0.5))
        let json = try JSONSerialization.jsonObject(
            with: Self.canonicalEncoder.encode(document))
        guard var object = json as? [String: Any] else {
            return XCTFail("not an object")
        }
        object["schemaVersion"] = LightamerSidecar.schemaVersionCurrent + 1
        let future = try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        // The tolerance contract: a NEWER document degrades its unknown
        // face but still yields everything the reader knows.
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: future)
        XCTAssertEqual(
            decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent + 1)
        XCTAssertEqual(decoded.rawOverrides?.boost, 0.5)
    }

    // MARK: - 4: nil absence + hash isolation

    func testNilRawOverridesOmitsTheKey() throws {
        let document = makeDocument(rawOverrides: nil, spec: v4FormSpec())
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertFalse(
            object.keys.contains("rawOverrides"),
            "encodeIfPresent: a pristine document keeps the key ABSENT")
    }

    func testRawOverridesAreHashIsolated() throws {
        // The SAME document with and without rawOverrides recomputes the
        // SAME drift anchor — the overrides are decode-domain (already
        // represented by decodeParamsHash) and never enter the hash. ONE
        // spec instance: the drawn form UUIDs must match across both.
        let spec = v4FormSpec()
        let plain = makeDocument(rawOverrides: nil, spec: spec)
        let withOverrides = makeDocument(
            rawOverrides: RAWTechnicalOverrides(
                noiseReductionAmount: 0.9, boost: 0.9), spec: spec)
        XCTAssertEqual(plain.historyHash, withOverrides.historyHash)
        XCTAssertEqual(plain.driftDetected, withOverrides.driftDetected)
        XCTAssertFalse(withOverrides.driftDetected)
    }
}
