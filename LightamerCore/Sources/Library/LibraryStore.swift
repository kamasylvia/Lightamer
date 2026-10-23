import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryStore (Plan M2-2-1 T4) — the SINGLE-WRITER CRUD face over the
// opened `.lalb` package: the three-kind album tree (OQ-6), the KD-4
// reference-count membership model, and the images row face.
//
// REFCOUNT DISCIPLINE (KD-4): album membership writes and the
// `images.ref_count` movement ride the SAME transaction (single-writer
// actor + withWriteBatch). Deleting an album deletes its `album_content`
// rows via the DECLARED FK CASCADE (foreign_keys=ON, the schema baseline)
// and decrements the affected images' counters — the store decrements
// BEFORE the album delete so it can see the membership rows it is paying
// for. `ref_count` NEVER deletes the images row on reaching zero — the
// picture's membership in the library is independent of albums; leaving
// the library = the explicit `removeImage` API (P3/management consumers).
// A materialized counter (not COUNT-derivation) because the grid
// sorts/filters on it — a 20k-row COUNT over album_content per page is
// the derivation-face's non-starter.
//
// FILTER ALBUMS (OQ-6): `filter_data` = the EXISTING `FilterPredicateGroup`
// Codable JSON (sortedKeys byte stability) — validated with
// `validating()` BEFORE persisting; `FilterSQL` consumes it (the M2-2-3
// smart-album evaluation rides the .library domain, KD-7). ZERO new
// predicate format.
//
// SMART-ALBUM ENVELOPE NOTE: the App-level SmartAlbumDocument envelope
// (schemaVersion+name+group) is deliberately NOT re-wrapped here — the
// `albums` row's name/type/filter_data columns ARE the envelope (the
// project DB has its own identity), the GROUP payload bytes are the same
// Codable model.
// ─────────────────────────────────────────────────────────────────────────────

/// One albums row (the OQ-6 three-kind tree node).
public struct LibraryAlbum: Sendable, Equatable, Identifiable {
    public let id: Int64
    public var kind: LibrarySchema.AlbumKind
    public var name: String
    public var parentID: Int64?
    /// Kind `.filter` ONLY: the smart album's predicate group (decoded
    /// from the `filter_data` JSON).
    public var filterGroup: FilterPredicateGroup?
    public var addedTime: Double?
    public var modifiedTime: Double?

    public init(
        id: Int64, kind: LibrarySchema.AlbumKind, name: String,
        parentID: Int64? = nil, filterGroup: FilterPredicateGroup? = nil,
        addedTime: Double? = nil, modifiedTime: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.parentID = parentID
        self.filterGroup = filterGroup
        self.addedTime = addedTime
        self.modifiedTime = modifiedTime
    }
}

/// The insert face for one images row (KD-1's three-form path carrier +
/// the organizational columns import knows at row-create time).
public struct LibraryImageRecord: Sendable, Equatable {
    public var imagePath: String
    public var pathKind: LibrarySchema.PathKind
    public var volumeUUID: String?
    public var fileStem: String?
    public var fileExt: String?
    public var filename: String?
    public var dir: String?

    public init(
        imagePath: String, pathKind: LibrarySchema.PathKind,
        volumeUUID: String? = nil, fileStem: String? = nil,
        fileExt: String? = nil, filename: String? = nil, dir: String? = nil
    ) {
        self.imagePath = imagePath
        self.pathKind = pathKind
        self.volumeUUID = volumeUUID
        self.fileStem = fileStem
        self.fileExt = fileExt
        self.filename = filename
        self.dir = dir
    }
}

/// One images row as read back (the store's projection read face).
public struct LibraryImage: Sendable, Equatable, Identifiable {
    public let id: Int64
    public var imagePath: String
    public var pathKind: LibrarySchema.PathKind
    public var volumeUUID: String?
    public var fileStem: String?
    public var rating: Int64?
    public var keywords: String?
    public var hasEdits: Int64?
    public var paramsHash: String?
    public var refCount: Int64
}

