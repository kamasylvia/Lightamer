import Accelerate
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// EmbeddingScanner (Plan M2-10-02 KD-4; D-M2-10-CONTEXT-1) — the vDSP BRUTE
// EXACT sweep: fp16 rows → blocked fp32 promotion (vImage) → dot products
// against the query (vDSP_dotpr) → top-N via a k-length min-heap.
//
// RULINGS BAKED IN (not re-openable here):
//   • D-1: NO ANN / sqlite-vec in v1 — the full sweep IS the baseline; the
//     200k-row p95 budget (≤50ms, three-run median) is the escape-hatch
//     sentinel, and the budget test IS that sentinel (over the line = the
//     executor stops and triggers the sqlite-vec discussion, never a
//     silent threshold loosening).
//   • D-8: ZERO normalization code here — both towers L2-normalize INSIDE
//     the exported CoreML graphs (M2-10-01 KD-2), so cosine degenerates to
//     a plain dot product; the scanner divides by nothing.
//
// TWO FACES, ONE CORE:
//   • `topK(rowIDs:contiguousFP16:…)` — the PRODUCTION face. The store's
//     load path packs the whole table into ONE flat fp16 buffer
//     (SemanticStore.loadScanTable), and the sweep reads it ZERO-COPY in
//     256-row blocks (a multi-row vImage_Buffer per block straight over
//     the payload). Per-row Data objects would add measurable per-row
//     overhead at the 200k tier (measured: the blocked flat shape is the
//     one that holds the budget — perf.md methodology note).
//   • `topK(rows:…)` — the KD-4 sketch face ([EmbeddingScanRow]); it
//     compacts into the flat shape and delegates. Small-N / test face.
// ─────────────────────────────────────────────────────────────────────────────

/// One per-row scan payload (the sketch face; the store's row-level load).
public struct EmbeddingScanRow: Sendable {
    public let imageID: Int64
    public let fp16: Data

    public init(imageID: Int64, fp16: Data) {
        self.imageID = imageID
        self.fp16 = fp16
    }
}

/// The typed scan failure face.
public enum EmbeddingScanError: Error, Equatable, Sendable {
    /// A row's BLOB is not `dim*2` bytes (the store's dim column disagrees
    /// with the engine's model row — corrupt/foreign row).
    case rowCorrupt(imageID: Int64, byteCount: Int, expectedBytes: Int)
    /// The query vector's width differs from the scan dimension.
    case dimensionMismatch(rows: Int, query: Int)
    /// The flat payload's byte count is not `rowCount*dim*2`.
    case tableCorrupt(byteCount: Int, expectedBytes: Int)
    /// The vImage half→float conversion failed (internal; carries the code).
    case conversionFailed(code: Int)
}

public enum EmbeddingScanner {

    /// Row count per conversion block (512KB of fp32 scratch — L2-resident
    /// on every Apple-Silicon performance core).
    private static let blockRows = 256

