// ─────────────────────────────────────────────────────────────────────────────
// LibraryFirstLaunch (gallery-first startup, 2026-11-02) — the DEFAULT
// LIBRARY assurance. First launch (no project open, no recents) opens the
// collection directly instead of the OQ-1 A Welcome sheet: a persistent
// `.lalb` package at `~/Library/Application Support/Lightamer/Library.lalb`
// (the PresetsStore base precedent — created once, opened on every later
// launch). The grid renders its REAL empty face (LibraryGridView.emptyState
// + its import entry) — no bespoke launch screen.
//
// Division of labor: the PURE assignment (which URL is the default library
// + its display name) lives here as testable nonisolated faces; the App-side
// caller (`LightamerShell` launch task) does the open-or-create drive through
// the existing `createProject`/`openProject` controller faces. This file
// touches neither the controller (FIX2③ zero-diff) nor the welcome view
// (the welcome sheet survives for the recents route).
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

/// The gallery-first startup faces (pure assignment — no IO here; the
/// caller drives `createProject`/`openProject` against `defaultLibraryURL`).
enum LibraryFirstLaunch {

    /// The default library's package file name (single source — the launch
    /// task + the fallback probe + the tests quote this).
    nonisolated static let defaultLibraryFileName = "Library.lalb"

    /// Whether this process is a unit-test host (`XCTestBundlePath` rides
    /// the environment in BOTH harnesses — test-direct.sh injects it for
    /// the direct-launch host, testmanagerd sets it under `xcodebuild
    /// test`). The shell's launch task skips the default-library drive
    /// here — a test host must never create/open the user's REAL library
    /// as a launch side effect (reproduced 2026-11-02: every bundle run
    /// created `~/Library/Application Support/Lightamer/Library.lalb`).
    /// The face is pure + injectable so the suite pins it without env
    /// mutation. A UI-test-driven app (`XCUIApplication().launch()`)
    /// carries no such variable and keeps the production drive.
    nonisolated static func isTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestBundlePath"] != nil
    }


    /// The default library's project name (the seeded `project_meta` name —
    /// the top bar's no-recents title).
    nonisolated static let defaultLibraryName = "Library"

    /// `~/Library/Application Support/Lightamer/Library.lalb` — the
    /// per-user default collection (nil = the support directory itself is
    /// unreachable — the launch task treats it as "stay on the fallback
    /// face", never a crash).
    nonisolated static func defaultLibraryURL(
        supportDirectory: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
    ) -> URL? {
        supportDirectory?
            .appendingPathComponent("Lightamer", isDirectory: true)
            .appendingPathComponent(defaultLibraryFileName)
    }
}
