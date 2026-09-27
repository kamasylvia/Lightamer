import CoreGraphics
import Foundation
import LightamerCore
import Observation
import os

// ─────────────────────────────────────────────────────────────────────────────
// CatalogThumbnailRouter (Plan 16-2 T5; RQ-16-9) — the cross-session grid's
// thumbnail face.
//
// ROUTE: `(session_id, rel_path)` → `catalog_sessions.root_path` → the
// per-session provider pool `[session_id: SessionThumbnailProvider]` — each
// provider is the EXISTING Phase 9 pipeline (double-tier ruling, disk store
// at `<root>/.lightamer/thumbs/`, stale regen) constructed exactly like the
// app root's per-session assembly (LightamerApp's open leg). Providers are
// LAZY: only sessions whose cells actually render pay the lindex open.
//
// POOL LIFECYCLE: follows the Catalogs grid data source — `teardown()`
// cancels every pending job and drops the pool (the single-session
// teardown semantics, generalized to N sessions; the app-level memory
// cache itself is NOT drained here — it lives with the app).
//
// MEMORY: the app-level 384MB shared LRU (ThumbnailMemoryCache singleton)
// serves the WHOLE pool — zero new budget face. Keys are NAMESPACED per
// session (`memoryKeyPrefix`, the provider's 16-2 face): the same relPath
// in two sessions is two different FILES, so pooling must not merge them.
//
// OFFLINE (D-16-CONTEXT-7②): a session whose registry row says offline, or
// whose root fails the stat, NEVER gets a provider — the cell shows the
// gray placeholder and no work is enqueued (零请求).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class CatalogThumbnailRouter {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "catalog-thumbs")

    /// The app-root-assigned instance (the SidebarView's session-management
    /// actions invalidate the cached root map through it after a remove /
    /// re-link; MainActor-typed like every access site).
    nonisolated(unsafe) static var shared: CatalogThumbnailRouter?

    /// Sessions that failed the offline probe (registry offline flag OR a
    /// root/lindex stat-open failure) — the cells' gray-placeholder face.
    private(set) var offlineSessionIDs: Set<String> = []

    /// The lazy provider pool (one per TOUCHED session, not per library).
    private var providers: [String: SessionThumbnailProvider] = [:]

    /// In-flight provider opens (dedupe concurrent cell fetches).
    private var openingTasks: [String: Task<SessionThumbnailProvider?, Never>] = [:]

    /// session_id → root (from the shared store's registry read; refreshed
    /// via `invalidateRoots()` after sweeps/re-links).
    private var sessionRoots: [String: URL] = [:]
    private var rootsLoaded = false

    // MARK: - Dependencies (the app root's provider-assembly faces)

    private let memory: ThumbnailMemoryCache
    private let registry: ModuleRegistry
    private let decoder: RAWDecoder?
    /// The injected decode seam (test face — the provider's own; nil = the
    /// real RAWDecoder decodes).
    private let decodeLeg: ThumbnailDecodeLeg?
    private let renderLeg: ThumbnailRenderLeg?
    private let runContextInjector: ThumbnailRunContextInjector?
    /// The catalog READ face (the session-roots source). A PROVIDER
    /// CLOSURE — the shared runtime store is rebuilt on a location
    /// re-point, and the router must always read the CURRENT instance.
    private let catalogStoreProvider: () -> CatalogIndexStore

    init(
        memory: ThumbnailMemoryCache,
        registry: ModuleRegistry,
        decoder: RAWDecoder?,
        decodeLeg: ThumbnailDecodeLeg? = nil,
        renderLeg: ThumbnailRenderLeg?,
        runContextInjector: ThumbnailRunContextInjector?,
        catalogStoreProvider: @escaping () -> CatalogIndexStore
    ) {
        self.memory = memory
        self.registry = registry
        self.decoder = decoder
        self.decodeLeg = decodeLeg
        self.renderLeg = renderLeg
        self.runContextInjector = runContextInjector
        self.catalogStoreProvider = catalogStoreProvider
    }

    // MARK: - Read faces

    func isOffline(_ sessionID: String) -> Bool {
        offlineSessionIDs.contains(sessionID)
    }

    /// A provider EXISTED for the session (pool introspection for tests).
    func hasProvider(_ sessionID: String) -> Bool {
        providers[sessionID] != nil
    }

    var poolCount: Int { providers.count }

    // MARK: - Routing

    /// The routed fetch: nil = offline/unknown session (the caller paints
    /// the gray placeholder; nothing was enqueued).
    func thumbnail(
        sessionID: String, relPath: String, visible: Bool = true
    ) async -> CGImage? {
        guard let provider = await provider(for: sessionID) else { return nil }
        return await provider.thumbnail(for: relPath, visible: visible)
    }

    /// The visible-priority jump routed into the owning provider.
    func prioritize(sessionID: String, relPath: String) async {
        await provider(for: sessionID)?.prioritize(relPath: relPath)
    }

    /// The lazy pool access (deduped across concurrent cells).
    func provider(for sessionID: String) async -> SessionThumbnailProvider? {
        if let cached = providers[sessionID] { return cached }
        if offlineSessionIDs.contains(sessionID) { return nil }
        if let existing = openingTasks[sessionID] {
            return await existing.value
        }
        let task = Task { [self] in
            await self.makeProvider(sessionID: sessionID)
        }
        openingTasks[sessionID] = task
        let provider = await task.value
        openingTasks[sessionID] = nil
        if let provider {
            providers[sessionID] = provider
        } else {
            offlineSessionIDs.insert(sessionID)
        }
        return provider
    }

    /// The registry map refresh (after a sweep / re-link / remove changed
    /// catalog_sessions; also forces the offline probes to re-run — a
    /// re-mounted volume recovers on the next grid visit).
    func invalidateRoots() {
        rootsLoaded = false
        sessionRoots = [:]
        offlineSessionIDs = []
    }

    /// The pool teardown (leaving Catalogs mode / the grid's disappear):
    /// pending jobs drop, in-flight results are discarded via the
    /// generation gate, and every provider reference releases.
    func teardown() async {
        for (_, provider) in providers {
            await provider.cancelAll()
        }
        providers.removeAll()
        openingTasks.values.forEach { $0.cancel() }
        openingTasks.removeAll()
    }

    // MARK: - Internals

    private func loadRootsIfNeeded() async {
        guard !rootsLoaded else { return }
        let rows = (try? await catalogStoreProvider().fetchSessions()) ?? []
        var roots: [String: URL] = [:]
        for row in rows {
            roots[row.sessionID] = URL(fileURLWithPath: row.rootPath, isDirectory: true)
            if row.offline == 1 {
                offlineSessionIDs.insert(row.sessionID)
            }
        }
        sessionRoots = roots
        rootsLoaded = true
    }

    private func makeProvider(
        sessionID: String
    ) async -> SessionThumbnailProvider? {
        await loadRootsIfNeeded()
        guard let root = sessionRoots[sessionID] else {
            Self.logger.warning("thumbnail route: unknown session \(sessionID)")
            return nil
        }
        // The offline probe: the root must exist (D-16-CONTEXT-7② — the
        // stat is the re-mount recovery face; a registry-offline row was
        // pre-seeded and skips the stat entirely).
        guard !offlineSessionIDs.contains(sessionID),
              FileManager.default.fileExists(atPath: root.path) else {
            return nil
        }
        // The open rides the REAL open+sync flow (the same leg a session
        // open runs) — the provider's tier ruling needs honest rows.
        let store = SessionIndexStore(sessionRoot: root)
        do {
            _ = try await store.openSession(
                root: root, scan: SessionTreeScanner.scan(root: root))
        } catch {
            Self.logger.warning(
                "thumbnail route: session open failed (\(error.localizedDescription, privacy: .public))")
            return nil
        }
        return SessionThumbnailProvider(
            sessionRoot: root,
            store: store,
            disk: ThumbnailDiskStore(sessionRoot: root),
            memory: memory,
            registry: registry,
            decoder: decoder,
            decodeLeg: decodeLeg,
            renderLeg: renderLeg,
            runContextInjector: runContextInjector,
            memoryKeyPrefix: sessionID + "/"
        )
    }
}
