import AppKit
import Foundation
import LightamerCore
import Observation
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
        _ = try await store.create(name: name)
        projectStore = store
        projectURL = url
        promoteRecent(url)
    }

    /// Open an existing package (the Open/Open-Recent routes converge).
    func openProject(at url: URL) async throws {
        let store = ProjectFileStore(at: url)
        _ = try await store.open()
        projectStore = store
        projectURL = url
        promoteRecent(url)
    }

    /// Close the current project (checkpoint discipline inside).
    func closeProject() async throws {
        guard let store = projectStore else { return }
        try await store.close()
        projectStore = nil
        projectURL = nil
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
            // The old directory is intact by the red line — reopen there.
            _ = try? await store.open()
            throw error
        }
        let newPackage = newDirectory
            .appendingPathComponent(stem)
            .appendingPathExtension(LibrarySchema.fileExtension)
        let moved = ProjectFileStore(at: newPackage)
        _ = try await moved.open()
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
        await service.setProgressHandler { [weak self] snapshot in
            Task { @MainActor in self?.importProgress = snapshot }
        }
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
                whitelist: defaults.resolvedWhitelist())
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
        importProgress = nil

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
