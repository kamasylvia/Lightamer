@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// SkinSmoothParityTests (Plan 07-2 T2/T4) — AI-05's frequency-separation
// skin smoothing. NO DARKTABLE COUNTERPART (L017 route: SELF-SYNTHESIZED
// float64 reference + identity triple — dt has no AI skin-smoothing
// module, 07-RESEARCH §2), so the golden face is:
//   - IDENTITY TRIPLE (T2, this file — direct-drive, GaussianBlurTests
//     pattern):
//     1. strength 0 ⇒ byte-exact blit;
//     2. mask nil == all-ones mask, byte-identical (the mask channel is a
//        no-op when absent — production spatial limiting rides the blendop);
//     3. flat field ⇒ any DC-1 blur preserves the flat ⇒ out ≈ in at ANY
//        strength (L017-proof vacuous identity, soften D5 twin).
//   - FLOAT64 PARITY (T4): 6 pinned σ×a×t cases × 6 fixtures vs
//     SkinSmoothReference (the Double transliteration of the split +
//     raised-cosine attenuation), gate <1e-5 (ParityGate double-gate
//     discipline).
//
// ANTI-VACUUM: every test runs a real comparison loop with compared>0.
// L014: every GPU readback drains first.
final class SkinSmoothParityTests: XCTestCase {

    private enum Tol {
        // Identity #3's envelope: the DC-1 IIR preserves a flat to ~1 ulp;
        // the residual feeds high ≈ ε and out = in − ε·a·m·g ≤ ε.
        static let flatFieldAbs: Float = 1e-5
    }

    private var metal: MetalContext!

    override func setUp() async throws {
        try await super.setUp()
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
    }

