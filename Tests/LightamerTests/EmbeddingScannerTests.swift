import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// EmbeddingScannerTests (Plan M2-10-02 T3, KD-4) — the vDSP brute sweep:
//
//   • hand-computed 4×3 anchor (orthogonal / same / opposite / diagonal) —
//     the expected dot products asserted PER POSITION
//   • the fp16 representation band: self-query ≈ 1 within 1e-3 (per-row
//     round-trip), no score escapes |s| ≤ 1 + 2e-3
//   • top-N ordering: the heap result == a naive Swift reference over the
//     SAME rows (both membership and order), strictly descending
//   • THE BUDGET SENTINEL (D-1): 200k rows × 512 dims, p95 shape — the
//     three-run MEDIAN must stay ≤ 50ms (over the line = the D-1 escape
//     hatch discussion fires, never a silent loosening). 10k/100k tiers
//     record into perf.md (no hard assertion — the baseline ledger).
// ─────────────────────────────────────────────────────────────────────────────

final class EmbeddingScannerTests: XCTestCase {

    private func packRow(_ id: Int64, _ vector: [Float]) -> EmbeddingScanRow {
        EmbeddingScanRow(imageID: id, fp16: FP16Coding.pack(vector))
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = Float(sqrt(vector.reduce(0.0) { $0 + Double($1 * $1) }))
        return vector.map { $0 / norm }
    }

    // MARK: - Hand-computed anchors (KD-4's correctness pin)

    func testHandComputedAnchorVectors() throws {
        let query: [Float] = [1, 0, 0]
        // Same direction = 1; orthogonal = 0; opposite = −1; the 45°
        // diagonal = √2/2. fp16 keeps all of these EXACT (powers of two /
        // representable halves).
        let rows = [
            packRow(1, [1, 0, 0]),                       // cos = 1
            packRow(2, [0, 1, 0]),                       // cos = 0
            packRow(3, [-1, 0, 0]),                      // cos = −1
            packRow(4, [0.707_106_78, 0.707_106_78, 0]),  // cos = √2/2
        ]
        let hits = try EmbeddingScanner.topK(rows: rows, dim: 3, query: query, k: 4)
        XCTAssertEqual(hits.map(\.id), [1, 4, 2, 3], "score-descending order")
        XCTAssertEqual(hits[0].score, 1.0, accuracy: 1e-6)
        // The diagonal rides its fp16 ulp (≈4.9e-4) — the plan's 1e-3 band.
        XCTAssertEqual(hits[1].score, Float(0.707_106_78), accuracy: 1e-3)
        XCTAssertEqual(hits[2].score, 0.0, accuracy: 1e-6)
        XCTAssertEqual(hits[3].score, -1.0, accuracy: 1e-6)
        // The partial sort: k = 2 keeps only the head.
        let top2 = try EmbeddingScanner.topK(rows: rows, dim: 3, query: query, k: 2)
        XCTAssertEqual(top2.map(\.id), [1, 4])
        // k = 0 / empty rows are empty results, not errors.
        XCTAssertTrue(try EmbeddingScanner.topK(rows: rows, dim: 3, query: query, k: 0).isEmpty)
        XCTAssertTrue(try EmbeddingScanner.topK(rows: [], dim: 3, query: query, k: 4).isEmpty)
    }

    func testDimensionMismatchIsTyped() throws {
        let rows = [packRow(1, [1, 0, 0])]
        XCTAssertThrowsError(
            try EmbeddingScanner.topK(rows: rows, dim: 3, query: [1, 0], k: 1)
        ) { error in
            XCTAssertEqual(
                error as? EmbeddingScanError, .dimensionMismatch(rows: 3, query: 2))
        }
    }

    func testCorruptRowByteCountIsTyped() throws {
        let rows = [EmbeddingScanRow(imageID: 7, fp16: Data([0x00, 0x3c, 0x00]))]
        XCTAssertThrowsError(
            try EmbeddingScanner.topK(rows: rows, dim: 2, query: [1, 0], k: 1)
        ) { error in
            XCTAssertEqual(
                error as? EmbeddingScanError,
                .rowCorrupt(imageID: 7, byteCount: 3, expectedBytes: 4))
        }
    }

    // MARK: - fp16 band

