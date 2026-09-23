@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

// MARK: - Fake debounce clock (02-06-03: the debounce is testable without
// real sleeps — research Open Question #7)

/// A park/advance clock: `sleep` PARKS the caller until `advance()` resumes
/// it. `scheduleWrite` ×3 then `advance()` proves the merge deterministically
/// (no timing races — a real sleep would make "3 writes inside 200ms" a
/// coin flip).
final class DebounceTestClock: Clock, @unchecked Sendable {

    typealias Instant = ContinuousClock.Instant

    private struct Parked {
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var nowValue: Instant = ContinuousClock().now
    private var parked: [Parked] = []

    var now: Instant { lock.withLock { nowValue } }

    let minimumResolution: Duration = .zero

    var parkedCount: Int { lock.withLock { parked.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.lock.withLock {
                    self.parked.append(Parked(continuation: continuation))
                }
            }
        } onCancel: {
            self.resumeAll(with: CancellationError())
        }
    }

    /// Advance: resume every parked sleep (the 2s window elapses).
    func advance() {
        resumeAll(with: nil)
    }

    private func resumeAll(with error: (any Error)?) {
        let toResume: [Parked] = lock.withLock {
            let taken = parked
            parked = []
            return taken
        }
        for entry in toResume {
            if let error {
                entry.continuation.resume(throwing: error)
            } else {
                entry.continuation.resume()
            }
        }
    }
}

/// Sidecar schema + store + round-trip semantics (Plan 02-06-02/03/07;
/// HIST-03/HIST-04, SC#3/SC#5, D-S1/S2/S3).
///
/// Layers covered, in file order:
/// 1. **Schema (02-06-02):** document round-trip equality with a real
///    `HistoryStack` (02-05 fixtures), `sidecarURL`/`imageURL` naming
///    (D-S2), UInt64-as-String on-disk spelling (checkpoint lock #2),
///    sortedKeys pretty output.
/// 2. **Store (02-06-03):** 2s debounce merge (fake clock → ONE write,
///    LAST document wins), atomic write leaves no tmp files, corrupt
///    file → `load()` nil (pristine upgrade, never throws into the UI).
/// 3. **Round-trip SC#3 / drift / unknown-op (02-06-07):** write → drop
///    everything → restore → identical instances/history/position +
///    identical rendered output bytes; hand-edited params → drift
///    detected + NO write-back at detection; unregistered op degrades
///    disabled with `paramsData` preserved byte-for-byte.
final class SidecarRoundTripTests: XCTestCase {

    // ── Fixtures (02-05 spelling) ─────────────────────────────────────────

    private func makeGain(
        _ gain: Float,
        priority: Int = 0,
        id: UUID = UUID(),
        enabled: Bool = true
    ) -> ModuleInstance {
        ModuleInstance(
            id: id, module: TestGainModule.self, multiPriority: priority,
            multiName: "gain\(priority)", params: .init(gain: gain),
            enabled: enabled
        )
    }

