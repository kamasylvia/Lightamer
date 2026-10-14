import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImportMergeStackTests (Plan M6-4-01 T5, KD-6/E1) — the import-seam
// merge→stack face, all through the REAL ImportService import flow (the E1
// fixture discipline: real `importFolder` over a real session-root tree with
// real `.lra` files on disk — hand-built image_path rows are FORBIDDEN):
//
//   ① the canonical flow (hdr-merge product + sources, image_path =
//      Media/<folderName>/<relPath> shapes) → the stack lands
//   ② the matching-rules table: suffix ambiguity → folderName
//      disambiguation / the full-library suffix fallback (out-of-root
//      source) / the unique-stem fallback / the stem-collision skip
//   ③ Mertens + pano kinds land too (the three-kind whitelist)
//   ④ a missing source → mergeStacksSkipped, zero stacks, zero half-writes
//   ⑤ no sidecar / non-merge kinds zero-touch + the Outcome additive
//      defaults (zero drift) + the other outcome counters unchanged
//   ⑥ the ESCAPE regression nail (acceptance M-a): `%` / `_` / a literal
//      backslash in a relPath resolve LITERALLY through the library LIKE
//      fallback — decoy rows prove the wildcards never leak
// ─────────────────────────────────────────────────────────────────────────────

final class ImportMergeStackTests: XCTestCase {

    private var root: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var service: ImportService!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-merge-stack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        packageURL = root.appendingPathComponent("MergeProj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "MergeProj")
        service = ImportService(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private var packageDirectory: URL {
        packageURL.deletingLastPathComponent()
    }

    nonisolated private static func syntheticBytes(seed: UInt8, count: Int = 4096) -> Data {
        Data((0..<count).map { (index: Int) -> UInt8 in
            (seed &* 31 &+ UInt8(truncatingIfNeeded: index)) % 251
        })
    }

    @discardableResult
    private func makeFile(_ path: String, seed: UInt8) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.syntheticBytes(seed: seed).write(to: url)
        return url
    }

    /// Write a REAL `.lra` next to `imagePath` (relative to `root`) carrying
    /// the merge provenance with the given source relPaths.
    private func writeMergeSidecar(
        _ imagePath: String, kind: SidecarProvenance.Kind,
        sources: [(relPath: String, ev: Double)]
    ) throws {
        let provenance = SidecarProvenance(
            kind: kind,
            algorithm: .init(
                name: kind == .hdrMertens
                    ? ProvenanceReplay.mertensAlgorithmName
                    : (kind == .panoMerge
                        ? ProvenanceReplay.panoAlgorithmName
                        : ProvenanceReplay.hdrAlgorithmName),
                implementationVersion: "1",
                params: StackMergeService.MergeParams()),
            sources: sources.map {
                .init(relPath: $0.relPath, stableHash: 1, exposureEV: $0.ev)
            },
            alignment: [], exposureRatioVerified: [],
            holeFraction: 0, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "test")
        let document = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "v8", decodeParamsHash: 0,
            instances: [], history: HistoryStack(),
            historyHash: HistoryHash.hash(
                stack: HistoryStack(), decodeParamsHash: 0),
            provenance: provenance)
        let data = try JSONEncoder().encode(document)
        let sidecarURL = URL(fileURLWithPath: root.appendingPathComponent(imagePath).path + ".lra")
        try FileManager.default.createDirectory(
            at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: sidecarURL)
    }

    /// Run the REAL import flow over `folder` (both categories — the
    /// products are .tif; the sources are .arw).
    private func importFolder(_ folder: String) async throws -> ImportOutcome {
        let sourceFolder = root.appendingPathComponent(folder)
        let plan = try await service.makePlan(
            sourceFolder: sourceFolder, projectDirectory: packageDirectory,
            mode: .copy, whitelist: LibrarySchema.defaultRawExtensions,
            categories: .all)
        return try await service.importFolder(plan)
    }

    private func stacksCount() async throws -> Int {
        try await LibraryStore(store: fileStore).stacks().count
    }

    // MARK: - ① the canonical flow

