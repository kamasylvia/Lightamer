import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailPath (Plan 09-03 T1) — the SINGLE SOURCE for thumbnail file
// naming and the stable cell identifier suffix.
//
// Execution decision (09-03-DECISIONS D3): the path hash is FNV-1a 64 over
// the relPath's UTF-8 bytes, spelled as 16 lowercase hex chars — the SAME
// StableHash primitive every other persisted identity uses (L013: stable
// across processes/launches/machines; Swift Hasher is banned). Hex (not
// decimal TEXT) here: this hash names a FILE, never rides the index as a
// numeric column, and 16 hex chars sort/uniquely identify without the
// `UInt64String` decimal discipline (which exists for JSON-number precision
// loss — a filename has no such consumer).
//
// Consumers: `ThumbnailDiskStore` (the `<pathhash>.jpg` file name) and the
// browser cell identifier `browser.cell.<pathhash>` (L010 stable id).
// ─────────────────────────────────────────────────────────────────────────────

public enum ThumbnailPath {

    /// The derived-cache directory name (D-09-CONTEXT-2: inside the
    /// session's `.lightamer/`).
    public static let thumbnailsDirectoryName = "thumbs"

    /// The disk thumbnail extension (execution decision D4: JPEG q85 —
    /// RESEARCH §5.3's plan-phase default; HEIC recorded as deferred).
    public static let thumbnailFileExtension = "jpg"

    /// FNV-1a 64 over `relPath` UTF-8 → 16 lowercase hex chars.
    public static func hash(_ relPath: some StringProtocol) -> String {
        let digest = StableHash.hash(relPath)
        return String(format: "%016llx", digest)
    }

    /// The disk thumbnail file NAME for a relPath (`<pathhash>.jpg`).
    public static func fileName(_ relPath: some StringProtocol) -> String {
        hash(relPath) + "." + thumbnailFileExtension
    }
}
