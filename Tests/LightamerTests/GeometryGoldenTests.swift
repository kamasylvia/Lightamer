@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

/// GeometryGoldenTests (Plan 04-02-T3) — track A + track B for the
/// crop/flip index modules.
///
/// REFERENCE PROVENANCE (L017 route — dt-cli float export is spatially
/// corrupt on this host, probed 2026-09-20):
/// - crop center-50% on the ramp: dt EXR probe shows the L017 signature
///   (first 3 cols exact, then phase-shifted/smear blocks; G≠R up to
///   0.023) — corrupt, NOT a reference.
/// - flipH on the ramp: same corruption (mirrored blocks + G/B skew).
/// - flats (uniform): both modules export exactly (flip flat bit-exact;
///   crop flat trivially exact — constant window of a constant).
/// So track-A references are CPU-SYNTHESIZED by gen_fixtures.py (`refs`
/// mode): the crop window / flip remap over the canonical fixture bytes
/// in float64 (exact integers — the gate is <1e-6). dt-side evidence:
/// XMP adoption (DB op_params hex byte-identical + "params v. N ok" +
/// commit lines) + flat probes (flip flat exact; crop flat vacuous).
///
/// Golden files regenerate via `bash input/golden/regenerate.sh`
/// (gen_fixtures refs mode); outputs are git-ignored, XMPs committed.
final class GeometryGoldenTests: XCTestCase {

