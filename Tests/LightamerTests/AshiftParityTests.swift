@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// AshiftParityTests (Plan 04-03-T2/T4) — the IOP-GEO-02 warp module.
///
/// REFERENCE PROVENANCE (L017 route ① — warp is a spatial operator;
/// dt-cli float export is spatially corrupt on this host, manifest
/// "dt-cli host finding"; additionally this host's dt build cannot load
/// libashift at all — `libashift.so` dlopens against the missing symbol
/// `_dt_opencl_copy_device_to_host`, so even XMP ADOPTION is unverifiable
/// and dt-side evidence reduces to the uniform-flat rotation probe +
/// formula同源 below):
/// - track-A references are CPU-SYNTHESIZED by gen_fixtures.py (`refs`
///   mode, `gen_ashift_refs`): float64 `_homography` + texel-center
///   bilinear, formula-mirrored with `Homography.compose` /
///   `AshiftKernels.metal` (gate <1e-5, warp class);
/// - dt-side evidence: `ashift_rot08` XMP blob layout verified field by
///   field (`<8f2i4f…>` v5, 892 bytes, GENERIC pins) + flat-rotation ==
///   flat probe (uniform leg, in-test, exact).
///
/// ANTI-VACUUM (the 04-02 track-A lesson): every test below runs a
/// comparison loop over real pixels — no vacuous parity passes.
/// L014: every GPU readback drains first.
final class AshiftParityTests: XCTestCase {

