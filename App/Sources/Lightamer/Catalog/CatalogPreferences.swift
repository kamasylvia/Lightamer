import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// CatalogPreferencesModel (Plan 16-2 T1) — the UI-side preferences face over
// the 16-1 enable key + the catalog LOCATION preference.
//
// KEY DISCIPLINE (single spelling): the enable flag rides the CORE
// `CatalogPreferences` statics (CatalogProjector.swift — the projector's
// guard reads the SAME key); this model never re-spells the key literal, it
// writes THROUGH the Core face so the guard and the UI can never diverge.
//
// LOCATION (RQ-16-1②): re-point, NEVER migrate — the outgoing handles close,
// the preference lands, and the NEXT open creates an empty library at the
// new path when missing. The stored value is the catalog DIRECTORY (the
// NSOpenPanel face is a directory picker per the plan); the database file
// keeps the frozen `CatalogIndexSchema.databaseFileName` inside it. Empty =
// the schema default.
//
// ORGANIZATION MODE AXIS (RQ-16-12): org-mode (sessions | catalogs) is the
// SECOND dimension, orthogonal to the browser-mode axis (grid/single/
// culling — ContentView.BrowserMode). Cold start is ALWAYS sessions — the
// default is a CONSTANT (`coldStartRawValue`), not remembered state; the
// AppStorage write happens on the first frame (ContentView applies it).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class CatalogPreferencesModel {

    /// The location preference (the catalog DIRECTORY; empty = default).
    nonisolated static let locationStorageKey = "catalogs.databasePath"

    /// The organization-mode AppStorage key (the segmented switcher's
    /// persistence; cold start still forces sessions — see below).
    nonisolated static let organizationModeStorageKey = "organization.mode"

    /// 恒默认做成常量 (RQ-16-12): the FIRST frame always overwrites the
    /// persisted org-mode with THIS value. Tests pin it.
    nonisolated static let coldStartRawValue = OrganizationMode.sessions.rawValue

    /// The two-value organization axis.
    enum OrganizationMode: String {
        case sessions
        case catalogs
    }

    /// Suite-NAME storage (Sendable; the UserDefaults instance is built on
    /// access) — nil = `.standard`. The enable flag rides the CORE face
    /// with the SAME suite name, so a test project never touches global
    /// state and the guard/UI always agree.
    private let defaultsSuiteName: String?

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Mirrors the Core-guard key (read at init; written through Core).
    private(set) var catalogsEnabled: Bool

    /// The catalog directory path ("" = `CatalogIndexSchema` default).
    private(set) var locationPath: String

    /// App-root seams (wired once in the scene `.task`; D-03b closures).
    /// `onEnabledChanged` = the repoint/empty-library leg on enable;
    /// `onLocationChanged` = the runtime re-point leg (closes handles).
    var onEnabledChanged: ((Bool) -> Void)?
    var onLocationChanged: ((URL) -> Void)?

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
        self.catalogsEnabled = CatalogPreferences.catalogsEnabled(
            defaultsSuiteName: defaultsSuiteName)
        self.locationPath = Self.defaults(of: defaultsSuiteName).string(
            forKey: Self.locationStorageKey) ?? ""
    }

    private nonisolated static func defaults(of suiteName: String?) -> UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The resolved `.lcat` file URL for the current location preference.
    var catalogURL: URL {
        if locationPath.isEmpty {
            return CatalogIndexSchema.defaultDatabaseURL()
        }
        return URL(fileURLWithPath: locationPath, isDirectory: true)
            .appendingPathComponent(CatalogIndexSchema.databaseFileName)
    }

    var usingDefaultLocation: Bool { locationPath.isEmpty }

    /// The `.lcat` file existence face (the settings row's existence note).
    var catalogFileExists: Bool {
        FileManager.default.fileExists(atPath: catalogURL.path)
    }

    /// The enable switch (the SAME key the projector guard reads — the
    /// write goes through the Core face, never a second spelling).
    func setCatalogsEnabled(_ enabled: Bool) {
        CatalogPreferences.setCatalogsEnabled(enabled, defaultsSuiteName: defaultsSuiteName)
        catalogsEnabled = enabled
        onEnabledChanged?(enabled)
    }

    /// Re-point the catalog location (RQ-16-1②: no migration). The runtime
    /// closure fires FIRST (closes the outgoing handles), then the
    /// preference lands; the next enable/open creates the library at the
    /// new path when missing (建空库).
    func setLocation(directory: URL) {
        let standardized = directory.standardizedFileURL.path
        guard standardized != locationPath else { return }
        onLocationChanged?(URL(fileURLWithPath: standardized, isDirectory: true))
        locationPath = standardized
        defaults.set(standardized, forKey: Self.locationStorageKey)
    }

    /// Back to the schema-default location (the same no-migration flow).
    func resetLocationToDefault() {
        guard !locationPath.isEmpty else { return }
        onLocationChanged?(CatalogIndexSchema.defaultDatabaseURL().deletingLastPathComponent())
        locationPath = ""
        defaults.removeObject(forKey: Self.locationStorageKey)
    }

    // MARK: - Plan 16-4: the schema-failed disabled state + the two-mode
    // rebuild (RQ-16-14)

    /// Rebuild progress payload (the X/N 浮层).
    struct RebuildProgressState: Equatable {
        var completed: Int
        var total: Int
    }

    /// The completion/failure notice (the TWO honest completion copies:
    /// reconcile = the library reconciled; destructive = metadata restored
    /// AND the organization-data loss spelled out — the discipline).
    enum RebuildOutcome: Equatable {
        case reconciled(sessions: Int)
        case restoredDestructive(sessions: Int)
        case failed(String)
    }

    /// The 损坏处置 state: the `.lcat` exists but refuses the frozen schema
    /// (v99 / truncated / unparsable). Catalogs mode renders its disabled
    /// face + the「重建目录库」button; Sessions mode is untouched (the
    /// failure semantics inherited from 16-1).
    private(set) var schemaFailed = false

    /// Rebuild-in-flight state (the grid shows 空网格 + 进度 while true).
    private(set) var isRebuilding = false
    private(set) var rebuildProgress: RebuildProgressState?

    /// The last rebuild's completion notice (the alert payload).
    private(set) var lastOutcome: RebuildOutcome?

    /// The alert's dismissal face (the Binding setter routes here — the
    /// field itself stays externally read-only).
    func clearOutcome() {
        lastOutcome = nil
    }

    /// App-root seams (wired with the other D-03b closures):
    /// `onBeforeDestructiveRebuild` closes every shared catalog handle (a
    /// writer holding the old inode would strand its state after the
    /// rename promotion); `onCatalogRuntimeReset` re-points the shared
    /// trio after ANY rebuild (fresh handles + the browser rebind hook);
    /// `recentRootsProvider` feeds the rebuild's session backfill (the
    /// recent list — the source of last resort when the old registry is
    /// unreadable).
    var onBeforeDestructiveRebuild: (() async -> Void)?
    var onCatalogRuntimeReset: (() async -> Void)?
    var recentRootsProvider: (() -> [URL])?

    /// Probe the schema state (idempotent; the file-missing case is the
    /// healthy empty state — a fresh library is created on the next open,
    /// never a failure).
    nonisolated private static func probeSchemaFailed(url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let handle = try? SQLiteHandle(path: url.path) else { return true }
        defer { handle.close() }
        do {
            try CatalogIndexSchema.apply(to: handle)
            return false
        } catch {
            return true
        }
    }

    func refreshSchemaState() {
        schemaFailed = Self.probeSchemaFailed(url: catalogURL)
    }

    /// 对账式重建（默认档）: zero watermarks → re-project every registered
    /// session; ids and organization data survive.
    func runReconcileRebuild() async {
        await runRebuild(destructive: false)
    }

    /// 破坏式重建（文件级恢复档）: fresh `catalog.lcat.tmp` → verify →
    /// same-dir rename promotion (L009); organization data is LOST (the
    /// completion copy says so, verbatim).
    func runDestructiveRebuild() async {
        await onBeforeDestructiveRebuild?()
        await runRebuild(destructive: true)
    }

    private func runRebuild(destructive: Bool) async {
        guard !isRebuilding else { return }
        isRebuilding = true
        rebuildProgress = nil
        defer {
            isRebuilding = false
            rebuildProgress = nil
        }
        let rebuilder = CatalogRebuilder(databaseURL: catalogURL)
        await rebuilder.setProgressHandler { [weak self] progress in
            guard let self else { return }
            let state = RebuildProgressState(
                completed: progress.completedSessions,
                total: progress.totalSessions)
            await MainActor.run { self.rebuildProgress = state }
        }
        do {
            let sessions: Int
            if destructive {
                sessions = try await rebuilder.destructiveRebuild(
                    recentRoots: recentRootsProvider?() ?? [])
            } else {
                sessions = try await rebuilder.reconcileRebuild(
                    recentRoots: recentRootsProvider?() ?? [])
            }
            lastOutcome = destructive
                ? .restoredDestructive(sessions: sessions)
                : .reconciled(sessions: sessions)
            schemaFailed = Self.probeSchemaFailed(url: catalogURL)
            await onCatalogRuntimeReset?()
        } catch {
            lastOutcome = .failed(error.localizedDescription)
            schemaFailed = Self.probeSchemaFailed(url: catalogURL)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CatalogSidebarSection (Plan 16-2 T2) — the Catalogs sidebar's five-section
// ORDER as a pinned constant (RQ-16-12: All Photographs / Categories /
// Collections / Smart Albums / Sessions 从属节). The categories/collections
// sections are 16-3 接线位 (this plan renders the skeleton + the empty face).
// ─────────────────────────────────────────────────────────────────────────────

enum CatalogSidebarSection: CaseIterable, Equatable {
    case allPhotographs
    case categories
    case collections
    case smartAlbums
    case sessions
}
