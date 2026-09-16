import Foundation
import Observation

/// Session-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the current session folder, the recent-sessions list (Phase 9
/// fills it), and the folder-watch status. Does NOT own image data, layers,
/// or inspector selection, and holds no references to the other state
/// objects — cross-state coordination flows through the View layer.
@Observable
@MainActor
final class SessionState {

    /// The folder backing the current Capture One-style session (Phase 9).
    private(set) var currentSessionURL: URL?

    /// Recent sessions (stub — Phase 9 fills via FSEvents + reconcile, L007).
    private(set) var recentSessions: [URL] = []

    /// Human-readable folder-watch status (empty = not watching; Phase 9).
    private(set) var folderWatchStatus: String = ""
}
