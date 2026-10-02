import Foundation
import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// NamingTemplateStore — the OQ-9 naming-template preset store (Plan M2-9-01
// T4, KD-4). App-layer by design (KD-3): the MODEL lives in Core
// (`NamingTemplate`), the PERSISTENCE lives here — UserDefaults JSON array
// under `export.namingTemplates` (the registered spelling; AGENTS.md's key
// registry gets the batch registration in M2-9-05).
//
// Faces (the Alcedo ExportNamingEditor surface):
//   • THREE built-in constants (the QML:35-52 spellings) that are NEVER
//     persisted — the UI concatenates them ahead of the stored list, so a
//     factory reset is automatic and the built-ins can't drift in storage;
//   • user presets: save (full-replacement write-back) / rename (the
//     Alcedo replacedName semantics — renaming overwrites the name in
//     place) / remove;
//   • corrupt storage degrades to an EMPTY library (a bad JSON blob never
//     blocks the panel).
//
// Injection discipline (M2-1 D-EXEC-1 / the ImportDefaults convention): the
// store reads ONLY the injected `UserDefaults` — no `.standard` reach-ins
// inside methods; the default init passes `.standard` as the app face and
// tests pass an isolated suite.
// ─────────────────────────────────────────────────────────────────────────────

struct NamingTemplateStore {

    /// The registered storage key (the ONLY spelling).
    nonisolated static let storageKey = "export.namingTemplates"

    /// The three built-in presets (the Alcedo QML spellings, patterns
    /// byte-identical to `ExportNamingEditor.qml:37-40`; labels are the QML
    /// `qsTr` sources). Stable per-process ids (the UI's selection anchors;
    /// the trailing index keeps them distinguishable).
    nonisolated static let builtIns: [NamingTemplate] = [
        NamingTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Source", pattern: "{source}", isBuiltIn: true),
        NamingTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Date + No.", pattern: "{date:yyyy MM dd}-{sequence:0000}",
            isBuiltIn: true),
        NamingTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Custom + No.", pattern: "Export-{sequence:0000}", isBuiltIn: true),
    ]

    private let defaults: UserDefaults

    /// The app face passes `.standard` (the default); tests pass an
    /// isolated-suite instance (no process-global mutation).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Read

    /// The stored user presets (empty when the key is unset or UNPARSEABLE
    /// — a corrupt blob degrades, never blocks). Built-ins are NEVER in the
    /// stored array; any sneaking in are filtered out on load.
    func loadTemplates() -> [NamingTemplate] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        guard let stored = try? JSONDecoder().decode([NamingTemplate].self, from: data)
        else { return [] }
        return stored.filter { !$0.isBuiltIn }
    }

    /// The full UI list: the three built-ins ahead of the stored user
    /// presets.
    func allTemplates() -> [NamingTemplate] {
        Self.builtIns + loadTemplates()
    }

    // MARK: - Write (full-replacement semantics)

    /// Persist the whole user list (the write-back face — callers mutate a
    /// `loadTemplates()` result and save it wholesale).
    func save(_ templates: [NamingTemplate]) {
        let userOnly = templates.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(userOnly) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Add a user preset (fresh UUID, `isBuiltIn` false) and persist.
    func add(name: String, pattern: String) -> NamingTemplate {
        let template = NamingTemplate(name: name, pattern: pattern)
        var templates = loadTemplates()
        templates.append(template)
        save(templates)
        return template
    }

    /// The Alcedo replacedName semantics: renaming OVERWRITES the name in
    /// place (an upsert on id). Unknown ids are a no-op.
    func rename(id: UUID, to newName: String) {
        var templates = loadTemplates()
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].name = newName
        save(templates)
    }

    /// Remove a user preset (unknown ids are a no-op). A built-in id is
    /// never in storage — removing one is a no-op by construction.
    func remove(id: UUID) {
        var templates = loadTemplates()
        templates.removeAll { $0.id == id }
        save(templates)
    }

    /// Clear every stored user preset (the reset face — the built-ins stay,
    /// they were never stored).
    func removeAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
