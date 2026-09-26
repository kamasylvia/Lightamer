import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// LutLibraryStore (Plan 12-5 T5, IOP-COLOR-08/PRES-03) — the user LUT
// library: `~/Library/Application Support/Lightamer/LUTs/` + a name→file
// registry + startup rescan (the YiyinFontStore three-part pattern).
//
// REFERENCE SEMANTICS (D-6 / 12-4 D10): iop params store the LIBRARY
// FILE NAME (not the source path — the path is dropped at import so
// references never rot). `.lightamer-preset` portability presumes the LUT
// library itself is copied; a missing entry degrades to the module's
// routed blit identity + a GUI toast (the unknown-op posture, DECISIONS
// D10 follow-up on the 12-4 hook).
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

    /// One installed LUT (the registry row). `name` IS the library file
    /// name — the string lut3d params reference (L013: the hash is the
    /// decimal String form, never raw UInt64 in JSON).
    public struct InstalledLut: Codable, Equatable, Sendable {
        public var name: String
        public var hash: String
        public var is1D: Bool
        public var size: Int
        public var title: String?

        public init(name: String, hash: String, is1D: Bool, size: Int, title: String?) {
            self.name = name
            self.hash = hash
            self.is1D = is1D
            self.size = size
            self.title = title
        }
    }

    /// The shared instance the registry-populated modules resolve through.
    /// Tests construct their own with a temporary directory.
    public static let shared = LutLibraryStore()

    public static let supportedExtensions = ["cube"]

    public let lutsDirectory: URL
    public let registryURL: URL

    private let lock = NSLock()
    private var installed: [String: InstalledLut] = [:]
    private var parsed: [String: CubeLut] = [:]

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lightamer/LUTs", isDirectory: true)
        self.lutsDirectory = base
        self.registryURL = base.appendingPathComponent("registry.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: registryURL),
            let decoded = try? JSONDecoder().decode([String: InstalledLut].self, from: data)
        {
            installed = decoded
        }
        rescan()
    }

    /// Startup rescan self-heal (YiyinFontStore shape): drop registry rows
    /// whose files vanished (or whose bytes changed — re-parse them),
    /// adopt library files present on disk but missing from the registry.
    public func rescan() {
        lock.lock()
        defer { lock.unlock() }
        // Validate existing rows.
        for (name, entry) in installed {
            let url = lutsDirectory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                installed.removeValue(forKey: name)
                parsed.removeValue(forKey: name)
                continue
            }
            if StableHash.hash(data) == UInt64(entry.hash) {
                // File intact — ensure the parse cache is warm.
                if parsed[name] == nil, let lut = try? CubeLutParser.parse(data: data) {
                    parsed[name] = lut
                }
            } else {
                // Content drifted (external overwrite) — re-parse + re-hash.
                adopt(data: data, name: name)
            }
        }
        // Adopt unregistered files.
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: lutsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where Self.supportedExtensions.contains(
            url.pathExtension.lowercased())
        {
            let name = url.lastPathComponent
            guard installed[name] == nil, let data = try? Data(contentsOf: url) else { continue }
            adopt(data: data, name: name)
        }
        persistRegistry()
    }

    /// Parse + register `data` under `name` (no dedup — the adopt/update
    /// path). Caller holds the lock.
    private func adopt(data: Data, name: String) {
        do {
            let lut = try CubeLutParser.parse(data: data)
            let is1D: Bool
            let size: Int
            switch lut.kind {
            case .lut3d(let s): is1D = false; size = s
            case .lut1d(let s): is1D = true; size = s
            }
            installed[name] = InstalledLut(
                name: name, hash: String(StableHash.hash(data)), is1D: is1D,
                size: size, title: lut.title)
            parsed[name] = lut
        } catch {
            // A drifted/corrupt file loses its row (typed absence — the
            // module's missing-entry degradation covers references).
            installed.removeValue(forKey: name)
            parsed.removeValue(forKey: name)
        }
    }

    private func persistRegistry() {
        let entries = installed
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }

    // MARK: - Query faces

    public var installedNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return installed.keys.sorted()
    }

    public func entry(named name: String) -> InstalledLut? {
        lock.lock()
        defer { lock.unlock() }
        return installed[name]
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
        return parsed[named]
    }

    /// The missing-entry check for the GUI toast (nil entry + non-nil name
    /// in params = the degraded state).
    public func isMissing(_ name: String?) -> Bool {
        guard let name else { return false }
        return lut(named: name) == nil
    }

    // MARK: - Import / remove

    /// Import a .cube file: parse-validate, dedup by content hash, copy
    /// into the library. Same-name-new-content = an update.
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
        // Copy into the library (same-name = an update overwrites).
        try? FileManager.default.removeItem(at: lutsDirectory.appendingPathComponent(name))
        do {
            try data.write(
                to: lutsDirectory.appendingPathComponent(name), options: .atomic)
        } catch {
            throw LutError.unreadable(name: name)
        }
        adopt(data: data, name: name)
        persistRegistry()
        return installed[name]!
    }

    /// Remove a library entry: delete the file + drop the row (references
    /// degrade to the blit identity per the D-10 posture).
    public func removeLut(named name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard installed[name] != nil else {
            throw LutError.notFound(name: name)
        }
        try? FileManager.default.removeItem(at: lutsDirectory.appendingPathComponent(name))
        installed.removeValue(forKey: name)
        parsed.removeValue(forKey: name)
        persistRegistry()
    }
}