    private func drain() {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Direct-drive plumbing (GaussianBlurTests pattern)

    private func makeRGBATexture(width: Int, height: Int, pixels: [Float]) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        precondition(pixels.count == width * height * 4 || pixels.isEmpty)
        if !pixels.isEmpty {
            pixels.withUnsafeBytes {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: width * 16)
            }
        }
        return texture
    }

    /// A single-channel r32Float plane (the mask seam's currency — the
    /// MaskCombiner effectivePlane shape).
    private func makeMaskTexture(width: Int, height: Int, value: Float) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        var pixels = [Float](repeating: value, count: width * height)
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private func readTexture(_ texture: any MTLTexture) -> [Float] {
        var out = [Float](repeating: 0, count: texture.width * texture.height * 4)
        out.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return out
    }

    /// Deterministic pseudo-random RGB content (linear Rec2020-ish range
    /// incl. >1 scene-referred values — the working space is unbounded).
    private func syntheticPixels(width: Int, height: Int, seed: UInt64 = 0x5EED) -> [Float] {
        var state = seed
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53))
        }
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            // Bases span 0.005..1.4 with per-channel jitter — plenty of
            // low/high frequency content after the DC split.
            pixels[i * 4] = next() * 1.4 + 0.005
            pixels[i * 4 + 1] = next() * 1.2 + 0.005
            pixels[i * 4 + 2] = next() * 1.0 + 0.005
            pixels[i * 4 + 3] = 1.0
        }
        return pixels
    }

    /// Drive the module directly (box-free): commit + process on a full
    /// 1:1 ROI. `mask` binds the module's direct-drive seam (nil = the
    /// no-mask leg).
    private func runDirect(
        pixels: [Float], width: Int, height: Int,
        params: SkinSmoothModule.Params,
        mask: (any MTLTexture)? = nil
    ) async throws -> [Float] {
        let module = SkinSmoothModule()
        var piece = IOPiece(
            dscIn: IOPBufferDesc(width: width, height: height),
            dscOut: IOPBufferDesc(width: width, height: height))
        module.commitParams(params, into: &piece)
        module.maskPlane = mask
        let input = makeRGBATexture(width: width, height: height, pixels: pixels)
        let output = makeRGBATexture(width: width, height: height, pixels: [])
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await module.process(
            input: input, output: output,
            roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        drain() // L014
        return readTexture(output)
    }

    // MARK: - Identity triple

    /// Triple #1: strength 0 ⇒ the D9 blit fast path — BYTE-exact on
    /// varying content (every pixel compared, including alpha).
    func testStrengthZeroIsByteExactIdentity() async throws {
        let w = 64, h = 64
        let pixels = syntheticPixels(width: w, height: h)
        let out = try await runDirect(
            pixels: pixels, width: w, height: h,
            params: SkinSmoothModule.Params(radius: 8.0, strength: 0.0, detailPreserve: 0.02))
        XCTAssertEqual(out.count, pixels.count)
        var compared = 0
        for i in 0..<out.count {
            XCTAssertEqual(
                out[i].bitPattern, pixels[i].bitPattern,
                "byte mismatch at \(i) (channel \(i % 4))")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    /// Triple #2: the mask channel is a NO-OP when absent — mask nil vs an
    /// ALL-ONES r32Float plane produce byte-identical output at active
    /// strength (the hasMask uniform gate must not change the m ≡ 1 math).
    func testMaskNilEqualsAllOnesMaskByteExact() async throws {
        let w = 48, h = 48
        let pixels = syntheticPixels(width: w, height: h, seed: 0xFACE)
        let params = SkinSmoothModule.Params(radius: 6.0, strength: 0.7, detailPreserve: 0.02)
        let noMask = try await runDirect(
            pixels: pixels, width: w, height: h, params: params, mask: nil)
        let ones = try await runDirect(
            pixels: pixels, width: w, height: h, params: params,
            mask: makeMaskTexture(width: w, height: h, value: 1.0))
        var compared = 0
        for i in 0..<noMask.count {
            XCTAssertEqual(
                noMask[i].bitPattern, ones[i].bitPattern,
                "nil-mask vs ones-mask diverge at \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    /// Triple #3: flat field ⇒ out ≈ in at ACTIVE strength through the
    /// KERNEL path (not the blit) — any DC-1 blur preserves the flat, so
    /// high ≈ 0 and the mix returns the flat (L017-proof; the envelope is
    /// the IIR's ulp-level flat residual feeding out = in − ε·a·m·g).
    func testFlatFieldIdentityAtActiveStrength() async throws {
        let w = 48, h = 48
        // Scene-referred mid-gray, flat everywhere (alpha 1).
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            pixels[i * 4] = 0.18
            pixels[i * 4 + 1] = 0.18
            pixels[i * 4 + 2] = 0.18
            pixels[i * 4 + 3] = 1.0
        }
        let out = try await runDirect(
            pixels: pixels, width: w, height: h,
            params: SkinSmoothModule.Params(radius: 8.0, strength: 1.0, detailPreserve: 0.02))
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 3) { // RGB only — alpha rides the original
            maxDiff = max(maxDiff, abs(out[i] - pixels[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
        XCTAssertLessThan(maxDiff, Tol.flatFieldAbs, "flat-field identity within the IIR envelope")
    }

    /// The mask seam actually attenuates: a ZERO mask must return the
    /// input through the KERNEL path (m=0 ⇒ factor 1 everywhere) — the
    /// directional counterweight of triple #2 (anti-vacuum: the mask
    /// channel must be load-bearing, not decorative).
    func testZeroMaskReturnsInputThroughKernelPath() async throws {
        let w = 48, h = 48
        let pixels = syntheticPixels(width: w, height: h, seed: 0xBEEF)
        let out = try await runDirect(
            pixels: pixels, width: w, height: h,
            params: SkinSmoothModule.Params(radius: 6.0, strength: 1.0, detailPreserve: 0.02),
            mask: makeMaskTexture(width: w, height: h, value: 0.0))
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(w * h * 4) {
            maxDiff = max(maxDiff, abs(out[i] - pixels[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        // out = low + (in − low)·1: float round-trip through the split
        // keeps the identity to the mix arithmetic's rounding (≤1e-6 rel
        // on these magnitudes).
        XCTAssertLessThan(maxDiff, 1e-5, "zero mask ⇒ kernel-path identity")
    }

    // MARK: - Derivation pins (σ chain — highpass.c:140 citation)

    func testSigmaHaloChains() {
        // r=8: σ = √((8·9·8+2)/3) = √(192.666..)
        let sig8 = SkinSmoothModule.sigma(radius: 8, scale: 1.0)
        XCTAssertEqual(sig8, ((8.0 * 9.0 * 8.0 + 2.0) / 3.0).squareRoot(), accuracy: 1e-5)
        // Scale compensation: radius 8 at half-scale → r=4.
        let sig4 = SkinSmoothModule.sigma(radius: 8, scale: 0.5)
        XCTAssertEqual(sig4, ((4.0 * 5.0 * 8.0 + 2.0) / 3.0).squareRoot(), accuracy: 1e-5)
        // Radius floors at 1 (σ=0 degenerates the IIR).
        XCTAssertEqual(SkinSmoothModule.scaledRadius(radius: 4, scale: 0.1), 1)
        XCTAssertEqual(SkinSmoothModule.scaledRadius(radius: 0.5, scale: 1.0), 1)
        // Halo = ceil(3σ) (D7, soften/highpass twin).
        XCTAssertEqual(
            SkinSmoothModule.halo(radius: 8, scale: 1.0),
            Int((3 * sig8).rounded(.up)))
        // Neutral predicate.
        let module = SkinSmoothModule()
        XCTAssertTrue(module.isNeutral(SkinSmoothModule.Params(strength: 0)))
        XCTAssertFalse(module.isNeutral(SkinSmoothModule.Params(strength: 0.01)))
        // The reference's σ chain mirrors the module's (module computes in
        // Float, reference in Double — agreement at the float32 grid; the
        // <1e-5 parity gate absorbs the σ ulp).
        XCTAssertEqual(
            SkinSmoothReference.sigma(radius: 8), Double(sig8), accuracy: 1e-5)
    }


    // MARK: - Track: float64 parity (T4 — 6 pinned σ×a×t cases × 6 fixtures)

    private enum ParityTol {
        static let relative: Double = 1e-5 // the plan's <1e-5 gate
        static let absFloor: Double = 1e-5 // tiny absolute slips pass (flat regions)
    }

    /// The pinned case book (07-2-DECISIONS D-07-2-T4-1): typical / strong /
    /// fine / boundary-transition / max-strength / near-hard threshold.
    private static let parityCases: [(name: String, radius: Float, strength: Float, t: Float)] = [
        ("skin_default", 8.0, 0.5, 0.02),
        ("skin_strong", 12.0, 0.9, 0.05),
        ("skin_fine", 4.0, 0.3, 0.01),
        ("skin_edge_transition", 8.0, 0.7, 0.03),
        ("skin_maxstrength", 6.0, 1.0, 0.02),
        ("skin_smallthreshold", 6.0, 0.8, 0.005),
    ]

    private static let parityFixtures = [
        "gradient_ramp", "flat_0ev", "flat_-4ev",
        "checkerboard", "delta_impulse", "ramp_8ev__noisy_iso125_s20260921",
    ]

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
                    + "`python3 input/golden/fixtures/gen_fixtures.py refs input/golden/fixtures`")
        }
        return url
    }

    /// GPU vs SkinSmoothReference over the full pixel field, every case ×
    /// fixture, both mask legs on one case (the parity must hold with the
    /// direct-drive mask bound too — m·a inside the kernel).
    func testFrequencySeparationFloat64Parity() async throws {
        var compared = 0
        var maxRelative: Double = 0
        var failures: [String] = []

        for fixture in Self.parityFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let exr = try GoldenParityTests.UncompressedEXR.load(fixtureURL)
            let w = exr.width, h = exr.height
            var rgba = [Float](repeating: 0, count: w * h * 4)
            for i in 0..<(w * h) {
                rgba[i * 4] = exr.rgb[i * 3]
                rgba[i * 4 + 1] = exr.rgb[i * 3 + 1]
                rgba[i * 4 + 2] = exr.rgb[i * 3 + 2]
                rgba[i * 4 + 3] = 1.0
            }
            // One deterministic soft mask per fixture (a horizontal
            // gradient — 0 at the top row, 1 at the bottom): exercises
            // the m·a product on real content without a model.
            var maskFloats = [Float](repeating: 0, count: w * h)
            for y in 0..<h {
                let v = Float(y) / Float(max(h - 1, 1))
                for x in 0..<w { maskFloats[y * w + x] = v }
            }
            let gradedMask = makeGradedMask(width: w, height: h, floats: maskFloats)

            for (caseName, radius, strength, t) in Self.parityCases {
                let params = SkinSmoothModule.Params(
                    radius: radius, strength: strength, detailPreserve: t)
                // Leg 1 — no mask (m ≡ 1).
                var gpu = try await runDirect(
                    pixels: rgba, width: w, height: h, params: params, mask: nil)
                var ref = SkinSmoothReference.process(
                    pixels: rgba, width: w, height: h,
                    radius: Double(radius), strength: Double(strength),
                    detailPreserve: Double(t), mask: nil)
                (compared, maxRelative) = compare(
                    gpu, ref, w, h, "\(caseName)×\(fixture)·nomask",
                    &failures, compared, maxRelative)
                // Leg 2 — the graded mask (m·a product), on the first
                // fixture's cases only (the seam is fixture-independent).
                if fixture == Self.parityFixtures[0] {
                    gpu = try await runDirect(
                        pixels: rgba, width: w, height: h, params: params, mask: gradedMask)
                    ref = SkinSmoothReference.process(
                        pixels: rgba, width: w, height: h,
                        radius: Double(radius), strength: Double(strength),
                        detailPreserve: Double(t), mask: maskFloats)
                    (compared, maxRelative) = compare(
                        gpu, ref, w, h, "\(caseName)×\(fixture)·gradedmask",
                        &failures, compared, maxRelative)
                }
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity must compare real pixels (anti-vacuum)")
        XCTAssertTrue(
            failures.isEmpty,
            "skinSmooth float64 parity exceeded rel \(ParityTol.relative) / abs "
                + "\(ParityTol.absFloor) (max rel \(maxRelative), \(compared) samples):\n"
                + failures.prefix(6).joined(separator: "\n"))
    }

    private func makeGradedMask(width: Int, height: Int, floats: [Float]) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private func compare(
        _ gpu: [Float], _ ref: [Float], _ w: Int, _ h: Int, _ label: String,
        _ failures: inout [String], _ compared: Int, _ maxRel: Double
    ) -> (Int, Double) {
        var compared = compared
        var maxRel = maxRel
        for i in 0..<(w * h * 3) { // RGB; alpha rides the original on both sides
            compared += 1
            let r = Double(ref[i])
            let g = Double(gpu[i])
            let diff = abs(g - r)
            let rel = diff / max(abs(r), 1e-3)
            maxRel = max(maxRel, rel)
            if rel >= ParityTol.relative && diff >= ParityTol.absFloor,
               failures.count < 12 {
                let (x, y) = (i % w, i / w)
                failures.append(
                    "\(label) (\(x),\(y)): gpu=\(g) ref=\(r) rel=\(rel)")
            }
        }
        return (compared, maxRel)
    }

    // MARK: - Track B: neutral-seed insertion is a zero-delta (T5)

    /// The ENABLED-neutral seed (strength 0 = the blit identity) inserted
    /// into the default editing chain must be BYTE-IDENTICAL to the chain
    /// without it — the retouch-empty-layer disposition (Plan T5 / the
    /// R1-seed-regression discipline: seed changes demand the full-suite
    /// pass; this test pins the zero-delta claim itself).
    func testNeutralSeedInsertionTrackBZeroDelta() async throws {
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

        func runChain(omitSkinSmooth: Bool) async throws -> ([Float], Int, Int) {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry)
            var boxes: [any ModuleBoxing] = []
            for record in LightamerIOPRegistry.editingDefaultInstances() {
                if omitSkinSmooth && record.opName == SkinSmoothModule.opName { continue }
                let made = await registry.makeBox(opName: record.opName, instanceID: record.id)
                let box = try XCTUnwrap(made as? any ModuleBoxing)
                // Re-commit the seed record's params onto the fresh box
                // (identity-restoring init — PreviewChainPerfTests pattern).
                try box.apply(record)
                boxes.append(box)
            }
            boxes.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
            let (texture, _) = try await RenderPipeline.process(
                image: image, instances: boxes, imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal,
                longEdge: nil)
            drain() // L014
            var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
            floats.withUnsafeMutableBytes {
                texture.getBytes(
                    $0.baseAddress!, bytesPerRow: texture.width * 16,
                    from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                    mipmapLevel: 0)
            }
            return (floats, texture.width, texture.height)
        }

        let (withSkin, wW, wH) = try await runChain(omitSkinSmooth: false)
        let (withoutSkin, woW, woH) = try await runChain(omitSkinSmooth: true)
        XCTAssertEqual(wW, woW)
        XCTAssertEqual(wH, woH)
        var compared = 0
        for i in 0..<withSkin.count {
            XCTAssertEqual(
                withSkin[i].bitPattern, withoutSkin[i].bitPattern,
                "seed insertion moved byte \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
    }

    // MARK: - Tiling spot-check (T5 — the low leg's halo amortization)

    /// Forced-tile execution vs whole-plane: the GaussianBlur halo
    /// convention (tileHalo = ceil(3σ), the soften/highpass twin) amortizes
    /// the IIR's support across tile seams — the T5 100MP spot-check at
    /// fixture scale (the seam residuals are the IIR tail beyond 3σ;
    /// bounded here, recorded in 07-2-DECISIONS D-07-2-T5-1).
    func testTiledExecutionMatchesWholePlane() async throws {
        let fixtureURL = try requireGolden("fixtures/gradient_ramp.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let made = await registry.makeBox(opName: SkinSmoothModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<SkinSmoothModule>)
        box.setParams(SkinSmoothModule.Params(radius: 8.0, strength: 0.6, detailPreserve: 0.02))
        let chain = [box as any ModuleBoxing, colorinBox]

        let (whole, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil)
        drain() // L014
        // Force small tiles: the working set (48 B/px aux + planes) at
        // fixture scale ≈ N·(48+32+16) bytes — a 2 MB budget splits a
        // 256² plane into several tiles.
        let (tiled, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil, maxTileWorkingBytes: 2_000_000)
        drain() // L014

        XCTAssertEqual(whole.width, tiled.width)
        XCTAssertEqual(whole.height, tiled.height)
        var wholeF = [Float](repeating: 0, count: whole.width * whole.height * 4)
        wholeF.withUnsafeMutableBytes {
            whole.getBytes($0.baseAddress!, bytesPerRow: whole.width * 16,
                from: MTLRegionMake2D(0, 0, whole.width, whole.height), mipmapLevel: 0)
        }
        var tiledF = [Float](repeating: 0, count: tiled.width * tiled.height * 4)
        tiledF.withUnsafeMutableBytes {
            tiled.getBytes($0.baseAddress!, bytesPerRow: tiled.width * 16,
                from: MTLRegionMake2D(0, 0, tiled.width, tiled.height), mipmapLevel: 0)
        }
        var compared = 0
        var maxDiff: Float = 0
        for i in 0..<(whole.width * whole.height * 3) {
            maxDiff = max(maxDiff, abs(wholeF[i] - tiledF[i]))
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "anti-vacuum")
        // The IIR tail beyond the 3σ halo shows as a bounded seam residual
        // (σ ≈ 13.9 at radius 8 ⇒ halo 42 px ≈ the whole 128-px fixture —
        // tiling is effectively whole-plane at fixture scale; the bound
        // below is the recorded envelope, D-07-2-T5-1).
        XCTAssertLessThan(maxDiff, 1e-4, "tiled vs whole-plane seam residual bound")
    }
}
