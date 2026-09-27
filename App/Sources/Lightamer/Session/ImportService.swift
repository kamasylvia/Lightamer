import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────
// ImportService (Plan 13-3 T4, SYS-04, D-13-CONTEXT-7) — the drop-import
// file leg: batch copy/move of Finder-dropped files into the open session.
//
// DESTINATION (execution decision, 13-3-DECISIONS): the SESSION ROOT —
// NOT the literal `Capture/` tier. D-09-CONTEXT-3 (the user-ratified 09
// ruling) EXCLUDES the root-level Capture/Crop/Output tiers from the
// browse set, so a file copied into `Capture/` could never enter the
// grid and the plan's own "reconcile 收编" acceptance would be dead on
// arrival. The session root IS the browse set's capture tier in the
// Lightamer layout; the caller passes the directory.
//
// Safety semantics (the plan's red lines, each pinned by ImportDropTests):
//   - COPY is the DEFAULT. Move happens ONLY through the caller's
//     explicit Option-modifier intent (`move: true`) — the no-modifier
//     path can NEVER relocate a source file.
//   - Copy leaves the SOURCE byte-identical (content + mtimes + the
//     source directory's own mtime is untouched — nothing is ever
//     written next to the source).
//   - Per-file failure isolation: one unreadable/colliding file neither
//     aborts the batch nor corrupts the outcome — failures are LISTED.
//   - Name collisions SKIP (never overwrite — a silent overwrite could
//     destroy an edited original; the failure line surfaces in the UI
//     toast). Execution decision, 13-3-DECISIONS.
//
// The file predicate is the SessionTreeScanner's browsable extension set
// (SINGLE SOURCE — what lands is exactly what the index will accept).
// Directories and `.lra` sidecars never import. The INDEX ingest after a
// batch is the caller's explicit `SessionIndexController.reconcile`
// trigger (never FSEvents timing — D-13-CONTEXT-7②).
// ─────────────────────────────────────────────────────────────────────────

enum ImportService {

    struct Failure: Sendable, Equatable {
        /// The source file that failed.
        var source: URL
        /// Why: a stable reason key ("collision" / "copyFailed" /
        /// "moveFailed" / "inSession") + message.
        var reason: String
    }

    struct Outcome: Sendable, Equatable {
        /// The DESTINATION urls that landed in the session (the caller's
        /// directory — the app passes the session ROOT, 13-3-DECISIONS).
        var imported: [URL] = []
        /// The per-file failures (the batch continues past each one).
        var failures: [Failure] = []

        var isFullySuccessful: Bool { failures.isEmpty }
    }

    /// Import `urls` into `destinationDirectory` (the session root — see
    /// the destination decision in the header). `move` = the explicit
    /// Option-modifier intent (source relocation); false (the default)
    /// copies. File-manager injectable for tests.
    static func importFiles(
        at urls: [URL], into destinationDirectory: URL, move: Bool = false,
        fileManager: FileManager = .default
    ) -> Outcome {
        var outcome = Outcome()
        // The destination must exist (the session root always does; a
        // custom tier self-heals here).
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            do {
                try fileManager.createDirectory(
                    at: destinationDirectory, withIntermediateDirectories: true)
            } catch {
                // Nothing can land — every file reports.
                return Outcome(
                    failures: urls.map {
                        Failure(source: $0, reason: "createDestinationFailed")
                    })
            }
        }
        for source in urls {
            // Only real, browsable files (dirs + sidecars + dotfiles skip).
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  SessionTreeScanner.isBrowsableFile(source.lastPathComponent),
                  !source.lastPathComponent.hasSuffix(".lra")
            else {
                outcome.failures.append(
                    Failure(source: source, reason: "notImportable"))
                continue
            }
            let destination = destinationDirectory.appendingPathComponent(
                source.lastPathComponent)
            // Already a member of this Capture tier — never self-copy.
            if source.standardizedFileURL == destination.standardizedFileURL {
                outcome.failures.append(
                    Failure(source: source, reason: "inSession"))
                continue
            }
            // Collision: SKIP, never overwrite (execution decision).
            if fileManager.fileExists(atPath: destination.path) {
                outcome.failures.append(
                    Failure(source: source, reason: "collision"))
                continue
            }
            do {
                if move {
                    try fileManager.moveItem(at: source, to: destination)
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                }
                outcome.imported.append(destination)
            } catch {
                outcome.failures.append(
                    Failure(
                        source: source,
                        reason: move ? "moveFailed" : "copyFailed"))
            }
        }
        return outcome
    }
}
