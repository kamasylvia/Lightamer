import CoreGraphics
import Foundation
import ImageIO
import LightamerCore
import SQLite3
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImportServiceTests (Plan M2-2-2 T3) — the three-transport import + the AC③
// hardened fixture, all machine-checked:
//
//   AC③  the synthetic C1-Session fixture (real directory shape +
//        .ARW/.ARW.xmp pairs + noise + a sub-tree ARW, SYNTHETIC bytes
//        only — the user ruling) imports EXACTLY the RAW count, never the
//        doubled file count, with precise typed rejection counts.
//   move same-volume rename (source leaves, sidecars ride); the RED PIN:
//        a cross-volume move with an injected verify failure leaves the
//        source file in place, writes NO row, counts one failure.
//   copy  per-file verify; duplicate bytes → skip; same name different
//        bytes → `-1` avoidance; progress monotonic.
//   link  source untouched, kind1/UUID row, `.lra` stays at origin (⑤).
//   cancel at a per-file checkpoint → rows == placed files (no ghosts).
//   EXIF  materialized columns filled through the M2-2-1 indexer seam.
//
// Fixtures in NSTemporaryDirectory (L009); the cross-volume leg rides the
// uuidProbe seam, never real hardware.
// ─────────────────────────────────────────────────────────────────────────────

final class ImportServiceTests: XCTestCase {

    private var root: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var service: ImportService!

