import Foundation
import LightamerCore
import Observation

/// Session-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the current session folder, the recent-sessions list, the
/// folder-watch status, and the lightweight browse-count snapshot shown in
/// the sidebar. Does NOT own image data, layers, or inspector selection,
/// and holds no references to the other state objects — cross-state
/// coordination flows through the View layer / `SessionCoordinator`
/// (Plan 09-01 T1).
///
/// The full browse ROW model (grid cells) arrives in Plan 9-3 backed by
/// `SessionIndexStore` queries; this state carries only the sidebar-visible
/// counts snapshot.
@Observable
@MainActor
final class SessionState {

    /// The folder backing the current Capture One-style session.
    private(set) var currentSessionURL: URL?

    /// Recent sessions (Plan 09-01 T1): persisted in `UserDefaults` (upper
    /// bound 10, dedupe-move-front, missing paths pruned on load AND on
    /// promote). The backing store is injectable for tests.
    private(set) var recentSessions: [URL] = []

    /// Folder-watch status (Plan 9-2 wires the REAL FSEvents source; the
    /// enum is the 9-1 state machine shell — `SessionCoordinator` flips it
    /// to `.scanning`/`.synced` around the open-session sync).
    private(set) var folderWatchStatus: FolderWatchStatus = .notWatching

    /// Lightweight browse-collection counts snapshot for the sidebar
    /// (total images / edited / orphan-sidecar rows). nil = no session open
    /// or the first sync has not landed yet. Full row model: Plan 9-3.
    private(set) var browseCounts: SessionBrowseCounts?

    /// The current session's ROOT was reported renamed/moved (the WatchRoot
    /// leg, 09-02 T4) — the sidebar surfaces a status hint and the
    /// recent-path entries pointing at the old root are flagged stale for
    /// re-confirmation. Cleared on the next successful session open.
    private(set) var currentSessionRootLost = false

    /// The actionable orphan-sidecar snapshot (relPaths of `.lra` rows whose
    /// original is gone, IGNORED entries filtered — 09-02 T4). The sidebar
    /// renders the remove/ignore actions off this; 9-3 takes the grid badge.
    private(set) var orphanSidecarRelPaths: [String] = []

    /// The recent-list persistence defaults. Injectable (test suite);
    /// nil disables persistence entirely (pure in-memory, unit tests).
    private let recentDefaults: UserDefaults?

    /// `UserDefaults` key holding the recent-session PATH strings.
    nonisolated static let recentStorageKey = "session.recentPaths"

    /// Recent-list upper bound (SESS-04: "~10").
    nonisolated static let recentLimit = 10

    // MARK: - Filter / sort / Quick Filter face (Plan 12-2 T4)

    /// `UserDefaults` keys for the persisted sort (execution decision,
    /// 12-2-DECISIONS — two flat keys, key-rawValue + direction).
    nonisolated static let sortKeyStorageKey = "browser.sort.key"
    nonisolated static let sortAscendingStorageKey = "browser.sort.ascending"

    /// The active FILTER CHIPS (each rule AND-joins with the others — the
    /// chips are the transient predicate group's projection; D-12-CONTEXT-7).
    /// The Quick Filter folds separately (see `queryGroups`).
    private(set) var filterChips: [FilterPredicateGroup.Rule] = []

    /// The Quick Filter text (raw, untrimmed; the group folds on read).
    private(set) var quickFilterText: String = ""

    /// The persisted sort (defaults key face).
    private(set) var sort: FilterSort

    /// Monotonic observation bump — the View layer's onChange anchor (the
    /// group contents are value types; the revision is the single thing to
    /// observe).
    private(set) var filterRevision = 0

    /// The re-query orchestration seam (D-03b: SessionState holds no state
    /// references — the App root injects the closure that re-runs the
    /// browser model reload through the current store; the same shape as
    /// SessionCoordinator's injected handlers).
    var onFilterChanged: (() async -> Void)?

    /// Debounce task for the text-driven re-query (chips/sort changes fire
    /// immediately).
    private var filterRefreshTask: Task<Void, Never>?

    /// The Quick Filter debounce interval (execution decision,
    /// 12-2-DECISIONS: 200ms — fast enough to feel live, slow enough to
    /// collapse a typed word into one query).
    nonisolated static let quickFilterDebounce: Duration = .milliseconds(200)

