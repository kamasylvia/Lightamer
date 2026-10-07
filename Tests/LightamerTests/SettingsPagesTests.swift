import LightamerCore
import LightamerIOP
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// SettingsPagesTests (Plan M2-3-3 T5, KD-5) — the Settings ten-entry
// navigation:
//
//   1. THE PAGE SET: `SettingsPage.navigationPages` == exactly the ten D7
//      ids in order; Acceleration/Updates are NEGATIVES (absent from every
//      face); Catalogs is a real case but OUTSIDE the ten.
//   2. THE GATE FACE: `displayedPages(legacyLibraryEnabled:)` two states —
//      gate=false → the ten, gate=true → the ten + Catalogs last.
//   3. DEFAULT BEHAVIOR: the mask-draw three-choice round-trips through an
//      isolated defaults suite; default = ask; reset returns to ask.
//   4. KEYBOARD: the default keymap is conflict-free over the full
//      MenuCommandID set, specific combos are pinned against the menu
//      declarations, and the pure detector catches a synthetic collision
//      pair while reporting zero on clean input.
//   5. IMPORT DEFAULTS: the three-key binding face — mode/remember
//      write-read round-trip, the whitelist replacement face, and reset
//      restoring every default (all on an isolated suite).
// ─────────────────────────────────────────────────────────────────────────────

final class SettingsPagesTests: XCTestCase {

    private var suiteName: String { "test.settingspages.\(UUID().uuidString)" }

    private func withSuite(_ body: (String) -> Void) {
        let name = suiteName
        body(name)
        UserDefaults().removePersistentDomain(forName: name)
    }

    // MARK: - 1: the page set

    func testNavigationPagesAreExactlyTheTenD7Ids() {
        let expected = [
            "languageTheme", "defaultBehavior", "cache",
            "localContentRecognition", "advancedContentAnalysis",
            "keyboard", "about", "importDefaults", "displays", "mcp",
        ]
        XCTAssertEqual(
            SettingsPage.navigationPages.map(\.rawValue), expected,
            "the ten-page set is the D7 assertion surface (order = list order)")
        // The negatives (D7 cut).
        XCTAssertFalse(
            SettingsPage.allCases.map(\.rawValue).contains("acceleration"),
            "Acceleration was cut by D7 — it must not exist as a page id")
        XCTAssertFalse(
            SettingsPage.allCases.map(\.rawValue).contains("updates"),
            "Updates was cut by D7 — it must not exist as a page id")
        // Catalogs is reachable but NOT one of the ten.
        XCTAssertEqual(SettingsPage.allCases.count, 11)
        XCTAssertFalse(SettingsPage.navigationPages.contains(.catalogs))
    }

    // MARK: - 2: the gate face

    func testDisplayedPagesGateTwoStates() {
        let plain = SettingsPage.displayedPages(legacyLibraryEnabled: false)
        XCTAssertEqual(plain.count, 10)
        XCTAssertFalse(plain.contains(.catalogs))

        let gated = SettingsPage.displayedPages(legacyLibraryEnabled: true)
        XCTAssertEqual(gated.count, 11)
        XCTAssertEqual(gated.last, .catalogs, "Catalogs appends last on the gate")
        XCTAssertEqual(
            gated.dropLast(), plain,
            "the gated list is exactly the ten-page list + Catalogs")
    }

    // MARK: - 3: Default Behavior (mask draw)

    func testMaskDrawBehaviorRoundTripAndReset() {
        withSuite { suite in
            let preferences = AppPreferences(defaultsSuiteName: suite)
            // Default = ask.
            XCTAssertEqual(preferences.maskDrawBehavior, .ask)
            // Round-trip every case.
            for behavior in MaskDrawBehavior.allCases {
                preferences.maskDrawBehavior = behavior
                XCTAssertEqual(preferences.maskDrawBehavior, behavior)
            }
            // Reset returns to ask.
            preferences.maskDrawBehavior = .currentNode
            preferences.resetMaskDrawBehavior()
            XCTAssertEqual(preferences.maskDrawBehavior, .ask)
        }
    }

    func testMaskBehaviorKeyIsTheRegisteredSpelling() {
        withSuite { suite in
            let preferences = AppPreferences(defaultsSuiteName: suite)
            preferences.maskDrawBehavior = .newLayer
            XCTAssertEqual(
                UserDefaults(suiteName: suite)?
                    .string(forKey: AppPreferences.maskBehaviorKey),
                MaskDrawBehavior.newLayer.rawValue,
                "the key hosts the raw value directly (M2-7 reads the same spelling)")
        }
    }

    // MARK: - 4: Keyboard keymap + conflicts

    func testDefaultKeymapCoversEveryCommandAndPinsTheMenu() {
        // Every command id has a table entry (combo or honest nil).
        for id in MenuCommandID.allCases {
            _ = DefaultKeymap.combo(for: id)
        }
        // Pins against the LightamerApp CommandMenus declarations.
        XCTAssertEqual(
            DefaultKeymap.combo(for: .projectNew), SettingsKeyCombo("n", command: true))
        XCTAssertEqual(
            DefaultKeymap.combo(for: .projectOpen),
            SettingsKeyCombo("o", command: true, option: true))
        XCTAssertEqual(
            DefaultKeymap.combo(for: .projectImportFolder),
            SettingsKeyCombo("i", command: true, shift: true))
        XCTAssertEqual(
            DefaultKeymap.combo(for: .workspaceEnterEditor),
            SettingsKeyCombo("e", command: true))
        XCTAssertEqual(
            DefaultKeymap.combo(for: .workspaceBackToLibrary),
            SettingsKeyCombo("w", command: true))
        XCTAssertEqual(
            DefaultKeymap.combo(for: .librarySearch),
            SettingsKeyCombo("f", command: true))
        // The shell toggles and the dead import route declare no shortcut.
        XCTAssertNil(DefaultKeymap.combo(for: .viewToolRail))
        XCTAssertNil(DefaultKeymap.combo(for: .viewScopes))
        XCTAssertNil(DefaultKeymap.combo(for: .viewAdjustmentStack))
        XCTAssertNil(DefaultKeymap.combo(for: .sessionImport))
    }

