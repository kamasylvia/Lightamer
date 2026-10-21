@testable import Lightamer
@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Metal
import XCTest

// LensDefaultsWiringTests (B-2, LENS-01 acceptance 2nd) — the ANTI-DEAD-END
// regression for the reloadDefaults production wiring.
//
// ONION LESSON: the pre-wiring acceptance proved `IOPModule.reloadDefaults`
// had zero production call sites while 17 module-level tests stayed green —
// module-internal tests CANNOT catch a dead write path. Every test here goes
// through the REAL production seam code (the exact functions the
// coordinator's pristine-load branch and the panel's selection commit call):
//   ① the load seam (`LensDefaultsWiring.injectedLensSeed`) — the EXIF
//     resolve-input snapshot + the opt-in auto-apply (source flip + the
//     synchronous bake, D-L4-1 option A) must make a fresh raster document
//     RESOLVE (the render gate's correction face);
//   ② the browser-selection seam (`LensDefaultsWiring.committedSelection`)
//     — the selection commit must fold the EXIF inputs, flip the source,
//     and bake a FRESH snapshot (a stale prior snapshot never survives a
//     missed re-selection);
//   ③ the E2E coordinator.load leg — the pristine seed the editor actually
//     carries after a real `PipeCoordinator.load` (this leg COMPILES on the
//     pre-fix tree and FAILS there: the runtime red proof; the two helpers
//     above did not exist pre-fix — their absence is the compile red).
//
// RED LEGS (both required by the batch discipline):
//   - runtime: the E2E load leg asserts the seeded lens record carries the
//     EXIF inputs + an active source — on the pre-wiring tree the seed is
//     the static `LensModule.Params()` (source .off, focal nil) → FAIL;
//   - source-level: `grep -rn "LensDefaultsWiring\." App/Sources` ≥ 2
//     production call sites (PipeCoordinator + LensPanelView), and
//     `git log -S ".reloadDefaults(image" -- App` lands this batch.
@MainActor
final class LensDefaultsWiringTests: XCTestCase {

    // MARK: - Fixtures (hermetic inline XML — LensMatchHardeningTests twin)

    /// Sony set: one camera + one 16mm lens with a ptlens calibration (the
    /// match needs focal > 0 + a key; the bake needs a matched entry).
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

    override func setUp() {
        super.setUp()
        // Each test installs its own DB face; the auto-apply key starts
        // ABSENT (the default-false contract).
        UserDefaults.standard.removeObject(forKey: LensAutoApplySetting.defaultsKey)
    }

    override func tearDown() {
        LensfunStore.uninstall()
        UserDefaults.standard.removeObject(forKey: LensAutoApplySetting.defaultsKey)
        super.tearDown()
    }

    private func installDB() {
        LensfunStore.install(db: LensfunDBLoader.parse(Data(Self.sonyXML.utf8)))
    }

    private func makeImage(
        embedded: EmbeddedGeometryState? = .notApplicable,
        lensModel: String? = "E 16mm f/2.8",
        focal: Double? = 16
    ) -> DecodedImage {
        var cap = CaptureMetadata()
        cap.lensModel = lensModel
        cap.focalLength = focal
        // 35mm derivation (X4 priority tier 1): 24/16 = 1.5 — opens the
        // crop gate against the 1.534-crop lens entry (1.5/1.534 = 0.978
        // ≥ 0.96; D-L1-10's gate — the fixture mirrors a real APS-C body
        // reporting FocalLengthIn35mm).
        cap.focalLength35mm = focal.map { $0 * 1.5 }
        return DecodedImage(
            ciImage: CIImage.empty(), rawTech: RAWTechnicalParams(), capture: cap,
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: nil,
            embeddedGeometry: embedded)
    }

    private func lensSeedRecord() -> ModuleInstance {
        ModuleInstance(module: LensModule.self, params: LensModule.Params())
    }

    private func lensParams(of record: ModuleInstance) throws -> LensModule.Params {
        try XCTUnwrap(record.params(of: LensModule.self))
    }

    // MARK: - Seam ① the pristine-load seed

