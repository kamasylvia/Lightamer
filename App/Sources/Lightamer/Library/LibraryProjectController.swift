import AppKit
import Foundation
import LightamerCore
import Observation
import os
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// LibraryProjectController (Plan M2-2-2 T4, KD-5) — the App-side project
// lifecycle face: create / open / recent (OQ-1 A: NSOpenPanel/NSSavePanel +
// a UserDefaults recent list) + backupProject / moveProject commands.
//
// MOVE = the WHOLE PROJECT DIRECTORY (the checker E5 ruling: the backup API
// cannot carry the physical `Media/` photos, so move never touches
// `sqlite3_backup`): close (forced checkpoint) → same-volume rename first,
// cross-volume copy → verify → remove source — the M2LIB-07① discipline
// REUSED: the source directory is NEVER removed before every file verified
// (the injected verifyStrategy failure leaves the old project intact).
// `.<stem>.lathumbs/` is a rebuildable derivative: skipped on the copy leg;
// the rename leg carries it harmlessly (no data hazard).
//
// Recent list = the SessionState.promoteRecent pattern (dedupe-move-front,
// cap 10, prune missing at load), stored as path strings under
// `library.recentProjects` through the injectable defaults suite.
// ─────────────────────────────────────────────────────────────────────────────

/// M6-1-01 T4 (KD-3): one project-open conflict — the dialog sheet's
/// payload (sheet(item:) identity per conflict; Equatable for the
/// @Observable diffing).
struct ProjectOpenConflict: Equatable, Identifiable, Sendable {
    let id = UUID()
    /// The package the second instance tried to open.
    let url: URL
    /// The holder's pid from the lock payload (nil = payload absent/stale —
    /// the「pid 未知」diagnostics fallback; NEVER a liveness criterion).
    let holderPid: Int32?
    /// The holder's claimed role raw value (nil = same fallback rules).
    let holderRole: String?
}

@MainActor
@Observable
final class LibraryProjectController {

    nonisolated static let recentStorageKey = "library.recentProjects"
    nonisolated static let recentLimit = 10

    /// The recent projects list (front = most recent).
    private(set) var recentProjects: [URL]

    /// The open package handle (nil = the no-project state).
    private(set) var projectStore: ProjectFileStore?

    /// The current package file URL — controller-OWNED (set at create/
    /// open/move) because `ProjectFileStore.fileURL` is actor-isolated and
    /// this face is read synchronously by views/commands.
    private(set) var projectURL: URL?

    /// The live import-progress snapshot (the @Sendable progress handler
    /// routes through HERE — capturing this controller, never the App
    /// struct; the overlay reads it).
    private(set) var importProgress: ImportProgress?

    /// The last surfaced failure (project lifecycle or import) — the
    /// alert's payload; `clearLastError` dismisses.
    private(set) var lastError: String?

    // ── M6-1-01 T4 (KD-3): the symmetric read-only fallback face ──────────

    /// The pending open conflict (nil = none). The app root presents it as
    /// the three-choice dialog sheet (只读打开 / 重试 / 取消). Settable so
    /// the sheet(item:) binding can dismiss it; only the open path publishes.
    var pendingConflict: ProjectOpenConflict?

    /// Whether the current project is the READ-ONLY face (the second
    /// instance's fallback). Source of the banner copy, the disabled
    /// projections and the write guards (one boolean, three seams).
    private(set) var isReadOnly = false

    /// The holder pid recorded at the read-only open (the banner's「pid N」
    /// source; nil = unknown holder).
    private(set) var readOnlyHolderPid: Int32?

    /// M2LIB-07① red-line seams (the ImportService twins): the injected
    /// verify for the cross-volume move leg and the volume probe forcing
    /// that leg in tests; nil = the production faces.
    var verifyStrategy: (@Sendable (URL, URL) async throws -> Bool)?
    var uuidProbe: (@Sendable (URL) -> String?)?