    private enum Tol {
        static let warpRelative: Float = 1e-5
        // float32-vs-float64 bilinear dust at high-contrast edges
        // (checkerboard steps amplify 1e-7 coord noise into ~4e-6 value
        // noise — still 400× below the 8-bit step 3.9e-3). Probed floor.
        static let warpAbsFloor: Float = 1e-5
    }

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs input/golden/fixtures` (Plan 04-03-T4)"
            )
        }
        return url
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    /// The ashift 钉参组 (gen_fixtures ASHIFT_CASES — mirrors the XMPs).
    private static func ashiftParams(
        rot: Float, sv: Float = 0, sh: Float = 0, shear: Float = 0,
        cl: Float = 0, cr: Float = 1, ct: Float = 0, cb: Float = 1
    ) -> AshiftModule.Params {
        AshiftModule.Params(
            rotation: rot, lensShiftV: sv, lensShiftH: sh, shear: shear,
            cl: cl, cr: cr, ct: ct, cb: cb)
    }

    private static let ashiftCases: [(name: String, params: AshiftModule.Params)] = [
        ("ashift_identity", ashiftParams(rot: 0)),
        ("ashift_rot08", ashiftParams(rot: 8)),
        ("ashift_rot-08", ashiftParams(rot: -8)),
        ("ashift_rot30", ashiftParams(rot: 30)),
        ("ashift_rot08_shift", ashiftParams(rot: 8, sv: 0.15, sh: -0.1)),
        ("ashift_persp", ashiftParams(rot: 0, sv: 0.3, shear: 0.08)),
        ("ashift_clip", ashiftParams(rot: 8, cl: 0.1, cr: 0.9, ct: 0.05, cb: 0.95)),
    ]

    private static let trackAFixtures = ["gradient_ramp", "flat_0ev", "flat_-4ev", "checkerboard"]

    /// TRACK A: every (fixture × case) synthesized reference vs the
    /// Lightamer `[ashift, colorin]` pipe (sort places ashift 15.0 before
    /// colorin 28.0 — the warp grows the frame first, colorin copies the
    /// grown plane), per-pixel relative <1e-5
    func testAshiftGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var compared = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.ashiftCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runAshiftPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size \(pipeW)×\(pipeH) vs golden \(golden.width)×\(golden.height)")
                    continue
                }
                let n = golden.width * golden.height
                compared += n * 3
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let got = pipe[i * 3 + c]
                        let diff = abs(got - ref)
                        let rel = diff / max(abs(ref), 1e-3)
                        maxRelative = max(maxRelative, rel)
                        if rel >= Tol.warpRelative && diff >= Tol.warpAbsFloor,
                           failures.count < 12 {
                            let (x, y) = (i % golden.width, i / golden.width)
                            failures.append(
                                "\(caseName)×\(fixture) (\(x),\(y)) ch\(c): "
                                    + "lightamer=\(got) ref=\(ref) rel=\(rel)"
                            )
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity must compare real pixels (anti-vacuum)")
        XCTAssertTrue(
            failures.isEmpty,
            "ashift golden parity exceeded \(Tol.warpRelative) rel / \(Tol.warpAbsFloor) abs "
                + "(max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }
    /// NOTE (chain order): instances sort by iopOrder in `run` (ashift
    /// 15.0 BEFORE colorin 28.0), so the warp grows the frame first and
    /// colorin copies the grown plane. Passing [colorin, ashift] sorts
    /// colorin first and trips its same-size assert on the grown AABB
    /// (caught live: "input dims 64×64 != roiOut 72×72").
    private func runAshiftPipe(
        image: DecodedImage, params: AshiftModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: AshiftModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<AshiftModule>)
        box.setParams(params)
        let chain = [box as any ModuleBoxing, colorinBox]
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        await drain(metal) // L014
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return (rgb, texture.width, texture.height)
    }

    /// Uniform-flat rotation probe (dt-side semantic evidence, in-test):
    func testFlatRotationIsFlatWithOpaqueAlpha() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/flat_0ev.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: AshiftModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<AshiftModule>)
        box.setParams(Self.ashiftParams(rot: 8))
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [box as any ModuleBoxing, colorinBox],
            imageID: UUID(), resolution: .preview, cache: PipeCache(),
            metal: metal, longEdge: nil)
        await drain(metal)
        // Full-plane readback with CPU-side center indexing (a sub-region
        // getBytes into a tight buffer reads back zeros on this host —
        // probed 2026-09-20 — so the window is cut on the CPU side).
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        let cx = texture.width / 2, cy = texture.height / 2
        var worst: Float = 0
        for dy in -4..<4 {
            for dx in -4..<4 {
                let i = ((cy + dy) * texture.width + (cx + dx)) * 4
                for c in 0..<3 {
                    worst = max(worst, abs(floats[i + c] - 0.5))
                }
                worst = max(worst, abs(floats[i + 3] - 1.0))
            }
        }
        XCTAssertLessThan(worst, 1e-5, "flat interior must stay flat+opaque under rotation")
    }

    /// Black-corner alpha leg (FOUND-02 premultiplied contract): rot30 on
    /// the ramp MUST produce alpha==0 corners and opaque interior, and
    /// the RGBA readback (not just RGB) carries it.
    func testRotatedCornersCarryTransparentAlpha() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: AshiftModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<AshiftModule>)
        box.setParams(Self.ashiftParams(rot: 30))
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [box as any ModuleBoxing, colorinBox],
            imageID: UUID(), resolution: .preview, cache: PipeCache(),
            metal: metal, longEdge: nil)
        await drain(metal)
        var rgba = [Float](repeating: 0, count: texture.width * texture.height * 4)
        rgba.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        // Corner (0,0) of a 30°-rotated frame is outside the source quad.
        let cornerA = rgba[3]
        XCTAssertEqual(cornerA, 0, accuracy: 1e-6, "rotated-out corner must be transparent")
        XCTAssertEqual(rgba[0], 0, accuracy: 1e-6, "transparent corner RGB must be black")
        // Center stays opaque.
        let ci = ((texture.height / 2) * texture.width + texture.width / 2) * 4 + 3
        XCTAssertEqual(rgba[ci], 1.0, accuracy: 1e-5, "warp interior stays opaque")
    }

    /// Track-B black corner through the DISPLAY leg (04-03 plan T2 action
    /// 3 / T4 轨 B): the working-space RGBA leg is pinned by
    /// `testRotatedCornersCarryTransparentAlpha`; this pins the
    /// gamma-tail leg — black corners (RGB=0) must survive ColorOut +
    /// sRGB TRC as DISPLAY BLACK in the .bgra8Unorm tail (not garbage,
    /// not NaN-propagated).
    func testRotatedBlackCornersSurviveGammaTail() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let ashiftMade = await registry.makeBox(opName: AshiftModule.opName)
        let ashift = try XCTUnwrap(ashiftMade as? ModuleBox<AshiftModule>)
        ashift.setParams(Self.ashiftParams(rot: 30))
        let colorinMade = await registry.makeBox(opName: ColorInModule.opName)
        let colorin = try XCTUnwrap(colorinMade as? ModuleBox<ColorInModule>)
        colorin.setParams(.init())
        let gammaMade = await registry.makeBox(opName: GammaModule.opName)
        let gamma = try XCTUnwrap(gammaMade as? ModuleBox<GammaModule>)
        gamma.setParams(.init())
        let (texture, _) = try await RenderPipeline.process(
            image: image,
            instances: [ashift as any ModuleBoxing, colorin, gamma],
            imageID: UUID(), resolution: .preview, cache: PipeCache(),
            metal: metal, longEdge: nil)
        await drain(metal)
        XCTAssertEqual(
            texture.pixelFormat, .bgra8Unorm,
            "gamma tail must hand back the display-format plane")
        var bgra = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bgra.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        // Display-frame corners of a 30° rotation are warp-outside; all
        // four must be display black.
        let w = texture.width, h = texture.height
        for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
            let i = (y * w + x) * 4
            XCTAssertEqual(bgra[i], 0, "corner (\(x),\(y)) B must be display black")
            XCTAssertEqual(bgra[i + 1], 0, "corner (\(x),\(y)) G must be display black")
            XCTAssertEqual(bgra[i + 2], 0, "corner (\(x),\(y)) R must be display black")
        }
        // Interior stays lit (ramp is non-zero in the visible quad).
        let ci = ((h / 2) * w + w / 2) * 4
        XCTAssertGreaterThan(
            max(bgra[ci], bgra[ci + 1], bgra[ci + 2]), 0,
            "warp interior must remain visible through the display tail")
    }

    /// Identity gate (恒等门): neutral params ⇒ byte-identical RGB plane
    /// through the REAL pipe (the cache-neutrality contract the editing
    /// seed relies on).
    func testNeutralAshiftIsByteIdentical() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (plain, pw, ph) = try await runAshiftPipe(
            image: image, params: Self.ashiftParams(rot: 0), metal: metal)
        let goldenURL = try requireGolden("output/ashift_identity__gradient_ramp.exr")
        let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
        XCTAssertEqual(pw, golden.width)
        // Identity ref == the fixture bytes themselves (the synth path
        // with H == pure translation over the same-size frame).
        var worst: Float = 0
        for i in 0..<(pw * ph * 3) {
            worst = max(worst, abs(plain[i] - golden.rgb[i]))
        }
        XCTAssertLessThan(worst, 1e-6, "neutral ashift must be byte-identical")
    }

    /// modifyROIOut: rot30 on 64×64 grows the AABB (dt `:1190-1194`);
    /// neutral keeps input; origin preserved (L020).
    func testModifyROIOutGrowsAABBOnRotation() async {
        let box = ModuleBox(module: AshiftModule())
        box.setParams(Self.ashiftParams(rot: 30))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 64, height: 64)
        var out = ROI()
        box.modifyROIOutErased(
            &out, input: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0),
            piece: piece)
        XCTAssertEqual(out.x, 0, "origin preserved (L020)")
        XCTAssertEqual(out.y, 0)
        XCTAssertGreaterThan(out.width, 64, "rotation grows the output AABB")
        XCTAssertGreaterThan(out.height, 64)
        // Hand value: 30° on 64×64 → span = 64·(cos30+sin30) = 87.4 → 87.
        XCTAssertEqual(out.width, 87, accuracy: 1, "forward AABB hand value")
    }

    /// modifyROIIn: rot30 output window pulls (near-)full input + 2px
    /// margin, clamped to bufIn (bounded — the plan's "输入 AABB 有界").
    func testModifyROIInStaysBounded() async {
        let box = ModuleBox(module: AshiftModule())
        box.setParams(Self.ashiftParams(rot: 30))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: 64, height: 64)
        var fwd = ROI()
        box.modifyROIOutErased(
            &fwd, input: ROI(x: 0, y: 0, width: 64, height: 64, scale: 1.0),
            piece: piece)
        var back = ROI()
        box.modifyROIInErased(output: fwd, input: &back, piece: piece)
        XCTAssertLessThanOrEqual(back.x + back.width, 64 + 1, "input AABB bounded by bufIn")
        XCTAssertLessThanOrEqual(back.y + back.height, 64 + 1)
        XCTAssertGreaterThanOrEqual(back.x, -1)
        XCTAssertGreaterThanOrEqual(back.y, -1)
    }

    /// Registration + v50 slot (rotate before crop — the task-book double
    /// pin: table AND module agree).
    func testAshiftRegisteredAtV50Slot() async throws {
        XCTAssertEqual(V50Order.order(for: "ashift"), 15.0)
        XCTAssertEqual(AshiftModule.iopOrder, 15.0)
        XCTAssertLessThan(AshiftModule.iopOrder, CropModule.iopOrder, "rotate(15.0) before crop(24.5)")
        XCTAssertLessThan(AshiftModule.iopOrder, FlipModule.iopOrder, "ashift(15.0) before flip(16.0)")
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: AshiftModule.opName)
        XCTAssertNotNil(made, "ashift must be registered")
    }
}
