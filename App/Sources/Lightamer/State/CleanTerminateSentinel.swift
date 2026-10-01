import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CleanTerminateSentinel (Plan M2-8-2 T4, KD-6; OQ-9-A) — the crash-detection
// DOUBLE-FLIP sentinel: the minimal recovery face over the structural safety
// the 2s debounce + tmp-promote + flushNow already deliver (D-M2-8-CONTEXT-9:
// no journal, no per-image recovery bar — ONE global toast).
//
// PROTOCOL (the order is load-bearing):
//   • launch (the assembly root, ONCE): read the stored value → the toast
//     decision → then set `true` (= this session is running);
//   • termination: `flushForTermination`'s bounded wait returns FIRST, THEN
//     the flag clears to `false` (= clean) — a kill inside the flush window
//     leaves `true`, which is exactly the unclean case the next launch
//     reports.
//
// STORAGE (L036 + the AppPreferences precedent): the suite name is the
// Sendable injectable (tests pass an isolated suite; the app face passes
// nil = `.standard`). The assembly root reads/writes ONCE — no view body
// ever touches defaults.
// ─────────────────────────────────────────────────────────────────────────────

/// The sentinel's pure core (the CleanTerminateSentinelTests truth table):
/// a stored `true` = the last session never cleared the flag = unclean.
/// `false` = the last session terminated clean. `nil` = first launch —
/// silent (never a false alarm).
enum CleanTerminateSentinel {

    /// The registered UserDefaults key.
    nonisolated static let key = "app.cleanTerminate"

    /// The launch-time verdict: `stored == true` (nil folds to false).
    static func uncleanTermination(stored: Bool?) -> Bool {
        stored == true
    }

    /// The one-shot toast copy (the OQ-9-A wording — the loss upper bound
    /// is the 2s debounce window).
    static let toastCopy: String = String(
        localized: "toast_unclean_terminate",
        defaultValue:
            "The last session quit unexpectedly — edits were auto-saved (at most the last few seconds were lost).")
}

/// The storage shell (the AppPreferences injectable-suite shape): the
/// assembly root holds ONE instance; the launch and termination legs read
/// and write through it.
struct CleanTerminateSentinelStore: Sendable {

    /// nil = `.standard` (the app face); tests pass an isolated suite name.
    let defaultsSuiteName: String?

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The launch leg: read the PREVIOUS session's verdict, then mark THIS
    /// session running. Returns `uncleanTermination(stored:)`.
    @discardableResult
    func consumeAtLaunch() -> Bool {
        let stored = defaults.object(forKey: CleanTerminateSentinel.key) as? Bool
        defaults.set(true, forKey: CleanTerminateSentinel.key)
        return CleanTerminateSentinel.uncleanTermination(stored: stored)
    }

    /// The termination leg: the flush's bounded wait has returned — clear
    /// the flag (the clean exit).
    func markClean() {
        defaults.set(false, forKey: CleanTerminateSentinel.key)
    }

    /// The test/reset face.
    func reset() {
        defaults.removeObject(forKey: CleanTerminateSentinel.key)
    }
}