    func testDefaultKeymapIsConflictFree() {
        let entries = MenuCommandID.allCases.map { id in
            (id: id, combo: DefaultKeymap.combo(for: id))
        }
        XCTAssertTrue(
            KeyboardConflictDetector.conflicts(entries).isEmpty,
            "the default keymap mirrors a menu that compiles today — zero conflicts")
    }

    func testConflictDetectorCatchesACollisionPairAndIgnoresNil() {
        // The synthetic collision: two commands on ⌘W (exactly the kind the
        // M2-x rebinding work must flag).
        let collision: [(id: MenuCommandID, combo: SettingsKeyCombo?)] = [
            (.workspaceBackToLibrary, SettingsKeyCombo("w", command: true)),
            (.sessionClose, SettingsKeyCombo("W", command: true)), // case-normalized
            (.projectNew, SettingsKeyCombo("n", command: true)),
            (.viewToolRail, nil), // unbound rows never conflict
        ]
        let conflicts = KeyboardConflictDetector.conflicts(collision)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(
            Set(conflicts.values.first ?? []),
            [.workspaceBackToLibrary, .sessionClose],
            "the case-differing spellings are ONE physical binding — both ids flagged")
    }

    func testKeyboardOverrideStoreRoundTripAndRestore() {
        withSuite { suite in
            let preferences = AppPreferences(defaultsSuiteName: suite)
            // v1 ships no overrides.
            XCTAssertFalse(preferences.hasKeyboardOverrides)
            // The store face round-trips (the M2-x rebinding contract).
            preferences.setKeyboardOverride(
                SettingsKeyCombo("k", command: true, shift: true),
                for: .librarySearch)
            XCTAssertEqual(
                preferences.keyboardOverride(for: .librarySearch),
                SettingsKeyCombo("k", command: true, shift: true))
            XCTAssertTrue(preferences.hasKeyboardOverrides)
            // The restore face clears the family.
            preferences.resetKeyboardOverrides()
            XCTAssertNil(preferences.keyboardOverride(for: .librarySearch))
            XCTAssertFalse(preferences.hasKeyboardOverrides)
        }
    }

    // MARK: - 5: Import Defaults (the Core three-key face)

    func testImportDefaultsWriteReadAndReset() {
        withSuite { suite in
            let defaults = ImportDefaults(defaultsSuiteName: suite)
            // Fresh face: copy / no-remember / frozen whitelist.
            XCTAssertEqual(defaults.resolvedMode(), .copy)
            XCTAssertFalse(defaults.rememberMode)
            let frozen = LibrarySchema.defaultRawExtensions

            // Write-read: a remembered move choice.
            defaults.storeChoice(ImportModeChoice(mode: .move, remember: true))
            XCTAssertEqual(defaults.resolvedMode(), .move)
            XCTAssertTrue(defaults.rememberMode)

            // The single-shot contract: remember=false drops a stale mode.
            defaults.storeChoice(ImportModeChoice(mode: .link, remember: false))
            XCTAssertEqual(defaults.resolvedMode(), .copy)
            XCTAssertFalse(defaults.rememberMode)

            // The whitelist replacement face (replace-never-union,
            // normalization included).
            defaults.setWhitelist([".ARW", "nef", " CR3 "])
            XCTAssertEqual(
                defaults.resolvedWhitelist(), ["arw", "nef", "cr3"])

            // Reset restores every default.
            defaults.reset()
            XCTAssertEqual(defaults.resolvedMode(), .copy)
            XCTAssertFalse(defaults.rememberMode)
            XCTAssertEqual(defaults.resolvedWhitelist(), frozen)
        }
    }

    // MARK: - 6: LUT library root (M2-5-3 KD-3)

    func testLutLibraryRootDefaultsResetsAndRegistersTheSpelling() {
        withSuite { suite in
            let preferences = AppPreferences(defaultsSuiteName: suite)
            // Unset = the default root (zero behavior change for existing
            // installs — AC 5).
            XCTAssertEqual(preferences.lutLibraryRoot(), LutLibraryStore.defaultRoot)
            // Round-trip a custom root (isDirectory: true — the face
            // returns directory URLs with the trailing slash).
            let custom = URL(fileURLWithPath: "/tmp/lut-root-\(UUID().uuidString)", isDirectory: true)
            preferences.setLutLibraryRoot(custom)
            XCTAssertEqual(preferences.lutLibraryRoot(), custom)
            // The registered spelling is the store's key (one key, two
            // faces — the store reads it from .standard at init).
            XCTAssertEqual(
                AppPreferences.lutLibraryRootKey, LutLibraryStore.libraryRootKey)
            // Reset falls back to the default root.
            preferences.resetLutLibraryRoot()
            XCTAssertEqual(preferences.lutLibraryRoot(), LutLibraryStore.defaultRoot)
        }
    }
}