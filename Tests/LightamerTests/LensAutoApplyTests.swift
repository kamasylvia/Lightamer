@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import XCTest

/// LensAutoApplyTests (Plan LENS-02 T2, D-LENS-1) — the opt-in auto-apply
/// for raster documents.
///
/// The EFFECTIVE DOMAIN is `embeddedGeometry == .notApplicable` ONLY: the
/// detected/unknown/nil judgments are the hard guard and never
/// auto-trigger, regardless of the switch. The read is injected (KD-4) —
/// tests replace `LensModule.autoApplyReader`; the UserDefaults face
/// defaults to FALSE on a missing key.
final class LensAutoApplyTests: XCTestCase {

    override func tearDown() {
        LensfunStore.uninstall()
        super.tearDown()
    }

    private func makeImage(
        embedded: EmbeddedGeometryState?, lensModel: String? = "E 16mm f/2.8"
    ) -> DecodedImage {
        var cap = CaptureMetadata()
        cap.lensModel = lensModel
        cap.focalLength = 16
        return DecodedImage(
            ciImage: CIImage.empty(), rawTech: RAWTechnicalParams(), capture: cap,
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: nil,
            embeddedGeometry: embedded)
    }

    func testEffectiveDomainTable() async {
        let module = LensModule()

        // ON + notApplicable + lens EXIF → the ONLY auto-trigger shape.
        module.autoApplyReader = { true }
        var p = await module.reloadDefaults(image: makeImage(embedded: .notApplicable))
        XCTAssertEqual(p.source, .lensfun)

        // ON + detected → hard guard (never auto-trigger).
        p = await module.reloadDefaults(image: makeImage(embedded: .detected))
        XCTAssertEqual(p.source, .off)
        // ON + unknown → hard guard.
        p = await module.reloadDefaults(image: makeImage(embedded: .unknown))
        XCTAssertEqual(p.source, .off)
        // ON + nil judgment (pre-batch) → not the effective domain.
        p = await module.reloadDefaults(image: makeImage(embedded: nil))
        XCTAssertEqual(p.source, .off)

        // ON + notApplicable but NO lens EXIF → no trigger.
        p = await module.reloadDefaults(image: makeImage(embedded: .notApplicable, lensModel: nil))
        XCTAssertEqual(p.source, .off)

        // OFF → never (the default-opt-in face).
        module.autoApplyReader = { false }
        p = await module.reloadDefaults(image: makeImage(embedded: .notApplicable))
        XCTAssertEqual(p.source, .off)
    }

    func testInjectedReaderConsumedOncePerReload() async {
        let module = LensModule()
        var reads = 0
        module.autoApplyReader = { reads += 1; return false }
        _ = await module.reloadDefaults(image: makeImage(embedded: .notApplicable))
        XCTAssertEqual(reads, 1, "the injected reader is the single consumption point")
    }

    func testUserDefaultsFaceDefaultsFalse() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "lens-autoapply-tests"))
        suite.removeObject(forKey: LensAutoApplySetting.defaultsKey)
        defer { suite.removeObject(forKey: LensAutoApplySetting.defaultsKey) }
        // Missing key = FALSE (the default-opt-in contract).
        XCTAssertFalse(LensAutoApplySetting.read(suite))
        // The write/read round trip.
        LensAutoApplySetting.write(true, suite)
        XCTAssertTrue(LensAutoApplySetting.read(suite))
        LensAutoApplySetting.write(false, suite)
        XCTAssertFalse(LensAutoApplySetting.read(suite))
    }

    func testDefaultsKeyRegisteredSpelling() {
        // The ledger-pinned spelling (single declaration).
        XCTAssertEqual(LensAutoApplySetting.defaultsKey, "lensfun.autoApply")
    }
}
