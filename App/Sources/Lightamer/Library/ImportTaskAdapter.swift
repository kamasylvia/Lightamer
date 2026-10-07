import Foundation
import LightamerCore
import Observation

// ─────────────────────────────────────────────────────────────────────────────
// ImportTaskAdapter (Plan M2-3-1 T6, KD-7 + checker E3) — the import leg of
// the BackgroundTaskHosting protocol: a READ-ONLY subscriber over
// `LibraryProjectController.importProgress` (the `:47` publication face)
// with `cancelImport()` transit (the `:267` route). THE CONTROLLER IS NEVER
// MODIFIED — `runImport`'s orchestration point stays out of this plan's
// modification face; the dialog flow (ImportModeDialog → runImport) is
// untouched, the adapter only MIRRORS the progress into the registry.
//
// MONOTONICITY: the ImportProgress stream is per-run monotonic in `processed`
// by construction, but the adapter still clamps (a replayed/out-of-order
// snapshot can never move the bar backwards — the AC's monotonic face).
// Completion/cancellation (progress == nil after a run, or phase terminal)
// is the registry finish signal — the HOST drives it (the view's onChange IS
// the read-only subscription seam; the adapter itself stays a pure mapper).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
@Observable
final class ImportTaskAdapter: BackgroundTaskHandle {

    let id = UUID()

    /// The task title (the importing folder's name rides along).
    let title: String

    var snapshot = BackgroundTaskSnapshot.indeterminate(
        String(localized: "tasks_import_waiting", defaultValue: "Import pending…"))

    /// The cancel transit — defaults to the controller's `cancelImport()`
    /// (the checker-E3 route); injectable for the spy tests.
    private let cancelRoute: () -> Void

    /// The clamping floor (the monotonic face: never below the last fraction).
    private var lastFraction: Double = 0

    init(controller: LibraryProjectController, folderName: String? = nil) {
        self.title = folderName.map {
            String(localized: "tasks_import_title",
                   defaultValue: "Importing \($0)…")
        } ?? String(localized: "tasks_import_title_generic",
                    defaultValue: "Importing photos…")
        self.cancelRoute = { [weak controller] in
            controller?.cancelImport()
        }
    }

    /// Test seam: an explicit cancel route (the spy face).
    init(title: String, cancelRoute: @escaping () -> Void) {
        self.title = title
        self.cancelRoute = cancelRoute
    }

    // MARK: - The read-only subscription face (the host drives)

    /// Map one controller publication into a clamped snapshot. `nil` (the
    /// post-run face) is NOT mapped here — the host finishes the task on it.
    func apply(_ progress: ImportProgress?) {
        guard let progress else { return }
        let fraction: Double? = progress.total > 0
            ? Double(progress.processed) / Double(progress.total)
            : nil
        switch progress.phase {
        case .scanning:
            snapshot = .indeterminate(
                String(localized: "tasks_import_scanning",
                       defaultValue: "Scanning folder…"))
        case .importing:
            let detail = Self.detail(for: progress)
            if let fraction {
                // The monotonic clamp: only forward motion lands.
                let clamped = max(fraction, lastFraction)
                lastFraction = clamped
                snapshot = .fraction(clamped, detail)
            } else {
                snapshot = .indeterminate(detail)
            }
        case .completed:
            lastFraction = 1
            snapshot = .fraction(
                1, String(localized: "tasks_import_completed",
                          defaultValue: "Import complete"))
        case .cancelled:
            snapshot = .fraction(
                lastFraction,
                String(localized: "tasks_import_cancelled",
                       defaultValue: "Import cancelled"))
        }
    }

    /// The stage copy (counts + failures + duplicate skips — the
    /// ImportProgressView summary face's twin, localized for the shell).
    private static func detail(for progress: ImportProgress) -> String {
        var detail = String(
            localized: "tasks_import_counts",
            defaultValue: "\(progress.processed) of \(progress.total)")
        if progress.failed > 0 {
            detail += " — " + String(
                localized: "tasks_import_failed",
                defaultValue: "failed \(progress.failed)")
        }
        if progress.skippedDuplicates > 0 {
            detail += " — " + String(
                localized: "tasks_import_duplicates",
                defaultValue: "duplicates skipped \(progress.skippedDuplicates)")
        }
        return detail
    }

    // MARK: - BackgroundTaskHandle

    /// The checker-E3 transit: straight to `cancelImport()` — the same face
    /// the M2-2 ImportProgressView's cancel button rides.
    func cancel() async {
        cancelRoute()
    }
}
