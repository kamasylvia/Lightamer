import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// AutoStackClusteringTests (Plan M6-4-01 T3, KD-4) — the capture-time
// auto-stack face, golden-table + boundary + double-skip + preview/commit:
//
//   golden (3 bursts + scatter, hand-computed) · gap boundary (== joins,
//   over breaks) · sort determinism (scrambled input, capture ties by id)
//   · runs ≥ 2 · the stacked skip (store leg) · the no-capture skip ·
//   preview zero-write (byte-identical package) · commit round-trip ·
//   the empty-pool guard (acceptance N-1, symmetric with stackedIDs).
// ─────────────────────────────────────────────────────────────────────────────

final class AutoStackClusteringTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("auto-stack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("AutoStack.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "AutoStack")
        store = LibraryStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Insert one image row carrying a capture time (the raw seed — the
    /// LibraryQueriesTests fixture shape; capture_date is the clustering's
    /// only data dependency, zero new columns).
    @discardableResult
    private func insertImage(capture: Double?) async throws -> Int64 {
        try await fileStore.withWriteBatch { handle -> Int64 in
            let insert = try handle.prepare(
                "INSERT INTO images (image_path, path_kind, capture_date)"
                    + " VALUES (?, 0, ?)")
            try insert.bindText(1, "Media/\(UUID().uuidString).arw")
            try insert.bindDouble(2, capture)
            _ = try insert.step()
            return handle.lastInsertRowID()
        }
    }

    // MARK: - ① golden table: 3 bursts + scatter

    func testGoldenClustersThreeBurstsAndScatter() async throws {
        // Hand-computed expectation (gap 60): bursts at 10:00:00/10:00:10/
        // 10:00:20 and 11:00:00/11:00:30 cluster; the rest are singletons.
        let t0 = 1_700_000_000.0
        let input: [(id: Int64, capture: Double?)] = [
            (101, t0),               // burst A
            (102, t0 + 10),
            (103, t0 + 20),
            (201, t0 + 3_600),       // burst B
            (202, t0 + 3_630),
            (301, t0 + 7_200),       // scattered singletons
            (302, t0 + 10_800),
            (303, nil),              // never clusters (no capture)
        ]
        let clusters = StackClustering.clusters(input)
        XCTAssertEqual(clusters, [[101, 102, 103], [201, 202]])
    }

    // MARK: - ② gap boundary

    func testGapBoundaryInclusiveOverBreaks() throws {
        let t0 = 1_700_000_000.0
        // Exactly `gap` joins; one microsecond over breaks.
        XCTAssertEqual(
            StackClustering.clusters(
                [(1, t0), (2, t0 + 60)], gap: 60),
            [[1, 2]])
        XCTAssertEqual(
            StackClustering.clusters(
                [(1, t0), (2, t0 + 60.001)], gap: 60),
            [])
        // The boundary rides the ADJACENT delta (a chain of ≤gap steps
        // merges into one cluster even when the ends sit far apart).
        XCTAssertEqual(
            StackClustering.clusters(
                [(1, t0), (2, t0 + 50), (3, t0 + 100)], gap: 60),
            [[1, 2, 3]])
    }

    // MARK: - ③ sort determinism (scrambled input + capture ties)

    func testScrambledInputAndTiesAreDeterministic() throws {
        let t0 = 1_700_000_000.0
        let scrambled: [(id: Int64, capture: Double?)] = [
            (9, t0 + 61), (3, t0), (7, t0), (1, t0 + 122), (5, t0 + 61),
        ]
        let clusters = StackClustering.clusters(scrambled, gap: 60)
        // The walk sorts by (capture, id): 3(t0) 7(t0) 5(+61) 9(+61)
        // 1(+122). The t0→+61 delta is 61 > 60, so the walk emits [3,7]
        // and [5,9]; the singleton 1 never clusters; each cluster
        // ascending by id.
        XCTAssertEqual(clusters, [[3, 7], [5, 9]])
        // Re-running the SAME input (or any permutation) yields the SAME
        // answer — the determinism contract is input-order-free.
        let permuted = scrambled.reversed()
        XCTAssertEqual(
            StackClustering.clusters(Array(permuted), gap: 60), clusters)
    }

    // MARK: - ④ runs ≥ 2

    func testSingletonRunsNeverCluster() throws {
        let t0 = 1_700_000_000.0
        // Four isolated singletons (every neighbor gap > 60).
        let input: [(id: Int64, capture: Double?)] = [
            (1, t0), (2, t0 + 100), (3, t0 + 200), (4, t0 + 300),
        ]
        XCTAssertEqual(StackClustering.clusters(input, gap: 60), [])
    }

    // MARK: - ⑤/⑥ the double skip (stacked + no-capture), store leg

    func testAutoStackSkipsStackedAndCapturelessRows() async throws {
        // Three rows within 10s of each other; one already stacked; one
        // capture-less (never enters the clustering).
        let t0 = 1_700_000_000.0
        let a = try await insertImage(capture: t0)
        let b = try await insertImage(capture: t0 + 5)
        let c = try await insertImage(capture: t0 + 10)
        _ = try await insertImage(capture: nil)
        // `a` joins a pre-existing stack with an out-of-pool member.
        let outside = try await insertImage(capture: t0 + 9_000)
        _ = try await store.createStack(memberIDs: [a, outside])

        let pool = [a, b, c, outside]
        let clusters = try await store.autoStack(ids: pool, preview: true)
        XCTAssertEqual(
            clusters, 1,
            "only [b, c] clusters — the stacked `a` and the captureless row "
                + "drop out (the outside partner also drops: it left the pool's "
                + "clustering with `a`)")
        let created = try await store.autoStack(ids: pool, preview: false)
        XCTAssertEqual(created, 1)
        let containingB = try await store.stackContaining(imageID: b)
        let stack = try XCTUnwrap(containingB)
        XCTAssertEqual(stack.memberIDs, [b, c].sorted())
        let containingA = try await store.stackContaining(imageID: a)
        XCTAssertEqual(
            Set(containingA?.memberIDs ?? []), Set([a, outside]),
            "the already-stacked row kept its OWN stack (it never joined the "
                + "auto-stack cluster)")
        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 2, "the pre-existing stack survived")
    }

    func testCapturelessRowsNeverClusterEvenAlone() async throws {
        let a = try await insertImage(capture: nil)
        let b = try await insertImage(capture: nil)
        let count = try await store.autoStack(ids: [a, b], preview: true)
        XCTAssertEqual(count, 0, "nil captures never cluster")
        let created = try await store.autoStack(ids: [a, b], preview: false)
        XCTAssertEqual(created, 0)
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty)
        // The pure function's own defense: nil captures filtered inside.
        XCTAssertEqual(
            StackClustering.clusters([(a, nil), (b, nil)]),
            [])
    }

    // MARK: - ⑦ preview zero-write (byte-identical package)

    func testPreviewWritesNothingByteIdentical() async throws {
        let t0 = 1_700_000_000.0
        var ids: [Int64] = []
        for index in 0..<4 {
            ids.append(try await insertImage(capture: t0 + Double(index * 5)))
        }
        // A clean close pins the WAL into the main file — the byte baseline.
        try await fileStore.close()
        let before = try Data(contentsOf: packageURL)
        fileStore = try await ProjectFileStore(at: packageURL).open()
        store = LibraryStore(store: fileStore)
        let preview = try await store.autoStack(ids: ids, preview: true)
        XCTAssertEqual(preview, 1, "one cluster is previewed")
        try await fileStore.close()
        let after = try Data(contentsOf: packageURL)
        XCTAssertEqual(
            before, after,
            "preview reported the count and wrote NOTHING — the package file "
                + "is byte-identical across the clean-close boundary")
        // Reopen for the tearDown (the store rides the fresh handle).
        fileStore = try await ProjectFileStore(at: packageURL).open()
        store = LibraryStore(store: fileStore)
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty)
    }

    // MARK: - ⑧ commit round-trip

    func testCommitLandsCollapsedStacksRoundTrip() async throws {
        let t0 = 1_700_000_000.0
        // Burst A (3 rows), burst B (2 rows), one singleton — gap 60.
        var aIDs: [Int64] = []
        for index in 0..<3 {
            aIDs.append(try await insertImage(capture: t0 + Double(index * 10)))
        }
        var bIDs: [Int64] = []
        for index in 0..<2 {
            bIDs.append(try await insertImage(capture: t0 + 3_600 + Double(index * 20)))
        }
        let loner = try await insertImage(capture: t0 + 100_000)

        let pool = aIDs + bIDs + [loner]
        let created = try await store.autoStack(ids: pool, preview: false)
        XCTAssertEqual(created, 2)

        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 2)
        for stack in stacks {
            XCTAssertTrue(stack.collapsed, "auto-stack results land collapsed")
            let members = Set(stack.memberIDs)
            XCTAssertTrue(
                members == Set(aIDs) || members == Set(bIDs),
                "clusters land whole: \(stack.memberIDs)")
            XCTAssertGreaterThanOrEqual(stack.memberIDs.count, 2)
        }
        // Round-trip: every stacked id resolves back through the UNIQUE
        // index; the loner stayed unstacked.
        for id in aIDs + bIDs {
            let containing = try await store.stackContaining(imageID: id)
            XCTAssertNotNil(containing)
        }
        let containingLoner = try await store.stackContaining(imageID: loner)
        XCTAssertNil(containingLoner)
    }

    // MARK: - ⑨ the empty-pool guard (acceptance N-1)

    func testEmptyPoolAnswersZeroWithoutInvalidSQL() async throws {
        // The read leg builds `WHERE id IN (...)` from the pool — an empty
        // pool would spell invalid `IN ()` SQL. The guard (symmetric with
        // stackedIDs below it) short-circuits to zero on both faces.
        let preview = try await store.autoStack(ids: [], preview: true)
        XCTAssertEqual(preview, 0, "an empty pool previews nothing")
        let created = try await store.autoStack(ids: [], preview: false)
        XCTAssertEqual(created, 0, "an empty pool creates nothing")
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty, "no half-landed stack")
    }
}