    /// The PRODUCTION face: `contiguousFP16` = rowIDs.count * dim * 2 bytes
    /// of native-endian fp16, row i at offset i*dim. → the top-k (imageID,
    /// score) pairs, score DESCENDING. Score = raw dot product == cosine
    /// (both sides pre-normalized in-graph, D-8). `k` ≤ 0 → empty.
    public static func topK(
        rowIDs: [Int64], contiguousFP16: Data, dim: Int, query: [Float], k: Int
    ) throws -> [(id: Int64, score: Float)] {
        guard k > 0, !rowIDs.isEmpty else { return [] }
        guard query.count == dim else {
            throw EmbeddingScanError.dimensionMismatch(rows: dim, query: query.count)
        }
        let expectedBytes = rowIDs.count * dim * MemoryLayout<Float16>.size
        guard contiguousFP16.count == expectedBytes else {
            throw EmbeddingScanError.tableCorrupt(
                byteCount: contiguousFP16.count, expectedBytes: expectedBytes)
        }
        var heap = MinHeap(capacity: k)
        var fp32Block = [Float](repeating: 0, count: dim * Self.blockRows)
        let rowCount = rowIDs.count
        let fp16RowBytes = dim * MemoryLayout<Float16>.size
        let fp32RowBytes = dim * MemoryLayout<Float>.size

        // The closure body is hoisted into a plain function parameter shape
        // (a nested rethrows closure confused the Debug type checker —
        // "failed to produce diagnostic").
        try contiguousFP16.withUnsafeBytes { (payload: UnsafeRawBufferPointer) in
            let base = payload.baseAddress!
            var index = 0
            try fp32Block.withUnsafeMutableBufferPointer {
                (fp32Buffer: inout UnsafeMutableBufferPointer<Float>) in
                while index < rowCount {
                    let rowsInBlock = min(Self.blockRows, rowCount - index)
                    // ZERO-COPY: the flat payload IS the blocked fp16
                    // layout — the block's vImage_Buffer points straight
                    // into it.
                    let sourcePointer = base + index * fp16RowBytes
                    var source = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: sourcePointer),
                        height: vDSP_Length(rowsInBlock),
                        width: vDSP_Length(dim),
                        rowBytes: fp16RowBytes)
                    var destination = vImage_Buffer(
                        data: fp32Buffer.baseAddress,
                        height: vDSP_Length(rowsInBlock),
                        width: vDSP_Length(dim),
                        rowBytes: fp32RowBytes)
                    let error = vImageConvert_Planar16FtoPlanarF(
                        &source, &destination, vImage_Flags(kvImageNoFlags))
                    guard error == kvImageNoError else {
                        throw EmbeddingScanError.conversionFailed(code: Int(error))
                    }
                    // The exact sweep: one dot per row, straight into the
                    // bounded heap. The non-improving rejection is INLINED
                    // (200k heap-call frames are measurable in Debug hosts).
                    let heapIsFull = heap.isFull
                    let floorScore = heap.minimum
                    for offset in 0..<rowsInBlock {
                        var score: Float = 0
                        vDSP_dotpr(
                            query, 1, fp32Buffer.baseAddress! + offset * dim, 1,
                            &score, vDSP_Length(dim))
                        if heapIsFull, let floorScore, score <= floorScore { continue }
                        heap.maybeInsert(score: score, id: rowIDs[index + offset])
                    }
                    index += rowsInBlock
                }
            }
        }
        return heap.sortedDescending()
    }

    /// The sketch face: per-row BLOBs → compacted flat payload → the
    /// production sweep. Small-N convenience (the store's row-level load).
    public static func topK(
        rows: [EmbeddingScanRow], dim: Int, query: [Float], k: Int
    ) throws -> [(id: Int64, score: Float)] {
        guard k > 0, !rows.isEmpty else { return [] }
        guard query.count == dim else {
            throw EmbeddingScanError.dimensionMismatch(rows: dim, query: query.count)
        }
        let expectedBytes = dim * MemoryLayout<Float16>.size
        var ids: [Int64] = []
        ids.reserveCapacity(rows.count)
        var flat = Data()
        flat.reserveCapacity(rows.count * expectedBytes)
        for row in rows {
            guard row.fp16.count == expectedBytes else {
                throw EmbeddingScanError.rowCorrupt(
                    imageID: row.imageID,
                    byteCount: row.fp16.count,
                    expectedBytes: expectedBytes)
            }
            ids.append(row.imageID)
            flat.append(row.fp16)
        }
        return try topK(
            rowIDs: ids, contiguousFP16: flat, dim: dim, query: query, k: k)
    }

    /// A fixed-capacity min-heap of (score, id) — the partial sort. A full
    /// heap rejects any score ≤ its minimum in O(1) (the 200k-row sweep
    /// pushes O(k log k) times, not O(n log n)).
    struct MinHeap {
        private var entries: [(score: Float, id: Int64)] = []
        private let capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
            entries.reserveCapacity(capacity)
        }

        var minimum: Float? { entries.first?.score }
        var isFull: Bool { entries.count == capacity }

        mutating func maybeInsert(score: Float, id: Int64) {
            if entries.count == capacity, score <= entries[0].score { return }
            if entries.count == capacity {
                entries[0] = (score, id)
                siftDown(from: 0)
            } else {
                entries.append((score, id))
                siftUp(from: entries.count - 1)
            }
        }

        private mutating func siftUp(from index: Int) {
            var child = index
            while child > 0 {
                let parent = (child - 1) / 2
                if entries[child].score < entries[parent].score {
                    entries.swapAt(child, parent)
                    child = parent
                } else { break }
            }
        }

        private mutating func siftDown(from index: Int) {
            var parent = index
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var smallest = parent
                if left < entries.count, entries[left].score < entries[smallest].score {
                    smallest = left
                }
                if right < entries.count, entries[right].score < entries[smallest].score {
                    smallest = right
                }
                if smallest == parent { return }
                entries.swapAt(parent, smallest)
                parent = smallest
            }
        }

        /// Pop everything → score-DESCENDING array (the result contract).
        func sortedDescending() -> [(id: Int64, score: Float)] {
            var sorted = entries
            sorted.sort { $0.score > $1.score }
            return sorted.map { (id: $0.id, score: $0.score) }
        }
    }
}
