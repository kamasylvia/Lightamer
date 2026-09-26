import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ExportNamer — the D-11-CONTEXT-4 output naming + collision-increment PURE
// functions (Plan 11-01 T2).
//
// Shape: `<stem>[_<tag>].<ext>`; a name collision increments `-1/-2/...`
// before the extension. PURE — nothing here touches the filesystem: the
// caller supplies the set of names ALREADY OCCUPIED in the target directory
// (the 11-04 queue wiring enumerates it; EXP-08's default landing zone is
// `SessionLayout.outputDirectory(for:)` — the 9-1 takeover constant, wired
// App-side in 11-04 per D-11-CONTEXT-4 "恒落 Session/Output/".
// ─────────────────────────────────────────────────────────────────────────────

public enum ExportNamer {

    /// Characters macOS filenames cannot carry. APFS itself only forbids
    /// `/` (the path separator) and, for legacy HFS interop, `:` — both are
    /// replaced rather than rejected so a weird stem still exports.
    private static let illegalCharacters = CharacterSet(charactersIn: "/:")

    /// The conservative stem policy (execution decision, 11-01-DECISIONS D6):
    /// REPLACE `/` and `:` with `-`, trim surrounding whitespace, fall back
    /// to `Untitled` when nothing survives (empty, whitespace-only, or a
    /// stem that was ONLY illegal characters → all dashes) — everything else
    /// (Unicode, spaces, dots, emoji) passes through untouched. No
    /// aggressive transliteration: a Chinese/emoji stem is a legal APFS name.
    public static func sanitizedStem(_ stem: String) -> String {
        let replaced = stem.components(separatedBy: illegalCharacters)
            .joined(separator: "-")
        let trimmed = replaced.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.allSatisfy({ $0 == "-" }) else {
            return "Untitled"
        }
        return trimmed
    }

    /// Sanitize a user-supplied tag the same way (an explicit `outputTag`
    /// can carry `/`; derived tags are digits/letters and pass unchanged).
    /// A result that is empty, the `Untitled` fallback, or all dashes (the
    /// tag was ONLY illegal characters) counts as absent → `nil`.
    public static func sanitizedTag(_ tag: String?) -> String? {
        guard let tag else { return nil }
        let cleaned = sanitizedStem(tag)
        guard cleaned != "Untitled", !cleaned.allSatisfy({ $0 == "-" }) else {
            return nil
        }
        return cleaned
    }

    /// The D-11-CONTEXT-4 resolution: `<stem>[_<tag>].<ext>`, and when that
    /// name (or any `-N` candidate) is already occupied in the target
    /// directory, the first free `-1/-2/-3...` increment wins.
    ///
    /// Occupancy is compared CASE-INSENSITIVELY (execution decision D7 — the
    /// default APFS volume is case-insensitive; a `Photo.JPG` on disk must
    /// block a `photo.jpg` candidate or the encoder overwrites it).
    ///
    /// - Parameters:
    ///   - directory: the destination folder, joined verbatim (no existence
    ///     check — the caller owns landing-zone decisions, EXP-08).
    ///   - stem: the source image stem (`sanitizedStem` applied here).
    ///   - tag: the variant tag (`sanitizedTag` applied here; `nil` → bare
    ///     `<stem>.<ext>`).
    ///   - ext: the format extension, already lowercase
    ///     (`ExportFormatSpec.fileExtension`).
    ///   - occupiedNames: file NAMES (not paths) already present in the
    ///     target directory.
    /// - Returns: the collision-free destination URL. Never touches disk.
    public static func destinationURL(
        directory: URL,
        stem: String,
        tag: String?,
        ext: String,
        occupiedNames: Set<String>
    ) -> URL {
        let cleanStem = sanitizedStem(stem)
        let cleanTag = sanitizedTag(tag)
        let prefix = cleanTag.map { "\(cleanStem)_\($0)" } ?? cleanStem
        let occupiedLower = Set(occupiedNames.map { $0.lowercased() })

        func candidate(_ suffix: String) -> String {
            "\(prefix)\(suffix).\(ext)".lowercased()
        }

        var chosen: String
        if !occupiedLower.contains(candidate("")) {
            chosen = "\(prefix).\(ext)"
        } else {
            var n = 1
            while occupiedLower.contains(candidate("-\(n)")) { n += 1 }
            chosen = "\(prefix)-\(n).\(ext)"
        }
        return directory.appendingPathComponent(chosen, isDirectory: false)
    }
}
