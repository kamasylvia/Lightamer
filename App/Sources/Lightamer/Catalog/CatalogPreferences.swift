import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// CatalogPreferencesModel (Plan 16-2 T1) — the UI-side preferences face over
// the 16-1 enable key + the catalog LOCATION preference.
//
// KEY DISCIPLINE (single spelling): the enable flag rides the CORE
// `CatalogPreferences` statics (CatalogProjector.swift — the projector's
// guard reads the SAME key); this model never re-spells the key literal, it
// writes THROUGH the Core face so the guard and the UI can never diverge.
//
// LOCATION (RQ-16-1②): re-point, NEVER migrate — the outgoing handles close,
// the preference lands, and the NEXT open creates an empty library at the
// new path when missing. The stored value is the catalog DIRECTORY (the
// NSOpenPanel face is a directory picker per the plan); the database file
// keeps the frozen `CatalogIndexSchema.databaseFileName` inside it. Empty =
// the schema default.
//
// ORGANIZATION MODE AXIS (RQ-16-12): org-mode (sessions | catalogs) is the
// SECOND dimension, orthogonal to the browser-mode axis (grid/single/
// culling — ContentView.BrowserMode). Cold start is ALWAYS sessions — the
// default is a CONSTANT (`coldStartRawValue`), not remembered state; the
// AppStorage write happens on the first frame (ContentView applies it).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class CatalogPreferencesModel {

    /// The location preference (the catalog DIRECTORY; empty = default).
    nonisolated static let locationStorageKey = "catalogs.databasePath"

    /// The organization-mode AppStorage key (the segmented switcher's
    /// persistence; cold start still forces sessions — see below).
    nonisolated static let organizationModeStorageKey = "organization.mode"

    /// 恒默认做成常量 (RQ-16-12): the FIRST frame always overwrites the
    /// persisted org-mode with THIS value. Tests pin it.
    nonisolated static let coldStartRawValue = OrganizationMode.sessions.rawValue

    /// The two-value organization axis.
    enum OrganizationMode: String {
        case sessions
        case catalogs
    }

    /// Suite-NAME storage (Sendable; the UserDefaults instance is built on
    /// access) — nil = `.standard`. The enable flag rides the CORE face
    /// with the SAME suite name, so a test project never touches global
    /// state and the guard/UI always agree.
    private let defaultsSuiteName: String?

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Mirrors the Core-guard key (read at init; written through Core).
    private(set) var catalogsEnabled: Bool

    /// The catalog directory path ("" = `CatalogIndexSchema` default).
    private(set) var locationPath: String

    /// App-root seams (wired once in the scene `.task`; D-03b closures).
    /// `onEnabledChanged` = the repoint/empty-library leg on enable;
    /// `onLocationChanged` = the runtime re-point leg (closes handles).
    var onEnabledChanged: ((Bool) -> Void)?
    var onLocationChanged: ((URL) -> Void)?

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
        self.catalogsEnabled = CatalogPreferences.catalogsEnabled(
            defaultsSuiteName: defaultsSuiteName)
        self.locationPath = Self.defaults(of: defaultsSuiteName).string(
            forKey: Self.locationStorageKey) ?? ""
    }

    private nonisolated static func defaults(of suiteName: String?) -> UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The resolved `.lcat` file URL for the current location preference.
    var catalogURL: URL {
        if locationPath.isEmpty {
            return CatalogIndexSchema.defaultDatabaseURL()
        }
        return URL(fileURLWithPath: locationPath, isDirectory: true)
            .appendingPathComponent(CatalogIndexSchema.databaseFileName)
    }

    var usingDefaultLocation: Bool { locationPath.isEmpty }

    /// The `.lcat` file existence face (the settings row's existence note).
    var catalogFileExists: Bool {
        FileManager.default.fileExists(atPath: catalogURL.path)
    }

    /// The enable switch (the SAME key the projector guard reads — the
    /// write goes through the Core face, never a second spelling).
    func setCatalogsEnabled(_ enabled: Bool) {
        CatalogPreferences.setCatalogsEnabled(enabled, defaultsSuiteName: defaultsSuiteName)
        catalogsEnabled = enabled
        onEnabledChanged?(enabled)
    }

    /// Re-point the catalog location (RQ-16-1②: no migration). The runtime
    /// closure fires FIRST (closes the outgoing handles), then the
    /// preference lands; the next enable/open creates the library at the
    /// new path when missing (建空库).
    func setLocation(directory: URL) {
        let standardized = directory.standardizedFileURL.path
        guard standardized != locationPath else { return }
        onLocationChanged?(URL(fileURLWithPath: standardized, isDirectory: true))
        locationPath = standardized
        defaults.set(standardized, forKey: Self.locationStorageKey)
    }

    /// Back to the schema-default location (the same no-migration flow).
    func resetLocationToDefault() {
        guard !locationPath.isEmpty else { return }
        onLocationChanged?(CatalogIndexSchema.defaultDatabaseURL().deletingLastPathComponent())
        locationPath = ""
        defaults.removeObject(forKey: Self.locationStorageKey)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CatalogSidebarSection (Plan 16-2 T2) — the Catalogs sidebar's five-section
// ORDER as a pinned constant (RQ-16-12: All Photographs / Categories /
// Collections / Smart Albums / Sessions 从属节). The categories/collections
// sections are 16-3 接线位 (this plan renders the skeleton + the empty face).
// ─────────────────────────────────────────────────────────────────────────────

enum CatalogSidebarSection: CaseIterable, Equatable {
    case allPhotographs
    case categories
    case collections
    case smartAlbums
    case sessions
}
