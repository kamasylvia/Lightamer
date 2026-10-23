import Foundation
import ImageIO
@testable import LightamerCore
import UniformTypeIdentifiers
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SmartPreviewStoreTests (Plan LUMEN-B T1) — the LPV1-shaped pack format's
// golden face: round-trip bit-identity, the <0.05% float16 relative error,
// the quantize consistency rule (H-LU3 arm 1), the plane-rearrangement
// compression motive, and the typed malformed-envelope tolerance.
//
// Test plane sources: a seeded-LCG random plane (noise domain) + a
// photo-like synthetic (gradient + smooth shading + fine noise — the
// "实拍导出平面" stand-in; CI carries no real captures, the LUMEN-B
// DECISIONS record the substitution).
// ─────────────────────────────────────────────────────────────────────────────

final class SmartPreviewStoreTests: XCTestCase {

    // MARK: - Plane fixtures

    /// Deterministic LCG (Numerical Recipes constants) — same seed, same
    /// plane, forever.
    private static func lcgRandomPlane(width: Int, height: Int, seed: UInt64) -> SmartPreviewPlane {
        var state = seed &+ 0x9E3779B97F4A7C15
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for index in rgba.indices {
            rgba[index] = next()
        }
        return SmartPreviewPlane(width: width, height: height, rgba: rgba)
    }

