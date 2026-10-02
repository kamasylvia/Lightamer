import CoreGraphics
import Foundation
import LightamerCore
@testable import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// ExportDrtChainTests (Plan M2-9-02 T2, KD-2 — EXPORT bundle) — the
// `exportDrtChain` pure function:
//
//   1. VERBATIM records: the DRT chain pre-edits NOTHING (the gamma/
//      colorout demotion is the PIPE's `.drt` policy — one demotion
//      semantic, no builder drift). Contrast: the legacy face strips gamma.
//   2. The override IS the KD-1 mapping (same cached instance) — the exit
//      leg's identity source/target and the embedded ICC.
//   3. The identity + dummy faces: coloroutOverridden == true (the exit
//      leg keys on it), target == the E7 dummy `.sRGB`, drtEncoding ==
//      the record's pair.
//   4. The typed refusal propagates for outside-the-linkage pairs.
//   5. The legacy Built carries drtEncoding == nil (the carrier default —
//      `exportChain`'s body byte-frozen, its call site untouched).
// ─────────────────────────────────────────────────────────────────────────────

final class ExportDrtChainTests: XCTestCase {

    /// A representative record list: base trio + editing defaults (the
    /// coordinator's live-set face, gamma/colorout/yiyin carriers included).
    private func makeRecords() async throws -> [ModuleInstance] {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let trio = await registry.makeDefaultInstances()
        return (trio + LightamerIOPRegistry.editingDefaultInstances())
            .sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    func testDrtChainCarriesRecordsVerbatim() async throws {
        let records = try await makeRecords()
        let built = try ExportChainBuilder.exportDrtChain(
            from: records, space: .rec709, eotf: .gamma22)
        XCTAssertEqual(
            built.instances.map(\.id), records.map(\.id),
            "the DRT chain pre-edits NOTHING — the pipe demotes in-pipe")
        XCTAssertEqual(built.instances.count, records.count)
        // Contrast (the legacy face strips gamma — the one-record diff):
        let legacy = try ExportChainBuilder.exportChain(
            from: records, target: .sRGB, linearVariant: false)
        XCTAssertEqual(legacy.instances.count, records.count - 1)
        XCTAssertFalse(
            legacy.instances.contains { $0.opName == GammaModule.opName },
            "the legacy chain strips gamma (the OQ-11-2 face, unchanged)")
        XCTAssertTrue(
            built.instances.contains { $0.opName == GammaModule.opName },
            "the DRT chain keeps gamma verbatim (the pipe demotes it)")
    }

    func testDrtChainOverrideIsTheKD1Mapping() async throws {
        let records = try await makeRecords()
        let built = try ExportChainBuilder.exportDrtChain(
            from: records, space: .p3d65, eotf: .st2084)
        let expected = try DrtOutputColorSpace.drtOutputColorSpace(
            space: .p3d65, eotf: .st2084)
        XCTAssertTrue(
            built.exportTargetOverride === expected,
            "the override is the KD-1 resolver's cached instance (the exit "
                + "leg's identity keys on instance identity)")
    }

    func testDrtChainIdentityAndDummyFaces() async throws {
        let records = try await makeRecords()
        let built = try ExportChainBuilder.exportDrtChain(
            from: records, space: .rec2020, eotf: .hlg)
        XCTAssertTrue(
            built.coloroutOverridden,
            "the exit leg's identity semantics ride the legacy flag")
        XCTAssertEqual(
            built.target, .sRGB,
            "the E7 dummy: ExportColorSpace never gains DRT arms — the real "
                + "encoding lives in drtEncoding")
        let pair = try XCTUnwrap(built.drtEncoding, "the DRT carrier is set")
        XCTAssertEqual(pair.space, .rec2020)
        XCTAssertEqual(pair.eotf, .hlg)
    }

    func testDrtChainTypedRefusalPropagates() async {
        let records = try? await makeRecords()
        let source = records ?? []
        // linear is persistable but outside every legal set — the mapping
        // (and therefore the builder) refuses it typed.
        do {
            _ = try ExportChainBuilder.exportDrtChain(
                from: source, space: .rec709, eotf: .linear)
            XCTFail("rec709+linear is outside the linkage table")
        } catch let error as AppError {
            guard case .invalidParameter = error else {
                return XCTFail("expected .invalidParameter, got \(error)")
            }
        } catch {
            XCTFail("expected a typed AppError, got \(error)")
        }
    }

    func testLegacyBuiltHasNilDrtEncoding() async throws {
        let records = try await makeRecords()
        let legacy = try ExportChainBuilder.exportChain(
            from: records, target: .displayP3, linearVariant: false)
        XCTAssertNil(
            legacy.drtEncoding,
            "the legacy face carries no DRT carrier (the defaulted memberwise "
                + "slot — exportChain's body byte-frozen)")
        XCTAssertEqual(legacy.target, .displayP3, "the legacy target is REAL")
    }
}
