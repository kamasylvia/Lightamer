import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan M2-2-3 T3 — the library benchmark harness (KD-5), MANUAL-ONLY,
// SC#3 methodology ported verbatim from CatalogBenchmarkHarness.
//
//   LA_LIBRARY_BENCH=1 Scripts/test-direct.sh 'LibraryBenchmarkHarness'
//
// NOT a CI test (machine-difference discipline); every test SKIPS unless the
// env gate is set. N defaults to 20,000 rows (override: LA_LIBRARY_BENCH_N).
//
// THE HARD GATE (OQ-9 A signed ruling): **Release hot p95 < 20ms @ 20k rows**
// over ≥12 search shapes × 3 sorts × 2 depths, p95 nearest-rank, warm-up
// pass then a measured pass. The gate is judged on the RELEASE column only
// (Debug reference-only); three Debug+Release rounds reconcile (perf.md).
// A missed gate is attributed via EXPLAIN QUERY PLAN and fixed at the SQL
// shape — the gate is NEVER lowered and NO speculative index is added
// (adding an index = a schema v2 migration, outside this plan's mandate).
//
// Plan 16-4 T1 FINAL-RUN ADDENDUM (the Release column's direct-launch
// procedure — identical to CatalogBenchmarkHarness's appendix):
//   1. caffeinate -dis xcodebuild build-for-testing -configuration Release
//      (the SAME DerivedData container; a full rebuild after deleting the
//      Release products directory if the incremental state ever mixes
//      module generations).
//   2. codesign --force --deep --sign - <Release>/Lightamer.app
//      (ad-hoc re-sign: Team-ID validation blocks DYLD injection).
//   3. The test-direct.sh direct-launch command with the Release container
//      and the DYLD search order APP-EMBEDDED FRAMEWORKS FIRST:
//        DYLD_LIBRARY_PATH="$DD/Lightamer.app/Contents/Frameworks:
//            $DD/PackageFrameworks:$XCODE_DEV/Platforms/.../usr/lib"
//        DYLD_FRAMEWORK_PATH="$DD/Lightamer.app/Contents/Frameworks:
//            $DD/PackageFrameworks:$XCODE_DEV/Contents/SharedFrameworks:..."
//      ($DD/PackageFrameworks carries the SwiftPM product frameworks;
//      $DD-root framework copies are stale-generation traps and must NOT
//      precede the app's own copies).
//
// Fixture (probe P2's distribution): N rows of synthetic EXIF — 5 cameras /
// 5 lenses / 7 ISO tiers / 6 aperture tiers / 7 focal tiers, seeded-random
// dates over ~2.8 years, stems IMG_##### — folded through ExifFold into the
// materialized columns (the FTS trigger indexes them). ~8% NULL capture
// dates and ~11% NULL ratings exercise the NULL-tail segments. The REAL RAW
// cross leg: when `input/RAW/` exists in the repo (or
// LA_LIBRARY_BENCH_REALRAW=<dir> points anywhere), ImportService copies the
// real files into the bench package — real EXIF materializes alongside the
// synthetic corpus. Absent dir → the leg prints `skipped` and is NOT a
// violation.
//
// Observations (non-gate): N=100,000 extrapolation (LA_LIBRARY_BENCH_N) +
// ImportService import throughput (≥100 images/min soft target, the M2-2-2
// T1 fixture approach — synthetic RAW-named files).
//
// Results print as `BENCH|...` lines (extracted from /tmp/la-direct-tests.log
// into perf.md by the executor).
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryBenchmarkHarness: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!

    private var rowCount: Int {
        Int(ProcessInfo.processInfo.environment["LA_LIBRARY_BENCH_N"] ?? "")
            ?? 20_000
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-bench-\(UUID().uuidString)", isDirectory: true)
        packageURL = tempDirectory.appendingPathComponent("Bench.lalb")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func gate() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LA_LIBRARY_BENCH"] == "1",
            "manual-only benchmark (LA_LIBRARY_BENCH=1)")
    }

    // MARK: - Fixture (probe P2 distribution, batched prepared loop)

    private struct LCG {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func next(_ modulus: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(modulus))
        }
    }

    /// Bulk-generate the synthetic corpus straight into a fresh `.lalb`.
    /// Returns the wall-clock generation seconds.
    @discardableResult
    private func seedFixture(n: Int) throws -> Double {
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        try LibrarySchema.apply(to: handle, projectName: "Bench")
        let started = Date()

        let insert = try handle.prepare("""
            INSERT INTO images (image_path, path_kind, camera_make,
                camera_model, lens_model, iso, focal_length, aperture,
                capture_date, rating, file_stem, file_ext, filename, dir,
                exif_search_text, exif_search_words, added_time, modified_time)
            VALUES (?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        var random = LCG()
        let cameras: [(String, String)] = [
            ("Sony", "A7R V"), ("Canon", "EOS R5"), ("Nikon", "Z8"),
            ("Fujifilm", "X-T5"), ("Leica", "Q3"),
        ]
        let lenses = [
            "FE 24-70 F2.8 GM", "RF 50 F1.2 L", "NIKKOR Z 24-70",
            "XF 35 F1.4", "Summilux 28 ASPH",
        ]
        let isoTiers = [100, 200, 400, 800, 1600, 3200, 6400]
        let apertureTiers = [1.4, 1.8, 2.0, 2.8, 4.0, 5.6]
        let focalTiers: [Double] = [24, 35, 50, 85, 135, 200, 400]
        let dateBase = 1_650_000_000.0  // 2022-04 — spread ~2.8 years

        try handle.exec("BEGIN IMMEDIATE")
        for i in 0..<n {
            let camera = cameras[random.next(cameras.count)]
            let lens = lenses[random.next(lenses.count)]
            let iso = isoTiers[random.next(isoTiers.count)]
            let aperture = apertureTiers[random.next(apertureTiers.count)]
            let focal = focalTiers[random.next(focalTiers.count)]
            let stem = String(format: "IMG_%05d", i)
            let date: Double? = random.next(100) < 8
                ? nil : dateBase + Double(random.next(88_000_000))
            let rating: Int64? = random.next(100) < 11
                ? nil : Int64(random.next(6))
            let facts = ExifFold.Facts(
                fileStem: stem, cameraMake: camera.0, cameraModel: camera.1,
                lensModel: lens, iso: iso, focalLength: focal,
                aperture: aperture,
                captureDate: date.map { Date(timeIntervalSince1970: $0) })
            let folded = ExifFold.foldedVariants(for: facts)
            let dir = String(format: "%04d", i / 500)

            try insert.reset()
            try insert.bindText(1, "Media/\(dir)/\(stem).ARW")
            try insert.bindText(2, camera.0)
            try insert.bindText(3, camera.1)
            try insert.bindText(4, lens)
            try insert.bindInt(5, Int64(iso))
            try insert.bindDouble(6, focal)
            try insert.bindDouble(7, aperture)
            try insert.bindDouble(8, date)
            try insert.bindInt(9, rating)
            try insert.bindText(10, stem)
            try insert.bindText(11, "arw")
            try insert.bindText(12, "\(stem).ARW")
            try insert.bindText(13, dir)
            try insert.bindText(14, folded.text)
            try insert.bindText(15, folded.words)
            try insert.bindDouble(16, dateBase)
            try insert.bindDouble(17, dateBase)
            _ = try insert.step()
            if i % 5_000 == 4_999 {
                try handle.exec("COMMIT")
                try handle.exec("BEGIN IMMEDIATE")
            }
        }
        try handle.exec("COMMIT")
        let seconds = Date().timeIntervalSince(started)
        print("BENCH|fixture|rows=\(n)|gen_seconds=\(String(format: "%.2f", seconds))")
        return seconds
    }

    /// The REAL RAW cross leg's source directory (env override, else the
    /// repo's `input/RAW` located via this file's path).
    private func realRawDirectory() -> URL? {
        if let override = ProcessInfo.processInfo.environment[
            "LA_LIBRARY_BENCH_REALRAW"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let raw = repoRoot.appendingPathComponent("input/RAW", isDirectory: true)
        return FileManager.default.fileExists(atPath: raw.path) ? raw : nil
    }

    // MARK: - Timing helpers

    private func p95(of samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = min(
            Int((0.95 * Double(sorted.count)).rounded(.up)) - 1,
            sorted.count - 1)
        return sorted[max(index, 0)]
    }

    // MARK: - The query matrix (the gate)

    func testBenchmarkQueryMatrix() async throws {
        try gate()
        _ = try seedFixture(n: rowCount)
        let store = ProjectFileStore(at: packageURL)
        _ = try await store.open()
        let queries = LibraryQueries(store: store)
        defer { Task { try? await store.close() } }

        // The REAL RAW cross leg — real EXIF materializes into the same
        // corpus (best effort; absence is NOT a violation).
        if let rawDir = realRawDirectory() {
            let service = ImportService(store: store)
            let started = Date()
            let plan = try await service.makePlan(
                sourceFolder: rawDir, projectDirectory: tempDirectory,
                mode: .copy)
            let outcome = try await service.importFolder(plan)
            let ms = Date().timeIntervalSince(started) * 1000
            print("BENCH|realraw|imported=\(outcome.imported)"
                + String(format: "|failed=%d|ms=%.1f", outcome.failed, ms))
        } else {
            print("BENCH|realraw|skipped=1")
        }

        let window = 1_700_000_000.0...(1_700_000_000.0 + 30 * 86_400)
        let shapes: [(String, ExifSearchFilter)] = [
            ("lexical4", ExifSearchFilter(
                plan: try ExifSearchParser.parse("sony fe gm 24"))),
            ("isoRange", ExifSearchFilter(
                plan: try ExifSearchParser.parse("iso:400-1600"))),
            ("apertureTier", ExifSearchFilter(
                plan: try ExifSearchParser.parse("f2.8"))),
            ("focal", ExifSearchFilter(
                plan: try ExifSearchParser.parse("35mm"))),
            ("dateWindow", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .captureDate, op: .between,
                          value: .doubleRange(lower: window.lowerBound,
                                              upper: window.upperBound)),
                ]))),
            ("camera", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
                ]))),
            ("lens", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .lensModel, op: .contains,
                          value: .text("FE")),
                ]))),
            ("rating", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                ]))),
            ("mix1", ExifSearchFilter(
                plan: try ExifSearchParser.parse("sony iso800"))),
            ("mix2", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
                ]),
                plan: try ExifSearchParser.parse("f2.8"))),
            ("mix3", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                ]),
                plan: try ExifSearchParser.parse("2024 35mm"))),
            ("mix4", ExifSearchFilter(
                group: FilterPredicateGroup(rules: [
                    .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
                ]),
                plan: try ExifSearchParser.parse("iso:400-1600 fe gm"))),
        ]
        let sorts: [(String, FilterSort)] = [
            ("dateDESC", FilterSort(key: .captureDate, ascending: false)),
            ("ratingASC", FilterSort(key: .rating, ascending: true)),
            ("filenameASC", FilterSort(key: .filename, ascending: true)),
        ]
        let pageSize = LibraryQueries.defaultPageSize
        let pages = 50
        let headSamples = 20

        var allSamples: [Double] = []
        var worstCell = (p95: 0.0, name: "")

        for (shapeName, filter) in shapes {
            for (sortName, sort) in sorts {
                for depth in ["head", "deep"] {
                    // Warm-up: one full walk + head repetition (discarded).
                    var anchor: LibraryPageAnchor?
                    var tailAnchor: LibraryPageAnchor?
                    var visited = 0
                    while visited < pages * pageSize {
                        var rows = try await queries.searchPage(
                            filter: filter, sort: sort, anchor: anchor,
                            limit: pageSize)
                        if rows.isEmpty {
                            rows = try await queries.searchNullTail(
                                filter: filter, sort: sort,
                                anchor: tailAnchor, limit: pageSize)
                            if rows.isEmpty { break }
                            visited += rows.count
                            if let last = rows.last {
                                tailAnchor = LibraryPageAnchor.anchor(
                                    of: last, key: sort.key)
                                    ?? LibraryPageAnchor(
                                        keyValue: .int(nil),
                                        imagePath: last.imagePath)
                            }
                            continue
                        }
                        visited += rows.count
                        anchor = rows.last.flatMap {
                            LibraryPageAnchor.anchor(of: $0, key: sort.key)
                        }
                    }
                    for _ in 0..<3 {
                        _ = try await queries.searchPage(
                            filter: filter, sort: sort, anchor: nil,
                            limit: pageSize)
                    }

                    // Measured pass.
                    var samples: [Double] = []
                    if depth == "head" {
                        for _ in 0..<headSamples {
                            let started = Date()
                            _ = try await queries.searchPage(
                                filter: filter, sort: sort, anchor: nil,
                                limit: pageSize)
                            samples.append(
                                Date().timeIntervalSince(started) * 1000)
                        }
                    } else {
                        anchor = nil
                        tailAnchor = nil
                        visited = 0
                        sampleLoop: while visited < pages * pageSize {
                            let started = Date()
                            var rows = try await queries.searchPage(
                                filter: filter, sort: sort, anchor: anchor,
                                limit: pageSize)
                            if rows.isEmpty {
                                rows = try await queries.searchNullTail(
                                    filter: filter, sort: sort,
                                    anchor: tailAnchor, limit: pageSize)
                                if rows.isEmpty { break }
                                samples.append(
                                    Date().timeIntervalSince(started) * 1000)
                                visited += rows.count
                                if let last = rows.last {
                                    tailAnchor = LibraryPageAnchor.anchor(
                                        of: last, key: sort.key)
                                        ?? LibraryPageAnchor(
                                            keyValue: .int(nil),
                                            imagePath: last.imagePath)
                                }
                                continue sampleLoop
                            }
                            samples.append(
                                Date().timeIntervalSince(started) * 1000)
                            visited += rows.count
                            anchor = rows.last.flatMap {
                                LibraryPageAnchor.anchor(of: $0, key: sort.key)
                            }
                        }
                    }
                    allSamples.append(contentsOf: samples)
                    let cellP95 = p95(of: samples)
                    print("BENCH|matrix|\(shapeName)|\(sortName)|\(depth)"
                        + String(
                            format: "|p95_ms=%.2f|samples=%d|rows=%d",
                            cellP95, samples.count, visited))
                    if cellP95 > worstCell.p95 {
                        worstCell = (cellP95, "\(shapeName)|\(sortName)|\(depth)")
                    }
                }
            }
        }
        let totalP95 = p95(of: allSamples)
        print(String(
            format: "BENCH|gate|shapes=%d|samples=%d|total_p95_ms=%.2f"
                + "|worst_p95_ms=%.2f|worst=%@|limit_ms=20.0|%@",
            shapes.count * sorts.count * 2, allSamples.count, totalP95,
            worstCell.p95, worstCell.name,
            worstCell.p95 < 20 ? "PASS" : "FAIL"))
    }

    // MARK: - Observation: ImportService throughput (non-gate)

    /// The M2-2-2 T1 fixture approach: 100 synthetic RAW-named files, the
    /// copy pipeline end to end (scan → plan → copy → verify → rows).
    /// Soft target ≥100 images/min (printed, judged in perf.md).
    func testBenchmarkImportThroughput() async throws {
        try gate()
        let source = tempDirectory.appendingPathComponent("ThroughputSrc",
                                                          isDirectory: true)
        try FileManager.default.createDirectory(
            at: source, withIntermediateDirectories: true)
        let payload = Data(repeating: 0x41, count: 4_096)
        for i in 0..<100 {
            try payload.write(
                to: source.appendingPathComponent(
                    String(format: "IMG_%05d.ARW", i)))
        }
        let package = tempDirectory.appendingPathComponent("Throughput.lalb")
        let store = ProjectFileStore(at: package)
        _ = try await store.create(name: "Throughput")
        defer { Task { try? await store.close() } }
        let service = ImportService(store: store)

        let started = Date()
        let plan = try await service.makePlan(
            sourceFolder: source, projectDirectory: tempDirectory,
            mode: .copy)
        let outcome = try await service.importFolder(plan)
        let seconds = Date().timeIntervalSince(started)
        let perMinute = seconds > 0 ? Double(outcome.imported) / seconds * 60 : 0
        print(String(
            format: "BENCH|import|files=%d|imported=%d|failed=%d"
                + "|seconds=%.2f|images_per_min=%.1f|target=100",
            100, outcome.imported, outcome.failed, seconds, perMinute))
    }
}
