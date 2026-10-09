import Foundation
import LightamerCore
import XCTest

@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// ImportFilterTests (Plan M2-2-2 T1) — the M2LIB-03 hardened ACs ①② as
// machine checks (the Alcedo 0.3.0 zero-filter defect's反向 pins):
//
//   AC① whitelist = LAST-extension exact match, case-insensitive:
//     photo.ARW / photo.arw / photo.ARw accepted; photo.ARW.xmp rejected
//     (its last extension is xmp); photo (no extension) rejected;
//     photo.jpeg / photo.tif rejected (not on the default whitelist)
//   AC② the hardcoded sidecar table (.xmp/.lra/.lightamer-preset/.pp3/.opc)
//     + hidden files all rejected — and the configuration can NEVER re-admit
//     a sidecar (the exclusion runs before the whitelist, KD-1 order ②)
//   ImportDefaults: injected-suite read/write + reset; the configured
//     whitelist REPLACES the default face (KD-1); default mode = copy with
//     the remember gate (OQ-4: single-shot overrides never persist)
//
// Hidden-flag leg uses a real temp file (L009: never the external volume).
// ─────────────────────────────────────────────────────────────────────────────

final class ImportFilterTests: XCTestCase {

    private var tempDirectory: URL!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("import-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true)
        defaultsSuiteName = "import-filter-tests-\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(
            forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        tempDirectory.appendingPathComponent(name)
    }

    private func reasons(
        _ names: [String], whitelist: Set<String> = LibrarySchema.defaultRawExtensions
    ) -> [String: ImportRejection.Reason] {
        let selection = ImportFilter.select(
            names.map(url), whitelist: whitelist)
        var map: [String: ImportRejection.Reason] = [:]
        for rejection in selection.rejected { map[rejection.url.lastPathComponent] = rejection.reason }
        // Cross-check: every accepted name must be absent from the map.
        for accepted in selection.accepted {
            XCTAssertFalse(
                names.contains(accepted.lastPathComponent) && map[accepted.lastPathComponent] != nil)
        }
        return map
    }

    // MARK: - AC① (whitelist, last extension, case-insensitive)

    func testWhitelistAcceptsRawAcrossCaseMatrix() {
        let map = reasons(["photo.ARW", "photo.arw", "photo.ARw", "IMG_0001.dng"])
        XCTAssertTrue(map.isEmpty, "all RAW-case variants must be accepted, got \(map)")
    }

    func testDoubleExtensionSidecarRejectedByLastExtension() {
        // photo.ARW.xmp — the LAST extension is xmp → the sidecar table
        // catches it BEFORE the whitelist sees "arw" (KD-1 order ②).
        let map = reasons(["photo.ARW.xmp"])
        XCTAssertEqual(map["photo.ARW.xmp"], .sidecar)
    }

    func testNoExtensionAndNonWhitelistedFormatsRejected() {
        // M4-1-02 T5 (OQ-5, THE designed flip — the plan's 恰一处 AC):
        // `photo.tif` was whitelist-rejected pre-M4-1; with the tiff
        // family DOUBLE-ON by default it is now ACCEPTED (nil reason).
        // The remaining names stay genuinely non-whitelisted.
        let map = reasons(["photo", "photo.jpeg", "photo.tif", "photo.jpg", "photo.png"])
        for name in ["photo", "photo.jpeg", "photo.jpg", "photo.png"] {
            XCTAssertEqual(
                map[name], .extensionNotWhitelisted, "\(name) must be whitelist-rejected")
        }
        XCTAssertNil(
            map["photo.tif"],
            "the tiff family is double-on by default — the M4-1-02 flip")
    }

    func testLastExtensionSemanticsDocumented() {
        // The KD-1 documented contract: the double-extension DISGUISE
        // (raw.xmp.arw — last extension arw) PASSES; the requirement's
        // semantics are last-extension-exact and this test pins it.
        let map = reasons(["raw.xmp.arw"])
        XCTAssertTrue(map.isEmpty)
    }

    // MARK: - AC② (hardcoded sidecar table + hidden)

    func testAllFiveSidecarExtensionsRejected() {
        let map = reasons([
            "photo.xmp", "shot.lra", "look.lightamer-preset", "edit.pp3", "curve.opc",
        ])
        for (name, reason) in map {
            XCTAssertEqual(reason, .sidecar, "\(name)")
        }
        XCTAssertEqual(map.count, 5, "all five sidecar kinds must reject")
    }

