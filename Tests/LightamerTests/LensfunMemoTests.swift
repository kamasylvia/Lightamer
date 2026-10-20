@testable import LightamerIOP
import XCTest

/// LensfunMemoTests (Plan LENS-01 T4, hazard H-L1 first stage) — the
/// process-level match memo in LensfunStore.
///
/// Key semantics under test:
/// - the key is the MATCHING INPUT face (maker/model/lensKey/imageCrop/
///   focal) — a change in any of them must miss;
/// - the value is the MATCH RESULT (entry + score + failure state), NOT
///   the resolved coefficients — so the memo is SIZE-INDEPENDENT: the
///   same params across full/preview/thumbnail renders hit (review M4;
///   the center-resolution coupling dies with the result-level memo);
/// - install/uninstall bumps the DB stamp and clears the table wholesale;
/// - LRU capacity 32 evicts the least-recently-used entry;
/// - a memo hit does NOT touch the full-library scan (LensfunMatch
///   .scanCounter observability).
final class LensfunMemoTests: XCTestCase {

    /// A small library with one matchable lens (score 100 on "E 16mm f/2.8").
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

    private func params(
        lensKey: String = "E 16mm f/2.8",
        maker: String? = nil, model: String? = nil, imageCrop: Double? = 1.534
    ) -> LensModule.Params {
        var p = LensModule.Params(
            source: .lensfun, focalLength: 16, aperture: 2.8, lensKey: lensKey)
        p.cameraMaker = maker
        p.cameraModel = model
        p.imageCrop = imageCrop
        return p
    }

    override func setUp() {
        super.setUp()
        LensfunMatch.scanCounter = 0
        LensfunStore.install(db: LensfunDBLoader.parse(Data(Self.libraryXML.utf8)))
    }

    override func tearDown() {
        LensfunStore.uninstall()
        LensfunMatch.scanCounter = 0
        super.tearDown()
    }

    func testSecondSameParamsCallHitsMemoWithoutRescan() {
        let p = params()
        guard case .matched = LensfunStore.matchOutcome(p) else {
            return XCTFail("first call must match")
        }
        let afterFirst = LensfunMatch.scanCounter
        XCTAssertEqual(afterFirst, 1, "first call scans the library once")
        for _ in 0..<3 {
            guard case .matched = LensfunStore.matchOutcome(p) else {
                return XCTFail("repeat calls must still match")
            }
        }
        XCTAssertEqual(LensfunMatch.scanCounter, afterFirst,
                       "memo hits must NOT rescan the library")
    }

    func testParameterChangeMissesMemo() {
        _ = LensfunStore.matchOutcome(params())
        let baseline = LensfunMatch.scanCounter
        // A lensKey change is a different matching input → miss → rescan.
        _ = LensfunStore.matchOutcome(params(lensKey: "FE 28mm F2 GM"))
        XCTAssertEqual(LensfunMatch.scanCounter, baseline + 1)
        // The imageCrop change likewise misses (the gate input).
        _ = LensfunStore.matchOutcome(params(imageCrop: 1.0))
        XCTAssertEqual(LensfunMatch.scanCounter, baseline + 2)
    }

    func testReinstallInvalidatesWholeTable() {
        _ = LensfunStore.matchOutcome(params())
        let baseline = LensfunMatch.scanCounter
        // Reinstall the SAME library — the stamp bumps, the memo clears.
        LensfunStore.install(db: LensfunDBLoader.parse(Data(Self.libraryXML.utf8)))
        _ = LensfunStore.matchOutcome(params())
        XCTAssertEqual(LensfunMatch.scanCounter, baseline + 1,
                       "post-reinstall the first lookup must rescan")
        // A DIFFERENT library must yield ITS OWN outcome (no cross-library
        // value serving).
        let empty = LensfunDBLoader.parse(Data("""
        <lensdatabase version="1"><lens><maker>Other</maker><model>X</model>\
        <cropfactor>1</cropfactor><calibration>\
        <distortion model="poly3" focal="50" k1="-0.01"/></calibration></lens>\
        </lensdatabase>
        """.utf8))
        LensfunStore.install(db: empty)
        let outcome = LensfunStore.matchOutcome(params())
        guard case .noLens = outcome ?? .noLens else {
            return XCTFail("cross-library memo serving detected: \(String(describing: outcome))")
        }
    }

    func testLRUCapacityEvictsOldest() {
        // Fill beyond capacity (32) with distinct matching inputs.
        var xml = "<lensdatabase version=\"1\">"
        for i in 0..<40 {
            xml += "<lens><maker>M</maker><model>Lens \(i)</model><cropfactor>1.5</cropfactor>"
            xml += "<calibration><distortion model=\"poly3\" focal=\"16\" k1=\"-0.01\"/></calibration></lens>"
        }
        xml += "</lensdatabase>"
        LensfunStore.install(db: LensfunDBLoader.parse(Data(xml.utf8)))
        var baseline = LensfunMatch.scanCounter
        for i in 0..<40 {
            _ = LensfunStore.matchOutcome(params(lensKey: "Lens \(i)"))
        }
        baseline = LensfunMatch.scanCounter
        XCTAssertEqual(baseline, 40, "each distinct input scans exactly once")
        // The LRU entry (Lens 0) was evicted — re-querying rescans.
        _ = LensfunStore.matchOutcome(params(lensKey: "Lens 0"))
        XCTAssertEqual(LensfunMatch.scanCounter, baseline + 1, "evicted entry must rescan")
        // The most-recent entry (Lens 39) survives — hit, no rescan.
        _ = LensfunStore.matchOutcome(params(lensKey: "Lens 39"))
        XCTAssertEqual(LensfunMatch.scanCounter, baseline + 1)
    }

    func testMemoIsSizeIndependent() {
        let p = params()
        _ = LensfunStore.resolveCommitted(p, width: 6000, height: 4000)
        let baseline = LensfunMatch.scanCounter
        // full → preview → thumbnail: same params, different plane sizes —
        // the memo key carries NO size term, so every leg hits.
        _ = LensfunStore.resolveCommitted(p, width: 1500, height: 1000)
        _ = LensfunStore.resolveCommitted(p, width: 300, height: 200)
        XCTAssertEqual(LensfunMatch.scanCounter, baseline,
                       "size changes must NOT miss the match memo")
    }

    func testUninstallClearsStoreFace() {
        _ = LensfunStore.matchOutcome(params())
        LensfunStore.uninstall()
        XCTAssertNil(LensfunStore.matchOutcome(params()))
        XCTAssertFalse(LensfunStore.isInstalled)
    }
}
