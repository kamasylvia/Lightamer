@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import XCTest

/// LensMatchHardeningTests (Plan LENS-01 T3, D-LENS-4 / X4) — the crop
/// gate comes ALIVE (the pre-T3 resolveCommitted passed nil/nil/1.0, so
/// the 0.96 gate never bit), the ≥60 threshold tier (40 word-overlap
/// loses its auto-selection qualification), the RawLab ambiguity refusal
/// (top-score ties REJECTED, never guessed), the camera-crop priority
/// chain baked at reloadDefaults (35mm derivation > unique camera hit >
/// nil→1.0), the resolve crop argument = the CAMERA imageCrop (review m5
/// regression), and the params-additive zero-drift negative.
final class LensMatchHardeningTests: XCTestCase {

    // MARK: - Fixtures (hermetic inline XML)

    /// APS-C calibration set (cropfactor 1.622 — the canon24 subset twin).
    static let apscXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Canon</maker>
                <model>Canon EF-S 24mm f/2.8 STM</model>
                <mount>Canon EF-S</mount>
                <cropfactor>1.622</cropfactor>
                <calibration>
                    <distortion model="poly3" focal="24" k1="-0.00902"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    static let sonyXML = """
        <lensdatabase version="1">
            <camera>
                <maker>Sony</maker>
                <model>ILCE-7M4</model>
                <mount>Sony E</mount>
                <cropfactor>1</cropfactor>
            </camera>
            <lens>
                <maker>Sony</maker>
                <model>E 16mm f/2.8</model>
                <mount>Sony E</mount>
                <cropfactor>1.534</cropfactor>
                <calibration>
                    <distortion model="ptlens" focal="16" a="0.01701" b="-0.02563" c="-0.0052"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    static let ambiguousXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Canon</maker>
                <model>50mm f/1.4</model>
                <cropfactor>1</cropfactor>
                <calibration><distortion model="poly3" focal="50" k1="-0.01"/></calibration>
            </lens>
            <lens>
                <maker>Nikon</maker>
                <model>50mm f/1.4</model>
                <cropfactor>1</cropfactor>
                <calibration><distortion model="poly3" focal="50" k1="-0.01"/></calibration>
            </lens>
        </lensdatabase>
        """

    static let twoCamerasXML = """
        <lensdatabase version="1">
            <camera>
                <maker>Sony</maker>
                <model>ILCE-7M4</model>
                <mount>Sony E</mount>
                <cropfactor>1</cropfactor>
            </camera>
            <camera>
                <maker>Sony</maker>
                <model>ILCE-7M4</model>
                <mount>Sony E</mount>
                <cropfactor>1.5</cropfactor>
            </camera>
        </lensdatabase>
        """

    private static func db(_ xml: String) -> LensfunDB {
        LensfunDBLoader.parse(Data(xml.utf8))
    }

    override func tearDown() {
        LensfunStore.uninstall()
        super.tearDown()
    }

    // MARK: - Crop gate alive (the full-frame vs APS-C mis-match arms)

    func testCropGateRejectsFullFrameAgainstAPSCSet() {
        let db = Self.db(Self.apscXML)
        // Full-frame camera (imageCrop 1.0): 1.0/1.622 = 0.617 < 0.96 → the
        // APS-C calibration set must NOT match (the pre-T3 1.0 hardcode
        // disabled this gate de facto).
        let ff = LensfunMatch.matchHardened(
            maker: "Canon", model: nil, lens: "Canon EF-S 24mm f/2.8 STM",
            imageCrop: 1.0, in: db)
        guard case .noLens = ff else { return XCTFail("expected noLens, got \(ff)") }
        // APS-C camera (imageCrop 1.62): the gate opens.
        let apsc = LensfunMatch.matchHardened(
            maker: "Canon", model: nil, lens: "Canon EF-S 24mm f/2.8 STM",
            imageCrop: 1.62, in: db)
        guard case .matched(let entry, _) = apsc else { return XCTFail("expected matched, got \(apsc)") }
        XCTAssertEqual(entry.cropfactor, 1.622)
    }

    // MARK: - Threshold tier (40 loses auto-selection, 60 keeps it)

