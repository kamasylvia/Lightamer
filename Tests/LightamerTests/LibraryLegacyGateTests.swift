import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// LibraryLegacyGateTests (Plan M2-2-4, KD-4) — the regression-channel pins
// for the M2LIB-06 legacy-library gate.
//
//   Layer 1 (gate evaluation): the injectable three-way split over LITERAL
//   dictionaries — absent → false / "0" → false / "1" → true (KD-1: the
//   process environment is never mutated; `ProcessInfo` is touched at the
//   assembly point only).
//
//   Layer 2 (section-collection snapshots): the visible-section marker
//   mappings on SidebarView / SettingsView / ContentView against HARDCODED
//   `Set<String>` literals transcribed from the pre-M2-2-4 sources — the
//   frozen snapshot carrier (checker minor #3: never runtime-recorded, so
//   snapshot drift is impossible). gate=false must be empty of every legacy
//   marker; gate=true must equal the frozen M2-2-era sets exactly (the
//   opt-back channel reproduces the old face).
//
//   Layer 3 (existing model tests untouched & green) is carried by the
//   whole suite: CatalogBrowserModelTests / CatalogModeIsolationTests /
//   Session-family tests run UNCHANGED (KD-4 machine proof that the gate
//   only narrowed the UI presentation layer).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class LibraryLegacyGateTests: XCTestCase {

    // MARK: - KD-4 layer 1: the injectable three-way evaluation

    func testGateEvaluationThreeWayOverLiteralDictionaries() {
        // Absent → false (the product default: legacy face hidden).
        XCTAssertFalse(
            LibraryLegacyGate.isLegacyLibraryRequested(environment: [:]),
            "no key = the narrowed project-first face (OQ-8 default)")
        // "0" → false (explicitly off).
        XCTAssertFalse(
            LibraryLegacyGate.isLegacyLibraryRequested(environment: [
                LibraryLegacyGate.environmentKey: "0",
            ]),
            "the \"0\" spelling stays on the narrowed face")
        // "1" → true (the QA/regression opt-back).
        XCTAssertTrue(
            LibraryLegacyGate.isLegacyLibraryRequested(environment: [
                LibraryLegacyGate.environmentKey: "1",
            ]),
            "the \"1\" spelling is the ONLY opt-back")
    }

    func testGateRejectsEveryNonOneSpelling() {
        for spelling in ["", "true", "yes", "2", "1 ", " 1", "on"] {
            XCTAssertFalse(
                LibraryLegacyGate.isLegacyLibraryRequested(environment: [
                    LibraryLegacyGate.environmentKey: spelling,
                ]),
                "spelling \(spelling.debugDescription) must not opt back")
        }
    }

    // MARK: - KD-4 layer 2: the sidebar section-collection snapshots

    /// The frozen M2-2-era Sessions-family markers (transcribed from the
    /// pre-M2-2-4 SidebarView: the current-session section presents
    /// `session.current` populated / `session.open` empty; the watch status
    /// line and the smart-album add control are always present; recent rows
    /// are data-dependent and ride the same branch).
    private static let frozenSessionFamily: Set<String> = [
        "session.current",
        "session.open",
        "session.watch",
        "smartalbum.add",
    ]

    /// The frozen M2-2-era Catalogs-family markers (the always-present
    /// all/add controls of the three structural sections; the smart-album
    /// and sessions-从属 rows ride the same branch).
    private static let frozenCatalogFamily: Set<String> = [
        "catalog.section.all",
        "catalog.category.add",
        "catalog.collection.add",
    ]

    private static let frozenModeSwitcher: Set<String> = ["organization.mode"]

    /// All legacy sidebar identifiers — the family union the default face
    /// must be disjoint from.
    private static let allLegacySidebarMarkers: Set<String> =
        frozenSessionFamily.union(frozenCatalogFamily).union(frozenModeSwitcher)

    func testDefaultSidebarFaceHidesEveryLegacySectionMarker() {
        // The full org/enable matrix — gate false hides the switcher and
        // BOTH families regardless of the persisted preference state.
        for catalogsEnabled in [false, true] {
            for mode in [CatalogPreferencesModel.OrganizationMode.sessions,
                         .catalogs] {
                let markers = SidebarView.visibleSidebarSectionMarkers(
                    legacyLibraryEnabled: false,
                    catalogsEnabled: catalogsEnabled,
                    organizationMode: mode)
                XCTAssertTrue(
                    markers.isEmpty,
                    "gate false renders no legacy section (state "
                        + "catalogsEnabled=\(catalogsEnabled) mode=\(mode))")
                XCTAssertFalse(
                    markers.contains("Sessions"),
                    "the List CONTAINER id stays byte-identical but no "
                        + "legacy section marker may leak")
                XCTAssertTrue(
                    markers.isDisjoint(with: Self.allLegacySidebarMarkers),
                    "default face ∩ legacy family = ∅")
            }
        }
    }

    func testGateOnSidebarSessionsFaceMatchesFrozenSnapshot() {
        // The M2-2 default state: Catalogs disabled → sessions face, no
        // switcher (D-16-CONTEXT-5①: the switcher exists ONLY while
        // Catalogs is enabled).
        XCTAssertEqual(
            SidebarView.visibleSidebarSectionMarkers(
                legacyLibraryEnabled: true,
                catalogsEnabled: false,
                organizationMode: .sessions),
            Self.frozenSessionFamily,
            "env=1 must reproduce the M2-2 sessions face exactly")
    }

    func testGateOnSidebarSessionsModeWithCatalogsEnabledAddsSwitcher() {
        XCTAssertEqual(
            SidebarView.visibleSidebarSectionMarkers(
                legacyLibraryEnabled: true,
                catalogsEnabled: true,
                organizationMode: .sessions),
            Self.frozenSessionFamily.union(Self.frozenModeSwitcher),
            "catalogs-enabled sessions mode = sessions face + the switcher")
    }

    func testGateOnSidebarCatalogsFaceMatchesFrozenSnapshot() {
        XCTAssertEqual(
            SidebarView.visibleSidebarSectionMarkers(
                legacyLibraryEnabled: true,
                catalogsEnabled: true,
                organizationMode: .catalogs),
            Self.frozenCatalogFamily.union(Self.frozenModeSwitcher),
            "env=1 must reproduce the M2-2 catalogs face exactly")
        let markers = SidebarView.visibleSidebarSectionMarkers(
            legacyLibraryEnabled: true,
            catalogsEnabled: true,
            organizationMode: .catalogs)
        XCTAssertTrue(
            markers.isDisjoint(with: Self.frozenSessionFamily),
            "the catalogs mode never shows the sessions family (16-2 "
                + "isolation, unchanged)")
    }

    // MARK: - KD-4 layer 2: the Settings catalog-section snapshot

    /// The frozen M2-2-era Settings catalog markers (the enable toggle,
    /// the location rows, and the two state-conditional rebuild rows at
    /// family granularity — schema-failed label + destructive recovery).
    private static let frozenSettingsCatalogMarkers: Set<String> = [
        "settings.catalogs.enable",
        "settings.catalogs.path",
        "settings.catalogs.existence",
        "settings.catalogs.change_location",
        "settings.catalogs.schema_failed",
        "settings.catalogs.rebuild_destructive",
        "settings.catalogs.rebuild_reconcile",
    ]

    func testDefaultSettingsFaceHidesTheCatalogSections() {
        let markers = SettingsView.visibleCatalogSectionMarkers(
            legacyLibraryEnabled: false)
        XCTAssertTrue(markers.isEmpty, "no catalog row renders by default")
        // OQ-8: NO new legacy-library switch exists either — the default
        // face carries none of the catalog keys AND the gate adds no new
        // toggle identifier anywhere.
        XCTAssertFalse(
            markers.contains("settings.legacy.library"),
            "the Settings page gains no legacy-library switch (OQ-8)")
    }

    func testGateOnSettingsFaceMatchesFrozenSnapshot() {
        XCTAssertEqual(
            SettingsView.visibleCatalogSectionMarkers(
                legacyLibraryEnabled: true),
            Self.frozenSettingsCatalogMarkers,
            "env=1 must reproduce the M2-2 Settings catalog rows exactly")
    }

    // The ContentView content-face dual-state snapshot (KD-4 layer 2) lands
    // with the T2 project-first startup face — see
    // testContentViewMarkersAreDisjointAcrossTheGate appended below in that
    // task's commit.
}
