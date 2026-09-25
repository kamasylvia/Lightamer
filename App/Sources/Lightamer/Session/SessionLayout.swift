import Foundation
import os

// ─────────────────────────────────────────────────────────────────────────────
// SessionLayout (Plan 09-01 T2; SESS-02) — the Capture One-style session
// folder conventions and their single consumption-point constants.
//
// Directory set = REQUIREMENTS SESS-02 literal three tiers (D-09-CONTEXT-3):
// Capture/ (originals + co-located .lra sidecars), Crop/ (v1: created and
// maintained EMPTY — no working-copy semantics yet), Output/ (the Phase 11
// export landing zone). Trash/ and Selects/ are C1 conventions NOT adopted —
// building them would imply semantics v1 does not have.
//
// The reserved-directory set doubles as the scanner/watcher EXCLUDE table's
// root-level segment (`SessionTreeScanner` consumes it — single source; the
// dotfile/tmp/cache exclusion rules live in the scanner's predicate).
// ─────────────────────────────────────────────────────────────────────────────

enum SessionLayout {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "session-layout"
    )

    // MARK: - Directory names (the SESS-02 contract)

    static let captureDirectoryName = "Capture"
    static let cropDirectoryName = "Crop"
    static let outputDirectoryName = "Output"

    /// The derived-cache directory inside the session root
    /// (`session.lindex` + `thumbs/` — D-09-CONTEXT-2). Always excluded
    /// from the browse set.
    static let derivedCacheDirectoryName = ".lightamer"

    /// The reserved ROOT-LEVEL directories excluded from the browse set
    /// (exports must not reflow back into candidates; working copies must
    /// not double-enter the grid). The scanner/watcher consume THIS set —
    /// single source (Plan 09-01 T2/T3; 9-2 reuses it).
    static let reservedRootDirectoryNames: Set<String> = [
        captureDirectoryName, cropDirectoryName, outputDirectoryName,
    ]

    // MARK: - Idempotent creation (SESS-02)

    /// Create `Capture/`, `Crop/`, `Output/` under `sessionRoot` —
    /// idempotent: `createDirectory(withIntermediateDirectories: true)` on
    /// an existing directory is a zero-side-effect no-op (mtime untouched),
    /// so running it twice (and on EVERY session open) is free. Trash/
    /// Selects are deliberately NOT created (D-09-CONTEXT-3).
    static func ensureDirectories(at sessionRoot: URL) throws {
        let fileManager = FileManager.default
        for name in [
            captureDirectoryName, cropDirectoryName, outputDirectoryName,
        ] {
            let target = sessionRoot.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(
                at: target, withIntermediateDirectories: true
            )
        }
        logger.debug("session directories ensured at \(sessionRoot.path, privacy: .public)")
    }

    // MARK: - Phase 11 consumption points (constants, NOT implementation)

    /// EXP-08 export landing zone — `…/Output/` of the session root.
    ///
    /// **Phase 11 takeover point (Phase 8 移交义务):** the export pipeline
    /// consumes THIS constant as its default destination; Phase 9 only
    /// guarantees the directory's existence (`ensureDirectories`) — no
    /// export logic lives here.
    static func outputDirectory(for sessionURL: URL) -> URL {
        sessionURL.appendingPathComponent(outputDirectoryName, isDirectory: true)
    }

    /// The original-capture directory (originals + co-located `.lra`
    /// sidecars — `LightamerSidecar.sidecarURL` is full-name co-located,
    /// the 02-06 convention). Future import/drop targets (Phase 13).
    static func captureDirectory(for sessionURL: URL) -> URL {
        sessionURL.appendingPathComponent(captureDirectoryName, isDirectory: true)
    }
}