    /// THE anti-dead-end gate: autoApply ON + raster + lens EXIF through the
    /// REAL load seam → the seeded params carry an ACTIVE lensfun source and
    /// RESOLVE (the render gate produces the correction). Pre-wiring, this
    /// exact call path did not exist and the seed stayed static-neutral.
    func testLoadSeamAutoAppliesAndResolves() async throws {
        installDB()
        LensAutoApplySetting.write(true) // the production key (panel toggle face)
        let seed = [lensSeedRecord()]
        let out = await LensDefaultsWiring.injectedLensSeed(
            into: seed, image: makeImage())
        let p = try lensParams(of: out[0])
        XCTAssertEqual(p.source, .lensfun, "auto-apply must flip the source at load")
        XCTAssertEqual(p.focalLength, 16, "the EXIF snapshot must ride the seed")
        XCTAssertEqual(p.lensKey, "E 16mm f/2.8")
        // The render face: the seeded doc must resolve (a real correction,
        // not the missingFocal identity downgrade).
        XCTAssertNotNil(
            LensfunStore.resolveCommitted(p, width: 64, height: 64),
            "the auto-applied seed must RESOLVE — the write path is alive")
        // Identity preservation (NDE-1): the seam re-params, never re-mints.
        XCTAssertEqual(out[0].id, seed[0].id)
        XCTAssertEqual(out[0].multiPriority, seed[0].multiPriority)
    }

    /// autoApply OFF (the default): the EXIF inputs still fold (the browser
    /// seam needs them) but the source stays .off — the render face stays
    /// the neutral blit.
    func testLoadSeamAutoApplyOffKeepsExifInputsOnly() async throws {
        installDB()
        // key absent = OFF
        let seed = [lensSeedRecord()]
        let out = await LensDefaultsWiring.injectedLensSeed(
            into: seed, image: makeImage())
        let p = try lensParams(of: out[0])
        XCTAssertEqual(p.source, .off, "the opt-in default must not flip the source")
        XCTAssertEqual(p.focalLength, 16, "the EXIF snapshot rides regardless")
        XCTAssertEqual(p.lensKey, "E 16mm f/2.8")
    }

    /// The mutex hard guard THROUGH the seam: a detected (RAW) document
    /// never auto-triggers, even with the key ON (D-LENS-1: notApplicable
    /// is the only effective domain).
    func testLoadSeamHardGuardDetectedNeverAutoApplies() async throws {
        installDB()
        LensAutoApplySetting.write(true)
        let seed = [lensSeedRecord()]
        let out = await LensDefaultsWiring.injectedLensSeed(
            into: seed, image: makeImage(embedded: .detected))
        let p = try lensParams(of: out[0])
        XCTAssertEqual(p.source, .off, "detected = the hard guard, never auto")
        XCTAssertEqual(p.embeddedGeometry, .detected, "the judgment rides the seed")
    }

