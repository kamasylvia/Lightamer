@testable import LightamerCore
import LightamerIOP
import XCTest

// SidecarSeedTopUp (the LUT-page-blank fix, 2026-10-08) — the restore-time
// seed top-up pair math.
//
// Reproduction shape (real documents, fix-batch evidence): a document whose
// persisted base predates lut3d's seed membership (Plan 12-5) — the m31walk
// RAW/DSC00012 v7 sidecar: 37 base records, NO lut3d — restored WITHOUT the
// op, and the LUT tab page rendered zero rows + zero panel. The top-up
// returns the CURRENT seed's identity records for the absent pairs so the
// restored document converges to the pristine face of the same build.
//
// The PipeCoordinator wiring (seed sourcing + the degrade pass ordering) is
// App-level; the pair math here is the Core-testable seam. The end-to-end
// face is covered by the GUI walkthrough (the previously-blank document's
// LUT page renders + import-cancel ×5, fix-batch MANIFEST).
final class SidecarSeedTopUpTests: XCTestCase {

    /// The seed rows for the tests: two real seed-shaped identity records
    /// (the exact constructors `LightamerIOPRegistry.editingDefaultInstances`
    /// uses for these ops — identity/neutral params).
    private var seed: [ModuleInstance] {
        [
            ModuleInstance(module: TemperatureModule.self, params: TemperatureModule.Params()),
            ModuleInstance(module: Lut3dModule.self, params: Lut3dModule.Params()),
        ]
    }

    /// An old-document base slice: temperature present (pre-dates nothing),
    /// lut3d ABSENT (the pre-12-5 snapshot shape — the reproduction set).
    private var oldBase: [ModuleInstance] {
        [
            ModuleInstance(module: TemperatureModule.self, params: TemperatureModule.Params()),
            ModuleInstance(module: ExposureModule.self, params: ExposureModule.Params()),
        ]
    }

    func testMissingOpGainsSeedRecord() {
        // One construction: the identity/paramsHash assertions compare
        // against the SAME array instance the function received (the seed
        // property is computed — a second access would mint fresh UUIDs).
        let seedRows = seed
        let missing = SidecarSeedTopUp.missingSeedInstances(
            persisted: oldBase, effective: [], seed: seedRows)
        // Exactly the lut3d seed row comes back — same identity/params the
        // seed carries (a fresh document's record, not a re-mint of history).
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.opName, Lut3dModule.opName)
        XCTAssertEqual(missing.first?.id, seedRows[1].id)
        XCTAssertEqual(missing.first?.paramsHash, seedRows[1].paramsHash)
        // The merged base then contains the op.
        let merged = oldBase + missing
        XCTAssertTrue(merged.contains { $0.opName == Lut3dModule.opName })
    }

    func testPersistedPairSuppressesTopUp() {
        // A base that already carries lut3d — even DISABLED with drifted
        // params (user state) — must NOT gain a second record.
        var persisted = oldBase
        persisted.append(
            ModuleInstance(
                module: Lut3dModule.self, params: Lut3dModule.Params(), enabled: false))
        let missing = SidecarSeedTopUp.missingSeedInstances(
            persisted: persisted, effective: [], seed: seed)
        XCTAssertTrue(missing.isEmpty)
    }

    func testEffectiveOwnedPairSuppressesTopUp() {
        // The op living ONLY in the restored history's effective set (a
        // history-owned snapshot) is present in the live projection — no
        // top-up for its pair.
        let effective = [ModuleInstance(module: Lut3dModule.self, params: Lut3dModule.Params())]
        let missing = SidecarSeedTopUp.missingSeedInstances(
            persisted: oldBase, effective: effective, seed: seed)
        XCTAssertTrue(missing.isEmpty)
    }

    func testMultiPriorityPairIsDistinct() {
        // Pairs are (opName, multiPriority): a lut3d@1 record does not
        // suppress the seed's lut3d@0 — the pair math stays exact (a doc can
        // only reach this shape through future multi-priority features; the
        // semantics are pinned so the dedupe contract stays load-bearing).
        var persisted = oldBase
        persisted.append(
            ModuleInstance(
                module: Lut3dModule.self, multiPriority: 1,
                params: Lut3dModule.Params()))
        let missing = SidecarSeedTopUp.missingSeedInstances(
            persisted: persisted, effective: [], seed: seed)
        XCTAssertEqual(missing.map(\.multiPriority), [0])
        XCTAssertEqual(missing.map(\.opName), [Lut3dModule.opName])
    }

    func testEmptyPersistedTopsUpEverythingAndStaysDupFree() {
        // persisted = [] (a degenerate document) → the WHOLE seed tops up.
        let seedRows = seed
        let missing = SidecarSeedTopUp.missingSeedInstances(
            persisted: [], effective: [], seed: seedRows)
        XCTAssertEqual(missing.count, seedRows.count)
        // A merged set carries no duplicated (opName, multiPriority) pair:
        // persisted already holding a seed op's pair means that op never
        // appears in `missing`, so persisted ∪ missing is dup-free by
        // construction — pin it on a realistic union (the old base + the
        // one op it lacks).
        let merged = oldBase + SidecarSeedTopUp.missingSeedInstances(
            persisted: oldBase, effective: [], seed: seedRows)
        let pairs = merged.map { Pair($0.opName, $0.multiPriority) }
        XCTAssertEqual(pairs.count, Set(pairs).count)
        XCTAssertTrue(merged.contains { $0.opName == Lut3dModule.opName })
    }

    private struct Pair: Hashable {
        let opName: String
        let multiPriority: Int
        init(_ opName: String, _ multiPriority: Int) {
            self.opName = opName
            self.multiPriority = multiPriority
        }
    }
}
