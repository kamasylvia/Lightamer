import Foundation
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// Plan 16-1 T5 — the SC#3 benchmark harness (RQ-16-13), MANUAL-ONLY.
//
//   LA_CATALOG_BENCH=1 Scripts/test-direct.sh 'CatalogBenchmarkHarness'
//
// NOT a CI test (machine-difference discipline — the same seam as the
// 09/12 perf harnesses); every test SKIPS unless the env gate is set.
// N defaults to 1M rows (override: LA_CATALOG_BENCH_N).
//
// Plan 16-4 T1 FINAL-RUN ADDENDUM (the Release column's direct-launch
// parameters — the Debug column rides test-direct.sh verbatim):
//   1. caffeinate -dis xcodebuild build-for-testing -configuration Release
//      (the SAME DerivedData container; a full rebuild after deleting the
//      Release products directory if the incremental state ever mixes
//      module generations — a stale LightamerCore.dSYM-era binary fails
//      dlopen with a mangled-symbol mismatch).
//   2. codesign --force --deep --sign - <Release>/Lightamer.app
//      (ad-hoc re-sign: the Team-ID validation blocks DYLD injection).
//   3. The test-direct.sh direct-launch command with the Release container
//      and the DYLD search order APP-EMBEDDED FRAMEWORKS FIRST:
//        DYLD_LIBRARY_PATH="$DD/Lightamer.app/Contents/Frameworks:
//            $DD/PackageFrameworks:$XCODE_DEV/.../usr/lib"
//        DYLD_FRAMEWORK_PATH="$DD/Lightamer.app/Contents/Frameworks:
//            $DD/PackageFrameworks:$XCODE_DEV/SharedFrameworks:..."
//      ($DD/PackageFrameworks carries the SwiftPM WebP product frameworks
//      — without it @rpath fails; $DD-root framework copies are stale-
//      generation traps and must NOT precede the app's own copies).
//   Main gate = the RELEASE column (Debug reference-only — 16-4-DECISIONS).
//
// Fixture (research §RQ-16-13 profile, straight into a real .lcat on the
// LOCAL disk /tmp — L009: never external-volume; the database is a throwaway
// artifact, never committed):
//   • N rows across 10 sessions
//   • capture_date 10% NULL, rating 60% NULL, color_label 70% NULL
//   • camera_model unscanned ~20% (the '' sentinel is NOT used here — the
//     EXIF light columns are NULL until a session-side sweep fills them,
//     which is the honest catalog picture for un-backfilled rows)
//   • 40% of rows carry a hierarchical keywords string ("A|B|C"-shaped),
//     materialized DIRECTLY into image_tags by the prefix-chain rule —
//     the expansion coefficient lands in the 3-9M band
//
// Query matrix = research §1.5: 8 filter shapes × 4 sort shapes × 3
// depths, 30 pages × 60 rows per shape, warm-up pass then a measured
// pass (p95, nearest-rank). COUNT face = §1.4 table. Projection
// throughput = the three RQ-16-5 scenarios against a separate 100k lindex
// fixture.
//
// Results print as `BENCH|...` lines (extracted from
// /tmp/la-direct-tests.log into perf.md by the executor).
// ─────────────────────────────────────────────────────────────────────────────

final class CatalogBenchmarkHarness: XCTestCase {

    private var tempDirectory: URL!
    private var catalogURL: URL!

