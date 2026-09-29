import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// AppPreferences (Plan M2-3-3 T5, KD-5) — the Settings pages' preference-key
// host: the Default Behavior mask-draw three-choice, the Keyboard default
// keymap + override store and the pure conflict detector.
//
// Conventions follow the Core `ImportDefaults` precedent: the suite name is
// the Sendable injectable (tests pass an isolated suite; the app face passes
// nil = `.standard`), every key is a registered nonisolated constant and a
// reset face clears the family. The M2-1 D-EXEC-1 lesson holds: NO view body
// reads a static defaults singleton — pages read THROUGH an injected
// instance.
//
// Scope boundary (KD-5): v1 STORES the mask-draw choice (M2-7 consumes it —
// 本 plan 只存不接线) and the Keyboard page is show/detect/restore only —
// NO live rebinding (the CONTEXT Deferred Ideas wording); the override store
// exists so the restore face and the M2-x rebinding work share ONE storage
// contract.
// ─────────────────────────────────────────────────────────────────────────────

/// The mask-draw default behavior (KD-5 three-choice; the M2-7 mask toolbar
/// consumes it when the user finishes a drawn mask).
enum MaskDrawBehavior: String, CaseIterable, Sendable {
    /// Ask on every completed mask stroke (the default).
    case ask
    /// Always create a new adjustment layer.
    case newLayer
    /// Always draw into the current node's mask.
    case currentNode
}

struct AppPreferences: Sendable {

    /// The Default Behavior mask-draw key (registered spelling; M2-7 reads
    /// the same one).
    nonisolated static let maskBehaviorKey = "mask.behavior.default"

    /// The Keyboard override key prefix — full key = prefix + command id.
    nonisolated static let keyboardOverrideKeyPrefix = "keyboard.override."

    /// nil = `.standard` (the app face); tests pass an isolated suite name.
    let defaultsSuiteName: String?

    init(defaultsSuiteName: String? = nil) {
        self.defaultsSuiteName = defaultsSuiteName
    }

    private var defaults: UserDefaults {
        defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: - Default Behavior (mask draw)

    /// The stored mask-draw default; unset/unparseable = `.ask` (the honest
    /// ask-every-time default). The setter is `nonmutating` on purpose: it
    /// writes straight through UserDefaults and touches no stored property,
    /// so pages holding the struct by value can still persist choices.
    var maskDrawBehavior: MaskDrawBehavior {
        get {
            defaults
                .string(forKey: Self.maskBehaviorKey)
                .flatMap(MaskDrawBehavior.init(rawValue:)) ?? .ask
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.maskBehaviorKey) }
    }

    func resetMaskDrawBehavior() {
        defaults.removeObject(forKey: Self.maskBehaviorKey)
    }

    // MARK: - Keyboard (the v1 override store — see the file header)

    /// The stored override for a command id (nil = the default keymap value
    /// stands; v1 never WRITES overrides — the store serves the restore face
    /// and the M2-x rebinding work).
    func keyboardOverride(for id: MenuCommandID) -> SettingsKeyCombo? {
        guard let raw = defaults.string(forKey: Self.keyboardOverrideKeyPrefix + id.rawValue)
        else { return nil }
        return SettingsKeyCombo(persisted: raw)
    }

    func setKeyboardOverride(_ combo: SettingsKeyCombo?, for id: MenuCommandID) {
        let key = Self.keyboardOverrideKeyPrefix + id.rawValue
        guard let combo else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(combo.persisted, forKey: key)
    }

    /// True when at least one override is stored (the restore button's
    /// visibility face — hidden with nothing to restore, 零假开关).
    var hasKeyboardOverrides: Bool {
        MenuCommandID.allCases.contains { keyboardOverride(for: $0) != nil }
    }

    /// Clear every override (the Keyboard page's restore face).
    func resetKeyboardOverrides() {
        for id in MenuCommandID.allCases {
            defaults.removeObject(forKey: Self.keyboardOverrideKeyPrefix + id.rawValue)
        }
    }
}

// MARK: - Keyboard keymap + conflict detection

/// One normalized keyboard combo (key character + modifier flags). The
/// Keyboard page's table row value and the conflict detector's grouping key.
struct SettingsKeyCombo: Equatable, Sendable {
    /// The key character (uppercased — the conflict face is case-normalized).
    let key: String
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool

