import CoreGraphics
import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryThumbnailBridge (Plan M2-3-1 T3, KD-4) — the dual-tier thumbnail
// supply for the library grid and the editor filmstrip. ZERO Core changes:
// the two tiers ride ONLY public faces.
//
//   • Tier A (hasEdits != 1): `SessionThumbnailProvider.embeddedPreview(url:)`
//     — the ImageIO embedded preview (10.6ms/张 @86MP measured in M2-2).
//   • Tier B (hasEdits == 1): an injected RENDER LEG at THUMBNAIL resolution
//     (the PipeCoordinator PREVIEW-leg family; the production leg wires the
//     decoder + sidecar materialize when the P2 grid lands — Library rows
//     carry no Session-domain index row, so the leg is a pure `(URL) async
//     throws -> CGImage` seam here, mock-fed by the tests).
//
// CACHES:
//   • disk — `ThumbnailDiskStore(directory:)` under the package's
//     `.<stem>.lathumbs/` (the M2-2-1 constant's directory; the caller picks
//     the directory, the bridge never guesses paths). Key = `String(imageID)`
//     (NOT the user path — space/Unicode-immune). A disk hit must be fresh:
//     the source's mtime may not be older than the thumb's (the has_edits
//     staleness face); a stale thumb regenerates.
//   • memory — an EXPLICIT LRU (deterministic eviction; NSCache's eviction
//     is unobservable and therefore untestable — execution decision D-T3-2).
//
// CONCURRENCY: a global in-flight cap (≤4 by default) enforced by an
// internal gate actor; same-id requests MERGE onto one production (the
// 万行-scroll guarantee: total productions ≤ visible window × constant);
// `prioritize` promotes the visible window's queued productions.
// ─────────────────────────────────────────────────────────────────────────────

/// The global production gate: ≤ `limit` productions run at once; queued
/// productions FIFO, with `prioritize` re-ordering the visible window to the
/// front. A released slot hands DIRECTLY to the first waiter (running count
/// unchanged — the invariant `running ≤ limit` holds by construction).
///
/// LUMEN-B T4: de-privatized to INTERNAL (was `private`) — the cull view's
/// loader reuses the SAME gate shape for its own production cap (the plan's
/// "ThumbnailProductionGate 形复用"; the type's semantics are untouched).
actor ThumbnailProductionGate {
    let limit: Int
    private(set) var running = 0
    private var queue: [(id: Int64, continuation: CheckedContinuation<Void, Never>)] = []

    init(limit: Int) {
        precondition(limit > 0, "the production cap must be positive")
        self.limit = limit
    }

    func acquire(id: Int64) async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            queue.append((id, continuation))
        }
        // The slot was handed over by release() — running already counts it.
    }

    /// Promote the queued productions for these ids to the front of the
    /// queue (preserving their relative order).
    func prioritize(_ ids: Set<Int64>) {
        guard !ids.isEmpty, !queue.isEmpty else { return }
        let promoted = queue.filter { ids.contains($0.id) }
        let rest = queue.filter { !ids.contains($0.id) }
        queue = promoted + rest
    }

    func release() {
        if let next = queue.first {
            queue.removeFirst()
            next.continuation.resume()
        } else {
            running -= 1
        }
    }

    /// The queued (slot-waiting) production count — the test observability
    /// face backing the deterministic prioritize test.
    var pendingCount: Int { queue.count }
}

