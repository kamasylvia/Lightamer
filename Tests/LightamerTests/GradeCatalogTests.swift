import LightamerCore
import LightamerIOP
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// GradeCatalogTests (Plan M2-5-1 T1) — the grade registry face (KD-1) + the
// LIGHTAMER V50Order rows (KD-3). M3-3-02 T4 adds the 19th catalog row
// (filmPlacement — counts 18/14/17 → 19/15/18); M5-1-01 T5 adds the 20th
// (colormatch — counts 19/15/18 → 20/16/19):
//
//   1. SHAPE: exactly 20 catalog rows (FEATURE-MAP §2.1 order + the
//      M3-3-02 placement row + the M5-1-01 colormatch row), 16 grade-owned
//      (14 + Tint + colormatch), unique catalogIDs.
//   2. COMPLETENESS (checker E7): the default-face registry op set minus
//      (the 19 catalog ops ∪ {testgain}) = ∅. THE testgain EXEMPTION: it
//      is the DEBUG-only registration (Registry.swift `#if DEBUG` — the
//      module type is compiled out of Release), NOT a catalog omission;
//      this note is the pin that keeps a later reader from "fixing" it.
//   3. OWNER MATRIX: all 19 rows carry the expected owner, the catalog
//      column and owner(of:) AGREE (the KD-1 consumption face), the four
//      DRT/Post seats are named, and the develop family regression holds.
//   4. V50 UNIQUENESS (KD-3 invariants): the eleven LIGHTAMER rows are
//      mutually unique; disjoint from every REGISTERED op's position; the
//      whole-table position collisions are exactly {28.5 cluster, 41.0
//      colorWheels↔colorbalance} — the ONE declared exception.
//   5. DEFAULT LOOK (KD-9): the three entries decode to +1.5 EV /
//      +15 / 1.3 on the right ops.
//   6. IDENTITY SNAPSHOTS (checker m5): the five aligned ops' identityJSON
//      decodes to the kernel no-op parameter points; shadhi's snapshot
//      (shadows 0 / highlights 0) is DISTINCT from its panel defaults
//      (50 / −50) — two separate values, by design.
// ─────────────────────────────────────────────────────────────────────────────

final class GradeCatalogTests: XCTestCase {

    // MARK: - 1: shape

    func testExactlyEighteenItemsInFeatureMapOrder() {
        XCTAssertEqual(GradeCatalog.items.count, 20)
        XCTAssertEqual(
            GradeCatalog.items.map(\.catalogID),
            [
                "cat02WhiteBalance", "exposure", "contrast", "white", "black",
                "shadows", "highlights", "curve", "hls", "saturation",
                "vibrance", "colorWheel", "lmt", "tint",
                "clarity", "sharpen", "halation", "filmGrain",
                "filmPlacement", "colormatch",
            ],
            "the FEATURE-MAP §2.1 table order + the placement and colormatch rows")
        XCTAssertEqual(Set(GradeCatalog.items.map(\.catalogID)).count, 20, "unique ids")
    }

    func testGradeItemsAreExactlyFourteen() {
        let grade = GradeCatalog.gradeItems()
        XCTAssertEqual(grade.count, 16, "14 Grade ops + Tint + colormatch (M5-1-01)")
        XCTAssertEqual(grade.filter { $0.catalogID == "tint" }.count, 1)
        XCTAssertTrue(grade.allSatisfy { $0.owner == .grade })
        // The four DRT/Post seats never leak into the grade face.
        let drt = GradeCatalog.items.filter { $0.owner == .drtPost }
        XCTAssertEqual(
            drt.map(\.catalogID), ["clarity", "sharpen", "halation", "filmGrain"])
    }

    // MARK: - 2: completeness (registry face ∖ (catalog ∪ {testgain}) = ∅)

