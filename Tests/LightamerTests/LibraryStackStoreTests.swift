import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryStackStoreTests (Plan M6-4-01 T2, KD-2/KD-3) — the stack CRUD face
// over a REAL `.lalb` package, the LightCraft op family SQL-ized:
//
//   create (≥2 / no dups / no cross-stack members; positions dense 0..n−1,
//          cover = index 0) · group union (whole-stack follow-in, order
//          preserved, <2 no-op) · stackWith (product pinned cover, born
//          collapsed) · setTop / move (renumber + clamp) · split (middle
//          cut, the =1/out-of-range/cover-cut boundaries) · ungroup ·
//          removeFromStacks (renumber + <2 dissolve) · collapsed flags ·
//          the removeImage dissolution sweep · modified_time stamps.
//
// All faces go through the store API; async reads hoist into locals before
// the XCTAssert calls (the LibraryStoreTests precedent).
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryStackStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-stack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("Stacks.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "Stacks")
        store = LibraryStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    /// Insert N images, returning their rowids in insertion order.
    @discardableResult
    private func insertImages(_ count: Int) async throws -> [Int64] {
        var ids: [Int64] = []
        for index in 1...count {
            ids.append(try await store.insertImage(
                record: LibraryImageRecord(
                    imagePath: "Media/i\(index).arw",
                    pathKind: .projectRelative)))
        }
        return ids
    }

    private func assertConstraintError(
        _ action: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await action()
            XCTFail("expected constraintViolation", file: file, line: line)
        } catch let error as LibraryError {
            guard case .constraintViolation = error else {
                return XCTFail(
                    "expected constraintViolation, got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }

    // MARK: - ① createStack happy: positions dense, cover = index 0

    func testCreateStackHappyDensePositionsCoverFirst() async throws {
        let ids = try await insertImages(3)
        let stack = try await store.createStack(memberIDs: ids)
        XCTAssertEqual(stack.memberIDs, ids, "positions land in the given order")
        XCTAssertFalse(stack.collapsed, "default birth is expanded")
        let members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, ids, "position order — index 0 IS the cover")
        let read = try await store.stackContaining(imageID: ids[0])
        XCTAssertEqual(read?.id, stack.id)
        XCTAssertEqual(read?.memberIDs, ids)
        let all = try await store.stacks()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - ②/③/④ validate rules

    func testCreateStackRejectsBelowTwoMembers() async throws {
        let ids = try await insertImages(2)
        await assertConstraintError {
            try await self.store.createStack(memberIDs: [ids[0]])
        }
        await assertConstraintError {
            try await self.store.createStack(memberIDs: [])
        }
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty, "the rejections wrote nothing")
    }

    func testCreateStackRejectsDuplicateMembers() async throws {
        let ids = try await insertImages(2)
        await assertConstraintError {
            try await self.store.createStack(memberIDs: [ids[0], ids[0]])
        }
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty)
    }

    func testCreateStackRejectsMemberAlreadyInAStack() async throws {
        let ids = try await insertImages(4)
        _ = try await store.createStack(memberIDs: [ids[0], ids[1]])
        // Any member already stacked rejects with the readable typed error
        // (the UNIQUE index stays the race backstop, never the primary UX).
        await assertConstraintError {
            try await self.store.createStack(memberIDs: [ids[2], ids[1]])
        }
        await assertConstraintError {
            try await self.store.createStack(memberIDs: [ids[0], ids[3]])
        }
        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 1, "the rejections wrote nothing")
    }

    // MARK: - ⑤/⑥ stackContaining + members order

    func testStackContainingReverseLookupAndMiss() async throws {
        let ids = try await insertImages(3)
        let stack = try await store.createStack(memberIDs: [ids[2], ids[0]])
        let hit = try await store.stackContaining(imageID: ids[0])
        XCTAssertEqual(hit?.id, stack.id)
        XCTAssertEqual(hit?.memberIDs, [ids[2], ids[0]])
        let miss = try await store.stackContaining(imageID: ids[1])
        XCTAssertNil(miss, "an unstacked image answers nil")
    }

    func testMembersReturnsPositionOrder() async throws {
        let ids = try await insertImages(4)
        let stack = try await store.createStack(
            memberIDs: [ids[3], ids[1], ids[2]])
        let members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, [ids[3], ids[1], ids[2]])
        await assertConstraintError {
            _ = try await self.store.members(ofStack: 999_999)
        }
    }

    // MARK: - ⑦/⑧ setTop + move

    func testSetTopSwapsCoverAndRenumbers() async throws {
        let ids = try await insertImages(3)
        let stack = try await store.createStack(memberIDs: ids)
        try await store.setTop(stackID: stack.id, imageID: ids[2])
        let members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(
            members, [ids[2], ids[0], ids[1]],
            "the new cover leads; the rest keeps relative order")
        await assertConstraintError {
            try await self.store.setTop(stackID: stack.id, imageID: 999_999)
        }
    }

    func testMoveInStackStepsAndClamps() async throws {
        let ids = try await insertImages(3)
        let stack = try await store.createStack(memberIDs: ids)
        // +1 moves the cover back one slot.
        try await store.moveInStack(
            stackID: stack.id, imageID: ids[0], delta: 1)
        var members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, [ids[1], ids[0], ids[2]])
        // -1 moves it back to the head.
        try await store.moveInStack(
            stackID: stack.id, imageID: ids[0], delta: -1)
        members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, ids)
        // Out-of-range deltas clamp to the ends (no wrap, no throw).
        try await store.moveInStack(
            stackID: stack.id, imageID: ids[2], delta: 9)
        members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, [ids[0], ids[1], ids[2]], "clamped at the tail")
        try await store.moveInStack(
            stackID: stack.id, imageID: ids[0], delta: -9)
        members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, ids, "clamped at the head")
    }

    // MARK: - ⑨/⑩ collapsed flags

    func testSetCollapsedSingleStack() async throws {
        let ids = try await insertImages(2)
        let stack = try await store.createStack(memberIDs: ids)
        try await store.setCollapsed(stackID: stack.id, collapsed: true)
        let read = try await store.stackContaining(imageID: ids[0])
        XCTAssertEqual(read?.collapsed, true)
        await assertConstraintError {
            try await self.store.setCollapsed(stackID: 999_999, collapsed: true)
        }
    }

    func testSetAllCollapsed() async throws {
        let ids = try await insertImages(4)
        let a = try await store.createStack(memberIDs: [ids[0], ids[1]])
        let b = try await store.createStack(memberIDs: [ids[2], ids[3]])
        try await store.setAllCollapsed(true)
        for stack in try await store.stacks() {
            XCTAssertTrue(stack.collapsed, "every stack folded")
        }
        try await store.setAllCollapsed(false)
        for stack in try await store.stacks() {
            XCTAssertFalse(stack.collapsed, "every stack unfolded")
        }
        _ = a; _ = b
    }

    // MARK: - ⑪/⑫ split

    func testSplitMiddleKeepsBothHalves() async throws {
        let ids = try await insertImages(4)
        let stack = try await store.createStack(
            memberIDs: ids, collapsed: true)
        let halves = try await store.splitStack(
            stackID: stack.id, atImageID: ids[2])
        // The head keeps the ORIGINAL id; the tail is a new stack carrying
        // the original's collapsed flag.
        let head = try XCTUnwrap(halves.head)
        XCTAssertEqual(head.id, stack.id, "the prefix keeps the stack id")
        XCTAssertEqual(head.memberIDs, [ids[0], ids[1]])
        let tail = try XCTUnwrap(halves.tail)
        XCTAssertNotEqual(tail.id, stack.id)
        XCTAssertEqual(tail.memberIDs, [ids[2], ids[3]])
        XCTAssertTrue(tail.collapsed, "the collapsed flag carries to the tail")
        let all = try await store.stacks()
        XCTAssertEqual(all.count, 2)
    }

    func testSplitBoundaries() async throws {
        // (a) suffix == 1 → the cut degrades to removeFromStacks.
        let a = try await insertImages(3)
        let stackA = try await store.createStack(memberIDs: a)
        let cutA = try await store.splitStack(
            stackID: stackA.id, atImageID: a[2])
        XCTAssertEqual(cutA.tail, nil, "a one-member suffix just leaves")
        XCTAssertEqual(cutA.head?.memberIDs, [a[0], a[1]])
        XCTAssertEqual(cutA.head?.id, stackA.id)

        // (b) prefix == 1 → the prefix dissolves, the suffix is a new stack.
        let b = try await insertImages(3)
        let stackB = try await store.createStack(memberIDs: b)
        let cutB = try await store.splitStack(
            stackID: stackB.id, atImageID: b[1])
        XCTAssertNil(cutB.head, "the one-member prefix dissolved")
        XCTAssertEqual(cutB.tail?.memberIDs, [b[1], b[2]])
        // (a)'s survivor + (b)'s tail — the dissolved head is gone (the
        // freed rowid may be reused, so identity rides the member sets).
        let stacksB = try await store.stacks()
        XCTAssertEqual(stacksB.count, 2)
        XCTAssertEqual(
            Set(stacksB.map { Set($0.memberIDs) }),
            [Set([a[0], a[1]]), Set([b[1], b[2]])])

        // (c) cut at the cover = empty prefix → typed no-op, SAME stack id.
        let c = try await insertImages(3)
        let stackC = try await store.createStack(
            memberIDs: c, collapsed: true)
        let cutC = try await store.splitStack(
            stackID: stackC.id, atImageID: c[0])
        let unchanged = try XCTUnwrap(cutC.head)
        XCTAssertEqual(unchanged.id, stackC.id, "S6: the stack id survives")
        XCTAssertEqual(unchanged.memberIDs, c, "no member moved")
        XCTAssertTrue(unchanged.collapsed)
        XCTAssertNil(cutC.tail)

        // (d) a non-member cut point rejects.
        await assertConstraintError {
            try await self.store.splitStack(
                stackID: stackC.id, atImageID: 999_999)
        }
    }

    // MARK: - ⑬/⑭ ungroup + removeFromStacks

    func testUngroupDissolvesWholeStack() async throws {
        let ids = try await insertImages(3)
        let stack = try await store.createStack(memberIDs: ids)
        try await store.ungroup(stackID: stack.id)
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty)
        for id in ids {
            let containing = try await store.stackContaining(imageID: id)
            XCTAssertNil(containing, "members stay, simply unstacked")
        }
        await assertConstraintError {
            try await self.store.ungroup(stackID: stack.id)
        }
    }

    func testRemoveFromStacksRenumbersAndDissolvesBelowTwo() async throws {
        // Renumber: removing a middle member tightens positions.
        let ids = try await insertImages(3)
        let stack = try await store.createStack(memberIDs: ids)
        try await store.removeFromStacks(imageID: ids[1])
        var members = try await store.members(ofStack: stack.id)
        XCTAssertEqual(members, [ids[0], ids[2]], "dense renumber after removal")
        // <2 remainder dissolves: a 2-stack losing one member is GONE.
        try await store.removeFromStacks(imageID: ids[0])
        let stacks = try await store.stacks()
        XCTAssertTrue(stacks.isEmpty, "the one-member remainder dissolved")
        // The dissolved stack answers members with the typed notFound face.
        await assertConstraintError {
            _ = try await self.store.members(ofStack: stack.id)
        }
        // A non-member is a typed rejection.
        await assertConstraintError {
            try await self.store.removeFromStacks(imageID: ids[0])
        }
    }

    // MARK: - ⑮ group union

    func testGroupUnionFollowsWholeStacksInOrder() async throws {
        let ids = try await insertImages(6)
        // Stack A: [0, 1, 2]; stack B: [3, 4]. Loose image 5.
        try await store.createStack(memberIDs: [ids[0], ids[1], ids[2]])
        try await store.createStack(memberIDs: [ids[3], ids[4]])
        // Grouping a member of A with a member of B + a loose image merges
        // BOTH whole stacks (original order preserved) around the mention.
        let mergedOptional = try await store.group(
            memberIDs: [ids[4], ids[5], ids[1]])
        let merged = try XCTUnwrap(mergedOptional)
        XCTAssertEqual(
            merged.memberIDs, [ids[3], ids[4], ids[5], ids[0], ids[1], ids[2]],
            "B's members lead (first mention), the loose image slots in, "
                + "A's members follow in their original order")
        let stacks = try await store.stacks()
        XCTAssertEqual(stacks.count, 1, "both source stacks dissolved into one")
        XCTAssertEqual(
            stacks.first?.memberIDs, merged.memberIDs,
            "the single survivor IS the union stack (source-stack rowids are "
                + "free to reuse — identity is the member set, not the id)")
        XCTAssertTrue(stacks.first?.collapsed ?? false, "manual groups are born collapsed")
        // A mention set that unions to <2 members is a typed no-op.
        let lone = try await insertImages(1)
        let noop = try await store.group(memberIDs: [lone[0]])
        XCTAssertNil(noop, "a single unstacked image is a no-op")
        let remaining = try await store.stacks()
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - ⑯ stackWith + modified_time stamps

    func testStackWithPinsProductCoverCollapsedAndStamps() async throws {
        let ids = try await insertImages(4)
        try await store.createStack(memberIDs: [ids[2], ids[3]])
        let stackOptional = try await store.stackWith(
            productID: ids[0], sourceIDs: [ids[1], ids[2], ids[3]])
        let stack = try XCTUnwrap(stackOptional)
        XCTAssertEqual(
            stack.memberIDs.first, ids[0], "the product IS the cover")
        XCTAssertTrue(stack.collapsed, "merge products are born collapsed")
        XCTAssertEqual(
            stack.memberIDs, [ids[0], ids[1], ids[2], ids[3]],
            "the sources' whole stack followed in, order preserved")
        // modified_time stamps: the create path stamps now; a mutation
        // (setTop) moves it forward.
        let afterCreate = try await store.stackContaining(imageID: ids[0])?
            .modifiedTime
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms — the REAL clock
        try await store.setTop(stackID: stack.id, imageID: ids[3])
        let afterSetTop = try await store.stackContaining(imageID: ids[0])?
            .modifiedTime
        let created = try XCTUnwrap(afterCreate)
        let mutated = try XCTUnwrap(afterSetTop)
        XCTAssertGreaterThan(
            mutated, created, "every write path re-stamps the stack")
        // stackWith below 2 members is a typed no-op.
        let lone = try await insertImages(1)
        let noop = try await store.stackWith(
            productID: lone[0], sourceIDs: [])
        XCTAssertNil(noop, "a product with no sources is a no-op")
    }
}
