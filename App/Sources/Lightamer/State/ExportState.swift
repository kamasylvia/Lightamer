import Foundation
import Observation

/// Export-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the export queue and its progress (stubs — export lands in
/// Phase 11). Does NOT own image data and holds no references to the other
/// state objects.
@Observable
@MainActor
final class ExportState {

    /// Files queued for export (stub — Phase 11 fills the queue + recipes).
    private(set) var queue: [URL] = []

    /// Overall export progress in [0, 1] (stub — Phase 11).
    private(set) var progress: Double = 0
}
