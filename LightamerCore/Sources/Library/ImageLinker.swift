import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ImageLinker (Plan M2-2-2 T2) — the KD-3 data face over the images rows'
// three-form path carrier (LibrarySchema.PathKind):
//
//   kind0 projectRelative — `<project dir>/Media/...` stored project-
//     relative; whole-directory moves are immune to mount-point renames
//     (the .lalb and its Media/ travel together, the relative path holds).
//   kind1 volumeRelative  — same-volume link import (OQ-5 A): path stored
//     RELATIVE TO THE VOLUME MOUNT POINT + the volume's UUID. Immune to
//     mount-point renames (the L009 `/Volumes/UNITEK` scenario) because
//     resolution matches the UUID, not the mount path.
//   kind2 absolute        — cross-volume fallback: absolute path + UUID
//     (still recorded, so "why is it broken" stays answerable).
//
// Stale = typed, two forms: `pathMissing` (a concrete path resolved but
// the file is gone) vs `volumeAbsent` (no mounted volume carries the
// recorded UUID — the OQ-5 "know WHY it broke" upgrade over a bare broken
// path). `relinkRecord` rebuilds kind/uuid/path from a file's CURRENT
// volume relationship (the Inspector's batch-relink data face; UI = M2-3).
//
// Volume identity = `URLResourceKey.volumeIdentifierKey` (Apple's stable
// per-volume identity); the mount point comes from statfs f_mntonname.
// When the UUID is unobtainable the record degrades TYPED to kind2 with a
// nil UUID (absolute paths still resolve by stat; SUMMARY notes the
// degradation) — never a silent guess.
// ─────────────────────────────────────────────────────────────────────────────

/// Why a link/reference row failed to resolve (OQ-5's two-form stale).
public enum ImageLinkStaleReason: Sendable, Equatable {
    /// The row resolved to a concrete path but no file lives there.
    case pathMissing
    /// No mounted volume carries the recorded volume UUID (the disk that
    /// held the linked original is not plugged in / was reformatted).
    case volumeAbsent
}

/// The resolve outcome (a usable file URL or a typed stale face).
public enum ImageLinkResolution: Sendable, Equatable {
    case resolved(URL)
    case stale(ImageLinkStaleReason)
}

public enum ImageLinker {

    // MARK: - Volume identity

