import Foundation
import ImageIO

// ─────────────────────────────────────────────────────────────────────────────
// XMPImport (Plan 12-3 T5, D-12-CONTEXT-2③) — the third-party `.xmp` READ
// face. READ-ONLY by construction: every entry point takes bytes and
// returns values; nothing in this file touches the source file (the red
// line — originals' `.xmp` attachments are never read/written/deleted
// automatically; THIS face runs only on a user-explicit import action,
// and even then the source file is only ever opened for reading).
//
// Mapping (RESEARCH §3.3 + the dt/Lr conventions):
// - `lr:hierarchicalSubject` Bag → full `|`-path strings, verbatim.
// - ABSENT lr → `dc:subject` Bag leaves promoted to single-level paths
//   (no ancestor information exists — the honest degradation).
// - `xmp:Rating` -1 → flag = reject (2), rating nil (XMP's reject IS
//   -1; the sidecar face separates rating and flag).
// - `xmp:Rating` 0 → nil (XMP 0 = unrated); 1...5 → verbatim.
// - `xmp:Label` → colorLabel via the writer's seven-color name table
//   (case-insensitive; unknown names never invent a colorLabel).
//
// The WRITE side of an import is MetadataService's alone (the single
// implementation — GUI and the Phase 14 tools share it); this file only
// produces the field projection the caller feeds there.
// ─────────────────────────────────────────────────────────────────────────────

public enum XMPImport {

    public enum ImportError: Error, Equatable, Sendable {
        /// The file could not be read as bytes.
        case unreadableFile(String)
        /// The bytes are not an XMP packet the host parser accepts.
        case unparsableXMP
        /// The packet parses but carries none of the importable fields.
        case noFields
    }

    /// The sidecar-field projection of one `.xmp` packet.
    public struct Fields: Equatable, Sendable {
        /// nil = no rating position (or unrated/unparseable).
        public var rating: Int?
        /// Non-nil ONLY for the Rating -1 reject convention.
        public var flag: Int?
        /// nil = no known label name in the packet.
        public var colorLabel: Int?
        /// Full `|`-path strings (lr: verbatim, or dc: leaves as
        /// single-level paths). nil = no keyword face in the packet.
        public var keywords: [String]?

        public init(
            rating: Int? = nil, flag: Int? = nil,
            colorLabel: Int? = nil, keywords: [String]? = nil
        ) {
            self.rating = rating
            self.flag = flag
            self.colorLabel = colorLabel
            self.keywords = keywords
        }

        public var isEmpty: Bool {
            rating == nil && flag == nil && colorLabel == nil && keywords == nil
        }
    }

    /// Parse an XMP packet's bytes → the importable field projection.
    public static func read(data: Data) throws -> Fields {
        guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else {
            throw ImportError.unparsableXMP
        }
        return try read(metadata: metadata)
    }

    /// Read a third-party `.xmp` FILE (opened read-only; never written).
    public static func read(fileURL: URL) throws -> Fields {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ImportError.unreadableFile(fileURL.lastPathComponent)
        }
        return try read(data: data)
    }

    // MARK: - The field projection

    private static func read(metadata: CGImageMetadata) throws -> Fields {
        var fields = Fields()

        if let raw = CGImageMetadataCopyStringValueWithPath(
            metadata, nil, "xmp:Rating" as CFString) as String?,
            let value = Int(raw.trimmingCharacters(in: .whitespaces)) {
            switch value {
            case -1:
                fields.flag = 2 // reject — the XMP convention
            case 1...5:
                fields.rating = value
            default:
                break // 0 = unrated; anything else is out of convention
            }
        }

        if let label = CGImageMetadataCopyStringValueWithPath(
            metadata, nil, "xmp:Label" as CFString) as String? {
            fields.colorLabel = XMPWriter.colorLabel(forName: label)
        }

        let hierarchical = arrayValue(metadata, "lr:hierarchicalSubject")
        if !hierarchical.isEmpty {
            fields.keywords = hierarchical
        } else {
            // Only dc:subject? The honest degradation: the leaves ARE the
            // single-level paths (no ancestor information exists).
            let leaves = arrayValue(metadata, "dc:subject")
            if !leaves.isEmpty {
                fields.keywords = leaves
            }
        }

        guard !fields.isEmpty else { throw ImportError.noFields }
        return fields
    }

    /// Bag read: on REPARSE the elements arrive as nested
    /// `CGImageMetadataTag`s wrapping strings (the write-side probe's
    /// mirror); a defensive plain-String branch rides along.
    private static func arrayValue(
        _ metadata: CGImageMetadata, _ path: String
    ) -> [String] {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString),
            let value = CGImageMetadataTagCopyValue(tag) as? [Any]
        else { return [] }
        return value.compactMap { element in
            if let string = element as? String { return string }
            // The element is a nested CGImageMetadataTag (CFTypeRef) — the
            // plain-String branch above is the defensive alternative.
            let nested = element as! CGImageMetadataTag
            return CGImageMetadataTagCopyValue(nested) as? String
        }
    }
}
