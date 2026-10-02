import LightamerCore
import XCTest

@testable import Lightamer

// ─────────────────────────────────────────────────────────────────────────────
// ExportMemoryKeysTests (Plan M2-9-04 T2, KD-5) — the quality-four memory
// keys (OQ-10) + the panel model's section-3/4 state faces:
//
//   • the registered key spellings (AC4: 键名拼写 = 登记值 — the constants
//     ARE the registration surface);
//   • the round-trip + the corrupt-value degrade over an ISOLATED suite
//     (an unset key ≠ a stored 0.0; out-of-domain/non-finite/foreign-type
//     values degrade to nil, never block the panel);
//   • the panel model defaults (AC2: 默认值对表 Alcedo — QML:27-46) and
//     the model-domain sizing guard (UI 按模型域禁越界值) + the assembly
//     input faces (makeSizing/makeFormat/makeMetadataPolicy).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ExportMemoryKeysTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "m2904-memory-keys-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - The registered spellings (AC4)

    func testQualityKeySpellingsMatchRegistration() {
        XCTAssertEqual(ExportState.jpegQualityKey, "export.jpegQuality")
        XCTAssertEqual(ExportState.heicQualityKey, "export.heicQuality")
        XCTAssertEqual(ExportState.avifQualityKey, "export.avifQuality")
        XCTAssertEqual(ExportState.webpQualityKey, "export.webpQuality")
        XCTAssertEqual(ExportState.lastDirectoryKey, "export.lastDirectory")
        // The kind → key map covers exactly the four lossy formats.
        XCTAssertEqual(Set(ExportState.qualityKeysByFormat.keys), ["jpeg", "heic", "avif", "webp"])
        XCTAssertEqual(ExportState.qualityKeysByFormat["jpeg"], ExportState.jpegQualityKey)
        XCTAssertEqual(ExportState.qualityKeysByFormat["heic"], ExportState.heicQualityKey)
        XCTAssertEqual(ExportState.qualityKeysByFormat["avif"], ExportState.avifQualityKey)
        XCTAssertEqual(ExportState.qualityKeysByFormat["webp"], ExportState.webpQualityKey)
    }

    // MARK: - The round-trip + degrade (OQ-10)

    func testQualityRoundTripAllFourFormats() {
        let state = ExportState(defaults: defaults)
        for (kind, key) in ExportState.qualityKeysByFormat.sorted(by: { $0.key < $1.key }) {
            XCTAssertNil(state.loadM2Quality(forKey: key), "\(kind) fresh = no memory")
            let value = 0.42
            state.storeM2Quality(value, forKey: key)
            XCTAssertEqual(state.loadM2Quality(forKey: key), value, "\(kind) round-trip")
        }
    }

    func testQualityZeroIsARealMemoryNotAnUnsetKey() {
        let state = ExportState(defaults: defaults)
        state.storeM2Quality(0.0, forKey: ExportState.jpegQualityKey)
        XCTAssertEqual(
            state.loadM2Quality(forKey: ExportState.jpegQualityKey), 0.0,
            "a stored 0.0 is a legitimate remembered value (the presence check)")
    }

    func testQualityDegradesOnOutOfRangeNonFiniteAndForeignTypes() {
        let state = ExportState(defaults: defaults)
        // Out of the 0...1 domain.
        state.storeM2Quality(1.5, forKey: ExportState.heicQualityKey)
        XCTAssertNil(state.loadM2Quality(forKey: ExportState.heicQualityKey))
        defaults.set(-0.1, forKey: ExportState.avifQualityKey)
        XCTAssertNil(state.loadM2Quality(forKey: ExportState.avifQualityKey))
        // A foreign value type (the corrupt-blob degrade face).
        defaults.set("garbage", forKey: ExportState.webpQualityKey)
        XCTAssertNil(state.loadM2Quality(forKey: ExportState.webpQualityKey))
        // The last-directory face: a foreign type degrades the same way.
        defaults.set(Data([0x01]), forKey: ExportState.lastDirectoryKey)
        XCTAssertNil(state.loadM2LastDirectory())
    }

    // MARK: - The panel model defaults (AC2 — Alcedo QML:27-46 对表)

    func testPanelModelDefaultsMatchAlcedo() {
        let model = ExportM2PanelModel()
        XCTAssertEqual(model.formatKind, .jpeg)
        XCTAssertEqual(model.jpegQuality, 0.95, "Alcedo 95/100 first use")
        XCTAssertFalse(model.hasQualityKnob == true && model.formatKind != .jpeg)
        XCTAssertEqual(model.sizingMode, .original)
        XCTAssertEqual(model.longEdgePx, 2048)
        XCTAssertEqual(model.boundsWidth, 2048)
        XCTAssertEqual(model.boundsHeight, 2048)
        XCTAssertEqual(model.physicalWidth, 210, accuracy: 0.0001)
        XCTAssertEqual(model.physicalHeight, 297, accuracy: 0.0001)
        XCTAssertEqual(model.physicalUnit, .millimeters)
        XCTAssertEqual(model.physicalDpi, 300)
        // OQ-11/OQ-12/OQ-6/OQ-7 defaults.
        XCTAssertFalse(model.subfolderEnabled)
        XCTAssertTrue(model.metadataOn)
        XCTAssertTrue(model.embedICC)
        XCTAssertFalse(model.allowUpscale)
        XCTAssertEqual(model.maximumEdgePixels, 0)
        XCTAssertTrue(model.canRun, "a fresh panel is runnable")
    }

    // MARK: - The model-domain sizing guard (KD-2 节 4)

    func testSizingViolationFollowsTheModelDomains() {
        let model = ExportM2PanelModel()
        XCTAssertFalse(model.sizingViolation, "original has no fields")

        model.sizingMode = .longEdge
        XCTAssertFalse(model.sizingViolation, "2048 in range")
        model.longEdgePx = 0
        XCTAssertTrue(model.sizingViolation, "px ≥ 1")
        model.longEdgePx = YiyinExportSettings.maxTargetPixels + 1
        XCTAssertTrue(model.sizingViolation, "px ≤ 100_000")
        model.longEdgePx = YiyinExportSettings.maxTargetPixels
        XCTAssertFalse(model.sizingViolation, "the cap itself is legal")

        model.sizingMode = .bounds
        model.boundsWidth = 1
        model.boundsHeight = 0
        XCTAssertTrue(model.sizingViolation)
        model.boundsHeight = 100_000
        XCTAssertFalse(model.sizingViolation)

        model.sizingMode = .physical
        model.physicalWidth = 0.009
        XCTAssertTrue(model.sizingViolation, "physical ≥ 0.01")
        model.physicalWidth = 210
        model.physicalDpi = 0
        XCTAssertTrue(model.sizingViolation, "dpi ≥ 1")
        model.physicalDpi = 2401
        XCTAssertTrue(model.sizingViolation, "dpi ≤ 2400 (the model domain, not Alcedo's 10k)")
        model.physicalDpi = 2400
        XCTAssertFalse(model.sizingViolation)

        // The advanced fold: 0 = off; negative violates.
        model.maximumEdgePixels = -1
        XCTAssertTrue(model.sizingViolation)
        model.maximumEdgePixels = 0
        XCTAssertFalse(model.sizingViolation)

        // The violation disables the run face (the shared gate).
        model.physicalDpi = 0
        XCTAssertFalse(model.canRun)
    }

    // MARK: - The assembly input faces (KD-4's panel half)

    func testMakeSizingMapsEveryMode() {
        let model = ExportM2PanelModel()
        XCTAssertEqual(model.makeSizing().mode, .original)

        model.sizingMode = .longEdge
        model.longEdgePx = 1280
        model.allowUpscale = true
        model.maximumEdgePixels = 8000
        let sizing = model.makeSizing()
        XCTAssertEqual(sizing.mode, .longEdge(px: 1280))
        XCTAssertTrue(sizing.allowUpscale)
        XCTAssertEqual(sizing.maximumEdgePixels, 8000)

        model.sizingMode = .bounds
        model.boundsWidth = 1600
        model.boundsHeight = 1200
        XCTAssertEqual(model.makeSizing().mode, .bounds(w: 1600, h: 1200))

        model.sizingMode = .physical
        model.physicalWidth = 8.5
        model.physicalHeight = 11
        model.physicalUnit = .inches
        model.physicalDpi = 600
        XCTAssertEqual(
            model.makeSizing().mode,
            .physical(width: 8.5, height: 11, unit: .inches, dpi: 600))
    }

    func testMakeFormatMapsTheSixKindsWithTheirKnobs() {
        let model = ExportM2PanelModel()
        model.jpegQuality = 0.8
        XCTAssertEqual(model.makeFormat(), .jpeg(quality: 0.8))

        model.formatKind = .png
        model.pngBitDepth = .sixteen
        XCTAssertEqual(model.makeFormat(), .png(bitDepth: .sixteen))
        XCTAssertFalse(model.hasQualityKnob, "PNG has no quality knob")
        XCTAssertNil(model.qualityMemoryWriteback, "no knob → no write-back")

        model.formatKind = .tiff
        model.tiffBitDepth = .float32
        model.tiffCompression = .lzw
        XCTAssertEqual(model.makeFormat(), .tiff(bitDepth: .float32, compression: .lzw))

        model.formatKind = .heic
        model.heicQuality = 0.7
        model.heicBitDepth = .ten
        XCTAssertEqual(model.makeFormat(), .heic(quality: 0.7, bitDepth: .ten))

        model.formatKind = .avif
        model.avifQuality = 0.6
        model.avifBitDepth = .twelve
        XCTAssertEqual(model.makeFormat(), .avif(quality: 0.6, bitDepth: .twelve))

        model.formatKind = .webp
        model.webpQuality = 0.5
        model.webpLossless = true
        XCTAssertEqual(model.makeFormat(), .webp(quality: 0.5, lossless: true))
    }

    func testActiveQualityBindsThePerFormatKnobAndMemory() {
        let state = ExportState(defaults: defaults)
        let model = ExportM2PanelModel()
        // The per-format knobs stay separate (OQ-10 A: no cross-kind bleed).
        model.jpegQuality = 0.9
        model.formatKind = .avif
        XCTAssertEqual(model.activeQuality, model.avifQuality)
        model.activeQuality = 0.55
        XCTAssertEqual(model.avifQuality, 0.55)
        XCTAssertEqual(model.jpegQuality, 0.9, "the JPEG knob untouched")

        // The write-back face lands on the kind's own registered key.
        let writeback = model.qualityMemoryWriteback
        XCTAssertEqual(writeback?.key, ExportState.avifQualityKey)
        XCTAssertEqual(writeback?.value, 0.55)
        state.storeM2Quality(writeback!.value, forKey: writeback!.key)
        XCTAssertEqual(state.loadM2Quality(forKey: ExportState.avifQualityKey), 0.55)
    }

    func testMakeMetadataPolicyMapsTheSingleSwitch() {
        let model = ExportM2PanelModel()
        let standard = model.makeMetadataPolicy()
        XCTAssertEqual(standard.mode, .standard)
        XCTAssertTrue(standard.includeExif)
        XCTAssertTrue(standard.includeXMP)
        XCTAssertTrue(standard.includeIPTC)
        XCTAssertFalse(standard.includeLocation, "the fixed strip stays (OQ-6)")
        XCTAssertFalse(standard.includeSerials)
        XCTAssertFalse(
            standard.includeEditingHistory,
            "the editing-summary packet stays unmounted by default (OQ-6 收窄)")

        model.metadataOn = false
        XCTAssertEqual(model.makeMetadataPolicy().mode, .none)
    }

    func testMakeVariantCarriesPolicyIntoTheVariant() {
        let model = ExportM2PanelModel()
        model.formatKind = .heic
        model.embedICC = false
        let variant = model.makeVariant()
        XCTAssertEqual(variant.format.formatName, "heic")
        XCTAssertFalse(variant.embedICC)
        XCTAssertEqual(variant.metadataPolicy.mode, .standard)
        XCTAssertNil(variant.drtOutput, "the DRT record rides the assembly (T3), not the panel")
    }
}