    func testDotPrefixHiddenRejected() {
        let map = reasons([".hidden", ".DS_Store"])
        XCTAssertEqual(map[".hidden"], .hidden)
        XCTAssertEqual(map[".DS_Store"], .hidden)
    }

    func testFinderHiddenFlagRejected() throws {
        // The macOS hidden flag (a REAL temp file, not a dot-name) — set
        // through the NSURL resource face (FileAttributeKey has no .hidden).
        let flagged = url("flagged.arw")
        try Data([0x41]).write(to: flagged)
        try (flagged as NSURL).setResourceValue(true, forKey: .isHiddenKey)
        let values = try flagged.resourceValues(forKeys: [.isHiddenKey])
        XCTAssertTrue(values.isHidden ?? false, "fixture must carry the flag")
        let map = reasons(["flagged.arw"])
        XCTAssertEqual(map["flagged.arw"], .hidden)
    }

    func testConfigurationCannotRe_admitSidecar() {
        // The hardened posture (OQ-12): even a whitelist that CONTAINS
        // "xmp" must not re-admit .xmp — the exclusion table runs first
        // and never reads configuration.
        let configured: Set<String> = LibrarySchema.defaultRawExtensions.union(["xmp"])
        let map = reasons(["photo.xmp"], whitelist: configured)
        XCTAssertEqual(map["photo.xmp"], .sidecar)
    }

    // MARK: - ImportDefaults (the configurable whitelist host)

    func testConfiguredWhitelistReplacesDefaultFace() {
        let defaults = ImportDefaults(defaultsSuiteName: defaultsSuiteName)
        // KD-1: the configured set REPLACES the default (never unions).
        defaults.setWhitelist(["mos"])
        var map = reasons(["a.mos", "b.arw"], whitelist: defaults.resolvedWhitelist())
        XCTAssertTrue(map["a.mos"] == nil, ".mos must be accepted once configured")
        XCTAssertEqual(
            map["b.arw"], .extensionNotWhitelisted,
            "replacement semantics: an unconfigured default drops out")

        // Reset → the frozen 14-item default returns.
        defaults.reset()
        let whitelist = defaults.resolvedWhitelist()
        XCTAssertEqual(whitelist, LibrarySchema.defaultRawExtensions)
        XCTAssertEqual(whitelist.count, 14)
        map = reasons(["b.arw"], whitelist: whitelist)
        XCTAssertTrue(map.isEmpty)
    }

    func testConfiguredWhitelistNormalizationTrimsDotsAndCase() {
        let defaults = ImportDefaults(defaultsSuiteName: defaultsSuiteName)
        defaults.setWhitelist([".MOS", " mos "])
        let whitelist = defaults.resolvedWhitelist()
        XCTAssertEqual(whitelist, ["mos"])
    }

    // MARK: - ImportDefaults (mode + remember gate, OQ-4)

    func testDefaultModeIsCopyWithoutRemember() {
        let defaults = ImportDefaults(defaultsSuiteName: defaultsSuiteName)
        XCTAssertEqual(defaults.resolvedMode(), .copy)
    }

    func testRememberedModePersistsAndResets() {
        let defaults = ImportDefaults(defaultsSuiteName: defaultsSuiteName)
        defaults.storeChoice(ImportModeChoice(mode: .link, remember: true))
        XCTAssertEqual(defaults.resolvedMode(), .link)
        XCTAssertTrue(defaults.rememberMode)

        defaults.reset()
        XCTAssertEqual(defaults.resolvedMode(), .copy)
        XCTAssertFalse(defaults.rememberMode)
    }

    func testSingleShotOverrideWithoutRememberNeverPersists() {
        let defaults = ImportDefaults(defaultsSuiteName: defaultsSuiteName)
        // A remembered link choice first…
        defaults.storeChoice(ImportModeChoice(mode: .link, remember: true))
        XCTAssertEqual(defaults.resolvedMode(), .link)
        // …then a single-shot copy with remember UNCHECKED: nothing may
        // persist — the next dialog defaults to copy again (OQ-4).
        defaults.storeChoice(ImportModeChoice(mode: .copy, remember: false))
        XCTAssertEqual(defaults.resolvedMode(), .copy)
        XCTAssertFalse(defaults.rememberMode)
        XCTAssertNil(
            UserDefaults(suiteName: defaultsSuiteName)?.string(forKey: ImportDefaults.modeKey),
            "the single-shot mode must not linger in storage")
    }
}