    func testFP16RoundTripBandOnUnitVectors() throws {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 33) / Float(UInt32.max)
        }
        let dim = 64
        let count = 256
        var query: [Float] = []
        var rows: [EmbeddingScanRow] = []
        for index in 0..<count {
            var vector = (0..<dim).map { _ in next() - 0.5 }
            vector = normalize(vector)
            if index == 0 { query = vector }
            rows.append(packRow(Int64(index + 1), vector))
        }
        // The first row IS the query: its fp16 round-trip keeps the
        // self-cosine at 1 within the representation band.
        let hits = try EmbeddingScanner.topK(rows: rows, dim: dim, query: query, k: count)
        XCTAssertEqual(hits.first?.id, 1)
        XCTAssertEqual(hits.first!.score, 1.0, accuracy: 1e-3)
        // No score escapes the unit sphere (fp16 slack ≈ 2e-3).
        for hit in hits {
            XCTAssertLessThanOrEqual(hit.score, 1.0 + 2e-3)
            XCTAssertGreaterThanOrEqual(hit.score, -1.0 - 2e-3)
        }
    }

    // MARK: - Top-N ordering against a naive reference

    func testTopNMatchesNaiveReferenceOrdering() throws {
        var state: UInt64 = 0xDEADBEEFCAFEF00D
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 33) / Float(UInt32.max)
        }
        let dim = 32
        let count = 500
        let query = normalize((0..<dim).map { _ in next() - 0.5 })
        var rows: [EmbeddingScanRow] = []
        var decoded: [(id: Int64, vector: [Float])] = []
        for index in 0..<count {
            let vector = normalize((0..<dim).map { _ in next() - 0.5 })
            decoded.append((id: Int64(index + 1), vector: vector))
            rows.append(packRow(Int64(index + 1), vector))
        }
        let hits = try EmbeddingScanner.topK(rows: rows, dim: dim, query: query, k: 25)
        // The naive reference (fp32, exact): sort desc, take 25 — the ids
        // and scores must agree (fp16 rounding can TIE close scores; the
        // reference ties break identically because both see the same fp32
        // promotion — assert on score bands instead of exact ids when the
        // gap is sub-fp16-ulp, i.e. compare against reference score order).
        let reference = decoded.map { row -> (id: Int64, score: Float) in
            var dot: Float = 0
            for index in 0..<dim { dot += query[index] * row.vector[index] }
            return (row.id, dot)
        }
        .sorted { $0.score > $1.score }
        .prefix(25)
        for (hit, expect) in zip(hits, reference) {
            XCTAssertEqual(hit.id, expect.id)
            XCTAssertEqual(hit.score, expect.score, accuracy: 1e-3)
        }
        // Strictly non-increasing.
        for index in 1..<hits.count {
            XCTAssertGreaterThanOrEqual(hits[index - 1].score, hits[index].score)
        }
    }

    // MARK: - The budget sentinel (D-1) + the perf.md tiers

    /// 64 distinct normalized vectors cycled across the row population —
    /// the sweep is data-INDEPENDENT (fixed FLOP count per row), so the
    /// cycle keeps generation trivial without touching the measurement
    /// (documented in perf.md's methodology note).
    private func makeSyntheticRows(count: Int, dim: Int) -> [EmbeddingScanRow] {
        let distinct = 64
        var vectors: [[Float]] = []
        var state: UInt64 = 0x1234567890ABCDEF
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 33) / Float(UInt32.max)
        }
        for _ in 0..<distinct {
            vectors.append(normalize((0..<dim).map { _ in next() - 0.5 }))
        }
        var rows: [EmbeddingScanRow] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            rows.append(packRow(Int64(index + 1), vectors[index % distinct]))
        }
        return rows
    }

    /// The CONTIGUOUS table shape (the production load: one flat fp16
    /// payload + parallel ids — the scanner's zero-copy face). The 64-vector
    /// cycle is packed ONCE and block-repeated (memcpy), so generation stays
    /// trivial in Debug hosts; the sweep itself is data-INDEPENDENT
    /// (documented in perf.md's methodology note).
    private func makeSyntheticTable(
        count: Int, dim: Int
    ) -> (rowIDs: [Int64], fp16: Data) {
        let cycleRows = 64
        var vectors: [[Float]] = []
        var state: UInt64 = 0x1234567890ABCDEF
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 33) / Float(UInt32.max)
        }
        for _ in 0..<cycleRows {
            vectors.append(normalize((0..<dim).map { _ in next() - 0.5 }))
        }
        var cycleIDs: [Int64] = []
        var cycle = Data()
        for index in 0..<cycleRows {
            cycleIDs.append(Int64(index + 1))
            cycle.append(FP16Coding.pack(vectors[index]))
        }
        var ids: [Int64] = []
        ids.reserveCapacity(count)
        var flat = Data()
        flat.reserveCapacity(count / cycleRows * cycle.count)
        var written = 0
        while written < count {
            let chunk = min(cycleRows, count - written)
            ids.append(contentsOf: cycleIDs[0..<chunk])
            flat.append(cycle.subdata(in: 0..<chunk * dim * 2))
            written += chunk
        }
        return (ids, flat)
    }

    private func timeScan(
        rows: [EmbeddingScanRow], dim: Int, query: [Float], runs: Int
    ) -> [Double] {
        var timings: [Double] = []
        for _ in 0..<runs {
            let start = DispatchTime.now()
            _ = try? EmbeddingScanner.topK(rows: rows, dim: dim, query: query, k: 256)
            let end = DispatchTime.now()
            timings.append(
                Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        }
        return timings
    }

    private func timeScanTable(
        table: (rowIDs: [Int64], fp16: Data), dim: Int, query: [Float], runs: Int
    ) -> [Double] {
        var timings: [Double] = []
        for _ in 0..<runs {
            let start = DispatchTime.now()
            _ = try? EmbeddingScanner.topK(
                rowIDs: table.rowIDs, contiguousFP16: table.fp16, dim: dim,
                query: query, k: 256)
            let end = DispatchTime.now()
            timings.append(
                Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        }
        return timings
    }

    func testContiguousTableShapeMismatchIsTyped() throws {
        let table = makeSyntheticTable(count: 10, dim: 4)
        XCTAssertThrowsError(
            try EmbeddingScanner.topK(
                rowIDs: table.rowIDs, contiguousFP16: table.fp16.prefix(39),
                dim: 4, query: [1, 0, 0, 0], k: 2)
        ) { error in
            XCTAssertEqual(
                error as? EmbeddingScanError,
                .tableCorrupt(byteCount: 39, expectedBytes: 80))
        }
    }

    /// AC #4's hard budget: 200k × 512, three runs, MEDIAN ≤ 50ms — over
    /// the CONTIGUOUS production face (the store's loadScanTable output).
    /// Over the line on three hosts = the D-1 escape-hatch discussion
    /// (sqlite-vec), NOT a loosened threshold.
    func testScanBudget200KRowsWithinP50Of50ms() throws {
        let dim = 512
        let count = 200_000
        let table = makeSyntheticTable(count: count, dim: dim)
        let query = normalize((0..<dim).map { Foundation.sin(Float($0) * 0.01) })
        // One warmup (page in the payload + first-touch the buffers).
        _ = try EmbeddingScanner.topK(
            rowIDs: table.rowIDs, contiguousFP16: table.fp16, dim: dim,
            query: query, k: 256)
        let timings = timeScanTable(table: table, dim: dim, query: query, runs: 3)
        let median = timings.sorted()[1]
        print("PERF|scan|shape=contiguous|rows=200000|dim=512|runs=[\(timings.map { String(format: "%.2f", $0) }.joined(separator: ","))]ms|median=\(String(format: "%.2f", median))ms")
        XCTAssertLessThanOrEqual(
            median, 50.0,
            "D-1 escape-hatch sentinel tripped (200k×512 median \(median)ms > 50ms) — stop and discuss sqlite-vec, do NOT loosen this threshold")
    }

    /// The perf.md ledger tiers (1万 / 10万 — recorded, not asserted), plus
    /// a per-row-face reference run at the 10k tier (the sketch face's
    /// documented per-row overhead).
    func testScanTierMeasurementsForPerfLedger() throws {
        let dim = 512
        for count in [10_000, 100_000] {
            let table = makeSyntheticTable(count: count, dim: dim)
            let query = normalize((0..<dim).map { Foundation.sin(Float($0) * 0.01) })
            _ = try EmbeddingScanner.topK(
                rowIDs: table.rowIDs, contiguousFP16: table.fp16, dim: dim,
                query: query, k: 256)
            let timings = timeScanTable(table: table, dim: dim, query: query, runs: 3)
            let median = timings.sorted()[1]
            print("PERF|scan|shape=contiguous|rows=\(count)|dim=512|runs=[\(timings.map { String(format: "%.2f", $0) }.joined(separator: ","))]ms|median=\(String(format: "%.2f", median))ms")
        }
        // The per-row sketch face at 10k (reference only — not asserted).
        let rows = makeSyntheticRows(count: 10_000, dim: dim)
        let query = normalize((0..<dim).map { Foundation.sin(Float($0) * 0.01) })
        _ = try EmbeddingScanner.topK(rows: rows, dim: dim, query: query, k: 256)
        let rowTimings = timeScan(rows: rows, dim: dim, query: query, runs: 3)
        print("PERF|scan|shape=per-row|rows=10000|dim=512|runs=[\(rowTimings.map { String(format: "%.2f", $0) }.joined(separator: ","))]ms|median=\(String(format: "%.2f", rowTimings.sorted()[1]))ms")
    }
}
