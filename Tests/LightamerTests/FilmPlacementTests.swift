@testable import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// FilmPlacementTests (Plan M3-3-02 T4, KD-5 — IOP bundle) — the op's TYPE
// face: params coding (snake_case keys), the clamp domain, the registration
// face, the E7 identityJSON (= the kernel no-op point) and the knee solve's
// determinism + closed-form exactness (the kernel/golden body lives in
// FilmPlacementKernelTests / M3-3-03).
// ─────────────────────────────────────────────────────────────────────────────

final class FilmPlacementTests: XCTestCase {

    // MARK: - params coding

    func testParamsCodingUsesSnakeCaseKeysAndRoundTrips() throws {
        let params = FilmPlacementModule.Params(
            shadowsPullBack: 1.25, highlightsPullBack: 2.5, rolloff: 3)
        let data = ParamsCoding.encode(params)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"shadows_pull_back\""), json)
        XCTAssertTrue(json.contains("\"highlights_pull_back\""), json)
        XCTAssertTrue(json.contains("\"rolloff\""), json)
        let decoded = try JSONDecoder().decode(
            FilmPlacementModule.Params.self, from: data)
        XCTAssertEqual(decoded, params)
    }

    func testClampDomain() {
        let clamped = FilmPlacementModule.clamped(.init(
            shadowsPullBack: -1, highlightsPullBack: 9, rolloff: 0.5))
        XCTAssertEqual(clamped.shadowsPullBack, 0, "negative pull-back clamps to the off point")
        XCTAssertEqual(clamped.highlightsPullBack, 9)
        XCTAssertEqual(clamped.rolloff, 1, "m clamps into [1, 8]")
        XCTAssertEqual(FilmPlacementModule.clamped(.init(rolloff: 99)).rolloff, 8)
        // The default IS the no-op point.
        XCTAssertEqual(FilmPlacementModule.Params(), .init())
        XCTAssertEqual(FilmPlacementModule.Params().rolloff, 2)
    }

    // MARK: - registration + the E7 identity snapshot

    func testModuleIsDefaultFaceRegisteredAndResolves() async {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)
        let box = await registry.makeBox(opName: FilmPlacementModule.opName)
        XCTAssertNotNil(box, "the 19th catalog row registers (E7 closure)")
        XCTAssertEqual(FilmPlacementModule.iopOrder, 20.8)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: FilmPlacementModule.opName), .grade)
        XCTAssertFalse(
            LightamerIOPRegistry.defaultFaceDisabledOpNames.contains(
                FilmPlacementModule.opName),
            "defaultFaceDisabledOpNames zero-diff (KD-5)")
    }

    func testCatalogIdentityJSONIsTheKernelNoOpPoint() throws {
        let item = try XCTUnwrap(GradeCatalog.item(opName: FilmPlacementModule.opName))
        XCTAssertEqual(item.catalogID, "filmPlacement")
        XCTAssertEqual(
            item.panelExposures, ["shadowsPullBack", "highlightsPullBack", "rolloff"])
        let identity = try JSONDecoder().decode(
            FilmPlacementModule.Params.self, from: Data(item.identityJSON.utf8))
        XCTAssertEqual(identity.shadowsPullBack, 0, "the identity = both branches off")
        XCTAssertEqual(identity.highlightsPullBack, 0)
        // The identity template's params bytes == the row's identityJSON
        // (the add-face seed contract — CatalogAddFaceTests pins it too).
        XCTAssertEqual(
            ParamsCoding.encode(identity), Data(item.identityJSON.utf8))
    }

    // MARK: - the knee solve (CPU, Float64)

    func testKneeSolveIsDeterministicBitIdentical() {
        let a = FilmPlacementModule.solveKnee(
            pullBack: 1.5, rolloff: 2,
            sceneExtreme: FilmPlacementModule.sceneTopEV,
            mediumBoundary: FilmPlacementModule.mediumTopEV)
        let b = FilmPlacementModule.solveKnee(
            pullBack: 1.5, rolloff: 2,
            sceneExtreme: FilmPlacementModule.sceneTopEV,
            mediumBoundary: FilmPlacementModule.mediumTopEV)
        XCTAssertEqual(a, b, "double solve is bit-identical (the FSIM-01b posture)")
        XCTAssertTrue(a.active)
    }

    func testZeroPullBackIsTheInactiveIdentity() {
        let knee = FilmPlacementModule.solveKnee(
            pullBack: 0, rolloff: 2,
            sceneExtreme: FilmPlacementModule.sceneTopEV,
            mediumBoundary: FilmPlacementModule.mediumTopEV)
        XCTAssertFalse(knee.active, "N = 0 → the branch is the exact identity (§9.3)")
    }

    func testM1ClosedFormLandsExactly() {
        // m=1 closed form: the landing lands EXACTLY at t = C ∓ N.
        let a = FilmPlacementModule.sceneTopEV
        let c = FilmPlacementModule.mediumTopEV
        let n = 1.5
        let t = c - n
        let knee = FilmPlacementModule.solveKnee(
            pullBack: n, rolloff: 1, sceneExtreme: a, mediumBoundary: c)
        let fA = knee.knee + FilmPlacementModule.smoothMin(a - knee.knee, knee.room, 1)
        XCTAssertEqual(fA, t, accuracy: 1e-12, "the m=1 landing is exact")
        XCTAssertGreaterThan(knee.room, 0, "the room stays positive (H = C − K)")
        XCTAssertLessThan(knee.knee, c)
    }

    func testM2BisectionNewtonLandsExactly() {
        let a = FilmPlacementModule.sceneTopEV
        let c = FilmPlacementModule.mediumTopEV
        for m in [2.0, 3.5, 8.0] {
            let n = 1.0
            let t = c - n
            let knee = FilmPlacementModule.solveKnee(
                pullBack: n, rolloff: m, sceneExtreme: a, mediumBoundary: c)
            let fA = knee.knee + FilmPlacementModule.smoothMin(a - knee.knee, knee.room, m)
            XCTAssertEqual(fA, t, accuracy: 1e-9, "m=\(m) landing exact (bisection+Newton)")
            // The higher the order, the flatter the branch start — the knee
            // sits LOWER for larger m (§5.5: high m bends early).
            let m1 = FilmPlacementModule.solveKnee(
                pullBack: n, rolloff: 1, sceneExtreme: a, mediumBoundary: c)
            XCTAssertLessThan(knee.knee, m1.knee, "m=\(m) knee below the m=1 knee")
        }
    }

    func testShadowSideSolvesSymmetrically() {
        let a = FilmPlacementModule.sceneBottomEV
        let c = FilmPlacementModule.mediumBottomEV
        let n = 1.0
        let t = c + n
        let knee = FilmPlacementModule.solveKnee(
            pullBack: n, rolloff: 2, sceneExtreme: a, mediumBoundary: c)
        XCTAssertGreaterThan(knee.knee, c, "the shadow knee sits ABOVE the boundary")
        let fA = knee.knee - FilmPlacementModule.smoothMin(knee.knee - a, knee.room, 2)
        XCTAssertEqual(fA, t, accuracy: 1e-9, "the shadow landing is exact")
    }

    // MARK: - the placement gain (the scalar CPU reference)

    func testPlacementGainIsIdentityInTheCore() {
        // A small pull-back keeps the knees far from mid-gray (0.1 stop
        // inside the boundary → knee ≈ +3.3): E = 0 sits deep in the core.
        let params = FilmPlacementModule.Params(
            shadowsPullBack: 0.1, highlightsPullBack: 0.1, rolloff: 2)
        let (gain, onBranch) = FilmPlacementModule.placementGain(
            SIMD3(0.184, 0.184, 0.184), params: params)
        XCTAssertEqual(gain, 1.0, "the core gain is exactly 1 (the delta form)")
        XCTAssertFalse(onBranch)
    }

    func testPlacementGainCompressesMonotonically() {
        let params = FilmPlacementModule.Params(
            shadowsPullBack: 0, highlightsPullBack: 2, rolloff: 2)
        var previousPlaced = -Double.greatestFiniteMagnitude
        var ev = 2.0
        while ev < 12.0 {
            let rgb = SIMD3(0.184 * Foundation.pow(2.0, ev), 0.184, 0.184)
            let (gain, onBranch) = FilmPlacementModule.placementGain(rgb, params: params)
            if onBranch {
                let placedEV = ev + Foundation.log2(gain)
                // Monotone increasing (compression never reorders)…
                XCTAssertGreaterThan(
                    placedEV, previousPlaced,
                    "the placed EV rises with the source EV (f monotone)")
                // …compressed (the branch pulls DOWN — placed < source)…
                XCTAssertLessThan(placedEV, ev, "the highlight branch compresses")
                previousPlaced = placedEV
            }
            ev += 0.5
        }
        // …and the asymptote: an extreme 20 stops out lands near (never far
        // beyond) the medium boundary.
        let (topGain, topBranch) = FilmPlacementModule.placementGain(
            SIMD3(0.184 * Foundation.pow(2.0, 20.0), 0.184, 0.184), params: params)
        XCTAssertTrue(topBranch)
        let landedEV = 20.0 + Foundation.log2(topGain)
        XCTAssertLessThan(landedEV, FilmPlacementModule.mediumTopEV + 1.0,
                          "the extreme lands at the boundary (the g_m asymptote)")
    }
}
