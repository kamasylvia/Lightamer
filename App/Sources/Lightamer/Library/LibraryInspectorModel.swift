import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryInspectorModel (Plan M2-3-2 T2, KD-2 / KD-5) — the Album Inspector's
// pure-logic face: group loading, click-to-filter folding, breadcrumb
// retreat, the overview card, the Activity series and the smart-album leg.
// The view renders from THIS and carries zero business logic.
//
// ZERO SQL (the M2-2-3 seam): every datum rides the nine-signature query
// face — `overviewCount` / `groupCounts(by:)` / `activitySeries` /
// `dayFilter` / `currentFilterDescription` / `SmartAlbumStore.evaluate(.library)`
// — over the SAME `LibraryGridModel` filter the grid and filmstrip render
// from (one collection state, never a copy).
//
// CLICK SEMANTICS (KD-2): a group click folds ONE typed payload into the
// filter's predicate group as an ARM (a named bundle of rules); clicking the
// same arm again removes it (反选); the breadcrumb retreats per arm. The
// payload stays typed end-to-end (day string / camera make+model / rating
// tier / lens string) — never a label re-parse.
//
// EXPRESSIBILITY (KD-2 risk note, resolved): every arm rides an EXISTING
// FilterField — camera/lens "Unknown" tiers fold as `.empty` rules (the
// NULL-or-empty class the text face already carries); the Unrated star tier
// has NO legal rule shape (rating's op list carries no `.empty`) and is
// rendered INERT (present, non-clickable) rather than widening FilterSQL —
// the Session-domain freeze wins.
//
// SMART ALBUMS (KD-5): a click evaluates the album's member set through
// `SmartAlbumStore.evaluate(.library)` (the closed loop — typed missingStore
// when no query face is injected: the no-project defense) and folds the
// ALBUM'S OWN predicate group as the arm (成员集 → 相册谓词 — the member
// set is what the grid then shows; the rules are how).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class LibraryInspectorModel {

    // MARK: - The arm model (one click = one arm)

    /// One folded click-filter arm: the typed click payload + the rules it
    /// contributed to the filter group (the breadcrumb's atom).
    struct FilterArm: Equatable {
        enum Source: Equatable {
            case day(String)
            case camera(make: String?, model: String?)
            case rating(Int)
            case lens(String?)
            case smartAlbum(id: String)
        }

        let source: Source
        let rules: [FilterPredicateGroup.Rule]
    }

    // MARK: - State (the render sources)

    private(set) var overviewCount = 0
    private(set) var groups: [LibraryGroupKey: [LibraryGroupCount]] = [:]
    private(set) var activity: [(day: String, count: Int)] = []
    private(set) var filterDescription: LibraryFilterDescription?
    private(set) var smartAlbumRows: [SmartAlbum] = []
    /// The evaluated member counts per smart-album id (the row's count chip;
    /// a failed evaluation simply leaves the id out).
    private(set) var smartAlbumMemberCounts: [String: Int] = [:]
    /// The typed missingStore face (KD-5: nil query-face injection — the
    /// no-project defense; the panel shows the honest empty state).
    private(set) var smartAlbumsUnavailable = false
    /// The folded arms in click order (the breadcrumb source).
    private(set) var arms: [FilterArm] = []
    private(set) var isLoading = false

    private let grid: LibraryGridModel
    /// nil = the no-project defense (KD-5) — group/overview/Activity faces
    /// idle and smart albums render the typed empty state.
    private let queries: LibraryQueries?
    private let smartAlbums: SmartAlbumStore?

    init(
        grid: LibraryGridModel,
        queries: LibraryQueries?,
        smartAlbums: SmartAlbumStore? = nil
    ) {
        self.grid = grid
        self.queries = queries
        self.smartAlbums = smartAlbums
    }

    // MARK: - The relink entry (Plan M2-3-2 T4, KD-4)

    /// The selected rows (the batch-relink acts on the grid's live
    /// selection; the sheet classifies them into the two stale forms).
    var selectedRows: [LibraryImageRow] {
        grid.rows.filter { grid.selectedIDs.contains($0.id) }
    }

    /// The selection size (the entry button's enabled face).
    var selectedCount: Int { grid.selectedIDs.count }

    // MARK: - Load (every render source, in one sweep)

    /// Reload every render source from the CURRENT grid filter. Called at
    /// mount and after every filter mutation (the counts ride the filter —
    /// the 总数卡联动).
    func refresh() async {
        guard let queries else { return }
        isLoading = true
        defer { isLoading = false }
        let filter = grid.filter
        // M2-10-02 (KD-6): an active semantic overlay IS the collection —
        // the count card shows the HIT count, not the filter aggregate.
        if let hits = grid.semanticHits {
            overviewCount = hits.count
        } else {
            overviewCount = (try? await queries.overviewCount(filter: filter)) ?? 0
        }
        for key in LibraryGroupKey.allCases {
            groups[key] = (try? await queries.groupCounts(by: key, filter: filter)) ?? []
        }
        activity = (try? await queries.activitySeries(filter: filter)) ?? []
        filterDescription = await queries.currentFilterDescription(filter: filter)
        await refreshSmartAlbums()
    }

    /// The smart-album rows + the member-count loop (KD-5's evaluate leg —
    /// the closed loop over `.library`).
    private func refreshSmartAlbums() async {
        smartAlbumRows = smartAlbums?.albums() ?? []
        guard let queries, let smartAlbums else { return }
        var counts: [String: Int] = [:]
        for album in smartAlbumRows {
            if let evaluation = try? await smartAlbums.evaluate(
                id: album.id,
                domain: .library,
                sessionStore: nil,
                catalogStore: nil,
                libraryQueries: queries),
                case .library(let ids) = evaluation {
                counts[album.id] = ids.count
            }
        }
        smartAlbumMemberCounts = counts
    }

    // MARK: - Group clicks (KD-2: typed payload → arm fold)

    /// A group-row click (captureDate/camera/labels/lens). Same-arm re-click
    /// = 反选. The Unrated rating tier carries no legal rule shape — the
    /// click is refused here (the view renders it inert).
    func toggle(group: LibraryGroupKey, payload: LibraryGroupCount) async {
        let source: FilterArm.Source
        switch group {
        case .captureDate:
            guard let day = payload.day else { return }
            source = .day(day)
        case .camera:
            source = .camera(make: payload.cameraMake, model: payload.cameraModel)
        case .labels:
            guard let rating = payload.rating else { return }  // Unrated: inert
            source = .rating(rating)
        case .lens:
            source = .lens(payload.lensModel)
        }
        await toggle(source: source)
    }

    /// An Activity bar click = the same date leg as a capture-date row.
    func toggleActivityDay(_ day: String) async {
        await toggle(source: .day(day))
    }

    /// A smart-album click (KD-5): the typed member-set evaluation closes
    /// the loop; the album's own group folds as the arm. A missing query
    /// face (or store) sets the typed unavailable face instead — never a
    /// silent empty result.
    func toggleSmartAlbum(_ album: SmartAlbum) async {
        guard let queries, let smartAlbums else {
            smartAlbumsUnavailable = true
            return
        }
        do {
            let evaluation = try await smartAlbums.evaluate(
                id: album.id,
                domain: .library,
                sessionStore: nil,
                catalogStore: nil,
                libraryQueries: queries)
            guard case .library(let ids) = evaluation else { return }
            smartAlbumMemberCounts[album.id] = ids.count
            smartAlbumsUnavailable = false
        } catch {
            // The typed refusal (missingStore / notFound) — the empty state.
            smartAlbumsUnavailable = true
            return
        }
        await toggle(source: .smartAlbum(id: album.id), extraRules: album.group.rules)
    }

    /// The shared fold: remove the arm when its source is already folded
    /// (反选), else append it — then rebuild the filter group and reapply.
    private func toggle(
        source: FilterArm.Source, extraRules: [FilterPredicateGroup.Rule] = []
    ) async {
        if let index = arms.firstIndex(where: { $0.source == source }) {
            arms.remove(at: index)
        } else {
            guard let arm = makeArm(source: source, extraRules: extraRules) else {
                return
            }
            arms.append(arm)
        }
        await applyArms()
    }

    /// The breadcrumb retreat: drop ONE arm, reapply.
    func removeArm(at index: Int) async {
        guard arms.indices.contains(index) else { return }
        arms.remove(at: index)
        await applyArms()
    }

    /// Drop every arm AND the lexical plan (the panel's clear-all face).
    func clearFilter() async {
        arms.removeAll()
        try? await grid.apply(filter: ExifSearchFilter())
        await refresh()
    }

    private func applyArms() async {
        let group = FilterPredicateGroup(
            match: .all, rules: arms.flatMap(\.rules))
        try? await grid.apply(filter: ExifSearchFilter(group: group, plan: grid.filter.plan))
        await refresh()
    }

    // MARK: - Arm construction (the typed payload → rule translation)

    private func makeArm(
        source: FilterArm.Source, extraRules: [FilterPredicateGroup.Rule]
    ) -> FilterArm? {
        switch source {
        case .day(let day):
            // The existing day projection (the UTC whole-day between) —
            // verbatim reuse, zero new rule shapes.
            guard let group = try? LibraryQueries.dayFilter(day) else { return nil }
            return FilterArm(source: source, rules: group.rules)
        case .camera(let make, let model):
            var rules: [FilterPredicateGroup.Rule] = []
            rules.append(contentsOf: textArmRules(
                field: .cameraMake, value: make))
            rules.append(contentsOf: textArmRules(
                field: .cameraModel, value: model))
            return FilterArm(source: source, rules: rules)
        case .rating(let rating):
            return FilterArm(
                source: source,
                rules: [FilterPredicateGroup.Rule(
                    field: .rating, op: .eq, value: .int(rating))])
        case .lens(let lens):
            return FilterArm(
                source: source,
                rules: textArmRules(field: .lensModel, value: lens))
        case .smartAlbum:
            return FilterArm(source: source, rules: extraRules)
        }
    }

    /// A text-tier arm: a known value folds as `eq`; the Unknown tier (nil
    /// payload after the query face's normalization) folds as `.empty` —
    /// the NULL-or-empty class the text face already carries.
    private func textArmRules(
        field: FilterField, value: String?
    ) -> [FilterPredicateGroup.Rule] {
        let rule: FilterPredicateGroup.Rule
        if let value {
            rule = FilterPredicateGroup.Rule(
                field: field, op: .eq, value: .text(value))
        } else {
            rule = FilterPredicateGroup.Rule(
                field: field, op: .empty, value: .text(""))
        }
        return [rule]
    }
}