    private var rowCount: Int {
        Int(ProcessInfo.processInfo.environment["LA_CATALOG_BENCH_N"] ?? "") ?? 1_000_000
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("catalog-bench-\(UUID().uuidString)", isDirectory: true)
        catalogURL = tempDirectory.appendingPathComponent("catalog.lcat")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func gate() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LA_CATALOG_BENCH"] == "1",
            "manual-only benchmark (LA_CATALOG_BENCH=1)")
    }

    // MARK: - Fixture

    /// Bulk-generate the catalog fixture (batched prepared loop, single
    /// transaction per 10k rows — the PERF-07 shape; NO temp-table joins).
    /// Returns the wall-clock generation seconds.
    @discardableResult
    private func seedFixture(n: Int) throws -> Double {
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: catalogURL.path)
        defer { handle.close() }
        try CatalogIndexSchema.apply(to: handle)
        let started = Date()

        let insert = try handle.prepare("""
            INSERT INTO catalog_images (
              session_id, rel_path, dir, filename, file_size, file_mtime,
              imageID, sidecar_present, sidecar_mtime, has_edits,
              params_hash, layer_count, layer_summary, orientation,
              width, height, capture_date, rating, color_label, keywords,
              orphan_sidecar, flag, note, camera_make, camera_model,
              lens_model, iso, focal_length, aperture, exposure
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        try handle.exec("BEGIN IMMEDIATE")
        for i in 0..<n {
            let dirIndex = i % 40
            let dir = String(format: "dir%04d", dirIndex)
            let rel = String(format: "%@/img%06d.arw", dir, i)
            try insert.bindText(1, "sess-\(i % 10)")
            try insert.bindText(2, rel)
            try insert.bindText(3, dir)
            try insert.bindText(4, String(format: "img%06d.arw", i))
            try insert.bindInt(5, Int64(4_096 + i % 1000))
            try insert.bindDouble(6, 1_700_000_000 + Double(i % 86_400))
            try insert.bindText(7, "id-\(i)")
            try insert.bindInt(8, i % 3 == 0 ? 1 : 0)
            try insert.bindDouble(9, 1234.5)
            try insert.bindInt(10, Int64(i % 2))
            try insert.bindText(11, "18000000000000000\(i % 10)")
            try insert.bindInt(12, Int64(i % 4))
            try insert.bindText(13, nil)
            try insert.bindInt(14, 1)
            try insert.bindInt(15, 6000)
            try insert.bindInt(16, 4000)
            // date 10% NULL
            if i % 10 == 0 {
                try insert.bindDouble(17, nil)
            } else {
                try insert.bindDouble(17, 1_700_000_000 + Double(i % 86_400))
            }
            // rating 60% NULL
            if i % 5 == 0 { try insert.bindInt(18, nil) }
            else { try insert.bindInt(18, Int64(i % 6)) }
            // color_label 70% NULL
            if i % 10 < 7 { try insert.bindInt(19, nil) }
            else { try insert.bindInt(19, Int64(i % 3)) }
            // 40% of rows carry a hierarchical keywords string.
            let keywords: String?
            if i % 5 < 2 {
                keywords = "Nature|Flower|Rose"
            } else if i % 5 == 2 {
                keywords = "City|Night"
            } else {
                keywords = nil
            }
            try insert.bindText(20, keywords)
            try insert.bindInt(21, 0)
            try insert.bindInt(22, nil)
            try insert.bindText(23, nil)
            try insert.bindText(24, "Sony")
            // camera_model unscanned ~20%.
            if i % 5 == 0 { try insert.bindText(25, nil) }
            else { try insert.bindText(25, "A7R V") }
            try insert.bindText(26, "FE 24-70")
            try insert.bindInt(27, Int64(100 + i % 6400))
            try insert.bindDouble(28, Double(24 + i % 50))
            try insert.bindDouble(29, [1.4, 2.0, 2.8, 4.0][i % 4])
            try insert.bindDouble(30, [0.008, 0.033, 0.125][i % 3])
            _ = try insert.step()
            try insert.reset()
            if i % 10_000 == 9_999 {
                try handle.exec("COMMIT")
                try handle.exec("BEGIN IMMEDIATE")
            }
        }
        // The tag materialization, expanded by the SAME prefix-chain rule
        // the projector uses (`tagRows` = the split tokens PLUS every
        // positional prefix). The candidate list enumerates BOTH halves and
        // the four-clause join lands each candidate via its matching arm —
        // head tokens ride `tag || '|%'`, leaf/middle tokens the
        // `'%|' || tag` / `'%|' || tag || '|%'` arms, compounds equality.
        // (16-1 acceptance fix: the first-cut candidate list enumerated the
        // PREFIX CHAIN ONLY, so the standalone tokens Flower/Rose/Night
        // never landed — 1.6 rows/image instead of the projector's true
        // 2.6; 16-4 T1 re-runs the matrix on this corrected shape.)
        try handle.execute("""
            INSERT OR IGNORE INTO image_tags (tag, catalog_image_id)
            SELECT t.tag, i.id FROM catalog_images i
            JOIN (SELECT 'Nature' AS tag UNION ALL SELECT 'Flower'
                  UNION ALL SELECT 'Rose' UNION ALL SELECT 'Nature|Flower'
                  UNION ALL SELECT 'Nature|Flower|Rose' UNION ALL SELECT 'City'
                  UNION ALL SELECT 'Night' UNION ALL SELECT 'City|Night') t
              ON (i.keywords = t.tag OR i.keywords LIKE t.tag || '|%'
                  OR i.keywords LIKE '%|' || t.tag
                  OR i.keywords LIKE '%|' || t.tag || '|%')
            WHERE i.keywords IS NOT NULL
            """)
        try handle.exec("COMMIT")

        let seconds = Date().timeIntervalSince(started)
        let tagCount = try handle.prepare("SELECT COUNT(*) FROM image_tags")
        _ = try tagCount.step()
        print("BENCH|fixture|rows=\(n)|tags=\(tagCount.columnInt(0) ?? 0)"
            + "|gen_seconds=\(String(format: "%.2f", seconds))")
        return seconds
    }

    // MARK: - Timing helpers

    private func p95(of samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let index = min(Int((0.95 * Double(sorted.count)).rounded(.up)) - 1,
                        sorted.count - 1)
        return sorted[max(index, 0)]
    }

    // MARK: - The §1.5 query matrix

    func testBenchmarkQueryMatrix() async throws {
        try gate()
        try seedFixture(n: rowCount)
        let store = CatalogIndexStore(databaseURL: catalogURL)

        let filters: [(String, [FilterPredicateGroup])] = [
            ("all", []),
            ("ratingGE4", [.init(rules: [
                .init(field: .rating, op: .gte, value: .int(4)),
            ])]),
            ("colorEq", [.init(rules: [
                .init(field: .colorLabel, op: .eq, value: .int(1)),
            ])]),
            ("cameraEq", [.init(rules: [
                .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
            ])]),
            ("dateRange", [.init(rules: [
                .init(field: .captureDate, op: .between,
                      value: .doubleRange(lower: 1_700_000_000, upper: 1_700_043_200)),
            ])]),
            ("tagAncestor", [.init(rules: [
                .init(field: .keywords, op: .contains, value: .text("Nature")),
            ])]),
            ("tag+rating", [
                .init(rules: [
                    .init(field: .keywords, op: .contains, value: .text("Nature")),
                ]),
                .init(rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                ]),
            ]),
            ("combo", [
                .init(rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                    .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
                ]),
                .init(rules: [
                    .init(field: .captureDate, op: .between,
                          value: .doubleRange(
                            lower: 1_700_000_000, upper: 1_700_043_200)),
                ]),
            ]),
        ]
        let sorts: [(String, FilterSort)] = [
            ("dateDESC", FilterSort(key: .captureDate, ascending: false)),
            ("dateASC", FilterSort(key: .captureDate, ascending: true)),
            ("ratingDESC", FilterSort(key: .rating, ascending: false)),
            ("filenameASC", FilterSort(key: .filename, ascending: true)),
        ]
        let depths = [0, 400_000, 800_000]

        let pageSize = CatalogIndexStore.defaultPageSize
        var coldSamples: [String: Double] = [:]

        // Pass 1: warm-up (the whole matrix once, discarded).
        // Pass 2: 30 measured pages per shape.
        for pass in 0..<2 {
            for (filterName, groups) in filters {
                for (sortName, sort) in sorts {
                    for depth in depths {
                        var samples: [Double] = []
                        var anchor: CatalogPageAnchor?
                        var tailAnchor: CatalogPageAnchor?
                        var visited = 0
                        let pages = 30
                        var firstOfShape = true
                        for _ in 0..<pages {
                            let started = Date()
                            var rows = try await store.queryPage(
                                groups: groups, sort: sort, anchor: anchor,
                                limit: pageSize)
                            if rows.isEmpty {
                                // Main exhausted. filename is never NULL
                                // (no tail segment — the shape is DONE);
                                // the nullable keys continue in the tail.
                                if sort.key == .filename { break }
                                rows = try await store.queryNullTail(
                                    groups: groups, sort: sort,
                                    anchor: tailAnchor, limit: pageSize)
                                if rows.isEmpty { break }
                                tailAnchor = rows.last.map {
                                    CatalogPageAnchor(
                                        keyValue: .int(nil),
                                        relPath: $0.relPath)
                                }
                            } else if let last = rows.last {
                                anchor = Self.anchor(of: last, key: sort.key)
                            }
                            visited += rows.count
                            let elapsed = Date().timeIntervalSince(started) * 1000
                            if pass == 0, firstOfShape, depth == 0 {
                                coldSamples["\(filterName)|\(sortName)|0"] = elapsed
                            }
                            if pass == 1 { samples.append(elapsed) }
                            firstOfShape = false
                        }
                        if pass == 1 {
                            let p95 = self.p95(of: samples)
                            print("BENCH|matrix|\(filterName)|\(sortName)|d\(depth)"
                                + String(
                                    format: "|p95_ms=%.2f|pages=%d|rows=%d",
                                    p95, samples.count, visited))
                            if depth == 0, let cold = coldSamples["\(filterName)|\(sortName)|0"] {
                                print(String(
                                    format: "BENCH|cold|\(filterName)|\(sortName)|ms=%.2f",
                                    cold))
                            }
                        }
                    }
                }
            }
        }
    }

    private static func anchor(
        of row: CatalogIndexRow, key: FilterSortKey
    ) -> CatalogPageAnchor? {
        switch key {
        case .captureDate: row.captureDate.map {
            CatalogPageAnchor(keyValue: .double($0), relPath: row.relPath)
        }
        case .rating: row.rating.map {
            CatalogPageAnchor(keyValue: .int($0), relPath: row.relPath)
        }
        case .filename: row.filename.map {
            CatalogPageAnchor(keyValue: .text($0), relPath: row.relPath)
        }
        default: nil
        }
    }

    // MARK: - The §1.4 COUNT face

    func testBenchmarkCountFace() async throws {
        try gate()
        try seedFixture(n: rowCount)
        let store = CatalogIndexStore(databaseURL: catalogURL)

        let shapes: [(String, [FilterPredicateGroup])] = [
            ("all", []),
            ("ratingGE4", [.init(rules: [
                .init(field: .rating, op: .gte, value: .int(4)),
            ])]),
            ("cameraEq", [.init(rules: [
                .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
            ])]),
            ("combo", [
                .init(rules: [
                    .init(field: .rating, op: .gte, value: .int(4)),
                    .init(field: .cameraModel, op: .eq, value: .text("A7R V")),
                ]),
                .init(rules: [
                    .init(field: .captureDate, op: .between,
                          value: .doubleRange(
                            lower: 1_700_000_000, upper: 1_700_043_200)),
                ]),
            ]),
        ]
        for (name, groups) in shapes {
            _ = try await store.count(groups: groups)  // warm
            let started = Date()
            let value = try await store.count(groups: groups)
            let ms = Date().timeIntervalSince(started) * 1000
            print(String(format: "BENCH|count|\(name)|ms=%.2f|value=%d", ms, value))
        }
        // Tag all-library counts: the ONE sweep.
        let started = Date()
        let tags = try await store.tagCounts()
        let ms = Date().timeIntervalSince(started) * 1000
        print(String(
            format: "BENCH|count|tagSweep|ms=%.2f|distinct=%d|total=%d",
            ms, tags.count, tags.values.reduce(0, +)))
    }

    // MARK: - The RQ-16-5 projection throughput scenarios

    /// Builds a real session.lindex fixture (a raw 34-column database).
    private func seedLindex(n: Int, epoch: Int64) throws -> URL {
        let root = tempDirectory.appendingPathComponent("proj-session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: root)
        try FileManager.default.createDirectory(
            at: lindexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let handle = try SQLiteHandle(path: lindexURL.path)
        defer { handle.close() }
        try SessionIndexSchema.apply(to: handle)
        let stamp = try handle.prepare(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('scan_epoch', ?)")
        try stamp.bindText(1, String(epoch))
        _ = try stamp.step()
        let insert = try handle.prepare("""
            INSERT INTO images (
              path, dir, filename, file_size, file_mtime, scan_epoch,
              imageID, sidecar_present, sidecar_mtime, has_edits,
              params_hash, layer_count, layer_summary, orientation,
              width, height, capture_date, rating, color_label, keywords,
              orphan_sidecar, dirty, flag, note,
              camera_make, camera_model, lens_model, iso, focal_length,
              aperture, exposure
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        try handle.exec("BEGIN IMMEDIATE")
        for i in 0..<n {
            let dir = String(format: "dir%04d", i % 40)
            let rel = String(format: "%@/img%06d.arw", dir, i)
            try insert.bindText(1, rel)
            try insert.bindText(2, dir)
            try insert.bindText(3, String(format: "img%06d.arw", i))
            try insert.bindInt(4, 4096)
            try insert.bindDouble(5, 1_700_000_000)
            try insert.bindInt(6, epoch)
            try insert.bindText(7, "id-\(i)")
            try insert.bindInt(8, 0)
            try insert.bindDouble(9, 0)
            try insert.bindInt(10, 0)
            try insert.bindText(11, nil)
            try insert.bindInt(12, nil)
            try insert.bindText(13, nil)
            try insert.bindInt(14, 1)
            try insert.bindInt(15, 100)
            try insert.bindInt(16, 100)
            if i % 10 == 0 { try insert.bindDouble(17, nil) }
            else { try insert.bindDouble(17, 1_700_000_000 + Double(i % 86_400)) }
            if i % 5 == 0 { try insert.bindInt(18, nil) }
            else { try insert.bindInt(18, Int64(i % 6)) }
            try insert.bindInt(19, nil)
            if i % 5 < 2 { try insert.bindText(20, "Nature|Flower|Rose") }
            else { try insert.bindText(20, nil) }
            try insert.bindInt(21, 0)
            try insert.bindInt(22, 0)
            try insert.bindInt(23, nil)
            try insert.bindText(24, nil)
            try insert.bindText(25, "Sony")
            try insert.bindText(26, "A7R V")
            try insert.bindText(27, "FE 24-70")
            try insert.bindInt(28, 400)
            try insert.bindDouble(29, 50.0)
            try insert.bindDouble(30, 2.8)
            try insert.bindDouble(31, 0.008)
            _ = try insert.step()
            try insert.reset()
            if i % 10_000 == 9_999 {
                try handle.exec("COMMIT")
                try handle.exec("BEGIN IMMEDIATE")
            }
        }
        try handle.exec("COMMIT")
        return root
    }

    func testBenchmarkProjectionThroughput() async throws {
        try gate()
        let defaultsSuite = "catalog-bench-\(UUID().uuidString)"
        CatalogPreferences.setCatalogsEnabled(true, defaultsSuiteName: defaultsSuite)
        defer {
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(
                forName: defaultsSuite)
        }

        // Scenario 1: a FULL 100k-row rebuild against the ≤30s budget.
        let root = try seedLindex(n: 100_000, epoch: 1)
        let projector = CatalogProjector(
            databaseURL: catalogURL, defaultsSuiteName: defaultsSuite)
        let startedFull = Date()
        let full = try await projector.project(sessionRoot: root)
        let fullSeconds = Date().timeIntervalSince(startedFull)
        print(String(
            format: "BENCH|project|full100k|seconds=%.3f|added=%d|budget=30",
            fullSeconds, full.added))

        // Scenario 2: a 10k-row INCREMENT (new epoch on 10k rows).
        let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: root)
        let lindex = try SQLiteHandle(path: lindexURL.path)
        try lindex.execute("UPDATE meta SET value = '2' WHERE key = 'scan_epoch'")
        try lindex.execute(
            "UPDATE images SET scan_epoch = 2, rating = 5 WHERE rowid % 10 = 0")
        lindex.close()
        let startedIncrement = Date()
        _ = try await projector.project(sessionRoot: root)
        let incrementMs = Date().timeIntervalSince(startedIncrement) * 1000
        print(String(
            format: "BENCH|project|increment10k|ms=%.1f", incrementMs))

        // Scenario 3: the pure diff SELECT (read-side cost of a projection).
        let readHandle = try SQLiteHandle(path: lindexURL.path)
        defer { readHandle.close() }
        let startedRead = Date()
        let diff = try readHandle.prepare(
            "SELECT path FROM images WHERE scan_epoch > 2")
        var diffRows = 0
        while try diff.step() { diffRows += 1 }
        let readMs = Date().timeIntervalSince(startedRead) * 1000
        print(String(
            format: "BENCH|project|pureDiffRead|ms=%.1f|rows=%d", readMs, diffRows))
    }

}
