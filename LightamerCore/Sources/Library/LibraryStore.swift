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

    /// Remove the images row — the album_content FK cascade takes every
    /// membership with it (the KD-4 cleanup). The refcount column dies
    /// WITH the row, so no decrement bookkeeping. Unknown id = typed
    /// rejection.
    public func removeImage(id: Int64) async throws {
        _ = try await store.withWriteBatch { handle in
            let delete = try handle.prepare("DELETE FROM images WHERE id = ?")
            try delete.bindInt(1, id)
            _ = try delete.step()
            guard handle.changes() == 1 else {
                throw LibraryError.constraintViolation(
                    detail: "unknown image id \(id)")
            }
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
}