    /// The stable volume identifier (UUID string) for the volume holding
    /// `url` — nil when the resource values are unavailable (typo'd path,
    /// detached volume): callers degrade typed, never guess.
    public static func volumeUUID(of url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey]),
              let identifier = values.volumeIdentifier else { return nil }
        if let uuid = identifier as? UUID { return uuid.uuidString }
        if let uuid = identifier as? NSUUID { return uuid.uuidString }
        if let data = identifier as? Data {
            return data.map { String(format: "%02X", $0) }.joined()
        }
        return String(describing: identifier)
    }

    /// The mount point of the volume holding `url` (statfs f_mntonname).
    static func volumeRoot(of url: URL) -> URL? {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return nil }
        let mount = withUnsafeBytes(of: fs.f_mntonname) { buffer -> String? in
            let chars = buffer.bindMemory(to: CChar.self)
            guard let base = chars.baseAddress else { return nil }
            return String(cString: base)
        }
        guard let mount, !mount.isEmpty else { return nil }
        return URL(fileURLWithPath: mount, isDirectory: true)
    }

    /// The kind1 stored spelling: `path` relative to the mount point when
    /// the path lives under it (the external-volume case — `/Volumes/X/...`
    /// survives a mount rename to `/Volumes/X2` through the UUID match).
    /// When the path does NOT carry the mount prefix — the root volume's
    /// firmlink reality (`/var`, `/tmp`, `/Users` report the Data-volume
    /// mount `/System/Volumes/Data` whose prefix the user-visible spelling
    /// never carries, and the mount-internal spelling does not resolve) —
    /// the `/`-rooted spelling is stored instead. `resolve` tries BOTH
    /// spellings against the UUID-matched volume, so both shapes resolve.
    static func relativePath(of path: URL, from root: URL) -> String {
        var rootPath = root.path
        while rootPath.hasSuffix("/") { rootPath.removeLast() }
        let fullPath = path.path
        if fullPath.hasPrefix(rootPath + "/") {
            return String(fullPath.dropFirst(rootPath.count + 1))
        }
        var trimmed = fullPath
        while trimmed.hasPrefix("/") { trimmed.removeFirst() }
        return trimmed
    }

    /// The candidate absolute spellings for a stored kind1 path on a
    /// volume rooted at `volume`: the mount-relative spelling first, then
    /// the `/`-rooted spelling (deduped — on the root volume they coincide).
    static func kind1Candidates(imagePath: String, volume: URL) -> [URL] {
        var candidates: [URL] = [volume.appendingPathComponent(imagePath)]
        let mounted = volume.path
        if mounted != "/" {
            candidates.append(URL(fileURLWithPath: "/" + imagePath))
        }
        return candidates
    }

    // MARK: - Record (import-time carrier + relink face)

    /// The link-row carrier for `source` under `projectDirectory` (KD-3):
    /// same volume as the project (UUID equality) → kind1 volume-relative
    /// + UUID; otherwise kind2 absolute + UUID (UUID unobtainable → kind2
    /// with nil — the typed degradation). `uuidProbe` is the test seam
    /// (forces the cross-volume leg without a second physical disk).
    public static func record(
        for source: URL, projectDirectory: URL,
        uuidProbe: (@Sendable (URL) -> String?)? = nil
    ) -> (imagePath: String, pathKind: LibrarySchema.PathKind, volumeUUID: String?) {
        let probe = uuidProbe ?? Self.volumeUUID
        let sourceUUID = probe(source)
        let projectUUID = probe(projectDirectory)
        if let sourceUUID, let projectUUID, sourceUUID == projectUUID,
           let root = volumeRoot(of: source) {
            return (relativePath(of: source, from: root), .volumeRelative, sourceUUID)
        }
        return (source.path, .absolute, sourceUUID)
    }

    /// Re-point a (typically stale) row at `newSource` — rebuild kind/uuid/
    /// path from the file's CURRENT relationship to the project (the
    /// OQ-5 relink data face; the M2-3 Inspector calls this per row).
    public static func relinkRecord(
        for newSource: URL, projectDirectory: URL,
        uuidProbe: (@Sendable (URL) -> String?)? = nil
    ) -> (imagePath: String, pathKind: LibrarySchema.PathKind, volumeUUID: String?) {
        record(for: newSource, projectDirectory: projectDirectory, uuidProbe: uuidProbe)
    }

    // MARK: - Resolve (read time)

    /// Resolve a stored row to a file URL or a typed stale face (KD-3):
    /// kind0 = project-relative stat; kind1 = UUID-match the project's
    /// volume (fast path) or traverse the mounted volumes, then stat;
    /// kind2 = absolute stat.
    public static func resolve(
        imagePath: String,
        pathKind: LibrarySchema.PathKind,
        volumeUUID: String?,
        projectDirectory: URL
    ) -> ImageLinkResolution {
        switch pathKind {
        case .projectRelative:
            let url = projectDirectory.appendingPathComponent(imagePath)
            return fileExists(url) ? .resolved(url) : .stale(.pathMissing)

        case .volumeRelative:
            guard let volumeUUID, !volumeUUID.isEmpty else {
                return .stale(.volumeAbsent)
            }
            // Fast path: the project still sits on the recorded volume.
            if let projectUUID = Self.volumeUUID(of: projectDirectory),
               projectUUID == volumeUUID,
               let root = Self.volumeRoot(of: projectDirectory) {
                for candidate in kind1Candidates(imagePath: imagePath, volume: root)
                where fileExists(candidate) {
                    return .resolved(candidate)
                }
                return .stale(.pathMissing)
            }
            // Else match a mounted volume by UUID (the disk may be mounted
            // anywhere — the mount-point-rename immunity is the point).
            let volumes = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeIdentifierKey],
                options: [.skipHiddenVolumes]) ?? []
            for volume in volumes {
                guard let candidateVolume = Self.volumeUUID(of: volume),
                      candidateVolume == volumeUUID else { continue }
                for candidate in kind1Candidates(imagePath: imagePath, volume: volume)
                where fileExists(candidate) {
                    return .resolved(candidate)
                }
                return .stale(.pathMissing)
            }
            return .stale(.volumeAbsent)

        case .absolute:
            let url = URL(fileURLWithPath: imagePath)
            return fileExists(url) ? .resolved(url) : .stale(.pathMissing)
        }
    }

    /// The existence face for resolved paths (FileManager stat).
    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