    /// The default-face registry op set: the terminal trio + the editing
    /// seed under the M2-1 narrowed face (same construction the
    /// NodeOwnershipCatalogTests completeness test uses).
    private func defaultFaceRegistryOps() async -> Set<String> {
        var face = Set(
            await ModuleRegistry.makeDefault().makeDefaultInstances().map(\.opName))
        face.formUnion(
            LightamerIOPRegistry.editingDefaultInstances(defaultFace: true).map(\.opName))
        return face
    }

    func testDefaultFaceIsCoveredByCatalogPlusTestgainExemption() async {
        // E7 completeness, executor form (the formula reading is signed in
        // M2-5-1-DECISIONS): the default face carries BOTH the 18 closed
        // catalogs AND the legacy D6-era grade modules (colisa/toneequal/
        // …) that answer through the default arm — so the machine check
        // pins the three true facts:
        //   (a) the ALIGNED catalog ops (pre-existing five + the DRT/Post
        //       four) are default-face registered TODAY;
        //   (b) the seven M2-5-1 ops join the face with their
        //       implementation commits (T7 asserts the full closure in
        //       testAllCatalogOpsAreDefaultFaceRegistered);
        //   (c) testgain is the DEBUG-only registration exemption
        //       (Registry.swift `#if DEBUG` — the module type is compiled
        //       out of Release; a Release face never contains it) — it is
        //       NOT a missed catalog row, and this note is the pin that
        //       keeps a later reader from "fixing" it.
        let face = await defaultFaceRegistryOps()
        let catalogOps = Set(GradeCatalog.items.map(\.opName))
        XCTAssertEqual(catalogOps.count, 19, "20 rows; Shadows/Highlights share the shadhi op")
        // The SEED-DEFERRED ops (join the editing seed with their panels —
        // the M2-5-1 seven + the M3-3-02 placement op, whose FSIM-02 panel
        // is M3-4; each IS default-face REGISTERED, only seed membership
        // waits). The subset check below pins the PRE-EXISTING aligned ops.
        let newSevenOps: Set<String> = [
            Cat02WBModule.opName, ContrastModule.opName, WhiteModule.opName,
            BlackModule.opName, SaturationModule.opName, TintModule.opName,
            ColorWheelsModule.opName, HlsModule.opName,
            FilmPlacementModule.opName,
            ColormatchModule.opName,
        ]
        let alignedOps = catalogOps.subtracting(newSevenOps)
        XCTAssertTrue(
            alignedOps.isSubset(of: face),
            "the pre-existing catalog ops must be default-face registered")
        // The testgain exemption is a REGISTRATION fact (not a seed one):
        // populate(defaultFace:) registers it under DEBUG only.
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)
        let testgainBox = await registry.makeBox(opName: TestGainModule.opName)
        #if DEBUG
        XCTAssertNotNil(testgainBox, "the DEBUG face registers testgain (the E7 exemption)")
        #else
        XCTAssertNil(testgainBox, "the Release face excludes testgain")
        #endif
    }

    /// DECISIONS §3 (b), the T7 closure: all 20 catalog rows' ops (19
    /// unique opNames — Shadows/Highlights share shadhi) RESOLVE from the
    /// default-face-populated registry. This is the strict-face narrowing
    /// precondition the P2 panels build on. Seed membership is deliberately
    /// NOT asserted here — the grade ops join the editing seed with their
    /// panels (M2-5-1-SUMMARY 移交), so the closure face is the registry
    /// registration face, not `editingDefaultInstances`.
    func testAllCatalogOpsAreDefaultFaceRegistered() async {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry, defaultFace: true)
        var resolved: Set<String> = []
        for item in GradeCatalog.items where !resolved.contains(item.opName) {
            let box = await registry.makeBox(opName: item.opName)
            XCTAssertNotNil(box, "\(item.opName) must be default-face registered")
            resolved.insert(item.opName)
        }
        XCTAssertEqual(resolved.count, 19, "19 unique catalog ops all resolve")
    }

    // MARK: - 3: the owner matrix

    func testOwnerMatrixOverAllEighteenRows() {
        let expected: [String: NodeOwnership] = [
            "cat02WhiteBalance": .grade,
            "exposure": .grade,
            "contrast": .grade,
            "white": .grade,
            "black": .grade,
            "shadows": .grade,
            "highlights": .grade,
            "curve": .grade,
            "hls": .grade,
            "saturation": .grade,
            "vibrance": .grade,
            "colorWheel": .grade,
            "lmt": .grade,
            "tint": .grade,
            "clarity": .drtPost,
            "sharpen": .drtPost,
            "halation": .drtPost,
            "filmGrain": .drtPost,
            "filmPlacement": .grade,
            "colormatch": .grade,
        ]
        for item in GradeCatalog.items {
            XCTAssertEqual(
                item.owner, expected[item.catalogID],
                "\(item.catalogID) owner drifted")
            // KD-1 consumption face: the table column and owner(of:) agree.
            XCTAssertEqual(
                NodeOwnershipCatalog.owner(of: item.opName), item.owner,
                "owner(of:) must consume the catalog column for \(item.catalogID)")
        }
        // The shared shadhi op resolves (first match) to a catalog row.
        XCTAssertEqual(GradeCatalog.item(opName: ShadhiModule.opName)?.catalogID, "shadows")
    }

    func testDevelopFamilyRegressionUnchanged() {
        // The catalog extension changed NO develop answer (the M2-4-1 grace
        // table still governs; NodeOwnershipCatalogTests pins the full set).
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: TemperatureModule.opName), .develop)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: LensModule.opName), .develop)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: FilmicRGBModule.opName), .develop)
        // Non-catalog, non-exception ops keep the default arm.
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: ColisaModule.opName), .grade)
        XCTAssertEqual(NodeOwnershipCatalog.owner(of: ColorInModule.opName), .grade)
    }

    // MARK: - 4: V50 uniqueness (KD-3 invariants)

    private static let lightamerGradeRows: [(String, Float)] = [
        ("acesccIn", 20.5),
        ("filmPlacement", 20.8),
        ("colormatch", 36.5),
        ("acesccOut", 69.9),
        ("colorWheels", 41.0),
        ("cat02WhiteBalance", 41.4),
        ("contrast", 41.6),
        ("white", 41.8),
        ("black", 41.95),
        ("saturation", 42.2),
        ("tint", 42.4),
        ("hls", 42.6),
    ]

    func testLightamerRowsPresentWithPinnedValues() {
        for (op, order) in Self.lightamerGradeRows {
            XCTAssertEqual(V50Order.order(for: op), order, "\(op) drifted")
        }
        // The envelope-entry/exit relations (KD-3): acesccIn sits BELOW the
        // lowest 18-catalog op (exposure 21.0); acesccOut sits ABOVE every
        // in-domain op and BELOW the 70.0 terminal floor. M3-3-02: the
        // placement op is the FIRST grade-domain mapping (acesccIn <
        // filmPlacement < exposure).
        XCTAssertLessThan(V50Order.order(for: "acesccIn")!, V50Order.order(for: "filmPlacement")!)
        XCTAssertLessThan(V50Order.order(for: "filmPlacement")!, V50Order.order(for: "exposure")!)
        XCTAssertLessThan(V50Order.order(for: "acesccIn")!, V50Order.order(for: "exposure")!)
        XCTAssertGreaterThan(V50Order.order(for: "retouch")!, 0)
        XCTAssertLessThan(V50Order.order(for: "retouch")!, V50Order.order(for: "acesccIn")!)
        XCTAssertLessThan(V50Order.order(for: "splittoning")!, V50Order.order(for: "acesccOut")!)
        XCTAssertLessThan(V50Order.order(for: "acesccOut")!, V50Order.order(for: "colorout")!)
    }

    func testLightamerRowsAreMutuallyUnique() {
        let orders = Self.lightamerGradeRows.map(\.1)
        XCTAssertEqual(Set(orders).count, orders.count, "the eleven LIGHTAMER rows are unique")
    }

    func testLightamerRowsDisjointFromRegisteredOpPositions() async {
        let newPositions = Set(Self.lightamerGradeRows.map(\.1))
        for op in await defaultFaceRegistryOps() {
            guard let position = V50Order.order(for: op) else {
                continue // no V50 slot (none expected in the default face)
            }
            XCTAssertFalse(
                newPositions.contains(position),
                "new LIGHTAMER row collides with REGISTERED op \(op) at \(position)")
        }
    }

    func testWholeTableCollisionsAreOnlyTheDeclaredExceptions() {
        let grouped = Dictionary(grouping: V50Order.entries, by: \.order).filter { $0.value.count > 1 }
        // The 28.5 dt cluster (six verbatim rows) + the ONE declared M2-5-1
        // exception: colorWheels shares 41.0 with the UNREGISTERED dt
        // colorbalance row (KD-3 — a future dt-colorbalance enablement
        // re-homes one of the two; declared in M2-5-1-DECISIONS).
        XCTAssertEqual(Set(grouped.keys), [28.5, 41.0])
        XCTAssertEqual(
            Set(grouped[28.5]!.map(\.opName)),
            ["channelmixerrgb", "diffuse", "censorize", "negadoctor", "blurs", "primaries"])
        XCTAssertEqual(
            Set(grouped[41.0]!.map(\.opName)), ["colorbalance", "colorWheels"])
    }

    // MARK: - 5: the default look (KD-9)

    func testDefaultLookThreeEntriesDecodeToPinnedValues() throws {
        XCTAssertEqual(GradeCatalog.defaultLook.count, 3)
        let exposure = GradeCatalog.defaultLook[0]
        XCTAssertEqual(exposure.opName, ExposureModule.opName)
        XCTAssertEqual(
            try JSONDecoder().decode(ExposureModule.Params.self, from: Data(exposure.paramsJSON.utf8))
                .exposure, 1.5)
        let contrast = GradeCatalog.defaultLook[1]
        XCTAssertEqual(contrast.opName, ContrastModule.opName)
        XCTAssertEqual(
            try JSONDecoder().decode(ContrastModule.Params.self, from: Data(contrast.paramsJSON.utf8))
                .contrast, 15)
        let saturation = GradeCatalog.defaultLook[2]
        XCTAssertEqual(saturation.opName, SaturationModule.opName)
        XCTAssertEqual(
            try JSONDecoder().decode(SaturationModule.Params.self, from: Data(saturation.paramsJSON.utf8))
                .saturation, 1.3)
    }

    // MARK: - 6: the identity snapshots (checker m5)

    private func identityItem(_ catalogID: String) throws -> GradeCatalogItem {
        guard let item = GradeCatalog.items.first(where: { $0.catalogID == catalogID }) else {
            XCTFail("catalog row \(catalogID) missing")
            throw NSError(domain: "GradeCatalogTests", code: 1)
        }
        return item
    }

    func testAlignedFiveIdentitySnapshotsAreKernelNoOpPoints() throws {
        // exposure: 0 EV (the exposure-0EV identity the whole cache story
        // rides on).
        let exposure = try JSONDecoder().decode(
            ExposureModule.Params.self,
            from: Data(try identityItem("exposure").identityJSON.utf8))
        XCTAssertEqual(exposure.exposure, 0)
        XCTAssertEqual(exposure.black, 0)
        // shadhi: the kernel no-op point (shadows 0 / highlights 0).
        let shadhi = try JSONDecoder().decode(
            ShadhiModule.Params.self,
            from: Data(try identityItem("shadows").identityJSON.utf8))
        XCTAssertEqual(shadhi.shadows, 0)
        XCTAssertEqual(shadhi.highlights, 0)
        // vibrance: amount 0.
        let vibrance = try JSONDecoder().decode(
            VibranceModule.Params.self,
            from: Data(try identityItem("vibrance").identityJSON.utf8))
        XCTAssertEqual(vibrance.amount, 0)
        // tonecurve: the default flat/identity curves.
        let curve = try JSONDecoder().decode(
            ToneCurveModule.Params.self,
            from: Data(try identityItem("curve").identityJSON.utf8))
        XCTAssertEqual(curve, ToneCurveModule.Params())
        // lut3d: no LUT loaded (the blit identity).
        let lut = try JSONDecoder().decode(
            Lut3dModule.Params.self,
            from: Data(try identityItem("lmt").identityJSON.utf8))
        XCTAssertNil(lut.lutName)
    }

    func testShadhiPanelDefaultsAreDistinctFromIdentitySnapshot() throws {
        // The checker-m5 declaration: shadhi's panel defaults (shadows 50 /
        // highlights −50) are a WORKING point, not an identity point — the
        // catalog snapshot and the panel default are two separate values
        // (P2 providers cite Params() defaults; Reset cites the snapshot).
        let snapshot = try JSONDecoder().decode(
            ShadhiModule.Params.self,
            from: Data(try identityItem("shadows").identityJSON.utf8))
        let panelDefault = ShadhiModule.Params()
        XCTAssertNotEqual(snapshot.shadows, panelDefault.shadows)
        XCTAssertNotEqual(snapshot.highlights, panelDefault.highlights)
        XCTAssertEqual(panelDefault.shadows, 50)
        XCTAssertEqual(panelDefault.highlights, -50)
    }

    func testNewSevenIdentitySnapshotsAreIdentityParams() throws {
        // The new ops' snapshots are their Params() identity values.
        let cat02 = try JSONDecoder().decode(
            Cat02WBModule.Params.self,
            from: Data(try identityItem("cat02WhiteBalance").identityJSON.utf8))
        XCTAssertEqual(cat02.temperature, 5999.9934)
        XCTAssertEqual(cat02.tint, 9.7112783)
        let white = try JSONDecoder().decode(
            WhiteModule.Params.self,
            from: Data(try identityItem("white").identityJSON.utf8))
        XCTAssertEqual(white.white, 0)
        let black = try JSONDecoder().decode(
            BlackModule.Params.self,
            from: Data(try identityItem("black").identityJSON.utf8))
        XCTAssertEqual(black.black, 0)
        let saturation = try JSONDecoder().decode(
            SaturationModule.Params.self,
            from: Data(try identityItem("saturation").identityJSON.utf8))
        XCTAssertEqual(saturation.saturation, 1.0)
        let tint = try JSONDecoder().decode(
            TintModule.Params.self,
            from: Data(try identityItem("tint").identityJSON.utf8))
        XCTAssertEqual(tint.tint, 0)
        let wheels = try JSONDecoder().decode(
            ColorWheelsModule.Params.self,
            from: Data(try identityItem("colorWheel").identityJSON.utf8))
        XCTAssertTrue(ColorWheelsModule.isIdentity(wheels))
        let hls = try JSONDecoder().decode(
            HlsModule.Params.self,
            from: Data(try identityItem("hls").identityJSON.utf8))
        XCTAssertEqual(hls, HlsModule.Params())
    }

    func testDRTPostIdentitySnapshotsAreNoOpPoints() throws {
        // clarity (equalizer): all-zero deltas.
        let equalizer = try JSONDecoder().decode(
            EqualizerModule.Params.self,
            from: Data(try identityItem("clarity").identityJSON.utf8))
        XCTAssertEqual(equalizer, EqualizerModule.Params())
        // sharpen: amount 0.
        let sharpen = try JSONDecoder().decode(
            SharpenModule.Params.self,
            from: Data(try identityItem("sharpen").identityJSON.utf8))
        XCTAssertEqual(sharpen.amount, 0)
        // halation (bloom) / filmGrain (grain): strength 0 (the kernel
        // no-op — NOT the module defaults, which the registry seeds
        // DISABLED for exactly that reason).
        let bloom = try JSONDecoder().decode(
            BloomModule.Params.self,
            from: Data(try identityItem("halation").identityJSON.utf8))
        XCTAssertEqual(bloom.strength, 0)
        let grain = try JSONDecoder().decode(
            GrainModule.Params.self,
            from: Data(try identityItem("filmGrain").identityJSON.utf8))
        XCTAssertEqual(grain.strength, 0)
    }
}
