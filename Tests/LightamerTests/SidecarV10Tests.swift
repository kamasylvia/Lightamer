import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SidecarV10Tests (Plan M6-2-01 T1, KD-1/KD-2 — LIB bundle, the
// FilmSidecarTests precedent, Core level) — the sidecar v10 additive
// transaction (the render process face) + the ledger/clamp faces:
//
//   1. THE THREE BYTE FACES:
//      ① a v9-form document (no process key) decodes and re-encodes
//        BYTE EXACT (the v9 zero-drift negative test — the SC#3 round-trip
//        contract);
//      ② the v10 writer with a nil process face emits the v9 shape with
//        ONLY the schemaVersion digit different (encodeIfPresent);
//      ③ a process-carrying document round-trips BYTE FAITHFUL.
//   2. HASH ISOLATION (OQ-2): ± process → the SAME historyHash bytes and
//      driftDetected double-false (a semantic label, never a pixel edit).
//   3. THE LENIENT DECODE TABLE (OQ-3, LightCraft form): legal domain
//      1...0xFFFF_FFFF retained (integral float 2.0 → 2); the corrupt set
//      (negative / 2.5 / string / null / array / 2^32) all → nil with the
//      rest of the document alive; a corrupt value is NOT retained (the
//      re-encode leaves the key ABSENT); stored-0 normalizes ABSENT
//      (0 ≡ absent ≡ legacy, the M1 double-gate note's stored side).
//   4. FUTURE-version tolerance (schemaVersion 11 reads everything).
//   5. THE LEDGER FACES (KD-1): type domain gate (0...0xFFFF_FFFF),
//      legacy/current constants (current == 1), ALL/current ordering,
//      the resolving clamp table (0/1/7/2^32−1 → v1).
//   6. THE TRANSPORT NEGATIVES (OQ-2): a version chain coexists with the
//      process key (the version slot never carries the process); the
//      LightamerPreset container has NO process key (presets never carry).
// ─────────────────────────────────────────────────────────────────────────────

final class SidecarV10Tests: XCTestCase {

    /// Canonical JSON (the D-S2 writer convention — sorted keys, stable
    /// bytes across encodes).
    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    private static let imageID = UUID(
        uuidString: "A1D2E3F4-1B3D-4E5F-9A0B-2C3D4E5F6A7C")!

    // MARK: - Fixtures

    private func makePlaceholder(priority: Int = 0) -> ModuleInstance {
        ModuleInstance(
            module: TestGainModule.self, multiPriority: priority,
            params: TestGainModule.Params(gain: 1.0))
    }

    private func makeDocument(
        history: HistoryStack = HistoryStack(),
        process: RenderProcessVersion? = nil
    ) -> LightamerSidecar {
        let decodeHash = UInt64(0x0123_4567_89AB_CDEF)
        return LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeHash,
            instances: [],
            history: history,
            historyHash: HistoryHash.hash(
                stack: history, decodeParamsHash: decodeHash),
            appVersion: "test",
            process: process)
    }

    /// Digit-rewound form (the FilmSidecarTests mechanics): the canonical
    /// bytes with ONLY the schemaVersion digit swapped.
    private func rewindToV9(_ document: LightamerSidecar) throws -> String {
        let currentBytes = try Self.canonicalEncoder.encode(document)
        let currentString = String(decoding: currentBytes, as: UTF8.self)
        let v9String = currentString.replacingOccurrences(
            of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
            with: "\"schemaVersion\" : 9")
        XCTAssertNotEqual(v9String, currentString)
        return v9String
    }

    // MARK: - 1①: the v9-form document round-trips BYTE EXACT

    func testV9FormDocumentDecodesAndReencodesByteExact() throws {
        let document = makeDocument(history: {
            var stack = HistoryStack()
            stack.commit(makePlaceholder(), label: "base")
            return stack
        }())
        XCTAssertNil(document.process)
        let v9String = try rewindToV9(document)

        // The v9 bytes decode (process = nil = legacy) and re-encode BYTE
        // EXACT — the key ABSENT on the write side (never passively
        // upgraded).
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: Data(v9String.utf8))
        XCTAssertEqual(decoded.schemaVersion, 9)
        XCTAssertNil(decoded.process)
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(
            String(decoding: reEncoded, as: UTF8.self), v9String,
            "the v9 form survives a v10 decode→encode cycle byte-exact")
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 1②: the nil-face v10 writer = the v9 writer except the digit

    func testNilProcessFaceDiffersFromV9ShapeOnlyAtTheSchemaVersionDigit() throws {
        let document = makeDocument(history: {
            var stack = HistoryStack()
            stack.commit(makePlaceholder(), label: "base")
            return stack
        }())
        let v10Bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: v10Bytes) as? [String: Any])
        XCTAssertFalse(
            object.keys.contains("process"),
            "encodeIfPresent — the nil (legacy) face keeps the key ABSENT")
        let v10String = String(decoding: v10Bytes, as: UTF8.self)
        let v9String = v10String.replacingOccurrences(
            of: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)",
            with: "\"schemaVersion\" : 9")
        // The digit swap is the ENTIRE diff — no other byte moved.
        XCTAssertNotEqual(v10String, v9String)
        XCTAssertEqual(
            v10String, v9String.replacingOccurrences(
                of: "\"schemaVersion\" : 9",
                with: "\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"))
    }

    // MARK: - 1③: the process-carrying document round-trips BYTE FAITHFUL

    func testProcessDocumentRoundTripsByteFaithful() throws {
        let document = makeDocument(
            history: {
                var stack = HistoryStack()
                stack.commit(makePlaceholder(), label: "base")
                return stack
            }(),
            process: .current)
        XCTAssertEqual(document.process, .current)
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: bytes)

        XCTAssertEqual(decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        XCTAssertEqual(decoded.process, .current)
        XCTAssertFalse(decoded.driftDetected)
        // Re-encode stability (byte-faithful round trip).
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes)
    }

    // MARK: - 2: hash isolation (OQ-2)

    func testProcessIsHashIsolated() throws {
        let history: HistoryStack = {
            var stack = HistoryStack()
            stack.commit(makePlaceholder(), label: "base")
            return stack
        }()
        let without = makeDocument(history: history, process: nil)
        let with = makeDocument(history: history, process: .current)
        let forward = makeDocument(
            history: history, process: RenderProcessVersion(rawValue: 7)!)

        // The SAME stack + decode seed → the SAME anchor bytes regardless
        // of the process face (the semantic label never folds).
        XCTAssertEqual(without.historyHash, with.historyHash)
        XCTAssertEqual(without.historyHash, forward.historyHash)
        XCTAssertFalse(without.driftDetected)
        XCTAssertFalse(with.driftDetected)
        XCTAssertFalse(forward.driftDetected)
        // The v7 version structure stays untouched too (the metadata
        // judgment: the fold formula is structural, not field-additive).
        XCTAssertEqual(without.layerStack, with.layerStack)
    }

    // MARK: - 3a: the lenient legal domain (1 / 2 / 0xFFFFFFFF retained)

    func testLenientLegalDomainBoundariesAreRetained() throws {
        let document = makeDocument()
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])

        for raw in [1, 2, 0xFFFF_FFFF] {
            var mutated = object
            mutated["process"] = raw
            let data = try JSONSerialization.data(
                withJSONObject: mutated, options: [.sortedKeys, .prettyPrinted])
            let decoded = try Self.decoder.decode(
                LightamerSidecar.self, from: data)
            XCTAssertEqual(
                decoded.process, RenderProcessVersion(rawValue: raw),
                "in-domain integer \(raw) is retained verbatim")
            // The re-encode preserves it (no downgrade on the write side).
            let reDecoded = try Self.decoder.decode(
                LightamerSidecar.self,
                from: Self.canonicalEncoder.encode(decoded))
            XCTAssertEqual(reDecoded.process?.rawValue, raw)
        }
    }

    // MARK: - 3b: the integral float form (2.0 → 2)

    func testIntegralFloatTwoPointZeroDecodesAsTwo() throws {
        let document = makeDocument()
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var mutated = object
        mutated["process"] = 2.0
        let data = try JSONSerialization.data(
            withJSONObject: mutated, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(LightamerSidecar.self, from: data)
        XCTAssertEqual(decoded.process, RenderProcessVersion(rawValue: 2)!)
        // The write side emits the INTEGER form (2, never 2.0).
        let reEncodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Self.canonicalEncoder.encode(decoded)) as? [String: Any])
        XCTAssertEqual(reEncodedObject["process"] as? Int, 2)
    }

    // MARK: - 3c: the corrupt set all → nil (the document survives)

    func testCorruptValuesDecodeAsNilWithoutHarmingTheDocument() throws {
        let history: HistoryStack = {
            var stack = HistoryStack()
            stack.commit(makePlaceholder(), label: "base")
            return stack
        }()
        let document = makeDocument(history: history)
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])

        let corruptSet: [Any] = [
            -1, 2.5, "x", NSNull(), [1, 2], 0x1_0000_0000,
        ]
        for corrupt in corruptSet {
            var mutated = object
            mutated["process"] = corrupt
            let data = try JSONSerialization.data(
                withJSONObject: mutated, options: [.sortedKeys, .prettyPrinted])
            let decoded = try Self.decoder.decode(
                LightamerSidecar.self, from: data)
            XCTAssertNil(
                decoded.process,
                "corrupt value \(corrupt) normalizes to legacy-nil")
            // The tolerant-decode discipline: the rest of the document
            // stays fully alive.
            XCTAssertEqual(decoded.schemaVersion, document.schemaVersion)
            XCTAssertEqual(decoded.imageID, document.imageID)
            XCTAssertEqual(decoded.history.items.count, 1)
            XCTAssertFalse(decoded.driftDetected)
        }
    }

    // MARK: - 3d: stored-0 normalizes to the ABSENT key

    func testStoredZeroNormalizesToAbsentKey() throws {
        let document = makeDocument()
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var withZero = object
        withZero["process"] = 0
        let zeroBytes = try JSONSerialization.data(
            withJSONObject: withZero, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: zeroBytes)
        XCTAssertNil(decoded.process, "stored-0 ≡ legacy (the M1 stored gate)")

        // The re-encode leaves the key ABSENT (0 ≡ absent — the
        // skip-serializing-if form; the normalization is pinned here).
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        let reEncodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: reEncoded) as? [String: Any])
        XCTAssertFalse(
            reEncodedObject.keys.contains("process"),
            "a stored-0 document re-saves without the key")
    }

    // MARK: - 3e: a corrupt value is not retained (the re-save drops it)

    func testCorruptValueIsNotRetainedOnRewrite() throws {
        let document = makeDocument()
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var corrupted = object
        corrupted["process"] = "garbage"
        let corruptBytes = try JSONSerialization.data(
            withJSONObject: corrupted, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: corruptBytes)
        XCTAssertNil(decoded.process)

        // The writer emits the nil face → the key ABSENT (损坏值不保留).
        let rewritten = try Self.canonicalEncoder.encode(decoded)
        let rewrittenObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        XCTAssertFalse(rewrittenObject.keys.contains("process"))
    }

    // MARK: - 4: FUTURE-version tolerance

    func testFutureVersionDocumentStillYieldsEverything() throws {
        let document = makeDocument(
            history: {
                var stack = HistoryStack()
                stack.commit(makePlaceholder(), label: "base")
                return stack
            }(),
            process: .current)
        let bytes = try Self.canonicalEncoder.encode(document)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var future = object
        future["schemaVersion"] = 11
        let futureBytes = try JSONSerialization.data(
            withJSONObject: future, options: [.sortedKeys, .prettyPrinted])
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: futureBytes)
        XCTAssertEqual(decoded.schemaVersion, 11)
        XCTAssertEqual(decoded.process, .current)
        XCTAssertFalse(decoded.driftDetected)
    }

    // MARK: - 5a: the type domain gate + the constants (KD-1)

    func testVersionTypeDomainGateAndConstants() {
        // The VALUE-TYPE gate includes 0 (the legacy sentinel) — the M1
        // double-gate note: this is the in-memory carrier's domain, the
        // sidecar's stored-value gate starts at 1.
        XCTAssertNil(RenderProcessVersion(rawValue: -1))
        XCTAssertNil(RenderProcessVersion(rawValue: 0x1_0000_0000))
        for raw in [0, 1, 2, 7, 0xFFFF_FFFF] {
            XCTAssertEqual(RenderProcessVersion(rawValue: raw)?.rawValue, raw)
        }
        XCTAssertEqual(RenderProcessVersion.legacy.rawValue, 0)
        // The M8-2 bump: the spectral film core's generation is the mint
        // (the ledger case doc = the ledger line; the re-pin discipline).
        XCTAssertEqual(RenderProcessVersion.current.rawValue, 2)
        XCTAssertNotEqual(RenderProcessVersion.legacy, RenderProcessVersion.current)
    }

    // MARK: - 5b: the ALL/current ledger face

    func testLedgerAllAndCurrentFaces() {
        // Oldest-first; current = last; the M8-2 two-generation shape (v1
        // the frozen density arm, v2 the spectral core -- the ledger case
        // docs are the register).
        XCTAssertEqual(RenderProcess.all, [.v1, .v2])
        XCTAssertEqual(RenderProcess.all.first, .v1,
                       "the oldest generation stays first (the freeze's arm)")
        XCTAssertEqual(RenderProcess.current, .v2)
        XCTAssertNotEqual(RenderProcess.all.first, RenderProcess.current,
                          "M8-2 opened the first real semantic fork")
        XCTAssertEqual(
            RenderProcess.current.processVersion, RenderProcessVersion.current)
    }

    // MARK: - 5c: the resolving clamp table

    func testResolvingClampTable() {
        // raw ≤ 0 → the OLDEST case (the legacy freeze made executable;
        // only 0 is constructible through the domain gate — negatives are
        // rejected at `init?`, the guard arm is defense in depth).
        XCTAssertEqual(
            RenderProcess.resolving(.legacy), RenderProcess.all.first!)
        // In-domain → its own case.
        XCTAssertEqual(
            RenderProcess.resolving(RenderProcessVersion(rawValue: 1)!), .v1)
        // Forward larger numbers clamp to current (the render clamp — the
        // STORED value itself is never rewritten; the SidecarV10Tests
        // retention tests pin that half).
        XCTAssertEqual(
            RenderProcess.resolving(RenderProcessVersion(rawValue: 7)!),
            RenderProcess.current)
        XCTAssertEqual(
            RenderProcess.resolving(
                RenderProcessVersion(rawValue: 0xFFFF_FFFF)!),
            RenderProcess.current)
    }

    // MARK: - 6a: the version slot never carries the process (coexistence)

    func testVersionChainCoexistsWithTheProcessKey() throws {
        // The v7 version structure + the v10 process key ride the SAME
        // document (the process is document-level, shared across version
        // slots — the version chain never carries a process of its own).
        var stack = HistoryStack()
        stack.commit(makePlaceholder(), label: "base")
        let now = Date()
        let slot = SidecarVersionRecord(
            id: UUID(uuidString: "B0B0B0B0-0000-4000-8000-0000000000B1")!,
            name: "Version 1", createdAt: now, updatedAt: now,
            chain: HistoryStack())
        let document = LightamerSidecar(
            imageID: Self.imageID,
            decoderVersionUsed: "v8",
            decodeParamsHash: 0x1234,
            instances: [],
            history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: 0x1234),
            appVersion: "test",
            versions: [slot],
            activeVersionID: slot.id.uuidString,
            process: .current)
        let bytes = try Self.canonicalEncoder.encode(document)
        let decoded = try Self.decoder.decode(
            LightamerSidecar.self, from: bytes)
        XCTAssertEqual(decoded.versions?.count, 1)
        XCTAssertEqual(decoded.process, .current)
        XCTAssertFalse(decoded.driftDetected)
        // Round-trip byte stability across the two faces together.
        let reEncoded = try Self.canonicalEncoder.encode(decoded)
        XCTAssertEqual(reEncoded, bytes)
        // The slot's own spelling carries NO process key.
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let versions = try XCTUnwrap(object["versions"] as? [[String: Any]])
        XCTAssertFalse(versions[0].keys.contains("process"))
    }

    // MARK: - 6b: the preset container has NO process key

    func testLightamerPresetCarriesNoProcessKey() throws {
        let preset = LightamerPreset(
            kind: .develop, name: "NoProcess",
            instances: [makePlaceholder()])
        let bytes = try Self.canonicalEncoder.encode(preset)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertFalse(
            object.keys.contains("process"),
            "presets never carry the process (OQ-2: copy/paste/sync/preset never transport it)")
        // And a decode tolerates a hand-injected key without effect on the
        // document equality (unknown keys are ignored by JSONDecoder).
        let decoded = try Self.decoder.decode(
            LightamerPreset.self, from: bytes)
        XCTAssertEqual(decoded, preset)
    }
}
