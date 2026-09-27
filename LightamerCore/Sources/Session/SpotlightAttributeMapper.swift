import CoreSpotlight
import Foundation
import SQLite3
import os

// ─────────────────────────────────────────────────────────────────────────────
// SpotlightAttributeMapper (Plan 13-1 T5) — the Spotlight importer's read
// seam: session-root walk-up → READ-ONLY lindex row → the STANDARD
// Spotlight attribute set (D-13-CONTEXT-3). The 34-column frozen table is
// the ONLY extraction source (the Phase 12 handover ①); custom schema /
// custom attributes are deliberately OUT (v1).
//
// THE READ-ONLY RED LINE: every open is SQLITE_OPEN_READONLY (immutable-URI
// retry after the app closes — the QuickLookRenderer posture); nothing in
// this file ever writes the lindex, a sidecar or thumbs.
//
// THE SCHEMA GATE: a stored schemaVersion > 2 (or unparsable) REFUSES the
// read — the importer registers NOTHING and Spotlight's built-in importers
// keep the file searchable with their own attributes. "Mutable and
// untrusted": every read re-derives, nothing is trusted from the row.
//
// The mapping (the EXECUTION-DECISION table, probed against the macOS 27
// CoreSpotlight surface + `mdimport -A` schema, recorded in 13-1-DECISIONS):
//
//   rating        → attributes.rating            (kMDItemStarRating; 0...5 only)
//   color_label   → attributes userTags          (kMDItemUserTags; the C1
//                    seven-color NAME set from XMPWriter.labelNames)
//   keywords      → attributes.keywords          (kMDItemKeywords; the
//                    `|`-materialized string flattened: tokens + path prefixes)
//   camera_make   → attributes.acquisitionMake   (kMDItemAcquisitionMake)
//   camera_model  → attributes.acquisitionModel  (kMDItemAcquisitionModel)
//   lens_model    → attributes.lensModel         (kMDItemLensModel)
//   capture_date  → attributes.contentCreationDate
//   iso           → attributes.isoSpeed          (kMDItemISOSpeed)
//   focal_length  → attributes.focalLength       (kMDItemFocalLength, mm)
//   aperture      → attributes.fNumber           (kMDItemFNumber — the F
//                    VALUE; kMDItemAperture is the APEX log scale and is
//                    deliberately NOT written)
//   exposure      → attributes.exposureTime      (kMDItemExposureTimeSeconds)
//
//   flag / note / layer_summary → NOT mapped (no standard seat; custom
//   schema deferred — v2 face). The projection struct simply carries no
//   such fields: the type system IS the zero-mapping proof.
// ─────────────────────────────────────────────────────────────────────────────

