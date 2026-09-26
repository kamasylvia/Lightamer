import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SmartAlbumStore (Plan 12-2 T5; META-06; D-12-CONTEXT-4) — the app-level
// smart-album directory: ONE rule = ONE file under
// `~/Library/Application Support/Lightamer/SmartAlbums/<uuid>.json`.
//
// The file body is the `SmartAlbumDocument` envelope over the ONE predicate
// group (the filter bar's transient group type — same model, same bytes).
// Smart albums are APP assets: the rules live with the app, the RESULTS
// follow the currently open session (the App evaluates the group against
// the session's index via the T3 query face — the two degrees of freedom
// stay decoupled).
//
// The YiyinFontStore 三拆 pattern (YIYIN-05): session registration (the
// init rescan), typed errors, and the startup self-heal — a corrupt or
// future-schema file is SKIPPED (typed decode degradation via the predicate
// model's unknown-field errors) and never destroys user data (no file is
// ever deleted by the scanner).
//
// Write discipline: sortedKeys + a SAME-DIRECTORY tmp file promoted via
// moveItem (L009 — never a cross-volume /tmp rename).
// ─────────────────────────────────────────────────────────────────────────────

/// The persisted file body (one smart album).
public struct SmartAlbumDocument: Codable, Equatable, Sendable {
    public static let schemaVersionCurrent = 1

    public var schemaVersion: Int
    public var name: String
    public var group: FilterPredicateGroup

    public init(schemaVersion: Int = SmartAlbumDocument.schemaVersionCurrent,
                name: String, group: FilterPredicateGroup) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.group = group
    }
}

/// One loaded smart album (the registry row; `id` = the file stem — a
/// stable identity that survives renames).
public struct SmartAlbum: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var group: FilterPredicateGroup

    public init(id: String, name: String, group: FilterPredicateGroup) {
        self.id = id
        self.name = name
        self.group = group
    }
}

public enum SmartAlbumError: Error, Equatable {
    /// A blank/whitespace-only name (the UI trims; the store re-checks).
    case emptyName
    /// No album with this id.
    case notFound(id: String)
}

/// `@Observable` (the App-side sidebar observes the registry through the
/// environment) + the NSLock (the registry may be touched from multiple
/// actors — the store is `@unchecked Sendable` like its YiyinFontStore
/// model).
@Observable
public final class SmartAlbumStore: @unchecked Sendable {

    public let directory: URL

    private let lock = NSLock()
    private var registry: [SmartAlbum] = []
    /// Files the rescan skipped (corrupt JSON / unknown predicate field —
    /// the typed forward-compat degradation). Never deleted; surfaced for
    /// diagnostics.
    public private(set) var skippedFiles: [String] = []

    /// Default directory:
    /// `~/Library/Application Support/Lightamer/SmartAlbums`.
    public convenience init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lightamer/SmartAlbums", isDirectory: true)
        self.init(directory: base)
    }

    /// Injected-directory init (tests + the app root's explicit layout).
    /// The startup rescan IS the self-heal: files decode or are skipped,
    /// the in-memory registry reflects exactly the readable set.
    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        rescan()
    }

    /// Re-read every `*.json` in the directory (sorted for a stable
    /// registry order; failures land in `skippedFiles` — never a crash,
    /// never a deletion).
    public func rescan() {
        lock.lock()
        defer { lock.unlock() }
        registry = []
        skippedFiles = []
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: file),
                  let document = try? JSONDecoder().decode(
                      SmartAlbumDocument.self, from: data)
            else {
                skippedFiles.append(file.lastPathComponent)
                continue
            }
            registry.append(
                SmartAlbum(
                    id: file.deletingPathExtension().lastPathComponent,
                    name: document.name,
                    group: document.group))
        }
        registry.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Read face

    /// The registry (sorted by name — the sidebar's stable order).
    public func albums() -> [SmartAlbum] {
        lock.lock()
        defer { lock.unlock() }
        return registry
    }

    public func album(id: String) -> SmartAlbum? {
        lock.lock()
        defer { lock.unlock() }
        return registry.first { $0.id == id }
    }

    // MARK: - Write face (typed errors; every write validates the group)

    /// Create a new album: validates the name and the predicate group, then
    /// writes the file atomically and registers the row.
    @discardableResult
    public func create(
        name rawName: String, group: FilterPredicateGroup
    ) throws -> SmartAlbum {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SmartAlbumError.emptyName }
        try group.validating()

        let id = UUID().uuidString
        let album = SmartAlbum(id: id, name: name, group: group)
        try write(album)
        lock.lock()
        registry.append(album)
        registry.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lock.unlock()
        return album
    }

    /// Rename (the file keeps its id — only the document's name changes).
    public func rename(id: String, to rawName: String) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SmartAlbumError.emptyName }
        lock.lock()
        guard let index = registry.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            throw SmartAlbumError.notFound(id: id)
        }
        registry[index].name = name
        let album = registry[index]
        registry.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lock.unlock()
        try write(album)
    }

    /// Replace the predicate group (the rules-live-with-the-app edit face;
    /// v1 has no editor UI — the API is the smart-album re-save seam).
    public func updateGroup(id: String, group: FilterPredicateGroup) throws {
        try group.validating()
        lock.lock()
        guard let index = registry.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            throw SmartAlbumError.notFound(id: id)
        }
        registry[index].group = group
        let album = registry[index]
        lock.unlock()
        try write(album)
    }

    /// Remove: the file goes FIRST (disk truth leads), then the registry
    /// row. A failed removal leaves the row (the state never lies; the next
    /// rescan reconciles).
    public func remove(id: String) throws {
        lock.lock()
        guard let index = registry.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            throw SmartAlbumError.notFound(id: id)
        }
        let album = registry[index]
        lock.unlock()
        let file = directory.appendingPathComponent(album.id + ".json")
        try FileManager.default.removeItem(at: file)
        lock.lock()
        registry.removeAll { $0.id == id }
        lock.unlock()
    }

    // MARK: - Atomic write (sortedKeys + same-dir tmp promotion, L009)

    private func write(_ album: SmartAlbum) throws {
        let document = SmartAlbumDocument(
            name: album.name, group: album.group)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        // The tmp file lives in the SAME directory (same volume — the L009
        // red line bans cross-volume /tmp renames) and moveItem is the
        // atomic promotion.
        let tmp = directory.appendingPathComponent(
            ".tmp-" + UUID().uuidString + ".json")
        try data.write(to: tmp, options: .atomic)
        let target = directory.appendingPathComponent(album.id + ".json")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: tmp, to: target)
    }
}