    /// A multi-word candidate whose normalized form keeps the words
    /// ("fe 28mm f2 gm" — no f/… segment to strip): the reordered EXIF
    /// word subset lands the 40 tier WITHOUT a bidirectional substring
    /// hit (which would score 60).
    static let tierXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Sony</maker>
                <model>FE 28mm F2 GM</model>
                <cropfactor>1.534</cropfactor>
                <calibration><distortion model="poly3" focal="28" k1="-0.01"/></calibration>
            </lens>
        </lensdatabase>
        """

    func testThresholdTierFortyRejectedSixtyAccepted() {
        let db = Self.db(Self.tierXML)
        // "f2 28mm" → every EXIF word ⊂ candidate words, but neither
        // string contains the other → the 40 tier → NO auto-selection.
        let forty = LensfunMatch.matchHardened(
            maker: nil, model: nil, lens: "F2 28mm", imageCrop: 1.5, in: db)
        guard case .noLens = forty else { return XCTFail("expected noLens at the 40 tier, got \(forty)") }
        // The contains tier on the sony fixture: "e 16mm f2.8 gm" ⊃
        // candidate "e 16mm" → 60 (+5 maker bonus) → matched.
        let sixty = LensfunMatch.matchHardened(
            maker: "Sony", model: nil, lens: "E 16mm f2.8 gm", imageCrop: 1.5,
            in: Self.db(Self.sonyXML))
        guard case .matched(let entry, let score) = sixty else {
            return XCTFail("expected matched at the 60 tier, got \(sixty)")
        }
        XCTAssertEqual(entry.maker, "Sony")
        XCTAssertGreaterThanOrEqual(score, 60)
    }

    func testMissingLensStringReadsMissingFocal() {
        let outcome = LensfunMatch.matchHardened(
            maker: nil, model: nil, lens: nil, imageCrop: 1.0, in: Self.db(Self.sonyXML))
        guard case .missingFocal = outcome else { return XCTFail("expected missingFocal, got \(outcome)") }
    }

    // MARK: - Ambiguity refusal (RawLab FindLenses semantics)

    func testTopScoreTiesRejectedAsAmbiguous() {
        let db = Self.db(Self.ambiguousXML)
        let outcome = LensfunMatch.matchHardened(
            maker: nil, model: nil, lens: "50mm f/1.4", imageCrop: 1.0, in: db)
        guard case .ambiguous(let score) = outcome else {
            return XCTFail("expected ambiguous, got \(outcome)")
        }
        XCTAssertEqual(score, 100)
    }

    // MARK: - Camera unique-hit crop (RawLab FindCameras semantics)

    func testUniqueCameraCropSingleHitAndMultiHitRejection() {
        let single = LensfunMatch.uniqueCameraCrop(
            maker: "Sony", model: "ILCE-7M4", in: Self.db(Self.sonyXML))
        XCTAssertEqual(single, 1.0)
        // Two camera entries carrying the same model → ambiguous → nil.
        let multi = LensfunMatch.uniqueCameraCrop(
            maker: "Sony", model: "ILCE-7M4", in: Self.db(Self.twoCamerasXML))
        XCTAssertNil(multi)
        let absent = LensfunMatch.uniqueCameraCrop(
            maker: "Fujifilm", model: "X-T5", in: Self.db(Self.sonyXML))
        XCTAssertNil(absent)
    }

    // MARK: - resolve crop argument = the CAMERA imageCrop (review m5)

    func testResolveCommittedUsesCameraCropNotEntryCrop() throws {
        LensfunStore.install(db: Self.db(Self.sonyXML))
        defer { LensfunStore.uninstall() }
        var params = LensModule.Params(
            source: .lensfun, focalLength: 16, aperture: 2.8, lensKey: "E 16mm f/2.8")
        params.imageCrop = 1.5 // the CAMERA crop (the entry carries 1.534)
        let out = LensfunStore.resolveCommitted(params, width: 6000, height: 4000)
        let entry = try XCTUnwrap(Self.db(Self.sonyXML).lenses.first)
        let directCamera = try XCTUnwrap(LensfunMatch.resolve(
            entry: entry, focal: 16, aperture: 2.8, distance: nil, crop: 1.5,
            imageWidth: 6000, imageHeight: 4000))
        let directEntry = LensfunMatch.resolve(
            entry: entry, focal: 16, aperture: 2.8, distance: nil, crop: 1.534,
            imageWidth: 6000, imageHeight: 4000)
        // The resolve site must fold the CAMERA crop — bit-identical to
        // the direct camera-crop call, and DIFFERENT from the pre-T3
        // entry-cropface (1.534) wherever the NS·HW fold carries it.
        let uniforms = try XCTUnwrap(out)
        XCTAssertEqual(uniforms.dc2, directCamera.dc2)
        XCTAssertEqual(uniforms.centerX, directCamera.centerX)
        if let entryFace = directEntry {
            XCTAssertNotEqual(uniforms.dc2, entryFace.dc2, accuracy: 1e-12)
        }
    }

    // MARK: - reloadDefaults bakes the X4 priority chain

    private func makeImage(
        capture: CaptureMetadata, embedded: EmbeddedGeometryState?
    ) -> DecodedImage {
        DecodedImage(
            ciImage: CIImage.empty(), rawTech: RAWTechnicalParams(), capture: capture,
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: nil,
            embeddedGeometry: embedded)
    }

    func testReloadDefaultsPrefers35mmDerivation() async throws {
        var cap = CaptureMetadata()
        cap.focalLength = 50
        cap.focalLength35mm = 75
        cap.cameraMake = "Sony"
        cap.cameraModel = "ILCE-7M4"
        let module = LensModule()
        let params = await module.reloadDefaults(image: makeImage(capture: cap, embedded: .unknown))
        XCTAssertEqual(try XCTUnwrap(params.imageCrop), 1.5, accuracy: 1e-12)
        XCTAssertEqual(params.cameraMaker, "Sony")
        XCTAssertEqual(params.cameraModel, "ILCE-7M4")
        XCTAssertEqual(params.embeddedGeometry, .unknown)
    }

    func testReloadDefaultsFallsToCameraHitThenNil() async throws {
        var cap = CaptureMetadata()
        cap.focalLength = 50
        cap.cameraMake = "Sony"
        cap.cameraModel = "ILCE-7M4"
        let module = LensModule()
        // No DB installed → the camera tier misses → nil (the 1.0 fallback
        // lives at the resolve site).
        var params = await module.reloadDefaults(image: makeImage(capture: cap, embedded: nil))
        XCTAssertNil(params.imageCrop)
        XCTAssertNil(params.embeddedGeometry, "nil judgment rides through untouched")
        // With the DB installed and a unique camera hit → the cropfactor.
        LensfunStore.install(db: Self.db(Self.sonyXML))
        params = await module.reloadDefaults(image: makeImage(capture: cap, embedded: .notApplicable))
        XCTAssertEqual(try XCTUnwrap(params.imageCrop), 1.0, accuracy: 1e-12)
        XCTAssertEqual(params.embeddedGeometry, .notApplicable)
        LensfunStore.uninstall()
    }

    // MARK: - Params additive zero-drift (the default-params JSON contract)

    func testDefaultParamsEncodeStaysByteIdentical() throws {
        // The pre-T3 params JSON shape: the four additive optionals are
        // nil and MUST NOT appear in the encoding.
        let legacyJSON = """
        {"distortionK1":0,"distortionK2":0,"tcaR":0,"tcaB":0,"vignetteK1":0,\
        "vignetteK2":0,"vignetteK3":0,"source":"off","focalLength":16,\
        "aperture":2.8,"lensKey":"E 16mm f/2.8"}
        """
        let decoded = try JSONDecoder().decode(LensModule.Params.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decoded.cameraMaker)
        XCTAssertNil(decoded.cameraModel)
        XCTAssertNil(decoded.imageCrop)
        XCTAssertNil(decoded.embeddedGeometry)
        let reencoded = try JSONEncoder().encode(decoded)
        let roundTripped = try JSONDecoder().decode(LensModule.Params.self, from: reencoded)
        XCTAssertEqual(decoded, roundTripped)
        // The default (all-nil additive) face encodes WITHOUT the new keys.
        let fresh = try JSONEncoder().encode(LensModule.Params())
        let freshObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: fresh) as? [String: Any])
        XCTAssertNil(freshObject["cameraMaker"])
        XCTAssertNil(freshObject["cameraModel"])
        XCTAssertNil(freshObject["imageCrop"])
        XCTAssertNil(freshObject["embeddedGeometry"])
    }
}
