import AppKit
import Foundation
import LightamerCore
import os

// ─────────────────────────────────────────────────────────────────────────────
// PostExportActions (Plan 11-04 T5, EXP-08) — the post-export actions:
// a user-chosen script run per exported file + a Finder reveal.
//
// D-11-CONTEXT-6 SECURITY FACE (the literal discipline):
//   • SCRIPT BY PATH, NEVER an inline command string. The user picks an
//     EXECUTABLE FILE via NSOpenPanel; the app persists a plain
//     bookmark (non-sandboxed: no security scope needed — the Project
//     carries ENABLE_USER_SELECTED_FILES=read-write) and re-validates
//     reachability at each use (a moved/deleted script degrades to a
//     "re-pick" state, never an error storm).
//   • Process DIRECT EXEC, NO shell interpretation: an executable file
//     runs as `executableURL` with `$1 = <output file path>`; a `.sh`
//     WITHOUT the execute bit runs as `/bin/sh <script> <output>`.
//     Either way the path is passed as ONE argv element — user paths
//     containing spaces/metacharacters are safe by construction.
//   • The script runs with the USER's full privileges (the MCP-10
//     philosophy — documented in the panel: a script is trusted code).
//
// TRIGGER (OQ-11-7): every exported FILE fires ONCE (the dt
// `darktable|exported` per-image semantics), from the queue's per-job
// completion hook. A FAILED job never triggers.
//
// Preferences persist in UserDefaults (the script pick + the two
// switches are USER PREFERENCES — unlike the recipe, D-11-CONTEXT-3's
// no-persistence ruling does not cover them).
// ─────────────────────────────────────────────────────────────────────────────

enum PostExportActions {

    private static let logger = Logger(
        subsystem: "com.kamasylvia.lightamer", category: "post-export")

    // MARK: - Preference keys

    private static let scriptBookmarkKey = "export.postaction.scriptBookmark"
    private static let runScriptKey = "export.postaction.runScript"
    private static let revealKey = "export.postaction.revealInFinder"

    // MARK: - Preference read/write (the panel's configuration face)

    static var wantsRunScript: Bool {
        get { UserDefaults.standard.bool(forKey: runScriptKey) }
        set { UserDefaults.standard.set(newValue, forKey: runScriptKey) }
    }

    static var wantsRevealInFinder: Bool {
        get { UserDefaults.standard.bool(forKey: revealKey) }
        set { UserDefaults.standard.set(newValue, forKey: revealKey) }
    }

    /// The picked script's bookmark (nil = none picked yet).
    static var scriptBookmark: Data? {
        get { UserDefaults.standard.data(forKey: scriptBookmarkKey) }
        set { UserDefaults.standard.set(newValue, forKey: scriptBookmarkKey) }
    }

    /// Resolve the bookmark to the script URL. nil = no bookmark, or the
    /// resource moved away (the panel surfaces the degraded state and the
    /// user re-picks — never an error alert storm).
    static func resolveScript() -> URL? {
        guard let data = scriptBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        else {
            logger.warning("post-export script bookmark unresolvable")
            return nil
        }
        // The degradation check (D-11-CONTEXT-6): a vanished script is a
        // re-pick prompt, not a hard failure.
        let reachable = (try? url.checkResourceIsReachable()) ?? false
        if !reachable {
            logger.warning(
                "post-export script unreachable: \(url.path, privacy: .public)")
            return nil
        }
        if isStale {
            // Refresh the bookmark in place (the file still resolves).
            scriptBookmark = try? url.bookmarkData()
        }
        return url
    }

    /// Persist a freshly picked script (NSOpenPanel result).
    static func storeScript(_ url: URL) {
        scriptBookmark = try? url.bookmarkData()
        logger.info("post-export script set: \(url.path, privacy: .public)")
    }

    // MARK: - The per-file trigger (the queue's completion hook)

    /// Fire BOTH actions for one promoted file (the caller decides from
    /// the preferences; a file that does not exist is skipped silently —
    /// it cannot be the promoted output).
    static func fire(for file: URL, script: URL?) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        if let script {
            runScriptDirect(script: script, outputFile: file)
        }
        revealInFinder(file)
    }

    // MARK: - Process DIRECT EXEC (no shell string, ever)

    /// Run the script with `$1 = <output file path>`. An executable file
    /// runs directly; a `.sh` lacking the execute bit runs through
    /// `/bin/sh` — in BOTH cases the paths ride ARGV (never a parsed
    /// command string: spaces, quotes and `$` in user paths are inert).
    /// Fire-and-forget on a utility task (a slow script must not block
    /// the queue's completion path); stdout/stderr are drained and
    /// logged, and the exit status is recorded.
    private static func runScriptDirect(script: URL, outputFile: URL) {
        Task.detached(priority: .utility) {
            let process = Process()
            let isShellFallback =
                script.pathExtension.lowercased() == "sh"
                && !FileManager.default.isExecutableFile(atPath: script.path)
            if isShellFallback {
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [script.path, outputFile.path]
            } else {
                process.executableURL = script
                process.arguments = [outputFile.path]
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                logger.error(
                    "post-export script failed to launch: \(error.localizedDescription, privacy: .public)")
                return
            }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                logger.warning(
                    "post-export script exit \(status, privacy: .public): \(String(decoding: errData, as: UTF8.self), privacy: .public)")
            }
            let out = String(decoding: outData, as: UTF8.self).trimmingCharacters(
                in: .whitespacesAndNewlines)
            if !out.isEmpty {
                logger.info("post-export script: \(out, privacy: .public)")
            }
        }
    }

    // MARK: - Finder reveal

    /// The standard reveal (single file highlighted; a missing file would
    /// have been filtered above).
    static func revealInFinder(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}
