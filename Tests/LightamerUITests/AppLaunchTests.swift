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

        // D-11: empty-state hero copy while no image is loaded.
        let emptyState = app.descendants(matching: .any)
            .matching(Self.labelPredicate(
                en: "Empty state: no session loaded. Press the button to select a folder, or drag a RAW file here.",
                zh: "空状态：未加载会话。点按按钮选择文件夹，或将 RAW 文件拖放到此处。"
            )).firstMatch
        XCTAssertTrue(emptyState.exists, "empty state prompt visible (D-11)")
    }

    /// D-10: v1 forces dark mode. Read via KVC on the host window
    /// (`effectiveAppearance` — XCUITest exposes no typed API). If the
    /// KVC channel is unavailable in a future macOS, this skips with the
    /// documented manual fallback per VALIDATION.
    func testForcedDarkMode() throws {
        let app = XCUIApplication()
        app.launch()
        let window = try XCTUnwrap(
            app.windows.firstMatch.waitForExistence(timeout: 10) ? app.windows.firstMatch : nil
        )

        let appearance = window.value(forKey: "effectiveAppearance") as? String
        guard let appearance else {
            throw XCTSkip(
                "effectiveAppearance not readable via XCUI on this OS build — "
                    + "dark mode stays a manual confirm per VALIDATION (D-10)"
            )
        }
        XCTAssertTrue(
            appearance.lowercased().contains("dark"),
            "app appearance must be dark (D-10), got \(appearance)"
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
