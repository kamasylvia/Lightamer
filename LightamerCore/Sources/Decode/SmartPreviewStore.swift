import Compression
import CryptoKit
import Foundation
import SQLite3

// ─────────────────────────────────────────────────────────────────────────────
// SmartPreviewStore (Plan LUMEN-B T1, X6) — the decoded-preview pack format
// behind the smart-preview cache (LU4). The store is a DECODE-EXIT wrapper
// layer over `RAWDecoder.decode` (the wrapper consumes decode through an
// injected closure — RAWDecoder itself keeps a ZERO-diff signature).
//
// ATTRIBUTION (MIT): the FORMAT SHAPE — the LPV1 magic + header-length +
// JSON-header + float16 plane + byte-plane split + zlib envelope — is
// derived from LUMEN RAW's `preview_cache.py` (Copyright (c) LUMEN RAW
// contributors, MIT license; the root NOTICE carries the entry). This is an
// independent Swift reimplementation for our own container (no code copied);
// the format is not algorithm surface, so the note rides this file header
// (the plan T1 note-level attribution; T3 re-checks the NOTICE coverage).
//
// FORMAT (T1, the plan's "LPV1 形我方拼写"):
//   magic "LAPV1" | UInt32 LE header length | JSON header | zlib(deflate) planes
//   header JSON = { width, height, version, meta: [String: String] }
//   planes      = the float16-quantized RGBA samples split into TWO byte
//                 planes (all low bytes, then all high bytes) — the
//                 rearrangement lifts zlib's ratio on smooth image data
//                 (the Lumen transliteration motive; the smoke test pins it).
//
// QUANTIZATION CONSISTENCY (H-LU3 arm 1, the T1 red line): `quantize` is a
// PUBLIC function and every FRESH decode passes through the same float16
// round-trip before it is cached or served — so a cache hit and a fresh
// decode produce BIT-IDENTICAL planes ("缓存不改变观感" made structural).
// The round-trip golden test pins bit-identity + the <0.05% relative error.
//
// COMPRESSION: zlib level 1 is the Lumen calibration (speed-first; the
// plan red line bans higher levels). Apple's Compression framework exposes
// no level knob — its COMPRESSION_ZLIB is a speed-oriented deflate, which
// is the structural equivalent of the "level 1" intent (declared in
// LUMEN-B DECISIONS).
// ─────────────────────────────────────────────────────────────────────────────

/// The decoded working plane the cache stores: working-space LINEAR float32
/// RGBA, row-major, premultiplied-alpha (the pipeline's plane discipline —
/// the readback composes straight into the RGBA face).
public struct SmartPreviewPlane: Sendable, Equatable {

    public let width: Int
    public let height: Int
    /// Row-major RGBA, `count == width * height * 4`.
    public let rgba: [Float]

    public init(width: Int, height: Int, rgba: [Float]) {
        precondition(width > 0 && height > 0, "plane dimensions must be positive")
        precondition(
            rgba.count == width * height * 4,
            "rgba count \(rgba.count) != \(width)*\(height)*4")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    public var sampleCount: Int { width * height * 4 }
}

/// The typed pack/unpack failures (malformed input NEVER crashes — the
/// plan's typed-failure face; the store treats every error as a cache miss).
public enum SmartPreviewFormatError: Error, Equatable, Sendable {
    case badMagic
    case truncatedEnvelope
    case headerTooLarge
    case badHeader
    case truncatedPlanes
}

/// The LPV1-shaped pack format ("LAPV1" spelling). Pure value semantics —
/// no I/O, no clock, fully deterministic (the golden tests ride this).
public enum SmartPreviewFormat {

    /// The container magic (our spelling of the Lumen LPV1 shape).
    public static let magic = "LAPV1"

    /// The cache-key format dimension (bumping it invalidates every entry —
    /// the T2 key folds this).
    public static let formatVersion = 1

    /// The header JSON's meta values are strings (the JSON-safe projection
    /// of the key/carrier facts T3 records: source path, process version…).
    public typealias Meta = [String: String]

    struct Header: Codable, Equatable {
        let width: Int
        let height: Int
        let version: Int
        let meta: Meta
    }

    // MARK: - Quantization (the consistency rule)