actor LibraryThumbnailBridge {

    /// The tier-B render leg seam: source file URL → THUMBNAIL-resolution
    /// image. nil = tier B disabled (has_edits rows then miss — the P2 grid
    /// wires the production leg).
    typealias RenderLeg = @Sendable (URL) async throws -> CGImage

    /// The source-URL resolver seam: row → the image file URL (the caller
    /// owns the path-kind spelling — package-relative / volume-relative /
    /// absolute; nil = unresolvable row, the bridge misses it).
    typealias URLResolver = @Sendable (LibraryImageRow) -> URL?

    /// The PRODUCTION resolver shape (M-1′): the host's rebuild face, the
    /// AI entry and the editor resolver all bind THIS one closure —
    /// PathKind decode + the Core three-form resolve over the project
    /// directory, zero path guessing. The Show-in-Finder doors resolve
    /// through the same face, and the SmallPoolUITests three-kind test
    /// drives it directly (the single source stays unit-reachable).
    static func sourceURLResolver(projectDirectory: URL) -> URLResolver {
        { row in
            guard let kind = LibrarySchema.PathKind(rawValue: row.pathKind),
                  case .resolved(let url) = ImageLinker.resolve(
                      imagePath: row.imagePath,
                      pathKind: kind,
                      volumeUUID: row.volumeUUID,
                      projectDirectory: projectDirectory)
            else { return nil }
            return url
        }
    }

    /// M-1′: the read face over the injected resolver — the library-grid
    /// and filmstrip Show-in-Finder doors resolve through the SAME
    /// surface the thumbnails ride (nonisolated: an immutable `let`, no
    /// actor hop on the menu-action path).
    nonisolated var sourceResolver: URLResolver { resolveURL }

    private let disk: ThumbnailDiskStore
    private let renderLeg: RenderLeg?
    private let resolveURL: URLResolver
    private let gate: ThumbnailProductionGate

    /// The explicit memory LRU (capacity in THUMBS, not bytes — deterministic).
    private var memory: MemoryLRU
    private let memoryCapacity: Int

    /// One production per id at a time; merged waiters await the SAME task.
    private var inFlight: [Int64: Task<CGImage?, Never>] = [:]

    /// Completed productions counter (the test observability face: cache
    /// hits and merged requests never bump it).
    private(set) var productionCount = 0

    init(
        thumbsDirectory: URL,
        renderLeg: RenderLeg? = nil,
        resolveURL: @escaping URLResolver,
        maxConcurrency: Int = 4,
        memoryCapacity: Int = 64
    ) {
        self.disk = ThumbnailDiskStore(directory: thumbsDirectory)
        self.renderLeg = renderLeg
        self.resolveURL = resolveURL
        self.gate = ThumbnailProductionGate(limit: maxConcurrency)
        self.memoryCapacity = memoryCapacity
        self.memory = MemoryLRU(capacity: memoryCapacity)
    }

    // MARK: - Request face

    /// The thumbnail for a library row: memory → fresh disk → merge onto the
    /// in-flight production → produce (tier A/B by `hasEdits`).
    func thumbnail(for row: LibraryImageRow) async -> CGImage? {
        if let cached = memory.access(row.id) {
            return cached
        }
        if let fresh = freshDiskImage(for: row) {
            memory.insert(row.id, fresh)
            return fresh
        }
        if let running = inFlight[row.id] {
            return await running.value
        }
        guard let sourceURL = resolveURL(row) else { return nil }

        let disk = self.disk
        let gate = self.gate
        let leg = self.renderLeg
        let id = row.id
        let hasEdits = row.hasEdits == 1
        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            await gate.acquire(id: id)
            defer { Task { await gate.release() } }
            let image: CGImage?
            if hasEdits {
                guard let leg else { return nil }
                image = try? await leg(sourceURL)
            } else {
                // Tier A — the ImageIO embedded preview (nonisolated static).
                image = SessionThumbnailProvider.embeddedPreview(url: sourceURL)
            }
            guard let image else { return nil }
            // Write-through (the disk tier is the authoritative cache).
            try? disk.write(image, relPath: String(id))
            return image
        }
        inFlight[id] = task
        let image = await task.value
        inFlight[id] = nil
        if let image {
            productionCount += 1
            memory.insert(id, image)
        }
        return image
    }

    /// Promote the visible window's queued productions (the scroll-stop /
    /// onAppear signal from the grid / filmstrip).
    func prioritize(_ ids: [Int64]) {
        Task { await self.gate.prioritize(Set(ids)) }
    }

    /// The memory LRU order (front = least recently used) — the test
    /// observability face.
    func memoryOrderForTesting() -> [Int64] {
        memory.orderForTesting
    }

    /// The queued (slot-waiting) production count — the test observability
    /// face backing the deterministic prioritize test.
    func queuedCountForTesting() async -> Int {
        await gate.pendingCount
    }

    /// Teardown face: drop the in-flight registry (running productions
    /// finish into the void — the SessionThumbnailProvider.cancelAll twin
    /// semantics: a render cannot be safely aborted mid-flight).
    func cancelAll() {
        inFlight.removeAll()
    }

    // MARK: - Disk tier (mtime freshness)

    private func freshDiskImage(for row: LibraryImageRow) -> CGImage? {
        let key = String(row.id)
        guard disk.exists(relPath: key), let image = disk.read(relPath: key)
        else { return nil }
        // The staleness face: a source written AFTER the thumb regenerates.
        let thumbURL = disk.fileURL(forRelPath: key)
        let fm = FileManager.default
        guard let sourceURL = resolveURL(row) else { return image }
        let sourceMtime = try? fm.attributesOfItem(
            atPath: sourceURL.path)[.modificationDate] as? Date
        let thumbMtime = try? fm.attributesOfItem(
            atPath: thumbURL.path)[.modificationDate] as? Date
        if let sourceMtime, let thumbMtime, sourceMtime > thumbMtime {
            return nil  // stale — regenerate
        }
        return image
    }
}

/// The deterministic memory LRU (the testability decision — NSCache's
/// eviction is not observable). Capacity counts THUMBS; access refreshes
/// recency; insertion over capacity evicts the least recently used entry.
struct MemoryLRU {
    private var entries: [Int64: CGImage] = [:]
    private var order: [Int64] = []
    private let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var count: Int { entries.count }

    /// The recency order, front = least recently used (the test
    /// observability face; production code never reads it).
    var orderForTesting: [Int64] { order }

    /// The hit path — refreshes recency (a hit that did not refresh would
    /// make this a FIFO, not an LRU).
    mutating func access(_ id: Int64) -> CGImage? {
        guard entries[id] != nil else { return nil }
        touch(id)
        return entries[id]
    }

    mutating func insert(_ id: Int64, _ image: CGImage) {
        if entries[id] != nil {
            entries[id] = image
            touch(id)
            return
        }
        entries[id] = image
        order.append(id)
        evictIfNeeded()
    }

    private mutating func touch(_ id: Int64) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    private mutating func evictIfNeeded() {
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries[evicted] = nil
        }
    }
}