    /// A photo-like plane: horizontal gradient + a smooth radial shading +
    /// fine-grain noise (the smooth domains are what the rearrangement
    /// compression feeds on).
    private static func photoLikePlane(width: Int, height: Int) -> SmartPreviewPlane {
        var state: UInt64 = 42
        func noise() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFF) / Float(0xFFFF) - 0.5
        }
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let gradient = Float(x) / Float(max(width - 1, 1))
                let dx = Float(x - width / 2), dy = Float(y - height / 2)
                let shading = exp(-(dx * dx + dy * dy) / Float(width * height / 8))
                rgba[index] = max(0, min(1, gradient * 0.7 + shading * 0.4 + noise() * 0.01))
                rgba[index + 1] = max(0, min(1, shading * 0.8 + noise() * 0.01))
                rgba[index + 2] = max(0, min(1, (1 - gradient) * 0.5 + noise() * 0.01))
                rgba[index + 3] = 1.0
            }
        }
        return SmartPreviewPlane(width: width, height: height, rgba: rgba)
    }

    /// The max-magnitude-scaled relative error (the declared form of the
    /// <0.05% bound — per-sample relative error is unbounded near zero).
    private static func relativeError(_ a: SmartPreviewPlane, _ b: SmartPreviewPlane) -> Float {
        precondition(a.width == b.width && a.height == b.height)
        var maxAbs: Float = 0
        for value in b.rgba where abs(value) > maxAbs { maxAbs = abs(value) }
        guard maxAbs > 0 else { return 0 }
        var worst: Float = 0
        for index in a.rgba.indices {
            let delta = abs(a.rgba[index] - b.rgba[index]) / maxAbs
            if delta > worst { worst = delta }
        }
        return worst
    }

    // MARK: - T1 round-trip golden (bit-identity + <0.05%)

    func testRoundTripQuantizedPlaneIsBitIdentical() throws {
        let sources = [
            ("lcg-random", Self.lcgRandomPlane(width: 64, height: 48, seed: 7)),
            ("photo-like", Self.photoLikePlane(width: 128, height: 96)),
        ]
        for (name, plane) in sources {
            let quantized = SmartPreviewFormat.quantize(plane)
            let packed = try SmartPreviewFormat.pack(quantized, meta: ["source": name])
            let (unpacked, meta) = try SmartPreviewFormat.unpack(packed)
            // BIT-IDENTICAL (the H-LU3 hit/miss equality premise).
            XCTAssertEqual(unpacked, quantized, "\(name): quantized round-trip must be bit-identical")
            XCTAssertEqual(meta["source"], name)
        }
    }

    func testRoundTripRawPlaneErrorBelow0Point05Percent() throws {
        let sources = [
            Self.lcgRandomPlane(width: 96, height: 64, seed: 99),
            Self.photoLikePlane(width: 192, height: 128),
        ]
        for plane in sources {
            let packed = try SmartPreviewFormat.pack(plane)
            let (unpacked, _) = try SmartPreviewFormat.unpack(packed)
            // The pack path quantizes; the unpack must equal quantize exactly…
            XCTAssertEqual(unpacked, SmartPreviewFormat.quantize(plane))
            // …and deviate from the raw plane by < 0.05% (2^-11 ≈ 0.049%).
            XCTAssertLessThan(
                Self.relativeError(unpacked, plane), 0.0005,
                "float16 relative error must stay below 0.05%")
        }
    }

    // MARK: - T1 quantize consistency rule

    func testQuantizeIsIdempotentAndMatchesPackPath() {
        let plane = Self.photoLikePlane(width: 33, height: 21)
        let once = SmartPreviewFormat.quantize(plane)
        let twice = SmartPreviewFormat.quantize(once)
        // Idempotence: a fresh decode quantized then stored then read back
        // lands on the SAME values as quantize applied twice — the rule
        // that makes hit and miss bit-identical (H-LU3 arm 1).
        XCTAssertEqual(once, twice)
    }

    // MARK: - T1 plane-rearrangement compression motive (smoke)

    func testPlanarRearrangementCompressesBetterThanInterleaved() throws {
        let plane = Self.photoLikePlane(width: 256, height: 192)
        let halves = SmartPreviewFormat.halves(SmartPreviewFormat.quantize(plane))
        let planar = SmartPreviewFormat.planarBytes(from: halves)
        let interleaved = SmartPreviewFormat.interleavedBytes(from: halves)
        // Monotone motive: the rearranged planes compress STRICTLY smaller
        // on smooth image data (the Lumen transliteration's reason to be).
        XCTAssertLessThan(
            SmartPreviewFormat.compress(planar)!.count,
            SmartPreviewFormat.compress(interleaved)!.count)
        // And the packed envelope is materially smaller than the raw bytes.
        let packed = try SmartPreviewFormat.pack(plane)
        XCTAssertLessThan(packed.count, planar.count)
    }

    // MARK: - T1 malformed envelope tolerance (typed, never crash)

    func testUnpackRejectsWrongMagic() {
        var data = try! SmartPreviewFormat.pack(Self.photoLikePlane(width: 8, height: 8))
        data.replaceSubrange(0..<5, with: Data("XXXXX".utf8))
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(data)) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .badMagic)
        }
    }

    func testUnpackRejectsTruncatedEnvelope() throws {
        let packed = try SmartPreviewFormat.pack(Self.photoLikePlane(width: 8, height: 8))
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(packed.prefix(6))) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .badMagic)
        }
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(packed.prefix(9))) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .truncatedEnvelope)
        }
    }

    func testUnpackRejectsLyingHeaderLength() throws {
        let packed = try SmartPreviewFormat.pack(Self.photoLikePlane(width: 8, height: 8))
        var mutated = Data(packed)
        // The UInt32 LE length field sits at offset 5 — claim a huge header.
        mutated.replaceSubrange(5..<9, with: Data([
            0xFF, 0xFF, 0xFF, 0x7F,
        ]))
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(mutated)) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .truncatedEnvelope)
        }
    }

    func testUnpackRejectsTruncatedPlanes() throws {
        let packed = try SmartPreviewFormat.pack(Self.photoLikePlane(width: 32, height: 32))
        // Cut half the compressed payload — the deflate stream cannot be
        // complete, so the decode lands short of `expected`.
        let truncated = packed.prefix(packed.count / 2)
        XCTAssertThrowsError(try SmartPreviewFormat.unpack(truncated)) { error in
            XCTAssertEqual(error as? SmartPreviewFormatError, .truncatedPlanes)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// T2 (X6/D-LU-3): the cache infrastructure — key invalidation (mtime/size/
// process-version dimensions), the byte-budget LRU eviction order, the
// ─────────────────────────────────────────────────────────────────────────────
// T2 (X6/D-LU-3): the cache infrastructure — key invalidation (mtime/size/
// process-version dimensions), the byte-budget LRU eviction order, the
// in-flight dedup through the SHARED holder, and the damage/degrade faces.
// ─────────────────────────────────────────────────────────────────────────────

extension SmartPreviewStoreTests {

    /// A tiny thread-safe counter (the decode-leg observability box).
    final class CounterBox: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); count += 1; lock.unlock() }

        /// The monotone injected-clock face (strictly increasing doubles).
        func bump() -> Double {
            lock.lock(); count += 1; lock.unlock()
            return Double(count)
        }
    }

    // MARK: - Fixtures

    /// A real temp file (the key/stamp tests stat it for truth).
    private func makeSourceFile(
        _ name: String, size: Int, mtime: Date? = nil
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartpreview-t2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0xAB, count: size).write(to: url)
        if let mtime {
            try FileManager.default.setAttributes(
                [.modificationDate: mtime], ofItemAtPath: url.path)
        }
        return url
    }

    private static func plane(width: Int = 8, height: Int = 8, value: Float = 0.25) -> SmartPreviewPlane {
        SmartPreviewPlane(
            width: width, height: height,
            rgba: [Float](repeating: value, count: width * height * 4))
    }

    private func makeStore(
        limitMB: Int = 64, clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }
    ) -> SmartPreviewStore {
        SmartPreviewStore(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("smartpreview-store-\(UUID().uuidString)", isDirectory: true),
            limitMB: limitMB, clock: clock)
    }

    // MARK: - Key invalidation (mtime / size / process version)

    func testCacheKeyInvalidatesOnStampAndProcessVersionChange() throws {
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try makeSourceFile("photo.nef", size: 100, mtime: mtime)
        let stamp = SmartPreviewStore.fileStamp(url)
        XCTAssertNotNil(stamp)
        let base = SmartPreviewStore.cacheKey(
            sourcePath: stamp!.resolvedPath, size: stamp!.size,
            mtimeNanos: stamp!.mtimeNanos, processVersion: 1)

        // Same stamp + same process → identical key.
        let again = SmartPreviewStore.cacheKey(
            sourcePath: stamp!.resolvedPath, size: stamp!.size,
            mtimeNanos: stamp!.mtimeNanos, processVersion: 1)
        XCTAssertEqual(base, again)

        // A size bump invalidates.
        let sizeKey = SmartPreviewStore.cacheKey(
            sourcePath: stamp!.resolvedPath, size: stamp!.size + 1,
            mtimeNanos: stamp!.mtimeNanos, processVersion: 1)
        XCTAssertNotEqual(base, sizeKey)

        // An mtime bump invalidates (write NEW content — the stamp re-read
        // sees a fresh nanosecond mtime).
        try Data(repeating: 0xCD, count: 100).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: mtime.addingTimeInterval(1)], ofItemAtPath: url.path)
        let newStamp = SmartPreviewStore.fileStamp(url)
        XCTAssertNotEqual(stamp!.mtimeNanos, newStamp!.mtimeNanos)
        let mtimeKey = SmartPreviewStore.cacheKey(
            sourcePath: newStamp!.resolvedPath, size: newStamp!.size,
            mtimeNanos: newStamp!.mtimeNanos, processVersion: 1)
        XCTAssertNotEqual(base, mtimeKey)

        // The process-version dimension (OURS — M6-2): a render-semantics
        // bump invalidates every old entry.
        let bumped = SmartPreviewStore.cacheKey(
            sourcePath: stamp!.resolvedPath, size: stamp!.size,
            mtimeNanos: stamp!.mtimeNanos, processVersion: 2)
        XCTAssertNotEqual(base, bumped)

        // The key is sha1 hex (the L013-adjacent index key face).
        XCTAssertEqual(base.count, 40)
        XCTAssertTrue(base.allSatisfy { $0.isHexDigit })
    }

    // MARK: - LRU trim (the eviction order)

    func testTrimEvictsOldestUsedFirst() async throws {
        let tick = CounterBox()
        let store = makeStore(limitMB: 64) { tick.bump() }
        let url = try makeSourceFile("photo2.nef", size: 10)
        let stamp = SmartPreviewStore.fileStamp(url)!
        var keys: [String] = []
        for index in 0..<5 {
            let process = 100 + index  // distinct keys over one source
            keys.append(SmartPreviewStore.cacheKey(
                sourcePath: stamp.resolvedPath, size: stamp.size,
                mtimeNanos: stamp.mtimeNanos, processVersion: process))
            _ = try await store.load(
                url: url, processVersion: process) { _ in
                    // UNIFORM bytes (one constant value) — equal-size
                    // entries make the keep-newest trim arithmetic exact.
                    SmartPreviewPlane(
                        width: 8, height: 8,
                        rgba: [Float](repeating: 0.5, count: 8 * 8 * 4))
                }
        }
        await store.flush()
        let total = await store.totalBytes()
        XCTAssertGreaterThan(total, 0)
        // Oldest-used first in the index (the injected clock is monotone).
        let ordered = await store.entriesOldestFirstForTesting()
        XCTAssertEqual(ordered, keys)

        // Trim to one-fifth of the bytes: the OLDEST entries die and the
        // newest survivor stays.
        let removed = await store.trim(targetBytes: total / 5)
        XCTAssertGreaterThanOrEqual(removed, 1)
        let remaining = await store.entriesOldestFirstForTesting()
        XCTAssertEqual(remaining, [keys[4]], "the eviction order is oldest-used first")
    }

    // MARK: - In-flight dedup through the shared holder

    func testInflightRequestsMergeThroughSharedHolder() async throws {
        let store = makeStore()
        SmartPreviewStore.replaceShared(store)
        defer {
            SmartPreviewStore.replaceShared(SmartPreviewStore(
                root: SmartPreviewStore.defaultRoot,
                limitMB: SmartPreviewStore.defaultLimitMB(
                    defaults: .standard)))
        }
        let url = try makeSourceFile("photo3.nef", size: 10)
        let counter = CounterBox()
        let decode: @Sendable (URL) async throws -> SmartPreviewPlane = { _ in
            counter.increment()
            try await Task.sleep(nanoseconds: 150_000_000)
            return SmartPreviewPlane(
                width: 8, height: 8, rgba: [Float](repeating: 0.5, count: 8 * 8 * 4))
        }
        async let first = SmartPreviewStore.shared.load(
            url: url, processVersion: 1, decode: decode)
        async let second = SmartPreviewStore.shared.load(
            url: url, processVersion: 1, decode: decode)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b)
        XCTAssertEqual(counter.value, 1, "same-key concurrent requests merge onto ONE decode")
        await store.flush()
        let total = await store.totalBytes()
        XCTAssertGreaterThan(total, 0, "the owner's decode was written back to disk")
    }

    // MARK: - Damage rebuild + degraded direct decode + disabled neutral

    func testDamagedPlaneEntryIsDroppedAndRebuilt() async throws {
        let store = makeStore()
        let url = try makeSourceFile("photo4.nef", size: 10)
        let counter = CounterBox()
        let decode: @Sendable (URL) async throws -> SmartPreviewPlane = { _ in
            counter.increment()
            return SmartPreviewPlane(
                width: 8, height: 8, rgba: [Float](repeating: 0.75, count: 8 * 8 * 4))
        }
        let first = try await store.load(url: url, processVersion: 1, decode: decode)
        await store.flush()
        XCTAssertEqual(counter.value, 1)

        // Corrupt the on-disk plane (the stamp is unchanged, so the same
        // key resolves) — the load must DROP the entry and rebuild it.
        let stamp = SmartPreviewStore.fileStamp(url)!
        let key = SmartPreviewStore.cacheKey(
            sourcePath: stamp.resolvedPath, size: stamp.size,
            mtimeNanos: stamp.mtimeNanos, processVersion: 1)
        let entryURL = store.root
            .appendingPathComponent("d/\(key.prefix(2))", isDirectory: true)
            .appendingPathComponent("\(key).lapv")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entryURL.path))
        try Data(repeating: 0x00, count: 64).write(to: entryURL)

        // A fresh store instance (cold memory) over the SAME root.
        let store2 = SmartPreviewStore(root: store.root, limitMB: 64)
        let second = try await store2.load(url: url, processVersion: 1, decode: decode)
        XCTAssertEqual(counter.value, 2, "the damaged entry missed and re-decoded")
        XCTAssertEqual(second, first)
        await store2.flush()
        let repaired = try? SmartPreviewFormat.unpack(try Data(contentsOf: entryURL))
        XCTAssertNotNil(repaired, "the rebuilt entry is a valid envelope again")
    }

    func testUnwritableRootDegradesToDirectDecode() async throws {
        // A root that cannot host a directory: a file standing where the
        // root directory would be.
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartpreview-blocker-\(UUID().uuidString)")
        try Data([0x01]).write(to: blocker)
        let store = SmartPreviewStore(root: blocker, limitMB: 64)
        let url = try makeSourceFile("photo5.nef", size: 10)
        // The degraded-ENABLED path still serves the quantized decode (the
        // Lumen semantics: quantize rides the miss path regardless of write
        // success — hit/miss consistency holds; only DISABLED serves raw).
        let raw = Self.plane(value: 1.0 / 3.0)
        let loaded = try await store.load(url: url, processVersion: 1) { _ in raw }
        XCTAssertEqual(loaded, SmartPreviewFormat.quantize(raw))
        XCTAssertNotEqual(loaded, raw)
        let total = await store.totalBytes()
        XCTAssertEqual(total, 0, "a broken cache persists nothing and blocks nothing")
    }

    func testDisabledBudgetReturnsRawDecodeUnquantized() async throws {
        let store = makeStore(limitMB: 0)
        let url = try makeSourceFile("photo6.nef", size: 10)
        let raw = Self.plane(value: 1.0 / 3.0)
        let loaded = try await store.load(url: url, processVersion: 1) { _ in raw }
        XCTAssertEqual(loaded, raw)
        XCTAssertNotEqual(loaded, SmartPreviewFormat.quantize(raw))
        let total = await store.totalBytes()
        XCTAssertEqual(total, 0, "a disabled cache writes nothing")
    }

    func testDamagedIndexRebuildsCleanly() async throws {
        let store = makeStore()
        let url = try makeSourceFile("photo7.nef", size: 10)
        _ = try await store.load(url: url, processVersion: 1) { _ in
            SmartPreviewPlane(width: 4, height: 4, rgba: [Float](repeating: 0.5, count: 64))
        }
        await store.flush()
        let recorded = await store.totalBytes()
        XCTAssertGreaterThan(recorded, 0)

        // Corrupt the index, then use a FRESH instance over the same root:
        // the open must rebuild and the next write must persist.
        try Data("this is not sqlite".utf8).write(
            to: store.root.appendingPathComponent("index.db"))
        let store2 = SmartPreviewStore(root: store.root, limitMB: 64)
        _ = try await store2.load(url: url, processVersion: 1) { _ in
            SmartPreviewPlane(width: 4, height: 4, rgba: [Float](repeating: 0.5, count: 64))
        }
        await store2.flush()
        let rebuilt = await store2.totalBytes()
        XCTAssertGreaterThan(rebuilt, 0, "the rebuilt index records entries again")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// T3 (X6): the shared decode leg + the four-gate consumption faces at the
// Core level — the tier cap, the disabled-neutral golden (a pure pass-
// through), and the consumer-level hit/miss bit-identity golden (H-LU3).
// The consumption-point NEGATIVE face (the editor working plane un-routed)
// is the T3 evidence grep (EditorState/PipeCoordinator carry no
// SmartPreviewStore reference) — source files are not visible to the built
// bundle, so the negative pin lives in evidence/lumenb/t3-grep.log.
// ─────────────────────────────────────────────────────────────────────────────

extension SmartPreviewStoreTests {

    /// A real raster fixture (PNG — RAWDecoder's raster leg decodes it).
    private func makePNG(width: Int, height: Int) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartpreview-t3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("photo.png")
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    // MARK: - The tier cap

    func testRenderPlaneLegCapsAtTierEdge() async throws {
        let url = try makePNG(width: 3000, height: 200)
        let plane = try await SmartPreviewRender.decodePlane(url: url)
        // 3000 → 2560 long edge; the short edge scales with it (rounded).
        XCTAssertEqual(plane.width, SmartPreviewRender.planeLongEdge)
        XCTAssertEqual(plane.height, 171)
        // A source already inside the tier is untouched.
        let small = try makePNG(width: 640, height: 480)
        let smallPlane = try await SmartPreviewRender.decodePlane(url: small)
        XCTAssertEqual(smallPlane.width, 640)
        XCTAssertEqual(smallPlane.height, 480)
    }

    // MARK: - The disabled-neutral golden (cache layer = pure pass-through)

    func testCacheDisabledNeutralGolden() async throws {
        let url = try makePNG(width: 320, height: 240)
        let store = makeStore(limitMB: 0)
        let loaded = try await store.load(
            url: url, processVersion: RenderProcessVersion.current.rawValue,
            decode: { try await SmartPreviewRender.decodePlane(url: $0) })
        let direct = try await SmartPreviewRender.decodePlane(url: url)
        // The disabled store hands back the decode leg's plane BYTE-EXACTLY
        // (the default-neutral face: no quantize, no cache arithmetic).
        XCTAssertEqual(loaded, direct)
    }

    // MARK: - The consumer-level hit/miss golden (H-LU3 at the leg)

    func testCacheHitAndMissServeBitIdenticalPlanes() async throws {
        let url = try makePNG(width: 200, height: 150)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartpreview-golden-\(UUID().uuidString)", isDirectory: true)
        let leg: @Sendable (URL) async throws -> SmartPreviewPlane = { url in
            try await SmartPreviewRender.decodePlane(url: url)
        }
        // Miss: decode + quantize + backfill.
        let missStore = SmartPreviewStore(root: root, limitMB: 64)
        let missPlane = try await missStore.load(
            url: url, processVersion: RenderProcessVersion.current.rawValue, decode: leg)
        await missStore.flush()
        // Hit: a cold store over the SAME root reads the disk entry.
        let hitStore = SmartPreviewStore(root: root, limitMB: 64)
        let hitPlane = try await hitStore.load(
            url: url, processVersion: RenderProcessVersion.current.rawValue, decode: leg)
        XCTAssertEqual(hitPlane, missPlane, "hit and miss are the SAME plane (H-LU3)")
        // And both are the quantized decode leg's output.
        let direct = try await SmartPreviewRender.decodePlane(url: url)
        XCTAssertEqual(hitPlane, SmartPreviewFormat.quantize(direct))
    }
}
