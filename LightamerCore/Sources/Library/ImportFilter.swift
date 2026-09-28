import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// ImportFilter (Plan M2-2-2 T1) — the RAW-only gate at the import mouth.
// M2LIB-03's hardened ACs ①② live here and are machine-checked by
// ImportFilterTests; the反向 lesson is Alcedo 0.3.0's zero-filter import
// chain (files doubled by sidecars, junk formats in the grid).
//
// KD-1: ONE pure-function face, three consumers (the scan → the plan → the
// tests). Judgment ORDER is load-bearing:
//   ① hidden (dot-prefix name OR the macOS hidden flag — the ONLY
//     filesystem touch in this face) → `.hidden`
//   ② the HARDCODED sidecar-exclusion table on the LAST path extension →
//     `.sidecar` (never configurable — OQ-12: a configurable exclusion
//     list would let `.xmp` back in)
//   ③ the RAW whitelist on the LAST path extension, exact match,
//     case-insensitive → `.extensionNotWhitelisted` (including the
//     no-extension case: `pathExtension` is "")
//
// "LAST extension" is the documented contract: `photo.ARW.xmp`'s last
// extension is `xmp` → ② catches it before the whitelist ever sees "arw";
// a double-extension DISGUISE (`raw.xmp.arw`) passes by design — the
// requirement's semantics are last-extension-exact, pinned by test.
// ─────────────────────────────────────────────────────────────────────────────

/// One rejected candidate with its typed reason (the progress panel's and
/// the tests' assertion face).
public struct ImportRejection: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// Dot-prefixed name or the macOS hidden flag.
        case hidden
        /// Last path extension ∈ the HARDCODED sidecar table (never
        /// user-configurable — OQ-12).
        case sidecar
        /// Last path extension ∉ the whitelist (or no extension at all).
        case extensionNotWhitelisted
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

public enum ImportFilter {

    /// Split candidates into accepted RAWs and typed rejections (KD-1).
    /// `whitelist` defaults to the frozen LibrarySchema face; callers that
    /// honor the user-configurable host pass `ImportDefaults.resolvedWhitelist()`.
    public static func select(
        _ urls: [URL],
        whitelist: Set<String> = LibrarySchema.defaultRawExtensions
    ) -> (accepted: [URL], rejected: [ImportRejection]) {
        var accepted: [URL] = []
        var rejected: [ImportRejection] = []
        accepted.reserveCapacity(urls.count)
        for url in urls {
            if let reason = rejectReason(for: url, whitelist: whitelist) {
                rejected.append(ImportRejection(url: url, reason: reason))
            } else {
                accepted.append(url)
            }
        }
        return (accepted, rejected)
    }