    init(recentDefaults: UserDefaults? = .standard) {
        self.recentDefaults = recentDefaults
        recentSessions = Self.loadRecent(from: recentDefaults)
        // Sort restore (defaults = filename ascending — the legacy path
        // order's key).
        if let raw = recentDefaults?.string(forKey: Self.sortKeyStorageKey),
           let key = FilterSortKey(rawValue: raw) {
            sort = FilterSort(
                key: key,
                ascending: recentDefaults?.object(forKey: Self.sortAscendingStorageKey) as? Bool
                    ?? true)
        } else {
            sort = FilterSort(key: .filename, ascending: true)
        }
    }

    /// The query groups (chips AND Quick Filter — the App root hands BOTH
    /// to the query face's group array; each translates through the ONE
    /// layer and joins with the baseline attached once). An ACTIVE smart
    /// album replaces the chip face (the mutual-exclusion decision) — its
    /// group is the sole constraint.
    var queryGroups: [FilterPredicateGroup] {
        if let group = activeSmartAlbumGroup { return [group] }
        var groups: [FilterPredicateGroup] = []
        if !filterChips.isEmpty {
            groups.append(FilterPredicateGroup(match: .all, rules: filterChips))
        }
        let trimmed = quickFilterText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            groups.append(.quickFilter(text: trimmed))
        }
        return groups
    }

    /// True when any face is active (the model's placeholder-page guard
    /// + the UI's clear affordance read this).
    var hasActiveFilter: Bool {
        !filterChips.isEmpty || !quickFilterText.isEmpty || activeSmartAlbumID != nil
    }

    /// Replace the whole chip set (the filter bar's chips row is a
    /// two-way projection of this list).
    func setFilterChips(_ chips: [FilterPredicateGroup.Rule]) {
        filterChips = chips
        scheduleFilterRefresh(debounced: false)
    }

    /// Toggle one chip (single click: present → remove, absent → add).
    func toggleChip(_ chip: FilterPredicateGroup.Rule) {
        if let index = filterChips.firstIndex(of: chip) {
            filterChips.remove(at: index)
        } else {
            filterChips.append(chip)
        }
        scheduleFilterRefresh(debounced: false)
    }

    /// Remove one chip (the custom chips' ⓧ / the long-press delete face).
    func removeChip(_ chip: FilterPredicateGroup.Rule) {
        filterChips.removeAll { $0 == chip }
        scheduleFilterRefresh(debounced: false)
    }

    /// Set the Quick Filter text (debounced re-query).
    func setQuickFilterText(_ text: String) {
        quickFilterText = text
        scheduleFilterRefresh(debounced: true)
    }

    /// Set the sort (persisted immediately; immediate re-query).
    func setSort(_ newSort: FilterSort) {
        sort = newSort
        if let recentDefaults {
            recentDefaults.set(newSort.key.rawValue, forKey: Self.sortKeyStorageKey)
            recentDefaults.set(newSort.ascending, forKey: Self.sortAscendingStorageKey)
        }
        scheduleFilterRefresh(debounced: false)
    }

    // MARK: - Smart album face (Plan 12-2 T5; D-12-CONTEXT-4)

    /// The ACTIVE smart album (nil = the plain chip face). Activation
    /// REPLACES the chip set (execution decision, 12-2-DECISIONS: the
    /// album's group and the chip face are mutually exclusive — stacking
    /// them would AND an uncontrolled double constraint; the chips the
    /// album was created from are exactly its rules).
    private(set) var activeSmartAlbumID: String?
    private(set) var activeSmartAlbumGroup: FilterPredicateGroup?

    /// Activate/deactivate. The group rides along so the re-query closure
    /// needs no store access (规则随 app / 结果随会话 — the evaluation
    /// happens against whatever session is open at refresh time).
    func activateSmartAlbum(id: String?, group: FilterPredicateGroup?) {
        activeSmartAlbumID = id
        activeSmartAlbumGroup = group
        if id != nil { filterChips = [] }
        scheduleFilterRefresh(debounced: false)
    }

    /// Clear every filter face (chips + Quick Filter + the active smart
    /// album — the ⓧ in the filter bar).
    func clearFilters() {
        guard hasActiveFilter else { return }
        filterChips = []
        quickFilterText = ""
        activeSmartAlbumID = nil
        activeSmartAlbumGroup = nil
        scheduleFilterRefresh(debounced: false)
    }

    /// The refresh orchestration: chips/sort fire at once; the Quick
    /// Filter text debounces. The injected closure does the actual re-query
    /// (nil = unit-test wiring, no-op).
    private func scheduleFilterRefresh(debounced: Bool) {
        filterRevision += 1
        filterRefreshTask?.cancel()
        guard onFilterChanged != nil else { return }
        filterRefreshTask = Task { [onFilterChanged] in
            if debounced {
                try? await Task.sleep(for: Self.quickFilterDebounce)
            }
            guard !Task.isCancelled else { return }
            await onFilterChanged?()
        }
    }

    // MARK: - Mutation entries (SessionCoordinator is the writer)

    /// Bind the current session (nil = close). Every binding clears the
    /// root-lost hint (a fresh open/switch is the recovery path).
    func setCurrentSession(_ url: URL?) {
        currentSessionURL = url
        if url == nil {
            browseCounts = nil
            orphanSidecarRelPaths = []
        }
        currentSessionRootLost = false
    }

    /// Publish the actionable orphan snapshot (sorted, ignored filtered).
    func setOrphanSidecarRelPaths(_ relPaths: [String]) {
        orphanSidecarRelPaths = relPaths
    }

    /// Flip the watch-status state machine.
    func setWatchStatus(_ status: FolderWatchStatus) {
        folderWatchStatus = status
    }

    /// The WatchRoot leg fired for the CURRENT session root (09-02 T4):
    /// surface the hint; the recent list is NOT silently rewritten (L012 —
    /// opening a session is always an explicit user action).
    func markCurrentSessionRootLost() {
        currentSessionRootLost = true
        folderWatchStatus = .rootLost
    }

    /// Publish the sidebar counts snapshot.
    func setBrowseCounts(_ counts: SessionBrowseCounts?) {
        browseCounts = counts
    }

    /// Promote `url` to the front of the recent list (dedupe-move-front,
    /// cap `Self.recentLimit`, prune paths that no longer exist). Writes
    /// through to the injected defaults. The PROMOTED url itself is not
    /// existence-checked here (it was just used); stale entries ahead of
    /// it are.
    func promoteRecent(_ url: URL) {
        var next: [URL] = [url]
        for existing in recentSessions where existing != url {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: existing.path, isDirectory: &isDirectory) {
                next.append(existing)
            }
        }
        if next.count > Self.recentLimit {
            next.removeLast(next.count - Self.recentLimit)
        }
        recentSessions = next
        persistRecent()
    }

    /// Drop recent entries whose path no longer exists (repair pass; also
    /// runs at init via `loadRecent`).
    func pruneMissingRecents() {
        let kept = recentSessions.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard kept.count != recentSessions.count else { return }
        recentSessions = kept
        persistRecent()
    }

    // MARK: - Persistence

    private func persistRecent() {
        guard let recentDefaults else { return }
        recentDefaults.set(recentSessions.map(\.path), forKey: Self.recentStorageKey)
    }

    private nonisolated static func loadRecent(from defaults: UserDefaults?) -> [URL] {
        guard let defaults,
              let paths = defaults.stringArray(forKey: recentStorageKey)
        else { return [] }
        return paths
            .compactMap { attempt in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: attempt, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else { return nil }
                return URL(fileURLWithPath: attempt, isDirectory: true)
            }
            .prefix(recentLimit)
            .map(\.self)
    }
}

