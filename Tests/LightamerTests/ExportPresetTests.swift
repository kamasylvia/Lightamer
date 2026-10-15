@testable import Lightamer
@testable import LightamerCore
import Foundation
import XCTest

/// ExportPresetTests (V2M-02 T5, EXPORT-PRESET-01) — the named preset
/// layer's state-layer pins: ① store round-trip with the built-ins never
/// persisting, ② the apply projection landing the :401 capture face while
/// the collision tier and the gain-map flag stay untouched (the M-5 pin —
/// a preset can never silently open the cross-session collision memory),
/// ③ the typed degrade arms (a hanging naming-template reference falls
/// back; a corrupt variant falls back WHOLE — no partial application),
/// ④ corrupt storage degrading to an empty library + built-in remove
/// being a no-op.
@MainActor
final class ExportPresetTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "export-preset-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// A preset face worth capturing: non-defaults in every captured leg.
    private var face: ExportPresetPanelFace {
        var f = ExportM2PanelModel.defaultFace
        f.formatKind = .heic
        f.heicQuality = 0.8
        f.heicBitDepth = .ten
        f.sizingMode = .longEdge
        f.longEdgePx = 4096
        f.allowUpscale = true
        f.maximumEdgePixels = 100_000
        f.metadataOn = false
        f.embedICC = false
        f.namingPattern = "{date:yyyy}-{sequence:000}"
        return f
    }

    // MARK: ① store round-trip

    func testPresetRoundTripsThroughStoreAndBuiltInsNeverPersist() throws {
        let store = ExportPresetStore(defaults: defaults)
        XCTAssertEqual(store.loadPresets(), [], "a fresh suite starts empty")
        XCTAssertEqual(store.allPresets().count, ExportPresetStore.builtIns.count)

        let preset = ExportPresetProjector.capture(name: "web set", from: face)
        store.save(preset)

        let loaded = store.loadPresets()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], preset, "the round-trip is byte-faithful")
        XCTAssertEqual(store.allPresets().count, ExportPresetStore.builtIns.count + 1)

        // The built-ins are NEVER in the stored array (a factory reset is
        // automatic; a sneaking stored built-in filters out on load).
        var tampered = loaded
        tampered.append(ExportPresetStore.builtIns[0])
        defaults.set(try JSONEncoder().encode(tampered), forKey: ExportPresetStore.storageKey)
        XCTAssertEqual(store.loadPresets().count, 1, "stored built-ins filter out")
    }

    // MARK: ② the apply projection

    func testApplyProjectsCapturedFieldsAndLeavesSessionStateAlone() throws {
        let model = ExportM2PanelModel()
        // Non-default session state the preset must NOT touch.
        model.collisionPolicy = .fail
        model.gainMapHDR = true

        let preset = ExportPresetProjector.capture(name: "p", from: face)
        model.applyPreset(preset)

        // The :401 capture face lands field by field.
        XCTAssertEqual(model.formatKind, .heic)
        XCTAssertEqual(model.heicQuality, 0.8, accuracy: 1e-12)
        XCTAssertEqual(model.heicBitDepth, .ten)
        XCTAssertEqual(model.sizingMode, .longEdge)
        XCTAssertEqual(model.longEdgePx, 4096)
        XCTAssertTrue(model.allowUpscale)
        XCTAssertEqual(model.maximumEdgePixels, 100_000)
        XCTAssertFalse(model.metadataOn)
        XCTAssertFalse(model.embedICC)
        XCTAssertEqual(model.pattern, "{date:yyyy}-{sequence:000}")

        // The M-5 pin: the collision tier is OUTSIDE the capture face — a
        // preset application can never open the cross-session memory the
        // M3-1-03 KD-1 ruling declined. The gain-map flag rides the same
        // structural exclusion (not in the :401 list).
        XCTAssertEqual(model.collisionPolicy, .fail, "the tier is session state")
        XCTAssertTrue(model.gainMapHDR, "the flag is outside the capture face")
    }

    // MARK: ③ the typed degrade arms

    func testApplyDegradesHangingTemplateAndCorruptVariant() throws {
        // A hanging template reference: the pattern fails the page's parse
        // gate → the first built-in pattern (the NamingTemplateStore
        // fallback precedent), everything else lands.
        var hanging = ExportPresetProjector.capture(name: "h", from: face)
        hanging.namingPattern = "{nonexistent_token} \("bad")"
        let model = ExportM2PanelModel()
        model.applyPreset(hanging)
        XCTAssertEqual(
            model.pattern, NamingTemplateStore.builtIns[0].pattern,
            "a hanging template degrades to the first built-in")
        XCTAssertEqual(model.formatKind, .heic, "the valid legs still land")

        // A corrupt variant (an out-of-domain quality) degrades the WHOLE
        // face — a partial application is the dishonest middle state.
        var corrupted = ExportPresetProjector.capture(name: "c", from: face)
        corrupted.variant.format = .jpeg(quality: 7.5)
        let fresh = ExportM2PanelModel()
        fresh.applyPreset(corrupted)
        XCTAssertEqual(fresh.face, ExportM2PanelModel.defaultFace,
                       "a corrupt preset falls back whole")
    }

    // MARK: ④ corrupt storage + built-in remove

    func testCorruptStorageDegradesAndBuiltInRemoveIsNoOp() throws {
        defaults.set(Data("not json".utf8), forKey: ExportPresetStore.storageKey)
        let store = ExportPresetStore(defaults: defaults)
        XCTAssertEqual(
            store.loadPresets(), [],
            "a corrupt blob degrades to an empty library, never blocks")

        // remove(built-in id) is a no-op and never corrupts the user list.
        let preset = ExportPresetProjector.capture(name: "u", from: face)
        store.save(preset)
        store.remove(id: ExportPresetStore.builtIns[0].id)
        XCTAssertEqual(store.loadPresets().map(\.name), ["u"])
        XCTAssertEqual(
            store.allPresets().count, ExportPresetStore.builtIns.count + 1,
            "the built-ins stay anchored after a no-op remove")

        // rename lands in place; remove(user) works.
        store.rename(id: preset.id, to: "renamed")
        XCTAssertEqual(store.loadPresets().map(\.name), ["renamed"])
        store.remove(id: preset.id)
        XCTAssertEqual(store.loadPresets(), [])
    }
}