    /// Index-class gate (RESEARCH Validation Architecture §2): pure
    /// index remaps carry zero sampling freedom — <1e-6.
    private enum ParityTolerance {
        static let indexRelative: Float = 1e-6
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
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs input/golden/fixtures` (Plan 04-02-T3)"
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

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Track A: crop

    /// The crop 钉参组 (gen_fixtures CROP_CASES — mirrors the dt blobs;
    /// ratio bits ride inert until the Phase-11 export aligner).
    private static let cropCases: [(name: String, params: CropModule.Params)] = [
        ("crop_full", CropModule.Params(left: 0, top: 0, right: 1, bottom: 1)),
        ("crop_center50", CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75)),
        ("crop_3x2", CropModule.Params(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75, ratioN: 2, ratioD: 3)),
    ]

    private static let trackAFixtures = ["ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase"]

    /// TRACK A for crop: every (fixture × case) synthesized reference vs
    /// the Lightamer `[crop]` pipe, per-pixel relative error < 1e-6.
    /// RGB only (alpha rides the CI leg premultiplied — CropParityTests
    /// documents the drift; the index identity is RGB).
    func testCropGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.cropCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runCropPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size \(pipeW)×\(pipeH) vs golden \(golden.width)×\(golden.height)")
                    continue
                }
                let n = golden.width * golden.height
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let la = pipe[i * 3 + c]
                        let rel = abs(la - ref) / max(abs(ref), 1e-9)
                        maxRelative = max(maxRelative, rel)
                        if rel >= ParityTolerance.indexRelative, failures.count < 12 {
                            let (x, y) = (i % golden.width, i / golden.width)
                            failures.append(
                                "\(caseName)×\(fixture) (\(x),\(y)) ch\(c): "
                                    + "lightamer=\(la) ref=\(ref) rel=\(rel)"
                            )
                        }
                    }
                }
            }
        }
        XCTAssertLessThan(
            Double(maxRelative), Double(ParityTolerance.indexRelative),
            "crop golden parity exceeded \(ParityTolerance.indexRelative) (max \(maxRelative))\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → `[colorin, crop]` pipe → RGB
    /// plane. colorin is the working-space boundary (identity on the
    /// Rec2020-tagged fixture — the same wrapper every track-A leg
    /// uses); the crop window must then equal the reference bytes.
    private func runCropPipe(
        image: DecodedImage, params: CropModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let cropMade = await registry.makeBox(opName: CropModule.opName)
        let crop = try XCTUnwrap(cropMade as? ModuleBox<CropModule>)
        crop.setParams(params)
        let chain = [colorinBox as any ModuleBoxing, crop]
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014
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

    // MARK: - Track A: flip

    /// The flip 钉参组 (gen_fixtures FLIP_CASES — 4 representative states;
    /// all 8 ride the same kernel path, FlipParityTests covers 8/8).
    private static let flipCases: [(name: String, orientation: FlipOrientation)] = [
        ("flip_none", .none),
        ("flip_h", .flipH),
        ("flip_v", .flipV),
        ("flip_ccw90", .rotCCW90),
    ]

    /// TRACK A for flip: every (fixture × case) synthesized reference vs
    /// the Lightamer `[flip]` pipe, per-pixel relative error < 1e-6.
    func testFlipGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, orientation) in Self.flipCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runFlipPipe(
                    image: image, orientation: orientation, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size \(pipeW)×\(pipeH) vs golden \(golden.width)×\(golden.height)")
                    continue
                }
                let n = golden.width * golden.height
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let la = pipe[i * 3 + c]
                        let rel = abs(la - ref) / max(abs(ref), 1e-9)
                        maxRelative = max(maxRelative, rel)
                        if rel >= ParityTolerance.indexRelative, failures.count < 12 {
                            let (x, y) = (i % golden.width, i / golden.width)
                            failures.append(
                                "\(caseName)×\(fixture) (\(x),\(y)) ch\(c): "
                                    + "lightamer=\(la) ref=\(ref) rel=\(rel)"
                            )
                        }
                    }
                }
            }
        }
        XCTAssertLessThan(
            Double(maxRelative), Double(ParityTolerance.indexRelative),
            "flip golden parity exceeded \(ParityTolerance.indexRelative) (max \(maxRelative))\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → `[colorin, flip]` pipe → RGB
    /// plane (same colorin wrapper as the crop leg).
    private func runFlipPipe(
        image: DecodedImage, orientation: FlipOrientation, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let flipMade = await registry.makeBox(opName: FlipModule.opName)
        let box = try XCTUnwrap(flipMade as? ModuleBox<FlipModule>)
        box.setParams(FlipModule.Params(orientation: orientation))
        let chain = [colorinBox as any ModuleBoxing, box]
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014
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

    // MARK: - Track B: ColorSync neutrality + cross-consistency

    /// Criterion 1: gray-patch neutrality through the FULL chain with
    /// crop (FULL-frame = identity window) + flip (NONE identity)
    /// inserted — channel spread < 2/255 per patch + level sanity.
    /// Full-frame crop keeps every patch inside the window (a 50% window
    /// would push the edge patches into the letterbox); the window path
    /// itself is covered by track A. Flip NONE exercises the remap as
    /// identity through the real chain.
    func testTrackBNeutralityWithCropFlipInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        let chain = try await makeChainWithCropFlip(
            registry: ModuleRegistry.makeDefault(), outputProfile: .displayP3
        )
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        let rgb = readRGB8(texture)
        let (w, h) = (texture.width, texture.height)

        var failures: [String] = []
        func srgbEncode(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
        for patch in Fixtures.neutralPatches {
            let s = sample3x3(rgb, width: w, height: h, x: patch.x, y: patch.y)
            let rg = abs(s.r - s.g), gb = abs(s.g - s.b)
            if rg >= 2 || gb >= 2 {
                failures.append("\(patch.name): |R−G|=\(rg) |G−B|=\(gb)")
            }
            let want = srgbEncode(patch.expectedLinearRec2020.0) * 255.0
            if abs((s.r + s.g + s.b) / 3 - want) > 2 {
                failures.append("\(patch.name): level \((s.r + s.g + s.b) / 3) vs ≈\(want)")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "track B criterion 1 (neutrality with crop+flip+lens inserted) FAILED:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// Criterion 2 (linear flavor): chain minus gamma (crop+flip+lens
    /// inserted) vs a CIContext ColorSync direct render into linear-P3.
    func testTrackBCrossConsistencyLinearWithCropFlipInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        var chain = try await makeChainWithCropFlip(
            registry: ModuleRegistry.makeDefault(), outputProfile: .displayP3
        )
        chain = chain.filter { $0.opName != GammaModule.opName }
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat, "no gamma tail → float32")
        var pipeFloats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        pipeFloats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }

        guard let p3 = CGColorSpace(name: CGColorSpace.displayP3) else {
            throw XCTSkip("system Display P3 colorspace unavailable")
        }
        let scaled = image.ciImage
        let w = Int(scaled.extent.width), h = Int(scaled.extent.height)
        let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? p3
        let context = CIContext(options: [
            .workingColorSpace: WorkingSpace.colorSpace,
            .outputColorSpace: linearP3,
        ])
        var baseline = [Float](repeating: 0, count: w * h * 4)
        baseline.withUnsafeMutableBytes {
            context.render(
                scaled, toBitmap: $0.baseAddress!, rowBytes: w * 16,
                bounds: scaled.extent, format: CIFormat.RGBAf,
                colorSpace: linearP3
            )
        }

        // Full-frame crop + NONE flip = identity geometry: the pipe plane
        // compares against the full-frame baseline directly (same shape
        // as the exposure track-B leg).
        let (pw, ph) = (texture.width, texture.height)
        XCTAssertEqual(pw, w, "full-frame crop keeps the frame width")
        XCTAssertEqual(ph, h, "full-frame crop keeps the frame height")
        var maxDiff: Float = 0
        var worst = (0, 0)
        for i in 0..<min(pipeFloats.count, baseline.count) {
            let d = abs(pipeFloats[i] - baseline[i])
            if d > maxDiff {
                maxDiff = d
                worst = (i / 4 % pw, i / 4 / pw)
            }
        }
        XCTAssertLessThan(
            Double(maxDiff), 0.004,
            "track B criterion 2 (linear, crop+flip+lens inserted): pipe vs ColorSync diverges "
                + "\(maxDiff) (worst at \(worst.0),\(worst.1))"
        )
    }

    /// Plan 05-06-T5 track B: nlmeans inserted ENABLED (strength 0 — on
    /// neutral flats dist=0 → w=1 → out = neighborhood mean = in; the
    /// LabMath a=b=0 neutral anchoring survives the in-module Lab round
    /// trip). Gray patches stay neutral AND at level (the Lab 往返中性度
    /// criterion the plan names), with the module LIVE in the chain —
    /// stronger than the disabled-piece pass-through the seed gives.
    func testTrackBNeutralityWithNLMeansInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let made = await registry.makeBox(opName: NLMeansModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<NLMeansModule>)
        box.setParams(NLMeansModule.Params(strength: 0))
        box.enabled = true
        chain.append(box)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        let rgb = readRGB8(texture)
        let (w, h) = (texture.width, texture.height)

        var failures: [String] = []
        func srgbEncode(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
        for patch in Fixtures.neutralPatches {
            let s = sample3x3(rgb, width: w, height: h, x: patch.x, y: patch.y)
            let rg = abs(s.r - s.g), gb = abs(s.g - s.b)
            if rg >= 2 || gb >= 2 {
                failures.append("\(patch.name): |R−G|=\(rg) |G−B|=\(gb)")
            }
            let want = srgbEncode(patch.expectedLinearRec2020.0) * 255.0
            if abs((s.r + s.g + s.b) / 3 - want) > 2 {
                failures.append("\(patch.name): level \((s.r + s.g + s.b) / 3) vs ≈\(want)")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "track B (nlmeans inserted, strength 0) FAILED:\n"
                + failures.joined(separator: "\n")
        )
    }

    // MARK: - Helpers (GoldenParityTests track-B shape)

    /// The default chain with crop (FULL-frame = identity window) + flip
    /// (NONE identity) + lens (neutral OFF) + the five detail neutrals
    /// (sharpen/bilat/equalizer enabled-neutral blit, highpass/soften
    /// DISABLED — plan 04-05-T5 track B) inserted at their v50 slots.
    /// Full-frame crop = whole-plane blit; neutral lens/detail = blit
    /// identity (cache-neutral shapes, exercise the blit legs through the
    /// real chain without moving patches into the letterbox).
    private func makeChainWithCropFlip(
        registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile
    ) async throws -> [any ModuleBoxing] {
        await LightamerIOPRegistry.populate(registry)
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: outputProfile
        )
        let flip = await registry.makeBox(opName: FlipModule.opName)
        let flipBox = try XCTUnwrap(flip as? ModuleBox<FlipModule>)
        flipBox.setParams(FlipModule.Params(orientation: .none))
        chain.append(flipBox)
        let lens = await registry.makeBox(opName: LensModule.opName)
        let lensBox = try XCTUnwrap(lens as? ModuleBox<LensModule>)
        lensBox.setParams(LensModule.Params())
        chain.append(lensBox)
        let crop = await registry.makeBox(opName: CropModule.opName)
        let cropBox = try XCTUnwrap(crop as? ModuleBox<CropModule>)
        cropBox.setParams(CropModule.Params())
        chain.append(cropBox)
        // Plan 04-05-T5 track B: the five detail neutrals (blit-identity
        // legs through the real chain — enabled-neutral ×3, disabled ×2).
        let sharpenMade = await registry.makeBox(opName: SharpenModule.opName)
        let sharpenBox = try XCTUnwrap(sharpenMade as? ModuleBox<SharpenModule>)
        sharpenBox.setParams(SharpenModule.Params())
        chain.append(sharpenBox)
        let bilatMade = await registry.makeBox(opName: LocalContrastModule.opName)
        let bilatBox = try XCTUnwrap(bilatMade as? ModuleBox<LocalContrastModule>)
        bilatBox.setParams(LocalContrastModule.Params())
        chain.append(bilatBox)
        let eqMade = await registry.makeBox(opName: EqualizerModule.opName)
        let eqBox = try XCTUnwrap(eqMade as? ModuleBox<EqualizerModule>)
        eqBox.setParams(EqualizerModule.Params())
        chain.append(eqBox)
        let highMade = await registry.makeBox(opName: HighpassModule.opName)
        let highBox = try XCTUnwrap(highMade as? ModuleBox<HighpassModule>)
        highBox.setParams(HighpassModule.Params())
        highBox.enabled = false
        chain.append(highBox)
        let softMade = await registry.makeBox(opName: SoftenModule.opName)
        let softBox = try XCTUnwrap(softMade as? ModuleBox<SoftenModule>)
        softBox.setParams(SoftenModule.Params())
        softBox.enabled = false
        chain.append(softBox)
        // Plan 05-04-T5 track B: vibrance + velvia + colorzones neutrals
        // (enabled-neutral ×3 — amount/strength 0 + flat-0.5 curves ⇒
        // identity through the real chain).
        let vibMade = await registry.makeBox(opName: VibranceModule.opName)
        let vibBox = try XCTUnwrap(vibMade as? ModuleBox<VibranceModule>)
        vibBox.setParams(VibranceModule.Params())
        chain.append(vibBox)
        let velMade = await registry.makeBox(opName: VelviaModule.opName)
        let velBox = try XCTUnwrap(velMade as? ModuleBox<VelviaModule>)
        velBox.setParams(VelviaModule.Params())
        chain.append(velBox)
        let czMade = await registry.makeBox(opName: ColorZonesModule.opName)
        let czBox = try XCTUnwrap(czMade as? ModuleBox<ColorZonesModule>)
        czBox.setParams(ColorZonesModule.Params())
        chain.append(czBox)
        // Plan 05-05-T4 track B: monochrome DISABLED seed (default size=2
        // filter is not neutral — disabled ⇒ pipe skips ⇒ zero chain delta;
        // 05-02 colorbalancergb T5 zero-increment precedent).
        let monoMade = await registry.makeBox(opName: MonochromeModule.opName)
        let monoBox = try XCTUnwrap(monoMade as? ModuleBox<MonochromeModule>)
        monoBox.setParams(MonochromeModule.Params())
        monoBox.enabled = false
        chain.append(monoBox)
        // Plan 05-07-T6 track B: denoiseprofile DISABLED (no zero-param
        // identity — force 0.5 keeps thrs > 0 — disabled ⇒ pipe skips ⇒
        // zero chain delta; the LIVE insertion coverage rides the parity
        // suite; 05-06's nlmeans keeps its own enabled-neutral test).
        let dpMade = await registry.makeBox(opName: DenoiseProfileModule.opName)
        let dpBox = try XCTUnwrap(dpMade as? ModuleBox<DenoiseProfileModule>)
        dpBox.setParams(DenoiseProfileModule.Params())
        dpBox.enabled = false
        chain.append(dpBox)
        // Plan 05-08-T5 track B: nlmeans + bilateral DISABLED (no zero-param
        // identity for either — D-05-06-T2-1 / D-05-08-T1-3; disabled ⇒ pipe
        // skips ⇒ zero chain delta). With these two the track-B chain now
        // carries EVERY Phase 3+4+5 module — the Phase 6 baseline.
        let nlMade = await registry.makeBox(opName: NLMeansModule.opName)
        let nlBox = try XCTUnwrap(nlMade as? ModuleBox<NLMeansModule>)
        nlBox.setParams(NLMeansModule.Params())
        nlBox.enabled = false
        chain.append(nlBox)
        let blMade = await registry.makeBox(opName: BilateralModule.opName)
        let blBox = try XCTUnwrap(blMade as? ModuleBox<BilateralModule>)
        blBox.setParams(BilateralModule.Params())
        blBox.enabled = false
        chain.append(blBox)
        return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

    private func readRGB8(_ texture: any MTLTexture) -> [(UInt8, UInt8, UInt8)] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var out: [(UInt8, UInt8, UInt8)] = []
        for i in stride(from: 0, to: bytes.count, by: 4) {
            out.append((bytes[i + 2], bytes[i + 1], bytes[i])) // BGRA → RGB
        }
        return out
    }

    private func sample3x3(
        _ rgb: [(UInt8, UInt8, UInt8)], width: Int, height: Int, x: Double, y: Double
    ) -> (r: Double, g: Double, b: Double) {
        let cx = Int((x * Double(width - 1)).rounded())
        let cy = Int((y * Double(height - 1)).rounded())
        var rs = 0.0, gs = 0.0, bs = 0.0, n = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let px = min(max(cx + dx, 0), width - 1)
                let py = min(max(cy + dy, 0), height - 1)
                let p = rgb[py * width + px]
                rs += Double(p.0); gs += Double(p.1); bs += Double(p.2); n += 1
            }
        }
        return (rs / Double(n), gs / Double(n), bs / Double(n))
    }
}
