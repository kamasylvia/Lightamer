import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ColorMatchSolveCache (Plan M5-1-01 T3, KD-3) — the runtime solve cache,
// FilmSolveCache 同构: NSLock + insertion-order LRU 8 + invalidateAll().
//
// KEY (the pinned fold — FilmRuntimeSolve.cacheKey 体例, little-endian byte
// order over the FNV-1a chain):
//     fnv(sourceStatsHash ⊕ referenceStatsHash ⊕ solverTag)
// with the two UInt64 terms folded as their raw little-endian bytes and the
// tag as UTF-8, all chained over the FNV offset basis. The exact key VALUE
// for a canonical (0, 0, gaussianOT) triple is pinned in DECISIONS + G1
// (the FilmSolveCache fold-order-pin precedent). The solve is a pure
// function of the key's terms, so cache hits are value-invisible by
// construction (G1's cache-transparency assertion).
// ─────────────────────────────────────────────────────────────────────────────

public final class ColorMatchSolveCache: @unchecked Sendable {

    private let lock = NSLock()
    private var solutions: [UInt64: ColorMatchSolution] = [:]
    private var order: [UInt64] = []
    private let capacity: Int

    public init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// The canonical key fold (source ⊕ reference ⊕ tag, little-endian bytes
    /// in that order over the FNV-1a chain).
    public static func cacheKey(
        sourceStatsHash: UInt64, referenceStatsHash: UInt64, solver: ColorMatchSolverKind
    ) -> UInt64 {
        var h = StableHash.fnvOffsetBasis
        withUnsafeBytes(of: sourceStatsHash) { h = StableHash.combine(h, $0) }
        withUnsafeBytes(of: referenceStatsHash) { h = StableHash.combine(h, $0) }
        let tag = Array(solver.cacheTag.utf8)
        return tag.withUnsafeBufferPointer {
            StableHash.combine(h, UnsafeRawBufferPointer($0))
        }
    }

    public func solution(for key: UInt64) -> ColorMatchSolution? {
        lock.lock()
        defer { lock.unlock() }
        guard let hit = solutions[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    public func store(_ solution: ColorMatchSolution, for key: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        solutions[key] = solution
        order.append(key)
        while order.count > capacity {
            solutions.removeValue(forKey: order.removeFirst())
        }
    }

    /// Test observability (the FilmSolveCache face).
    public var countForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return solutions.count
    }

    /// The invalidation face (value-invisible by construction — the face
    /// exists so a future reference-set change lands in one place).
    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        solutions.removeAll()
        order.removeAll()
    }

    /// The process-wide cache (one per session — the solve is a pure
    /// function of the key, so sharing across consumers is value-invisible).
    public static let shared = ColorMatchSolveCache()
}
