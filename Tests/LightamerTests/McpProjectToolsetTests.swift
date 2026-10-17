import Foundation
import LightamerCore
import LightamerIOP
import MCP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// McpProjectToolsetTests (Plan M7-3-01 T5) — the FOURTH domain's snapshot
// layer + the single-writer lock arbitration fixture (ROADMAP §M7-3
// acceptance ②) + the list_versions golden (MCP2-07):
//
//   • the domain snapshot layer: three tools verbatim + the 27 分账 + the
//     whitelist negative + the writer/read annotation judgments;
//   • the arbitration fixture (the in-process dual-store flock shape —
//     flock arbitrates per OPEN FILE DESCRIPTION, so a second in-process
//     store genuinely holds the lock against the provider's open): held →
//     typed projectReadOnly with the holder pid; release → natural
//     recovery; the self-switch checkpoint leg; the create refusals; the
//     read-only host gate; the get_state immediacy (the per-call box
//     read); the A→B anchor leg (H2); the GUI provider predicate legs
//     (H4③ — the stub controller face); the M1 http-arm-absence leg;
//   • list_versions: the three-version projection (byte-equal), the
//     includeItems arms, the 500 cap keeping the NEWEST end per version,
//     the dual addressing, the ACTIVE chain ≡ get_history identity, the
//     pristine honest face, the dangling activeVersionID.
//
// The cross-process sequences A/B live in McpProjectArbitrationTests —
// ZERO diff there (the launch-path discipline; this file exercises the
// RUNTIME seam in-process).
// ─────────────────────────────────────────────────────────────────────────────

