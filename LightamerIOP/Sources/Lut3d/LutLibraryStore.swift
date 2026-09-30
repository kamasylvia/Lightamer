import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// LutLibraryStore (Plan 12-5 T5, IOP-COLOR-08/PRES-03; M2-5-3 KD-1..KD-4)
// — the user LUT library: `~/Library/Application Support/Lightamer/LUTs/`
// (or the user-configured root, `lut.library.root`) + a registry +
// startup rescan (the YiyinFontStore three-part pattern).
//
// REFERENCE SEMANTICS (D-6 / 12-4 D10): iop params store a LIBRARY
// REFERENCE (not the source path — the path is dropped at import so
// references never rot). `.lightamer-preset` portability presumes the LUT
// library itself is copied; a missing entry degrades to the module's
// routed blit identity + a GUI toast (the unknown-op posture, DECISIONS
// D10 follow-up on the 12-4 hook).
//
// M2-5-3 REGISTRY KEY UPGRADE (KD-1): the `installed`/`parsed` keys moved
// from the file NAME to the ROOT-RELATIVE POSIX path (`BuiltIn/Foo.cube`).
// One upgrade carries three things: recursive subdirectories (KD-2),
// same-name disambiguation (relative paths are unique by construction)
// and the configurable root (KD-3 — every root holds its own self-
// contained registry). Root-level files keep relativePath == file name,
// so the legacy flat encoding is the degenerate case. Rows written
// before the upgrade (no `relativePath` field) decode tolerantly: the
// field is derived from the dict key (== the file name) and written back
// on the next rescan. Legacy references in old documents (bare file
// names) resolve through a UNIQUE tail-segment fallback at query time —
// the stored reference bytes are never rewritten.
//
// IMPORT (plan literal): copy into the library + FNV-1a-64 content
// dedup — importing the same BYTES under a different name does NOT copy
// again (the existing entry is returned; one content, one stored file).
// Same name with NEW content overwrites (an update), refreshing the
// parsed cache. Files must parse as .cube (typed failure — never a
// silent fallback, the YiyinFontStore discipline).
// ─────────────────────────────────────────────────────────────────────────

public final class LutLibraryStore: Lut3dModule.LutResolving, @unchecked Sendable {

    public enum LutError: Error, Equatable {
        case unsupportedFormat(name: String)
        case unreadable(name: String)
        case corruptCube(name: String, reason: String)
        case notFound(name: String)
    }

    /// One installed LUT (the registry row). `name` is the FILE NAME (the
    /// display base); the registry KEY is `relativePath` (KD-1). The two
    /// additive fields are optional so the pre-recursive registry (flat
    /// keys, no new fields) decodes without a custom conformance; the
    /// decode fixup derives them from the dict key.
    public struct InstalledLut: Codable, Equatable, Sendable {
        public var name: String
        public var hash: String
        public var is1D: Bool
        public var size: Int
        public var title: String?
        /// The root-relative POSIX path — the registry key encoding
        /// (KD-1). nil only on rows decoded from the legacy registry
        /// (derived from the key + written back on the next rescan).
        public var relativePath: String?
        /// The containing subdirectory relative to the root (nil = the
        /// root itself; the panel groups on this).
        public var subdirectory: String?

        public init(
            name: String, relativePath: String? = nil, subdirectory: String? = nil,
            hash: String, is1D: Bool, size: Int, title: String?
        ) {
            self.name = name
            self.hash = hash
            self.is1D = is1D
            self.size = size
            self.title = title
            self.relativePath = relativePath
            self.subdirectory = subdirectory
        }

        /// The in-memory key face (relativePath is always set post-fixup).
        public var resolvedRelativePath: String { relativePath ?? name }
    }

    // MARK: - Shared holder (M2-5-3 KD-3, checker m6)

    private static let sharedLock = NSLock()
    private nonisolated(unsafe) static var sharedInstance = LutLibraryStore()

    /// The shared instance the registry-populated modules resolve through.
    /// Reads ride the lock so a root switch (Settings) is atomic against
    /// concurrent resolutions. Tests construct their own with a temporary
    /// directory.
    public static var shared: LutLibraryStore {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        return sharedInstance
    }

    /// Atomically replace the shared store (the Settings root switch:
    /// build the new store, then swap it in — the getter face above keeps
    /// every consumer on the live instance).
    public static func replaceShared(_ store: LutLibraryStore) {
        sharedLock.lock()
        sharedInstance = store
        sharedLock.unlock()
    }

