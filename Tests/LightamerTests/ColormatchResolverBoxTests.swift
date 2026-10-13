import Foundation
import XCTest

@testable import LightamerCore
@testable import LightamerIOP

// ─────────────────────────────────────────────────────────────────────────────
// Plan M6-1-01 T8 (KD-6, OQ-6 搭车): the ColormatchResolverBox NSLock holder
// — the LutLibraryStore shared-holder 体例镜像. The getter/replaceShared
// semantics, the forward's lock-scoped read (value into a local, no second
// read outside the lock) and the nil-degrade contract (the box is
// session-scoped state shared by the whole process — tests must restore the
// prior face).
// ─────────────────────────────────────────────────────────────────────────────

final class ColormatchResolverBoxTests: XCTestCase {

    /// The in-memory resolver (the ColormatchModuleTests MemoryResolver
    /// shape + a load-call recorder for the forward routing assertion).
    private final class RecordingResolver: ColormatchAssetResolving, @unchecked Sendable {
        let tag: String
        var solution: ColorMatchCDFSolution?
        init(tag: String, solution: ColorMatchCDFSolution? = nil) {
            self.tag = tag
            self.solution = solution
        }
        func loadCube(
            assetRef: String, expectedHash: String?
        ) -> ColormatchCubeAsset.LoadResult {
            .loaded(table: [SIMD3(Float(tag.count), 0, 0)], bytesHash: 1)
        }
        func cdfSolution(
            sourceStatsHash: String, referenceStatsHash: String
        ) -> ColorMatchCDFSolution? {
            solution
        }
    }

    override func setUp() {
        super.setUp()
        ColormatchResolverBox.replaceShared(nil)
    }

    override func tearDown() {
        ColormatchResolverBox.replaceShared(nil)
        super.tearDown()
    }

    /// The getter returns the installed instance (identity).
    func testGetterReturnsInstalledResolver() {
        let resolver = RecordingResolver(tag: "one")
        XCTAssertNil(ColormatchResolverBox.shared)
        ColormatchResolverBox.replaceShared(resolver)
        XCTAssertEqual(
            ColormatchResolverBox.shared.map { ObjectIdentifier($0 as AnyObject) },
            ObjectIdentifier(resolver),
            "the getter answers the installed instance")
    }

    /// replaceShared swaps atomically — including back to nil (the
    /// session-teardown leg).
    func testReplaceSharedSwapsAndClears() {
        let first = RecordingResolver(tag: "first")
        let second = RecordingResolver(tag: "second")
        ColormatchResolverBox.replaceShared(first)
        ColormatchResolverBox.replaceShared(second)
        XCTAssertEqual(
            ColormatchResolverBox.shared.map { ObjectIdentifier($0 as AnyObject) },
            ObjectIdentifier(second))
        ColormatchResolverBox.replaceShared(nil)
        XCTAssertNil(ColormatchResolverBox.shared, "nil clears the box")
    }

    /// The forward's nil degrade contract: no installed resolver → the
    /// typed degrade reason (the arm blits), cdfSolution nil.
    func testForwardDegradesWhenNil() {
        let forward = ColormatchSharedResolverForward()
        guard case .degraded(let reason) = forward.loadCube(
            assetRef: "x.cube", expectedHash: nil)
        else {
            return XCTFail("the nil box must degrade the LUT arm")
        }
        XCTAssertEqual(reason, "colormatch resolver not installed")
        XCTAssertNil(
            forward.cdfSolution(sourceStatsHash: "a", referenceStatsHash: "b"))
    }

    /// The forward reads THROUGH to the LIVE instance — a swap between
    /// calls re-routes (the long-lived-box contract), with the second read
    /// landing in a lock-scoped local.
    func testForwardRoutesToTheLiveInstance() {
        let forward = ColormatchSharedResolverForward()
        let first = RecordingResolver(tag: "first")
        ColormatchResolverBox.replaceShared(first)
        guard case .loaded(let table1, _) = forward.loadCube(
            assetRef: "x.cube", expectedHash: nil)
        else {
            return XCTFail("the installed resolver answers")
        }
        XCTAssertEqual(table1.first?.x, 5, "first.tag.count = 5")
        let second = RecordingResolver(tag: "second-resolver")
        ColormatchResolverBox.replaceShared(second)
        guard case .loaded(let table2, _) = forward.loadCube(
            assetRef: "x.cube", expectedHash: nil)
        else {
            return XCTFail("the swapped resolver answers")
        }
        XCTAssertEqual(
            table2.first?.x, Float("second-resolver".count),
            "the forward routes to the LIVE instance after the swap")
    }
}
