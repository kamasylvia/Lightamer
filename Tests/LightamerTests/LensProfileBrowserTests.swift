@testable import LightamerIOP
import XCTest
@testable import Lightamer

/// LensProfileBrowserTests (Plan LENS-02 T4) — the profile browser model
/// (scoring/ordering/selection/detected-confirmation) + the Apply/Clear
/// retirement faces.
///
/// The model is a pure static namespace over a hermetic inline LensfunDB:
/// the search scores via LensfunMatch.modelScore (the SAME tiers — 100
/// exact / 60 contains / 40 word-overlap / +5 maker), keeps score > 0,
/// orders score-desc then maker/model, and flags the <60 band as the
/// low-confidence annotation (D-LENS-4 continuation: visible, NEVER
/// auto-selected). The selection commit is ONE params transformation;
/// the detected judgment (D-LENS-2 v1 face, review M2) gates it.
final class LensProfileBrowserTests: XCTestCase {

    static let dbXML = """
        <lensdatabase version="1">
            <lens>
                <maker>Sony</maker>
                <model>E 16mm f/2.8</model>
                <cropfactor>1.534</cropfactor>
            </lens>
            <lens>
                <maker>Sony</maker>
                <model>FE 28mm F2 GM</model>
                <cropfactor>1.534</cropfactor>
            </lens>
            <lens>
                <maker>Canon</maker>
                <model>EF-S 24mm f/2.8 STM</model>
                <cropfactor>1.622</cropfactor>
            </lens>
        </lensdatabase>
        """

    private func db() -> LensfunDB {
        LensfunDBLoader.parse(Data(Self.dbXML.utf8))
    }

    // MARK: - Ordering / confidence tiers (rows injected — the store's
    // candidateRows face owns the raw scoring)

    func testTierAnnotationAndOrdering() {
        let rows = LensProfileBrowserModel.candidates(rows: [
            LensCandidateRow(maker: "Sony", model: "FE 28mm F2 GM", score: 60),
            LensCandidateRow(maker: "Sony", model: "E 16mm f/2.8", score: 100),
            LensCandidateRow(maker: "Canon", model: "EF-S 24mm f/2.8 STM", score: 40),
        ])
        // Exact-first ordering.
        XCTAssertEqual(rows[0].model, "E 16mm f/2.8")
        XCTAssertFalse(rows[0].lowConfidence)
        XCTAssertEqual(rows[1].score, 60)
        XCTAssertFalse(rows[1].lowConfidence)
        // The 40 band = the low-confidence annotation.
        XCTAssertEqual(rows[2].score, 40)
        XCTAssertTrue(rows[2].lowConfidence, "the 40 tier is the low-confidence annotation")
        for pair in zip(rows, rows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.0.score, pair.1.score)
        }
    }

    func testEmptyRowsYieldEmptyList() {
        XCTAssertEqual(LensProfileBrowserModel.candidates(rows: []), [])
    }

    func testStoreFaceScoresTheInstalledLibrary() {
        LensfunStore.install(db: db())
        defer { LensfunStore.uninstall() }
        // The store face: "16mm" is CONTAINED in "e 16mm" → the 60 tier.
        let rows = LensfunStore.candidateRows(search: "16mm")
        XCTAssertEqual(rows?.count, 1)
        XCTAssertEqual(rows?.first?.model, "E 16mm f/2.8")
        XCTAssertEqual(rows?.first?.score, 60)
        LensfunStore.uninstall()
        XCTAssertNil(LensfunStore.candidateRows(search: "16mm"), "no DB → nil (the absent face)")
    }

    // MARK: - Selection / clear transformations

    func testSelectedParamsFlipsSourceAndKey() {
        var base = LensModule.Params(source: .manual, focalLength: 16, aperture: 2.8)
        base.lensKey = "old"
        let c = LensProfileCandidate(maker: "Sony", model: "E 16mm f/2.8", score: 100, lowConfidence: false)
        let p = LensProfileBrowserModel.selectedParams(base: base, candidate: c)
        XCTAssertEqual(p.source, .lensfun)
        XCTAssertEqual(p.lensKey, "E 16mm f/2.8")
        XCTAssertEqual(p.focalLength, 16, "the resolve inputs ride untouched")
        XCTAssertEqual(p.aperture, 2.8)
    }

    func testClearedParamsDropSourceKeepValues() {
        var base = LensModule.Params(source: .lensfun, focalLength: 16, lensKey: "E 16mm f/2.8")
        base.distortionK1 = 0.05
        let p = LensProfileBrowserModel.clearedParams(base: base)
        XCTAssertEqual(p.source, .manual)
        XCTAssertEqual(p.lensKey, "E 16mm f/2.8", "the stored key survives (Clear semantics)")
        XCTAssertEqual(p.distortionK1, 0.05, "the slider values survive")
    }

    // MARK: - The detected-confirmation gate (D-LENS-2 v1 face, review M2)

    func testDetectedConfirmationGate() {
        XCTAssertTrue(LensProfileBrowserModel.needsConfirmation(embedded: .detected))
        XCTAssertFalse(LensProfileBrowserModel.needsConfirmation(embedded: .unknown))
        XCTAssertFalse(LensProfileBrowserModel.needsConfirmation(embedded: .notApplicable))
        XCTAssertFalse(LensProfileBrowserModel.needsConfirmation(embedded: nil))
    }

    // MARK: - The retired Apply face (grep-visible retirement)

    func testApplyRetirementKeysAbsentFromModel() {
        // The Apply semantics live ONLY in selectedParams — the retired
        // panel button's copy key is allowlisted as an orphan (the tail
        // block discipline keeps the catalog entry; the source face is
        // gone). This test pins the MODEL's face so a future re-introduction
        // of an auto-apply-shaped button must come through the model.
        let c = LensProfileCandidate(maker: "M", model: "L", score: 100, lowConfidence: false)
        XCTAssertEqual(LensProfileBrowserModel.selectedParams(base: LensModule.Params(), candidate: c).source, .lensfun)
    }
}