    /// A `LutResolving` face that ALWAYS forwards to the current shared
    /// instance. Module boxes are constructed once at registry install and
    /// would otherwise capture the store snapshot of that moment; handing
    /// them this forwarder keeps resolution on the live store after a
    /// root switch without touching Lut3dModule (kernel face zero diff).
    public struct SharedForwardingResolver: Lut3dModule.LutResolving, Sendable {
        public init() {}
        public func lut(named: String) -> CubeLut? { LutLibraryStore.shared.lut(named: named) }
    }

    /// The forwarding face for long-lived module boxes (Registry install).
    public static let sharedResolver = SharedForwardingResolver()

    // MARK: - Root configuration (M2-5-3 KD-3)

    /// The UserDefaults key hosting the user-configurable library root
    /// (registered spelling; `AppPreferences` re-exports the registration
    /// + reset face on the App side). Empty/unset = the default root.
    public static let libraryRootKey = "lut.library.root"

    /// The default library root (unchanged from 12-5).
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lightamer/LUTs", isDirectory: true)
    }

    /// KD-3 reachability probe for a candidate root (the L009 external-
    /// volume lesson): it must exist as a directory AND accept a write.
    /// A failed probe = the Settings switch degrades to the default root
    /// + an error line (v1 creates NO security-scoped bookmark — the
    /// stored path stays a plain String by design).
    public static func validateRoot(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return false }
        let probe = url.appendingPathComponent(".lightamer-lut-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }
        return FileManager.default.createFile(atPath: probe.path, contents: Data())
    }

    public static let supportedExtensions = ["cube"]

    public let lutsDirectory: URL
    public let registryURL: URL

    private let lock = NSLock()
    private var installed: [String: InstalledLut] = [:]
    private var parsed: [String: CubeLut] = [:]

    public init(directory: URL? = nil) {
        let base: URL
        if let directory {
            base = directory
        } else if let stored = UserDefaults.standard.string(forKey: Self.libraryRootKey),
            !stored.isEmpty
        {
            base = URL(fileURLWithPath: stored, isDirectory: true)
        } else {
            base = Self.defaultRoot
        }
        self.lutsDirectory = base
        self.registryURL = base.appendingPathComponent("registry.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: registryURL),
            let decoded = try? JSONDecoder().decode([String: InstalledLut].self, from: data)
        {
            // KD-1 legacy migration: rows written before the key upgrade
            // carry no relativePath — derive it from the dict key (the
            // legacy flat encoding, where key == file name == a root
            // file). The next persistRegistry writes the upgraded form.
            var migrated: [String: InstalledLut] = [:]
            migrated.reserveCapacity(decoded.count)
            for (key, entry) in decoded {
                var upgradedEntry = entry
                if upgradedEntry.relativePath == nil {
                    upgradedEntry.relativePath = key
                    upgradedEntry.subdirectory = nil
                }
                migrated[key] = upgradedEntry
            }
            installed = migrated
        }
        // KD-4: the built-in set seeds ONLY on the default root (a custom
        // root is user data territory — no automatic copies there).
        if base.standardizedFileURL.path == Self.defaultRoot.standardizedFileURL.path,
            let bundled = Bundle.main.url(forResource: "LUTs", withExtension: nil)
        {
            Self.seedBuiltIns(from: bundled, into: base)
        }
        rescan()
    }

    // MARK: - Recursive rescan (M2-5-3 KD-2)

    /// Startup rescan self-heal (YiyinFontStore shape): drop registry rows
    /// whose files vanished (or whose bytes changed — re-parse them),
    /// adopt library files present on disk but missing from the registry.
    /// M2-5-3: the adoption walk is RECURSIVE (`enumerator(at:)`) — any
    /// depth of subdirectory is collected; hidden directories (dot
    /// prefixes, e.g. `.lathumbs`-style derivatives) are skipped;
    /// `registry.json` never matches the extension filter.
    public func rescan() {
        lock.lock()
        defer { lock.unlock() }
        // Validate existing rows (keyed by relativePath post-upgrade).
        for (key, entry) in installed {
            let relative = entry.relativePath ?? key
            let url = lutsDirectory.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url) else {
                installed.removeValue(forKey: key)
                parsed.removeValue(forKey: key)
                continue
            }
            if StableHash.hash(data) == UInt64(entry.hash) {
                // File intact — ensure the parse cache is warm.
                if parsed[key] == nil, let lut = try? CubeLutParser.parse(data: data) {
                    parsed[key] = lut
                }
            } else {
                // Content drifted (external overwrite) — re-parse + re-hash.
                adopt(data: data, relativePath: relative)
            }
        }
        // Adopt unregistered files — recursive (KD-2).
        let enumerator = FileManager.default.enumerator(
            at: lutsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                continue
            }
            guard Self.supportedExtensions.contains(url.pathExtension.lowercased()),
                let relative = Self.relativePath(of: url, within: lutsDirectory),
                installed[relative] == nil,
                let data = try? Data(contentsOf: url)
            else { continue }
            adopt(data: data, relativePath: relative)
        }
        persistRegistry()
    }

    /// The root-relative POSIX path of `url` (nil when outside the root —
    /// the enumerator cannot produce this, but the guard keeps the path
    /// arithmetic honest).
    private static func relativePath(of url: URL, within root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return String(path.dropFirst(rootPath.count + 1))
    }

    /// Parse + register `data` under `relativePath` (no dedup — the
    /// adopt/update path). Caller holds the lock.
    private func adopt(data: Data, relativePath: String) {
        do {
            let lut = try CubeLutParser.parse(data: data)
            let is1D: Bool
            let size: Int
            switch lut.kind {
            case .lut3d(let s): is1D = false; size = s
            case .lut1d(let s): is1D = true; size = s
            }
            let name = (relativePath as NSString).lastPathComponent
            let subdirectory = relativePath.contains("/")
                ? String(relativePath[..<relativePath.lastIndex(of: "/")!])
                : nil
            installed[relativePath] = InstalledLut(
                name: name, relativePath: relativePath, subdirectory: subdirectory,
                hash: String(StableHash.hash(data)), is1D: is1D, size: size, title: lut.title)
            parsed[relativePath] = lut
        } catch {
            // A drifted/corrupt file loses its row (typed absence — the
            // module's missing-entry degradation covers references).
            installed.removeValue(forKey: relativePath)
            parsed.removeValue(forKey: relativePath)
        }
    }

    private func persistRegistry() {
        let entries = installed
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    // MARK: - KD-1 resolution (legacy reference compatibility)

    /// The registry key for a params reference: the exact key (the new
    /// relativePath encoding) first; a legacy bare file-name reference
    /// falls back to a UNIQUE tail-segment match. Ambiguous (the same
    /// file name in several subdirectories) or absent = nil — the caller
    /// degrades (blit identity + toast), the stored bytes stay untouched.
    private func resolvedKey(for name: String) -> String? {
        if installed[name] != nil { return name }
        var match: String?
        for (key, entry) in installed {
            let relative = entry.relativePath ?? key
            guard relative == name || relative.hasSuffix("/" + name) else { continue }
            if match != nil { return nil }
            match = key
        }
        return match
    }

    // MARK: - Query faces

    /// The registry keys (root-relative POSIX paths). For a flat
    /// root-only library these ARE the file names (the legacy encoding).
    public var installedNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return installed.keys.sorted()
    }

    /// The key a picker should tag/display for `name` — the exact key or
    /// the resolved legacy fallback (nil = unresolvable). Lets the panel
    /// highlight legacy references WITHOUT rewriting their bytes.
    public func displayKey(for name: String?) -> String? {
        guard let name else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return resolvedKey(for: name)
    }

    public func entry(named name: String) -> InstalledLut? {
        lock.lock()
        defer { lock.unlock() }
        guard let key = resolvedKey(for: name) else { return nil }
        return installed[key]
    }

    public func entry(withHash hash: String) -> InstalledLut? {
        lock.lock()
        defer { lock.unlock() }
        return installed.values.first { $0.hash == hash }
    }

    /// The Lut3dModule resolution face (nil = missing → blit identity).
    public func lut(named: String) -> CubeLut? {
        lock.lock()
        defer { lock.unlock() }
        guard let key = resolvedKey(for: named) else { return nil }
        return parsed[key]
    }

    /// The missing-entry check for the GUI toast (nil entry + non-nil name
    /// in params = the degraded state).
    public func isMissing(_ name: String?) -> Bool {
        guard let name else { return false }
        return lut(named: name) == nil
    }

    // MARK: - Panel tree face (M2-5-3, M2GRADE-05)

    /// One subdirectory group of the library tree (`path` "" = the root).
    public struct LibraryGroup: Equatable, Sendable {
        public let path: String
        public let keys: [String]

        public init(path: String, keys: [String]) {
            self.path = path
            self.keys = keys
        }
    }

    /// The tree grouping for the panel: the root group first, then
    /// subdirectory groups with `BuiltIn` (the seeded set) leading and the
    /// rest alphabetical.
    public func libraryGroups() -> [LibraryGroup] {
        lock.lock()
        defer { lock.unlock() }
        var root: [String] = []
        var byPath: [String: [String]] = [:]
        for (key, entry) in installed {
            if let path = entry.subdirectory {
                byPath[path, default: []].append(key)
            } else {
                root.append(key)
            }
        }
        let groups = byPath.keys.sorted { lhs, rhs in
            if lhs == "BuiltIn" { return true }
            if rhs == "BuiltIn" { return false }
            return lhs < rhs
        }
        return (
            [LibraryGroup(path: "", keys: root.sorted())]
                + groups.map { LibraryGroup(path: $0, keys: byPath[$0]!.sorted()) }
        )
    }

    // MARK: - Import / remove

    /// Import a .cube file: parse-validate, dedup by content hash, copy
    /// into the library ROOT (subdirectory placement = drop files in the
    /// Finder; the recursion picks them up on rescan). Same-name-new-
    /// content = an update.
    @discardableResult
    public func importLut(from sourceURL: URL) throws -> InstalledLut {
        let ext = sourceURL.pathExtension.lowercased()
        let name = sourceURL.lastPathComponent
        guard Self.supportedExtensions.contains(ext) else {
            throw LutError.unsupportedFormat(name: name)
        }
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw LutError.unreadable(name: name)
        }
        let lut: CubeLut
        do {
            lut = try CubeLutParser.parse(data: data)
        } catch let error as CubeLutError {
            throw LutError.corruptCube(name: name, reason: String(describing: error))
        } catch {
            throw LutError.corruptCube(name: name, reason: "unknown parse failure")
        }

        let hash = String(StableHash.hash(data))
        lock.lock()
        defer { lock.unlock() }
        // Content dedup (plan literal: 同哈希改名不重拷).
        if let existing = installed.values.first(where: { $0.hash == hash }) {
            return existing
        }
        // Copy into the library root (same-name = an update overwrites).
        try? FileManager.default.removeItem(at: lutsDirectory.appendingPathComponent(name))
        do {
            try data.write(
                to: lutsDirectory.appendingPathComponent(name), options: .atomic)
        } catch {
            throw LutError.unreadable(name: name)
        }
        adopt(data: data, relativePath: name)
        persistRegistry()
        return installed[name]!
    }

    /// Remove a library entry: delete the file + drop the row (references
    /// degrade to the blit identity per the D-10 posture). The name may be
    /// a registry key or a legacy bare file name (resolved first).
    public func removeLut(named name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let key = resolvedKey(for: name), installed[key] != nil else {
            throw LutError.notFound(name: name)
        }
        try? FileManager.default.removeItem(
            at: lutsDirectory.appendingPathComponent(installed[key]!.resolvedRelativePath))
        installed.removeValue(forKey: key)
        parsed.removeValue(forKey: key)
        persistRegistry()
    }

    // MARK: - Built-in set seeder (M2-5-3 KD-4)

    /// Copy the built-in film LUT set (`sourceDirectory` — the bundle
    /// `LUTs/` folder: tables + LICENSE + NOTICE) into `root/BuiltIn/`.
    /// First-launch semantics: the init runs this on the DEFAULT root
    /// only. Idempotency sentinel = destination exists with the same byte
    /// count (content-hash compares are too dear for a startup path; a
    /// drifted file is re-copied — the rescan "content drift re-parse"
    /// spirit). Returns the copy count (0 = nothing to do).
    @discardableResult
    public static func seedBuiltIns(from sourceDirectory: URL, into root: URL) -> Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: sourceDirectory, includingPropertiesForKeys: nil)
        else { return 0 }
        let destination = root.appendingPathComponent("BuiltIn", isDirectory: true)
        var copied = 0
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if let size = try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                let existing = try? Data(contentsOf: target),
                existing.count == size
            { continue }
            do {
                try FileManager.default.createDirectory(
                    at: destination, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: item, to: target)
                copied += 1
            } catch {
                // Best-effort: a failed copy simply stays unregistered
                // (the rescan adopts what landed).
                continue
            }
        }
        return copied
    }
}
