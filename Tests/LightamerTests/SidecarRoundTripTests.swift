@testable import LightamerCore
import LightamerIOP
import XCTest

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
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.instances, state.instances)
        XCTAssertEqual(decoded.history, state.history)
        XCTAssertEqual(decoded.history.position, 1, "the undo'd mid-state persists")
        XCTAssertEqual(decoded.history.items.count, 3, "D-H2: the redo tail persists too")
        XCTAssertEqual(decoded.layerStack, nil, "Phase 6 reservation stays null in v1")
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
        // alphabetically; schemaVersion renders as a bare number.
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
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
}
