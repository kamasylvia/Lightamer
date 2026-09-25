import CoreGraphics
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailMemoryCache (Plan 09-03 T1) — the browser-thumbnail MEMORY tier.
//
// RESEARCH §5.3: a path→CGImage LRU with a BYTE budget (execution decision:
// 384 MB — the 256–512 MB window's midpoint; at ~0.35 MB per 360px thumbnail
// that is ~1100 resident images, comfortably covering a screenful-heavy
// scroll session without competing with the session plane cache's 3 GB budget —
// the two budgets are INDEPENDENT BY CONTRACT, the browser tier never
// touches the shared session plane cache).
//
// The cache counts bytes EXACTLY as measured by the injected `byteCounter`
// (default: `width × height × 4` — every thumbnail this app produces is
// 8-bit RGBA), so unit tests can assert the eviction SEQUENCE and the
// resident total to the byte (the防空转 red line: no "output exists" test).
//
// Actor isolation: SwiftUI cells fetch from any task; the LRU order array +
// dictionary mutate on the actor only.
// ─────────────────────────────────────────────────────────────────────────────

public actor ThumbnailMemoryCache {

    /// Byte counter for a resident image. The default estimates 4 bytes per
    /// pixel (8-bit RGBA — every thumbnail path in 9-3 produces that form);
    /// tests inject an exact counter for synthetic images.
    public typealias ByteCounter = @Sendable (CGImage) -> Int

    /// The injected byte budget (execution decision: 384 MB, RESEARCH §5.3
    /// window midpoint).
    public static let defaultBudgetBytes = 384 * 1024 * 1024

    /// Oldest-first LRU order (index 0 = least recently used; eviction pops
    /// the front). Insertion and every hit move the path to the tail.
    private var lruOrder: [String] = []

    /// path → (image, exact counted bytes).
    private var entries: [String: (image: CGImage, bytes: Int)] = [:]

    /// Sum of `entries` byte values — maintained incrementally so the
    /// budget check is O(1).
    private(set) var residentBytes = 0

    private let budgetBytes: Int
    private let byteCounter: ByteCounter

    // Hit/miss accounting (tests assert these; also useful diagnostics).
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var evictions = 0

    /// The exact eviction sequence, oldest evicted first (test assertion
    /// face — production code never reads it).
    private(set) var evictionSequence: [(path: String, bytes: Int)] = []

    public init(
        budgetBytes: Int = ThumbnailMemoryCache.defaultBudgetBytes,
        byteCounter: @escaping ByteCounter = { image in
            // 8-bit RGBA estimate: every thumbnail producer in 9-3 renders
            // (or downsamples to) 8-bit RGBA. `bitsPerPixel / 8` keeps the
            // estimate honest for any surprise format.
            let bytesPerPixel = max(1, image.bitsPerPixel / 8)
            return image.width * image.height * bytesPerPixel
        }
    ) {
        self.budgetBytes = max(1, budgetBytes)
        self.byteCounter = byteCounter
    }

    // MARK: - Read

    /// LRU read: a hit refreshes recency; a miss counts and returns nil.
    public func image(for path: String) -> CGImage? {
        guard let entry = entries[path] else {
            misses += 1
            return nil
        }
        hits += 1
        touch(path)
        return entry.image
    }

    /// Whether the path is resident (no recency change, no hit count —
    /// a pure probe for tests/diagnostics).
    public func contains(_ path: String) -> Bool {
        entries[path] != nil
    }

    // MARK: - Write

    /// Insert (or replace) the image for `path`, then evict LRU-oldest
    /// entries until the resident total fits the budget. The freshly
    /// inserted entry sits at the TAIL: it is never its own eviction victim
    /// unless it alone exceeds the budget (in which case the cache would
    /// thrash on every insert — tolerated, same posture as the session plane cache's
    /// oversized-plane note; a thumbnail is ~0.35 MB against a 384 MB
    /// budget, so the case is unreachable in practice).
    public func insert(_ image: CGImage, for path: String) {
        let bytes = byteCounter(image)
        if let existing = entries[path] {
            residentBytes -= existing.bytes
            lruOrder.removeAll { $0 == path }
        }
        entries[path] = (image, bytes)
        residentBytes += bytes
        lruOrder.append(path)
        evictToFit()
    }

    /// Drop one path (row removed / thumb regenerated elsewhere).
    public func remove(_ path: String) {
        guard let existing = entries.removeValue(forKey: path) else { return }
        residentBytes -= existing.bytes
        lruOrder.removeAll { $0 == path }
    }

    /// Teardown leg (session switch ②: "thumb LRU empty"). Resets the
    /// counters along with the content.
    public func removeAll() {
        entries.removeAll()
        lruOrder.removeAll()
        residentBytes = 0
    }

    // MARK: - Introspection (tests / teardown leak assertions)

    /// Resident image count.
    public var count: Int { entries.count }

    /// The LRU order snapshot, oldest-first (test assertion face).
    public var orderSnapshot: [String] { lruOrder }

    // MARK: - Internals

    /// Move `path` to the recency tail.
    private func touch(_ path: String) {
        guard let index = lruOrder.firstIndex(of: path) else { return }
        lruOrder.remove(at: index)
        lruOrder.append(path)
    }

    /// Evict from the LRU FRONT until resident ≤ budget. Pops stop at the
    /// freshly inserted tail entry (see `insert`).
    private func evictToFit() {
        while residentBytes > budgetBytes, lruOrder.count > 1 {
            let victim = lruOrder.removeFirst()
            guard let entry = entries.removeValue(forKey: victim) else { continue }
            residentBytes -= entry.bytes
            evictions += 1
            evictionSequence.append((victim, entry.bytes))
        }
    }
}