public enum SpotlightAttributeMapper {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "spotlight-import")

    /// The columns this importer reads — EVERY name must be a member of
    /// `SessionIndexSchema.imagesColumns` (the frozen 34-column contract;
    /// the same-batch test asserts the membership verbatim, so a read-face
    /// change cannot drift from the freeze).
    public static let projectedColumns: [String] = [
        "path", "rating", "color_label", "keywords",
        "camera_make", "camera_model", "lens_model",
        "capture_date", "iso", "focal_length", "aperture", "exposure",
    ]

    /// The row projection handed to `apply` — the v2 metadata columns ONLY
    /// (no flag / note / layer_summary: the zero-mapping proof is structural).
    public struct Projection: Sendable, Equatable {
        public var relPath: String
        public var rating: Int64?
        public var colorLabel: Int64?
        public var keywords: String?
        public var cameraMake: String?
        public var cameraModel: String?
        public var lensModel: String?
        public var captureDate: Double?
        public var iso: Int64?
        public var focalLength: Double?
        public var aperture: Double?
        public var exposure: Double?

        public init(relPath: String) {
            self.relPath = relPath
        }
    }

    // MARK: - The import entry (the appex shell calls exactly this)

    /// File URL → walk up to the nearest session root (`.lightamer/
    /// session.lindex` presence) → read-only, schema-gated row read → the
    /// projection. `nil` = register NOTHING (no session root, refused
    /// schema, or the file is not in the lindex).
    public static func projection(forFileAt url: URL) -> Projection? {
        guard var dir = directory(of: url) else { return nil }
        while true {
            let lindexURL = SessionIndexSchema.databaseURL(forSessionRoot: dir)
            if FileManager.default.fileExists(atPath: lindexURL.path) {
                let relPath = relPath(of: url, under: dir)
                guard let outcome = readProjection(lindexURL: lindexURL, relPath: relPath)
                else { return nil }
                return outcome.rowExists ? outcome.projection : nil
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    /// Project the row onto the STANDARD attribute set (every field optional:
    /// a NULL column simply writes nothing).
    public static func apply(_ projection: Projection, to attributes: CSSearchableItemAttributeSet) {
        // rating: the strict 0...5 star band (an out-of-band value — e.g. a
        // stray -1 — is NOT a star rating and must not surface as one).
        if let rating = projection.rating, (0...5).contains(rating) {
            attributes.rating = NSNumber(value: Int(rating))
        }
        if let colorLabel = projection.colorLabel,
           let name = XMPWriter.labelNames[Int(colorLabel)] {
            attributes.setValue([name], forKey: "userTags")
        }
        let keywords = spotlightKeywords(fromMaterialized: projection.keywords)
        if !keywords.isEmpty {
            attributes.keywords = keywords
        }
        if let make = projection.cameraMake {
            attributes.acquisitionMake = make
        }
        if let model = projection.cameraModel {
            attributes.acquisitionModel = model
        }
        if let lens = projection.lensModel {
            attributes.lensModel = lens
        }
        if let captureDate = projection.captureDate {
            attributes.contentCreationDate = Date(timeIntervalSince1970: captureDate)
        }
        if let iso = projection.iso {
            attributes.isoSpeed = NSNumber(value: Int(iso))
        }
        if let focalLength = projection.focalLength {
            attributes.focalLength = NSNumber(value: focalLength)
        }
        if let aperture = projection.aperture {
            attributes.fNumber = NSNumber(value: aperture)
        }
        if let exposure = projection.exposure {
            attributes.exposureTime = NSNumber(value: exposure)
        }
    }

    /// The `|`-materialized keywords → the Spotlight keyword list: the split
    /// tokens PLUS every hierarchical path prefix ("People|Alice|Studio" →
    /// People, Alice, Studio, People|Alice, People|Alice|Studio) — the same
    /// superset the catalog projector indexes, order-preserving, deduped.
    public static func spotlightKeywords(fromMaterialized materialized: String?) -> [String] {
        guard let materialized, !materialized.isEmpty else { return [] }
        let tokens = materialized
            .split(separator: "|", omittingEmptySubsequences: true)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }
        var result: [String] = []
        func append(_ value: String) {
            if !result.contains(value) { result.append(value) }
        }
        tokens.forEach(append)
        for i in 1...tokens.count {
            append(tokens[0..<i].joined(separator: "|"))
        }
        return result
    }

    // MARK: - The read-only row read

    struct ReadOutcome {
        var projection: Projection
        var rowExists: Bool
    }

    /// Read-only + schema-gated; the immutable-URI retry mirrors
    /// `QuickLookRenderer` (the app-closed WAL reality). `nil` = refused
    /// (open failure / future schema / unparsable version).
    static func readProjection(lindexURL: URL, relPath: String) -> ReadOutcome? {
        if let outcome = readProjectionRow(path: lindexURL.path, flags: SQLiteHandle.readOnlyFlags, relPath: relPath) {
            return outcome
        }
        let encodedPath = lindexURL.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? lindexURL.path
        return readProjectionRow(
            path: "file://" + encodedPath + "?immutable=1",
            flags: immutableReadFlags, relPath: relPath)
    }

    private static let immutableReadFlags =
        SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX

    private static func readProjectionRow(path: String, flags: Int32, relPath: String)
        -> ReadOutcome?
    {
        guard let handle = try? SQLiteHandle(path: path, flags: flags) else {
            return nil
        }
        defer { handle.close() }
        do {
            // The schema gate — refuse a FUTURE or unparsable version.
            let versionStatement = try handle.prepare(
                "SELECT value FROM meta WHERE key = ?")
            try versionStatement.bindText(1, SessionIndexSchema.MetaKey.schemaVersion)
            guard try versionStatement.step(),
                  let stored = versionStatement.columnText(0),
                  let version = Int(stored),
                  version <= SessionIndexSchema.schemaVersion else {
                logger.info(
                    "spotlight import: lindex schema refused (not readable as v\(SessionIndexSchema.schemaVersion)) for \(relPath, privacy: .public)")
                return nil
            }

            let sql = "SELECT \(projectedColumns.dropFirst().joined(separator: ", ")) "
                + "FROM images WHERE path = ?"
            let statement = try handle.prepare(sql)
            try statement.bindText(1, relPath)
            let projection = Projection(relPath: relPath)
            guard try statement.step() else {
                return ReadOutcome(projection: projection, rowExists: false)
            }
            var outcome = ReadOutcome(projection: projection, rowExists: true)
            outcome.projection.rating = statement.columnInt(0)
            outcome.projection.colorLabel = statement.columnInt(1)
            outcome.projection.keywords = statement.columnText(2)
            outcome.projection.cameraMake = statement.columnText(3)
            outcome.projection.cameraModel = statement.columnText(4)
            outcome.projection.lensModel = statement.columnText(5)
            outcome.projection.captureDate = statement.columnDouble(6)
            outcome.projection.iso = statement.columnInt(7)
            outcome.projection.focalLength = statement.columnDouble(8)
            outcome.projection.aperture = statement.columnDouble(9)
            outcome.projection.exposure = statement.columnDouble(10)
            return outcome
        } catch {
            logger.info(
                "spotlight import: row read degraded for \(relPath, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Path helpers (the QuickLookRenderer twins)

    private static func directory(of url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? url.standardized : url.deletingLastPathComponent().standardized
    }

    /// POSIX rel-path of `url` under `root` (the lindex `path` column's
    /// spelling — rel TO the session root; SessionIndexStore.swift:29-31).
    private static func relPath(of url: URL, under root: URL) -> String {
        let urlPath = url.standardized.path
        let rootPath = root.standardized.path
        if urlPath.hasPrefix(rootPath + "/") {
            return String(urlPath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }
}
