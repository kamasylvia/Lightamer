import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailDiskStore (Plan 09-03 T2) — the browser-thumbnail DISK tier,
// the AUTHORITATIVE thumbnail cache (RESEARCH §5.3: the memory LRU is only
// a speedup; the files survive relaunches).
//
// Location (D-09-CONTEXT-2): `<sessionRoot>/.lightamer/thumbs/<pathhash>.jpg`
// — inside the session's derived-cache directory, so "delete = rebuild" and
// the folder moves WITH the session (a stale absolute `thumb_path` after a
// move just misses and regenerates — the index is a rebuildable cache).
//
// Format (execution decision D4): JPEG quality 85 — the RESEARCH plan-phase
// default. ~30–60 KB per 360px thumb → 10k ≈ 0.5 GB ceiling (budget note
// lands in .work/09/perf.md). HEIC recorded as deferred (09-CONTEXT).
//
// Writes are atomic (same-directory tmp + rename — L009: never /tmp across
// volumes). The path hash is `ThumbnailPath.hash` (FNV-1a 64 hex — the one
// naming source shared with the cell identifiers).
// ─────────────────────────────────────────────────────────────────────────────

public struct ThumbnailDiskStore: Sendable {

    /// The thumbs directory (`.lightamer/thumbs` under the session root).
    public let directory: URL

    /// JPEG compression quality (execution decision D4).
    public static let jpegQuality: Double = 0.85

    public init(sessionRoot: URL) {
        self.directory = sessionRoot
            .appendingPathComponent(SessionIndexSchema.derivedCacheDirectoryName, isDirectory: true)
            .appendingPathComponent(ThumbnailPath.thumbnailsDirectoryName, isDirectory: true)
    }

    /// Test seam: an explicit directory (SSD temp fixtures).
    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Paths

    /// The file URL for a browse relPath (`<pathhash>.jpg`).
    public func fileURL(forRelPath relPath: String) -> URL {
        directory.appendingPathComponent(ThumbnailPath.fileName(relPath))
    }

    // MARK: - Write

    /// Encode + atomically write the thumbnail. Returns the written file
    /// URL (the index row's `thumb_path`). Throws on encode/IO failure —
    /// the caller logs; a missing thumb is a regenerable miss, never fatal.
    @discardableResult
    public func write(_ image: CGImage, relPath: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(forRelPath: relPath)
        let data = try Self.jpegData(from: image)
        // Atomic promotion in the SAME directory (L009): tmp sibling + rename.
        let tmp = directory.appendingPathComponent(
            ".tmp-\(UUID().uuidString)-\(url.lastPathComponent)"
        )
        try data.write(to: tmp)
        // Rename over any existing thumb (idempotent regeneration).
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        return url
    }

    // MARK: - Read

    /// Decode the cached JPEG. nil = miss (or a corrupt file — treated as
    /// a miss; the next generation overwrites it).
    public func read(relPath: String) -> CGImage? {
        let url = fileURL(forRelPath: relPath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Whether the cached file exists (a cheap probe before decode).
    public func exists(relPath: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(forRelPath: relPath).path)
    }

    // MARK: - Removal (9-1 removed-leg hookup + teardown)

    /// Drop one thumb file (row removed — the sync's cleanupThumbFiles owns
    /// the DB-driven leg; this is the provider-side regeneration path).
    public func remove(relPath: String) {
        try? FileManager.default.removeItem(at: fileURL(forRelPath: relPath))
    }

    /// Drop the WHOLE cache (manual rebuild semantics — D-09-CONTEXT-2:
    /// deleting `.lightamer/` loses nothing but regenerable files).
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Introspection (budget estimates → perf.md)

    /// Cached-file count + total bytes (the 0.5 GB/10k budget note).
    public func stats() -> (files: Int, bytes: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return (0, 0) }
        var files = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            ), values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (files, bytes)
    }

    // MARK: - JPEG encode

    /// Encode a CGImage as JPEG q85 (`kCGImageDestinationLossyCompressionQuality`).
    public static func jpegData(from image: CGImage) throws -> Data {
        let mutable = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                mutable, UTType.jpeg.identifier as CFString, 1, nil
            )
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "CGImageDestinationCreateWithData(jpeg) failed",
            ])
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed",
            ])
        }
        return mutable as Data
    }
}
