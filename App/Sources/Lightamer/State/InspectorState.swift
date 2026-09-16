import Foundation
import Observation

/// Inspector-subsystem state (D-03b isolation contract).
///
/// Owns ONLY: the selected iop panel and panel expand/collapse state (stubs —
/// Phase 3+ fills with the real iop panel stack). Does NOT own image data and
/// holds no references to the other state objects.
@Observable
@MainActor
final class InspectorState {

    /// Currently selected inspector panel identifier (stub).
    private(set) var selectedPanel: String = ""

    /// Identifiers of expanded inspector sections (stub).
    private(set) var expandedSections: Set<String> = []
}
