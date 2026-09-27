import Foundation
import LightamerCore
import Observation

// Plan 13-2 T4 — the soft-proof UI state machine (COLOR-02's control face).
//
// The state machine OWNS the routing decisions (which entry, whether the
// toggle is legal, recency memory); the actual pipe coupling is the ONE
// `PipeCoordinator.setSoftProof` call per committed change — the proof
// state itself is coordinator-level runtime data (never Params/history/
// export, see `SoftProofProfile`). Every route funnels through
// `recommit(_:)`, so the coordinator always receives the SAME shape the
// UI would produce by hand.
//
// UX boundary (the plan's wording discipline, same face as the QL preview
// semantics): soft proofing is a DISPLAY simulation — the copy must never
// suggest it changes the stored edit. The rejection copy states what was
// rejected and why, in display terms.
@Observable
@MainActor
final class SoftProofState {

    /// The live proof configuration routed to the coordinator (nil = OFF).
    private(set) var profile: SoftProofProfile?

    /// Gamut check (T3 OOG black clipping) — a UI-facing knob on the SAME
    /// profile object; flipping it re-commits (the stableID folds it).
    private(set) var gamutCheck: Bool = false

    /// Black-point compensation (default ON; the T1 probe's public switch).
    private(set) var blackPointCompensation: Bool = true

    /// The currently selected printer entry (nil = none chosen yet — the
    /// toggle stays inert until one is; dt's softproof requires a profile
    /// too). NOT restored across launches: proofing is a view mode, the
    /// default is OFF (13-2-DECISIONS).
    private(set) var selectedEntry: PrinterProfileCatalog.Entry?

    /// Most-recently-used printer names (UI ordering memory; the DEFAULT
    /// section list stays catalog order). Persisted via UserDefaults.
    private(set) var recentNames: [String] = []

    /// The last rejection reason (a display-terms message for the status
    /// toast; nil = nothing pending). Consumed by the control view.
    private(set) var lastRejection: String?

    var isActive: Bool { profile != nil }

    private static let recentKey = "softproof.recent.names"
    static let recentLimit = 5

    init() {
        recentNames = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    // MARK: - Routes (the ONLY ways the coordinator's proof state changes)

    /// Select a printer profile and turn proofing ON with it. Returns false
    /// (with `lastRejection` set) for a rejected entry — a CMYK profile or
    /// an unreadable file; the proof state stays untouched.
    @discardableResult
    func select(entry: PrinterProfileCatalog.Entry, coordinator: PipeCoordinator) -> Bool {
        do {
            let profile = try entry.makeProfile(
                intent: .relativeColorimetric,
                blackPointCompensation: blackPointCompensation,
                gamutCheck: gamutCheck)
            selectedEntry = entry
            recordRecent(entry.name)
            lastRejection = nil
            self.profile = profile
            coordinator.setSoftProof(profile)
            return true
        } catch {
            lastRejection = AppError(error).localizedDescription
            return false
        }
    }

    /// Toggle proofing with the CURRENT selection. Without a selection the
    /// toggle cannot turn ON (a proof without a chosen printer would
    /// silently simulate an arbitrary profile — the printer is a user
    /// decision): a rejection is recorded and the state stays OFF.
    func toggle(coordinator: PipeCoordinator) {
        if isActive {
            profile = nil
            coordinator.setSoftProof(nil)
            lastRejection = nil
            return
        }
        guard let entry = selectedEntry else {
            lastRejection = String(localized: "softproof_reject_no_printer")
            return
        }
        select(entry: entry, coordinator: coordinator)
    }

    /// Flip the gamut check; an active proof re-commits with the new flag
    /// (the OFF state just remembers it for the next activation).
    func setGamutCheck(_ on: Bool, coordinator: PipeCoordinator) {
        gamutCheck = on
        guard isActive, let entry = selectedEntry else { return }
        select(entry: entry, coordinator: coordinator)
    }

    // MARK: - Internals

    private func recordRecent(_ name: String) {
        recentNames.removeAll { $0 == name }
        recentNames.insert(name, at: 0)
        if recentNames.count > Self.recentLimit {
            recentNames = Array(recentNames.prefix(Self.recentLimit))
        }
        UserDefaults.standard.set(recentNames, forKey: Self.recentKey)
    }
}