    override func setUp() async throws {
        try await super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        packageURL = root.appendingPathComponent("Proj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Proj")
        service = ImportService(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Fixture helpers

    /// Deterministic pseudo-random bytes (synthetic only — the fixture
    /// ruling forbids user photos).
    nonisolated private static func syntheticBytes(seed: UInt8, count: Int = 4096) -> Data {
        Data((0..<count).map { (index: Int) -> UInt8 in
            (seed &* 31 &+ UInt8(truncatingIfNeeded: index)) % 251
        })
    }

    // MARK: - M6-2-01 T4 (KD-7 ②): the AI-copy birth sidecar stamps .current

    func testAICopyBirthSidecarStampsCurrentProcess() async throws {
        // A copy already placed under Media/ (the EnhanceCopyWriter's
        // half is the writer's domain — the twin takes it from here).
        let media = packageDirectory.appendingPathComponent(
            LibrarySchema.mediaDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: media, withIntermediateDirectories: true)
        let copy = media.appendingPathComponent("DSC09991-增强.tif")
        try Self.syntheticBytes(seed: 9).write(to: copy)

        let provenance = SidecarAIProvenanceRecord(
            operation: .upscale, scale: 4, amount: 0,
            sourceFile: "DSC09991.tif",
            sourceImageID: "6F1D2FB2-7A34-4C1E-9E8A-55B0C3A1D2E4",
            backend: "coreml-worker")
        _ = try await service.importFile(
            at: copy, projectDirectory: packageDirectory, albumID: nil,
            aiProvenance: provenance)

        let sidecarURL = LightamerSidecar.sidecarURL(for: copy)
        let data = try Data(contentsOf: sidecarURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["process"] as? Int, 1, "the AI-copy birth stamp")
        let document = try JSONDecoder().decode(LightamerSidecar.self, from: data)
        XCTAssertEqual(document.process, .current)
        XCTAssertEqual(document.aiProvenance, provenance)
        XCTAssertTrue(document.history.items.isEmpty, "the copy starts pristine")
        XCTAssertFalse(document.driftDetected)
    }

    @discardableResult
    private func makeFile(_ path: String, bytes: Data) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    /// The AC③ fixture: a synthetic C1-Session-SHAPED folder — `Capture/
    /// RAW/` with six .ARW + their .ARW.xmp pairs, two .tif noise files,
    /// one dot-hidden file, and one deeper sub-tree .ARW. All bytes are
    /// synthetic (the user ruling: structure fidelity, no real photos).
    private func makeC1SessionFixture(name: String) throws -> URL {
        let session = root.appendingPathComponent(name, isDirectory: true)
        for index in 1...6 {
            let raw = session.appendingPathComponent(
                "Capture/RAW/DSC0000\(index).ARW")
            try FileManager.default.createDirectory(
                at: raw.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.syntheticBytes(seed: UInt8(index)).write(to: raw)
            try Self.syntheticBytes(seed: UInt8(index + 100))
                .write(to: session.appendingPathComponent(
                    "Capture/RAW/DSC0000\(index).ARW.xmp"))
        }
        try FileManager.default.createDirectory(
            at: session.appendingPathComponent("Capture/Preview"),
            withIntermediateDirectories: true)
        try Self.syntheticBytes(seed: 200, count: 512)
            .write(to: session.appendingPathComponent("Capture/Preview/shot1.tif"))
        try Self.syntheticBytes(seed: 201, count: 512)
            .write(to: session.appendingPathComponent("Capture/Preview/shot2.tif"))
        try Data([0x2E]).write(to: session.appendingPathComponent("Capture/RAW/.hidden"))
        try FileManager.default.createDirectory(
            at: session.appendingPathComponent("Capture/RAW/Selects"),
            withIntermediateDirectories: true)
        try Self.syntheticBytes(seed: 7)
            .write(to: session.appendingPathComponent("Capture/RAW/Selects/DSC00007.ARW"))
        return session
    }

    private func makePlan(
        sourceFolder: URL, mode: ImportMode,
        whitelist: Set<String> = LibrarySchema.defaultRawExtensions
    ) async throws -> ImportPlan {
        // M4-1-02 T5 registration: the C1 fixture contract pins the
        // RAW-ONLY era count (7 RAWs, 2 .tif noise typed-rejected) — the
        // helper pins `categories: .raw` so the fixture math stays exact
        // under the OQ-5 double-on default. The double-on flip face lives
        // in ImportCategoryTests / the flipped ImportFilterTests row.
        try await service.makePlan(
            sourceFolder: sourceFolder, projectDirectory: packageDirectory,
            mode: mode, whitelist: whitelist, categories: .raw)
    }

    private var packageDirectory: URL {
        packageURL.deletingLastPathComponent()
    }

    private func imageCount() throws -> Int {
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        let statement = try handle.prepare("SELECT COUNT(*) FROM images")
        try XCTAssertTrue(statement.step())
        return Int(statement.columnInt(0) ?? 0)
    }

    private func mediaFiles() throws -> [String] {
        let media = packageDirectory.appendingPathComponent("Media", isDirectory: true)
        guard FileManager.default.fileExists(atPath: media.path) else { return [] }
        // Relative-component walk (spelling-immune — the manager resolves
        // the /var firmlink to /private/var inside directory listings, so
        // prefix-cutting absolute paths is unsound; see the Core scanner).
        var paths: [String] = []
        let fm = FileManager.default
        func walk(_ directory: URL, relative: String) {
            let children = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [])) ?? []
            for child in children {
                let childRelative = relative.isEmpty
                    ? child.lastPathComponent
                    : relative + "/" + child.lastPathComponent
                let isDirectory = (try? child.resourceValues(
                    forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    walk(child, relative: childRelative)
                } else {
                    paths.append(childRelative)
                }
            }
        }
        walk(media, relative: "")
        return paths.sorted()
    }

    // MARK: - AC③ (the synthetic C1-Session fixture)

    func testC1SessionFixtureImportsExactlyTheRawCount() async throws {
        // The Alcedo 0.3.0 defect shape: 16 files on disk (6+1 RAW, 6
        // xmp sidecars, 2 tif noise, 1 hidden) — the import must land
        // EXACTLY the 7 RAWs, sidecars riding as ⑤, noise rejected typed.
        let session = try makeC1SessionFixture(name: "SessionAlpha")
        let plan = try await makePlan(sourceFolder: session, mode: .copy)

        XCTAssertEqual(plan.items.count, 7, "only the RAWs pass the filter")
        let byReason = Dictionary(grouping: plan.rejected, by: \.reason)
        XCTAssertEqual(byReason[.sidecar]?.count, 6, "the six .ARW.xmp pairs")
        // M4-1-02 T5: with the RAW-only category face the two .tif noise
        // files account as `.excludedType` (the family-mask account, NOT
        // the whitelist account — the OQ-7 分账).
        XCTAssertEqual(byReason[.excludedType]?.count, 2, "the two .tif noise")
        XCTAssertEqual(byReason[.hidden]?.count, 1, "the dot-hidden file")

        let outcome = try await service.importFolder(plan)
        XCTAssertEqual(outcome.imported, 7)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.skippedDuplicates, 0)
        XCTAssertFalse(outcome.cancelled)
        let rows = try imageCount()
        XCTAssertEqual(rows, 7, "imported count == RAW count, never the file count")

        // The source-subtree shape survives under Media/<session>/, with
        // the six .xmp sidecars riding ⑤ (one per paired RAW — DSC00007
        // has none): 7 ARW + 6 xmp = 13 placed files.
        let files = try mediaFiles()
        XCTAssertTrue(files.contains("SessionAlpha/Capture/RAW/DSC00001.ARW"))
        XCTAssertTrue(files.contains("SessionAlpha/Capture/RAW/Selects/DSC00007.ARW"))
        XCTAssertEqual(files.count, 13)
        XCTAssertEqual(files.filter { $0.hasSuffix(".ARW") }.count, 7)
        XCTAssertEqual(files.filter { $0.hasSuffix(".ARW.xmp") }.count, 6)
    }

    // MARK: - Move (M2LIB-07①)

    func testMoveSameVolumeRenamesAndSidecarsRideAlong() async throws {
        let raw = try makeFile(
            "SessionBeta/Capture/RAW/DSC00001.ARW",
            bytes: Self.syntheticBytes(seed: 11))
        let lra = try makeFile(
            "SessionBeta/Capture/RAW/DSC00001.ARW.lra", bytes: Data([0x4C]))
        let xmp = try makeFile(
            "SessionBeta/Capture/RAW/DSC00001.ARW.xmp", bytes: Data([0x58]))
        let originalBytes = try Data(contentsOf: raw)

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionBeta", isDirectory: true),
            mode: .move)
        let outcome = try await service.importFolder(plan)

        XCTAssertEqual(outcome.imported, 1)
        XCTAssertEqual(outcome.failed, 0)
        // The source tree is GONE (rename semantics)…
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lra.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path))
        // …and the placement + sidecars landed under Media/.
        let placed = packageDirectory.appendingPathComponent(
            "Media/SessionBeta/Capture/RAW/DSC00001.ARW")
        XCTAssertTrue(FileManager.default.fileExists(atPath: placed.path))
        XCTAssertEqual(try Data(contentsOf: placed), originalBytes, "byte-faithful")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: placed.path + ".lra", isDirectory: nil))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: placed.path + ".xmp", isDirectory: nil))
        XCTAssertEqual(try imageCount(), 1)
    }

    /// THE RED PIN (M2LIB-07①): a cross-volume move whose verify FAILS
    /// must leave the source file in place, write NO row, and count one
    /// failure — 校验通过前永不删源.
    func testMoveCrossVolumeVerifyFailureNeverRemovesSource() async throws {
        let raw = try makeFile(
            "SessionGamma/Capture/RAW/DSC00001.ARW",
            bytes: Self.syntheticBytes(seed: 12))
        try makeFile(
            "SessionGamma/Capture/RAW/DSC00001.ARW.lra", bytes: Data([0x4C]))

        // Force the cross-volume leg without real hardware.
        await service.setUUIDProbe { url in
            url.path.contains("SessionGamma") ? "vol-src" : "vol-proj"
        }
        // Inject the failing verify (the plan's verifyStrategy seam).
        await service.setVerifyStrategy { _, _ in false }

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionGamma", isDirectory: true),
            mode: .move)
        let outcome = try await service.importFolder(plan)

        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.imported, 0)
        // THE RED LINE: the source photo + its sidecar still stand.
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path + ".lra"))
        XCTAssertEqual(try Data(contentsOf: raw), Self.syntheticBytes(seed: 12))
        // No row (no ghost), no half-placed bytes under Media/.
        XCTAssertEqual(try imageCount(), 0)
        XCTAssertEqual(try mediaFiles(), [])
    }

    func testMoveCrossVolumeSuccessRemovesSourceOnlyAfterVerify() async throws {
        let raw = try makeFile(
            "SessionDelta/Capture/RAW/DSC00001.ARW",
            bytes: Self.syntheticBytes(seed: 13))
        await service.setUUIDProbe { url in
            url.path.contains("SessionDelta") ? "vol-src" : "vol-proj"
        }
        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionDelta", isDirectory: true),
            mode: .move)
        let outcome = try await service.importFolder(plan)
        XCTAssertEqual(outcome.imported, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path),
                       "verified placement → the source may leave")
        let placed = packageDirectory.appendingPathComponent(
            "Media/SessionDelta/Capture/RAW/DSC00001.ARW")
        XCTAssertEqual(try Data(contentsOf: placed), Self.syntheticBytes(seed: 13))
    }

    // MARK: - Copy (M2LIB-07②)

    func testCopyDuplicatesSkipAndNameClashAvoids() async throws {
        // First import: run1/Card/DSC00001.ARW (bytes X).
        try makeFile("run1/Card/DSC00001.ARW", bytes: Self.syntheticBytes(seed: 21))
        let plan1 = try await makePlan(
            sourceFolder: root.appendingPathComponent("run1/Card", isDirectory: true),
            mode: .copy)
        let outcome1 = try await service.importFolder(plan1)
        XCTAssertEqual(outcome1.imported, 1)

        // Second import of IDENTICAL bytes → duplicate skip (no copy, no
        // row, no -1 sibling).
        let plan2 = try await makePlan(
            sourceFolder: root.appendingPathComponent("run1/Card", isDirectory: true),
            mode: .copy)
        let outcome2 = try await service.importFolder(plan2)
        XCTAssertEqual(outcome2.imported, 0)
        XCTAssertEqual(outcome2.skippedDuplicates, 1)
        XCTAssertEqual(try imageCount(), 1)
        XCTAssertEqual(try mediaFiles(), ["Card/DSC00001.ARW"])

        // Same name, DIFFERENT bytes (a same-named folder in another run)
        // → the `-1` avoidance.
        try makeFile("run2/Card/DSC00001.ARW", bytes: Self.syntheticBytes(seed: 22))
        let plan3 = try await makePlan(
            sourceFolder: root.appendingPathComponent("run2/Card", isDirectory: true),
            mode: .copy)
        let outcome3 = try await service.importFolder(plan3)
        XCTAssertEqual(outcome3.imported, 1)
        XCTAssertEqual(try imageCount(), 2)
        XCTAssertEqual(
            try mediaFiles(),
            ["Card/DSC00001-1.ARW", "Card/DSC00001.ARW"],
            "the clashing copy lands beside the original as <stem>-1")
    }

    func testCopyProgressIsMonotonicAndCompletes() async throws {
        let session = try makeC1SessionFixture(name: "SessionEpsilon")
        let plan = try await makePlan(sourceFolder: session, mode: .copy)

        let snapshots = ImportProgressRecorder()
        await service.setProgressHandler { snapshot in
            await snapshots.record(snapshot)
        }
        let outcome = try await service.importFolder(plan)
        XCTAssertEqual(outcome.imported, 7)

        let history = await snapshots.history
        XCTAssertFalse(history.isEmpty)
        var seen = 0
        for snapshot in history {
            XCTAssertLessThanOrEqual(
                snapshot.processed, snapshot.total,
                "processed may never exceed total")
            XCTAssertGreaterThanOrEqual(snapshot.processed, seen, "monotonic")
            seen = snapshot.processed
        }
        let final = try XCTUnwrap(history.last)
        XCTAssertEqual(final.phase, .completed)
        XCTAssertEqual(final.processed, 7)
        XCTAssertEqual(final.total, 7)
    }

    /// AC⑦'s failure leg: a sidecar migration failure fails the WHOLE
    /// file and rolls back the already-placed bytes (no row, source
    /// intact) — the ⑤ transactional semantics.
    func testCopySidecarFailureRollsBackPlacedBytes() async throws {
        let raw = try makeFile(
            "SessionIota/Capture/RAW/DSC00001.ARW",
            bytes: Self.syntheticBytes(seed: 41))
        try makeFile(
            "SessionIota/Capture/RAW/DSC00001.ARW.lra", bytes: Data([0x4C]))
        // A DIRECTORY occupies the sidecar's destination — copyItem
        // refuses an existing destination, forcing the migration failure.
        let mediaRaw = packageDirectory.appendingPathComponent(
            "Media/SessionIota/Capture/RAW", isDirectory: true)
        try FileManager.default.createDirectory(
            at: mediaRaw, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: mediaRaw.appendingPathComponent("DSC00001.ARW.lra"),
            withIntermediateDirectories: true)

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionIota", isDirectory: true),
            mode: .copy)
        let outcome = try await service.importFolder(plan)

        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.imported, 0)
        // The source + its sidecar stand; NO placed bytes, NO row.
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path + ".lra"))
        XCTAssertEqual(try mediaFiles(), [], "the placed bytes rolled back")
        XCTAssertEqual(try imageCount(), 0)
    }

    // MARK: - Link (M2LIB-07③ + ⑤)

    func testLinkLeavesSourceAndSidecarInPlaceWithKindRow() async throws {
        let raw = try makeFile(
            "SessionZeta/Capture/RAW/DSC00001.ARW",
            bytes: Self.syntheticBytes(seed: 31))
        try makeFile(
            "SessionZeta/Capture/RAW/DSC00001.ARW.lra", bytes: Data([0x4C]))

        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionZeta", isDirectory: true),
            mode: .link)
        let outcome = try await service.importFolder(plan)

        XCTAssertEqual(outcome.imported, 1)
        // The source + its sidecar NEVER move (⑤: link points at origin).
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path + ".lra"))
        XCTAssertEqual(try mediaFiles(), [], "no bytes land in Media/")
        XCTAssertEqual(try imageCount(), 1)

        // The row carries the same-volume (kind1) record and resolves.
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        let statement = try handle.prepare(
            "SELECT image_path, path_kind, volume_uuid FROM images")
        try XCTAssertTrue(statement.step())
        let imagePath = statement.columnText(0) ?? ""
        let pathKind = statement.columnInt(1) ?? -1
        let volumeUUID = statement.columnText(2)
        XCTAssertEqual(pathKind, 1, "same volume → kind1 volume-relative")
        XCTAssertEqual(
            volumeUUID, ImageLinker.volumeUUID(of: packageDirectory))
        XCTAssertFalse(imagePath.hasPrefix("Media/"), "link rows are not Media rows")

        let resolution = ImageLinker.resolve(
            imagePath: imagePath, pathKind: .volumeRelative,
            volumeUUID: volumeUUID, projectDirectory: packageDirectory)
        // Same-FILE assertion (spelling-immune: the scan root's firmlink
        // resolution may store the /private/var spelling, which resolves
        // through the Data-volume mount spelling — one file, one inode).
        guard case .resolved(let resolvedURL) = resolution else {
            return XCTFail("expected resolved, got \(resolution)")
        }
        let expectedID = try raw.resourceValues(forKeys: [.fileIdentifierKey])
            .fileIdentifier
        let resolvedID = try resolvedURL.resourceValues(forKeys: [.fileIdentifierKey])
            .fileIdentifier
        XCTAssertEqual(resolvedID, expectedID, "resolve lands on the same file")
    }

    /// The volume-stable inode identity (same volume → same file).
    private func fileIdentifier(_ url: URL) throws -> UInt64? {
        try url.resourceValues(forKeys: [.fileIdentifierKey]).fileIdentifier
    }

    // MARK: - R13 link-import regression (lumen-culling acceptance major-1)

    /// The lumen-culling acceptance major-1 shape: an 8-file TIFF source
    /// under the dialog's double-on category mask, imported through the
    /// LINK leg. The real-machine report (Link×4 → `images COUNT(*)=0`)
    /// could NOT be reproduced at HEAD — the probe chain AND the full GUI
    /// sheet flow (⌘I → Link → Import → AI ask → Not Now → quit) both land
    /// 8/8 rows (`.work/gsd/phases/r13-repairs` evidence). This test pins
    /// the chain the report observed breaking: rows land, the outcome
    /// feeds runImport's AI-tail precondition, and every kind1 row
    /// resolves to the original file.
    func testLinkImportTiffThroughDoubleOnMaskLandsRowsAndAIPrecondition() async throws {
        let fx = try makeTiffFolder(name: "fx", count: 8)
        let plan = try await service.makePlan(
            sourceFolder: fx, projectDirectory: packageDirectory,
            mode: .link, whitelist: LibrarySchema.defaultRawExtensions,
            categories: .all)
        XCTAssertEqual(plan.items.count, 8, "the double-on mask admits all 8 TIFFs")
        let outcome = try await service.importFolder(plan)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.imported, 8)
        XCTAssertEqual(try imageCount(), 8)

        // The AI-tail precondition (runImport's `newImageIDs` query): the
        // rows the import added are the whole table here.
        let allIDs = try await AIAnalysisQueries.imageIDs(in: fileStore, afterRowID: 0)
        XCTAssertEqual(allIDs.count, 8)

        // Every row resolves to the ORIGINAL file (kind1 volume-relative).
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        let statement = try handle.prepare(
            "SELECT image_path, path_kind, volume_uuid FROM images ORDER BY id")
        var resolved = 0
        while try statement.step() {
            XCTAssertEqual(statement.columnInt(1) ?? -1, 1, "kind1 volume-relative")
            let resolution = ImageLinker.resolve(
                imagePath: statement.columnText(0) ?? "",
                pathKind: .volumeRelative,
                volumeUUID: statement.columnText(2),
                projectDirectory: packageDirectory)
            guard case .resolved = resolution else {
                return XCTFail("link row did not resolve: \(resolution)")
            }
            resolved += 1
        }
        XCTAssertEqual(resolved, 8)
    }

    /// The report's session sequence: the same source imported by COPY
    /// first (the 8/8 round), then LINK — the link batch must ADD rows
    /// (count doubles), the copy rows stay kind0/Media, and the AI tail
    /// sees exactly the link delta. Guards the family where a link batch
    /// could collide with or evict an existing copy batch.
    func testLinkImportAfterCopyBatchAddsRowsWithoutDisturbingCopyRows() async throws {
        let fx = try makeTiffFolder(name: "fx2", count: 8)
        let copyPlan = try await service.makePlan(
            sourceFolder: fx, projectDirectory: packageDirectory,
            mode: .copy, whitelist: LibrarySchema.defaultRawExtensions,
            categories: .all)
        let copyOutcome = try await service.importFolder(copyPlan)
        XCTAssertEqual(copyOutcome.imported, 8)
        XCTAssertEqual(try imageCount(), 8)

        let beforeMax = try await AIAnalysisQueries.maxImageRowID(in: fileStore)
        let linkPlan = try await service.makePlan(
            sourceFolder: fx, projectDirectory: packageDirectory,
            mode: .link, whitelist: LibrarySchema.defaultRawExtensions,
            categories: .all)
        let linkOutcome = try await service.importFolder(linkPlan)
        XCTAssertEqual(linkOutcome.imported, 8, "link rows land beside the copy batch")
        XCTAssertEqual(linkOutcome.skippedDuplicates, 0,
                       "link has no Media placement duplicate check to trip")
        XCTAssertEqual(try imageCount(), 16)

        let newIDs = try await AIAnalysisQueries.imageIDs(in: fileStore, afterRowID: beforeMax)
        XCTAssertEqual(newIDs.count, 8, "the AI ask precondition sees the link delta")

        // The copy batch keeps its kind0 Media rows; the link batch is kind1.
        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        let statement = try handle.prepare(
            "SELECT path_kind, COUNT(*) FROM images GROUP BY path_kind ORDER BY path_kind")
        var kinds: [Int: Int] = [:]
        while try statement.step() {
            kinds[Int(statement.columnInt(0) ?? -1)] = Int(statement.columnInt(1) ?? 0)
        }
        XCTAssertEqual(kinds[0], 8, "copy rows untouched")
        XCTAssertEqual(kinds[1], 8, "link rows landed")
    }

    /// Minimal valid TIFF files (8×8 RGBA through ImageIO) — real
    /// ImageIO-encodable bytes so `fillMetadata`'s property read rides the
    /// true path (the acceptance's fx source was EXIF-carrying TIFF).
    private func makeTiffFolder(name: String, count: Int) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        for index in 0..<count {
            let width = 8, height = 8
            var pixels = [UInt8]()
            for pixel in 0..<(width * height * 4) {
                pixels.append((UInt8(index &* 7 &+ 11)
                    &* 31 &+ UInt8(truncatingIfNeeded: pixel)) % 251)
            }
            let provider = CGDataProvider(data: pixels.withUnsafeBytes {
                Data($0) as CFData
            })!
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)!
            let out = NSMutableData()
            let destination = CGImageDestinationCreateWithData(
                out, "public.tiff" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            try Data(out as Data).write(to: folder.appendingPathComponent(
                String(format: "FX_%03d.tif", index)))
        }
        return folder
    }

    // MARK: - Cancel (KD-4 generation semantics)

    func testCancelAtPerFileCheckpointLeavesNoGhostRows() async throws {
        let session = try makeC1SessionFixture(name: "SessionEta")
        let plan = try await makePlan(sourceFolder: session, mode: .copy)

        // Cancel as soon as the second file completes: the handler runs
        // INSIDE the actor's await, so cancel() lands before the next
        // checkpoint — the result is deterministic (2 processed).
        let capturedService = service!
        await capturedService.setProgressHandler { snapshot in
            if snapshot.processed >= 2 {
                await capturedService.cancel()
            }
        }
        let outcome = try await capturedService.importFolder(plan)
        await capturedService.setProgressHandler(nil)

        XCTAssertTrue(outcome.cancelled)
        XCTAssertEqual(outcome.imported, 2, "rows == processed")
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(try imageCount(), 2, "no ghost rows")
        XCTAssertEqual(try mediaFiles().filter { $0.hasSuffix(".ARW") }.count, 2,
                       "placed files == rows")
    }

    // MARK: - EXIF (KD-6: the M2-2-1 indexer seam, no re-invented keys)

    func testImportFillsExifMaterializedColumns() async throws {
        // A synthetic JPEG-with-EXIF saved under an .ARW name: ImageIO
        // reads properties by CONTENT, the whitelist gates by extension —
        // both faces exercised with zero real-camera bytes.
        let bytes = try XCTUnwrap(Self.exifJPEGBytes(), "EXIF JPEG synthesis")
        try makeFile("SessionTheta/Capture/RAW/DSC00050.ARW", bytes: bytes)
        let plan = try await makePlan(
            sourceFolder: root.appendingPathComponent("SessionTheta", isDirectory: true),
            mode: .copy)
        let outcome = try await service.importFolder(plan)
        XCTAssertEqual(outcome.imported, 1)

        let handle = try SQLiteHandle(path: packageURL.path)
        defer { handle.close() }
        let statement = try handle.prepare(
            "SELECT camera_make, camera_model, iso, focal_length, aperture,"
                + " capture_date, exif_search_words FROM images")
        try XCTAssertTrue(statement.step())
        XCTAssertEqual(statement.columnText(0), "TestCam")
        XCTAssertEqual(statement.columnText(1), "X-100")
        XCTAssertEqual(statement.columnInt(2), 400)
        XCTAssertEqual(statement.columnDouble(3) ?? 0, 35.0, accuracy: 0.001)
        XCTAssertEqual(statement.columnDouble(4) ?? 0, 2.8, accuracy: 0.001)
        XCTAssertNotNil(statement.columnDouble(5), "capture_date materialized")
        let words = statement.columnText(6) ?? ""
        XCTAssertTrue(words.contains("iso400"), "folded words face, got: \(words)")
        XCTAssertTrue(words.contains("testcam"), "the stem+facts fold, got: \(words)")
    }

    /// A 4×4 JPEG carrying EXIF (TIFF Make/Model, ISO, focal, aperture,
    /// DateTimeOriginal, LensModel) — fully synthetic.
    nonisolated private static func exifJPEGBytes() -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = context.makeImage() else { return nil }
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "TestCam",
            kCGImagePropertyTIFFModel: "X-100",
        ]
        let exif: [CFString: Any] = [
            kCGImagePropertyExifISOSpeedRatings: [400],
            kCGImagePropertyExifFocalLength: 35.0,
            kCGImagePropertyExifFNumber: 2.8,
            kCGImagePropertyExifLensModel: "Test 35mm",
            kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05",
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImagePropertyExifDictionary: exif,
        ]
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

/// Thread-safe snapshot collector (the handler is @Sendable); named apart
/// from SessionBatchApplierTests' class recorder (same test module).
private actor ImportProgressRecorder {
    private(set) var history: [ImportProgress] = []
    func record(_ snapshot: ImportProgress) {
        history.append(snapshot)
    }
}
