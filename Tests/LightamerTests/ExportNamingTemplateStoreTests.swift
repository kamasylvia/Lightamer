import Foundation
@testable import Lightamer
import LightamerCore
import XCTest

/// M2-9-01 T4 — the naming-template preset store (OQ-9 A / KD-4): the
/// three built-in spellings pinned against the Alcedo QML, the CRUD
/// round-trip over an isolated UserDefaults suite, and the corrupt-storage
/// degrade. The built-ins are NEVER persisted; the store reads only the
/// injected defaults (the M2-1 D-EXEC-1 injection discipline).
final class ExportNamingTemplateStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "m2901-naming-templates-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The built-in spellings ARE the Alcedo QML:35-52 surface — the three
    /// patterns byte-identical, `isBuiltIn` set, stable ids.
    func testBuiltInSpellingsMatchAlcedo() {
        let builtIns = NamingTemplateStore.builtIns
        XCTAssertEqual(builtIns.count, 3)
        XCTAssertEqual(builtIns[0].name, "Source")
        XCTAssertEqual(builtIns[0].pattern, "{source}")
        XCTAssertEqual(builtIns[1].name, "Date + No.")
        XCTAssertEqual(builtIns[1].pattern, "{date:yyyy MM dd}-{sequence:0000}")
        XCTAssertEqual(builtIns[2].name, "Custom + No.")
        XCTAssertEqual(builtIns[2].pattern, "Export-{sequence:0000}")
        XCTAssertTrue(builtIns.allSatisfy(\.isBuiltIn))
        XCTAssertEqual(Set(builtIns.map(\.id)).count, 3, "stable distinct ids")
    }

    /// Fresh storage: nothing persisted, the UI list = exactly the
    /// built-ins.
    func testFreshStorageIsBuiltInsOnly() {
        let store = NamingTemplateStore(defaults: defaults)
        XCTAssertTrue(store.loadTemplates().isEmpty)
        XCTAssertEqual(store.allTemplates(), NamingTemplateStore.builtIns)
        XCTAssertNil(defaults.data(forKey: NamingTemplateStore.storageKey))
    }

    /// Add → allTemplates carries the user entry AFTER the built-ins; the
    /// stored array itself never contains a built-in.
    func testAddRoundTrip() {
        let store = NamingTemplateStore(defaults: defaults)
        let added = store.add(name: "My preset", pattern: "{source}-{sequence:00}")
        XCTAssertFalse(added.isBuiltIn)

        let stored = store.loadTemplates()
        XCTAssertEqual(stored, [added])
        XCTAssertEqual(store.allTemplates().count, 4)
        XCTAssertEqual(store.allTemplates().last?.id, added.id)

        // The persisted payload contains ONLY user templates (a corrupted
        // built-in smuggling attempt filters out on load).
        let raw = try! JSONDecoder().decode(
            [NamingTemplate].self,
            from: defaults.data(forKey: NamingTemplateStore.storageKey)!)
        XCTAssertEqual(raw, [added])

        // save() with a built-in inside still stores user-only.
        var withBuiltin = store.loadTemplates()
        withBuiltin.append(NamingTemplateStore.builtIns[0])
        store.save(withBuiltin)
        XCTAssertEqual(store.loadTemplates(), [added],
                       "built-ins never persist")
    }

    /// rename = the Alcedo replacedName semantics (name overwritten in
    /// place); unknown ids are a no-op; remove drops exactly the target.
    func testRenameAndRemoveRoundTrip() {
        let store = NamingTemplateStore(defaults: defaults)
        let first = store.add(name: "A", pattern: "{source}")
        let second = store.add(name: "B", pattern: "{iso}")

        store.rename(id: first.id, to: "Renamed")
        let renamed = store.loadTemplates()
        XCTAssertEqual(renamed.first?.name, "Renamed")
        XCTAssertEqual(renamed.first?.pattern, "{source}", "the pattern is untouched")
        XCTAssertEqual(renamed.last?.name, "B")

        store.rename(id: UUID(), to: "ghost")
        XCTAssertEqual(store.loadTemplates().count, 2, "unknown-id rename is a no-op")
        store.rename(id: NamingTemplateStore.builtIns[0].id, to: "nope")
        XCTAssertEqual(store.loadTemplates().count, 2, "built-in ids never rename")

        store.remove(id: first.id)
        XCTAssertEqual(store.loadTemplates().map(\.name), ["B"])
        store.remove(id: UUID())
        XCTAssertEqual(store.loadTemplates().map(\.name), ["B"], "unknown-id remove is a no-op")

        // Full clear → back to the built-ins-only face.
        store.removeAll()
        XCTAssertTrue(store.loadTemplates().isEmpty)
        XCTAssertEqual(store.allTemplates(), NamingTemplateStore.builtIns)
    }

    /// A corrupt JSON blob degrades to an EMPTY library (never blocks the
    /// panel); the next save overwrites the corruption.
    func testCorruptStorageDegradesToEmpty() {
        let store = NamingTemplateStore(defaults: defaults)
        defaults.set(Data("not json at all".utf8), forKey: NamingTemplateStore.storageKey)
        XCTAssertTrue(store.loadTemplates().isEmpty, "corrupt blob → empty library")
        XCTAssertEqual(store.allTemplates(), NamingTemplateStore.builtIns)

        // Recovery: the next save repairs the storage.
        let added = store.add(name: "post-corruption", pattern: "{source}")
        XCTAssertEqual(store.loadTemplates(), [added])

        // The wrong-shape blob (valid JSON, wrong type) degrades too.
        defaults.set(Data("[1,2,3]".utf8), forKey: NamingTemplateStore.storageKey)
        XCTAssertTrue(store.loadTemplates().isEmpty)
    }

    /// The registered key spelling is pinned (source-constant single
    /// source — the AC grep face).
    func testStorageKeySpelling() {
        XCTAssertEqual(NamingTemplateStore.storageKey, "export.namingTemplates")
    }
}
