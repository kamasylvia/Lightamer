import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV7Tests (Plan M2-8-1 T1, KD-1/KD-6 — APP bundle, the
// SidecarV5Tests/DrtSidecarTests precedent) — the sidecar v7 additive
// transaction (the version face):
//
//   1. THE THREE BYTE FACES:
//      ① a v6-form document (no version keys) decodes and re-encodes BYTE
//        EXACT (the decode→encode round-trip is the SC#3 contract);
//      ② the v7 writer with an all-nil version face emits the v6 shape
//        with ONLY the schemaVersion digit different (both new keys
//        ABSENT — encodeIfPresent);
//      ③ a versioned document round-trips BYTE FAITHFUL (records,
//        chains, the active id verbatim).
//   2. ITEMS NEVER DOUBLE-WRITE (AC#6): the ACTIVE chain's bytes live in
//      the `history` key only — the active record carries NO `chain`.
//   3. HASH ISOLATION (KD-1 negative): tampering the version METADATA
//      (a `name` rewrite) never flips `driftDetected` — the version
//      structure is structurally outside the fold formula (the hash
//      signature is untouched; this pins the BEHAVIOR face).
//   4. DANGLING activeVersionID (decode-layer input): the value decodes
//      verbatim with no matching record — the typed degrade (structure
//      dropped, edits kept) is the T2 real-chain behavior face.
//   5. PRISTINE JUDGMENT FACE (KD-6 ②): the projection input
//      (`history.effectiveInstances()`) is not flipped by version
//      structure — an empty ACTIVE chain + non-empty versions still
//      judges "no edits".
//
//   UInt64 note (L013): the version record carries NO hash fields (UUID +
//   Strings + Dates) — the decimal-String lock has ZERO new surface in v7
//   (declared here; nothing to assert mechanically).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV7Tests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention — sorted keys, stable
    /// bytes across encodes).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let imageID = UUID(
        uuidString: "9936E8A9-1D6B-4A66-9B63-C8C6A39A2AA0")!

    // ── Fixtures ──

    private func makeInstance() -> ModuleInstance {
        ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params())
    }

    /// A committed chain with `count` items (labels distinguish them).
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
        versions: [SidecarVersionRecord]? = nil,
        activeVersionID: String? = nil
    ) -> LightamerSidecar {
        let decodeHash = UInt64(0x1234_5678_9ABC_DEF0)
        return LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash),
            appVersion: "test",
            versions: versions,
            activeVersionID: activeVersionID)
    }

    private func versionRecord(
        id: UUID, name: String, chain: HistoryStack?
    ) -> SidecarVersionRecord {
        SidecarVersionRecord(
            id: id, name: name, createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000), chain: chain)
    }

    // MARK: - 1①: the v6-form document round-trips BYTE EXACT

    func testV6FormDocumentDecodesAndReencodesByteExact() throws {
        let document = makeDocument(history: makeChain(count: 2))
        let v7Bytes = try Self.canonicalEncoder.encode(document)

        // The all-nil version face keeps BOTH keys ABSENT (the ② face's
        // key half — asserted here because the v6 bytes are constructed
        // from these).
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: v7Bytes) as? [String: Any])
        XCTAssertFalse(object.keys.contains("versions"), "encodeIfPresent")
        XCTAssertFalse(object.keys.contains("activeVersionID"), "encodeIfPresent")

        // The v6 byte shape = the same canonical bytes with ONLY the
        // schemaVersion digit rewound (the writer emitted no v7 keys, so
        // the digit is the one and only delta).
        let v6Bytes = try v6Shape(of: v7Bytes)
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: v6Bytes)
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(
            String(decoding: reEncoded, as: UTF8.self),
            String(decoding: v6Bytes, as: UTF8.self),
            "the v6 form survives a v7 decode→encode cycle byte-exact")
    }

    // MARK: - 1②: the nil-face v7 writer = the v6 writer except the digit

    func testNilVersionFaceDiffersFromV6ShapeOnlyAtTheSchemaVersionDigit() throws {
        let document = makeDocument(history: makeChain(count: 1))
        let v7Bytes = try Self.canonicalEncoder.encode(document)
        let v7String = String(decoding: v7Bytes, as: UTF8.self)
        let v6String = String(
            decoding: try v6Shape(of: v7Bytes), as: UTF8.self)

        // The digit swap is the ENTIRE diff — no other byte moved.
        XCTAssertNotEqual(v7String, v6String)
        XCTAssertEqual(
            v6String,
            v7String.replacingOccurrences(
                of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
                with: "\"schemaVersion\" : 6"),
            "the nil version face is the v6 byte shape with one digit")

        // And the rewound bytes decode as a clean v6 document (nil face).
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: v6String.data(using: .utf8)!)
        XCTAssertEqual(decoded.schemaVersion, 6)
        XCTAssertNil(decoded.versions)
        XCTAssertNil(decoded.activeVersionID)
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 1③: the versioned document round-trips BYTE FAITHFUL

    func testVersionedDocumentRoundTripsByteFaithful() throws {
        let activeID = UUID()
        let archivedID = UUID()
        let archivedChain = makeChain(count: 3)
        let document = makeDocument(
            history: makeChain(count: 1),
            versions: [
                versionRecord(id: activeID, name: "版本 1", chain: nil),
                versionRecord(id: archivedID, name: "版本 2", chain: archivedChain),
            ],
            activeVersionID: activeID.uuidString)
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)

        XCTAssertEqual(decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        XCTAssertEqual(decoded.activeVersionID, activeID.uuidString)
        XCTAssertEqual(decoded.versions?.count, 2)
        XCTAssertEqual(decoded.versions?[0].id, activeID)
        XCTAssertEqual(decoded.versions?[0].name, "版本 1")
        XCTAssertNil(decoded.versions?[0].chainStack, "the ACTIVE slot carries no chain")
        XCTAssertEqual(decoded.versions?[1].id, archivedID)
        XCTAssertEqual(decoded.versions?[1].chainStack, archivedChain,
                       "the non-active chain round-trips byte-faithful")
        XCTAssertFalse(decoded.driftDetected, "the v7 anchor is self-consistent")
        // And the same writer re-encodes to the same bytes (stability).
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes)
    }

    // MARK: - 2: items never double-write (AC#6)

    func testActiveChainItemsLiveOnlyInTheHistoryKey() throws {
        let activeID = UUID()
        let history = makeChain(count: 2)
        let document = makeDocument(
            history: history,
            versions: [versionRecord(id: activeID, name: "版本 1", chain: nil)],
            activeVersionID: activeID.uuidString)
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])

        // The active record (matched by activeVersionID) carries NO chain
        // key — its items exist ONLY in the history key.
        let versions = try XCTUnwrap(object["versions"] as? [[String: Any]])
        XCTAssertEqual(versions.count, 1)
        let activeRecord = try XCTUnwrap(versions.first {
            ($0["id"] as? String) == activeID.uuidString
        })
        XCTAssertFalse(
            activeRecord.keys.contains("chain"),
            "the active slot's items are NOT duplicated into versions[]")

        // Whole-document count: the items spelling appears exactly once
        // (the history key) — no second copy anywhere.
        let string = String(decoding: bytes, as: UTF8.self)
        XCTAssertEqual(
            string.components(separatedBy: "\"items\"").count - 1, 1,
            "exactly one items array on disk (the active chain)")
    }

    // MARK: - 3: hash isolation (the KD-1 tamper negative)

    func testTamperingVersionMetadataDoesNotFlipTheDriftAnchor() throws {
        let activeID = UUID()
        let document = makeDocument(
            history: makeChain(count: 2),
            versions: [
                versionRecord(id: activeID, name: "版本 1", chain: nil),
                versionRecord(id: UUID(), name: "版本 2", chain: makeChain(count: 1)),
            ],
            activeVersionID: activeID.uuidString)
        let bytes = try Self.canonicalEncoder.encode(document)

        // Rewrite one version's NAME in the JSON — a metadata-only tamper.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var versions = try XCTUnwrap(object["versions"] as? [[String: Any]])
        versions[1]["name"] = "Tampered"
        var mutated = object
        mutated["versions"] = versions
        let tamperedBytes = try JSONSerialization.data(
            withJSONObject: mutated, options: [.sortedKeys])

        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: tamperedBytes)
        XCTAssertFalse(
            decoded.driftDetected,
            "version metadata is not a pixel semantic — the anchor ignores it")
    }

    // MARK: - 4: dangling activeVersionID (decode-layer input face)

    func testDanglingActiveVersionIDDecodesVerbatim() throws {
        let document = makeDocument(
            history: makeChain(count: 1),
            versions: [versionRecord(id: UUID(), name: "版本 1", chain: nil)],
            activeVersionID: UUID().uuidString) // no matching record
        let bytes = try Self.canonicalEncoder.encode(document)

        // Decode face: the document is NOT refused — the value survives
        // verbatim; the STRUCTURE drop (slots cleared, history kept) is
        // the T2 restore-leg behavior (VersionSwapTests).
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: bytes)
        XCTAssertNotNil(decoded.activeVersionID)
        XCTAssertNotEqual(
            decoded.activeVersionID, decoded.versions?.first?.id.uuidString)
        XCTAssertEqual(decoded.versions?.count, 1)
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 5: the pristine judgment face (KD-6 ②)

    func testEmptyActiveChainWithVersionsStillJudgesNoEdits() throws {
        // An empty-chain version creation (position -1) + version
        // structure: the projection input stays EMPTY — has_edits/pristine
        // faces are judged from items/position, never from versions.
        let activeID = UUID()
        let document = makeDocument(
            history: HistoryStack(), // position -1, zero items
            versions: [
                versionRecord(id: activeID, name: "版本 1", chain: nil),
                versionRecord(id: UUID(), name: "版本 2", chain: makeChain(count: 1)),
            ],
            activeVersionID: activeID.uuidString)
        XCTAssertTrue(
            document.history.effectiveInstances().isEmpty,
            "the projection judgment input is not flipped by version structure")
        XCTAssertEqual(document.history.position, -1)
        XCTAssertEqual(document.versions?.count, 2)
    }

    // MARK: - The branch seam (KD-1 ③: copyingPrefixOf)

    func testCopyingPrefixOfTakesTheRedoTailFreePrefix() throws {
        var source = makeChain(count: 4)
        source.jump(to: 1) // jumped back — items 2..3 are the redo tail

        let branch = HistoryStack.copyingPrefixOf(source, upTo: source.position)
        XCTAssertEqual(branch.items.count, 2, "the redo tail stays in the source")
        XCTAssertEqual(branch.position, 1, "position sits at the copy tail")
        XCTAssertEqual(branch.items, source.items[0...1].map { $0 })

        // Clamped edges: pristine source → the empty stack; count-1 → all.
        XCTAssertEqual(
            HistoryStack.copyingPrefixOf(HistoryStack(), upTo: -1).items.count, 0)
        let full = HistoryStack.copyingPrefixOf(source, upTo: 99)
        XCTAssertEqual(full.items.count, 4)
        XCTAssertEqual(full.position, 3)
        // Value semantics: the copy is independent (mutating the source's
        // pointer never moves the branch).
        var mutated = source
        mutated.jump(to: 3)
        XCTAssertEqual(branch.position, 1)
    }

    // MARK: - Helpers

    /// The v6 byte shape of the current writer's output: rewind ONLY the
    /// schemaVersion digit (the nil version face guarantees no v7 keys —
    /// asserted by the callers).
    private func v6Shape(of v7Bytes: Data) throws -> Data {
        let string = String(decoding: v7Bytes, as: UTF8.self)
        let current = "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"
        guard string.contains(current) else {
            throw NSError(domain: "SidecarV7Tests", code: 1)
        }
        return Data(string.replacingOccurrences(of: current, with: "\"schemaVersion\" : 6").utf8)
    }
}