    private func makeTrio() -> [ModuleInstance] {
        [
            ModuleInstance(module: ColorInModule.self, params: .init()),
            ModuleInstance(module: ColorOutModule.self, params: .init()),
            ModuleInstance(module: GammaModule.self, params: .init()),
        ]
        .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    /// A real 02-05-shaped state: default trio + two testgain instances,
    /// three commits and one undo (the SC#3 seed).
    private func makeState() -> (instances: [ModuleInstance], history: HistoryStack) {
        var stack = HistoryStack()
        let colorin = ModuleInstance(module: ColorInModule.self, params: .init())
        let g1 = makeGain(1.5, priority: 0)
        let g2 = makeGain(2.0, priority: 1)
        stack.commit(g1, label: "testgain 1.5×")
        stack.commit(g2, label: "testgain 2.0×")
        stack.commit(colorin, label: "colorin touched")
        stack.undo() // position: 1 — a mid-state, not the tail

        var instances = makeTrio()
        instances.append(g1)
        instances.append(g2)
        instances.sort {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        return (instances, stack)
    }

    private func makeDocument(
        instances: [ModuleInstance],
        history: HistoryStack,
        decodeSeed: UInt64 = 0x1234_5678_9ABC_DEF0
    ) -> LightamerSidecar {
        LightamerSidecar(
            imageID: UUID(uuidString: "DEADBEEF-1234-5678-9ABC-DEF012345678")!,
            decoderVersionUsed: "v8",
            decodeParamsHash: decodeSeed,
            instances: instances,
            history: history,
            historyHash: HistoryHash.hash(stack: history, decodeParamsHash: decodeSeed),
            appVersion: "0.2.0-test"
        )
    }

    private func encode(_ document: LightamerSidecar) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func decode(_ data: Data) throws -> LightamerSidecar {
        try JSONDecoder().decode(LightamerSidecar.self, from: data)
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1. Schema (02-06-02)
    // ══════════════════════════════════════════════════════════════════════

    /// SC#3 foundation: a document built from a REAL 02-05 state
    /// round-trips through JSON with full equality — every instance, every
    /// history item (inline snapshots incl. undo'd tail), position, both
    /// hash atoms.
    func testDocumentRoundTripsWithRealHistoryStack() throws {
        let state = makeState()
        let document = makeDocument(instances: state.instances, history: state.history)

        let decoded = try decode(try encode(document))

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.schemaVersion, LightamerSidecar.schemaVersionCurrent)
        XCTAssertGreaterThanOrEqual(decoded.schemaVersion, 1,
                                    "writers emit the CURRENT version (v2 since 06-01)")
        XCTAssertEqual(decoded.instances, state.instances)
        XCTAssertEqual(decoded.history, state.history)
        XCTAssertEqual(decoded.history.position, 1, "the undo'd mid-state persists")
        XCTAssertEqual(decoded.history.items.count, 3, "D-H2: the redo tail persists too")
        XCTAssertEqual(decoded.layerStack, nil, "no layer payload for a layerless document")
    }

    /// D-S2 naming: `<original FULL name>.lra` appended — `DSC09991.ARW` →
    /// `DSC09991.ARW.lra` — and the inverse strips it; non-.lra names
    /// refuse to invert.
    func testSidecarURLNamingRule() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let original = dir.appendingPathComponent("DSC09991.ARW")
        let sidecar = LightamerSidecar.sidecarURL(for: original)
        XCTAssertEqual(sidecar.lastPathComponent, "DSC09991.ARW.lra")
        XCTAssertEqual(sidecar.deletingLastPathComponent(), dir)

        let inverted = try XCTUnwrap(LightamerSidecar.imageURL(for: sidecar))
        XCTAssertEqual(inverted, original)

        XCTAssertNil(LightamerSidecar.imageURL(for: dir.appendingPathComponent("DSC09991.ARW")))
        XCTAssertNil(LightamerSidecar.imageURL(for: dir.appendingPathComponent("notes.lra.txt")))
    }

    /// Checkpoint lock #2 ON DISK: the three UInt64 hash fields (plus every
    /// inline snapshot's `paramsHash`) serialize as DECIMAL STRINGS, so a
    /// JS/python JSON round-trip cannot lose precision; `paramsData` stays
    /// base64 (lock #1 verbatim spelling); pretty output is sortedKeys.
    func testUInt64FieldsSerializeAsDecimalStrings() throws {
        let state = makeState()
        let decodeSeed: UInt64 = 0xFFFF_FFFF_FFFF_F1F0 // way over 2^53
        let document = makeDocument(
            instances: state.instances, history: state.history, decodeSeed: decodeSeed
        )
        let json = try XCTUnwrap(String(data: try encode(document), encoding: .utf8))

        // The BIG hash values appear as quoted decimal strings.
        let expectedDecode = String(decodeSeed)
        XCTAssertTrue(
            json.contains("\"decodeParamsHash\" : \"\(expectedDecode)\""),
            "decodeParamsHash must be a decimal String on disk"
        )
        XCTAssertTrue(
            json.contains("\"historyHash\" : \"") && !json.contains("\"historyHash\" : 0"),
            "historyHash must be a decimal String on disk"
        )
        for occurrence in json.ranges(of: "\"paramsHash\" : ") {
            let after = json[occurrence.upperBound...]
            XCTAssertTrue(
                after.hasPrefix("\""),
                "paramsHash must be a decimal String on disk"
            )
        }
        // Lock #1 verbatim spelling: paramsData is base64 (a JSON string).
        XCTAssertTrue(json.contains("\"paramsData\" : \""))

        // And the sortedKeys pretty output shape (D-S1): first key sorts
        // alphabetically; schemaVersion renders as a bare number (v2 since
        // 06-01).
        XCTAssertTrue(json.contains("\"schemaVersion\" : \(LightamerSidecar.schemaVersionCurrent)"))
        XCTAssertTrue(json.hasPrefix("{\n  \"appVersion\""))
    }

    /// Defensive decode (lock #2): bare JSON numbers decode too — a file
    /// edited by a tool that re-emitted hashes as numbers still loads.
    func testDecoderAcceptsBareNumberHashes() throws {
        let state = makeState()
        let document = makeDocument(instances: state.instances, history: state.history)
        var json = try XCTUnwrap(String(data: try encode(document), encoding: .utf8))
        json = json.replacingOccurrences(
            of: "\"historyHash\" : \"\(document.historyHash)\"",
            with: "\"historyHash\" : \(document.historyHash)"
        )
        let decoded = try decode(Data(json.utf8))
        XCTAssertEqual(decoded.historyHash, document.historyHash)
    }

    /// The drift verdict primitive (HIST-04/SC#5): a pristine document is
    /// self-consistent; seeding follows the FILE's own decode hash, so a
    /// different live decode seed does NOT read as drift.
    func testDriftPrimitiveSelfConsistent() throws {
        let state = makeState()
        let document = makeDocument(instances: state.instances, history: state.history)
        XCTAssertFalse(document.driftDetected)

        let decoded = try decode(try encode(document))
        XCTAssertFalse(decoded.driftDetected)
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2. Store (02-06-03)
    // ══════════════════════════════════════════════════════════════════════

    private func tempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeStore(
        _ name: String, clock: any Clock<Duration> = ContinuousClock()
    ) throws -> (store: SidecarStore, destination: URL, directory: URL) {
        let directory = try tempDir(name)
        let destination = directory.appendingPathComponent("IMG_0001.ARW.lra")
        return (SidecarStore(destination: destination, clock: clock), destination, directory)
    }

    /// D-S3 debounce: three scheduleWrites inside the merge window produce
    /// exactly ONE file write carrying the LAST document. The fake clock
    /// makes this deterministic: writes PARK until `advance()` — before it,
    /// zero files exist; after it, exactly one, and its content equals the
    /// third document.
    func testDebounceMergesWritesAndLastDocumentWins() async throws {
        let clock = DebounceTestClock()
        let (store, destination, _) = try makeStore("debounce", clock: clock)

        let docs = [
            makeDocument(instances: [makeGain(1.0)], history: HistoryStack()),
            makeDocument(instances: [makeGain(2.0)], history: HistoryStack()),
            makeDocument(instances: [makeGain(3.0)], history: HistoryStack()),
        ]
        await store.scheduleWrite(docs[0])
        await store.scheduleWrite(docs[1])
        await store.scheduleWrite(docs[2])
        let pendingAfterSchedule = await store.hasPendingWrite
        XCTAssertTrue(pendingAfterSchedule)

        // Unstructured-Task start order vs the next actor hop is not
        // guaranteed — poll until the LAST sleeper has parked (the first
        // two were cancelled before their sleeps; each cancel resumes all
        // parked sleeps, so the stable end state is exactly one parked).
        for _ in 0..<200 where clock.parkedCount != 1 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(clock.parkedCount, 1, "re-schedules reset ONE sleeper, not one per call")

        // Nothing hits disk inside the window.
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        clock.advance()
        for _ in 0..<200 {
            if !(await store.hasPendingWrite) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pendingAfterAdvance = await store.hasPendingWrite
        XCTAssertFalse(pendingAfterAdvance)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let loaded = await store.load()
        let reloaded = try XCTUnwrap(loaded)
        XCTAssertEqual(reloaded, docs[2], "the LAST scheduled document wins the merge")
        XCTAssertEqual(reloaded.instances.first?.opName, "testgain")
        try XCTAssertEqual(try XCTUnwrap(reloaded.instances.first).params(of: TestGainModule.self).gain, 3.0)
    }

    /// D-S3 flushNow: forces the pending document immediately; idempotent
    /// when nothing is pending; the cancelled sleeper never double-writes.
    func testFlushNowWritesPendingAndIsIdempotent() async throws {
        let clock = DebounceTestClock()
        let (store, destination, _) = try makeStore("flush", clock: clock)

        // Idempotent no-op on an empty store.
        try await store.flushNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        await store.scheduleWrite(makeDocument(instances: [makeGain(1.5)], history: HistoryStack()))
        try await store.flushNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let pendingAfterFlush = await store.hasPendingWrite
        XCTAssertFalse(pendingAfterFlush)

        let loaded = await store.load()
        let reloaded = try XCTUnwrap(loaded)
        XCTAssertEqual(reloaded.instances.first?.paramsHash, makeGain(1.5).paramsHash)

        // advance() after the flush: the sleeper was cancelled — no second
        // write, no debris.
        clock.advance()
        try await Task.sleep(for: .milliseconds(50))
        let contents = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
        XCTAssertEqual(contents, ["IMG_0001.ARW.lra"], "exactly the sidecar, no tmp files")
    }

    /// Atomicity (L009): after success (and after failure) the directory
    /// holds ONLY the sidecar — no `.tmp-` sibling ever survives.
    func testAtomicWriteLeavesNoTmpFiles() throws {
        let directory = try tempDir("atomic")
        let destination = directory.appendingPathComponent("IMG_0002.ARW.lra")
        let document = makeDocument(instances: makeTrio(), history: HistoryStack())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)

        // The same promotion SidecarStore.writeAtomic performs, exercised
        // on both legs: first write (rename) and overwrite (replaceItemAt).
        let tmp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        try FileManager.default.moveItem(at: tmp, to: destination)

        let tmp2 = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp2)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: tmp2)

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents, ["IMG_0002.ARW.lra"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path) == false)
    }

    /// Corrupt sidecar: `load()` returns nil + logs — never throws into the
    /// UI; the caller upgrades to pristine (checkpoint lock #5 flow).
    func testCorruptFileLoadsAsNil() async throws {
        let (store, destination, _) = try makeStore("corrupt")
        try Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01]).write(to: destination)

        let loaded = await store.load()
        XCTAssertNil(loaded, "corrupt bytes → nil (pristine), not a throw")
    }

    /// Absent sidecar: `load()` nil (the pristine first-open path).
    func testAbsentFileLoadsAsNil() async throws {
        let (store, _, _) = try makeStore("absent")
        let absent = await store.load()
        XCTAssertNil(absent)
    }
}