/// Folder-watch state machine (SESS-05; Plan 9-2 feeds the real source).
/// Five states (09-02 T4): `scanning` = an open/reconcile walk is in
/// flight; `synced` = the index matches the tree; `stale` = events landed
/// that the index has not reconciled yet; `rootLost` = the WatchRoot event
/// reported the session root renamed/moved (full rescan + the recent-path
/// invalidation hint — never a silent path rewrite).
enum FolderWatchStatus: String, Sendable {
    case notWatching
    case scanning
    case synced
    case stale
    case rootLost

    /// Sidebar-facing localized label (L010: leaf-level label, never on a
    /// container).
    var displayKey: String {
        switch self {
        case .notWatching: "session_watch_not_watching"
        case .scanning: "session_watch_scanning"
        case .synced: "session_watch_synced"
        case .stale: "session_watch_stale"
        case .rootLost: "session_watch_root_lost"
        }
    }
}

/// The sidebar-visible browse-collection counts snapshot (Plan 09-01 T1).
struct SessionBrowseCounts: Equatable, Sendable {
    /// Images in the browse set (originals; sidecars/retained dirs excluded).
    var total: Int
    /// Rows with `has_edits = 1`.
    var edited: Int
    /// Orphan-sidecar rows (`.lra` without its original — never hard-fails).
    var orphans: Int
}
