import Darwin
import Foundation
import LightamerCore
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionTreeScanner (Plan 09-01 T3; D-09-CONTEXT-3) — the recursive browse-
// collection walk.
//
// Browse set = the session root RECURSIVELY (photographers organize by
// day/scene subfolders), excluding:
//   • the reserved ROOT-LEVEL dirs `Capture/` `Crop/` `Output/` (a nested
//     user folder with the same name deeper in the tree stays browsable);
//   • `.lightamer/` (own derived cache — self-feedback-loop defense) and
//     EVERY dotfile/dot-directory;
//   • `*.tmp-*` (SidecarStore promotion residue — same `.tmp-` pattern);
//   • `*.cosessiondb` (C1 session artifacts — read-only, never touched);
//   • `.lra` files themselves (sidecar attachments, never browse rows).
//
// Output = a STREAM of pages of stat triples `(relPath, mtime, size)` —
// the progressive-ingest seam (9-3's grid renders while the walk runs) and
// T4's single-transaction incremental sync consumes it page by page.
//
// Orphan sidecars (`.lra` whose original is gone) are CLASSIFIED, never a
// hard failure (ROADMAP SC#2 "gracefully") — they ride the stream in a
// separate lane; the reconcile ACTIONS arrive in 9-2.
//
// The `isExcludedFile`/`isExcludedDirectory` predicates are the SINGLE
// SOURCE shared with the 9-2 FSEvents watcher.
//
// Extension filter (execution decision, recorded in 09-01-DECISIONS): a
// static extension set mirroring `RAWDecoder`'s UTI surface + the raster
// fallback (JPEG/TIFF/HEIC/PNG/WebP) — extension matching only (no UTI
// resolution per file: 10k stat-time files must not pay type resolution).
// ─────────────────────────────────────────────────────────────────────────────

// The stat-triple/page types (`SessionScanEntry`/`SessionScanPage`) live in
// LightamerCore next to `SessionIndexStore` — the sync consumes them across
// the module boundary (T4).