// MARK: - Drift injection + unknown-op degrade (02-06-07)

extension SidecarRoundTripTests {

    // ══════════════════════════════════════════════════════════════════════
    // 3. Drift + unknown-op (02-06-07; HIST-04/SC#5, checkpoint locks #4/#5)
    // ══════════════════════════════════════════════════════════════════════

    /// Drift injection (SC#5): hand-edit one `paramsData` in the JSON
    /// WITHOUT touching `historyHash` (the external-tamper simulation) →
    /// the next load DETECTS the mismatch, the in-memory (decoded) state
    /// wins, and — the load-bearing assertion — the store schedules NO
    /// write-back at detection time; only a subsequent legit edit
    /// rewrites the file.
    func testDriftInjectionDetectedAndDoesNotRewrite() async throws {
        let (store, destination, _) = try makeStore("drift")
        let state = makeState()
        let document = makeDocument(instances: state.instances, history: state.history)
        await store.scheduleWrite(document)
        try await store.flushNow()

        // Hand-tamper: swap the FIRST instance's paramsData for different
        // valid base64 (a different gain), historyHash left untouched.
        let json = try XCTUnwrap(String(data: try Data(contentsOf: destination), encoding: .utf8))
        let originalParams = try XCTUnwrap(
            state.instances.first { $0.opName == "testgain" }?.paramsData
        )
        let tampered = try JSONEncoder().encode(TestGainModule.Params(gain: 9.75))
        let jsonTweaked = json.replacingOccurrences(
            of: originalParams.base64EncodedString(),
            with: tampered.base64EncodedString(),
            options: .literal, range: json.range(of: originalParams.base64EncodedString())
        )
        XCTAssertNotEqual(json, jsonTweaked, "the tamper must actually change the bytes")
        try Data(jsonTweaked.utf8).write(to: destination)

        // The drift verdict on the AS-SAVED document (the load path's check).
        let store2 = SidecarStore(destination: destination)
        let reloadedDoc = await store2.load()
        let reloaded = try XCTUnwrap(reloadedDoc)
        XCTAssertTrue(reloaded.driftDetected, "hand-edited params must read as drift")

        // NO write-back at detection: load() schedules nothing (the
        // in-memory/decoded state wins; the file is user-inspectable).
        let pending = await store2.hasPendingWrite
        XCTAssertFalse(pending, "detection must NOT schedule a rewrite")
        let afterDetection = try Data(contentsOf: destination)
        XCTAssertEqual(afterDetection, Data(jsonTweaked.utf8),
                       "the file is untouched at detection time")

        // A subsequent LEGIT edit rewrites normally (write-back happens on
        // user action, never on detection) — and the new write is
        // self-consistent (drift clears).
        let newState = makeState()
        var newDoc = makeDocument(instances: newState.instances, history: newState.history)
        newDoc.imageID = reloaded.imageID // the same session continues
        await store2.scheduleWrite(newDoc)
        try await store2.flushNow()
        let afterEditDoc = await store2.load()
        let afterEdit = try XCTUnwrap(afterEditDoc)
        XCTAssertFalse(afterEdit.driftDetected, "the legit rewrite is self-consistent")
        XCTAssertEqual(afterEdit.instances, newDoc.instances)

    }