    /// The single judgment face (order ①②③ above) — `nil` means accept.
    public static func rejectReason(
        for url: URL, whitelist: Set<String>
    ) -> ImportRejection.Reason? {
        // ① hidden: the dot-prefix convention OR the Finder hidden flag.
        if url.lastPathComponent.hasPrefix(".") { return .hidden }
        if let values = try? url.resourceValues(forKeys: [.isHiddenKey]),
           values.isHidden == true {
            return .hidden
        }
        // The LAST path extension, lowercased once — every downstream set
        // is stored lowercase-without-dot (LibrarySchema contract).
        let ext = url.pathExtension.lowercased()
        // ② hardcoded sidecar exclusion — BEFORE the whitelist, so a
        // configured whitelist can never re-admit a sidecar.
        if LibrarySchema.hardcodedSidecarExclusions.contains(ext) {
            return .sidecar
        }
        // ③ whitelist exact match ("" = no extension → not whitelisted).
        if whitelist.contains(ext) { return nil }
        return .extensionNotWhitelisted
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ImportMode / ImportModeChoice / ImportDefaults (KD-4) — the dialog's state
// face, Core-defined and injectable so tests construct everything directly.
// M2-1 D-EXEC-1 lesson: NO view body ever reads a static defaults singleton —
// the dialog reads THROUGH this face with an injected suite name.
// ─────────────────────────────────────────────────────────────────────────────

/// The three import transport modes (M2LIB-07 ①②③).
public enum ImportMode: String, Sendable, CaseIterable, Codable {
    case move
    case copy
    case link
}

/// The dialog's resolved choice (KD-4: a plain Codable struct, test-built).
public struct ImportModeChoice: Codable, Equatable, Sendable {
    public var mode: ImportMode
    public var remember: Bool

    public init(mode: ImportMode, remember: Bool) {
        self.mode = mode
        self.remember = remember
    }
}

/// The three UserDefaults keys (`library.import.*`) + the injectable suite
/// host (the CatalogRebuilder suite-NAME pattern: the name is Sendable, the
/// `UserDefaults` instance builds on access). Storage faces:
///   • `mode` — the remembered transport (only meaningful when remembered)
///   • `rememberMode` — whether the dialog's last choice persists (OQ-4)
///   • `rawExtensions` — the whitelist REPLACEMENT face (KD-1: replace,
///     never union — the settings page writes the full set)
public struct ImportDefaults: Sendable {

    public nonisolated static let modeKey = "library.import.mode"
    public nonisolated static let rememberModeKey = "library.import.rememberMode"
    public nonisolated static let rawExtensionsKey = "library.import.rawExtensions"

    /// nil = `.standard` (the app face); tests pass an isolated suite name.
    public let defaultsSuiteName: String?

    public init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: - Whitelist (the configurable host, OQ-12)

    /// The effective whitelist: the stored replacement set when present
    /// (normalized lowercase, dots trimmed, empties dropped), else the
    /// frozen default. The sidecar exclusion table NEVER reads config —
    /// `ImportFilter` hardwires it before this face.
    public func resolvedWhitelist() -> Set<String> {
        guard let stored = defaults.stringArray(forKey: Self.rawExtensionsKey) else {
            return LibrarySchema.defaultRawExtensions
        }
        let normalized = Set(
            stored.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
                .filter { !$0.isEmpty })
        return normalized.isEmpty ? LibrarySchema.defaultRawExtensions : normalized
    }

    /// The whitelist write face (the future settings page's host): stores
    /// the FULL replacement set (KD-1 replace-never-union semantics).
    public func setWhitelist(_ extensions: Set<String>) {
        defaults.set(extensions.sorted(), forKey: Self.rawExtensionsKey)
    }

    /// Convenience overload for literal construction in tests/callers.
    public func setWhitelist(_ extensions: [String]) {
        setWhitelist(Set(extensions))
    }

    // MARK: - Mode + remember (OQ-4: default = copy)

    /// The dialog's effective default: the remembered mode ONLY when the
    /// remember flag says so — otherwise `.copy` (a single-shot override
    /// with remember unchecked must never persist itself).
    public func resolvedMode() -> ImportMode {
        guard defaults.bool(forKey: Self.rememberModeKey) else { return .copy }
        guard let raw = defaults.string(forKey: Self.modeKey),
              let mode = ImportMode(rawValue: raw) else { return .copy }
        return mode
    }

    public var rememberMode: Bool {
        get { defaults.bool(forKey: Self.rememberModeKey) }
        set { defaults.set(newValue, forKey: Self.rememberModeKey) }
    }

    /// Persist the dialog's confirm (KD-4's single write face). remember =
    /// true → the mode rides along; remember = false → NOTHING persists
    /// (any stale remembered mode is dropped — the next dialog defaults to
    /// copy again, the "单次覆盖不落盘" contract).
    public func storeChoice(_ choice: ImportModeChoice) {
        guard choice.remember else {
            defaults.removeObject(forKey: Self.modeKey)
            defaults.set(false, forKey: Self.rememberModeKey)
            return
        }
        defaults.set(choice.mode.rawValue, forKey: Self.modeKey)
        defaults.set(true, forKey: Self.rememberModeKey)
    }

    /// Clear all three keys (the settings page's reset face, OQ-4).
    public func reset() {
        defaults.removeObject(forKey: Self.modeKey)
        defaults.removeObject(forKey: Self.rememberModeKey)
        defaults.removeObject(forKey: Self.rawExtensionsKey)
    }
}
