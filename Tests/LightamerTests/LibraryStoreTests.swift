import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// LibraryStoreTests (Plan M2-2-1 T4) — the single-writer CRUD face over the
// opened package:
//
//   • the three album kinds (album/folder/filter) with the OQ-6 type
//     discriminator — filter requires a validated predicate group, the
//     other kinds reject one, blank names reject
//   • the folder tree: parent moves + the typed cycle rejection
//   • KD-4 refcount transactionality: one image in N albums → ref_count
//     N; removing from one album decrements; removing an album (with its
//     SUBTREE) decrements per membership row; ref_count 0 NEVER deletes
//     the images row
//   • filter_data JSON round-trip (the OQ-6 zero-new-format face)
//   • removeImage cleans every membership (the FK cascade)
//
// All faces go through the store API (no raw-SQL closures from the test —
// the actor seam stays intact). Async reads hoist into locals before the
// XCTAssert calls (their autoclosures do not support `await`).
// ─────────────────────────────────────────────────────────────────────────────

final class LibraryStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var packageURL: URL!
    private var fileStore: ProjectFileStore!
    private var store: LibraryStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("library-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        packageURL = tempDirectory.appendingPathComponent("StoreProj.lalb")
        fileStore = ProjectFileStore(at: packageURL)
        _ = try await fileStore.create(name: "StoreProj")
        store = LibraryStore(store: fileStore)
    }

    override func tearDown() async throws {
        try? await fileStore.close()
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
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

    // MARK: - Three album kinds (OQ-6)

    func testCreateThreeAlbumKinds() async throws {
        let plain = try await store.createAlbum(kind: .album, name: "Trip 2026")
        let folder = try await store.createAlbum(kind: .folder, name: "Travel")
        let group = FilterPredicateGroup(
            match: .all,
            rules: [.init(field: .rating, op: .gte, value: .int(4))])
        let filter = try await store.createAlbum(
            kind: .filter, name: "Rated", filterGroup: group)

        let plainKind = try await store.album(id: plain.id).kind
        let folderKind = try await store.album(id: folder.id).kind
        let filterKind = try await store.album(id: filter.id).kind
        XCTAssertEqual(plainKind, .album)
        XCTAssertEqual(folderKind, .folder)
        XCTAssertEqual(filterKind, .filter)
        let all = try await store.albums()
        XCTAssertEqual(all.count, 3)
    }

    func testFilterAlbumRequiresValidatedGroupAndOthersRejectOne() async throws {
        // A filter album WITHOUT a group rejects.
        await assertConstraintError {
            try await self.store.createAlbum(kind: .filter, name: "Broken")
        }
        // A plain album WITH a group rejects.
        let group = FilterPredicateGroup(rules: [])
        await assertConstraintError {
            try await self.store.createAlbum(
                kind: .album, name: "Plain", filterGroup: group)
        }
        // An ILLEGAL group rejects before persistence (rating contains).
        let illegal = FilterPredicateGroup(
            rules: [.init(field: .rating, op: .contains, value: .int(1))])
        await assertConstraintError {
            try await self.store.createAlbum(
                kind: .filter, name: "Illegal", filterGroup: illegal)
        }
        // Blank names reject on every kind.
        await assertConstraintError {
            try await self.store.createAlbum(kind: .album, name: "   ")
        }
        let all = try await store.albums()
        XCTAssertEqual(all.count, 0)
    }

    // MARK: - Tree: rename / move / cycle guard

    func testTreeRenameMoveAndCycleRejection() async throws {
        let folder = try await store.createAlbum(kind: .folder, name: "Root")
        let child = try await store.createAlbum(
            kind: .album, name: "Child", parentID: folder.id)
        var childRow = try await store.album(id: child.id)
        XCTAssertEqual(childRow.parentID, folder.id)

        try await store.renameAlbum(id: child.id, to: "Renamed")
        childRow = try await store.album(id: child.id)
        XCTAssertEqual(childRow.name, "Renamed")

        // Move to root and back.
        try await store.moveAlbum(id: child.id, toParent: nil)
        childRow = try await store.album(id: child.id)
        XCTAssertNil(childRow.parentID)
        try await store.moveAlbum(id: child.id, toParent: folder.id)

        // Cycle: moving the folder under its own child rejects.
        await assertConstraintError {
            try await self.store.moveAlbum(id: folder.id, toParent: child.id)
        }
        // Unknown parent rejects.
        await assertConstraintError {
            try await self.store.moveAlbum(id: child.id, toParent: 99_999)
        }
    }

    // MARK: - filter_data JSON round-trip (OQ-6)

    func testFilterDataJSONRoundTrip() async throws {
        let group = FilterPredicateGroup(
            match: .all,
            rules: [
                .init(field: .rating, op: .gte, value: .int(4)),
                .init(field: .keywords, op: .contains, value: .text("Nature")),
            ])
        let filter = try await store.createAlbum(
            kind: .filter, name: "Top Nature", filterGroup: group)
        let decoded = try await store.album(id: filter.id)
        XCTAssertEqual(decoded.filterGroup, group, "Codable round-trip identity")
    }

    // MARK: - KD-4 reference counting

    func testOneImageInMultipleAlbumsCountsN() async throws {
        let imageID = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/a.arw", pathKind: .projectRelative))
        let albumA = try await store.createAlbum(kind: .album, name: "A")
        let albumB = try await store.createAlbum(kind: .album, name: "B")
        let albumC = try await store.createAlbum(kind: .album, name: "C")

        try await store.addImage(imageID, to: albumA.id)
        try await store.addImage(imageID, to: albumB.id)
        try await store.addImage(imageID, to: albumC.id)
        var image = try await store.image(id: imageID)
        XCTAssertEqual(image.refCount, 3)
        let members = try await store.members(of: albumB.id)
        XCTAssertEqual(members, [imageID])

        // A repeat add is idempotent — no double increment.
        try await store.addImage(imageID, to: albumB.id)
        image = try await store.image(id: imageID)
        XCTAssertEqual(image.refCount, 3)

        // Removing from one album decrements by one.
        try await store.removeImage(imageID, from: albumB.id)
        image = try await store.image(id: imageID)
        XCTAssertEqual(image.refCount, 2)
        // A repeat remove is a typed rejection (not a silent decrement).
        await assertConstraintError {
            try await self.store.removeImage(imageID, from: albumB.id)
        }
    }

    func testRemoveAlbumDecrementsAndZeroKeepsRow() async throws {
        let imageID = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/b.arw", pathKind: .projectRelative))
        let album = try await store.createAlbum(kind: .album, name: "Only")
        try await store.addImage(imageID, to: album.id)
        var image = try await store.image(id: imageID)
        XCTAssertEqual(image.refCount, 1)

        // Removing the album decrements to zero — and the image ROW
        // SURVIVES (KD-4: membership is independent of library presence).
        try await store.removeAlbum(id: album.id)
        image = try await store.image(id: imageID)
        XCTAssertEqual(image.refCount, 0)
        XCTAssertEqual(image.imagePath, "Media/b.arw")
    }

    func testRemoveAlbumCascadesSubtreePerMembership() async throws {
        // Folder F → albums A, B. image1 ∈ A; image2 ∈ A+B.
        let folder = try await store.createAlbum(kind: .folder, name: "F")
        let albumA = try await store.createAlbum(
            kind: .album, name: "A", parentID: folder.id)
        let albumB = try await store.createAlbum(
            kind: .album, name: "B", parentID: folder.id)
        let image1 = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/i1.arw", pathKind: .projectRelative))
        let image2 = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/i2.arw", pathKind: .projectRelative))
        try await store.addImage(image1, to: albumA.id)
        try await store.addImage(image2, to: albumA.id)
        try await store.addImage(image2, to: albumB.id)
        let before = try await store.image(id: image2)
        XCTAssertEqual(before.refCount, 2)

        // Removing the folder cascades the subtree; image2 paid TWO
        // memberships (per-row decrement).
        try await store.removeAlbum(id: folder.id)
        let survivors = try await store.albums()
        XCTAssertEqual(survivors, [], "the whole subtree is gone")
        let after1 = try await store.image(id: image1)
        let after2 = try await store.image(id: image2)
        XCTAssertEqual(after1.refCount, 0)
        XCTAssertEqual(after2.refCount, 0)
        // Both image rows survive (zero never deletes).
        XCTAssertEqual(after1.imagePath, "Media/i1.arw")
    }

    func testRemoveImageCleansAllMembership() async throws {
        let imageID = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/c.arw", pathKind: .projectRelative))
        let albumA = try await store.createAlbum(kind: .album, name: "A")
        let albumB = try await store.createAlbum(kind: .album, name: "B")
        try await store.addImage(imageID, to: albumA.id)
        try await store.addImage(imageID, to: albumB.id)

        try await store.removeImage(id: imageID)
        let membersA = try await store.members(of: albumA.id)
        let membersB = try await store.members(of: albumB.id)
        XCTAssertEqual(membersA, [])
        XCTAssertEqual(membersB, [])
        await assertConstraintError {
            try await self.store.image(id: imageID)
        }
    }

    /// KD-4 atomicity (acceptance regression): a membership move whose
    /// REFCOUNT leg is aborted mid-batch must roll the MEMBERSHIP leg back
    /// too — the two statements ride the withWriteBatch transaction, not
    /// autocommit. Injection = an AFTER trigger that RAISE(ABORT)s exactly
    /// the 1→0 decrement leg.
    func testRefcountMoveIsAtomicUnderMidStatementFailure() async throws {
        let imageID = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/atomic.arw", pathKind: .projectRelative))
        let album = try await store.createAlbum(kind: .album, name: "Atomic")
        try await store.addImage(imageID, to: album.id)

        try await fileStore.withHandle { handle -> Bool in
            try handle.execute("""
                CREATE TRIGGER atomicity_inject AFTER UPDATE OF ref_count ON images
                WHEN OLD.ref_count = 1
                BEGIN SELECT RAISE(ABORT, 'injected atomicity failure'); END
                """)
            return true
        }

        do {
            try await store.removeImage(imageID, from: album.id)
            XCTFail("expected the injected abort")
        } catch {
            // Any error shape — the STATE after the failure is the contract.
        }

        // WITHOUT the batch transaction the DELETE would already be
        // committed here (membership gone, ref_count stuck at 1).
        let image = try await store.image(id: imageID)
        XCTAssertEqual(image.refCount, 1, "the refcount leg rolled back")
        let members = try await store.members(of: album.id)
        XCTAssertEqual(members, [imageID], "the membership leg rolled back")

        // Drop the injection so tearDown's close checkpoint stays clean.
        try await fileStore.withHandle { handle -> Bool in
            try handle.execute("DROP TRIGGER atomicity_inject")
            return true
        }
    }

    // MARK: - Unknown ids + projection

    func testUnknownIDsRejectTyped() async throws {
        await assertConstraintError {
            try await self.store.addImage(1, to: 2)
        }
        await assertConstraintError {
            try await self.store.renameAlbum(id: 99_999, to: "X")
        }
        await assertConstraintError {
            try await self.store.removeAlbum(id: 99_999)
        }
        await assertConstraintError {
            try await self.store.removeImage(id: 99_999)
        }
        await assertConstraintError {
            try await self.store.updateProjection(
                imageID: 99_999, hasEdits: true, paramsHash: "1")
        }
    }

    func testUpdateProjectionL013Text() async throws {
        let imageID = try await store.insertImage(
            record: LibraryImageRecord(
                imagePath: "Media/d.arw", pathKind: .projectRelative))
        // L013: the FNV-1a 64 hash as DECIMAL TEXT (never INTEGER).
        let hash = "18446744073709551615"
        try await store.updateProjection(
            imageID: imageID, hasEdits: true, paramsHash: hash)
        let image = try await store.image(id: imageID)
        XCTAssertEqual(image.hasEdits, 1)
        XCTAssertEqual(image.paramsHash, hash)
        XCTAssertEqual(image.refCount, 0)
    }
}