public actor LibraryStore {

    private let store: ProjectFileStore

    public init(store: ProjectFileStore) {
        self.store = store
    }

    // MARK: - Album CRUD (the three-kind tree)

    /// Create an album node. `.filter` requires a predicate group
    /// (validated BEFORE persist — an illegal group never reaches the
    /// disk); the other kinds reject one. Blank names reject (the
    /// SmartAlbumStore emptyName semantics).
    @discardableResult
    public func createAlbum(
        kind: LibrarySchema.AlbumKind, name rawName: String,
        parentID: Int64? = nil, filterGroup: FilterPredicateGroup? = nil
    ) async throws -> LibraryAlbum {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw LibraryError.constraintViolation(detail: "album name is blank")
        }
        var filterData: String?
        switch kind {
        case .filter:
            guard let filterGroup else {
                throw LibraryError.constraintViolation(
                    detail: "filter album requires a predicate group")
            }
            do {
                try filterGroup.validating()
            } catch {
                // The store's uniform typed face — the predicate model's
                // own error rides INSIDE the detail.
                throw LibraryError.constraintViolation(
                    detail: "invalid filter group: \(error)")
            }
            filterData = try Self.encodeFilterData(filterGroup)
        case .album, .folder:
            if filterGroup != nil {
                throw LibraryError.constraintViolation(
                    detail: "only filter albums carry a predicate group")
            }
        }
        let now = Date().timeIntervalSince1970
        return try await store.withWriteBatch { handle in
            if let parentID {
                try Self.assertAlbumExists(handle, id: parentID)
            }
            let insert = try handle.prepare("""
                INSERT INTO albums (type, name, parent_id, filter_data,
                    added_time, modified_time)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            try insert.bindText(1, kind.rawValue)
            try insert.bindText(2, name)
            try insert.bindInt(3, parentID)
            try insert.bindText(4, filterData)
            try insert.bindDouble(5, now)
            try insert.bindDouble(6, now)
            _ = try insert.step()
            return LibraryAlbum(
                id: handle.lastInsertRowID(), kind: kind, name: name,
                parentID: parentID, filterGroup: filterGroup,
                addedTime: now, modifiedTime: now)
        }
    }

    /// Rename (id and kind survive; modified_time bumps).
    public func renameAlbum(id: Int64, to rawName: String) async throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw LibraryError.constraintViolation(detail: "album name is blank")
        }
        _ = try await store.withWriteBatch { handle in
            let update = try handle.prepare(
                "UPDATE albums SET name = ?, modified_time = ? WHERE id = ?")
            try update.bindText(1, name)
            try update.bindDouble(2, Date().timeIntervalSince1970)
            try update.bindInt(3, id)
            _ = try update.step()
            guard handle.changes() == 1 else {
                throw LibraryError.constraintViolation(
                    detail: "unknown album id \(id)")
            }
            return true
        }
    }

    /// Move under a new parent (nil = root). A cycle (moving a node under
    /// its own descendant) is a typed rejection.
    public func moveAlbum(id: Int64, toParent newParent: Int64?) async throws {
        _ = try await store.withWriteBatch { handle in
            if let newParent {
                try Self.assertAlbumExists(handle, id: newParent)
                // Walk UP from the new parent — meeting `id` means the
                // move would make it its own ancestor.
                var cursor: Int64? = newParent
                while let current = cursor {
                    if current == id {
                        throw LibraryError.constraintViolation(
                            detail: "cannot move album \(id) under its own descendant")
                    }
                    cursor = try Self.parent(of: current, on: handle)
                }
            }
            let update = try handle.prepare(
                "UPDATE albums SET parent_id = ?, modified_time = ? WHERE id = ?")
            try update.bindInt(1, newParent)
            try update.bindDouble(2, Date().timeIntervalSince1970)
            try update.bindInt(3, id)
            _ = try update.step()
            guard handle.changes() == 1 else {
                throw LibraryError.constraintViolation(
                    detail: "unknown album id \(id)")
            }
            return true
        }
    }

    /// Remove an album (and its whole folder SUBTREE — the parent_id FK
    /// cascade). ONE transaction: decrement every subtree membership's
    /// refcount first (the store must SEE the rows it pays for — after
    /// the album delete they are cascaded away), then delete the subtree.
    /// A zero refcount NEVER deletes the images row (KD-4).
    public func removeAlbum(id: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            try Self.assertAlbumExists(handle, id: id)
            // The subtree (self + descendants, recursive).
            let subtreeStatement = try handle.prepare("""
                WITH RECURSIVE subtree(node) AS (
                    SELECT ? UNION
                    SELECT a.id FROM albums a
                    JOIN subtree s ON a.parent_id = s.node
                )
                SELECT node FROM subtree
                """)
            try subtreeStatement.bindInt(1, id)
            var nodes: [Int64] = []
            while try subtreeStatement.step() {
                if let node = subtreeStatement.columnInt(0) { nodes.append(node) }
            }
            // Decrement per MEMBERSHIP ROW (an image in two subtree albums
            // pays twice), bounded at zero. A fresh membership SELECT per
            // node (no statement reuse — the handles finalize on scope
            // exit).
            let decrement = try handle.prepare(
                "UPDATE images SET ref_count = MAX(ref_count - 1, 0),"
                    + " modified_time = ? WHERE id = ?")
            for node in nodes {
                let membership = try handle.prepare(
                    "SELECT image_id FROM album_content WHERE album_id = ?")
                try membership.bindInt(1, node)
                var imageIDs: [Int64] = []
                while try membership.step() {
                    if let imageID = membership.columnInt(0) { imageIDs.append(imageID) }
                }
                for imageID in imageIDs {
                    // reset BEFORE each reuse — a DONE statement refuses a
                    // rebind/step (SQLITE_MISUSE) without it.
                    try decrement.reset()
                    try decrement.bindDouble(1, Date().timeIntervalSince1970)
                    try decrement.bindInt(2, imageID)
                    _ = try decrement.step()
                }
            }
            // The subtree delete — the FK cascades take album_content and
            // child albums with it.
            let delete = try handle.prepare("DELETE FROM albums WHERE id = ?")
            try delete.bindInt(1, id)
            _ = try delete.step()
            guard handle.changes() >= 1 else {
                throw LibraryError.constraintViolation(
                    detail: "unknown album id \(id)")
            }
            return true
        }
    }

    /// One album (typed notFound via constraintViolation).
    public func album(id: Int64) async throws -> LibraryAlbum {
        try await store.withHandle { handle in
            guard let album = try Self.readAlbum(id: id, on: handle) else {
                throw LibraryError.constraintViolation(
                    detail: "unknown album id \(id)")
            }
            return album
        }
    }

    /// Every album (name-ordered — the sidebar's stable order).
    public func albums() async throws -> [LibraryAlbum] {
        try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT id FROM albums ORDER BY name")
            var albums: [LibraryAlbum] = []
            while try statement.step() {
                if let id = statement.columnInt(0),
                   let album = try Self.readAlbum(id: id, on: handle) {
                    albums.append(album)
                }
            }
            return albums
        }
    }

    // MARK: - Membership (KD-4 refcount, one transaction per move)

    /// Add an image to an album: the album_content row + the refcount
    /// increment in ONE transaction. Idempotent (a repeat add neither
    /// duplicates the row nor double-increments).
    public func addImage(_ imageID: Int64, to albumID: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            try Self.assertAlbumExists(handle, id: albumID)
            try Self.assertImageExists(handle, id: imageID)
            let insert = try handle.prepare(
                "INSERT OR IGNORE INTO album_content (album_id, image_id)"
                    + " VALUES (?, ?)")
            try insert.bindInt(1, albumID)
            try insert.bindInt(2, imageID)
            _ = try insert.step()
            guard handle.changes() == 1 else { return true } // already a member
            let increment = try handle.prepare(
                "UPDATE images SET ref_count = ref_count + 1 WHERE id = ?")
            try increment.bindInt(1, imageID)
            _ = try increment.step()
            return true
        }
    }

    /// Remove an image from an album: the membership row + the refcount
    /// decrement in ONE transaction. A repeat remove is a typed no-match
    /// rejection (the caller's bookkeeping is broken — say so).
    public func removeImage(_ imageID: Int64, from albumID: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            let delete = try handle.prepare(
                "DELETE FROM album_content WHERE album_id = ? AND image_id = ?")
            try delete.bindInt(1, albumID)
            try delete.bindInt(2, imageID)
            _ = try delete.step()
            guard handle.changes() == 1 else {
                throw LibraryError.constraintViolation(
                    detail: "image \(imageID) is not a member of album \(albumID)")
            }
            let decrement = try handle.prepare(
                "UPDATE images SET ref_count = MAX(ref_count - 1, 0) WHERE id = ?")
            try decrement.bindInt(1, imageID)
            _ = try decrement.step()
            return true
        }
    }

    /// The member image ids of one album (id-ordered — stable iteration).
    public func members(of albumID: Int64) async throws -> [Int64] {
        try await store.withHandle { handle in
            try Self.assertAlbumExists(handle, id: albumID)
            let statement = try handle.prepare(
                "SELECT image_id FROM album_content WHERE album_id = ?"
                    + " ORDER BY image_id")
            try statement.bindInt(1, albumID)
            var ids: [Int64] = []
            while try statement.step() {
                if let id = statement.columnInt(0) { ids.append(id) }
            }
            return ids
        }
    }

    // MARK: - Images row face

    /// Insert one images row (ref_count starts 0; timestamps now; the
    /// M2-5-2 KD-5 `default_look_pending` marker starts 1 — EVERY new
    /// import carries the pending default look; no switch, OQ-8 A).
    /// Returns the new id (the rowid-alias PK the FTS/FK/keyset faces
    /// consume).
    @discardableResult
    public func insertImage(record: LibraryImageRecord) async throws -> Int64 {
        try await store.withWriteBatch { handle in
            let now = Date().timeIntervalSince1970
            let insert = try handle.prepare("""
                INSERT INTO images (image_path, path_kind, volume_uuid,
                    file_stem, file_ext, filename, dir,
                    added_time, modified_time, default_look_pending)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
                """)
            try insert.bindText(1, record.imagePath)
            try insert.bindInt(2, record.pathKind.rawValue)
            try insert.bindText(3, record.volumeUUID)
            try insert.bindText(4, record.fileStem)
            try insert.bindText(5, record.fileExt)
            try insert.bindText(6, record.filename)
            try insert.bindText(7, record.dir)
            try insert.bindDouble(8, now)
            try insert.bindDouble(9, now)
            _ = try insert.step()
            return handle.lastInsertRowID()
        }
    }

    /// Remove the images row — the album_content AND stack_content FK
    /// cascades take every membership with it (the KD-4 cleanup). The
    /// refcount column dies WITH the row, so no decrement bookkeeping. The
    /// stack sweep (KD-2): with the membership rows gone, any stack whose
    /// remainder fell below 2 (including the fully-cascaded one-member
    /// stack, which has NO rows left) dissolves IN THE SAME TRANSACTION
    /// (LightCraft remove_from_stacks semantics, the delete arm). Unknown
    /// id = typed rejection.
    public func removeImage(id: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            let delete = try handle.prepare("DELETE FROM images WHERE id = ?")
            try delete.bindInt(1, id)
            _ = try delete.step()
            guard handle.changes() == 1 else {
                throw LibraryError.constraintViolation(
                    detail: "unknown image id \(id)")
            }
            // The stack dissolution sweep: empty stacks (all rows cascaded)
            // plus stacks holding a single remaining member.
            let sweep = try handle.prepare("""
                DELETE FROM stacks WHERE
                  id NOT IN (SELECT stack_id FROM stack_content)
                  OR id IN (
                    SELECT stack_id FROM stack_content
                    GROUP BY stack_id HAVING COUNT(*) < 2)
                """)
            _ = try sweep.step()
            return true
        }
    }

    /// Update the edit-state PROJECTION columns (has_edits / params_hash —
    /// L013 DECIMAL TEXT; the `.lra` sidecar stays the truth, OQ-3).
    public func updateProjection(
        imageID: Int64, hasEdits: Bool, paramsHash: String?
    ) async throws {
        _ = try await store.withWriteBatch { handle in
            try Self.assertImageExists(handle, id: imageID)
            let update = try handle.prepare(
                "UPDATE images SET has_edits = ?, params_hash = ?,"
                    + " modified_time = ? WHERE id = ?")
            try update.bindInt(1, hasEdits ? 1 : 0)
            try update.bindText(2, paramsHash)
            try update.bindDouble(3, Date().timeIntervalSince1970)
            try update.bindInt(4, imageID)
            _ = try update.step()
            return true
        }
    }

    /// The metadata-mark PROJECTION update (R1 mark-chain repair): the
    /// culling trio columns + `modified_time` for the target group in ONE
    /// write batch. The projection face only — the `.lra` sidecar write is
    /// `LibraryMetadataWriter.apply` (the truth lands first, then this).
    public func setMetadataMarks(_ marks: [LibraryMetadataMark]) async throws {
        try await store.withWriteBatch { handle in
            let update = try handle.prepare(
                "UPDATE images SET rating = ?, color_label = ?, flag = ?,"
                    + " modified_time = ? WHERE id = ?")
            let now = Date().timeIntervalSince1970
            for mark in marks {
                try update.reset()
                try update.bindInt(1, mark.rating)
                try update.bindInt(2, mark.colorLabel)
                try update.bindInt(3, mark.flag)
                try update.bindDouble(4, now)
                try update.bindInt(5, mark.imageID)
                _ = try update.step()
            }
        }
    }

    /// One images row (typed notFound).
    public func image(id: Int64) async throws -> LibraryImage {
        try await store.withHandle { handle in
            guard let image = try Self.readImage(id: id, on: handle) else {
                throw LibraryError.constraintViolation(
                    detail: "unknown image id \(id)")
            }
            return image
        }
    }

    // MARK: - M2-5-2 default-look pending marker (KD-5, additive)

    /// The per-image default-look pending read (the editor OPEN entry
    /// consumes this to decide the mint branch). Missing row = false.
    public func defaultLookPending(imageRowID: Int64) async throws -> Bool {
        try await store.withHandle { handle in
            let statement = try handle.prepare(
                "SELECT default_look_pending FROM images WHERE id = ?")
            try statement.bindInt(1, imageRowID)
            guard try statement.step() else { return false }
            return (statement.columnInt(0) ?? 0) != 0
        }
    }

    /// Clear the pending marker (the mint branch consumes it — once the
    /// flag has served the open, the marker is spent). Idempotent.
    public func clearDefaultLookPending(imageRowID: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            try Self.assertImageExists(handle, id: imageRowID)
            let update = try handle.prepare(
                "UPDATE images SET default_look_pending = 0, modified_time = ?"
                    + " WHERE id = ?")
            try update.bindDouble(1, Date().timeIntervalSince1970)
            try update.bindInt(2, imageRowID)
            _ = try update.step()
            return true
        }
    }

    // MARK: - M2-8-1 version_ref projection (KD-3; D-M2-8-CONTEXT-1-A)

    /// One `version_ref` row (the projection's typed face). `versionID` is
    /// the `.lra` version UUID STRING (the `.lra`↔`.lalb` join key).
    public struct VersionRefRow: Sendable, Equatable {
        public var versionID: String
        public var elementID: Int64
        public var displayName: String
        public var createdAtUnix: Int64
        public var updatedAtUnix: Int64

        public init(
            versionID: String, elementID: Int64, displayName: String,
            createdAtUnix: Int64, updatedAtUnix: Int64
        ) {
            self.versionID = versionID
            self.elementID = elementID
            self.displayName = displayName
            self.createdAtUnix = createdAtUnix
            self.updatedAtUnix = updatedAtUnix
        }
    }

    /// Whole-table reconcile for ONE image's version projection (KD-3):
    /// DELETE the element's every row, then INSERT the current set — ONE
    /// transaction, idempotent, no incremental drift face (the row set is
    /// a rebuildable mirror of the `.lra` truth; an empty `rows` clears
    /// the projection — the remove/remove-all face). The app-side sink
    /// calls this at every version-command tail + restore hydrate (KD-5);
    /// failures are the caller's log-and-continue (projection ≠ truth).
    public func replaceVersionRefs(
        elementID: Int64, rows: [VersionRefRow]
    ) async throws {
        try await store.withWriteBatch { handle in
            try Self.assertImageExists(handle, id: elementID)
            let delete = try handle.prepare(
                "DELETE FROM version_ref WHERE element_id = ?")
            try delete.bindInt(1, elementID)
            _ = try delete.step()
            let insert = try handle.prepare("""
                INSERT INTO version_ref (version_id, element_id, display_name,
                    created_at_unix, updated_at_unix)
                VALUES (?, ?, ?, ?, ?)
                """)
            for row in rows {
                try insert.reset()
                try insert.bindText(1, row.versionID)
                try insert.bindInt(2, row.elementID)
                try insert.bindText(3, row.displayName)
                try insert.bindInt(4, row.createdAtUnix)
                try insert.bindInt(5, row.updatedAtUnix)
                _ = try insert.step()
            }
            return true
        }
    }

    /// The version_ref rows of one image (id-ordered by version_id —
    /// stable iteration for the reconcile assertions).
    public func versionRefs(elementID: Int64) async throws -> [VersionRefRow] {
        try await store.withHandle { handle in
            let statement = try handle.prepare("""
                SELECT version_id, element_id, display_name,
                    created_at_unix, updated_at_unix
                FROM version_ref WHERE element_id = ?
                ORDER BY version_id
                """)
            try statement.bindInt(1, elementID)
            var rows: [VersionRefRow] = []
            while try statement.step() {
                guard let versionID = statement.columnText(0),
                    let element = statement.columnInt(1),
                    let name = statement.columnText(2)
                else { continue }
                rows.append(VersionRefRow(
                    versionID: versionID, elementID: element,
                    displayName: name,
                    createdAtUnix: statement.columnInt(3) ?? 0,
                    updatedAtUnix: statement.columnInt(4) ?? 0))
            }
            return rows
        }
    }

    // MARK: - Photo stacks (M6-4-01 KD-2/KD-3; the LightCraft op family)

    /// One stack as read back (KD-2's typed face). `memberIDs` is POSITION
    /// order — index 0 IS the cover (no cover column; the single truth).
    public struct LibraryStack: Sendable, Equatable, Identifiable {
        public let id: Int64
        public var collapsed: Bool
        public var memberIDs: [Int64]
        public var addedTime: Double?
        public var modifiedTime: Double?

        public init(
            id: Int64, collapsed: Bool, memberIDs: [Int64],
            addedTime: Double?, modifiedTime: Double?
        ) {
            self.id = id
            self.collapsed = collapsed
            self.memberIDs = memberIDs
            self.addedTime = addedTime
            self.modifiedTime = modifiedTime
        }
    }

    /// Create a stack from ≥2 unstacked images (validate rules 1-3: count,
    /// no duplicates, one-image-one-stack — the store pre-check gives the
    /// READABLE typed error, the UNIQUE index is the race backstop).
    /// Positions land dense 0..n−1 in the given order; index 0 = the cover.
    @discardableResult
    public func createStack(
        memberIDs rawMembers: [Int64], collapsed: Bool = false
    ) async throws -> LibraryStack {
        try Self.validateStackInput(rawMembers)
        return try await store.withWriteBatch { handle in
            for member in rawMembers {
                try Self.assertImageExists(handle, id: member)
                if let existing = try Self.stackID(of: member, on: handle) {
                    throw LibraryError.constraintViolation(
                        detail: "image \(member) already belongs to stack \(existing)")
                }
            }
            return try Self.insertStack(
                memberIDs: rawMembers, collapsed: collapsed, on: handle)
        }
    }

    /// The LightCraft `group_ops` union (KD-2): the named members JOINED BY
    /// every stack they already belong to — a stacked member pulls its WHOLE
    /// stack in, members in each involved stack keeping their original
    /// (position) order, first-mention order otherwise. The union below 2
    /// members is a typed no-op (nil, nothing written). Manual groups are
    /// born COLLAPSED (the grid's default-collapsed display makes the new
    /// stack appear as its cover — DECISIONS-registered birth choice).
    @discardableResult
    public func group(memberIDs rawMembers: [Int64]) async throws -> LibraryStack? {
        try await store.withWriteBatch { handle in
            let union = try Self.unionMembers(handle, heads: rawMembers, pinnedHead: nil)
            guard union.members.count >= 2 else { return nil }
            for stackID in union.involved {
                let delete = try handle.prepare("DELETE FROM stacks WHERE id = ?")
                try delete.bindInt(1, stackID)
                _ = try delete.step()
            }
            return try Self.insertStack(
                memberIDs: union.members, collapsed: true, on: handle)
        }
    }

    /// The LightCraft `stack_with_ops` merge-product semantics (KD-6's
    /// consumer): the group union with the PRODUCT PINNED as head (cover)
    /// and the stack born COLLAPSED. The union below 2 members is a typed
    /// no-op (nil). ONE transaction.
    @discardableResult
    public func stackWith(
        productID: Int64, sourceIDs: [Int64]
    ) async throws -> LibraryStack? {
        try await store.withWriteBatch { handle in
            let union = try Self.unionMembers(
                handle, heads: sourceIDs, pinnedHead: productID)
            guard union.members.count >= 2 else { return nil }
            for stackID in union.involved {
                let delete = try handle.prepare("DELETE FROM stacks WHERE id = ?")
                try delete.bindInt(1, stackID)
                _ = try delete.step()
            }
            return try Self.insertStack(
                memberIDs: union.members, collapsed: true, on: handle)
        }
    }

    /// Move `imageID` to the head (the cover — LightCraft `set_top_ops`,
    /// "cover = photos[0]" same mechanism). Whole-stack renumber, one
    /// transaction, `modified_time` stamped.
    public func setTop(stackID: Int64, imageID: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            var members = try Self.existingMembers(stackID: stackID, on: handle)
            guard let index = members.firstIndex(of: imageID) else {
                throw LibraryError.constraintViolation(
                    detail: "image \(imageID) is not a member of stack \(stackID)")
            }
            members.remove(at: index)
            members.insert(imageID, at: 0)
            try Self.writePositions(
                stackID: stackID, members: members, on: handle)
            return true
        }
    }

    /// Step one member ±`delta` slots (LightCraft `move_in_stack_ops`); the
    /// target index clamps to the member range (no wrap, no cross-stack).
    public func moveInStack(
        stackID: Int64, imageID: Int64, delta: Int
    ) async throws {
        _ = try await store.withWriteBatch { handle in
            var members = try Self.existingMembers(stackID: stackID, on: handle)
            guard let index = members.firstIndex(of: imageID) else {
                throw LibraryError.constraintViolation(
                    detail: "image \(imageID) is not a member of stack \(stackID)")
            }
            let target = max(0, min(members.count - 1, index + delta))
            guard target != index else { return true }
            members.remove(at: index)
            members.insert(imageID, at: target)
            try Self.writePositions(stackID: stackID, members: members, on: handle)
            return true
        }
    }

    /// Cut a new stack starting AT `atImageID` (LightCraft `split_stack_ops`):
    /// the suffix becomes its own stack (the original's collapsed flag
    /// carried over — DECISIONS-registered), any half below 2 dissolves (its
    /// members leave ALL stacks), and a cut at the cover (empty prefix) is a
    /// typed NO-OP that keeps the original stack id (S6). Returns the
    /// surviving halves (nil = that half dissolved / was a no-op tail).
    @discardableResult
    public func splitStack(
        stackID: Int64, atImageID imageID: Int64
    ) async throws -> (head: LibraryStack?, tail: LibraryStack?) {
        try await store.withWriteBatch { handle in
            let members = try Self.existingMembers(stackID: stackID, on: handle)
            let originalCollapsed = try Self.stackCollapsed(
                stackID: stackID, on: handle)
            guard let index = members.firstIndex(of: imageID) else {
                throw LibraryError.constraintViolation(
                    detail: "image \(imageID) is not a member of stack \(stackID)")
            }
            guard index > 0 else {
                // S6: the cut point at the cover = an empty prefix — no-op,
                // the original stack (same id) stands unchanged.
                let unchanged = try Self.readStack(id: stackID, on: handle)
                return (unchanged, nil)
            }
            let prefix = Array(members[..<index])
            let suffix = Array(members[index...])
            // The original's memberships all leave; the prefix re-seats into
            // the SAME stack id when it stays ≥2 (positions rewritten); the
            // below-2 prefix dissolves (its members leave, the stack row goes).
            let delete = try handle.prepare(
                "DELETE FROM stack_content WHERE stack_id = ?")
            try delete.bindInt(1, stackID)
            _ = try delete.step()
            var head: LibraryStack?
            if prefix.count >= 2 {
                try Self.writePositions(
                    stackID: stackID, members: prefix, on: handle)
                head = try Self.readStack(id: stackID, on: handle)
            } else {
                let drop = try handle.prepare("DELETE FROM stacks WHERE id = ?")
                try drop.bindInt(1, stackID)
                _ = try drop.step()
            }
            var tail: LibraryStack?
            if suffix.count >= 2 {
                tail = try Self.insertStack(
                    memberIDs: suffix, collapsed: originalCollapsed, on: handle)
            }
            return (head, tail)
        }
    }

    /// Dissolve a whole stack (LightCraft `ungroup_ops`): the stack row
    /// goes, the FK cascade takes every membership — members stay in the
    /// library, simply unstacked.
    public func ungroup(stackID: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            try Self.assertStackExists(handle, id: stackID)
            let delete = try handle.prepare("DELETE FROM stacks WHERE id = ?")
            try delete.bindInt(1, stackID)
            _ = try delete.step()
            return true
        }
    }

    /// Remove ONE image from whatever stack holds it (LightCraft
    /// `remove_from_stacks_ops`): the remainder renumbers, and a remainder
    /// below 2 dissolves IN THE SAME TRANSACTION. A non-member is a typed
    /// rejection (the caller's bookkeeping is broken — say so).
    public func removeFromStacks(imageID: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            guard let stackID = try Self.stackID(of: imageID, on: handle) else {
                throw LibraryError.constraintViolation(
                    detail: "image \(imageID) is not in any stack")
            }
            var members = try Self.existingMembers(stackID: stackID, on: handle)
            members.removeAll { $0 == imageID }
            if members.count >= 2 {
                try Self.writePositions(
                    stackID: stackID, members: members, on: handle)
            } else {
                // The below-2 remainder dissolves: the stack row goes and
                // the FK cascade takes the (≤1) leftover membership.
                let drop = try handle.prepare("DELETE FROM stacks WHERE id = ?")
                try drop.bindInt(1, stackID)
                _ = try drop.step()
            }
            return true
        }
    }

    /// Flip one stack's collapsed flag (LightCraft `set_collapsed_ops`).
    public func setCollapsed(stackID: Int64, collapsed: Bool) async throws {
        _ = try await store.withWriteBatch { handle in
            let update = try handle.prepare(
                "UPDATE stacks SET collapsed = ?, modified_time = ? WHERE id = ?")
            try update.bindInt(1, collapsed ? 1 : 0)
            try update.bindDouble(2, Date().timeIntervalSince1970)
            try update.bindInt(3, stackID)
            _ = try update.step()
            guard handle.changes() == 1 else {
                throw LibraryError.constraintViolation(
                    detail: "unknown stack id \(stackID)")
            }
            return true
        }
    }

    /// Flip EVERY stack's collapsed flag (the View-menu collapse-all face).
    public func setAllCollapsed(_ collapsed: Bool) async throws {
        _ = try await store.withWriteBatch { handle in
            let update = try handle.prepare(
                "UPDATE stacks SET collapsed = ?, modified_time = ?")
            try update.bindInt(1, collapsed ? 1 : 0)
            try update.bindDouble(2, Date().timeIntervalSince1970)
            _ = try update.step()
            return true
        }
    }

    /// Every stack, id-ordered (stable iteration for the read faces).
    public func stacks() async throws -> [LibraryStack] {
        try await store.withHandle { handle in
            let statement = try handle.prepare("SELECT id FROM stacks ORDER BY id")
            var stacks: [LibraryStack] = []
            while try statement.step() {
                if let id = statement.columnInt(0),
                   let stack = try Self.readStack(id: id, on: handle) {
                    stacks.append(stack)
                }
            }
            return stacks
        }
    }

    /// The stack holding `imageID` (the UNIQUE index reverse lookup);
    /// nil = unstacked.
    public func stackContaining(imageID: Int64) async throws -> LibraryStack? {
        try await store.withHandle { handle in
            guard let stackID = try Self.stackID(of: imageID, on: handle) else {
                return nil
            }
            return try Self.readStack(id: stackID, on: handle)
        }
    }

    /// The capture-time auto-stack commit face (KD-4; OQ-M6-4-2 = A). The
    /// pool is the CALLER-given id set (the App picks the multi-select or
    /// the full sweep); rows already in a stack and rows without a capture
    /// time drop out (the store leg of the double defense — the pure
    /// function defends the nil-capture half). `preview = true` reports the
    /// cluster COUNT and writes NOTHING; `false` lands one collapsed stack
    /// per cluster in ONE transaction (LightCraft's "one undo batch" as a
    /// transactional equivalent — the KD-3 no-undo posture). Returns the
    /// previewed / created cluster count.
    public func autoStack(
        ids: [Int64],
        gap: Double = StackClustering.defaultGapSeconds,
        preview: Bool
    ) async throws -> Int {
        // The read leg: capture times + existing memberships for the pool.
        // The empty-pool guard mirrors `stackedIDs` below — an empty pool
        // must not spell an invalid `IN ()` statement (it clusters nothing,
        // so both faces answer 0).
        let rows: [(id: Int64, capture: Double?)] = try await store.withHandle {
            handle in
            guard !ids.isEmpty else { return [] }
            var rows: [(id: Int64, capture: Double?)] = []
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let statement = try handle.prepare(
                "SELECT id, capture_date FROM images WHERE id IN (\(placeholders))")
            for (index, id) in ids.enumerated() {
                try statement.bindInt(Int32(index + 1), id)
            }
            while try statement.step() {
                guard let id = statement.columnInt(0) else { continue }
                rows.append((id: id, capture: statement.columnDouble(1)))
            }
            return rows
        }
        let stacked = try await stackedIDs(in: ids)
        let candidates = rows.filter { !stacked.contains($0.id) }
        let clusters = StackClustering.clusters(candidates, gap: gap)
        if preview { return clusters.count }
        // The commit leg: one batch, one collapsed stack per cluster. The
        // per-cluster re-check (KD-4's belt) keeps a concurrent stacker from
        // half-landing a cluster — a contended cluster is skipped whole.
        return try await store.withWriteBatch { handle in
            var created = 0
            for cluster in clusters {
                var contended = false
                for member in cluster {
                    if try Self.stackID(of: member, on: handle) != nil {
                        contended = true
                        break
                    }
                }
                guard !contended else { continue }
                _ = try Self.insertStack(
                    memberIDs: cluster, collapsed: true, on: handle)
                created += 1
            }
            return created
        }
    }

    /// The stack memberships of the given ids (the autoStack double-defense
    /// read leg).
    private func stackedIDs(in ids: [Int64]) async throws -> Set<Int64> {
        guard !ids.isEmpty else { return [] }
        return try await store.withHandle { handle in
            var stacked = Set<Int64>()
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let statement = try handle.prepare(
                "SELECT image_id FROM stack_content"
                    + " WHERE image_id IN (\(placeholders))")
            for (index, id) in ids.enumerated() {
                try statement.bindInt(Int32(index + 1), id)
            }
            while try statement.step() {
                if let id = statement.columnInt(0) { stacked.insert(id) }
            }
            return stacked
        }
    }

    /// The member ids of one stack in POSITION order (cover first). Unknown
    /// stack = typed rejection.
    public func members(ofStack stackID: Int64) async throws -> [Int64] {
        try await store.withHandle { handle in
            try Self.existingMembers(stackID: stackID, on: handle)
        }
    }

    // MARK: Stack helpers (static — actor-confined closures carry no self)

    /// Validate rules 1-2 (KD-2): ≥2 members, no duplicates. Rule 3 (one
    /// image one stack) is the caller's per-id check — it names the image.
    static func validateStackInput(_ members: [Int64]) throws {
        guard members.count >= 2 else {
            throw LibraryError.constraintViolation(
                detail: "a stack needs at least two members, got \(members.count)")
        }
        var seen = Set<Int64>()
        for member in members {
            guard seen.insert(member).inserted else {
                throw LibraryError.constraintViolation(
                    detail: "duplicate stack member \(member)")
            }
        }
    }

    /// The group-union walk (KD-2): the head members plus the WHOLE of every
    /// stack they already belong to. `pinnedHead` (the merge product) is
    /// admitted FIRST so it stays the cover; nil = plain mention order.
    static func unionMembers(
        _ handle: SQLiteHandle, heads: [Int64], pinnedHead: Int64?
    ) throws -> (members: [Int64], involved: Set<Int64>) {
        var ordered: [Int64] = []
        var seen = Set<Int64>()
        var involved = Set<Int64>()
        func admit(_ id: Int64) {
            if seen.insert(id).inserted { ordered.append(id) }
        }
        if let pinnedHead {
            try assertImageExists(handle, id: pinnedHead)
            if let stackID = try Self.stackID(of: pinnedHead, on: handle) {
                involved.insert(stackID)
                for member in try Self.existingMembers(
                    stackID: stackID, on: handle) {
                    admit(member)
                }
            } else {
                admit(pinnedHead)
            }
        }
        for head in heads where head != pinnedHead {
            try assertImageExists(handle, id: head)
            if let stackID = try Self.stackID(of: head, on: handle) {
                involved.insert(stackID)
                for member in try Self.existingMembers(
                    stackID: stackID, on: handle) {
                    admit(member)
                }
            } else {
                admit(head)
            }
        }
        return (ordered, involved)
    }

    /// Insert one stacks row + its dense-position memberships (the shared
    /// create face for createStack/group/stackWith/split — one spelling).
    static func insertStack(
        memberIDs members: [Int64], collapsed: Bool,
        on handle: SQLiteHandle
    ) throws -> LibraryStack {
        let now = Date().timeIntervalSince1970
        let insert = try handle.prepare(
            "INSERT INTO stacks (collapsed, added_time, modified_time)"
                + " VALUES (?, ?, ?)")
        try insert.bindInt(1, collapsed ? 1 : 0)
        try insert.bindDouble(2, now)
        try insert.bindDouble(3, now)
        _ = try insert.step()
        let stackID = handle.lastInsertRowID()
        try writeMemberRows(stackID: stackID, members: members, on: handle)
        return LibraryStack(
            id: stackID, collapsed: collapsed, memberIDs: members,
            addedTime: now, modifiedTime: now)
    }

    /// Rewrite a stack's memberships to the given order (dense renumber) +
    /// stamp `modified_time` — the ONE renumbering face every mutating op
    /// reuses (KD-2's "positions stay dense 0..n−1" duty). The old rows
    /// leave FIRST: the UNIQUE image index makes a blind INSERT a violation.
    static func writePositions(
        stackID: Int64, members: [Int64], on handle: SQLiteHandle
    ) throws {
        let delete = try handle.prepare(
            "DELETE FROM stack_content WHERE stack_id = ?")
        try delete.bindInt(1, stackID)
        _ = try delete.step()
        try writeMemberRows(stackID: stackID, members: members, on: handle)
        let stamp = try handle.prepare(
            "UPDATE stacks SET modified_time = ? WHERE id = ?")
        try stamp.bindDouble(1, Date().timeIntervalSince1970)
        try stamp.bindInt(2, stackID)
        _ = try stamp.step()
    }

    static func writeMemberRows(
        stackID: Int64, members: [Int64], on handle: SQLiteHandle
    ) throws {
        let insert = try handle.prepare(
            "INSERT INTO stack_content (stack_id, image_id, position)"
                + " VALUES (?, ?, ?)")
        for (position, member) in members.enumerated() {
            try insert.reset()
            try insert.bindInt(1, stackID)
            try insert.bindInt(2, member)
            try insert.bindInt(3, Int64(position))
            _ = try insert.step()
        }
    }

    /// The stack holding `imageID` (nil = unstacked) — the UNIQUE reverse
    /// index's read face.
    static func stackID(
        of imageID: Int64, on handle: SQLiteHandle
    ) throws -> Int64? {
        let statement = try handle.prepare(
            "SELECT stack_id FROM stack_content WHERE image_id = ?")
        try statement.bindInt(1, imageID)
        return try statement.step() ? statement.columnInt(0) : nil
    }

    static func assertStackExists(
        _ handle: SQLiteHandle, id: Int64
    ) throws {
        let statement = try handle.prepare("SELECT 1 FROM stacks WHERE id = ?")
        try statement.bindInt(1, id)
        guard try statement.step() else {
            throw LibraryError.constraintViolation(
                detail: "unknown stack id \(id)")
        }
    }

    /// The members of a KNOWN stack in position order; unknown stack =
    /// typed rejection (the notFound face).
    static func existingMembers(
        stackID: Int64, on handle: SQLiteHandle
    ) throws -> [Int64] {
        try assertStackExists(handle, id: stackID)
        return try memberIDs(stackID: stackID, on: handle)
    }

    static func memberIDs(
        stackID: Int64, on handle: SQLiteHandle
    ) throws -> [Int64] {
        let statement = try handle.prepare(
            "SELECT image_id FROM stack_content WHERE stack_id = ?"
                + " ORDER BY position")
        try statement.bindInt(1, stackID)
        var members: [Int64] = []
        while try statement.step() {
            if let id = statement.columnInt(0) { members.append(id) }
        }
        return members
    }

    static func stackCollapsed(
        stackID: Int64, on handle: SQLiteHandle
    ) throws -> Bool {
        let statement = try handle.prepare(
            "SELECT collapsed FROM stacks WHERE id = ?")
        try statement.bindInt(1, stackID)
        guard try statement.step() else {
            throw LibraryError.constraintViolation(
                detail: "unknown stack id \(stackID)")
        }
        return (statement.columnInt(0) ?? 0) != 0
    }

    static func readStack(
        id: Int64, on handle: SQLiteHandle
    ) throws -> LibraryStack? {
        let statement = try handle.prepare(
            "SELECT collapsed, added_time, modified_time FROM stacks WHERE id = ?")
        try statement.bindInt(1, id)
        guard try statement.step() else { return nil }
        return LibraryStack(
            id: id,
            collapsed: (statement.columnInt(0) ?? 0) != 0,
            memberIDs: try memberIDs(stackID: id, on: handle),
            addedTime: statement.columnDouble(1),
            modifiedTime: statement.columnDouble(2))
    }

    // MARK: - Row helpers (static — actor-confined closures carry no self)

    static func assertAlbumExists(
        _ handle: SQLiteHandle, id: Int64
    ) throws {
        let statement = try handle.prepare("SELECT 1 FROM albums WHERE id = ?")
        try statement.bindInt(1, id)
        let exists = try statement.step()
        guard exists else {
            throw LibraryError.constraintViolation(detail: "unknown album id \(id)")
        }
    }

    static func assertImageExists(
        _ handle: SQLiteHandle, id: Int64
    ) throws {
        let statement = try handle.prepare("SELECT 1 FROM images WHERE id = ?")
        try statement.bindInt(1, id)
        let exists = try statement.step()
        guard exists else {
            throw LibraryError.constraintViolation(detail: "unknown image id \(id)")
        }
    }

    static func parent(of albumID: Int64, on handle: SQLiteHandle) throws -> Int64? {
        let statement = try handle.prepare(
            "SELECT parent_id FROM albums WHERE id = ?")
        try statement.bindInt(1, albumID)
        let parent: Int64? = try statement.step() ? statement.columnInt(0) : nil
        return parent
    }

    static func readAlbum(
        id: Int64, on handle: SQLiteHandle
    ) throws -> LibraryAlbum? {
        let statement = try handle.prepare("""
            SELECT type, name, parent_id, filter_data, added_time, modified_time
            FROM albums WHERE id = ?
            """)
        try statement.bindInt(1, id)
        guard try statement.step() else { return nil }
        guard let typeRaw = statement.columnText(0),
              let kind = LibrarySchema.AlbumKind(rawValue: typeRaw),
              let name = statement.columnText(1) else {
            return nil
        }
        let filterJSON = statement.columnText(3)
        var filterGroup: FilterPredicateGroup?
        if let filterJSON, let data = filterJSON.data(using: .utf8) {
            filterGroup = try? JSONDecoder().decode(
                FilterPredicateGroup.self, from: data)
        }
        let album = LibraryAlbum(
            id: id, kind: kind, name: name,
            parentID: statement.columnInt(2),
            filterGroup: filterGroup,
            addedTime: statement.columnDouble(4),
            modifiedTime: statement.columnDouble(5))
        return album
    }

    static func readImage(
        id: Int64, on handle: SQLiteHandle
    ) throws -> LibraryImage? {
        let statement = try handle.prepare("""
            SELECT image_path, path_kind, volume_uuid, file_stem, rating,
                keywords, has_edits, params_hash, ref_count
            FROM images WHERE id = ?
            """)
        try statement.bindInt(1, id)
        guard try statement.step() else { return nil }
        guard let imagePath = statement.columnText(0),
              let pathKindRaw = statement.columnInt(1),
              let pathKind = LibrarySchema.PathKind(rawValue: pathKindRaw) else {
            return nil
        }
        let image = LibraryImage(
            id: id, imagePath: imagePath, pathKind: pathKind,
            volumeUUID: statement.columnText(2),
            fileStem: statement.columnText(3),
            rating: statement.columnInt(4),
            keywords: statement.columnText(5),
            hasEdits: statement.columnInt(6),
            paramsHash: statement.columnText(7),
            refCount: statement.columnInt(8) ?? 0)
        return image
    }

    // MARK: - Filter JSON (the OQ-6 zero-new-format face)

    /// The `filter_data` spelling: sortedKeys (the SmartAlbumDocument
    /// byte-stability discipline).
    static func encodeFilterData(_ group: FilterPredicateGroup) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(group)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LibraryError.constraintViolation(detail: "filter data is not UTF-8")
        }
        return json
    }

    // MARK: - Culling analysis write face (LUMEN-A T5, additive)

    /// Persist one analysis product: the seven v6 columns only (the
    /// default-neutral red line — no other column is touched except the
    /// modified_time stamp), plus the X2 lazy-backfill legs (serial/capture
    /// fill ONLY when the stored value is NULL via COALESCE). The empty
    /// analysis (products nil, version stamped) rides the same face — the
    /// anti-retry-storm record (Lumen :162).
    public func setAnalysis(_ record: LibraryAnalysisRecord) async throws {
        let notifiedIDs: [Int64] = try await store.withWriteBatch { handle in
            let update = try handle.prepare("""
                UPDATE images SET analysis_version = ?, sharpness = ?,
                    faces = ?, eyes_closed = ?, signature = ?,
                    face_boxes = ?, camera_serial = COALESCE(camera_serial, ?),
                    capture_date = COALESCE(?, capture_date), modified_time = ?
                WHERE id = ?
                """)
            try update.bindInt(1, Int64(record.analysisVersion))
            try update.bindDouble(2, record.sharpness)
            try update.bindInt(3, record.faces.map(Int64.init))
            try update.bindInt(4, record.eyesClosed.map(Int64.init))
            try update.bindBlob(5, record.signature)
            try update.bindText(6, record.faceBoxes)
            try update.bindText(7, record.cameraSerial)
            try update.bindDouble(8, record.captureDate)
            try update.bindDouble(9, Date().timeIntervalSince1970)
            try update.bindInt(10, record.imageID)
            _ = try update.step()
            return [record.imageID]
        }
        emitAnalysis(notifiedIDs)
    }

    // MARK: - Analysis notify seam (LUMEN-A T5, review m-2)

    /// The analysis-write events: image ids whose analysis columns moved.
    /// ADDITIVE — no pre-existing row-change channel exists (the grid
    /// refreshes through caller-driven reloads); consumers (the badge
    /// refresh in T7's grid face) subscribe here. Multi-consumer.
    private var analysisContinuations:
        [UUID: AsyncStream<[Int64]>.Continuation] = [:]

    public func analysisEvents() -> AsyncStream<[Int64]> {
        AsyncStream { continuation in
            let id = UUID()
            analysisContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeAnalysisContinuation(id) }
            }
        }
    }

    private func removeAnalysisContinuation(_ id: UUID) {
        analysisContinuations[id] = nil
    }

    private func emitAnalysis(_ ids: [Int64]) {
        for continuation in analysisContinuations.values {
            continuation.yield(ids)
        }
    }
}