    /// M2-10-03 (OQ-6-A): the AI-analysis legs, injected by the shell host
    /// once its faces exist. nil = the inert face (no-shell contexts and
    /// the existing import tests skip the AI tail entirely).
    var aiAnalysis: AIAnalysisRegistry?
    var labelingPrompts: LabelingPromptController?

    private let defaultsSuiteName: String?
    private var activeImportService: LightamerCore.ImportService?

    /// FIX2 (T2/D-7): the live run's progress coalescer (nil outside a run).
    /// Holding it here keeps the drain tasks' target alive for the run's
    /// duration; cleared at the run tail (the terminal publication).
    private var importProgressCoalescer: ImportProgressCoalescer?

    /// FIX2 (T2/D-7) completion watchdog channel (diagnostics only — the
    /// stall's tail pin: a run that never reaches this line has its last
    /// emission logged instead, and a run that does publishes the outcome).
    nonisolated private static let importWatchdog = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "import-watchdog")

    nonisolated private static func seconds(
        _ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant
    ) -> String {
        let (secs, atto) = (end - start).components
        return String(format: "%.2f", Double(secs) + Double(atto) * 1e-18)
    }

    nonisolated private static func defaults(of suiteName: String?) -> UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private var defaults: UserDefaults { Self.defaults(of: defaultsSuiteName) }

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
        self.recentProjects = Self.loadRecent(from: Self.defaults(of: defaultsSuiteName))
    }

    // MARK: - Lifecycle

    /// Create a new `.lalb` package at `url` (already save-panel shaped)
    /// and open it as the current project.
    func createProject(at url: URL, name: String) async throws {
        let store = ProjectFileStore(at: url)
        // M6-1-01 omp M-OMP-4: a freshly created project enters the same
        // locked state as a normally opened one (the plan's explicit-
        // parameter prescription — otherwise the first instance writes
        // lockless while a second instance's `open(role:)` takes the
        // writer right unknowingly = dual write).
        _ = try await store.create(name: name, role: .gui)
        projectStore = store
        projectURL = url
        promoteRecent(url)
    }

    /// Open an existing package (the Open/Open-Recent routes converge).
    /// M6-1-01 (KD-3/OQ-2): a held project lock is the TYPED conflict —
    /// published as `pendingConflict` (the three-choice dialog's payload)
    /// and NOT rethrown: the dialog is the answer, not the generic alert.
    /// Every other error still throws.
    func openProject(at url: URL) async throws {
        let store = ProjectFileStore(at: url)
        do {
            _ = try await store.open(role: .gui)
        } catch let error as LibraryError {
            if case .projectHeldByOther = error {
                publishConflict(for: url)
                return
            }
            throw error
        }
        projectStore = store
        projectURL = url
        isReadOnly = false
        readOnlyHolderPid = nil
        promoteRecent(url)
    }

    /// The dialog's 只读打开 leg (KD-3): lockless read-only open, the face
    /// flag + holder pid recorded. NO auto-upgrade — the read-only face
    /// lasts until close/reopen (a reopen re-arbitrates; the dialog's
    /// 重试 leg is the explicit upgrade path).
    func openProjectReadOnly(at url: URL) async throws {
        let store = ProjectFileStore(at: url)
        _ = try await store.openReadOnly()
        projectStore = store
        projectURL = url
        isReadOnly = true
        readOnlyHolderPid = Self.readHolderPid(at: url)
        promoteRecent(url)
    }

    /// The dialog's 取消 leg: clear the conflict, open nothing.
    func dismissConflict() {
        pendingConflict = nil
    }

    /// Build the conflict payload from the lock file (the pid/role ride the
    /// payload; absent = nil — the「pid 未知」display fallback).
    private func publishConflict(for url: URL) {
        let lockURL = url.deletingPathExtension()
            .appendingPathExtension("lalb.lock")
        let payload = SingleWriterLock.readPayload(at: lockURL)
        pendingConflict = ProjectOpenConflict(
            url: url,
            holderPid: payload?.pid,
            holderRole: payload.map { payload in
                SingleWriterRole(rawValue: payload.role)?.rawValue ?? payload.role
            })
    }

    /// Read the holder pid off a package's lock payload (the read-only
    /// open's banner source; nil = unknown).
    nonisolated private static func readHolderPid(at url: URL) -> Int32? {
        let lockURL = url.deletingPathExtension()
            .appendingPathExtension("lalb.lock")
        return SingleWriterLock.readPayload(at: lockURL)?.pid
    }

    /// The applicationWillTerminate leg (M6-1-01 KD-2): a SYNCHRONOUS
    /// bounded wait (5s — the `stopEmbeddedForTermination` shape) closing
    /// the open store (checkpoint → handle close → lock release) before
    /// the process exits. A hung volume must not block termination forever;
    /// the process exit + kernel release is the floor either way.
    func flushForTermination() {
        guard let store = projectStore else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            try? await store.close()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        projectStore = nil
        projectURL = nil
    }

    /// Close the current project (checkpoint discipline inside).
    func closeProject() async throws {
        guard let store = projectStore else { return }
        try await store.close()
        projectStore = nil
        projectURL = nil
        isReadOnly = false
        readOnlyHolderPid = nil
    }

    /// The ONLY sanctioned copy path (KD-5: `sqlite3_backup` online
    /// consistency — a bare file copy could lose the WAL tail).
    func backupProject(to destination: URL) async throws {
        guard let store = projectStore else { throw LibraryError.notOpen }
        try await store.backup(to: destination)
    }

    /// Move the WHOLE project directory to `newDirectory` (which must not
    /// exist). Same volume → rename; cross volume → copy + verify + remove
    /// source (verify failure = typed throw, the old project untouched and
    /// reopened). Reopens at the new location and promotes the recent list.
    func moveProject(to newDirectory: URL) async throws {
        // M6-1-01 (KD-2/KD-3): the move window needs the write right —
        // the read-only face refuses (UI disables the entry; this is the
        // typed backstop; the lock semantics note lives in DECISIONS).
        if isReadOnly {
            throw LibraryError.projectReadOnly(detail:
                "the project is open read-only (another instance holds the "
                    + "project lock); close and reopen read-write to move")
        }
        guard let store = projectStore, let packageURL = projectURL else {
            throw LibraryError.notOpen
        }
        let stem = packageURL.deletingPathExtension().lastPathComponent
        let oldDirectory = packageURL.deletingLastPathComponent()
        guard oldDirectory.standardizedFileURL.path
            != newDirectory.standardizedFileURL.path else {
            throw LibraryError.constraintViolation(
                detail: "move destination equals the current location")
        }
        // Containment guards (the moveItem self-nesting hazard): the
        // destination may not lie inside the project directory (nor vice
        // versa) — a nested target would make the move descend into itself.
        let sourcePath = oldDirectory.standardizedFileURL.path
        let destinationPath = newDirectory.standardizedFileURL.path
        guard !destinationPath.hasPrefix(sourcePath + "/") else {
            throw LibraryError.constraintViolation(
                detail: "move destination lies inside the project directory")
        }
        guard !sourcePath.hasPrefix(destinationPath + "/") else {
            throw LibraryError.constraintViolation(
                detail: "move destination contains the project directory")
        }
        guard !FileManager.default.fileExists(atPath: newDirectory.path) else {
            throw LibraryError.constraintViolation(
                detail: "move destination already exists: \(newDirectory.path)")
        }
        try await store.close()
        do {
            try await Self.moveDirectory(
                from: oldDirectory, to: newDirectory, stem: stem,
                verify: verifyStrategy, uuidProbe: uuidProbe)
        } catch {
            // The old directory is intact by the red line — reopen there
            // (M-OMP-4: re-acquire the lock, same as the pre-move state).
            _ = try? await store.open(role: .gui)
            throw error
        }
        let newPackage = newDirectory
            .appendingPathComponent(stem)
            .appendingPathExtension(LibrarySchema.fileExtension)
        let moved = ProjectFileStore(at: newPackage)
        // M-OMP-4: the new-location reopen re-acquires the lock — the
        // move-window note's "intrusion lands the typed conflict face"
        // premise rests on this re-acquisition.
        _ = try await moved.open(role: .gui)
        projectStore = moved
        projectURL = newPackage
        promoteRecent(newPackage)
    }

    /// The directory move engine: rename-first, copy+verify+remove cross
    /// volume. Static + nonisolated (pure FileManager work + the async
    /// verify seam).
    private nonisolated static func moveDirectory(
        from oldDirectory: URL, to newDirectory: URL, stem: String,
        verify: (@Sendable (URL, URL) async throws -> Bool)?,
        uuidProbe: (@Sendable (URL) -> String?)?
    ) async throws {
        let probe = uuidProbe ?? ImageLinker.volumeUUID
        // Unknown identity on either side → the conservative copy leg (the
        // verify-then-remove direction is the safe one for the red line).
        let sameVolume: Bool = {
            guard let from = probe(oldDirectory), let to = probe(newDirectory) else {
                return false
            }
            return from == to
        }()
        if sameVolume {
            try FileManager.default.moveItem(at: oldDirectory, to: newDirectory)
            return
        }
        let thumbs = LibrarySchema.thumbsDirectoryName(stem: stem)
        var pairs: [(source: URL, destination: URL)] = []
        try copyTree(
            from: oldDirectory, to: newDirectory,
            skipDirectoryName: thumbs, pairs: &pairs)
        do {
            for pair in pairs {
                let strategy = verify ?? { source, destination in
                    LightamerCore.ImportService.defaultVerify(source: source, destination: destination)
                }
                guard try await strategy(pair.source, pair.destination) else {
                    throw ImportError.verifyFailed(
                        source: pair.source.path, destination: pair.destination.path)
                }
            }
        } catch {
            // Roll the copy back; the source directory stands (red line).
            try? FileManager.default.removeItem(at: newDirectory)
            throw error
        }
        try FileManager.default.removeItem(at: oldDirectory)
    }

    /// Recursive copy building the verify pair list; skips the named
    /// derivative directory (`.lathumbs`).
    private nonisolated static func copyTree(
        from source: URL, to destination: URL,
        skipDirectoryName: String?,
        pairs: inout [(source: URL, destination: URL)]
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [])
        for item in contents {
            if let skipDirectoryName, item.lastPathComponent == skipDirectoryName {
                continue
            }
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory {
                try copyTree(
                    from: item, to: target,
                    skipDirectoryName: skipDirectoryName, pairs: &pairs)
            } else {
                try fm.copyItem(at: item, to: target)
                pairs.append((item, target))
            }
        }
    }

    // MARK: - Import orchestration (the dialog → ImportService wiring)

    /// Run the confirmed import (the dialog's onConfirm route): scan →
    /// per-file execute with progress pushed onto `importProgress`, the
    /// EXIF/FTS batch faces riding the M2-2-1 seams.
    ///
    /// Defect A (M2-3 walkthrough 真缺陷 A): the completion publication
    /// hangs. The previous handler body `await MainActor.run { ... }` made
    /// EVERY progress emission BLOCK the ImportService actor until the main
    /// thread drained that hop — a structural actor↔main-thread mutual
    /// dependency. When one of those jobs lost its wake-up on the idle
    /// run loop (the walkthrough's 2/2 repro: zero import stack frames,
    /// 0% CPU, tail statements never reached; a cancel click — main-thread
    /// event traffic — kicked the hop alive), the actor suspended on the
    /// emission forever: `importFolder` never returned, so the tail
    /// (`importProgress = nil`) never ran and the task bar hung. The fix
    /// CUTS the dependency: the handler hands the snapshot to a detached
    /// MainActor task and returns immediately — the actor loop and the
    /// completion publication never wait on a main-executor drain again.
    /// Main-queue FIFO preserves snapshot order (the adapter's monotonic
    /// clamp stays as belt-and-braces).
    func runImport(folder: URL, choice: ImportModeChoice) async {
        guard let store = projectStore, let packageURL = projectURL,
              importProgress == nil else { return }
        let service = LightamerCore.ImportService(store: store)
        activeImportService = service
        // FIX2 (T2/D-7): the per-run delivery coalescer — the handler hands
        // each snapshot to the coalescer and returns IMMEDIATELY (zero await:
        // the doc comment's Defect A dependency stays cut); the coalescer
        // throttles the UI publication to one delivery per window with
        // latest-wins semantics. Terminal snapshots (.completed/.cancelled)
        // bypass the window — the onChange consumer (WorkspaceHostView)
        // finishes the task bar on the run's end, so a swallowed terminal
        // would hang the bar again. The controller-nil carrier below (the
        // run tail) is the SECOND terminal carrier and stays a direct write.
        let coalescer = ImportProgressCoalescer { [weak self] snapshot in
            self?.importProgress = snapshot
        }
        importProgressCoalescer = coalescer
        await service.setProgressHandler { [weak coalescer] snapshot in
            coalescer?.submit(snapshot)
        }
        let startedAt = ContinuousClock.now
        // M2-10-03 (OQ-6-A): the AI legs key on the rows this import ADDS —
        // captured against the pre-import high-water mark. A failed read
        // skips the legs: derived-data bookkeeping never fails an import.
        let beforeMaxRowID = try? await AIAnalysisQueries.maxImageRowID(in: store)
        var newImageIDs: [Int64] = []
        do {
            let defaults = ImportDefaults(defaultsSuiteName: defaultsSuiteName)
            let plan = try await service.makePlan(
                sourceFolder: folder,
                projectDirectory: packageURL.deletingLastPathComponent(),
                mode: choice.mode,
                whitelist: defaults.resolvedWhitelist(),
                categories: choice.categories)
            importProgress = ImportProgress(
                phase: .importing, total: plan.items.count)
            let outcome = try await service.importFolder(plan)
            if let beforeMaxRowID, outcome.imported > 0, !outcome.cancelled {
                newImageIDs = (try? await AIAnalysisQueries.imageIDs(
                    in: store, afterRowID: beforeMaxRowID)) ?? []
            }
        } catch {
            lastError = error.localizedDescription
        }
        activeImportService = nil
        // FIX2 (T2/D-7) completion watchdog: one diagnostic line BEFORE the
        // terminal publication — if the stall phenotype ever recurs, the log
        // pins the tail's arrival (or its absence) with the run's shape.
        // Zero behavior change.
        do {
            let elapsed = Self.seconds(startedAt, .now)
            let lastPhase = String(describing: importProgress?.phase ?? .importing)
            Self.importWatchdog.info(
                "import run finished in \(elapsed, privacy: .public)s — last service-side face \(lastPhase, privacy: .public); publishing nil terminal")
        }
        // R6 (import zero-row): quiesce the delivery coalescer BEFORE the
        // direct nil write — a queued drain/flush delivery landing after the
        // nil would resurrect the published progress with no writer left
        // behind, so the onChange consumer's nil-finish branch (the grid's
        // reloadFirstPage) would never fire (the R5-2 / obs-4 phenotype).
        coalescer.invalidate()
        importProgress = nil
        importProgressCoalescer = nil

        // The AI tail (auto leg first, no prompt; then the labeling mode
        // three-state). Everything here is post-close: the prompt publishes
        // one beat AFTER the progress publication (the plan's 弹询时机 pin —
        // a Task.yield gives the overlay dismissal's render the turn first).
        guard !newImageIDs.isEmpty else { return }
        aiAnalysis?.enqueue(.embedding(imageIDs: newImageIDs))
        if let prompts = labelingPrompts {
            switch prompts.intentForNewImages(newImageIDs) {
            case .enqueueNow:
                aiAnalysis?.enqueue(.labeling(imageIDs: newImageIDs))
            case .ask:
                await Task.yield()
                prompts.presentPrompt(newImageIDs)
            case nil:
                break
            }
        }
    }

    /// Cancel at the next per-file checkpoint.
    func cancelImport() {
        guard let service = activeImportService else { return }
        Task { await service.cancel() }
    }

    func clearLastError() {
        lastError = nil
    }

    /// Surface a failure from the command routes (the alert's payload).
    func reportError(_ message: String) {
        lastError = message
    }

    // MARK: - Recent list (the SessionState.promoteRecent pattern)

    /// Promote `url` to the front: dedupe-move-front, cap 10, prune paths
    /// that no longer exist, persist through the injected defaults.
    func promoteRecent(_ url: URL) {
        var next: [URL] = [url]
        for existing in recentProjects where existing != url {
            if FileManager.default.fileExists(atPath: existing.path) {
                next.append(existing)
            }
        }
        if next.count > Self.recentLimit {
            next.removeLast(next.count - Self.recentLimit)
        }
        recentProjects = next
        defaults.set(next.map(\.path), forKey: Self.recentStorageKey)
    }

    /// Drop dead paths (the startup repair pass; init runs the same filter
    /// through loadRecent).
    func pruneMissingRecents() {
        let kept = recentProjects.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard kept.count != recentProjects.count else { return }
        recentProjects = kept
        defaults.set(kept.map(\.path), forKey: Self.recentStorageKey)
    }

    private nonisolated static func loadRecent(from defaults: UserDefaults) -> [URL] {
        guard let paths = defaults.stringArray(forKey: recentStorageKey) else {
            return []
        }
        return paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .prefix(recentLimit)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LibraryPanels — the OQ-1 A panel wrappers (NSSavePanel/NSOpenPanel), the
// FileOpener sibling for the project commands.
// ─────────────────────────────────────────────────────────────────────────────

// L057 (fix(l057), 2026-10-08): every wrapper is async and presents via
// PanelPresentation.present (the `begin` seam) — runModal nested inside
// the menu-command dispatch tore down SwiftUI button/menu-item closure
// contexts on cancel (SIGSEGV over-release; .ips 2026-10-08-085205 came
// from the Task-wrapped menu path, so the hop alone was not enough).
@MainActor
enum LibraryPanels {

    /// New project: NSSavePanel, the `.lalb` suffix appended when absent.
    static func newProject() async -> URL? {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.nameFieldStringValue = "Untitled." + LibrarySchema.fileExtension
        panel.canCreateDirectories = true
        guard let url = await PanelPresentation.present(panel) else { return nil }
        return url.pathExtension.isEmpty
            ? url.appendingPathExtension(LibrarySchema.fileExtension)
            : url
    }

    /// Open project: NSOpenPanel for an existing `.lalb`.
    static func openProject() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return await PanelPresentation.present(panel)
    }

    /// Pick an existing directory (the import source / the move destination
    /// parent).
    static func folder(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return await PanelPresentation.present(panel)
    }

    /// Pick a destination file (the backup target).
    static func destination(title: String, defaultName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        return await PanelPresentation.present(panel)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// M6-1-01 T4 (KD-3/OQ-2) — the project-open conflict dialog (zh verbatim
// 定稿). Pure SwiftUI sheet face (the L057 runModal ban holds — the app root
// presents it via .sheet(item:)); plain values + closures only, NO
// @Environment Observable reads (the M2-8-3 FINDING-A sheet-boundary rule —
// an app-root sheet must not rely on the chain's .environment writes).
// ─────────────────────────────────────────────────────────────────────────────

struct ProjectConflictDialog: View {
    let conflict: ProjectOpenConflict
    let onReadOnly: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "project_read_only_dialog_title",
                        defaultValue: "项目已由另一实例打开"))
                .font(.headline)
            Text(String(
                localized: "project_read_only_dialog_message",
                defaultValue: "“\(conflict.url.deletingPathExtension().lastPathComponent)” 由另一实例持有（pid \(pidText)）。可只读打开浏览，或重试获取写权。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    onReadOnly()
                } label: {
                    Text(String(localized: "project_read_only_open",
                                defaultValue: "只读打开"))
                }
                Button {
                    onRetry()
                } label: {
                    Text(String(localized: "project_read_only_retry",
                                defaultValue: "重试"))
                }
                Button {
                    onCancel()
                } label: {
                    Text(String(localized: "project_read_only_cancel",
                                defaultValue: "取消"))
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(minWidth: 420)
        .accessibilityIdentifier("project.conflict.dialog")
    }

    /// The「pid N」display face (「pid 未知」when the payload was absent —
    /// diagnostics only, never a liveness claim).
    private var pidText: String {
        conflict.holderPid.map { String($0) } ?? "未知"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LibraryWelcomeView — the OQ-1 A minimal Welcome face (no project open AND
// no recent projects at launch). Pure presentation: the app root supplies
// the actions. zh copy landed with M2-3-4 T1 (the P4 backfill batch): the
// static verbatim strings moved onto String(localized:) keys; project names
// stay verbatim (data, not copy).
// ─────────────────────────────────────────────────────────────────────────────

struct LibraryWelcomeView: View {
    let recentProjects: [URL]
    let onCreate: () -> Void
    let onOpen: () -> Void
    let onOpenRecent: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "welcome_app_name",
                        defaultValue: "Lightamer"))
                .font(.largeTitle.bold())
            Text(String(localized: "welcome_subtitle",
                        defaultValue: "Create a project to organize your photo library."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    onCreate()
                } label: {
                    Text(String(localized: "welcome_new_project",
                                defaultValue: "New Project…"))
                }
                .keyboardShortcut(.defaultAction)
                Button {
                    onOpen()
                } label: {
                    Text(String(localized: "welcome_open_project",
                                defaultValue: "Open Project…"))
                }
            }
            if !recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "welcome_recent_projects",
                                defaultValue: "Recent Projects"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(recentProjects, id: \.absoluteString) { url in
                        Button {
                            onOpenRecent(url)
                        } label: {
                            Text(verbatim: url.lastPathComponent)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            Button {
                onDismiss()
            } label: {
                Text(String(localized: "welcome_continue_without",
                            defaultValue: "Continue without a project"))
            }
            .buttonStyle(.link)
        }
        .padding(40)
        .frame(minWidth: 440)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImportProgressCoalescer (FIX2 T2/D-7) — the progress-delivery throttle
// between the ImportService actor's per-file loop and the main-actor UI face.
//
// WHY: the service emits one snapshot per file (`emit` awaits the handler
// INSIDE its actor loop, ImportService.swift:736-738). The pre-FIX2 handler
// hopped every snapshot to a fresh MainActor task — an O(file-count) main-
// queue storm that, under the D-6 churn's main-thread pressure, starves the
// run tail into the minute-scale stall (the D-7 sample: zero import frames
// + 909 mach_msg main-thread ticks while Media finished landing). The
// coalescer collapses that storm to ≤1 delivery per window with
// latest-wins semantics.
//
// TWO PINS (the FIX2 plan's M-1):
// 1. NON-BLOCKING: `submit` is the handler body's whole work — it takes a
//    lock, stashes the snapshot, schedules a fire-and-forget task and
//    returns. ZERO await in the handler path: any suspension here would
//    re-create the actor↔main mutual wait (the runImport doc comment's
//    Defect A — the previous generation's `await MainActor.run` handler).
//    The throttle's sleep lives in the scheduled DRAIN task, never in the
//    handler.
// 2. ORDER: every DELIVERED snapshot rides the main actor (single-flight
//    window drain + terminal flush), so the UI sees main-queue FIFO; the
//    single pending slot makes in-window intermediate snapshots drop while
//    the LATEST always lands (the ImportTaskAdapter's monotonic clamp stays
//    as belt-and-braces). Terminal snapshots (.completed/.cancelled) bypass
//    the window AND supersede any pending interim — the visual tail (the
//    WorkspaceHostView onChange's nil-finish + the adapter's finish) can
//    never hang on a dropped terminal.
// ─────────────────────────────────────────────────────────────────────────────

final class ImportProgressCoalescer: @unchecked Sendable {

    private let lock = NSLock()
    /// The latest not-yet-delivered snapshot (single slot — newest wins).
    private var pending: ImportProgress?
    /// One window-drain task in flight at most (the FIFO pin's guard).
    private var windowDrainArmed = false
    /// R6 (import zero-row): once invalidated, every face is a no-op —
    /// see `invalidate()`.
    private var invalidated = false
    /// nil = never delivered (the leading delivery is always immediate).
    private var lastDelivery: ContinuousClock.Instant?
    private let interval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let deliver: @MainActor @Sendable (ImportProgress) -> Void

    init(
        interval: Duration = .milliseconds(100),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        deliver: @escaping @MainActor @Sendable (ImportProgress) -> Void
    ) {
        self.interval = interval
        self.now = now
        self.lastDelivery = nil
        self.deliver = deliver
    }

    /// The pure window decision (the unit-test seam): a delivery inside the
    /// open window would coalesce; past the edge it may lead a new window.
    nonisolated static func isWindowOpen(
        lastDelivery: ContinuousClock.Instant?,
        now: ContinuousClock.Instant,
        interval: Duration
    ) -> Bool {
        guard let lastDelivery else { return false }
        return now < lastDelivery + interval
    }

    /// The service-side handler body: stash + schedule, never await.
    func submit(_ snapshot: ImportProgress) {
        let terminal = snapshot.phase == .completed || snapshot.phase == .cancelled
        lock.lock()
        guard !invalidated else { lock.unlock(); return }
        pending = snapshot
        var arm = false
        if !terminal, !windowDrainArmed {
            windowDrainArmed = true
            arm = true
        }
        lock.unlock()
        if arm {
            // Leading+trailing throttle: the drain sleeps the REMAINING
            // window (0 = the leading immediate delivery), then publishes
            // the latest pending. The sleep rides this fire-and-forget task
            // — the handler itself never sleeps (pin 1).
            let remaining = remainingWindow()
            Task { @MainActor in
                if remaining > .zero {
                    try? await Task.sleep(for: remaining)
                }
                self.drainWindow()
            }
        }
        if terminal {
            // Bypass: the terminal lands on the main queue immediately and
            // supersedes any pending interim (single slot).
            Task { @MainActor in self.flushTerminal() }
        }
    }

    private func remainingWindow() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        guard let lastDelivery,
            Self.isWindowOpen(
                lastDelivery: lastDelivery, now: now(), interval: interval)
        else { return .zero }
        return (lastDelivery + interval) - now()
    }

    @MainActor
    private func drainWindow() {
        lock.lock()
        guard !invalidated else { lock.unlock(); return }
        let snapshot = pending
        pending = nil
        lastDelivery = now()
        windowDrainArmed = false
        lock.unlock()
        if let snapshot {
            deliver(snapshot)
        }
    }

    @MainActor
    private func flushTerminal() {
        lock.lock()
        guard !invalidated else { lock.unlock(); return }
        let snapshot = pending
        pending = nil
        lock.unlock()
        if let snapshot {
            deliver(snapshot)
        }
    }

    /// R6 (import zero-row, the R5-2 / omp obs-4 root cause): the run-tail
    /// coordination face. The run tail writes `importProgress = nil`
    /// DIRECTLY (the controller-nil terminal carrier), racing the queued
    /// window-drain / terminal-flush delivery jobs on the main queue — a
    /// delivery that lands AFTER the nil write resurrects the published
    /// state (an interim or `.completed` snapshot) with NO further writer
    /// behind it, so the onChange consumer's nil-finish branch — the grid's
    /// `reloadFirstPage`, the row-arrival publication — never fires. The
    /// DB rows are committed but the grid page never shows them (the
    /// "grid rows never arrived" probe phenotype; load-sensitive because
    /// the queue interleave widens under pressure, present at low load too
    /// — a bare scheduling race, the 2/5 idle baseline). The run tail calls
    /// this BEFORE the nil write: the pending slot drops, every in-flight
    /// delivery no-ops, and nil is the terminal writer by construction.
    /// Already-delivered snapshots are NOT retracted (the bar's history is
    /// honest; only the future dies).
    func invalidate() {
        lock.lock()
        invalidated = true
        pending = nil
        lock.unlock()
    }
}
