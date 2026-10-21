@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import XCTest

/// LensSnapshotTests (Plan LENS-04 T1, D-LENS-3 / X3) — the coefficient
/// snapshot persistence: the round-trip, the SNAPSHOT-FIRST consumption
/// (zero-DB — the H-L2 hard gate), the legacy nil face, the dbTag
/// strip-on-hash, and the Re-match flow.
final class LensSnapshotTests: XCTestCase {

    static let libraryXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Sony</maker>
                <model>E 16mm f/2.8</model>
                <cropfactor>1.534</cropfactor>
                <calibration><distortion model="poly3" focal="16" k1="-0.01"/></calibration>
            </lens>
        </lensdatabase>
        """

    override func setUp() {
        super.setUp()
        LensfunStore.installForTesting(
            db: LensfunDBLoader.parse(Data(Self.libraryXML.utf8)),
            dbTag: "0123456789abcdef")
    }

    override func tearDown() {
        LensfunStore.uninstall()
        super.tearDown()
    }

    private func params() -> LensModule.Params {
        var p = LensModule.Params(source: .lensfun, focalLength: 16, lensKey: "E 16mm f/2.8")
        p.imageCrop = 1.534
        return p
    }

    // MARK: - The bake + round-trip

    func testBakeStampsSnapshotAndRoundTrips() throws {
        let baked = try XCTUnwrap(LensfunStore.bakeCommitted(params()))
        let snap = try XCTUnwrap(baked.snapshot)
        XCTAssertEqual(baked.source, .lensfun)
        XCTAssertEqual(snap.profileMaker, "Sony")
        XCTAssertEqual(snap.profileModel, "E 16mm f/2.8")
        XCTAssertEqual(snap.matchScore, 100)
        XCTAssertEqual(snap.dbTag, "0123456789abcdef")
        XCTAssertEqual(snap.distortionRows?.count, 1, "the poly3 row rides the extract")
        XCTAssertEqual(snap.distortionRows?.first?.model, .poly3)
        // JSON round-trip: the persisted face survives the codec.
        let data = try JSONEncoder().encode(baked)
        let back = try JSONDecoder().decode(LensModule.Params.self, from: data)
        XCTAssertEqual(back.snapshot, snap)
    }

    // MARK: - The SNAPSHOT-FIRST consumption (zero DB — H-L2's hard gate)

    func testSnapshottedRenderSurvivesDatabaseUninstall() async throws {
        let module = LensModule()
        module.setCommittedForTesting(params())
        let withDB = await module.resolveUniforms(
            bufW: 3000, bufH: 2000, roiIn: ROI(), roiOut: ROI())
        let baked = try XCTUnwrap(LensfunStore.bakeCommitted(params()))
        module.setCommittedForTesting(baked)

        // THE GATE: uninstall the database entirely — the snapshotted
        // render face must be UNCHANGED (bit-identical uniforms).
        LensfunStore.uninstall()
        let withoutDB = await module.resolveUniforms(
            bufW: 3000, bufH: 2000, roiIn: ROI(), roiOut: ROI())
        let a = try XCTUnwrap(withDB)
        let b = try XCTUnwrap(withoutDB)
        XCTAssertEqual(a.dist, b.dist)
        XCTAssertEqual(a.tcaR, b.tcaR)
        XCTAssertEqual(a.vig, b.vig)
        XCTAssertEqual(a.scale, b.scale)

        // The legacy face (snapshot nil) DOWNgrades on the same uninstall
        // — the live-resolve miss = nil (the identity face).
        module.setCommittedForTesting(params())
        let live = await module.resolveUniforms(
            bufW: 3000, bufH: 2000, roiIn: ROI(), roiOut: ROI())
        XCTAssertNil(live, "snapshot-nil + no DB = the legacy identity face")
    }

    // MARK: - The dbTag strip-on-hash (X3, review m2)

    func testDBTagNeverShiftsParamsHash() {
        let module = LensModule()
        let bakedA = LensfunStore.bakeCommitted(params())!
        var pieceA = IOPiece(dscIn: IOPBufferDesc(width: 64, height: 64))
        module.commitParams(bakedA, into: &pieceA)
        // The Re-match face: a NEW dbTag (a DB update), SAME calibration.
        var bakedB = bakedA
        bakedB.snapshot?.dbTag = "fedcba9876543210fedcba9876543210"
        var pieceB = IOPiece(dscIn: IOPBufferDesc(width: 64, height: 64))
        module.commitParams(bakedB, into: &pieceB)
        XCTAssertEqual(pieceA.paramsHash, pieceB.paramsHash,
                       "the dbTag is strip-on-hash — a DB update never shifts the cache key")
        // The CALIBRATION drift still shifts it (the real invalidation).
        var bakedC = bakedA
        bakedC.snapshot?.distortionRows = []
        var pieceC = IOPiece(dscIn: IOPBufferDesc(width: 64, height: 64))
        module.commitParams(bakedC, into: &pieceC)
        XCTAssertNotEqual(pieceA.paramsHash, pieceC.paramsHash)
    }

    // MARK: - The zero-drift negative (the default-params JSON)

    func testSnapshotNilEncodeStaysByteIdentical() throws {
        let fresh = try JSONEncoder().encode(LensModule.Params())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: fresh) as? [String: Any])
        XCTAssertNil(object["snapshot"])
        // The legacy JSON decodes to the snapshot-nil face.
        let legacy = try JSONDecoder().decode(
            LensModule.Params.self,
            from: Data("""
            {"distortionK1":0,"distortionK2":0,"tcaR":0,"tcaB":0,"vignetteK1":0,\
            "vignetteK2":0,"vignetteK3":0,"source":"off"}
            """.utf8))
        XCTAssertNil(legacy.snapshot)
    }

    // MARK: - The Re-match flow (miss clears the snapshot)

    func testRematchMissAndClear() throws {
        // A calibrated document: bake → snapshot present.
        let baked = try XCTUnwrap(LensfunStore.bakeCommitted(params()))
        XCTAssertNotNil(baked.snapshot)
        // Re-match against the SAME database → fresh snapshot, same face.
        let rematched = try XCTUnwrap(LensfunStore.rematch(baked))
        XCTAssertEqual(rematched.snapshot, baked.snapshot)
        // Uninstall the DB → the Re-match MISSES → the clear face.
        LensfunStore.uninstall()
        XCTAssertNil(LensfunStore.rematch(baked))
        let cleared = LensfunStore.clearSnapshot(baked)
        XCTAssertNil(cleared.snapshot)
    }
}