    /// The float16 round-trip every fresh decode passes through (H-LU3 arm
    /// 1): relative precision ≈ 2^-11 ≈ 0.049% < 0.05% (the Lumen measured
    /// bound the golden test asserts). Bit-identity: quantize(quantize(p))
    /// == quantize(p) — the idempotence the hit/miss equality rides.
    public static func quantize(_ plane: SmartPreviewPlane) -> SmartPreviewPlane {
        var out = plane.rgba
        out.reserveCapacity(out.count)
        for index in out.indices {
            out[index] = Float(Float16(out[index]))
        }
        return SmartPreviewPlane(width: plane.width, height: plane.height, rgba: out)
    }

    /// The float16 halves of a plane (the pack intermediate; internal so the
    /// rearrangement smoke test can compose both byte orders).
    static func halves(_ plane: SmartPreviewPlane) -> [Float16] {
        var out = [Float16](repeating: 0, count: plane.sampleCount)
        for index in 0..<plane.sampleCount {
            out[index] = Float16(plane.rgba[index])
        }
        return out
    }

    /// The byte-plane split (low plane first, then high plane) — the
    /// rearrangement that lifts the zlib ratio.
    static func planarBytes(from halves: [Float16]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: halves.count * 2)
        for index in 0..<halves.count {
            let bits = halves[index].bitPattern
            out[index] = UInt8(bits & 0xFF)
            out[halves.count + index] = UInt8(bits >> 8)
        }
        return out
    }