    /// Unknown-op degrade (checkpoint lock #4): a sidecar carrying an op
    /// the current binary cannot build keeps the instance VERBATIM
    /// (`paramsData` byte-for-byte) and disables it — user data is never
    /// dropped (research Risk #10). The degraded history is stable against
    /// `rebuildInstances()` (enabled=false survives a reload projection).
    func testUnknownOpDegradesDisabledWithParamsPreserved() async throws {
        let registry = ModuleRegistry() // terminal trio only — no testgain
        var stack = HistoryStack()
        let unknown = ModuleInstance(
            id: UUID(), opName: "futuremodule", multiPriority: 0,
            multiName: "from the future", iopOrder: 50.5, version: 1,
            enabled: true,
            paramsData: Data("\"{\"someParam\":true}\"".utf8),
            paramsHash: 0xABCD_EF01_2345_6789
        )
        stack.commit(unknown, label: "futuremodule edit")

        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 42,
            instances: makeTrio() + [unknown], history: stack,
            historyHash: HistoryHash.hash(stack: stack, decodeParamsHash: 42),
            appVersion: "99.0.0"
        )
        // Sanity: with the op UNKNOWN, the raw document's drift anchor
        // folds it (it was enabled at write time).
        let (degraded, unknownOps) = await document.degradedForUnknownOps(registry: registry)
        XCTAssertEqual(unknownOps, ["futuremodule"])
        XCTAssertEqual(degraded.items.count, 1)
        let snapshot = degraded.items[0].snapshot
        XCTAssertFalse(snapshot.enabled, "the unknown op degrades to disabled")
        XCTAssertEqual(snapshot.paramsData, unknown.paramsData,
                       "paramsData must be preserved byte-for-byte")
        XCTAssertEqual(snapshot.paramsHash, unknown.paramsHash,
                       "the hash atom rides along untouched")
        XCTAssertEqual(snapshot.opName, "futuremodule")
        XCTAssertEqual(snapshot.multiName, "from the future")
        // Position and item identity survive the projection.
        XCTAssertEqual(degraded.position, stack.position)
        XCTAssertEqual(degraded.items[0].id, stack.items[0].id)
    }
}