    func testCanonicalHDRMergeImportLandsTheStack() async throws {
        // The session-root tree: a Burst folder with three RAWs (nested
        // subtree — the relPath structure survives the import) + the merge
        // product carrying their relPaths.
        let relPaths = [
            "Capture/RAW/DSC00001.ARW", "Capture/RAW/DSC00002.ARW",
            "Capture/RAW/DSC00003.ARW",
        ]
        for (index, relPath) in relPaths.enumerated() {
            try makeFile("Burst/\(relPath)", seed: UInt8(index + 1))
        }
        try makeFile("Burst/HDR/DSC00001-hdr.tif", seed: 50)
        try writeMergeSidecar(
            "Burst/HDR/DSC00001-hdr.tif", kind: .hdrMerge,
            sources: relPaths.map { ($0, 0) })

        let outcome = try await importFolder("Burst")
        XCTAssertEqual(outcome.imported, 4)
        XCTAssertEqual(outcome.mergeStacksCreated, 1)
        XCTAssertEqual(outcome.mergeStacksSkipped, 0)

        let store = LibraryStore(store: fileStore)
        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 1)
        let stack = try XCTUnwrap(stacks.first)
        XCTAssertTrue(stack.collapsed, "merge products land collapsed")
        // The product is the COVER; the landed rows carry the
        // Media/<folderName>/<relPath> shape (the E1 formula).
        let productRow = try await rowsByStem(store: store, stem: "DSC00001-hdr")
        let stackRowIDs = Set(stack.memberIDs)
        XCTAssertTrue(stackRowIDs.contains(productRow))
        XCTAssertEqual(stack.memberIDs.first, productRow, "the product IS the cover")
        let sourceRows = try await rowsByStems(store: store, stems: [
            "DSC00001", "DSC00002", "DSC00003",
        ])
        XCTAssertEqual(
            Set(stack.memberIDs).subtracting([productRow]), Set(sourceRows))
        // The landed image_path shape (the E1 formula, spot-pinned).
        let productPath = try await imagePath(of: productRow, store: store)
        XCTAssertEqual(productPath, "Media/Burst/HDR/DSC00001-hdr.tif")
    }

    // MARK: - ② the matching-rules table

    func testMatchingRulesTable() async throws {
        // (a) SUFFIX ambiguity → the folderName candidate disambiguates:
        // one import root carrying Sub/x.arw AND Deep/Sub/x.arw (different
        // bytes) + a product whose relPath is Sub/x.arw. The suffix
        // "/Sub/x.arw" matches BOTH rows; the exact Media/S/Sub/x.arw
        // candidate picks the shallower one.
        try makeFile("S/Sub/x.arw", seed: 1)
        try makeFile("S/Deep/Sub/x.arw", seed: 2)
        try makeFile("S/Deep/Sub/y.arw", seed: 3)
        try makeFile("S/P.tif", seed: 60)
        try writeMergeSidecar(
            "S/P.tif", kind: .hdrMerge,
            sources: [("Sub/x.arw", 0), ("Deep/Sub/y.arw", -1)])
        var outcome = try await importFolder("S")
        XCTAssertEqual(outcome.mergeStacksCreated, 1)
        let store = LibraryStore(store: fileStore)
        let stacksAfterS = try await store.stacks()
        var stack = try XCTUnwrap(stacksAfterS.first)
        XCTAssertEqual(
            Set(stack.memberIDs).count, 3, "product + disambiguated pair")
        let coverPath = try await imagePath(of: stack.memberIDs[0], store: store)
        XCTAssertEqual(coverPath, "Media/S/P.tif")

        // (a5) The EARLIER batch (its rows feed (b)'s library fallback and
        // (d)'s stem collision; no product — plain RAWs only).
        for (index, name) in ["DSC00001.ARW", "DSC00002.ARW", "DSC00003.ARW"]
            .enumerated() {
            try makeFile("Burst/Capture/RAW/\(name)", seed: UInt8(index + 1))
        }
        _ = try await importFolder("Burst")

        // (b) The full-library suffix fallback: the product imports ALONE
        // (its sources landed in the earlier batch — the batch map has no
        // candidates, the library query resolves them).
        try makeFile("Solo/Q.tif", seed: 61)
        try writeMergeSidecar(
            "Solo/Q.tif", kind: .hdrMerge,
            sources: [("Capture/RAW/DSC00001.ARW", 0),
                      ("Capture/RAW/DSC00002.ARW", -2)])
        outcome = try await importFolder("Solo")
        XCTAssertEqual(outcome.mergeStacksCreated, 1, "the earlier batch's rows resolve")
        let stacksAfterSolo = try await store.stacks()
        stack = try XCTUnwrap(stacksAfterSolo.last)
        XCTAssertEqual(stack.memberIDs.count, 3)
        let qCover = try await imagePath(of: stack.memberIDs[0], store: store)
        XCTAssertEqual(qCover, "Media/Solo/Q.tif")

        // (c) The unique-stem fallback: the relPath matches NOTHING by
        // suffix or folderName, but its stem is unique AND UNSTACKED in
        // the library (a plain RAW from its own earlier import).
        try makeFile("Lone/plain.arw", seed: 65)
        _ = try await importFolder("Lone")
        try makeFile("Odd/R.tif", seed: 62)
        try writeMergeSidecar(
            "Odd/R.tif", kind: .hdrMerge,
            sources: [("nowhere/at/all/plain.arw", 0)])
        outcome = try await importFolder("Odd")
        XCTAssertEqual(outcome.mergeStacksCreated, 1, "the unique stem resolves")
        let stacksAfterOdd = try await store.stacks()
        stack = try XCTUnwrap(stacksAfterOdd.last)
        XCTAssertEqual(stack.memberIDs.count, 2)

        // (d) The stem collision → the whole group SKIPS (zero half-stack).
        // The same-stem tif lands beside the earlier batch's RAW, so the
        // stem "DSC00003" resolves to TWO rows; a product referencing the
        // stem-only fallback stays ambiguous.
        try makeFile("Amb/DSC00003.tif", seed: 64)
        try makeFile("Amb/A.tif", seed: 63)
        try writeMergeSidecar(
            "Amb/A.tif", kind: .hdrMerge,
            sources: [("also/nowhere/DSC00003.ARW", 0)])
        outcome = try await importFolder("Amb")
        XCTAssertEqual(outcome.mergeStacksCreated, 0)
        XCTAssertEqual(outcome.mergeStacksSkipped, 1)
        let containing = try await store.stackContaining(
            imageID: try await rowsByStem(store: store, stem: "A"))
        XCTAssertNil(containing, "the product never half-landed")
    }

    // MARK: - ③ the Mertens + pano kinds

    func testMertensAndPanoKindsLandToo() async throws {
        let relPaths = ["Capture/RAW/DSC00004.ARW", "Capture/RAW/DSC00005.ARW"]
        for (index, relPath) in relPaths.enumerated() {
            try makeFile("Kinds/\(relPath)", seed: UInt8(index + 10))
        }
        try makeFile("Kinds/Mertens/m1.tif", seed: 70)
        try writeMergeSidecar(
            "Kinds/Mertens/m1.tif", kind: .hdrMertens,
            sources: relPaths.map { ($0, 0) })
        try makeFile("Kinds/Pano/p1.tif", seed: 71)
        try writeMergeSidecar(
            "Kinds/Pano/p1.tif", kind: .panoMerge,
            sources: relPaths.map { ($0, 0) })
        // Two products sharing the same source pair: the FIRST lands; the
        // second's sources are already stacked → skip (the seam never
        // merges existing stacks — KD-6).
        let outcome = try await importFolder("Kinds")
        XCTAssertEqual(outcome.mergeStacksCreated, 1)
        XCTAssertEqual(outcome.mergeStacksSkipped, 1)
        let store = LibraryStore(store: fileStore)
        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 1)
    }

    // MARK: - ④ the missing-source skip

    func testMissingSourceSkipsWholeGroupZeroHalfStack() async throws {
        try makeFile("Missing/Capture/RAW/DSC00006.ARW", seed: 20)
        try makeFile("Missing/M.tif", seed: 72)
        // The second source matches nothing anywhere (and its stem is a
        // guaranteed miss).
        try writeMergeSidecar(
            "Missing/M.tif", kind: .hdrMerge,
            sources: [("Capture/RAW/DSC00006.ARW", 0),
                      ("Ghost/never/imported.abw", -1)])
        let outcome = try await importFolder("Missing")
        XCTAssertEqual(outcome.mergeStacksCreated, 0)
        XCTAssertEqual(outcome.mergeStacksSkipped, 1)
        let store = LibraryStore(store: fileStore)
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty, "zero half-stacks")
        // The rows themselves landed (the import is untouched).
        let mRow = try await rowsByStem(store: store, stem: "M")
        let mImage = try await store.image(id: mRow)
        XCTAssertEqual(mImage.imagePath, "Media/Missing/M.tif")
    }

    // MARK: - ⑤ zero-touch + additive defaults

    func testNoSidecarAndNonMergeKindsZeroTouch() async throws {
        let relPaths = ["Capture/RAW/DSC00007.ARW", "Capture/RAW/DSC00008.ARW"]
        for (index, relPath) in relPaths.enumerated() {
            try makeFile("Plain/\(relPath)", seed: UInt8(index + 30))
        }
        // (a) A product with NO sidecar at all → zero-touch.
        try makeFile("Plain/N.tif", seed: 80)
        // (b) A focus-stack product (NOT in the three-kind whitelist) →
        // zero-touch, NOT even a skip.
        try makeFile("Plain/F.tif", seed: 81)
        try writeMergeSidecar(
            "Plain/F.tif", kind: .focusStack,
            sources: relPaths.map { ($0, 0) })

        let outcome = try await importFolder("Plain")
        XCTAssertEqual(outcome.imported, 4)
        XCTAssertEqual(outcome.mergeStacksCreated, 0)
        XCTAssertEqual(outcome.mergeStacksSkipped, 0, "non-merge kinds never count")
        let store = LibraryStore(store: fileStore)
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty)
        // The Outcome additive zero-drift: the pre-stacks constructor shape
        // carries the new counts at their explicit defaults.
        let plain = ImportOutcome(imported: 3, failed: 1, skippedDuplicates: 2)
        XCTAssertEqual(plain.mergeStacksCreated, 0)
        XCTAssertEqual(plain.mergeStacksSkipped, 0)
        XCTAssertEqual(
            ImportOutcome(), ImportOutcome(
                imported: 0, failed: 0, skippedDuplicates: 0, cancelled: false,
                mergeStacksCreated: 0, mergeStacksSkipped: 0))
    }

    // MARK: - ⑥ the ESCAPE regression nail (acceptance M-a)

    func testEscapeSensitiveRelPathsResolveLiterallyNotAsWildcards() async throws {
        // D-07's versioned clause: the library LIKE fallback escapes the
        // escape char ITSELF plus `%` and `_`. Each real source lands
        // beside a decoy an UNESCAPED pattern would leak to (or wrongly
        // resolve to): `%`→`X` and `_`→`X` widen the hit set into a
        // folderName ambiguity (whole-group skip), and an unescaped `\s`
        // consumes the escape char and resolves the backslash-less decoy.
        let reals = [
            "Deep/100%zoom.arw",
            "Deep/raw_file.arw",
            "Deep/back\\slash.arw",
        ]
        let decoys = [
            "Deep/100Xzoom.arw",
            "Deep/rawXfile.arw",
            "Deep/backslash.arw",
        ]
        for (index, relPath) in (reals + decoys).enumerated() {
            try makeFile("Esc/\(relPath)", seed: UInt8(index + 1))
        }
        _ = try await importFolder("Esc")

        // The product imports ALONE (its sources live in the earlier
        // batch) — the batch map has no candidates, the ESCAPE'd library
        // LIKE query must resolve all three literally.
        try makeFile("EscProd/W.tif", seed: 60)
        try writeMergeSidecar(
            "EscProd/W.tif", kind: .hdrMerge,
            sources: [("Deep/100%zoom.arw", 0),
                      ("Deep/raw_file.arw", 0),
                      ("Deep/back\\slash.arw", 0)])
        let outcome = try await importFolder("EscProd")
        XCTAssertEqual(
            outcome.mergeStacksCreated, 1,
            "every escape-sensitive source resolved through the LIKE fallback")
        XCTAssertEqual(outcome.mergeStacksSkipped, 0)

        let store = LibraryStore(store: fileStore)
        let stacks = try await store.stacks()
        let stack = try XCTUnwrap(stacks.first)
        XCTAssertEqual(stack.memberIDs.count, 4)
        // The members are the REAL rows — not the wildcard-leak decoys
        // (`100Xzoom` / `rawXfile` / `backslash` stay unstacked).
        let productRow = try await rowsByStem(store: store, stem: "W")
        let realIDs = try await rowsByStems(store: store, stems: [
            "100%zoom", "raw_file", "back\\slash",
        ])
        XCTAssertEqual(Set(stack.memberIDs), Set([productRow] + realIDs))
        let decoyIDs = try await rowsByStems(store: store, stems: [
            "100Xzoom", "rawXfile", "backslash",
        ])
        XCTAssertTrue(
            Set(stack.memberIDs).isDisjoint(with: decoyIDs),
            "the wildcards never leaked to the decoys")
    }

    // MARK: - Row helpers

    private func rowsByStem(store: LibraryStore, stem: String) async throws -> Int64 {
        let ids = try await rowsByStems(store: store, stems: [stem])
        guard ids.count == 1, let id = ids.first else {
            throw LibraryError.constraintViolation(
                detail: "expected exactly one row for stem \(stem), got \(ids.count)")
        }
        return id
    }

    private func rowsByStems(store: LibraryStore, stems: [String]) async throws -> [Int64] {
        try await fileStore.withHandle { handle in
            let placeholders = stems.map { _ in "?" }.joined(separator: ",")
            let statement = try handle.prepare(
                "SELECT id FROM images WHERE file_stem IN (\(placeholders))")
            for (index, stem) in stems.enumerated() {
                try statement.bindText(Int32(index + 1), stem)
            }
            var ids: [Int64] = []
            while try statement.step() {
                if let id = statement.columnInt(0) { ids.append(id) }
            }
            return ids
        }
    }

    private func imagePath(of id: Int64, store: LibraryStore) async throws -> String {
        try await store.image(id: id).imagePath
    }
}
