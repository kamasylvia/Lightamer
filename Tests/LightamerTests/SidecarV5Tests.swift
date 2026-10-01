import LightamerCore
import LightamerIOP
import Metal
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
        spec.contentRevision = 7
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

        // v6 bump (M2-6-1 T6): the pin follows the CURRENT version constant
        // — the writer's contract is "always emits the current version",
        // which moved from the literal 5 to 6 with the additive bump.
        XCTAssertEqual(decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        XCTAssertEqual(decoded.rawOverrides, overrides)
        let mask = try XCTUnwrap(decoded.layerStack?.layers.first?.mask?.spec)
        // M2-7 flip (Plan M2-7-1 T4, KD-4 — the D-M2-4-1-3 gap-pin above is
        // now a TRUE two-way carriage assertion): the SidecarMaskSpec
        // projection captures AND restores the spec-level lock and the
        // content revision; the drawn payload verbatim check stays.
        XCTAssertEqual(mask.deletionProtected, true, "the lock rides the file now")
        XCTAssertEqual(mask.contentRevision, 7, "the revision rides the file now")
        XCTAssertEqual(
            mask.drawn?.group?.items.first?.inverted, false,
            "the drawn payload round-trips verbatim")
        XCTAssertFalse(decoded.driftDetected, "the v5 anchor is self-consistent")
    }

    // MARK: - M2-7: the revision data face (Plan M2-7-1 T4, KD-3/KD-5)

    /// The bump primitive (nil → 1, then +1), the optimistic-concurrency
    /// gate (nil folds to 0 both sides), and the mask-hash fold.
    func testContentRevisionBumpAndMatchesExpectedPrimitives() throws {
        var spec = v4FormSpec()
        XCTAssertNil(spec.contentRevision, "pre-M2-7 shape decodes nil")

        spec.bumpContentRevision()
        XCTAssertEqual(spec.contentRevision, 1, "nil folds to 0, then +1")
        spec.bumpContentRevision()
        XCTAssertEqual(spec.contentRevision, 2, "exactly +1 per bump")

        // The gate: nil ↔ 0 folding both sides (the single implementation).
        XCTAssertTrue(MaskSpec.matchesExpected(nil, in: MaskSpec()))
        XCTAssertFalse(MaskSpec.matchesExpected(1, in: MaskSpec()))
        XCTAssertTrue(MaskSpec.matchesExpected(2, in: spec))
        XCTAssertFalse(MaskSpec.matchesExpected(1, in: spec), "stale snapshot")
        XCTAssertFalse(MaskSpec.matchesExpected(3, in: spec), "unseen write")

        // Setting the revision moves the canonical bytes + the hash; the
        // round-trip is stable (encode → decode → encode).
        let withRevision = spec
        let bytes = try Self.canonicalEncoder.encode(withRevision)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["contentRevision"] as? Int, 2)
        let hash = withRevision.stableHash()
        let decoded = try Self.decoder.decode(MaskSpec.self, from: bytes)
        XCTAssertEqual(decoded.contentRevision, 2)
        XCTAssertEqual(decoded.stableHash(), hash)
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

    // MARK: - T5: the REAL load chain (AC7, checker E1)

    /// The repo RAW fixture (the GUI-22 precedent: skip when absent).
    private var fixtureURL: URL {
        let testsDir = (#filePath as NSString).deletingLastPathComponent
        let repoRoot = ((testsDir as NSString).deletingLastPathComponent as NSString)
            .deletingLastPathComponent
        return URL(fileURLWithPath: repoRoot)
            .appendingPathComponent("input/RAW/DSC00012.ARW")
    }

    /// A fresh per-test work directory with the fixture copied in (the
    /// sidecars land beside it — never beside the repo input sample).
    private func makeWorkCopy() throws -> URL {
        let fixture = fixtureURL
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("RAW fixture missing: \(fixture.path)")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidecarv5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: url)
        return url
    }

    /// A drift-free sidecar document (empty history, self-consistent
    /// anchor) with an optional rawOverrides payload.
    private func writeDriftFreeSidecar(
        to imageURL: URL, rawOverrides: RAWTechnicalOverrides?
    ) throws {
        let decodeHash = UInt64(42)
        let history = HistoryStack()
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash, instances: [], history: history,
            historyHash: HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash, layerSnapshot: nil),
            appVersion: "test", rawOverrides: rawOverrides)
        try Self.canonicalEncoder.encode(document).write(
            to: LightamerSidecar.sidecarURL(for: imageURL))
    }

    /// The production composition minus windowing: EditorState +
    /// PipeCoordinator + WorkspaceModel cross-attached (the KD-5 E1③
    /// channel), registry + metal injected.
    @MainActor
    private func makeAssembly() async throws -> (
        editorState: EditorState, coordinator: PipeCoordinator,
        workspace: WorkspaceModel, metal: MetalContext
    ) {
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        let workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry, defaultFace: false)
        return (editorState, coordinator, workspace, metal)
    }

    /// Poll until the boost readback shows `value` (the decoded readback
    /// face — the decode #2 completion marker), with a generous timeout.
    @MainActor
    private func waitForBoostReadback(
        _ editorState: EditorState, value: Double?, timeout: TimeInterval
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if editorState.image?.rawTech.boost == value, !editorState.isDecoding {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("decode readback never reached boost=\(String(describing: value))")
    }

    /// AC7 write leg: panel commit → session carrier → the pass-through
    /// hook → the throttled document → the flushed FILE carries the
    /// rawOverrides field; reload reads the same value back.
    @MainActor
    func testWriteLegPersistsOverridesIntoTheSidecarFile() async throws {
        let url = try makeWorkCopy()
        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        editorState.load(
            url: url, decoder: workspace.editorDecoder, metal: metal,
            logger: EditorState.decodeLogger)
        try await waitForBoostReadback(editorState, value: nil, timeout: 90)

        // The panel commit's exact shape (the view body is untouched —
        // the hook rides the WorkspaceModel write face).
        let overrides = RAWTechnicalOverrides(boost: 0.6)
        workspace.setRawDecodeOverrides(overrides, for: url)
        // Let the schedule task hop to the store actor (pending is set
        // there asynchronously; production flush sites are seconds later).
        try await Task.sleep(for: .milliseconds(200))
        await coordinator.flushSidecar()

        let document = try Self.decoder.decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(for: url)))
        XCTAssertEqual(
            document.rawOverrides, overrides,
            "the flushed sidecar carries the persisted overrides (M2DIS-04)")

        // Reload on a FRESH assembly (the closed-editor semantics): the
        // load side receives the same value from the file.
        // coordinator2 stays a NAMED binding: the assembly's weak
        // cross-references die with an immediately-discarded tuple slot.
        let (editorState2, coordinator2, workspace2, metal2) = try await makeAssembly()
        editorState2.load(
            url: url, decoder: workspace2.editorDecoder, metal: metal2,
            logger: EditorState.decodeLogger)
        try await waitForBoostReadback(editorState2, value: 0.6, timeout: 90)
        XCTAssertEqual(
            workspace2.rawDecodeOverrides(for: url), overrides,
            "the restore leg primes the session carrier from the document")
    }

    /// AC7 restore leg (E1 方案①): a document WITH rawOverrides loaded by
    /// a fresh session — decode #1 is identity, the restore leg primes the
    /// carrier and triggers the re-decode; the FINAL decoded readback
    /// carries the stored overrides.
    @MainActor
    func testRestoreLegReDecodesWithStoredOverrides() async throws {
        let url = try makeWorkCopy()
        let stored = RAWTechnicalOverrides(boost: 0.6)
        try writeDriftFreeSidecar(to: url, rawOverrides: stored)

        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        // The identity first frame arrives, then the overrides replace it.
        editorState.load(
            url: url, decoder: workspace.editorDecoder, metal: metal,
            logger: EditorState.decodeLogger)
        try await waitForBoostReadback(editorState, value: 0.6, timeout: 120)

        XCTAssertEqual(
            editorState.image?.rawTech.boost, 0.6,
            "the FINAL decoded readback carries the stored overrides")
        XCTAssertEqual(
            workspace.rawDecodeOverrides(for: url), stored,
            "the restore leg primed the session cache (switch-back = single decode)")
        // A switch-back reload with the cache in place does NOT re-decode:
        // the frame already carries the overrides (the equivalence gate) —
        // the readback stays 0.6 and no second prime can occur.
        editorState.load(
            url: url, decoder: workspace.editorDecoder, metal: metal,
            logger: EditorState.decodeLogger, overrides: stored)
        try await waitForBoostReadback(editorState, value: 0.6, timeout: 90)
    }

    /// AC7 pristine leg: a v5 document WITHOUT the rawOverrides key —
    /// single decode, zero re-decode, zero priming (the session dict stays
    /// empty and the identity readback is never replaced).
    @MainActor
    func testPristineDocumentSingleDecodesWithoutPriming() async throws {
        let url = try makeWorkCopy()
        try writeDriftFreeSidecar(to: url, rawOverrides: nil)

        let (editorState, coordinator, workspace, metal) = try await makeAssembly()
        editorState.load(
            url: url, decoder: workspace.editorDecoder, metal: metal,
            logger: EditorState.decodeLogger)
        // The identity readback settles and STAYS (a re-decode with any
        // overrides would surface here as a non-nil boost leg).
        try await waitForBoostReadback(editorState, value: nil, timeout: 90)
        try await Task.sleep(for: .milliseconds(600)) // the re-decode window
        _ = coordinator // alive to scope end (the weak web must not die)
        XCTAssertNil(
            editorState.image?.rawTech.boost,
            "no re-decode may fire for a pristine document")
        XCTAssertTrue(
            workspace.rawDecodeOverrides.isEmpty,
            "a pristine document never primes the session carrier")
    }
}