enum SessionTreeScanner {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-scan"
    )

    /// Emitted entries per page (progressive ingest granularity).
    static let pageSize = 256

    // MARK: - Extension sets (execution decision — see 09-01-DECISIONS)

    /// RAW extensions mirroring `RAWDecoder.rawUTIs` (+ the common `nrw`
    /// Nikon alias; dynamic UTI conformance cannot be afforded at scan
    /// time — decode-time routing still uses the REAL UTI path).
    static let rawExtensions: Set<String> = [
        "arw", "cr2", "cr3", "nef", "nrw", "raf", "rw2", "orf", "pef",
        "srw", "dng", "rwl", "3fr", "fff", "iiq", "x3f",
    ]

    /// Raster fallback decodable through `RAWDecoder`'s raster path.
    static let rasterExtensions: Set<String> = [
        "jpg", "jpeg", "tif", "tiff", "heic", "png", "webp",
    ]

    static var browsableExtensions: Set<String> {
        rawExtensions.union(rasterExtensions)
    }

    // MARK: - Exclusion predicates (SINGLE SOURCE — the 9-2 watcher reuses)

    /// Files excluded from the browse set wherever they appear.
    static func isExcludedFile(_ name: String) -> Bool {
        isExcludedMetadata(name) || name.hasSuffix(".lra")  // sidecars are attachments
    }

    /// The NOISE half of the file exclude table (dotfiles + SidecarStore
    /// residue, `*.tmp-*` promotion residue, C1 `*.cosessiondb` artifacts).
    ///
    /// Plan 09-02: this is ALSO the watcher's file predicate — `.lra`
    /// events must NOT be dropped there, because an EXTERNAL sidecar write
    /// is a legitimate reconcile signal (sidecar drift re-read), while the
    /// SELF-written sidecars are swallowed by the write journal instead
    /// (the double defense; 09-02 T3). Internal (not private): the T3
    /// single-source assertion pins watcher == this predicate by value.
    static func isWatcherExcludedFile(_ name: String) -> Bool {
        isExcludedMetadata(name)
    }

    static func isExcludedMetadata(_ name: String) -> Bool {
        name.hasPrefix(".")                    // dotfiles + SidecarStore residue
            || name.contains(".tmp-")          // `*.tmp-*` promotion residue
            || name.hasSuffix(".cosessiondb")  // C1 artifacts — read-only
    }

    /// Directories excluded from BOTH the browse set and DESCENT.
    /// `isDirectlyUnderRoot` gates the reserved three tiers to the root
    /// level only (nested same-name user folders stay browsable).
    static func isExcludedDirectory(
        _ name: String, isDirectlyUnderRoot: Bool
    ) -> Bool {
        name.hasPrefix(".")
            || name.contains(".tmp-")
            || (isDirectlyUnderRoot
                && SessionLayout.reservedRootDirectoryNames.contains(name))
    }

    /// Browse-set membership by extension.
    static func isBrowsableFile(_ name: String) -> Bool {
        guard let ext = name.split(separator: ".").last else { return false }
        return browsableExtensions.contains(ext.lowercased())
    }

    // MARK: - Walk

    /// Stream the tree page by page. The stream finishes when the walk
    /// finishes; errors (unreadable dirs) are logged and skipped — a scan
    /// NEVER throws the whole session open away (SC#2 gracefully).
    static func scan(root: URL) -> AsyncStream<SessionScanPage> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var page = SessionScanPage()
                var orphanPage = SessionScanPage()

                func flush() {
                    if !page.isEmpty {
                        continuation.yield(page)
                        page = SessionScanPage()
                    }
                    if !orphanPage.isEmpty {
                        continuation.yield(orphanPage)
                        orphanPage = SessionScanPage()
                    }
                }

                let fileManager = FileManager.default
                // REL-PATH MATH: the enumerator hands back child paths in
                // the SYMLINK-RESOLVED spelling (it realpath's the root:
                // /var → /private/var on macOS) while URL.path keeps the
                // /var prefix — and Foundation's own
                // resolvingSymlinksInPath does NOT resolve the prefix link.
                // Compute the physical prefix once with realpath(3) and
                // match BOTH spellings.
                let physicalRootPath: String = {
                    // withCString — a caller-owned buffer scope; the
                    // fileSystemRepresentation(withPath:) buffer must NOT
                    // be handed to free/deallocate (heap corruption).
                    root.path.withCString { cpath -> String in
                        var buf = [CChar](repeating: 0, count: 4096)
                        if realpath(cpath, &buf) != nil {
                            return String(cString: buf)
                        }
                        return root.path
                    }
                }()
                let rootPrefixes = Array(Set([
                    physicalRootPath + "/",
                    root.path + "/",
                ]))
                func relPath(of url: URL) -> String {
                    let path = url.path
                    for prefix in rootPrefixes
                    where path.hasPrefix(prefix) && path.count > prefix.count {
                        return String(path.dropFirst(prefix.count))
                    }
                    return url.lastPathComponent // defensive fallback
                }
                let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
                    ],
                    options: [],
                    errorHandler: { url, error in
                        logger.error(
                            "scan skip \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                        return true // keep walking (graceful)
                    }
                )

                if let enumerator {
                    // `while nextObject()` — NSDirectoryEnumerator's
                    // `makeIterator` is unavailable from async contexts.
                    while let url = enumerator.nextObject() as? URL {
                        if relPath(of: url).isEmpty {
                            continue // defensive: some Foundation versions yield the base
                        }
                        let name = url.lastPathComponent
                        let values = try? url.resourceValues(
                            forKeys: [
                                .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
                            ]
                        )
                        let isDirectory = values?.isDirectory ?? false

                        if isDirectory {
                            // Directly under root = the dir's OWN relPath
                            // carries no further "/" segment.
                            let directlyUnderRoot = !relPath(of: url).contains("/")
                            if isExcludedDirectory(
                                name, isDirectlyUnderRoot: directlyUnderRoot
                            ) {
                                enumerator.skipDescendants()
                            }
                            continue
                        }

                        if isExcludedFile(name) {
                            if name.hasSuffix(".lra") {
                                // Orphan classification: the sidecar's
                                // original is GONE from disk (existence
                                // check — independent of scan completeness).
                                let original = LightamerSidecar.imageURL(for: url)
                                if let original,
                                   !fileManager.fileExists(atPath: original.path) {
                                    let rel = relPath(of: url)
                                    orphanPage.orphanSidecarRelPaths.append(rel)
                                    if orphanPage.orphanSidecarRelPaths.count >= pageSize {
                                        flush()
                                    }
                                }
                            }
                            continue
                        }

                        guard isBrowsableFile(name) else { continue }

                        let rel = relPath(of: url)
                        page.entries.append(SessionScanEntry(
                            relPath: rel,
                            mtime: values?.contentModificationDate?
                                .timeIntervalSince1970 ?? 0,
                            size: Int64(values?.fileSize ?? 0)
                        ))
                        if page.entries.count >= pageSize {
                            flush()
                        }
                    }
                }
                flush()
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Collect the whole walk (tests + the T6 parity reseeds).
    static func collect(
        root: URL
    ) async -> (entries: [SessionScanEntry], orphans: [String]) {
        var entries: [SessionScanEntry] = []
        var orphans: [String] = []
        for await page in scan(root: root) {
            entries.append(contentsOf: page.entries)
            orphans.append(contentsOf: page.orphanSidecarRelPaths)
        }
        return (entries, orphans)
    }
}