    init(
        _ key: String, command: Bool = false, shift: Bool = false,
        option: Bool = false, control: Bool = false
    ) {
        self.key = key.uppercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// The display/normalize face: modifiers in fixed ⌃⌥⇧⌘ order + the key
    /// (two combos with equal `normalized` strings are ONE physical binding).
    var normalized: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "")
            + (command ? "⌘" : "") + key
    }

    /// The persisted form (`⌃⌥⇧⌘` + key — the same normalized spelling; the
    /// store keeps human-readable values on purpose).
    var persisted: String { normalized }

    /// The parse face for `keyboardOverride(for:)`.
    init?(persisted: String) {
        var control = false, option = false, shift = false, command = false
        var key = ""
        for character in persisted {
            switch character {
            case "⌃": control = true
            case "⌥": option = true
            case "⇧": shift = true
            case "⌘": command = true
            default: key.append(character)
            }
        }
        guard !key.isEmpty else { return nil }
        self.init(key, command: command, shift: shift, option: option, control: control)
    }
}

/// The default keymap over the `MenuCommandID` set — the Keyboard page's
/// display table. v1: the LIVE bindings stay owned by LightamerApp's
/// CommandMenus (declared inline); this table MIRRORS them for the
/// show/detect faces. Drift risk is bounded by the pin test (specific
/// combos asserted per menu declaration).
enum DefaultKeymap {

    /// The default combo for a command id (nil = the menu declares no
    /// shortcut for it — the row shows "—").
    static func combo(for id: MenuCommandID) -> SettingsKeyCombo? {
        switch id {
        // The Session dead routes (gate=true only; keymap mirrors the menu).
        case .sessionNew: SettingsKeyCombo("n", command: true, shift: true)
        case .sessionOpen: SettingsKeyCombo("o", command: true, shift: true)
        case .sessionClose: SettingsKeyCombo("w", command: true, shift: true)
        case .sessionImport: nil
        // The project face (M2-2-2).
        case .projectNew: SettingsKeyCombo("n", command: true)
        case .projectOpen: SettingsKeyCombo("o", command: true, option: true)
        case .projectRecent: nil
        case .projectImportFolder: SettingsKeyCombo("i", command: true, shift: true)
        case .projectBackup: nil
        case .projectMove: nil
        // The two-workspace circuit (M2-3-1).
        case .workspaceEnterEditor: SettingsKeyCombo("e", command: true)
        case .workspaceBackToLibrary: SettingsKeyCombo("w", command: true)
        case .librarySearch: SettingsKeyCombo("f", command: true)
        // The editor-shell visibility toggles (no shortcuts in the menu).
        case .viewToolRail, .viewScopes, .viewAdjustmentStack: nil
        }
    }
}

/// The pure conflict detector (the Keyboard page's highlight face): groups
/// the effective combos (default ⊕ override) by their normalized spelling
/// and keeps the groups holding two or more ids. Nil combos (unbound
/// commands) never conflict.
enum KeyboardConflictDetector {

    /// The conflict map: normalized combo → the command ids sharing it
    /// (only groups of ≥2 are returned; an empty result = a clean keymap).
    static func conflicts(
        default defaultCombo: (MenuCommandID) -> SettingsKeyCombo?,
        override overrideCombo: (MenuCommandID) -> SettingsKeyCombo?
    ) -> [String: [MenuCommandID]] {
        var grouped: [String: [MenuCommandID]] = [:]
        for id in MenuCommandID.allCases {
            guard let combo = overrideCombo(id) ?? defaultCombo(id) else { continue }
            grouped[combo.normalized, default: []].append(id)
        }
        return grouped.filter { $0.value.count > 1 }
    }

    /// Convenience overload for plain tables (tests / the page's snapshot
    /// face).
    static func conflicts(
        _ entries: [(id: MenuCommandID, combo: SettingsKeyCombo?)]
    ) -> [String: [MenuCommandID]] {
        var grouped: [String: [MenuCommandID]] = [:]
        for (id, combo) in entries {
            guard let combo else { continue }
            grouped[combo.normalized, default: []].append(id)
        }
        return grouped.filter { $0.value.count > 1 }
    }
}
