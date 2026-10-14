import Foundation
import LightamerCore
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// StackPaginationTests (Plan M6-4-01 T4, KD-5/KD-7) — the stack-aware
// pagination face over a REAL `.lalb`:
//
//   ① the collapsed predicate (collapsed stacks leave covers only)
//   ② `.flat` byte identity — dual evidence: the no-arg call compiles and
//      returns ROW-IDENTICAL pages to the explicit `.flat` call (the
//      call-site grep inventory rides DECISIONS; runPage has no SQL
//      capture seam, so a SQL-assembly-diff assertion is UNLANDABLE —
//      plan M2's wording)
//   ③ the NULL-tail leg carries the predicate
//   ④ the mixed collapsed/expanded grid (the flag rides the join)
//   ⑤ memberships map (position/size/collapsed)
//   ⑥ rows(byIDs:) order + the missing-id face
//   ⑦ the forward-only fixup PURE transform (前插 + displayed 去重 + 保序)
//   ⑧ cross-page keyset walk under the predicate (anchor chain, no
//      gap/overlap)
//   ⑨ the expanded-walk union golden: query pages + per-page fixup ==
//      the `.flat` full-walk id set
//
// The fixup host is the App model (KD-7); per checker O-3 the transform's
// tests import the Lightamer App module from this LIB-domain file — no
// Core fixup file exists (the files_modified additive declaration holds).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class StackPaginationTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!
    private var queries: LibraryQueries!

    // Insertion order == filename ASC order (filename ASC walks rowid order
    // — the LibraryGridModelTests pin), so "rows 0-9" below are rowids 1-10.

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("stack-page-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("StackPage.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "StackPage")
        store = LibraryStore(store: fileStore)
        queries = LibraryQueries(store: fileStore)
        // Ten rows, filename ASC == rowid ASC; capture dates staggered so
        // the date sort has no ties.
        for index in 1...10 {
            try await fileStore.withWriteBatch { handle -> Bool in
                let insert = try handle.prepare(
                    "INSERT INTO images (image_path, path_kind, capture_date,"
                        + " file_stem, filename) VALUES (?, 0, ?, ?, ?)")
                try insert.bindText(1, "Media/r\(index).arw")
                try insert.bindDouble(2, Double(index))
                try insert.bindText(3, String(format: "r%02d", index))
                try insert.bindText(4, String(format: "r%02d.arw", index))
                _ = try insert.step()
                return true
            }
        }
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Stack rows [i0, i1, ...] as ids are rowids: `stack(ids:)` maps
    /// insertion-order indexes to rowids.
    private func rowIDs(_ indexes: [Int]) -> [Int64] {
        indexes.map { Int64($0 + 1) }
    }

    private func makeSort() -> FilterSort {
        FilterSort(key: .filename, ascending: true)
    }

    // MARK: - ① the collapsed predicate

    func testCollapsedPredicateLeavesCoversOnly() async throws {
        let ids = rowIDs([0, 1, 2])
        let stack = try await store.createStack(
            memberIDs: ids, collapsed: true)
        // .flat sees all ten rows, .collapsed sees eight (the two non-cover
        // members of the collapsed stack are hidden).
        let flat = try await queries.searchPage(sort: makeSort(), limit: 100)
        XCTAssertEqual(flat.count, 10)
        let collapsed = try await queries.searchPage(
            sort: makeSort(), limit: 100, stackMode: .collapsed)
        XCTAssertEqual(collapsed.count, 8)
        let hidden = Set(flat.map(\.id)).subtracting(collapsed.map(\.id))
        XCTAssertEqual(hidden, Set([ids[1], ids[2]]))
        // Unfold → every member returns.
        try await store.setCollapsed(stackID: stack.id, collapsed: false)
        let expanded = try await queries.searchPage(
            sort: makeSort(), limit: 100, stackMode: .collapsed)
        XCTAssertEqual(expanded.count, 10)
    }

    // MARK: - ② .flat byte identity (row-level evidence)

    func testFlatDefaultArgumentIsRowIdentical() async throws {
        let ids = rowIDs([0, 1, 2])
        _ = try await store.createStack(memberIDs: ids, collapsed: true)
        let sort = makeSort()
        // Walk both segments with NO stackMode argument at all (the exact
        // shape every pre-stacks call site compiles to).
        var noArg: [LibraryImageRow] = []
        var anchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                sort: sort, anchor: anchor, limit: 3)
            noArg.append(contentsOf: page)
            guard page.count == 3, let last = page.last else { break }
            anchor = LibraryPageAnchor(
                keyValue: .text(last.filename ?? ""), imagePath: last.imagePath)
        }
        var tailAnchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchNullTail(
                sort: sort, anchor: tailAnchor, limit: 3)
            noArg.append(contentsOf: page)
            guard page.count == 3, let last = page.last else { break }
            tailAnchor = LibraryPageAnchor(
                keyValue: .int(nil), imagePath: last.imagePath)
        }
        // The explicit .flat spelling: row-for-row identical.
        let explicit = try await queries.searchPage(
            sort: sort, limit: 100, stackMode: .flat)
        XCTAssertEqual(noArg, explicit, "the default IS .flat, row-for-row")
        XCTAssertEqual(noArg.count, 10)
    }

    // MARK: - ③ the NULL-tail leg

    func testNullTailLegCarriesThePredicate() async throws {
        // r01 + r02 stack (collapsed); both carry a NULL rating — the tail
        // leg would see both, the predicate hides the non-cover.
        let ids = rowIDs([0, 1])
        _ = try await store.createStack(memberIDs: ids, collapsed: true)
        let sort = FilterSort(key: .rating, ascending: true)
        let flatTail = try await queries.searchNullTail(
            sort: sort, limit: 100)
        XCTAssertEqual(flatTail.count, 10, "all ten rows lack ratings")
        let collapsedTail = try await queries.searchNullTail(
            sort: sort, limit: 100, stackMode: .collapsed)
        XCTAssertEqual(collapsedTail.count, 9)
        XCTAssertFalse(
            collapsedTail.contains { $0.id == ids[1] },
            "the non-cover member is hidden in the tail leg too")
    }

    // MARK: - ④ the mixed collapsed/expanded grid

    func testMixedCollapsedAndExpandedStacks() async throws {
        let collapsedIDs = rowIDs([0, 1, 2])
        _ = try await store.createStack(
            memberIDs: collapsedIDs, collapsed: true)
        let expandedIDs = rowIDs([5, 6])
        _ = try await store.createStack(
            memberIDs: expandedIDs, collapsed: false)
        let collapsed = try await queries.searchPage(
            sort: makeSort(), limit: 100, stackMode: .collapsed)
        let visible = Set(collapsed.map(\.id))
        XCTAssertEqual(Set(collapsedIDs).subtracting(visible), Set(collapsedIDs[1...2]),
                       "the collapsed stack hides its non-covers")
        XCTAssertTrue(
            expandedIDs.allSatisfy(visible.contains),
            "the expanded stack shows ALL its members in collapsed mode")
    }

    // MARK: - ⑤ memberships

    func testStackMembershipsMap() async throws {
        let ids = rowIDs([0, 1, 2])
        let stack = try await store.createStack(
            memberIDs: ids, collapsed: true)
        let memberships = try await queries.stackMemberships(ids: ids + [99])
        XCTAssertEqual(memberships.count, 3, "the unstacked probe id drops")
        for (index, id) in ids.enumerated() {
            let membership = try XCTUnwrap(memberships[id])
            XCTAssertEqual(membership.stackID, stack.id)
            XCTAssertEqual(membership.position, Int64(index))
            XCTAssertEqual(membership.size, 3)
            XCTAssertTrue(membership.collapsed)
        }
        XCTAssertEqual(memberships[ids[0]]?.position, 0, "the cover is position 0")
    }

    // MARK: - ⑥ rows(byIDs:)

    func testRowsByIDSGivenOrderAndMissingFace() async throws {
        let ids = rowIDs([0, 4, 2])
        let rows = try await queries.rows(byIDs: ids + [9_999])
        XCTAssertEqual(
            rows.map(\.id), ids,
            "the given order rules; the missing id drops out")
        let empty = try await queries.rows(byIDs: [])
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - ⑦ the forward-only fixup pure transform

    func testForwardOnlyFixupPureTransform() throws {
        // Displayed: [r00, r05]. A new page brings r01 (a member of the
        // stack [r01, r02, r03] whose cover r02 is NOT displayed) and r06.
        // The transform gathers r02+... wait — the fixture: stack S =
        // [r02, r01, r03] positions (cover r02, then r01, r03); the page
        // carries r01 + r06; supplemental rows for r02/r03 provided.
        func row(_ id: Int64) -> LibraryImageRow {
            LibraryImageRow(
                id: id, imagePath: "Media/r\(id)", pathKind: 0, volumeUUID: nil,
                cameraMake: nil, cameraModel: nil, lensModel: nil, iso: nil,
                focalLength: nil, aperture: nil, exposure: nil, captureDate: nil,
                fileStem: nil, fileExt: nil, exifSearchText: nil,
                exifSearchWords: nil, rating: nil, colorLabel: nil, keywords: nil,
                filename: "r\(id).arw", dir: nil, flag: nil, note: nil,
                hasEdits: nil, paramsHash: nil, refCount: 0, addedTime: nil,
                modifiedTime: nil)
        }
        let displayedRows = [row(10), row(15)]
        let displayed = Set(displayedRows.map(\.id))
        let page = [row(11), row(16)]
        let stackID: Int64 = 77
        let memberships: [Int64: StackMembership] = [
            11: StackMembership(stackID: stackID, position: 1, size: 3, collapsed: false),
        ]
        let memberLists: [Int64: [Int64]] = [
            stackID: [12, 11, 13],  // cover 12, then 11, then 13
        ]
        let supplemental: [Int64: LibraryImageRow] = [
            12: row(12), 13: row(13),
        ]
        let outcome = LibraryGridModel.stackAdjacencyFixup(
            rows: displayedRows + page,
            memberships: memberships,
            memberLists: memberLists,
            supplemental: supplemental,
            displayed: displayed.union(page.map(\.id)))
        // The members gathered FORWARD, right after the earliest displayed
        // member of the stack (r11), in stack position order (12, 13):
        let expected = [
            row(10), row(15), row(11), row(12), row(13), row(16),
        ]
        XCTAssertEqual(outcome.rows.map(\.id), expected.map(\.id))
        XCTAssertEqual(
            outcome.inserted, [12, 13], "only the missing members inserted")
        XCTAssertEqual(outcome.displayed, Set([10, 15, 11, 12, 13, 16]))

        // The displayed-guard: a member already shown EARLIER (forward-only
        // — no re-pull) is not inserted again; the page row itself is kept.
        let alreadyShown: [Int64: StackMembership] = [
            16: StackMembership(stackID: 78, position: 1, size: 2, collapsed: false),
        ]
        let repeatOutcome = LibraryGridModel.stackAdjacencyFixup(
            rows: [row(16)],
            memberships: alreadyShown,
            memberLists: [78: [15, 16]],
            supplemental: [15: row(15)],
            displayed: [15, 16])
        XCTAssertEqual(
            repeatOutcome.rows.map(\.id), [16],
            "the earlier-page member 15 is NOT re-pulled (forward-only)")
        XCTAssertEqual(repeatOutcome.inserted, [])
    }

    // MARK: - ⑧ cross-page keyset walk under the predicate

    func testCrossPageWalkUnderPredicateNoGapNoOverlap() async throws {
        // Three collapsed 2-stacks: 6 covers + 3 hidden = 7 visible rows.
        for indexes in [[0, 1], [3, 4], [7, 8]] {
            _ = try await store.createStack(
                memberIDs: rowIDs(indexes), collapsed: true)
        }
        let sort = makeSort()
        var walked: [Int64] = []
        var anchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                sort: sort, anchor: anchor, limit: 2, stackMode: .collapsed)
            if page.isEmpty { break }
            walked.append(contentsOf: page.map(\.id))
            guard page.count == 2, let last = page.last else { break }
            anchor = LibraryPageAnchor(
                keyValue: .text(last.filename ?? ""), imagePath: last.imagePath)
        }
        XCTAssertEqual(walked.count, 7, "every visible row exactly once")
        XCTAssertEqual(Set(walked).count, 7, "no duplicates across pages")
        // The anchor chain is consistent: a fresh full page equals the walk.
        let full = try await queries.searchPage(
            sort: sort, limit: 100, stackMode: .collapsed)
        XCTAssertEqual(walked, full.map(\.id))
    }

    // MARK: - ⑨ the expanded-walk union golden

    func testExpandedWalkUnionGolden() async throws {
        // Cover in the FIRST keyset page, members positioned in LATER ones
        // (reverse-member stacks) — the cross-page gather fixture.
        let sort = makeSort()
        let coverA = rowIDs([8])    // r09 — first page (page size 3)
        let membersA = rowIDs([0, 4])
        _ = try await store.createStack(
            memberIDs: coverA + membersA, collapsed: false)
        let coverB = rowIDs([9])    // r10 — last page
        let membersB = rowIDs([2, 6])
        _ = try await store.createStack(
            memberIDs: coverB + membersB, collapsed: false)

        // The expanded walk, spelled out at the composition level (the
        // flat query + per-page fixup — the KD-7 loop without the model):
        // dedupe each fetched page against the displayed set, gather the
        // page's stack members forward through the pure transform.
        var expanded: [LibraryImageRow] = []
        var anchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                sort: sort, anchor: anchor, limit: 3)
            if page.isEmpty { break }
            let displayed = Set(expanded.map(\.id))
            expanded += page.filter { !displayed.contains($0.id) }
            let memberships = try await queries.stackMemberships(
                ids: page.map(\.id))
            let stackIDs = Set(
                memberships.values.filter { $0.size >= 2 }.map(\.stackID))
            let memberLists = try await queries.stackMembers(
                ofStacks: Array(stackIDs))
            let shown = Set(expanded.map(\.id))
            let missing = memberLists.values.flatMap { $0 }
                .filter { !shown.contains($0) }
            let supplementalRows = try await queries.rows(byIDs: missing)
            let supplemental = Dictionary(
                uniqueKeysWithValues: supplementalRows.map { ($0.id, $0) })
            let outcome = LibraryGridModel.stackAdjacencyFixup(
                rows: expanded,
                memberships: memberships,
                memberLists: memberLists,
                supplemental: supplemental,
                displayed: shown)
            expanded = outcome.rows
            guard page.count == 3, let last = page.last else { break }
            anchor = LibraryPageAnchor(
                keyValue: .text(last.filename ?? ""), imagePath: last.imagePath)
        }
        // The .flat full walk.
        var flatIDs: [Int64] = []
        var flatAnchor: LibraryPageAnchor?
        while true {
            let page = try await queries.searchPage(
                sort: sort, anchor: flatAnchor, limit: 3)
            flatIDs.append(contentsOf: page.map(\.id))
            guard page.count == 3, let last = page.last else { break }
            flatAnchor = LibraryPageAnchor(
                keyValue: .text(last.filename ?? ""), imagePath: last.imagePath)
        }
        // UNION GOLDEN (R1): same id SET, no duplicates in the expanded walk.
        XCTAssertEqual(
            Set(expanded.map(\.id)), Set(flatIDs),
            "the expanded walk covers exactly the flat collection")
        XCTAssertEqual(expanded.count, flatIDs.count, "no duplicates")
        // And the gather actually moved members to their stacks: each
        // stack's members sit adjacent to its cover.
        let positions = Dictionary(uniqueKeysWithValues: expanded.enumerated().map { ($1.id, $0) })
        for (cover, members) in [(coverA[0], membersA), (coverB[0], membersB)] {
            let coverPosition = try XCTUnwrap(positions[cover])
            for member in members {
                let memberPosition = try XCTUnwrap(positions[member])
                XCTAssertLessThan(
                    abs(memberPosition - coverPosition), 4,
                    "members gather near their stack")
            }
        }
    }
}
