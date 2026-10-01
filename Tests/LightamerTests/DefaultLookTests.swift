import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// DefaultLookTests (Plan M2-5-2 T7, KD-5 / checker E5) — the product default
// look injection over the REAL load chain (EditorState + PipeCoordinator +
// a real RAW decode):
//
//   ① flag=1 + no .lra → ONE AdjustmentLayer minted with the three
//     GradeCatalog.defaultLook instances (+1.5 EV / +15 / 1.3), EXACTLY ONE
//     history item, and — E5 double assertion #1 — a forced flushNow()
//     leaves the disk WITHOUT a `.lra` (persist zero-scheduling proof);
//   ② E5 double assertion #2: ONE undo steps back to pristine;
//   ③ flag=1 + .lra present → restore wins, ZERO injection;
//   ④ flag=0 → ZERO injection; a user-built grade = EMPTY chain (identity);
//   ⑤ the AC#9 `.lalb` v1→v3 migration: hand-rolled v1 package →
//     open → the pre-migration sqlite3_backup snapshot (generation-named,
//     M2-8-1 E2) + user_version 3 + the idempotent additive column + old
//     rows flag 0 + new imports 1.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class DefaultLookTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!

    /// The repo-root real sample (the GUI-22 fixture path — skips when a
    /// checkout lacks it).
    private var sampleSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("input/RAW/DSC00012.ARW")
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("defaultlook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: sampleSourceURL.path) else {
            throw XCTSkip("default-look real-sample fixture missing: \(sampleSourceURL.path)")
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)

        editorState = EditorState()
        coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - the load harness (the real decode chain)

    /// Copy the sample in and run the REAL load with the pending flag; the
    /// mint runs inside the decode task after the pipe's sidecar probe.
    private func loadSample(pending: Bool) throws -> URL {
        let url = tempDirectory.appendingPathComponent("sample.ARW")
        try FileManager.default.copyItem(at: sampleSourceURL, to: url)
        editorState.load(
            url: url, decoder: RAWDecoder(), metal: metal,
            logger: EditorState.decodeLogger, defaultLookPending: pending)
        return url
    }

    /// Wait for the decode task (the mint precedes the `isDecoding` clear).
    private func waitForLoad() async throws {
        try await waitFor(editorState)
    }

    /// A fresh state pair wired like setUp (the second-session leg).
    private func makeFreshStatePair() async throws -> (EditorState, PipeCoordinator) {
        let freshEditor = EditorState()
        let freshCoordinator = PipeCoordinator()
        freshEditor.attach(pipeCoordinator: freshCoordinator)
        freshCoordinator.attach(editorState: freshEditor)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        freshCoordinator.attach(registry: registry)
        return (freshEditor, freshCoordinator)
    }

    private func waitFor(_ state: EditorState) async throws {
        for _ in 0..<200 where state.isDecoding {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<20 { await Task.yield() }
        try XCTUnwrap(state.loadedImageURL, "the load never landed")
        if let error = state.decodeError {
            XCTFail("decode failed: \(error.localizedDescription)")
        }
    }

    private func sidecarURL(for url: URL) -> URL {
        LightamerSidecar.sidecarURL(for: url)
    }

    // MARK: - ①: the mint + E5 assertion #1 (flushNow → no .lra)

    func testPendingFlagMintsOneLayerThreeInstancesNoSidecar() async throws {
        let url = try loadSample(pending: true)
        try await waitForLoad()

        // ONE layer: the minted chain = exactly the three catalog ops at
        // the pinned default-look values.
        let layers = editorState.layerStack?.compositeLayers.compactMap {
            $0 as? AdjustmentLayer
        } ?? []
        XCTAssertEqual(layers.count, 1, "exactly ONE minted AdjustmentLayer")
        let chain = try XCTUnwrap(layers.first).chain
        XCTAssertEqual(
            Set(chain.map(\.opName)),
            [ExposureModule.opName, ContrastModule.opName, SaturationModule.opName])
        for record in chain {
            switch record.opName {
            case ExposureModule.opName:
                XCTAssertEqual(
                    try record.params(of: ExposureModule.self).exposure, 1.5,
                    accuracy: 1e-6)
            case ContrastModule.opName:
                XCTAssertEqual(
                    try record.params(of: ContrastModule.self).contrast, 15,
                    accuracy: 1e-6)
            case SaturationModule.opName:
                XCTAssertEqual(
                    try record.params(of: SaturationModule.self).saturation, 1.3,
                    accuracy: 1e-6)
            default:
                XCTFail("unexpected minted op \(record.opName)")
            }
        }

        // EXACTLY ONE history item (the single-commit construction).
        XCTAssertEqual(editorState.history.items.count, 1)

        // E5 double assertion #1: a FORCED flush leaves NO `.lra` — the
        // persist scheduler was never armed (the "`.lra` absence = unedited"
        // invariant holds constructively).
        await coordinator.flushSidecar()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sidecarURL(for: url).path),
            "the mint must never schedule a sidecar write")
    }

    // MARK: - ②: E5 assertion #2 (one undo → pristine)

    func testOneUndoStepsBackToPristine() async throws {
        let url = try loadSample(pending: true)
        try await waitForLoad()
        XCTAssertGreaterThanOrEqual(
            editorState.layerStack?.adjustmentLayers.count ?? 0, 1)
        XCTAssertTrue(editorState.performUndo())
        let layers = editorState.layerStack?.compositeLayers.compactMap {
            $0 as? AdjustmentLayer
        } ?? []
        XCTAssertTrue(
            layers.isEmpty, "one undo removes the minted grade — pristine again")
        // And the sidecar STILL does not exist (undo schedules nothing).
        await coordinator.flushSidecar()
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL(for: url).path))
    }

    // MARK: - ③: .lra present → restore wins (zero injection)

    func testSidecarPresenceSuppressesTheMint() async throws {
        // Session 1: mint, then CREATE a real edit (a second layer) and
        // flush — the `.lra` lands.
        let url = try loadSample(pending: true)
        try await waitForLoad()
        _ = editorState.addAdjustmentLayer()
        await coordinator.layerStackDidChange(persist: true)
        // The schedule rides a fire-and-forget task — let it land before
        // forcing the flush (flushNow writes only a PENDING document).
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<20 { await Task.yield() }
        await coordinator.flushSidecar()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL(for: url).path))
        let restoredName = try XCTUnwrap(
            editorState.layerStack?.compositeLayers.first?.name)

        // Session 2: a FRESH state pair re-opens the SAME url with the
        // flag still set — the restore must win (zero mint). BOTH halves
        // stay alive (the coordinator holds the editorState weakly — a
        // dropped coordinator silently detaches the whole pipe leg).
        let (freshEditor, freshCoordinator) = try await makeFreshStatePair()
        _ = freshCoordinator // keep-alive to test end
        freshEditor.load(
            url: url, decoder: RAWDecoder(), metal: metal,
            logger: EditorState.decodeLogger, defaultLookPending: true)
        try await waitFor(freshEditor)
        // The restored session carries the sidecar's TWO layers (the minted
        // one + the user's), and NO additional mint layer appeared.
        XCTAssertEqual(
            freshEditor.layerStack?.compositeLayers.count, 2,
            "restore wins over the flag — zero injection")
        XCTAssertEqual(
            freshEditor.layerStack?.compositeLayers.first?.name, restoredName)
    }

    // MARK: - ④: flag=0 → zero injection; a user grade = identity chain

    func testClearedFlagNeverMintsAndUserGradeStaysIdentity() async throws {
        let url = try loadSample(pending: false)
        try await waitForLoad()
        let layers = editorState.layerStack?.compositeLayers.compactMap {
            $0 as? AdjustmentLayer
        } ?? []
        XCTAssertTrue(layers.isEmpty, "flag=0 never mints (old imports)")
        // A user-built grade = EMPTY chain (identity) — the KD-5 letter.
        let layer = try XCTUnwrap(editorState.addAdjustmentLayer())
        XCTAssertTrue(layer.chain.isEmpty)
        _ = url
    }

    // MARK: - ⑤: the AC#9 .lalb v1→v2 first migration

    func testLibrarySchemaV1ToV2FirstMigration() async throws {
        // Hand-roll a v1 package: the 28-column images table + one row,
        // user_version stamped 1.
        let v1URL = tempDirectory.appendingPathComponent("legacy.lalb")
        let handle = try SQLiteHandle(path: v1URL.path)
        try handle.execute("PRAGMA journal_mode=WAL")
        try handle.execute("""
            CREATE TABLE images (
              id INTEGER PRIMARY KEY,
              image_path TEXT NOT NULL,
              path_kind INTEGER NOT NULL DEFAULT 0,
              volume_uuid TEXT,
              camera_make TEXT, camera_model TEXT, lens_model TEXT,
              iso INTEGER, focal_length REAL, aperture REAL, exposure REAL,
              capture_date REAL,
              file_stem TEXT, file_ext TEXT, exif_search_text TEXT,
              exif_search_words TEXT,
              rating INTEGER, color_label INTEGER, keywords TEXT,
              filename TEXT, dir TEXT, flag INTEGER, note TEXT,
              has_edits INTEGER, params_hash TEXT,
              ref_count INTEGER NOT NULL DEFAULT 0,
              added_time REAL, modified_time REAL
            )
            """)
        try handle.execute(
            "CREATE TABLE project_meta (key TEXT PRIMARY KEY, value TEXT)")
        let insert = try handle.prepare(
            "INSERT INTO images (image_path, path_kind) VALUES ('Media/legacy.ARW', 0)")
        _ = try insert.step()
        try LibrarySchema.writeUserVersion(1, to: handle)
        handle.close()

        // Open: the dispatch snapshots FIRST (the pre-migration backup —
        // dead at v1 until now), then the idempotent additive migration.
        let store = ProjectFileStore(at: v1URL)
        _ = try await store.open()
        let snapshotURL = v1URL.deletingPathExtension()
            .appendingPathExtension("pre-migrate.1-3.bak")  // M2-8-1 E2: generation-named
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "the pre-migration sqlite3_backup snapshot hook consumed")
        XCTAssertEqual(try readUserVersion(v1URL), 3)

        let library = LibraryStore(store: store)
        // The legacy row: flag 0 (old imports never mint).
        let legacyPending = try await library.defaultLookPending(imageRowID: 1)
        XCTAssertFalse(legacyPending)
        // A NEW import row: flag 1 (KD-5 — every new import carries it).
        let newID = try await library.insertImage(record: LibraryImageRecord(
            imagePath: "Media/new.ARW", pathKind: .projectRelative))
        let newPending = try await library.defaultLookPending(imageRowID: newID)
        XCTAssertTrue(newPending)
        // The clear face spends the marker (idempotent).
        try await library.clearDefaultLookPending(imageRowID: newID)
        let cleared = try await library.defaultLookPending(imageRowID: newID)
        XCTAssertFalse(cleared)
        // The migration is IDEMPOTENT: a second open (stored == 3) neither
        // re-runs it nor re-snapshots (the dispatch short-circuits).
        try await store.close()
        let reopened = ProjectFileStore(at: v1URL)
        _ = try await reopened.open()
        XCTAssertEqual(try readUserVersion(v1URL), 3)
        try await reopened.close()
    }

    /// The version read on a fresh read handle (WAL read alongside the
    /// store's connection is safe for the pragma).
    private func readUserVersion(_ url: URL) throws -> Int {
        let handle = try SQLiteHandle(path: url.path)
        defer { handle.close() }
        return try LibrarySchema.readUserVersion(from: handle)
    }
}