    /// The naive interleaved byte order (the smoke test's baseline — what
    /// zlib would see WITHOUT the rearrangement).
    static func interleavedBytes(from halves: [Float16]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: halves.count * 2)
        for index in 0..<halves.count {
            let bits = halves[index].bitPattern
            out[index * 2] = UInt8(bits & 0xFF)
            out[index * 2 + 1] = UInt8(bits >> 8)
        }
        return out
    }

    static func halves(fromPlanarBytes bytes: [UInt8]) -> [Float16] {
        let count = bytes.count / 2
        var out = [Float16](repeating: 0, count: count)
        for index in 0..<count {
            out[index] = Float16(bitPattern: UInt16(bytes[index]) | (UInt16(bytes[count + index]) << 8))
        }
        return out
    }

    // MARK: - Pack / unpack

    /// The packed envelope: magic + header length + JSON header + zlib'd
    /// planar float16 bytes.
    public static func pack(
        _ plane: SmartPreviewPlane, meta: Meta = [:]
    ) throws -> Data {
        let header = Header(
            width: plane.width, height: plane.height,
            version: formatVersion, meta: meta)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let headerData = try? encoder.encode(header) else {
            throw SmartPreviewFormatError.badHeader
        }
        guard headerData.count <= Int(UInt32.max) else {
            throw SmartPreviewFormatError.headerTooLarge
        }
        let planes = planarBytes(from: halves(plane))
        guard let compressed = Self.compress(planes) else {
            throw SmartPreviewFormatError.badHeader
        }

        var data = Data()
        data.reserveCapacity(magicData.count + 4 + headerData.count + compressed.count)
        data.append(magicData)
        var length = UInt32(headerData.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(headerData)
        data.append(compressed)
        return data
    }

    /// The read-back: envelope → plane + meta. Every malformed shape is a
    /// typed throw (the store deletes + rebuilds on any of them).
    public static func unpack(_ data: Data) throws -> (plane: SmartPreviewPlane, meta: Meta) {
        let bytes = [UInt8](data)
        let magicBytes = Array(magicData)
        guard bytes.count >= magicBytes.count + 4, Array(bytes[0..<magicBytes.count]) == magicBytes
        else { throw SmartPreviewFormatError.badMagic }

        let lengthOffset = magicBytes.count
        let headerLength = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: lengthOffset, as: UInt32.self).littleEndian
        }
        let headerStart = lengthOffset + 4
        let headerEnd = headerStart + Int(headerLength)
        guard Int(headerLength) > 0, headerEnd <= bytes.count else {
            throw SmartPreviewFormatError.truncatedEnvelope
        }
        guard let header = try? JSONDecoder().decode(
            Header.self, from: Data(bytes[headerStart..<headerEnd]))
        else { throw SmartPreviewFormatError.badHeader }
        guard header.version == formatVersion else {
            throw SmartPreviewFormatError.badHeader
        }

        let expected = header.width * header.height * 4 * 2
        let compressed = Data(bytes[headerEnd...])
        guard let planes = decompress(compressed, byteCount: expected),
              planes.count == expected
        else { throw SmartPreviewFormatError.truncatedPlanes }

        let plane = SmartPreviewPlane(
            width: header.width, height: header.height,
            rgba: halves(fromPlanarBytes: planes).map(Float.init))
        return (plane, header.meta)
    }

    static var magicData: Data {
        Data(magic.utf8)
    }

    // MARK: - Deflate (the level-1-intent carrier — see the file header)

    static func compress(_ input: [UInt8]) -> Data? {
        guard !input.isEmpty else { return nil }
        let dstCapacity = input.count + input.count / 2 + 64
        var dst = Data(count: dstCapacity)
        let written = dst.withUnsafeMutableBytes { raw -> Int in
            input.withUnsafeBufferPointer { src in
                compression_encode_buffer(
                    raw.bindMemory(to: UInt8.self).baseAddress!, dstCapacity,
                    src.baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return dst.prefix(written)
    }

    static func decompress(_ input: Data, byteCount: Int) -> [UInt8]? {
        guard byteCount > 0, !input.isEmpty else { return nil }
        var dst = [UInt8](repeating: 0, count: byteCount)
        let written = input.withUnsafeBytes { raw -> Int in
            dst.withUnsafeMutableBufferPointer { buffer in
                compression_decode_buffer(
                    buffer.baseAddress!, byteCount,
                    raw.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == byteCount else { return nil }
        return dst
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The cache itself (Plan LUMEN-B T2, X6/D-LU-3): key (path|size|mtime ns|
// process version|format version → sha1 hex — the process dimension is OURS,
// a render-semantics bump invalidates naturally, M6-2), an index SQLite in
// WAL mode, plane files written to a same-directory temp name and renamed
// (L009 — never a cross-volume /tmp rename), a byte-budget LRU (default
// 4 GB; 0 = off; trim to 90% by oldest `used`, every 16th write), a small
// decoded-plane memory LRU, in-flight dedup, and the damage/degrade
// semantics: a cache that cannot be read or written NEVER keeps a decode
// from happening (the default-neutral face — disabled = the raw decode,
// byte-identical to the pre-plan behavior).
//
// The transliteration source for the table/file/trim/in-flight shapes is
// Lumen preview_cache.py (MIT — see the file header note); the store form
// is the Swift actor + the M2-5 shared-holder体例 (`shared` getter under an
// NSLock + `replaceShared(_:)` — review m-9).
// ─────────────────────────────────────────────────────────────────────────────

/// `SQLITE_TRANSIENT` — sqlite copies the bound text (the SQLiteHandle
/// file's local-definition form; the SQLite3 overlay's spelling is private).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public actor SmartPreviewStore {

    /// THE UserDefaults key — the single source (the T7 Settings row and
    /// AppPreferences alias this constant; the literal is spelled nowhere
    /// else in the repo).
    public static let limitKey = "previews.cacheMB"

    /// The default budget (Lumen DEFAULT_MB).
    public static let defaultLimitMB = 4096

    /// The in-memory decoded planes kept warm (Lumen MEMORY_ITEMS).
    static let memoryCapacity = 6

    /// The trim cadence (every 16th scheduled write — Lumen `_pending`).
    static let trimCadence = 16

    /// The app cache location (D-LU-3: rebuildable, cross-project shared,
    /// never inside a `.lalb` package). `LIGHTAMER_PREVIEW_CACHE` overrides
    /// (the headless/test escape hatch, Lumen's env override 同形).
    public static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["LIGHTAMER_PREVIEW_CACHE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return caches.appendingPathComponent("Lightamer/smart-previews", isDirectory: true)
    }

    /// The typed budget read (KD-4): unset/unparseable = the 4 GB default;
    /// 0 = off; negative clamps to 0.
    public static func defaultLimitMB(defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: limitKey) as? Int else {
            return defaultLimitMB
        }
        return max(0, stored)
    }

    // MARK: - The shared holder (review m-9 — the M2-5 体例)

    private static let sharedLock = NSLock()
    private nonisolated(unsafe) static var sharedInstance: SmartPreviewStore?

    /// The process-wide store (created on first use): the default root +
    /// the UserDefaults budget. All four consumers share ONE instance —
    /// one index DB handle, one memory LRU, one in-flight table.
    public static var shared: SmartPreviewStore {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let instance = sharedInstance { return instance }
        let store = SmartPreviewStore(
            root: defaultRoot, limitMB: defaultLimitMB(defaults: .standard))
        sharedInstance = store
        return store
    }

    /// Atomically replace the shared store (the tests' isolation face; the
    /// T7 budget face swaps through here too).
    public static func replaceShared(_ store: SmartPreviewStore) {
        sharedLock.lock()
        sharedInstance = store
        sharedLock.unlock()
    }

    // MARK: - Key + stamp

    /// `sourcePath|size|mtime ns|process version|cache format version` →
    /// sha1 hex (the L013-adjacent hex index key face; sha1 IS hex — no
    /// decimal-string projection applies). mtime is pinned at NANOSECOND
    /// precision (the stat st_mtimespec — same-second burst frames never
    /// share a key, review m-10).
    public static func cacheKey(
        sourcePath: String, size: Int, mtimeNanos: Int64, processVersion: Int
    ) -> String {
        let text = "\(sourcePath)|\(size)|\(mtimeNanos)|\(processVersion)|\(SmartPreviewFormat.formatVersion)"
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The resolved-path + size + nanosecond-mtime stamp of a source as it
    /// sits on disk NOW (nil = unstatable — the caller degrades to a direct
    /// decode).
    public static func fileStamp(
        _ url: URL
    ) -> (resolvedPath: String, size: Int, mtimeNanos: Int64)? {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return nil }
        // Resolve symlinks so one file behind several paths shares a key.
        let resolved = url.resolvingSymlinksInPath().path
        let nanos = Int64(status.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(status.st_mtimespec.tv_nsec)
        return (resolved, Int(status.st_size), nanos)
    }

    // MARK: - State

    nonisolated let root: URL
    /// The byte budget (0 = off — every load degrades to the raw decode).
    private(set) var limitBytes: Int
    /// The injected `used` clock (tests pin the eviction ORDER).
    private let clock: @Sendable () -> Double

    private var db: OpaquePointer?
    /// The decoded planes kept warm (quantized — the disk values).
    private var memory: [String: SmartPreviewPlane] = [:]
    private var memoryOrder: [String] = []
    /// One production per key; merged waiters await the SAME task.
    private var inflight: [String: Task<SmartPreviewPlane, Error>] = [:]
    /// Scheduled disk writes (the `flush()` test face awaits them).
    private var writeTasks: [String: Task<Void, Never>] = [:]
    private var writeCount = 0
    private var trimTask: Task<Void, Never>?

    public init(
        root: URL, limitMB: Int,
        clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) {
        self.root = root
        self.limitBytes = max(0, limitMB) * 1024 * 1024
        self.clock = clock
    }

    /// The live budget face (the T7 Settings row rides this — the Lumen
    /// set_limit semantics: a lowered budget trims; 0 clears).
    public func setLimit(megabytes: Int) {
        limitBytes = max(0, megabytes) * 1024 * 1024
        if limitBytes == 0 {
            memory.removeAll()
            memoryOrder.removeAll()
        }
        scheduleTrim()
    }

    public var isEnabled: Bool { limitBytes > 0 }

    // MARK: - Load (the one entry the four consumers ride)

    /// The decoded plane for `url` through the cache. `processVersion` is
    /// the M6-2 read point — callers pass `RenderProcessVersion.current
    /// .rawValue` (the single source); tests inject values to pin the bump
    /// invalidation. `decode` is the caller's raw decode leg (the wrapper
    /// seam — RAWDecoder's signature stays zero-diff).
    ///
    /// Semantics: DISABLED or unstatable → the RAW decode untouched (the
    /// default-neutral face: byte-identical to the pre-plan behavior);
    /// miss → decode + `quantize` + remember + backfill; hit → the SAME
    /// quantized values from memory/disk (H-LU3: hit and miss are
    /// bit-identical). A cache that cannot be read or written never keeps
    /// a decode from happening.
    public func load(
        url: URL, processVersion: Int,
        decode: @escaping @Sendable (URL) async throws -> SmartPreviewPlane
    ) async throws -> SmartPreviewPlane {
        guard limitBytes > 0, let stamp = Self.fileStamp(url) else {
            return try await decode(url)
        }
        let key = Self.cacheKey(
            sourcePath: stamp.resolvedPath, size: stamp.size,
            mtimeNanos: stamp.mtimeNanos, processVersion: processVersion)

        if let hit = memoryAccess(key) { return hit }
        if let diskHit = readDisk(key) {
            remember(key, diskHit)
            return diskHit
        }

        // The in-flight claim is a SYNCHRONOUS actor section (check + set
        // with no await between — the gate-actor discipline).
        let isOwner: Bool
        let task: Task<SmartPreviewPlane, Error>
        if let existing = inflight[key] {
            task = existing
            isOwner = false
        } else {
            task = Task.detached(priority: .userInitiated) { [decode] in
                SmartPreviewFormat.quantize(try await decode(url))
            }
            inflight[key] = task
            isOwner = true
        }

        do {
            let plane = try await task.value
            if isOwner {
                inflight[key] = nil
                remember(key, plane)
                scheduleWrite(key, plane)
            }
            return plane
        } catch {
            if isOwner { inflight[key] = nil }
            throw error
        }
    }

    // MARK: - Memory LRU

    private func memoryAccess(_ key: String) -> SmartPreviewPlane? {
        guard memory[key] != nil else { return nil }
        touchMemory(key)
        return memory[key]
    }

    private func remember(_ key: String, _ plane: SmartPreviewPlane) {
        memory[key] = plane
        touchMemory(key)
        while memoryOrder.count > Self.memoryCapacity {
            let evicted = memoryOrder.removeFirst()
            memory[evicted] = nil
        }
    }

    private func touchMemory(_ key: String) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }

    // MARK: - Disk tier (plane files + index)

    private func planeURL(_ key: String) -> URL {
        root.appendingPathComponent("d/\(key.prefix(2))", isDirectory: true)
            .appendingPathComponent("\(key).lapv")
    }

    private func readDisk(_ key: String) -> SmartPreviewPlane? {
        let url = planeURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let (plane, _) = try? SmartPreviewFormat.unpack(data) else {
            // Damaged entry: the cache is rebuildable — drop and miss.
            forget(key)
            return nil
        }
        touch(key)
        return plane
    }

    private func scheduleWrite(_ key: String, _ plane: SmartPreviewPlane) {
        writeCount += 1
        writeTasks[key] = Task { [weak self] in
            await self?.writeToDisk(key, plane)
        }
        if writeCount % Self.trimCadence == 0 {
            scheduleTrim()
        }
    }

    private func writeToDisk(_ key: String, _ plane: SmartPreviewPlane) {
        guard limitBytes > 0 else { return }
        guard let data = try? SmartPreviewFormat.pack(plane) else { return }
        let destination = planeURL(key)
        let directory = destination.deletingLastPathComponent()
        // L009: the temp lives in the SAME directory; the rename is the
        // atomic promotion (never a cross-volume /tmp hop).
        let temp = directory.appendingPathComponent(
            "\(destination.lastPathComponent).\(getpid()).\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: temp, options: .atomic)
            // moveItem does NOT overwrite — clear a previous entry first.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temp, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return  // a full disk / a hostile directory never propagates
        }
        record(key, bytes: data.count)
    }

    /// Wait for the scheduled writes + trim (the tests' determinism face;
    /// shutdown may ride it too).
    public func flush() async {
        let pending = Array(writeTasks.values)
        writeTasks.removeAll()
        for task in pending { _ = await task.result }
        if let trim = trimTask { _ = await trim.result; trimTask = nil }
    }

    /// The memory + memory-order face (the test observability window).
    func memoryStateForTesting() -> (order: [String], count: Int) {
        (memoryOrder, memory.count)
    }

    // MARK: - Index SQLite (WAL; damaged = rebuilt)

    private func openIndex() -> OpaquePointer? {
        if let db { return db }
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let dbPath = root.appendingPathComponent("index.db").path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &handle, flags, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return nil
        }
        // WAL first (persistent) + NORMAL (the ProjectFileStore discipline).
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        let schema = "CREATE TABLE IF NOT EXISTS entries("
            + "key TEXT NOT NULL, kind TEXT NOT NULL, bytes INTEGER NOT NULL, "
            + "used REAL NOT NULL, PRIMARY KEY(key, kind))"
        if sqlite3_exec(handle, schema, nil, nil, nil) != SQLITE_OK {
            // A damaged index: the cache is rebuildable — start a new one
            // (the Lumen DatabaseError arm).
            sqlite3_close(handle)
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: root.appendingPathComponent("index.db\(suffix)"))
            }
            var fresh: OpaquePointer?
            guard sqlite3_open_v2(dbPath, &fresh, flags, nil) == SQLITE_OK, let fresh else {
                sqlite3_close(fresh)
                return nil
            }
            sqlite3_exec(fresh, "PRAGMA journal_mode=WAL", nil, nil, nil)
            sqlite3_exec(fresh, "PRAGMA synchronous=NORMAL", nil, nil, nil)
            sqlite3_exec(fresh, schema, nil, nil, nil)
            sqlite3_exec(fresh, "CREATE INDEX IF NOT EXISTS entries_used ON entries(used)", nil, nil, nil)
            db = fresh
            return db
        }
        sqlite3_exec(handle, "CREATE INDEX IF NOT EXISTS entries_used ON entries(used)", nil, nil, nil)
        db = handle
        return db
    }

    private func touch(_ key: String) {
        guard let db = openIndex() else { return }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "UPDATE entries SET used=? WHERE key=? AND kind=?", -1, &statement, nil)
        if let statement {
            sqlite3_bind_double(statement, 1, clock())
            sqlite3_bind_text(statement, 2, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, "d", -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func record(_ key: String, bytes: Int) {
        guard let db = openIndex() else { return }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db, "INSERT OR REPLACE INTO entries(key, kind, bytes, used) VALUES (?, ?, ?, ?)",
            -1, &statement, nil)
        if let statement {
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, "d", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 3, Int64(bytes))
            sqlite3_bind_double(statement, 4, clock())
            _ = sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func forget(_ key: String) {
        try? FileManager.default.removeItem(at: planeURL(key))
        guard let db = openIndex() else { return }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "DELETE FROM entries WHERE key=? AND kind=?", -1, &statement, nil)
        if let statement {
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, "d", -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    /// The byte budget summary (the test/trim face).
    public func totalBytes() -> Int {
        guard let db = openIndex() else { return 0 }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(bytes), 0) FROM entries", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard let statement, sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// The entry keys oldest-`used` first (the eviction-order test face).
    func entriesOldestFirstForTesting() -> [String] {
        guard let db = openIndex() else { return [] }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db, "SELECT key FROM entries ORDER BY used, key", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        var keys: [String] = []
        while let statement, sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                keys.append(String(cString: text))
            }
        }
        return keys
    }

    // MARK: - LRU trim

    private func scheduleTrim() {
        guard trimTask == nil else { return }
        trimTask = Task { [weak self] in
            await self?.trim()
            await self?.clearTrimTask()
        }
    }

    private func clearTrimTask() {
        trimTask = nil
    }

    /// Drop least-recently-used entries until the cache sits below 90% of
    /// the budget (Lumen trim 直译; `targetBytes` overrides — the deterministic
    /// test face). Returns the removed count.
    @discardableResult
    public func trim(targetBytes: Int? = nil) -> Int {
        guard limitBytes > 0 else { return 0 }
        let target = targetBytes ?? limitBytes * 9 / 10
        var total = totalBytes()
        guard total > target else { return 0 }
        guard let db = openIndex() else { return 0 }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db, "SELECT key, bytes FROM entries ORDER BY used, key", -1, &statement, nil)
        var victims: [(key: String, bytes: Int)] = []
        while let statement, sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                victims.append((String(cString: text), Int(sqlite3_column_int64(statement, 1))))
            }
        }
        sqlite3_finalize(statement)
        var removed = 0
        for victim in victims {
            if total <= target { break }
            forget(victim.key)
            memory[victim.key] = nil
            memoryOrder.removeAll { $0 == victim.key }
            total -= victim.bytes
            removed += 1
        }
        return removed
    }
}
