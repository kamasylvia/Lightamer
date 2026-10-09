import CoreImage
import LightamerCore
import LightamerIOP
import Metal
import XCTest

@testable import Lightamer
@testable import LightamerCore

// ─────────────────────────────────────────────────────────────────────────────
// FilmLatitudePanelTests (Plan M3-4-01 T3, KD-3 — APP bundle, the
// FilmPanelTests harness twin) — the latitude panel's faces:
//
//   1. THE SHARE READOUT: hand-computed below/inside/above vectors over a
//      synthetic histogram (whole-bin classification — a straddling bin
//      counts INSIDE, the ≤1-bin tolerance); nil levels and an empty
//      histogram answer nil (the absence is presented, never faked).
//   2. THE RESOLVER ANCHORS: live stats P99.9/P0.1 (integer rank) +
//      descriptor useful pair; the no-film fallback constants on any miss.
//   3. THE DYNAMIC MINIMUMS (rule ①, the side-explicit form) + the §6.4
//      FOUR ROWS all writable through the resolve face (the E3 gate — the
//      typed refusal is reserved for input-domain violations) + the fifth
//      row's kneeOrder refusal + the per-side demand rejections.
//   4. THE FIT (§9.3): the §6.1 flagship scene's H_min suggestion-face
//      refusal (rooms 2.97 < 3.0 — the registered anchor); a wide paper
//      applies; the m=3 crossing shares (landing at the sides-off
//      degenerate — the honest λ→0 outcome, DECISIONS).
//   5. THE ENDPOINT SLOPES: the §6.4 row-2 published values (0.0648 /
//      0.0820) through the §5.4 g'_Δ face.
//   6. THE SESSION FACES: addPlacement (the existing command faces; the
//      grade envelope's layer host), the D-H1 trio lands ONE
//      history_film_placement item, the typed-refusal snap-back (a
//      rejected tick writes NOTHING), and the teaching keys' static face
//      (no interpolation — F-2).
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class FilmLatitudePanelTests: XCTestCase {

    private var metal: MetalContext!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var workspace: WorkspaceModel!
    private var model: FilmPanelModel!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        editorState = EditorState()
        coordinator = PipeCoordinator()
        workspace = WorkspaceModel()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        workspace.attach(pipeCoordinator: coordinator)
        coordinator.attach(workspace: workspace)
        coordinator.attach(metal: metal)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)
        let profiles = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FilmProfiles/profiles")
        coordinator.attachFilmStore(try FilmMaterialStore(profilesDirectory: profiles))
        model = FilmPanelModel(editorState: editorState, pipeCoordinator: coordinator)
    }

    override func tearDown() async throws {
        model = nil
        workspace = nil
        coordinator = nil
        editorState = nil
        metal = nil
        try await super.tearDown()
    }

    nonisolated private static func decodedGradient(size: Int = 160) -> DecodedImage {
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        return DecodedImage(
            ciImage: gradient,
            rawTech: RAWTechnicalParams(blackLevel: 0.0),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8)
    }

    private func loadGradient() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lat-panel-\(UUID().uuidString).jpg")
        try await coordinator.load(
            url: url, decoded: Self.decodedGradient(), instances: [], metal: metal)
    }

    /// Bounded wait for the placement params to reflect a write (the
    /// session's update/commit ride fire-and-forget Tasks).
    private func waitForPlacement(
        _ check: @MainActor (FilmPlacementModule.Params?) -> Bool,
        timeout: TimeInterval = 5, hint: String
    ) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if check(model.placementParams) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("the placement params never landed: \(hint)")
    }

    private func waitForItemCount(_ count: Int, timeout: TimeInterval = 5) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if editorState.history.items.count >= count { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            editorState.history.items.count, count,
            "the history never reached \(count) items")
    }

    /// The RFC-023 §6.4 scene (the golden vector source's own anchors).
    private let rfc64 = PlacementAnchors(
        aH: 8.0, cH: 4.2, aS: -7.0, cS: -4.3, usedFallback: false)
    /// The §6.1 anchors (the flagship 15→8.5 scene — the fallback twins).
    private let rfc61 = PlacementAnchors(
        aH: 8.0, cH: 4.2, aS: -7.0, cS: -4.3, usedFallback: true)

    // MARK: - 1: the share readout (hand vectors)

    func testLatitudeSharesHandComputedVector() {
        // The ramp histogram: bin b carries b+1 counts (total 32896).
        var luma = [UInt32](repeating: 0, count: 256)
        for b in 0..<256 { luma[b] = UInt32(b + 1) }
        let histogram = FilmStatsSeam.PlaneHistogram(perChannel: [
            luma, luma, luma, luma,
        ])
        // The thresholds (the measured portra×endura useful pair).
        let shares = FilmPanelModel.latitudeShares(
            histogram: histogram, belowEV: -1.4663, aboveEV: 4.4485)
        // v_low = 0.184·2^−1.4663 ≈ 0.06659 → bins 0..16 lie fully below
        // (upper edge 17/256 = 0.06641 ≤ v_low), bin 17 straddles →
        // INSIDE. v_high = 0.184·2^4.4485 ≈ 4.46 > 1 → NO bin above.
        let below = (1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14
            + 15 + 16 + 17)
        let total = 256 * 257 / 2
        XCTAssertEqual(shares?.below ?? -1, Double(below) / Double(total), accuracy: 1e-12)
        XCTAssertEqual(
            shares?.inside ?? -1, Double(total - below) / Double(total), accuracy: 1e-12)
        XCTAssertEqual(shares?.above ?? -1, 0.0, accuracy: 1e-12)

        // The straddling-both-ends shape: a threshold inside one bin on
        // BOTH sides — the straddlers count INSIDE (the ≤1-bin tolerance).
        let tight = FilmPanelModel.latitudeShares(
            histogram: histogram,
            belowEV: FilmPanelModel.binEV(100) - 0.001,
            aboveEV: FilmPanelModel.binEV(103) + 0.001)
        // Bins 0..99 fully below (counts 1..100); bins 104..255 fully
        // above (counts 105..256); 100..103 in.
        let belowCount = 100 * 101 / 2
        let aboveCount = (105 + 256) * 152 / 2
        XCTAssertEqual(tight?.below ?? -1, Double(belowCount) / Double(total), accuracy: 1e-12)
        XCTAssertEqual(tight?.above ?? -1, Double(aboveCount) / Double(total), accuracy: 1e-12)
        XCTAssertEqual(
            tight?.inside ?? -1,
            Double(total - belowCount - aboveCount) / Double(total), accuracy: 1e-12)

        // The absence faces: nil levels / an empty histogram → nil.
        XCTAssertNil(FilmPanelModel.latitudeShares(
            histogram: histogram, belowEV: nil, aboveEV: 1))
        let zeroRow = [UInt32](repeating: 0, count: 256)
        let empty = FilmStatsSeam.PlaneHistogram(
            perChannel: [zeroRow, zeroRow, zeroRow, zeroRow])
        XCTAssertNil(FilmPanelModel.latitudeShares(
            histogram: empty, belowEV: -1, aboveEV: 1))
    }

    // MARK: - 2: the anchors

    func testResolverAnchorsThreeStates() {
        // The full fallback: no stats, no descriptor.
        let fallback = PlacementResolver.anchors(stats: nil, descriptor: nil)
        XCTAssertEqual(fallback.aH, FilmPlacementModule.sceneTopEV)
        XCTAssertEqual(fallback.cH, FilmPlacementModule.mediumTopEV)
        XCTAssertEqual(fallback.aS, FilmPlacementModule.sceneBottomEV)
        XCTAssertEqual(fallback.cS, FilmPlacementModule.mediumBottomEV)
        XCTAssertTrue(fallback.usedFallback)

        // The live face: synthetic stats (uniform 4/bin → P99.9 bin 255,
        // P0.1 bin 0) + a descriptor → the stats' EV extremes and the
        // descriptor's useful pair.
        var luma = [UInt32](repeating: 4, count: 256)
        luma[0] = 2
        luma[255] = 6
        let stats = FilmStatsSeam.PlaneHistogram(perChannel: [
            luma, luma, luma, [UInt32](repeating: 4, count: 256),
        ])
        let descriptor = ProfileLatitudeDescriptor(
            evMin: -12, evMax: 12, usefulShadowEV: -3.0, usefulHighlightEV: 2.5,
            referenceEV: 0.05, response: [Float](repeating: 0.5, count: 8),
            slope: [Float](repeating: 0, count: 8), materialPairHash: 7)
        let live = PlacementResolver.anchors(stats: stats, descriptor: descriptor)
        XCTAssertFalse(live.usedFallback)
        XCTAssertEqual(live.cH, 2.5)
        XCTAssertEqual(live.cS, -3.0)
        // P99.9 of the 1024-total = target 1023 → the cumulative crosses
        // in the LAST bin; P0.1 target = 1 → the FIRST bin.
        let topEV = Foundation.log2((255.0 + 0.5) / 256.0 / 0.184)
        let bottomEV = Foundation.log2((0.0 + 0.5) / 256.0 / 0.184)
        XCTAssertEqual(live.aH, topEV, accuracy: 1e-12)
        XCTAssertEqual(live.aS, bottomEV, accuracy: 1e-12)

        // The descriptor alone (no stats) stays on the fallback (the C
        // anchors need BOTH faces — the A anchors have no source).
        let half = PlacementResolver.anchors(stats: nil, descriptor: descriptor)
        XCTAssertTrue(half.usedFallback)
    }

    // MARK: - 3: dynamic minimums + the §6.4 rows through the resolve face

    func testSliderMinimumsSideExplicit() {
        let mins = PlacementResolver.sliderMinimums(anchors: rfc64)
        XCTAssertEqual(mins.nH, 4.05, accuracy: 1e-12, "(a−C)+margin, highlights")
        XCTAssertEqual(mins.nS, 2.95, accuracy: 1e-12, "(C−a)+margin, shadows")
        // The side-off degenerate: the extreme at/below the boundary → 0.
        let off = PlacementAnchors(
            aH: 3.0, cH: 4.2, aS: -7.0, cS: -4.3, usedFallback: false)
        let offMins = PlacementResolver.sliderMinimums(anchors: off)
        XCTAssertEqual(offMins.nH, 0, "a_h ≤ C_h → the side is off")
        XCTAssertEqual(offMins.nS, 2.95, accuracy: 1e-12)
    }

    /// THE E3 GATE: the §6.4 four reference rows are ALL writable through
    /// the T3 validity face (rule ① rides the sliders; the typed refusal
    /// is reserved for input-domain violations) — and the resolved knees
    /// match the published values (the golden's own vectors, resolved
    /// through the panel's single source).
    func testResolveAcceptsAllRFC64RowsAndRejectsTheCrossing() {
        let rows: [(nH: Double, nS: Double, kH: Double, kS: Double)] = [
            (3.90, 2.80, +2.278, -2.703),
            (4.05, 2.95, +1.231, -1.783),
            (4.50, 2.95, -1.011, -1.783),
            (4.05, 3.40, +1.231, +0.266),
        ]
        for row in rows {
            let result = PlacementResolver.resolve(
                anchors: rfc64, nH: row.nH, nS: row.nS, m: 2)
            guard case .success(let params) = result else {
                XCTFail("row (\(row.nH),\(row.nS)) must be writable: \(result)")
                continue
            }
            XCTAssertEqual(params.kHighlight ?? 0, row.kH, accuracy: 5e-4)
            XCTAssertEqual(params.kShadow ?? 0, row.kS, accuracy: 5e-4)
            XCTAssertEqual(params.highlightsPullBack, Float(row.nH))
            XCTAssertEqual(params.rolloff, 2)
            // The wire discipline: the resolved knees ride the params.
            XCTAssertNotNil(params.kHighlight)
            XCTAssertNotNil(params.hShadow)
        }
        // The fifth row: the typed kneeOrder refusal (named, not clamped).
        let crossing = PlacementResolver.resolve(
            anchors: rfc64, nH: 4.50, nS: 3.40, m: 2)
        XCTAssertEqual(crossing, .failure(.kneeOrder))
        // The input-domain violations: the per-side named rejections.
        XCTAssertEqual(
            PlacementResolver.resolve(anchors: rfc64, nH: 3.0, nS: 2.95, m: 2),
            .failure(.highlightDemand))
        XCTAssertEqual(
            PlacementResolver.resolve(anchors: rfc64, nH: 4.05, nS: 2.0, m: 2),
            .failure(.shadowDemand))
    }

    // MARK: - 4: the Fit

    func testFitHMinSuggestionFaceRefusal() {
        // The §6.1 flagship scene at m=2: the fit pair IS (4.05, 2.95) but
        // its rooms (2.969 / 2.517) undercut H_min — the recommendation is
        // WITHHELD (the suggestion face; nothing writes).
        let outcome = PlacementResolver.fit(anchors: rfc61, m: 2)
        XCTAssertEqual(outcome.nH, 4.05, accuracy: 1e-9)
        XCTAssertEqual(outcome.nS, 2.95, accuracy: 1e-9)
        XCTAssertTrue(outcome.refusedByHMin, "the registered flagship-scene refusal")
        XCTAssertFalse(outcome.sharedDeficit)
        XCTAssertFalse(outcome.sidesOff)
    }

    func testFitAppliesOnAWideRoomScene() {
        // A deep-scene-vs-narrow-paper demand (N≈6/5): the solved rooms
        // clear the curvature ceiling → the recommendation LANDS (the
        // §6.4 row-3 shape — bigger pull-backs widen the rooms).
        let wide = PlacementAnchors(
            aH: 10.0, cH: 4.2, aS: -9.0, cS: -4.3, usedFallback: false)
        let outcome = PlacementResolver.fit(anchors: wide, m: 2)
        XCTAssertEqual(outcome.nH, 6.05, accuracy: 1e-9)
        XCTAssertEqual(outcome.nS, 4.95, accuracy: 1e-9)
        XCTAssertFalse(outcome.refusedByHMin)
        if case .success(let params) = PlacementResolver.resolve(
            anchors: wide, nH: outcome.nH, nS: outcome.nS, m: 2) {
            XCTAssertGreaterThan(params.hHighlight ?? 0, PlacementResolver.hMin)
        } else {
            XCTFail("the wide-paper fit must resolve")
        }
    }

    func testFitCrossingShareAtM3LandsOnTheSidesOffDegenerate() {
        // The m=3 minimum cross (the registered example): the margin fit
        // crosses (K_h=−0.602 < K_s=−0.293, independently recomputed), the
        // share engages, and the honest landing = both sides OFF (even
        // λ→0 stays crossed within the rule-① domain — DECISIONS).
        let outcome = PlacementResolver.fit(anchors: rfc61, m: 3)
        XCTAssertTrue(outcome.sharedDeficit, "the share path engaged")
        XCTAssertTrue(outcome.sidesOff, "the λ→0 degenerate")
        XCTAssertEqual(outcome.nH, 0)
        XCTAssertEqual(outcome.nS, 0)
        // And the crossing itself, verified directly (the plan's numbers).
        let hi = FilmPlacementModule.solveKnee(
            pullBack: 4.05, rolloff: 3, sceneExtreme: 8, mediumBoundary: 4.2)
        let lo = FilmPlacementModule.solveKnee(
            pullBack: 2.95, rolloff: 3, sceneExtreme: -7, mediumBoundary: -4.3)
        XCTAssertEqual(hi?.knee ?? 0, -0.602, accuracy: 2e-3)
        XCTAssertEqual(lo?.knee ?? 0, -0.293, accuracy: 2e-3)
        XCTAssertGreaterThan(lo!.knee, hi!.knee, "the m=3 knees cross")
    }

    // MARK: - 5: the endpoint slopes (the §6.4 published row 2)

    func testEndpointSlopesMatchThePublishedRow() {
        let hi = FilmPlacementModule.solveKnee(
            pullBack: 4.05, rolloff: 2, sceneExtreme: 8, mediumBoundary: 4.2)
        let lo = FilmPlacementModule.solveKnee(
            pullBack: 2.95, rolloff: 2, sceneExtreme: -7, mediumBoundary: -4.3)
        let slopeH = PlacementResolver.endpointSlope(
            extreme: 8, boundary: 4.2, knee: hi!.knee, m: 2)
        let slopeS = PlacementResolver.endpointSlope(
            extreme: -7, boundary: -4.3, knee: lo!.knee, m: 2)
        XCTAssertEqual(slopeH, 0.0648, accuracy: 5e-4, "f'(+8) per §6.4")
        XCTAssertEqual(slopeS, 0.0820, accuracy: 5e-4, "f'(−7) per §6.4")
    }

    // MARK: - 6: the session faces

    func testAddPlacementLandsTwoCommitsAndResolvesThroughTheLayerHost() async throws {
        try await loadGradient()
        XCTAssertNil(model.placementTarget)
        let before = editorState.history.items.count
        model.addPlacement()
        try await waitForItemCount(before + 2)
        // The add = ONE structure item (the layer host) + the module's
        // layer-chain item.
        XCTAssertNotNil(model.placementTarget)
        XCTAssertNotNil(model.placementTarget?.layerID, "the grade envelope's layer host")
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_layer_module_add"))
        // The resolver writes the resolved face (fallback anchors in this
        // bare session): valid N only.
        let outcome = model.commitPlacement(nH: 3.25, nS: 0, m: 2)
        XCTAssertEqual(outcome, .committed)
        await waitForPlacement(
            { $0?.highlightsPullBack == 3.25 }, hint: "the discrete commit")
        XCTAssertNotNil(
            model.placementParams?.kHighlight, "the resolved knees ride the params")
        XCTAssertNil(model.lastPlacementRejection)
        // The params round-trip: a second distinct value commits again.
        XCTAssertEqual(
            model.commitPlacement(nH: 3.6, nS: 0, m: 2), .committed)
        await waitForPlacement(
            { $0?.highlightsPullBack == 3.6 }, hint: "the second commit")
    }

    func testPlacementTrioLandsOneItemAndRejectionSnapsBack() async throws {
        try await loadGradient()
        model.addPlacement()
        try await waitForItemCount(2)
        let itemsAfterAdd = editorState.history.items.count
        // The live window: begin → ticks (zero items) → end (ONE item).
        model.beginPlacementDrag()
        model.tickPlacement(highlights: 3.4, shadows: nil)
        await waitForPlacement(
            { $0?.highlightsPullBack == 3.4 }, hint: "the live tick")
        XCTAssertEqual(
            editorState.history.items.count, itemsAfterAdd,
            "live ticks land ZERO items")
        model.endPlacementDrag()
        try await waitForItemCount(itemsAfterAdd + 1)
        XCTAssertEqual(
            editorState.history.items.last?.label,
            String(localized: "history_film_placement"))

        // The typed refusal: an invalid demand writes NOTHING (the truth
        // the slider binding reads — the snap-back).
        let before = model.placementParams
        model.tickPlacement(highlights: 1.0, shadows: nil)
        XCTAssertEqual(model.lastPlacementRejection, .highlightDemand)
        XCTAssertEqual(model.placementParams, before, "the rejected tick left the truth")
    }

    // MARK: - the teaching keys' static face (F-2)

    func testTeachingKeysAreStaticStrings() {
        let keys = [
            "latitude_teaching_scene_vs_dev",
            "latitude_teaching_edr_output",
            "latitude_histogram_placeholder",
            "latitude_descriptor_missing",
            "latitude_fallback_note",
            "latitude_reject_knee_order",
            "latitude_reject_highlight_demand",
            "latitude_reject_shadow_demand",
            "latitude_fit_refused_hmin",
            "latitude_fit_shared",
            "latitude_fit_sides_off",
        ]
        for key in keys {
            let value = String(localized: String.LocalizationValue(key))
            XCTAssertFalse(value.isEmpty, "\(key) resolves")
            XCTAssertFalse(value == key, "\(key) must not fall back to the bare key")
            XCTAssertFalse(
                value.contains("%"), "\(key) must carry no interpolation (F-2)")
        }
    }
}
