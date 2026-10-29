@testable import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// ProcessForkCacheKeyTests (Plan M9-4 T2, D-M9SP-8 — the H-SP1 hard gate)
// — the cache fold's NEGATIVE TRIO in the PipeHash pure-function domain
// (the fold statements mirror `PixelPipe.prepareChain` verbatim — the
// same `chain(running, hash)` FNV-1a thread — plus the ledger/clamp
// table the bump walks):
//
//   ① the SAME params bytes under the .v1 vs .v3 arms produce DIFFERENT
//     chain hashes (the arms never share a cache plane — the
//     frozen-arm-vs-new-arm cross-pollution the whole fold exists to
//     prevent);
//   ② the .legacy/.v1/.v2 arms fold NOTHING — the chain stays BIT-
//     IDENTICAL to the unfoldable pre-M9-4 shape (every historical
//     cache entry stays a hit, the zero-drift guarantee);
//   ③ the .v3 arm's chain still FLIPS with a params change (the fold
//     does not swallow the parameter dimension) and the fork tag
//     constant is pinned (L013 — StableHash over the literal).
// ─────────────────────────────────────────────────────────────────────────

final class ProcessForkCacheKeyTests: XCTestCase {

    /// The prepareChain fold, verbatim in the pure-function domain:
    /// the chain walks the BOXES — each contributes its paramsHash, and
    /// a fork-reporting box contributes its tag ONCE (per-box, not
    /// per-term).
    private func foldChain(
        seed: UInt64, _ boxes: [(hash: UInt64, fork: UInt64?)]
    ) -> UInt64 {
        var running = seed
        for entry in boxes {
            var h = entry.hash
            running = withUnsafeBytes(of: &h) { StableHash.combine(running, $0) }
            if let f = entry.fork {
                var fv = f
                running = withUnsafeBytes(of: &fv) { StableHash.combine(running, $0) }
            }
        }
        return running
    }

    /// The unfoldable pre-M9-4 chain (the reference shape the trio
    /// compares against).
    private func plainChain(seed: UInt64, _ hashes: [UInt64]) -> UInt64 {
        foldChain(seed: seed, hashes.map { ($0, nil) })
    }

    /// The three-box fixture: upstream / colorWheels / downstream — the
    /// colorWheels slot's fork rides the arm.
    private func fixture(
        seed: UInt64, arm: RenderProcessVersion, box: ColorWheelsModule,
        cwHash: UInt64 = 22
    ) -> UInt64 {
        foldChain(seed: seed, [
            (hash: 11, fork: nil),
            (hash: cwHash, fork: box.processForkHash(arm)),
            (hash: 33, fork: nil),
        ])
    }

    // MARK: - The ledger table (the bump's compile-time half)

    func testLedgerTableAndCurrentBump() {
        XCTAssertEqual(RenderProcess.all, [.v1, .v2, .v3])
        XCTAssertEqual(RenderProcessVersion.current.rawValue, 3)
        XCTAssertEqual(RenderProcess.current, .v3)
        // The clamp table: legacy → oldest; in-range → own; forward →
        // current.
        XCTAssertEqual(RenderProcess.resolving(.legacy), .v1)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 1)!), .v1)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 2)!), .v2)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 3)!), .v3)
        XCTAssertEqual(RenderProcess.resolving(RenderProcessVersion(rawValue: 99)!), .v3)
        // The inverse map is total over the ledger.
        for (index, arm) in RenderProcess.all.enumerated() {
            XCTAssertEqual(arm.processVersion.rawValue, index + 1)
        }
    }

    // MARK: - Negative ①: the arms never share a key

    func testSameParamsV1vsV3ChainsDiverge() {
        let box = ColorWheelsModule()
        let seed = UInt64(0xDEADBEEFCAFEBABE)
        let v1 = fixture(seed: seed, arm: .init(rawValue: 1)!, box: box)
        let v3 = fixture(seed: seed, arm: .init(rawValue: 3)!, box: box)
        XCTAssertNotEqual(v1, v3,
            "the same params bytes on the two arms MUST NOT share a cache plane (H-SP1)")
        // And the divergence comes exactly from the folded fork term —
        // the manual thread (params 11 ⊕ cw-fork ⊕ 33) reproduces it.
        let manual = {
            var running = seed
            for entry in [(hash: UInt64(11), fork: UInt64?.none),
                          (hash: UInt64(22),
                           fork: StableHash.hash(ColorWheelsModule.v3ForkTag)),
                          (hash: UInt64(33), fork: UInt64?.none)] {
                var h = entry.hash
                running = withUnsafeBytes(of: &h) { StableHash.combine(running, $0) }
                if let f = entry.fork {
                    var fv = f
                    running = withUnsafeBytes(of: &fv) { StableHash.combine(running, $0) }
                }
            }
            return running
        }()
        XCTAssertEqual(v3, manual)
    }

    // MARK: - Negative ②: legacy/v1/v2 fold NOTHING (bit-identical)

    func testLegacyV1V2ChainsStayByteIdentical() {
        let box = ColorWheelsModule()
        let seed = UInt64(0x0123456789ABCDEF)
        let plain = plainChain(seed: seed, [11, 22, 33])
        for arm in [RenderProcessVersion.legacy,
                    RenderProcessVersion(rawValue: 1)!,
                    RenderProcessVersion(rawValue: 2)!] {
            XCTAssertEqual(
                fixture(seed: seed, arm: arm, box: box), plain,
                "the \(arm) arm folds NOTHING — every historical cache key stays a hit")
        }
        // The fork tag is nil on all three arms (the discriminated gate).
        XCTAssertNil(box.processForkHash(.legacy))
        XCTAssertNil(box.processForkHash(RenderProcessVersion(rawValue: 1)!))
        XCTAssertNil(box.processForkHash(RenderProcessVersion(rawValue: 2)!))
    }

    // MARK: - Negative ③: the parameter dimension survives the fold

    func testV3ChainStillFlipsWithParams() {
        let box = ColorWheelsModule()
        let seed = UInt64(0xAAAA_BBBB_CCCC_DDDD)
        let a = fixture(seed: seed, arm: .init(rawValue: 3)!, box: box, cwHash: 22)
        let b = fixture(seed: seed, arm: .init(rawValue: 3)!, box: box, cwHash: 99)
        XCTAssertNotEqual(a, b,
            "the fold does not swallow the parameter dimension (SC#2 intact)")
        // The fork tag constant is pinned (L013 — StableHash over the
        // literal; any spelling drift trips this first).
        XCTAssertEqual(
            box.processForkHash(RenderProcessVersion(rawValue: 3)!),
            Self.pinnedV3ForkTagHash,
            "the fork tag's hash is pinned — a StableHash implementation or spelling drift trips this first")
        XCTAssertEqual(
            box.processForkHash(RenderProcessVersion(rawValue: 3)!),
            StableHash.hash("lightamer.colorwheels.v3"))
    }

    /// FNV-1a over the v3 fold tag literal (pinned 2026-10-27, first run —
    /// 0x0C91_FEA1_BACB_7BE4).
    private static let pinnedV3ForkTagHash: UInt64 = 905_990_834_909_371_860
}