// The suite rides the MainActor (the GUI-predicate legs + the stub face
// are MainActor-shaped; the registry/provider calls hop as needed).
@MainActor
final class McpProjectToolsetTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mcp-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        // STDIN safety (the runtime stdio legs arm the REAL EOF watcher in
        // this process): point STDIN_FILENO at /dev/null so the armed
        // watcher polls a device that can never report HUP — the suite must
        // never self-exit. The real HUP→checkpoint→exit semantics ride the
        // two-process launch-path discipline (McpProjectArbitrationTests).
        let nullFD = open("/dev/null", O_RDWR)
        if nullFD >= 0 {
            dup2(nullFD, STDIN_FILENO)
            close(nullFD)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(at: extraDirectory)
    }

    /// A second workspace for the B package (the A→B switch legs).
    private var extraDirectory: URL {
        tempDirectory.appendingPathComponent("extra", isDirectory: true)
    }

    // MARK: - Fixtures

    /// Creates a real package and CLOSES it (the on-disk artifact the open
    /// face targets).
    private func makePackage(at url: URL, name: String) async throws {
        let store = ProjectFileStore(at: url)
        _ = try await store.create(name: name)
        try await store.close()
    }

    private var packageA: URL {
        tempDirectory.appendingPathComponent("Alpha.lalb")
    }

    private var packageB: URL {
        extraDirectory.appendingPathComponent("Beta.lalb")
    }

    /// The RUNTIME registry: the search/state context rides the BOX (the
    /// per-call face), the project context rides the Core-direct providers.
    /// This is the headless-arm assembly verbatim, in-process.
    private func makeRuntimeRegistry(mode: McpServerController.LaunchMode = .stdio)
        async -> McpToolRegistry
    {
        await McpServerController.makeRegistry(
            searchState: McpServerController.makeHeadlessSearchState(mode: mode),
            project: McpServerController.makeHeadlessProjectContext(mode: mode))
    }

    /// A registry with ONLY the project face (the domain snapshot layer).
    private func makeProjectOnlyRegistry() async -> McpToolRegistry {
        await McpServerController.makeRegistry(project: McpProjectContext())
    }

    private static func callJSON(
        _ registry: McpToolRegistry, name: String,
        arguments: [String: McpJSON] = [:], file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String: Any] {
        let output = try await registry.call(name: name, arguments: arguments)
        guard case .text(let text) = output.content.first else {
            XCTFail("expected a text payload", file: file, line: line)
            return [:]
        }
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any], file: file, line: line)
    }

    private static func toolError(
        of body: @escaping @Sendable () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> McpToolError {
        do {
            try await body()
        } catch let error as McpToolError {
            return error
        } catch {
            XCTFail("expected McpToolError, got \(error)", file: file, line: line)
            throw error
        }
        XCTFail("expected a McpToolError — the call succeeded", file: file, line: line)
        throw McpToolError.internalError("test harness: no error surfaced")
    }

    // MARK: - The domain snapshot layer

    /// The three tools verbatim (names + VERBATIM schemas + the annotation
    /// column) — the domain layer of the M7-3 union freeze (McpFinalSnapshot
    ///Tests carries the 27 count; this file asserts the DOMAIN layer).
    func testProjectDomainSnapshotVerbatim() async throws {
        let registry = await makeProjectOnlyRegistry()
        try await McpRegistrySnapshotTests.assertSnapshot(
            registry: registry,
            expected: [
                McpToolDescriptor(
                    name: "list_versions",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"image":{"type":"string","description":"A library image id (digits) or an open-session relPath"},"includeItems":{"type":"boolean","default":false,"description":"Attach each version's own item list (capped at the 500 NEWEST; the truncated flag rides per version)"}},"required":["image"]}"#,
                    readOnlyHint: true),
                McpToolDescriptor(
                    name: "project_create",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"folder":{"type":"string","description":"An EXISTING directory the package is created in"},"name":{"type":"string","minLength":1,"description":"The package name (folder/<name>.lalb; no path separators / colons / leading dots)"}},"required":["folder","name"]}"#),
                McpToolDescriptor(
                    name: "project_open",
                    description: "snapshot",
                    inputSchemaJSON:
                        #"{"type":"object","properties":{"path":{"type":"string","description":"The absolute path of the .lalb package to open"}},"required":["path"]}"#),
            ])
        let descriptors = await registry.descriptors()
        XCTAssertEqual(descriptors.count, 3, "the project domain is exactly 3 tools")
    }

    /// The writer/read annotations, executable: with the writer gate OFF the
    /// open/create pair dies at the gate (serverReadOnly) while
    /// list_versions serves straight through (the read-only exemption).
    func testProjectAnnotationsWriterGateExecutable() async throws {
        try await makePackage(at: packageA, name: "Alpha")
        let registry = await makeProjectOnlyRegistry()
        await registry.setWriterCheck { false }
        let openPath = packageA.path

        let openError = try await Self.toolError {
            _ = try await registry.call(name: "project_open", arguments: [
                "path": .string(openPath),
            ])
        }
        XCTAssertEqual(openError.code, "serverReadOnly",
                       "project_open rides the writer gate")

        let createTempPath = tempDirectory.path
        let createError = try await Self.toolError {
            _ = try await registry.call(name: "project_create", arguments: [
                "folder": .string(createTempPath),
                "name": .string("Whatever"),
            ])
        }
        XCTAssertEqual(createError.code, "serverReadOnly",
                       "project_create rides the writer gate")

        // list_versions: the read-only exemption (a bad image name still
        // reaches the handler and answers the typed addressing arm).
        let versionsError = try await Self.toolError {
            _ = try await registry.call(name: "list_versions", arguments: [
                "image": .string("Media/nowhere.arw"),
            ])
        }
        XCTAssertEqual(versionsError.code, "notSessionMember",
                       "list_versions serves THROUGH the false gate")
    }

    /// The whitelist negative: unknown names answer the typed internalError
    /// (the union precedent shape, domain-scoped).
    func testProjectDomainWhitelistNegative() async throws {
        let registry = await makeProjectOnlyRegistry()
        let error = try await Self.toolError {
            _ = try await registry.call(name: "project_delete", arguments: [:])
        }
        XCTAssertEqual(error.code, "internalError")
        XCTAssertTrue(error.message.contains("unknownTool"))
    }

    // MARK: - The arbitration fixture (in-process dual-store flock)

    /// Check-before-open (Alcedo 同构): a wrong path never reaches the
    /// provider — typed invalidParams carries the path; a bad suffix too.
    func testProjectOpenCheckBeforeOpen() async throws {
        // Order independence: the box is process-global — clear any parked
        // state from an earlier parking test.
        McpServerController.headlessProjectBox.set(.init(store: nil, url: nil, readOnly: false))
        let registry = await makeRuntimeRegistry()
        let missingPath = tempDirectory.appendingPathComponent("Nope.lalb").path
        let badPath = tempDirectory.appendingPathComponent("Nope.txt").path
        let missing = try await Self.toolError {
            _ = try await registry.call(name: "project_open", arguments: [
                "path": .string(missingPath),
            ])
        }
        XCTAssertEqual(missing.code, "invalidParams")
        XCTAssertTrue(missing.message.contains("Nope.lalb"))
        let badSuffix = try await Self.toolError {
            _ = try await registry.call(name: "project_open", arguments: [
                "path": .string(badPath),
            ])
        }
        XCTAssertEqual(badSuffix.code, "invalidParams")
        // The box stays empty (nothing parked, nothing half-open).
        let state = try await Self.callJSON(registry, name: "get_state")
        XCTAssertTrue(state["project"] is NSNull, "the box stays empty")
    }

    /// THE held leg (ROADMAP acceptance ②): a second in-process store holds
    /// the target's project lock (flock arbitrates per open file
    /// description, so this is a REAL held shape) → typed projectReadOnly
    /// carrying the holder summary with the REAL pid; the box stays empty.
    func testHeldTargetIsTypedProjectReadOnly() async throws {
        McpServerController.headlessProjectBox.set(.init(store: nil, url: nil, readOnly: false))
        try await makePackage(at: packageA, name: "Alpha")
        let holder = ProjectFileStore(at: packageA)
        _ = try await holder.open(role: .headless)
        defer { Task { try? await holder.close() } }

        let registry = await makeRuntimeRegistry()
        let heldPath = packageA.path
        let expectedPid = getpid()
        let error = try await Self.toolError {
            _ = try await registry.call(name: "project_open", arguments: [
                "path": .string(heldPath),
            ])
        }
        XCTAssertEqual(error.code, "projectReadOnly")
        XCTAssertTrue(
            error.message.contains("pid=\(expectedPid)"),
            "the holder summary carries the REAL pid: \(error.message)")
        // The box stays empty (the honest no-project state).
        let state = try await Self.callJSON(registry, name: "get_state")
        XCTAssertTrue(state["project"] is NSNull)
    }

    /// The natural-recovery leg: the holder exits (close) → the retry opens.
    func testReleaseThenOpenRecovers() async throws {
        try await makePackage(at: packageA, name: "Alpha")
        let holder = ProjectFileStore(at: packageA)
        _ = try await holder.open(role: .headless)
        try await holder.close()

        let registry = await makeRuntimeRegistry()
        let payload = try await Self.callJSON(registry, name: "project_open", arguments: [
            "path": .string(packageA.path),
        ])
        XCTAssertEqual(payload["path"] as? String, packageA.path)
        XCTAssertEqual(payload["name"] as? String, "Alpha")
        XCTAssertEqual(payload["readOnly"] as? Bool, false)
        XCTAssertEqual(payload["heldByOther"] as? Bool, false)
        // NO photo_count (D-M7-3-6 — the four-field summary).
        XCTAssertNil(payload["photo_count"], "the summary carries no photo count")
        // get_state immediacy: the box answers the SAME call's truth.
        let state = try await Self.callJSON(registry, name: "get_state")
        let project = try XCTUnwrap(state["project"] as? [String: Any])
        XCTAssertEqual(project["path"] as? String, packageA.path)
        XCTAssertEqual(project["readOnly"] as? Bool, false)
    }

    /// The self-switch checkpoint leg (open B while holding A): close A
    /// rides checkpoint, B parks, and BOTH the get_state project face and
    /// the library resolution anchor (H2) point at B.
    func testSelfSwitchClosesThenOpensWithAnchorFollowing() async throws {
        try await makePackage(at: packageA, name: "Alpha")
        try FileManager.default.createDirectory(at: extraDirectory, withIntermediateDirectories: true)
        try await makePackage(at: packageB, name: "Beta")

        let registry = await makeRuntimeRegistry()
        _ = try await Self.callJSON(registry, name: "project_open", arguments: [
            "path": .string(packageA.path),
        ])
        let before = try await Self.callJSON(registry, name: "get_state")
        XCTAssertEqual(
            (before["project"] as? [String: Any])?["path"] as? String,
            packageA.path)

        _ = try await Self.callJSON(registry, name: "project_open", arguments: [
            "path": .string(packageB.path),
        ])
        let after = try await Self.callJSON(registry, name: "get_state")
        XCTAssertEqual(
            (after["project"] as? [String: Any])?["path"] as? String,
            packageB.path, "the runtime switch is visible to the next call")
        // The H2 anchor leg: the library seam's projectDirectory follows the
        // BOX (projectRelative rows resolve against B's directory now).
        let library = try XCTUnwrap(
            McpServerController.makeHeadlessSearchState(mode: .stdio).library)
        let seam = try await library()
        XCTAssertEqual(
            try XCTUnwrap(seam).projectDirectory,
            packageB.deletingLastPathComponent(),
            "the resolution anchor follows the box (fix 20997721 same-family)")
        // The runtime open armed the stdio EOF leg exactly once.
        XCTAssertTrue(McpServerController.eofArmDone, "the runtime open armed the EOF leg")
    }

    /// The create refusals (typed invalidParams, three arms): an existing
    /// package, a missing folder, an empty/illegal name.
    func testCreateRefusalsAreTypedInvalidParams() async throws {
        try await makePackage(at: packageA, name: "Alpha")
        let registry = await makeRuntimeRegistry()
        let tempPath = tempDirectory.path

        let exists = try await Self.toolError {
            _ = try await registry.call(name: "project_create", arguments: [
                "folder": .string(tempPath),
                "name": .string("Alpha"),
            ])
        }
        XCTAssertEqual(exists.code, "invalidParams", "creating never overwrites")

        let gonePath = tempDirectory.appendingPathComponent("gone").path
        let noFolder = try await Self.toolError {
            _ = try await registry.call(name: "project_create", arguments: [
                "folder": .string(gonePath),
                "name": .string("Fresh"),
            ])
        }
        XCTAssertEqual(noFolder.code, "invalidParams")

        let emptyName = try await Self.toolError {
            _ = try await registry.call(name: "project_create", arguments: [
                "folder": .string(tempPath),
                "name": .string("  "),
            ])
        }
        XCTAssertEqual(emptyName.code, "invalidParams")

        let slashName = try await Self.toolError {
            _ = try await registry.call(name: "project_create", arguments: [
                "folder": .string(tempPath),
                "name": .string("a/b"),
            ])
        }
        XCTAssertEqual(slashName.code, "invalidParams")

        // The happy leg: create lands folder/<name>.lalb and parks the box.
        let created = try await Self.callJSON(registry, name: "project_create", arguments: [
            "folder": .string(tempDirectory.path),
            "name": .string("Fresh"),
        ])
        XCTAssertEqual(created["name"] as? String, "Fresh")
        XCTAssertEqual(
            created["path"] as? String,
            tempDirectory.appendingPathComponent("Fresh.lalb").path)
        let state = try await Self.callJSON(registry, name: "get_state")
        XCTAssertEqual(
            (state["project"] as? [String: Any])?["path"] as? String,
            tempDirectory.appendingPathComponent("Fresh.lalb").path)
    }

    /// The no-project null face on the empty box is the bare-context face
    /// byte-identical: project null AND the server fallback's hostMode null.
    func testBoxEmptyGetStateIsTheBareContextNullFace() async throws {
        McpServerController.headlessProjectBox.set(.init(store: nil, url: nil, readOnly: false))
        let registry = await makeRuntimeRegistry()
        let state = try await Self.callJSON(registry, name: "get_state")
        XCTAssertTrue(state["project"] is NSNull)
        XCTAssertTrue(state["workspace"] is NSNull)
        XCTAssertTrue(state["editor"] is NSNull)
        XCTAssertTrue(state["tasks"] is NSNull)
        let server = try XCTUnwrap(state["server"] as? [String: Any])
        XCTAssertEqual(server["name"] as? String, McpServerController.serverName)
        XCTAssertTrue(server["hostMode"] is NSNull, "the bare-context fallback face")
        XCTAssertTrue(server["readOnly"] is NSNull)
        let control = try XCTUnwrap(state["control"] as? [String: Any])
        XCTAssertTrue(control["lock"] is NSNull, "no probe on the headless project face")
    }

    /// The M1 leg (the http arm-absence): a runtime open captured on the
    /// http mode NEVER flips the EOF arm (an http daemon's stdin may already
    /// be closed — an unguarded poll would self-exit the daemon on the
    /// first open). The stdio arm's real body rides the launch-path
    /// two-process discipline via the shared extracted function.
    func testHttpModeRuntimeOpenArmsNothing() async throws {
        // Order-independence: an earlier stdio leg may have armed the
        // watcher — reset the once-flag so THIS leg's judgment is clean.
        McpServerController.eofArmDone = false
        try await makePackage(at: packageA, name: "Alpha")
        let context = McpServerController.makeHeadlessProjectContext(mode: .http)
        let open = try XCTUnwrap(context.openProject)
        let outcome = try await open(packageA)
        XCTAssertEqual(outcome.url, packageA)
        XCTAssertFalse(
            McpServerController.eofArmDone,
            "the http mode must never arm the stdio EOF watcher")
        // The guard itself: the arm called with http stays inert.
        McpServerController.armStdioEOFReleaseOnce(mode: .http)
        XCTAssertFalse(McpServerController.eofArmDone)
    }

    // MARK: - The GUI provider predicate legs (H4③ — the stub face)

    /// The GUI-embedded arm's provider PREDICATE (the LightamerApp closure
    /// shape) against a stub controller face: held-target pre-check BEFORE
    /// openProject + the before/after conflict diff. The controller FILE
    /// itself is zero-diff this wave — the predicate is verified here.
    /// `@unchecked Sendable`: every touch routes through MainActor (the
    /// closures hop explicitly) — the annotation silences the region
    /// isolation of holding the stub inside the @Sendable provider.
    @MainActor
    private final class StubProjectController: @unchecked Sendable {
        var projectStore: String?
        var projectURL: URL?
        var pendingConflict: URL?

        nonisolated init() {}

        /// The controller's real shape: a held target PUBLISHES the dialog
        /// (no throw) and leaves the store untouched.
        func openProject(at url: URL, heldTargets: Set<URL>) {
            if heldTargets.contains(url) {
                pendingConflict = url
                return
            }
            projectStore = url.path
            projectURL = url
            pendingConflict = nil
        }
    }

    /// The provider closure shape LightamerApp assembles (verbatim logic —
    /// the pre-check + the diff), factored for the stub legs.
    private static func makeGuiShapedProvider(
        stub: StubProjectController, heldTargets: Set<URL>
    ) -> @Sendable (URL) async throws -> ProjectOpenOutcome {
        { url in
            let lockURL = url.deletingPathExtension()
                .appendingPathExtension("lalb.lock")
            guard SingleWriterLock.probeLockAvailable(at: lockURL) else {
                throw McpToolError.projectReadOnly(
                    SingleWriterLock.holderSummary(at: lockURL))
            }
            let beforeStore = await MainActor.run { stub.projectStore }
            let beforeConflict = await MainActor.run { stub.pendingConflict }
            await MainActor.run { stub.openProject(at: url, heldTargets: heldTargets) }
            let afterConflict = await MainActor.run { stub.pendingConflict }
            let afterStore = await MainActor.run { stub.projectStore }
            // Value equality (the stub's store face is a String path; the
            // production closure compares the ProjectFileStore reference).
            if beforeConflict == nil, afterConflict != nil, afterStore == beforeStore {
                throw McpToolError.projectReadOnly(
                    SingleWriterLock.holderSummary(at: lockURL))
            }
            return ProjectOpenOutcome(url: url)
        }
    }

    /// H4③ leg 1: a held target B (its lock REALLY held by a second
    /// in-process store) is intercepted at the PRE-CHECK — typed
    /// projectReadOnly and the stub's open state STILL A (one agent call
    /// must not displace the user's open project).
    func testGuiProviderHeldTargetNeverDisplacesTheOpenProject() async throws {
        try await makePackage(at: packageA, name: "Alpha")
        try await makePackage(at: packageB, name: "Beta")
        let holder = ProjectFileStore(at: packageB)
        _ = try await holder.open(role: .headless)
        defer { Task { try? await holder.close() } }

        stubController.projectURL = packageA
        stubController.projectStore = packageA.path
        let provider = Self.makeGuiShapedProvider(stub: stubController, heldTargets: [])
        let heldBPath = packageB
        let error = try await Self.toolError {
            _ = try await provider(heldBPath)
        }
        XCTAssertEqual(error.code, "projectReadOnly")
        XCTAssertEqual(stubController.projectStore, packageA.path, "A stays open")
        XCTAssertEqual(stubController.projectURL, packageA, "get_state.project still指 A")
        XCTAssertNil(stubController.pendingConflict,
                     "the pre-check intercepted BEFORE the dialog")
    }

    /// H4③ leg 2 (the stale-dialog reverse false positive): a conflict from
    /// an EARLIER interaction is on record, then the open target is FREE →
    /// the diff must NOT fire — the open succeeds.
    func testGuiProviderStaleConflictDoesNotReverseMisfire() async throws {
        try await makePackage(at: packageB, name: "Beta")
        // A STALE dialog from an earlier interaction (before != nil).
        stubController.pendingConflict = packageA
        let provider = Self.makeGuiShapedProvider(stub: stubController, heldTargets: [])
        let outcome = try await provider(packageB)
        XCTAssertEqual(outcome.url, packageB, "the open succeeded past the stale dialog")
        XCTAssertEqual(stubController.projectStore, packageB.path)
        XCTAssertNil(stubController.pendingConflict)
    }

    /// S3 (M7-3 ledger ③, M7-4-01 T2): the POSITIVE arm of the diff
    /// predicate — a held target WITHOUT a real lock (the stub's dialog
    /// path: the held target publishes pendingConflict and leaves the
    /// store untouched) trips the full diff clause (before == nil ∧
    /// after != nil ∧ the store did not change) → typed projectReadOnly.
    /// The existing legs pass heldTargets: [] and can never reach this arm.
    func testGuiProviderHeldTargetDialogDiffFiresReadOnly() async throws {
        try await makePackage(at: packageA, name: "Alpha")
        try await makePackage(at: packageB, name: "Beta")
        stubController.projectURL = packageA
        stubController.projectStore = packageA.path
        XCTAssertNil(
            stubController.pendingConflict,
            "before == nil: no conflict dialog on record")
        let beforeStore = stubController.projectStore
        let heldTarget = packageB
        let provider = Self.makeGuiShapedProvider(
            stub: stubController, heldTargets: [heldTarget])
        let error = try await Self.toolError {
            _ = try await provider(heldTarget)
        }
        XCTAssertEqual(error.code, "projectReadOnly")
        XCTAssertNotNil(
            stubController.pendingConflict,
            "after != nil: the held target published the conflict dialog")
        XCTAssertEqual(
            stubController.projectStore, beforeStore,
            "the store did not change: the open store stayed A")
        XCTAssertEqual(stubController.projectStore, packageA.path, "A stays open")
    }

    private let stubController = StubProjectController()

    // MARK: - list_versions golden (MCP2-07)

    /// The version-tree fixture: a real .lalb + two golden sidecars.
    ///   - `golden.arw`: three versions (two chained + one ACTIVE) — the
    ///     projection byte-equal + includeItems arms + the ACTIVE ≡
    ///     get_history identity;
    ///   - `long.arw`: ONE non-active version with a 505-item chain — the
    ///     500 cap keeps the NEWEST end per version with the truncated flag;
    ///   - `pristine.arw`: no sidecar — the honest empty face;
    ///   - `dangling.arw`: an activeVersionID pointing OUTSIDE the versions
    ///     array — the structure rides the disk truth (no synthesis).
    private struct VersionFixture {
        var packageURL: URL
        var fileStore: ProjectFileStore
        var goldenID: Int64
        var longID: Int64
        var pristineID: Int64
        var danglingID: Int64
        var goldenVersions: [SidecarVersionRecord]
        var goldenHistory: HistoryStack
    }

    private func makeVersionFixture() async throws -> VersionFixture {
        let packageURL = tempDirectory.appendingPathComponent("Versions.lalb")
        let fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Versions")

        let exposure = ModuleInstance(
            module: ExposureModule.self, params: ExposureModule.Params())

        // ── golden.arw: the three-version shape. ──
        let goldenImageURL = tempDirectory.appendingPathComponent("Media/golden.arw")
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Media", isDirectory: true),
            withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 32).write(to: goldenImageURL)
        var goldenHistory = HistoryStack()
        goldenHistory.commit(exposure, label: "Exposure 2.0×")
        goldenHistory.commit(exposure, label: "Second edit")
        var chainA = HistoryStack()
        chainA.commit(exposure, label: "vA-1")
        chainA.commit(exposure, label: "vA-2")
        var chainB = HistoryStack()
        chainB.commit(exposure, label: "vB-1")
        let versions = [
            SidecarVersionRecord(
                id: UUID(), name: "Alt A",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 11), chain: chainA),
            SidecarVersionRecord(
                id: UUID(), name: "Alt B",
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 21), chain: chainB),
            SidecarVersionRecord(
                id: UUID(), name: "Main",
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 31), chain: nil),
        ]
        let goldenDoc = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "RAW8", decodeParamsHash: 7,
            instances: [exposure], history: goldenHistory, historyHash: 9,
            versions: versions,
            activeVersionID: versions[2].id.uuidString)
        try JSONEncoder().encode(goldenDoc).write(
            to: LightamerSidecar.sidecarURL(for: goldenImageURL))
        let goldenID = try await LibraryStore(store: fileStore).insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/golden.arw", pathKind: .projectRelative,
                fileStem: "golden", fileExt: "arw", filename: "golden.arw",
                dir: "Media"))

        // ── long.arw: a 505-item NON-ACTIVE chain (the 500 cap). ──
        let longImageURL = tempDirectory.appendingPathComponent("Media/long.arw")
        try Data(repeating: 0xCD, count: 32).write(to: longImageURL)
        var longChain = HistoryStack()
        for index in 0..<505 {
            longChain.commit(exposure, label: "edit \(index)")
        }
        let longDoc = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "RAW8", decodeParamsHash: 7,
            instances: [exposure], history: HistoryStack(), historyHash: 1,
            versions: [
                SidecarVersionRecord(
                    id: UUID(), name: "Long",
                    createdAt: Date(timeIntervalSince1970: 40),
                    updatedAt: Date(timeIntervalSince1970: 41), chain: longChain),
            ],
            activeVersionID: nil)
        try JSONEncoder().encode(longDoc).write(
            to: LightamerSidecar.sidecarURL(for: longImageURL))
        let longID = try await LibraryStore(store: fileStore).insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/long.arw", pathKind: .projectRelative,
                fileStem: "long", fileExt: "arw", filename: "long.arw",
                dir: "Media"))

        // ── pristine.arw: NO sidecar document. ──
        let pristineImageURL = tempDirectory.appendingPathComponent("Media/pristine.arw")
        try Data(repeating: 0xEF, count: 8).write(to: pristineImageURL)
        let pristineID = try await LibraryStore(store: fileStore).insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/pristine.arw", pathKind: .projectRelative,
                fileStem: "pristine", fileExt: "arw", filename: "pristine.arw",
                dir: "Media"))

        // ── dangling.arw: an activeVersionID outside the versions array. ──
        let danglingImageURL = tempDirectory.appendingPathComponent("Media/dangling.arw")
        try Data(repeating: 0xCD, count: 16).write(to: danglingImageURL)
        var danglingHistory = HistoryStack()
        danglingHistory.commit(exposure, label: "only")
        let danglingDoc = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "RAW8", decodeParamsHash: 3,
            instances: [exposure], history: danglingHistory, historyHash: 2,
            versions: [],
            activeVersionID: UUID().uuidString)
        try JSONEncoder().encode(danglingDoc).write(
            to: LightamerSidecar.sidecarURL(for: danglingImageURL))
        let danglingID = try await LibraryStore(store: fileStore).insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/dangling.arw", pathKind: .projectRelative,
                fileStem: "dangling", fileExt: "arw", filename: "dangling.arw",
                dir: "Media"))

        return VersionFixture(
            packageURL: packageURL, fileStore: fileStore,
            goldenID: goldenID, longID: longID, pristineID: pristineID,
            danglingID: danglingID, goldenVersions: versions,
            goldenHistory: goldenHistory)
    }

    /// The OQ-8 shape: the SAME closure variable rides BOTH contexts (the
    /// library seam is constructed ONCE here and assigned to both).
    private func makeVersionRegistries(
        fixture fileStore: ProjectFileStore, packageURL: URL
    ) async throws -> (versions: McpToolRegistry, history: McpToolRegistry) {
        let librarySeam:
            @Sendable () async -> (
                store: ProjectFileStore, projectDirectory: URL
            )? = { [fileStore, packageURL] in
                (store: fileStore,
                 projectDirectory: packageURL.deletingLastPathComponent())
            }
        let versionsRegistry = await McpServerController.makeRegistry(
            project: McpProjectContext(library: librarySeam))
        let historyRegistry = await McpServerController.makeRegistry(
            searchState: McpSearchStateContext(library: librarySeam))
        return (versionsRegistry, historyRegistry)
    }

    func testListVersionsGoldenProjectionByteEqual() async throws {
        let fixture = try await makeVersionFixture()
        let (versionsRegistry, historyRegistry) = try await makeVersionRegistries(
            fixture: fixture.fileStore, packageURL: fixture.packageURL)

        // ── The byte-equal projection: the tool output text ≡ the
        // hand-built expected serialization (same key order discipline —
        // sorted keys). ──
        let payload = try await Self.callJSON(
            versionsRegistry, name: "list_versions",
            arguments: ["image": .string(String(fixture.goldenID))])
        let outputData = try JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])

        let versions = fixture.goldenVersions
        var expectedVersions: [[String: Any]] = []
        for record in versions {
            let stack = record.chainStack ?? fixture.goldenHistory
            let dict: [String: Any] = [
                "id": record.id.uuidString,
                "name": record.name,
                "createdAt": McpSearchStateToolset.iso8601(record.createdAt),
                "updatedAt": McpSearchStateToolset.iso8601(record.updatedAt),
                "active": record.chainStack == nil,
                "position": stack.position,
                "itemCount": stack.items.count,
                "truncated": false,
            ]
            expectedVersions.append(dict)
        }
        let expected: [String: Any] = [
            "image": String(fixture.goldenID),
            "activeVersionID": versions[2].id.uuidString,
            "versions": expectedVersions,
        ]
        let expectedData = try JSONSerialization.data(
            withJSONObject: expected, options: [.sortedKeys])
        XCTAssertEqual(
            String(decoding: outputData, as: UTF8.self),
            String(decoding: expectedData, as: UTF8.self),
            "the projection is byte-equal to the hand-built expected shape")

        // Structural cross-checks (readability of the byte-equal above).
        XCTAssertEqual((payload["versions"] as? [[String: Any]])?.count, 3)
        let rows = try XCTUnwrap(payload["versions"] as? [[String: Any]])
        XCTAssertEqual(rows.filter { ($0["active"] as? Bool) == true }.count, 1)
        XCTAssertNil(rows[0]["items"], "includeItems defaults OFF")
        XCTAssertEqual(rows[2]["position"] as? Int, 1, "the ACTIVE chain position")
        XCTAssertEqual(rows[0]["itemCount"] as? Int, 2, "the frozen chain A count")
    }

    /// The includeItems arms + the ACTIVE-chain ≡ get_history identity
    /// (同源同投影 — the description's division-of-labor sentence).
    func testListVersionsIncludeItemsAndActiveChainIdentity() async throws {
        let fixture = try await makeVersionFixture()
        let (versionsRegistry, historyRegistry) = try await makeVersionRegistries(
            fixture: fixture.fileStore, packageURL: fixture.packageURL)

        let detailed = try await Self.callJSON(
            versionsRegistry, name: "list_versions",
            arguments: [
                "image": .string(String(fixture.goldenID)),
                "includeItems": .bool(true),
            ])
        let rows = try XCTUnwrap(detailed["versions"] as? [[String: Any]])
        XCTAssertEqual((rows[0]["items"] as? [[String: Any]])?.count, 2, "chain A items")
        XCTAssertEqual((rows[1]["items"] as? [[String: Any]])?.count, 1, "chain B items")
        XCTAssertEqual((rows[2]["items"] as? [[String: Any]])?.count, 2, "ACTIVE items")
        XCTAssertEqual(
            (rows[0]["items"] as? [[String: Any]])?.compactMap { $0["label"] as? String },
            ["vA-1", "vA-2"], "chain A rides its OWN frozen items")

        // The ACTIVE chain's items ≡ get_history's items (same source, same
        // projection — the ACTIVE version reads the document history key).
        let history = try await Self.callJSON(
            historyRegistry, name: "get_history",
            arguments: ["image": .string(String(fixture.goldenID))])
        XCTAssertEqual(
            (rows[2]["items"] as? [[String: Any]])?.map { $0["label"] as? String },
            (history["items"] as? [[String: Any]])?.map { $0["label"] as? String },
            "ACTIVE chain items ≡ get_history items (同源)")
    }

    /// The 500 cap per version: the 505-item chain truncates to the NEWEST
    /// 500 with position/itemCount staying TRUE (F-5 同式逐版本).
    func testListVersionsCapKeepsNewestEndPerVersion() async throws {
        let fixture = try await makeVersionFixture()
        let versionsRegistry = await McpServerController.makeRegistry(
            project: McpProjectContext(library: { [fileStore = fixture.fileStore,
                                                   packageURL = fixture.packageURL] in
                (store: fileStore,
                 projectDirectory: packageURL.deletingLastPathComponent())
            }))
        let payload = try await Self.callJSON(
            versionsRegistry, name: "list_versions",
            arguments: [
                "image": .string(String(fixture.longID)),
                "includeItems": .bool(true),
            ])
        let rows = try XCTUnwrap(payload["versions"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["itemCount"] as? Int, 505, "itemCount stays TRUE")
        XCTAssertEqual(rows[0]["truncated"] as? Bool, true)
        let items = try XCTUnwrap(rows[0]["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 500, "the cap")
        XCTAssertEqual(items.first?["label"] as? String, "edit 5", "the NEWEST end kept")
        XCTAssertEqual(items.last?["label"] as? String, "edit 504")
    }

    /// The pristine honest face (no sidecar = the empty projection, NOT an
    /// error) + the dangling activeVersionID riding the disk truth.
    func testListVersionsPristineAndDanglingFaces() async throws {
        let fixture = try await makeVersionFixture()
        let versionsRegistry = await McpServerController.makeRegistry(
            project: McpProjectContext(library: { [fileStore = fixture.fileStore,
                                                   packageURL = fixture.packageURL] in
                (store: fileStore,
                 projectDirectory: packageURL.deletingLastPathComponent())
            }))

        let pristine = try await Self.callJSON(
            versionsRegistry, name: "list_versions",
            arguments: ["image": .string(String(fixture.pristineID))])
        XCTAssertTrue(pristine["versions"] is [Any] && (pristine["versions"] as? [Any])?.isEmpty == true)
        XCTAssertTrue(pristine["activeVersionID"] is NSNull)

        let dangling = try await Self.callJSON(
            versionsRegistry, name: "list_versions",
            arguments: ["image": .string(String(fixture.danglingID))])
        let doc = try JSONDecoder().decode(
            LightamerSidecar.self,
            from: Data(contentsOf: LightamerSidecar.sidecarURL(
                for: tempDirectory.appendingPathComponent("Media/dangling.arw"))))
        XCTAssertEqual(
            dangling["activeVersionID"] as? String, doc.activeVersionID,
            "the structure rides the DISK truth (no synthesis, no repair)")
        XCTAssertEqual((dangling["versions"] as? [Any])?.count, 0)
    }

    /// The relPath addressing arm rides the sessionPair seam (the dual
    /// addressing — the same two-form shape get_history answers).
    func testListVersionsRelPathArmViaSessionPair() async throws {
        let fixture = try await makeVersionFixture()
        // A session fixture: the relPath row the sessionPair arm needs.
        let sessionRoot = tempDirectory.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionRoot.appendingPathComponent("Capture", isDirectory: true),
            withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 16).write(
            to: sessionRoot.appendingPathComponent("Capture/sess.arw"))
        let sessionStore = SessionIndexStore(sessionRoot: sessionRoot)
        _ = try await sessionStore.openSession(
            root: sessionRoot,
            scan: AsyncStream { continuation in
                continuation.yield(SessionScanPage(entries: [
                    SessionScanEntry(relPath: "Capture/sess.arw", mtime: 0, size: 16),
                ]))
                continuation.finish()
            })
        let sessDoc = LightamerSidecar(
            imageID: UUID(), decoderVersionUsed: "RAW8", decodeParamsHash: 5,
            instances: [], history: HistoryStack(), historyHash: 4,
            versions: [
                SidecarVersionRecord(
                    id: UUID(), name: "Sess v",
                    createdAt: Date(timeIntervalSince1970: 50),
                    updatedAt: Date(timeIntervalSince1970: 51), chain: nil),
            ],
            activeVersionID: nil)
        try JSONEncoder().encode(sessDoc).write(
            to: LightamerSidecar.sidecarURL(
                for: sessionRoot.appendingPathComponent("Capture/sess.arw")))

        // OQ-8: the SAME closure variables feed BOTH contexts.
        let librarySeam:
            @Sendable () async -> (
                store: ProjectFileStore, projectDirectory: URL
            )? = { [fileStore = fixture.fileStore, packageURL = fixture.packageURL] in
                (store: fileStore,
                 projectDirectory: packageURL.deletingLastPathComponent())
            }
        let sessionPairSeam:
            @Sendable () async -> (store: SessionIndexStore, root: URL)? = {
                [sessionStore, sessionRoot] in (sessionStore, sessionRoot)
            }
        let registry = await McpServerController.makeRegistry(
            project: McpProjectContext(
                library: librarySeam, sessionPair: sessionPairSeam))
        let payload = try await Self.callJSON(
            registry, name: "list_versions",
            arguments: ["image": .string("Capture/sess.arw")])
        let rows = try XCTUnwrap(payload["versions"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"] as? String, "Sess v")
        XCTAssertEqual(rows[0]["active"] as? Bool, true)
    }
}