    /// A seed without a lens record passes through verbatim (the
    /// terminal-trio-only chains).
    func testLoadSeamWithoutLensRecordIsVerbatim() async throws {
        let trio = ModuleInstance(
            module: ColorInModule.self, params: ColorInModule.Params())
        let out = await LensDefaultsWiring.injectedLensSeed(
            into: [trio], image: makeImage())
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0], trio)
    }

    // MARK: - Seam ② the browser selection commit

    /// THE browser-path anti-dead-end gate: the selection commit through the
    /// REAL seam folds the EXIF inputs (pre-wiring: EXIF-less params →
    /// missingFocal → identity + "no lens info"), flips the source, and
    /// bakes a FRESH snapshot that RESOLVES.
    func testBrowserSelectionCommitFoldsExifAndBakes() async throws {
        installDB()
        // autoApply stays OFF: the selection must not depend on it.
        let base = LensModule.Params() // the EXIF-less face (pre-wiring shape)
        let candidate = LensProfileCandidate(
            maker: "Sony", model: "E 16mm f/2.8", score: 100, lowConfidence: false)
        let committed = await LensDefaultsWiring.committedSelection(
            base: base, candidate: candidate, image: makeImage())
        XCTAssertEqual(committed.source, .lensfun)
        XCTAssertEqual(committed.lensKey, "E 16mm f/2.8", "the picked model lands")
        XCTAssertEqual(committed.focalLength, 16, "the EXIF inputs folded in")
        XCTAssertNotNil(
            LensfunStore.resolveCommitted(committed, width: 64, height: 64),
            "selection = correction: the committed params must RESOLVE")
    }

    /// A missed re-selection clears any STALE prior snapshot (the rematch
    /// face): the render honestly drops the previous correction instead of
    /// silently keeping it while the readout shows the miss.
    func testBrowserSelectionMissClearsStaleSnapshot() async throws {
        installDB()
        // A previously-baked doc (snapshot stamped) re-selecting a lens the
        // DB does not carry.
        var stale = LensModule.Params(source: .lensfun, focalLength: 16)
        stale.snapshot = LensCoefficientSnapshot()
        let candidate = LensProfileCandidate(
            maker: "Nikon", model: "Totally Absent Optic 12345", score: 100,
            lowConfidence: false)
        let committed = await LensDefaultsWiring.committedSelection(
            base: stale, candidate: candidate, image: makeImage())
        XCTAssertEqual(committed.source, .lensfun)
        XCTAssertEqual(committed.lensKey, "Totally Absent Optic 12345")
        XCTAssertNil(
            committed.snapshot,
            "the stale snapshot must not survive a missed re-selection")
    }

    // MARK: - m-5 the manual arm's projection fold

    /// Manual coefficients + a projection pick: resolveUniforms must carry
    /// the SAME fold the panel's resolvedScalePreview manual arm shows (the
    /// pre-m5 divergence: readout folded, render silently unfolded).
    func testManualArmFoldsProjectionRaws() async throws {
        let module = LensModule()
        var manual = LensModule.Params(source: .manual)
        manual.distortionK1 = -0.01
        module.setCommittedForTesting(manual)

        // Baseline: no projections → the rectilinear identity fold.
        let plainResult = await module.resolveUniforms(
            bufW: 1000, bufH: 800,
            roiIn: ROI(x: 0, y: 0, width: 1000, height: 800, scale: 1.0),
            roiOut: ROI(x: 0, y: 0, width: 1000, height: 800, scale: 1.0))
        let plain = try XCTUnwrap(plainResult)
        XCTAssertEqual(plain.sourceProj.x, Int32(LensProjection.rectilinear.slotIndex))
        XCTAssertEqual(plain.sourceProj.y, Int32(LensProjection.rectilinear.slotIndex))

        // The fold: target fisheye + source equirectangular ride the raws.
        manual.targetProjection = LensProjection.fisheye.rawValue
        manual.sourceProjection = LensProjection.equirectangular.rawValue
        module.setCommittedForTesting(manual)
        let foldedResult = await module.resolveUniforms(
            bufW: 1000, bufH: 800,
            roiIn: ROI(x: 0, y: 0, width: 1000, height: 800, scale: 1.0),
            roiOut: ROI(x: 0, y: 0, width: 1000, height: 800, scale: 1.0))
        let folded = try XCTUnwrap(foldedResult)
        XCTAssertEqual(
            folded.sourceProj.y, Int32(LensProjection.fisheye.slotIndex),
            "the manual arm must fold the TARGET projection (m-5)")
        XCTAssertEqual(
            folded.sourceProj.x, Int32(LensProjection.equirectangular.slotIndex),
            "the manual arm must fold the SOURCE projection (m-5)")
    }

    // MARK: - E2E the real coordinator.load pristine branch (runtime red leg)

    /// The REAL load chain: a pristine `PipeCoordinator.load` of a synthetic
    /// raster document (autoApply ON) must seed the editor's lens record
    /// with the EXIF inputs + an active source. THE RUNTIME RED LEG: this
    /// test compiles on the pre-wiring tree (load's signature is untouched)
    /// and FAILS there — the pre-wiring seed is the static neutral params.
    func testCoordinatorLoadSeedsLensThroughRealLoadChain() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        installDB()
        LensAutoApplySetting.write(true)

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lens-wiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        let editorState = EditorState()
        let coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        coordinator.attach(registry: registry)

        // Synthetic raster plane (EditorMetalLegRegressionTests' shape) with
        // lens EXIF + the notApplicable judgment — the auto-apply domain.
        var cap = CaptureMetadata()
        cap.lensModel = "E 16mm f/2.8"
        cap.focalLength = 16
        cap.focalLength35mm = 24 // the crop gate opener (see makeImage)
        let gradient = CIImage(color: CIColor(red: 0.55, green: 0.45, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let decoded = DecodedImage(
            ciImage: gradient, rawTech: RAWTechnicalParams(), capture: cap,
            segmentationSkyMatte: nil, decoderVersionUsed: .v8, contentDedupeID: 0,
            embeddedGeometry: .notApplicable)

        let url = tempDirectory.appendingPathComponent("lens-wiring.tif")
        try await coordinator.load(url: url, decoded: decoded, instances: [], metal: metal)

        // The pristine seed the editor actually carries.
        let lensRecord = try XCTUnwrap(
            editorState.instances.first { $0.opName == LensModule.opName },
            "the pristine load must seed a lens record")
        let p = try lensParams(of: lensRecord)
        XCTAssertEqual(
            p.source, .lensfun,
            "the REAL load chain must carry the auto-applied source (B-2 seam ①)")
        XCTAssertEqual(p.focalLength, 16)
        XCTAssertNotNil(
            LensfunStore.resolveCommitted(p, width: 64, height: 64),
            "the loaded document must RESOLVE — the write path is alive end-to-end")
    }
}
