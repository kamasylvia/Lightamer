@testable import LightamerCore
@testable import LightamerIOP
import XCTest

/// LensProjectionResolveTests (Plan LENS-03 T1, D-LENS-8) — the resolve
/// face of the projection batch: the 8-slot enum compile face, the
/// lenient decode, the REFUSAL LIFT (target set → a non-rectilinear
/// entry resolves; target unset → the conservative refusal stands),
/// the params-additive zero-drift negative, and the entry-type fold into
/// the kernel params.
final class LensProjectionResolveTests: XCTestCase {

    static let fisheyeXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Samyang</maker>
                <model>8mm F3.5 FISH-EYE</model>
                <cropfactor>1.534</cropfactor>
                <type>fisheye</type>
                <calibration>
                    <distortion model="poly3" focal="8" k1="-0.01"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    static let rectilinearXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Sony</maker>
                <model>E 16mm f/2.8</model>
                <cropfactor>1.534</cropfactor>
                <calibration>
                    <distortion model="poly3" focal="16" k1="-0.01"/>
                </calibration>
            </lens>
        </lensdatabase>
        """

    override func tearDown() {
        LensfunStore.uninstall()
        super.tearDown()
    }

    // MARK: - The 8-slot enum face

    func testEnumSlotsAndReservedFaces() {
        XCTAssertEqual(LensProjection.allCases.count, 8, "the 8-slot compile face")
        XCTAssertEqual(LensProjection.active, [.fisheye, .equisolid, .stereographic, .orthographic])
        XCTAssertTrue(LensProjection.panoramic.isReserved)
        XCTAssertTrue(LensProjection.equirectangular.isReserved)
        XCTAssertTrue(LensProjection.thoby.isReserved)
        for active in LensProjection.active {
            XCTAssertFalse(active.isReserved)
        }
        // The slot ordinals = the Alcedo enum order.
        XCTAssertEqual(LensProjection.rectilinear.slotIndex, 1)
        XCTAssertEqual(LensProjection.fisheye.slotIndex, 2)
        XCTAssertEqual(LensProjection.equisolid.slotIndex, 7)
        XCTAssertEqual(LensProjection.thoby.slotIndex, 8)
    }

    func testLenientDecode() {
        XCTAssertEqual(LensProjection.decodeLenient("fisheye"), .fisheye)
        XCTAssertEqual(LensProjection.decodeLenient("nonsense"), .rectilinear)
        XCTAssertEqual(LensProjection.decodeLenient(nil), .rectilinear)
    }

    // MARK: - The refusal lift (both arms)

    func testNonRectilinearResolvesWhenTargetSet() throws {
        LensfunStore.install(db: LensfunDBLoader.parse(Data(Self.fisheyeXML.utf8)))
        defer { LensfunStore.uninstall() }
        var p = LensModule.Params(
            source: .lensfun, focalLength: 8, lensKey: "8mm F3.5 FISH-EYE")
        p.imageCrop = 1.534 // the camera crop (the 0.96 gate reads it)
        p.targetProjection = "fisheye"
        let out = LensfunStore.resolveCommitted(p, width: 3000, height: 2000)
        let resolved = try XCTUnwrap(out)
        XCTAssertEqual(resolved.sourceProjection, "fisheye",
                       "the entry type folds into the kernel params")
        // target == source → the fold identity (fisheye shot with the
        // fisheye target = no re-projection; the distortion still rides).
        p.targetProjection = nil
        XCTAssertNil(LensfunStore.resolveCommitted(p, width: 3000, height: 2000),
                     "target UNSET + non-rectilinear = the conservative refusal")
    }

    func testRectilinearEntryUnaffected() throws {
        LensfunStore.install(db: LensfunDBLoader.parse(Data(Self.rectilinearXML.utf8)))
        defer { LensfunStore.uninstall() }
        var p = LensModule.Params(
            source: .lensfun, focalLength: 16, lensKey: "E 16mm f/2.8")
        p.imageCrop = 1.534
        XCTAssertNotNil(LensfunStore.resolveCommitted(p, width: 3000, height: 2000),
                        "rectilinear entries never touch the refusal face")
    }

    // MARK: - The projection fold math (sanity on the CPU face)

    func testFoldIdentityWhenProjectionsCoincide() {
        let (x, y) = LensProjection.fold(0.3, -0.2, source: .fisheye, target: .fisheye)
        XCTAssertEqual(x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(y, -0.2, accuracy: 1e-12)
    }

    func testFisheyeToRectilinearFoldDirection() {
        // A fisheye-domain point maps OUTWARD into the rectilinear sample
        // domain (tan stretches the rim) — the direction face. Off-axis
        // (the rectilinear pole at erect (0,0) degenerates to 1/0).
        let (x, y) = LensProjection.fold(0.3, 0.1, source: .rectilinear, target: .fisheye)
        XCTAssertGreaterThan(x, 0.3, "rectilinear sampling of a fisheye shot stretches outward")
        XCTAssertFalse(y.isFinite == false)
    }

    // MARK: - The params additive zero-drift negative

    func testParamsProjectionFieldsZeroDrift() throws {
        let fresh = try JSONEncoder().encode(LensModule.Params())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: fresh) as? [String: Any])
        XCTAssertNil(object["targetProjection"])
        XCTAssertNil(object["sourceProjection"])
        let legacy = try JSONDecoder().decode(
            LensModule.Params.self,
            from: Data("""
            {"distortionK1":0,"distortionK2":0,"tcaR":0,"tcaB":0,"vignetteK1":0,\
            "vignetteK2":0,"vignetteK3":0,"source":"off"}
            """.utf8))
        XCTAssertNil(legacy.targetProjection)
        XCTAssertNil(legacy.sourceProjection)
    }
}
