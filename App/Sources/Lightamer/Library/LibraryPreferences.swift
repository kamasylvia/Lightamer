import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LibraryLegacyGate (Plan M2-2-4, M2LIB-06 / OQ-8) — the legacy-library
// boolean gate that hides the M2-era Sessions/Catalogs face behind the
// project-first default.
//
// Semantics (OQ-8 ruling, frozen): the gate defaults to FALSE — the Sessions
// sections, the Catalogs sections, the organization-mode switcher and the
// Settings Catalogs rows are all hidden, and the project workspace is the
// startup face (OQ-1). `LIGHTAMER_LEGACY_LIBRARY=1` in the process
// environment opts BACK into the pre-M2-2-4 library face — the QA/regression
// channel (the gated code and tests stay in the tree untouched, so the
// opt-back path is the M2-2 face byte-for-byte). There is deliberately NO
// Settings switch (双库并存的心智负担 — the OQ-8 rationale verbatim); this env
// seam is documented in AGENTS.md only, never in UI copy.
//
// KD-1 injection discipline (the M2-1 D-EXEC-1 lesson): the ONLY place the
// environment is read is `isLegacyLibraryRequested(environment:)` — a pure,
// injectable function. The production assembly (LightamerApp) evaluates it
// ONCE and distributes the resulting Bool as plain values; view bodies never
// touch ProcessInfo (pinned by `git grep ProcessInfo App/Sources/Lightamer/UI/`
// returning the assembly point only). Tests feed literal dictionaries — the
// three-way split (absent → false / "0" → false / "1" → true) is the KD-4
// layer-1 pin.
// ─────────────────────────────────────────────────────────────────────────────

enum LibraryLegacyGate {

    /// The opt-back environment key (the ONLY spelling; "1" = legacy face).
    nonisolated static let environmentKey = "LIGHTAMER_LEGACY_LIBRARY"

    /// The gate's single evaluation point (KD-1). Default argument reads the
    /// process environment (the production face); tests inject literal
    /// dictionaries (the override seam — no process-global mutation).
    nonisolated static func isLegacyLibraryRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[environmentKey] == "1"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LabelingPreferences (Plan M2-10-03 KD-3 / M2AI-03) — the auto-labeling
// ask-mode key family (`library.ai.labelingMode`), the ImportDefaults twin:
// constant key + injectable suite + full-replacement store + reset. Three
// states (OQ-6-A): `.ask` (default — the SemanticGenerationDialog-style
// prompt on import), `.always` (skip the ask, enqueue), `.never` (silent).
// An absent/unreadable stored value falls back to `.ask` — labeling writes
// user-visible state, so the safe default is the ASK.
// ─────────────────────────────────────────────────────────────────────────────

/// The auto-labeling ask mode (`LabelingPreferences.mode`).
enum LabelingMode: String, Sendable, CaseIterable {
    case ask
    case always
    case never
}

struct LabelingPreferences: Sendable {

    /// The single key (the ONLY spelling).
    nonisolated static let modeKey = "library.ai.labelingMode"

    /// nil = `.standard` (the app face); tests pass an isolated suite name.
    let defaultsSuiteName: String?

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The effective mode: the stored value when parseable, else `.ask`.
    var mode: LabelingMode {
        guard let raw = defaults.string(forKey: Self.modeKey),
            let mode = LabelingMode(rawValue: raw)
        else { return .ask }
        return mode
    }

    /// The full-replacement write face (never a partial/union semantic).
    func store(_ mode: LabelingMode) {
        defaults.set(mode.rawValue, forKey: Self.modeKey)
    }

    /// Clear the key (the settings page's reset face) — back to `.ask`.
    func reset() {
        defaults.removeObject(forKey: Self.modeKey)
    }
}