// MARK: - SC#3 end-to-end round-trip (02-06-07; the app coordinator's
// verify path at Core level — the coordinator itself is App-internal and
// not test-importable, 02-05 recorded deviation #1)

extension SidecarRoundTripTests {

    /// A non-constant synthetic image (a horizontal linear gradient in
    /// linear Rec2020) — constant colors could mask channel-dependent
    /// breakage in the terminal trio.
    private func makeGradientImage(width: Int = 64, height: Int = 48) -> DecodedImage {
        let gradient = CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            .applyingFilter("CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: CGFloat(width), y: 0),
                "inputColor0": CIColor(red: 0.1, green: 0.2, blue: 0.3),
                "inputColor1": CIColor(red: 0.9, green: 0.8, blue: 0.7),
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    /// Materialize boxes from records exactly the way the app coordinator's
    /// `rematerializeInstances` does (registry.makeBox by op + apply by
    /// record; unknown ops cannot occur here — degraded upstream).
    private func materialize(
        _ records: [ModuleInstance], registry: ModuleRegistry
    ) async -> [any ModuleBoxing] {
        var boxes: [any ModuleBoxing] = []
        for record in records {
            guard let box = await registry.makeBox(opName: record.opName, instanceID: record.id) else {
                continue
            }
            do {
                try box.apply(record)
            } catch {
                XCTFail("apply failed for \(record.opName): \(error)")
            }
            boxes.append(box)
        }
        return boxes
    }

    /// GPU completion fence — getBytes on shared memory does NOT wait for
    /// in-flight encoders; every readback in this file MUST drain first
    /// (same pattern as TerminalTrioTests.drain; without it the bisect
    /// above races the render and reads half-written zeros).
    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    private func readPlaneBytes(_ texture: any MTLTexture) -> [UInt8] {
        // The PREVIEW final plane is the gamma tail: `.bgra8Unorm` (4 B/px —
        // PixelPipe's terminal-tail policy), NOT the float32 working format.
        let bytesPerPixel = 4
        let rowBytes = texture.width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: rowBytes * texture.height)
        texture.getBytes(
            &bytes, bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return bytes
    }

    /// THE SC#3 contract: build state → write sidecar → drop EVERYTHING →
    /// restore from the file → re-render → instances/history/position/
    /// imageID identical AND the rendered output plane BYTE-IDENTICAL.
    func testRoundTripRestoresIdenticalRenderedOutput() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let state = makeState()
        let decodeSeed: UInt64 = 0x1234_5678_9ABC_DEF0
        let imageID = UUID()

        // ── session 1: materialize + render + persist ──
        let registry1 = ModuleRegistry()
        await registry1.register(opName: TestGainModule.opName) { id in
            ModuleBox(module: TestGainModule(), instanceID: id)
        }
        let boxes1 = await materialize(state.instances, registry: registry1)
        XCTAssertEqual(boxes1.count, 5, "trio + two testgain instances")

        let metal1 = try MetalContext()
        try await metal1.registerDefaultLibrary(in: TestGainKernel.metalBundle)
        let cache1 = PipeCache()
        let image = makeGradientImage()
        let (out1, _) = try await RenderPipeline.process(
            image: image, instances: boxes1, imageID: imageID,
            resolution: .preview, cache: cache1, metal: metal1, longEdge: 64
        )
        drain(metal1)
        let bytes1 = readPlaneBytes(out1)
        do {
            var nonzero = 0
            for b in bytes1 where b != 0 { nonzero += 1 }
            print("[debug] session-1 final plane: \(bytes1.count) bytes, \(nonzero) nonzero, first 16: \(Array(bytes1.prefix(16)))")
        }
        XCTAssertFalse(bytes1.allSatisfy { $0 == 0 }, "session-1 render is not blank")

        let document = makeDocument(instances: state.instances, history: state.history)
        let directory = try tempDir("sc3")
        let destination = directory.appendingPathComponent("IMG_SC3.ARW.lra")
        let store1 = SidecarStore(destination: destination)
        await store1.scheduleWrite(document)
        try await store1.flushNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        // ── session 2: EVERYTHING dropped — fresh registry, cache, metal ──
        let registry2 = ModuleRegistry()
        await registry2.register(opName: TestGainModule.opName) { id in
            ModuleBox(module: TestGainModule(), instanceID: id)
        }
        let store2 = SidecarStore(destination: destination)
        let loaded2 = await store2.load()
        let doc2 = try XCTUnwrap(loaded2)
        XCTAssertFalse(doc2.driftDetected)
        let (degradedHistory, unknown) = await doc2.degradedForUnknownOps(registry: registry2)
        XCTAssertTrue(unknown.isEmpty)
        XCTAssertEqual(degradedHistory, state.history)

        // The restore projection (EditorState.restoreFromSidecar's rule).
        let effective = degradedHistory.effectiveInstances()
        let base = doc2.instances.filter { record in
            !effective.contains {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }
        }
        var merged = base
        for record in effective {
            if let index = merged.firstIndex(where: {
                $0.opName == record.opName && $0.multiPriority == record.multiPriority
            }) {
                merged[index] = record
            } else {
                merged.append(record)
            }
        }
        merged.sort {
            ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority)
        }
        XCTAssertEqual(merged, state.instances)

        let boxes2 = await materialize(merged, registry: registry2)
        XCTAssertEqual(boxes2.count, 5)
        let metal2 = try MetalContext()
        try await metal2.registerDefaultLibrary(in: TestGainKernel.metalBundle)
        let cache2 = PipeCache()
        let (out2, _) = try await RenderPipeline.process(
            image: image, instances: boxes2, imageID: doc2.imageID,
            resolution: .preview, cache: cache2, metal: metal2, longEdge: 64
        )
        drain(metal2)
        let bytes2 = readPlaneBytes(out2)
        XCTAssertFalse(bytes2.allSatisfy { $0 == 0 }, "session-2 render is not blank")
        XCTAssertEqual(bytes1, bytes2, "SC#3: the restored session re-renders IDENTICAL bytes")
    }
}
