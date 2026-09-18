import XCTest

/// FOUND-01/05 UI verification: the app launches into the three-column
/// shell (sidebar / editor viewport / inspector) with the empty state
/// visible (D-07/D-10/D-11). Scope per VALIDATION: launch + shell
/// STRUCTURE only — NSOpenPanel-driven file opening is not reliably
/// drivable by XCUITest on macOS and stays a manual verification
/// (01-VALIDATION "Manual-Only Verifications" + the 01-06-06 e2e pass).
///
/// a11y labels are String-Catalog localized, so queries match EITHER the
/// en or zh value (the test host inherits the Mac's UI language).
final class AppLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// FOUND-01: the app launches, the window exists, all three columns of
    /// the shell are reachable, and the D-11 empty state is shown.
    func testAppLaunchesAndShowsShell() throws {
        let app = XCUIApplication()
        app.launch()

        // The main window exists.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "app window appears")

        // FOUND-01: three-column shell — sidebar ("Sessions"), center
        // viewport ("Image viewport"), right inspector ("Inspector").
        // Each label query matches en OR zh catalog values.
        let sessions = app.descendants(matching: .any)
            .matching(Self.labelPredicate(en: "Sessions", zh: "会话")).firstMatch
        XCTAssertTrue(sessions.waitForExistence(timeout: 5), "sidebar (Sessions) present")

        let viewport = app.descendants(matching: .any)
            .matching(Self.labelPredicate(en: "Image viewport", zh: "图像视口")).firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5), "editor viewport present")

        let inspector = app.descendants(matching: .any)
            .matching(Self.labelPredicate(en: "Inspector", zh: "检查器")).firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 5), "inspector present")

        // D-11: empty-state hero copy while no image is loaded. The combined
        // element surfaces as a BUTTON; label matching uses CONTAINS because
        // SwiftUI combine semantics may append the hint to the label.
        let emptyState = app.buttons
            .matching(NSPredicate(
                format: "label CONTAINS %@ OR label CONTAINS %@",
                "Empty state", "空状态"
            ))
            .firstMatch
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "empty state prompt visible (D-11). TREE DUMP:\n\(app.debugDescription)"
        )
    }

    /// D-10: v1 forces dark mode. XCUITest exposes no typed API for the
    /// host window's appearance — KVC (`value(forKey: "effectiveAppearance")`)
    /// raises an ObjC NSUnknownKeyException that Swift's guard cannot catch,
    /// so the documented VALIDATION fallback applies: the app root sets
    /// `.preferredColorScheme(.dark)` (LightamerApp.swift, D-10) and the
    /// visual confirm is the VALIDATION manual row (screenshot evidence,
    /// 2026-09-16 evening session).
    func testForcedDarkMode() throws {
        throw XCTSkip(
            "XCUI exposes no appearance API (KVC throws uncatchable NSUnknownKeyException) — "
                + "dark mode is verified by .preferredColorScheme(.dark) at the app root + "
                + "VALIDATION manual screenshot confirm (D-10)"
        )
    }

    /// FOUND-05 — displaying a decoded RAW in the viewport is covered by
    /// the manual e2e pass (VALIDATION Manual-Only: XCUITest cannot drive
    /// the out-of-process NSOpenPanel). This test documents that decision
    /// instead of pretending an automated check exists.
    func testFileOpenDisplaysImage() throws {
        throw XCTSkip(
            "NSOpenPanel interaction is restricted for XCUITest on macOS — "
                + "manual e2e (File → Open CR3/JPEG/NEF) covers FOUND-05 per VALIDATION"
        )
    }

    // MARK: - helpers

    /// Match an element whose accessibility label equals either the en or
    /// zh catalog value (the String Catalog localizes at render time).
    private nonisolated static func labelPredicate(en: String, zh: String) -> NSPredicate {
        NSPredicate(
            format: "label == %@ OR label == %@ OR identifier == %@",
            en, zh, en
        )
    }
}
