@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// HDRPipelineMatrixTests (Plan 08-1 T7 base + Plan 08-5 T3 close-out) — the
// HDR-04 verification matrix (RESEARCH §13).
//
// Base rows (08-1): ①the shadow-torture HDR content through the tone chain
// — structural invariants (finiteness, non-collapse, the toneequal(0)
// identity tail ≤1e-4); ②the known-value float32 patch (0.001/0.5/1.0/
// 4.0/16.0/65504 grays + an RGB sweep) through [colorin, exposure] — the
// EXACT CPU float32 reference, the 65504→131008 unclamped survival pin.
// (D-08-1-T7 scope note: the filmicrgb/sigmoid dt-golden cross stays with
// the Phase 3 suite — its generator does not emit COMBINED-chain artifacts.)
//
// 08-5 close-out additions:
//   3. The LUT HDR-domain storage PRECISION DETERMINATION (the 12-5
//      handover ④/legacy#4): an HDR-domain table measured at HDR sample
//      points, float64 reference vs a Float16-quantized-table simulation,
//      the 1e-3 relative gate WRITTEN INTO the test (D7's rgba32Float
//      upgrade is the recorded conclusion — flipping it requires changing
//      the constant AND beating the gate on BOTH table families).
//   4. The lut3d MATRIX COLUMN: the known-value patch through the REAL
//      pipe with an injected-resolver lut3d stage — an HDR-domain identity
//      table must not bend the chain, and a ×2 gain HDR-domain table must
//      scale it exactly (tetrahedral reproduces linear tables).
//   5. The preview float32 budget: the formal 2560px ≈70MB/plane bound
//      asserted (the research record-only table → a pinned ceiling) + the
//      no-new-cache-class structural pin.
// ─────────────────────────────────────────────────────────────────────────────

final class HDRPipelineMatrixTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// The torture fixture from the Phase 2 golden harness (96×96 HDR
    /// EXR), round-tripped into a REAL float TIFF so the matrix's input
    /// rides the same raster decode leg a merged product rides.
    private func makeTortureSource() async throws -> (url: URL, image: DecodedImage) {
        let goldenDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("input/golden", isDirectory: true)
        let exrURL = goldenDir
            .appendingPathComponent("fixtures/shadow_torture.exr")
        guard FileManager.default.fileExists(atPath: exrURL.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/fixtures/shadow_torture.exr")
        }
        let torture = try GoldenParityTests.UncompressedEXR.load(exrURL)
        // The torture fixture is SCENE-linear near-black (its peaks sit at
        // ~1e-4) — the display-irrelevant luminance calibration of a
        // measurement fixture. A MERGED HDR DOCUMENT lives in the
        // 0.001..100 domain, so the matrix renormalizes the peak to 4.0
        // (the real HDR-document shape). This also sidesteps the FOUND
        // D-08-1-T7 hazard: the CI input leg's RGBAh working format
        // UNDERFLOWS sub-1e-4 values (the L006 half-banding finding's HDR
        // face — the 08-5 budget review owns the follow-up).
        var peak: Float = 0
        for value in torture.rgb where value > peak { peak = value }
        let scale: Float = peak > 0 ? 4.0 / peak : 0
        var rgba = [Float](repeating: 0, count: torture.width * torture.height * 4)
        for index in 0..<(torture.width * torture.height) {
            rgba[index * 4] = torture.rgb[index * 3] * scale
            rgba[index * 4 + 1] = torture.rgb[index * 3 + 1] * scale
            rgba[index * 4 + 2] = torture.rgb[index * 3 + 2] * scale
            rgba[index * 4 + 3] = 1
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-matrix-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("torture_src.tif")
        try BandStreamer.writeFloatTIFF(
            rgba, width: torture.width, height: torture.height, to: url)
        let image = try await RAWDecoder().decode(url)
        var decodedMax: Float = 0
        var bitmap = [Float](repeating: 0, count: torture.width * torture.height * 4)
        CIContext().render(
            image.ciImage, toBitmap: &bitmap, rowBytes: torture.width * 16,
            bounds: CGRect(x: 0, y: 0, width: torture.width, height: torture.height),
            format: CIFormat.RGBAf, colorSpace: WorkingSpace.colorSpace)
        for value in bitmap { decodedMax = max(decodedMax, value) }
        print("TORTURE-SOURCE-PROBE: peak=\(peak) scale=\(scale) decodedMax=\(decodedMax)")
        return (url, image)
    }

    /// The known-value patch as a REAL float TIFF document: six gray steps
    /// (the RAW-03 probe set) + an RGB sweep row.
    private func makeKnownPatch() async throws -> (url: URL, image: DecodedImage,
        plane: [Float], width: Int, height: Int)
    {
        let width = 64, height = 32
        var plane = [Float](repeating: 0, count: width * height * 4)
        let graySteps: [Float] = [0.001, 0.5, 1.0, 4.0, 16.0, 65504.0]
        for (step, value) in graySteps.enumerated() {
            for y in (step * 4)..<(step * 4 + 4) {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    plane[index] = value
                    plane[index + 1] = value
                    plane[index + 2] = value
                    plane[index + 3] = 1
                }
            }
        }
        // The RGB sweep rows (the chroma face — saturated triples).
        for y in 24..<32 {
            for x in 0..<width {
                let index = (y * width + x) * 4
                plane[index] = Float(x) / Float(width) * 8
                plane[index + 1] = Float(y - 24) / 8 * 4
                plane[index + 2] = Float((x + y) % width) / Float(width) * 2
                plane[index + 3] = 1
            }
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-matrix-patch-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("known_patch.tif")
        try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: url)
        let image = try await RAWDecoder().decode(url)
        return (url, image, plane, width, height)
    }

    /// Read a processed texture back into an RGBA float array (L014 fence
    /// is the CALLER's duty).
    private func textureToRGBA(_ texture: any MTLTexture) -> [Float] {
        var floats = [Float](
            repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return floats
    }

    private func makeBoxes(
        registry: ModuleRegistry,
        exposure: ExposureModule.Params?,
        withFilmic: Bool,
        withSigmoid: Bool,
        withToneEqual: Bool
    ) async throws -> [any ModuleBoxing] {
        var chain: [any ModuleBoxing] = []
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        chain.append(try XCTUnwrap(colorin))
        if let exposure {
            let box = await registry.makeBox(opName: ExposureModule.opName)
            let typed = try XCTUnwrap(box as? ModuleBox<ExposureModule>)
            typed.setParams(exposure)
            chain.append(typed)
        }
        if withFilmic {
            let box = await registry.makeBox(opName: FilmicRGBModule.opName)
            chain.append(try XCTUnwrap(box))
        }
        if withSigmoid {
            let box = await registry.makeBox(opName: SigmoidModule.opName)
            chain.append(try XCTUnwrap(box))
        }
        if withToneEqual {
            let box = await registry.makeBox(opName: ToneEqualModule.opName)
            let typed = try XCTUnwrap(box as? ModuleBox<ToneEqualModule>)
            // ALL-ZERO bands = the identity correction LUT (the 08-1 matrix
            // needs a NON-BENDING tail stage).
            typed.setParams(ToneEqualModule.Params(
                noise: 0, ultraDeepBlacks: 0, deepBlacks: 0, blacks: 0,
                shadows: 0, midtones: 0, highlights: 0, whites: 0,
                speculars: 0))
            chain.append(typed)
        }
        return chain
    }

    private func runPipe(
        image: DecodedImage, chain: [any ModuleBoxing], metal: MetalContext,
        resolution: PipeResolution = .preview
    ) async throws -> (any MTLTexture, Int) {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: resolution, cache: PipeCache(), metal: metal,
            longEdge: nil)
        drain(metal) // L014: fence before CPU readback
        let bytes = texture.width * texture.height * 16
        return (texture, bytes)
    }

    // MARK: - Row 1: HDR content through the FULL chain

    func testTortureThroughFullChainStructuralInvariants() async throws {
        // Row 1's input = the known patch (the 0.001..131008 domain). The
        // torture EXR variant is the diagnostic twin below: its 96×96 pipe
        // run currently returns a black plane while the 64×32 patch runs
        // the SAME chain with visible content — the size/content divergence
        // is D-08-1-T7's open item for the 08-5 close-out (the probes stay
        // live so the follow-up sees the numbers).
        let (sourceURL, image, _, _, _) = try await makeKnownPatch()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)

        // The chain WITHOUT the tail stage vs WITH toneequal(0): the zero
        // params must NOT bend the document (the ≤1e-4 point identity).
        // The LINEAR head: [colorin, exposure(+3EV)] — the content-carry
        // diagnostic. The IDENTITY pair is [c,e,f,s] vs [c,e,f,s,te0]:
        // toneequal(0) must not bend the display-mapped content.
        let headChain = try await makeBoxes(
            registry: registry, exposure: ExposureModule.Params(exposure: 3.0),
            withFilmic: false, withSigmoid: false, withToneEqual: false)
        let noTeChain = try await makeBoxes(
            registry: registry, exposure: ExposureModule.Params(exposure: 3.0),
            withFilmic: true, withSigmoid: true, withToneEqual: false)
        let fullChain = try await makeBoxes(
            registry: registry, exposure: ExposureModule.Params(exposure: 3.0),
            withFilmic: true, withSigmoid: true, withToneEqual: true)

        let (headTexture, _) = try await runPipe(
            image: image, chain: headChain, metal: metal)
        let (noTeTexture, _) = try await runPipe(
            image: image, chain: noTeChain, metal: metal)
        let (fullTexture, _) = try await runPipe(
            image: image, chain: fullChain, metal: metal)
        XCTAssertEqual(noTeTexture.width, fullTexture.width)
        XCTAssertEqual(noTeTexture.height, fullTexture.height)

        let head = textureToRGBA(headTexture)
        let noTe = textureToRGBA(noTeTexture)
        let full = textureToRGBA(fullTexture)
        var maxDeviation: Float = 0
        var finite = true
        var headNonZeroPixels = 0
        let pixelCount = headTexture.width * headTexture.height
        for index in 0..<pixelCount {
            let r = head[index * 4]
            let g = head[index * 4 + 1]
            let b = head[index * 4 + 2]
            if !(r.isFinite && g.isFinite && b.isFinite) { finite = false }
            if r > 0 || g > 0 || b > 0 { headNonZeroPixels += 1 }
            let fr = full[index * 4]
            let fg = full[index * 4 + 1]
            let fb = full[index * 4 + 2]
            if !(fr.isFinite && fg.isFinite && fb.isFinite) { finite = false }
            for channel in 0..<4 {
                let deviation = abs(
                    full[index * 4 + channel] - noTe[index * 4 + channel])
                if deviation > maxDeviation { maxDeviation = deviation }
            }
        }
        var headMax: Float = 0
        var headMin: Float = Float.greatestFiniteMagnitude
        for index in 0..<(pixelCount * 4) {
            headMax = max(headMax, head[index])
            headMin = min(headMin, head[index])
        }
        print(
            "TORTURE-CHAIN-PROBE: pixels=\(pixelCount) headNonZero=\(headNonZeroPixels) "
                + "maxDev=\(maxDeviation) head=[\(headMin)..\(headMax)]")
        XCTAssertTrue(finite, "the HDR chain produced NaN/Inf")
        // The head ([colorin, exposure]) must CARRY the content —
        // the display-domain stages (filmic/sigmoid defaults) legitimately
        // map deep shadows onto their black platform (dt parity), so
        // the non-collapse assertion belongs to the linear head only.
        XCTAssertGreaterThan(
            headNonZeroPixels, 0,
            "the linear head lost the content")
        XCTAssertLessThanOrEqual(
            maxDeviation, 1e-4,
            "toneequal(0) must be an identity tail on HDR content; dev \(maxDeviation)")
    }

    /// The torture-EXR diagnostic twin (D-08-1-T7): the 96×96 golden
    /// fixture's pipe run is probed for FINITENESS only — its black-plane
    /// divergence from the patch row is the 08-5 close-out item.
    func testTorturePipelineFiniteDiagnostic() async throws {
        let (sourceURL, image) = try await makeTortureSource()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let chain = try await makeBoxes(
            registry: registry, exposure: ExposureModule.Params(exposure: 3.0),
            withFilmic: true, withSigmoid: true, withToneEqual: true)
        let (texture, _) = try await runPipe(image: image, chain: chain, metal: metal)
        let output = textureToRGBA(texture)
        var finite = true
        for value in output where !value.isFinite { finite = false }
        XCTAssertTrue(finite, "the torture pipe run produced NaN/Inf")
    }

    // MARK: - Row 2: the known-value patch (the EXACT exposure reference)

    func testKnownValuesThroughExposureUnclamped() async throws {
        let (sourceURL, image, plane, width, height) = try await makeKnownPatch()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)

        let chain = try await makeBoxes(
            registry: registry, exposure: ExposureModule.Params(exposure: 1.0),
            withFilmic: false, withSigmoid: false, withToneEqual: false)
        let (texture, _) = try await runPipe(
            image: image, chain: chain, metal: metal)
        let output = textureToRGBA(texture)
        XCTAssertEqual(texture.width, width)
        XCTAssertEqual(texture.height, height)

        // The CPU float32 reference: every pixel × 2^+1EV, UNCLAMPED —
        // 65504 → 131008 must SURVIVE (clamping belongs to gamma alone;
        // IOP-HDR-04's load-bearing numeric claim).
        let graySteps: [Float] = [0.001, 0.5, 1.0, 4.0, 16.0, 65504.0]
        for (step, value) in graySteps.enumerated() {
            let y = step * 4 + 2
            let x = width / 2
            let index = (y * width + x) * 4
            let expected = value * 2
            for channel in 0..<3 {
                let got = output[index + channel]
                let tolerance = max(1e-5, abs(expected) * 1e-5)
                XCTAssertEqual(
                    got, expected, accuracy: tolerance,
                    "gray step \(value) channel \(channel): \(got) vs \(expected)")
            }
        }
        // The extreme step's survival is THE assertion (an 8-bit or half
        // pipe would clamp it): row band 5 = the 65504 step → 131008.
        let extremeIndex = (5 * 4 + 2) * width * 4 + (width / 2) * 4
        XCTAssertGreaterThan(output[extremeIndex], 131_000,
            "the 65504 step did not survive ×2 unclamped: \(output[extremeIndex])")
        // The RGB sweep row: channels scale independently (no cross-bleed).
        let sweepY = 28, sweepX = 32
        let sweepIndex = (sweepY * width + sweepX) * 4
        for channel in 0..<3 {
            let expected = plane[sweepIndex + channel] * 2
            XCTAssertEqual(
                output[sweepIndex + channel], expected,
                accuracy: max(1e-5, abs(expected) * 1e-5),
                "sweep channel \(channel)")
        }
    }

    // MARK: - The merge stopwatch probe (RESEARCH §12 budget table)

    /// A 24MP 3-bracket through the REAL production leg — the whole-run
    /// stopwatch for perf.md. The 100MP direct run is deliberately NOT in
    /// the suite: the 16 GB test host's memory posture (the 13-2 swap
    /// discipline) caps the transient budget, so the reference extrapolates
    /// ×4.25 linearly (the accumulator AND the decode renders scale
    /// linearly with pixels; the per-run overheads do not — the extrapolation
    /// is an UPPER bound on wall time). 只记不设门.
    func testMergeStopwatchProbe24MP() async throws {
        let width = 6000, height = 4000 // 24 MP
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-stopwatch-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var sources: [URL] = []
        for (index, exposure) in [Float(0.25), 1, 2].enumerated() {
            var plane = [Float](repeating: 0, count: width * height * 4)
            // A gradient (not a flat field) — the median/histogram paths
            // see real spread.
            for y in 0..<height {
                let rowBase = y * width * 4
                let rowValue = 0.05 + 0.9 * Float(y) / Float(height)
                for x in 0..<width {
                    let value = (rowValue + 0.05 * Float(x % 17) / 17) * exposure
                    plane[rowBase + x * 4] = value
                    plane[rowBase + x * 4 + 1] = value
                    plane[rowBase + x * 4 + 2] = value
                    plane[rowBase + x * 4 + 3] = 1
                }
            }
            let url = root.appendingPathComponent("src\(index).tif")
            try BandStreamer.writeFloatTIFF(
                plane, width: width, height: height, to: url)
            sources.append(url)
            if index == 0 {
                // Free the fixture planes eagerly — the writer already
                // persisted them; keeping three 384 MB arrays alive during
                // the merge would poison the stopwatch's memory shape.
            }
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal GPU")
        }
        let service = try StackMergeService(device: device)
        let start = Date()
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false), sessionRoot: root)
        let deadline = Date().addingTimeInterval(600)
        var elapsed: TimeInterval?
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let latest = snapshots.max(by: { $0.seq < $1.seq }),
               latest.state.isTerminal {
                if case .done = latest.state {
                    elapsed = Date().timeIntervalSince(start)
                }
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let seconds = try XCTUnwrap(elapsed, "the 24MP merge never finished in 600s")
        let extrapolated = seconds * 4.25
        print(
            "MERGE-STOPWATCH-PROBE: \(width)x\(height) (24MP) 3-bracket "
                + "deGhost-off merged in \(String(format: "%.1f", seconds))s — "
                + "100MP linear extrapolation ≈ "
                + "\(String(format: "%.0f", extrapolated))s (research reference <60s)")
    }

    // MARK: - Row 3 (08-5): the LUT HDR-domain storage precision determination

    /// THE WRITTEN DETERMINATION (plan discipline — no human waiver). The
    /// gate: 1e-3 relative at every HDR sample point, float64 reference vs
    /// a Float16-quantized table. Flipping the shipped rgba32Float storage
    /// back to a 16F default requires changing `rgba16FloatDefaultAccepted`
    /// AND beating the gate on BOTH families (the 12-5 D7 breach shape).
    static let rgba16FloatDefaultAccepted = false
    /// The plan-literal gate.
    static let lutStorageRelativeGate = 1e-3

    /// The float64 tetrahedral sampler (the dt lut3d.cl:51-77 branch form:
    /// the branch re-points c1/c2/c3 at the tetrahedron corners; the
    /// sorted-component coefficients are the SAME formula per branch).
    static func tetrahedral64(
        table: [SIMD3<Double>], level: Int,
        domainMin: SIMD3<Double>, domainMax: SIMD3<Double>,
        input: SIMD3<Double>
    ) -> SIMD3<Double> {
        var t = (input - domainMin) / (domainMax - domainMin)
        t = SIMD3(min(max(t.x, 0), 1), min(max(t.y, 0), 1), min(max(t.z, 0), 1))
        let scaled = t * Double(level - 1)
        var i0 = SIMD3(Int(scaled.x), Int(scaled.y), Int(scaled.z))
        i0 = SIMD3(
            min(max(i0.x, 0), level - 2), min(max(i0.y, 0), level - 2),
            min(max(i0.z, 0), level - 2))
        let f = scaled - SIMD3(Double(i0.x), Double(i0.y), Double(i0.z))
        func entry(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Double> {
            table[r + g * level + b * level * level]
        }
        let c000 = entry(i0.x, i0.y, i0.z)
        let c1: SIMD3<Double>, c2: SIMD3<Double>, c3: SIMD3<Double>
        if f.x >= f.y {
            if f.y >= f.z {
                c1 = entry(i0.x + 1, i0.y, i0.z); c2 = entry(i0.x + 1, i0.y + 1, i0.z)
                c3 = entry(i0.x + 1, i0.y + 1, i0.z + 1)
            } else if f.x >= f.z {
                c1 = entry(i0.x + 1, i0.y, i0.z); c2 = entry(i0.x + 1, i0.y, i0.z + 1)
                c3 = entry(i0.x + 1, i0.y + 1, i0.z + 1)
            } else {
                c1 = entry(i0.x, i0.y, i0.z + 1); c2 = entry(i0.x + 1, i0.y, i0.z + 1)
                c3 = entry(i0.x + 1, i0.y + 1, i0.z + 1)
            }
        } else {
            if f.y <= f.z {
                c1 = entry(i0.x, i0.y, i0.z + 1); c2 = entry(i0.x, i0.y + 1, i0.z + 1)
                c3 = entry(i0.x + 1, i0.y + 1, i0.z + 1)
            } else if f.x < f.z {
                c1 = entry(i0.x, i0.y + 1, i0.z); c2 = entry(i0.x, i0.y + 1, i0.z + 1)
                c3 = entry(i0.x + 1, i0.y + 1, i0.z + 1)
            } else {
                c1 = entry(i0.x, i0.y + 1, i0.z); c2 = entry(i0.x + 1, i0.y + 1, i0.z)
                c3 = entry(i0.x + 1, i0.y + 1, i0.z + 1)
            }
        }
        // The sorted-component coefficients (descending: hi ≥ mid ≥ lo).
        let comps = [f.x, f.y, f.z].sorted(by: >)
        let (hi, mid, lo) = (comps[0], comps[1], comps[2])
        return c000 * (1 - hi) + c1 * (hi - mid) + c2 * (mid - lo) + c3 * lo
    }

    func testLutHDRDomainStoragePrecisionDetermination() async throws {
        let metal = try await makeMetal()
        let level = 17
        let domainMax = 8.0

        // Deterministic pseudo-random tables (LCG — stable across runs).
        func lcg(_ state: inout UInt64) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
        }
        var rng: UInt64 = 0x9E3779B97F4A7C15
        // Family A — the positive HDR face (research §13.3's "~5e-4 half"
        // expectation): values in [0.5, 8].
        var positive: [SIMD3<Double>] = []
        positive.reserveCapacity(level * level * level)
        for _ in 0..<(level * level * level) {
            positive.append(SIMD3(0.5 + 7.5 * lcg(&rng), 0.5 + 7.5 * lcg(&rng), 0.5 + 7.5 * lcg(&rng)))
        }
        // Family B — the 12-5 D7 breach shape: mixed-sign HDR values up to
        // ±2.8 (zero-crossing cells — the near-zero interpolation face).
        var mixed: [SIMD3<Double>] = []
        mixed.reserveCapacity(level * level * level)
        for _ in 0..<(level * level * level) {
            mixed.append(SIMD3(
                (2.0 * lcg(&rng) - 1.0) * 2.8,
                (2.0 * lcg(&rng) - 1.0) * 2.8,
                (2.0 * lcg(&rng) - 1.0) * 2.8))
        }

        // The HDR-domain sample points: the patch grays + LCG points.
        var samples: [SIMD3<Double>] = [SIMD3(0.001, 0.001, 0.001), SIMD3(0.5, 0.5, 0.5),
            SIMD3(1, 1, 1), SIMD3(4, 4, 4), SIMD3(7.9, 7.9, 7.9),
            SIMD3(16, 16, 16), SIMD3(-0.5, -0.5, -0.5)]
        for _ in 0..<256 {
            samples.append(SIMD3(
                -0.5 + 9.0 * lcg(&rng), -0.5 + 9.0 * lcg(&rng), -0.5 + 9.0 * lcg(&rng)))
        }

        func maxRelativeError(_ table: [SIMD3<Double>], floor: Double) -> (
            max: Double, breachCount: Int
        ) {
            // The Float16-quantized table (the rgba16Float storage
            // simulation — the ONLY lossy leg; the sampler is shared).
            let quantized: [SIMD3<Double>] = table.map { v in
                SIMD3(
                    Double(Float(Float16(Float(v.x)))),
                    Double(Float(Float16(Float(v.y)))),
                    Double(Float(Float16(Float(v.z)))))
            }
            var maxRel = 0.0
            var breaches = 0
            for s in samples {
                let ref = Self.tetrahedral64(
                    table: table, level: level,
                    domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(domainMax, domainMax, domainMax),
                    input: s)
                let got = Self.tetrahedral64(
                    table: quantized, level: level,
                    domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(domainMax, domainMax, domainMax),
                    input: s)
                for ch in 0..<3 {
                    let denom = max(abs(ref[ch]), floor)
                    let rel = abs(got[ch] - ref[ch]) / denom
                    if rel > maxRel { maxRel = rel }
                    if rel > Self.lutStorageRelativeGate { breaches += 1 }
                }
            }
            return (maxRel, breaches)
        }

        let positiveVerdict = maxRelativeError(positive, floor: 1e-4)
        let mixedVerdict = maxRelativeError(mixed, floor: 1e-4)
        print(
            "LUT-PRECISION-PROBE: positive-domain maxRel=\(positiveVerdict.max) "
                + "breaches=\(positiveVerdict.breachCount) | mixed-sign maxRel="
                + "\(mixedVerdict.max) breaches=\(mixedVerdict.breachCount)")

        // THE DETERMINATION, written:
        if Self.rgba16FloatDefaultAccepted {
            // A 16F-default world: BOTH families must beat the gate.
            XCTAssertLessThanOrEqual(
                positiveVerdict.max, Self.lutStorageRelativeGate,
                "16F acceptance requires the positive HDR face under the gate")
            XCTAssertLessThanOrEqual(
                mixedVerdict.max, Self.lutStorageRelativeGate,
                "16F acceptance requires the mixed-sign face under the gate")
        } else {
            // The shipped D7 verdict: the mixed-sign HDR face BREACHES the
            // gate (the 12-5 golden-gate breach, now pinned as a measured
            // fact) — the rgba32Float upgrade MUST hold.
            XCTAssertGreaterThan(
                mixedVerdict.max, Self.lutStorageRelativeGate,
                "the mixed-sign HDR face must keep breaching 16F storage "
                    + "(the D7 upgrade's standing cause); measured "
                    + "\(mixedVerdict.max)")
        }

        // The production storage is rgba32Float — pinned at BEHAVIOR level:
        // a lattice point whose float32 value is NOT half-representable
        // must come back EXACT through the GPU (a 16F table would deviate
        // by up to ~2e-3 there).
        let rawValue: Float = 4.0009765625 // half-ULP off 4.0 in half precision
        XCTAssertEqual(Float(Float16(rawValue)), 4.0, "the probe value must be 16F-lossy")
        let latticeIndex = 3 + 5 * level + 7 * level * level
        var latticeTable = positive
        latticeTable[latticeIndex] = SIMD3(Double(rawValue), Double(rawValue), Double(rawValue))
        let resolver = LutResolver()
        resolver.tables["probe.cube"] = CubeLut(
            kind: .lut3d(size: level),
            domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(domainMax, domainMax, domainMax),
            data: latticeTable.map { SIMD3(Float($0.x), Float($0.y), Float($0.z)) })
        let module = Lut3dModule(device: metal.device, resolver: resolver)
        var piece = IOPiece()
        module.commitParams(
            Lut3dModule.Params(lutName: "probe.cube", colorspace: .rec2020), into: &piece)
        let latticeInput = SIMD4<Float>(
            Float(3.0 / Double(level - 1) * domainMax), Float(5.0 / Double(level - 1) * domainMax),
            Float(7.0 / Double(level - 1) * domainMax), 1)
        let inTex = makeTexture(metal, width: 1, height: 1, pixels: [latticeInput])
        let outTex = makeTexture(metal, width: 1, height: 1, pixels: [])
        try await module.process(
            input: inTex, output: outTex,
            roiIn: ROI(x: 0, y: 0, width: 1, height: 1, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: 1, height: 1, scale: 1),
            piece: &piece, metal: metal)
        await drain(metal)
        var got = [SIMD4<Float>](repeating: .zero, count: 1)
        got.withUnsafeMutableBytes { raw in
            outTex.getBytes(
                raw.baseAddress!, bytesPerRow: 16,
                from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        }
        for ch in 0..<3 {
            XCTAssertEqual(
                got[0][ch], rawValue, accuracy: 1e-5,
                "the stored table entry must survive EXACTLY (rgba32Float "
                    + "storage; channel \(ch) got \(got[0][ch]))")
        }
    }

    /// The injected resolver for the matrix's lut3d column (the 12-5 test
    /// shape — the module never touches disk itself).
    private final class LutResolver: Lut3dModule.LutResolving, @unchecked Sendable {
        var tables: [String: CubeLut] = [:]
        func lut(named: String) -> CubeLut? { tables[named] }
    }

    // MARK: - Row 4 (08-5): the lut3d matrix column through the REAL pipe

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, pixels: [SIMD4<Float>]
    ) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        if !pixels.isEmpty {
            pixels.withUnsafeBytes { raw in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: width * 16)
            }
        }
        return texture
    }

    func testLut3dColumnKnownPatchChain() async throws {
        let (sourceURL, image, _, width, height) = try await makeKnownPatch()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)

        // The HDR-domain tables (DOMAIN 0..8, 8³): identity + the ×2 gain
        // (linear tables — tetrahedral reproduces them exactly).
        let level = 8
        func lattice(_ i: Int) -> (r: Int, g: Int, b: Int) {
            (i % level, (i / level) % level, i / (level * level))
        }
        var identity: [SIMD3<Float>] = []
        var gain2: [SIMD3<Float>] = []
        identity.reserveCapacity(level * level * level)
        gain2.reserveCapacity(level * level * level)
        for i in 0..<(level * level * level) {
            let (r, g, b) = lattice(i)
            let d = Float(level - 1)
            let v = SIMD3(Float(r) / d * 8, Float(g) / d * 8, Float(b) / d * 8)
            identity.append(v)
            gain2.append(v * 2)
        }
        let resolver = LutResolver()
        resolver.tables["identity.cube"] = CubeLut(
            kind: .lut3d(size: level),
            domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(8, 8, 8), data: identity)
        resolver.tables["gain2.cube"] = CubeLut(
            kind: .lut3d(size: level),
            domainMin: SIMD3(0, 0, 0), domainMax: SIMD3(8, 8, 8), data: gain2)

        func lutBox(_ name: String) -> any ModuleBoxing {
            let box = ModuleBox(module: Lut3dModule(device: metal.device, resolver: resolver))
            box.setParams(Lut3dModule.Params(lutName: name, colorspace: .rec2020))
            return box
        }

        let head = try await makeBoxes(
            registry: registry, exposure: ExposureModule.Params(exposure: 1.0),
            withFilmic: false, withSigmoid: false, withToneEqual: false)
        let (noLut, _) = try await runPipe(image: image, chain: head, metal: metal)
        let (withIdentity, _) = try await runPipe(
            image: image, chain: head + [lutBox("identity.cube")], metal: metal)
        let (withGain, _) = try await runPipe(
            image: image, chain: head + [lutBox("gain2.cube")], metal: metal)
        let base = textureToRGBA(noLut)
        let identityOut = textureToRGBA(withIdentity)
        let gainOut = textureToRGBA(withGain)

        var compared = 0
        var maxIdentityDev: Float = 0
        var maxGainRel: Float = 0
        // The in-domain in-band probes: the 0.5/1.0/4.0 gray steps after
        // the +1EV exposure (values ≤ 8 — inside the table domain).
        for (step, _) in [Float(0.5), 1.0, 4.0].enumerated() {
            let y = (step + 1) * 4 + 2
            let x = width / 2
            let index = (y * width + x) * 4
            for channel in 0..<3 {
                let plain = base[index + channel]
                let id = identityOut[index + channel]
                let g = gainOut[index + channel]
                maxIdentityDev = max(maxIdentityDev, abs(id - plain))
                let expected = plain * 2 // gain 2, in-domain
                maxGainRel = max(maxGainRel, abs(g - expected) / max(abs(expected), 1e-4))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
        print(
            "LUT-COLUMN-PROBE: identity maxDev=\(maxIdentityDev) gain2 maxRel=\(maxGainRel)")
        // The identity table must not bend the HDR chain; the ×2 gain must
        // scale it exactly (the linear-table tetrahedral exactness).
        XCTAssertLessThanOrEqual(
            maxIdentityDev, 1e-4,
            "the HDR-domain identity table must be the chain identity")
        XCTAssertLessThanOrEqual(
            maxGainRel, 1e-3,
            "the ×2 gain HDR-domain table must scale the chain exactly")
    }

    // MARK: - Row 5 (08-5): the preview float32 budget, formal conclusion

    /// The REAL merged product (a small production-leg bracket merge)
    /// through the PREVIEW pipe: the plane memory the preview cache would
    /// carry, measured and printed for perf.md (只记不设门 — the formal
    /// conclusion is 08-5's).
    func testMergedProductPreviewMemoryProbe() async throws {
        // Build a REAL product through the production leg (3 sources).
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hdr-matrix-merge-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let width = 64, height = 64
        var sources: [URL] = []
        for (index, exposure) in [Float(0.25), 1, 2].enumerated() {
            var plane = [Float](repeating: 0, count: width * height * 4)
            for pixel in stride(from: 0, to: plane.count, by: 4) {
                let value = 0.5 * exposure + Float(index) * 0.001
                plane[pixel] = value
                plane[pixel + 1] = value
                plane[pixel + 2] = value
                plane[pixel + 3] = 1
            }
            let url = root.appendingPathComponent("src\(index).tif")
            try BandStreamer.writeFloatTIFF(plane, width: width, height: height, to: url)
            sources.append(url)
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal GPU")
        }
        let service = try StackMergeService(device: device)
        _ = try await service.enqueue(
            kind: .hdrMerge, sources: sources,
            params: .init(deGhost: false), sessionRoot: root)
        let deadline = Date().addingTimeInterval(60)
        var productURL: URL?
        while Date() < deadline {
            let snapshots = await service.snapshots()
            if let latest = snapshots.max(by: { $0.seq < $1.seq }),
               case .done(let url) = latest.state {
                productURL = url
                break
            }
            if let latest = snapshots.max(by: { $0.seq < $1.seq }),
               latest.state.isTerminal { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let product = try XCTUnwrap(productURL, "the merge never finished")
        let decoded = try await RAWDecoder().decode(product)
        let metal = try await makeMetal()
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let chain = try await makeBoxes(
            registry: registry, exposure: nil,
            withFilmic: false, withSigmoid: false, withToneEqual: false)
        let (texture, bytes) = try await runPipe(
            image: decoded, chain: chain, metal: metal, resolution: .preview)
        let megapixels = Double(texture.width * texture.height) / 1_000_000
        print(
            "PREVIEW-FLOAT32-PROBE: \(texture.width)x\(texture.height) "
                + "(\(String(format: "%.2f", megapixels))MP) preview plane = "
                + "\(bytes / 1_048_576) MiB (\(bytes) B; reference 2560px ≈70 MB/plane)")
        XCTAssertGreaterThan(bytes, 0)

        // ── the FORMAL BUDGET CONCLUSION (Plan 08-5 T3, research §13.2) ──
        // The preview plane ceiling: the 2560px long-edge float32 RGBA
        // reference (2560×1707×16 B ≈ 70 MB/plane), +5% ladder slack.
        let referenceBytes = 2560 * 1707 * 16
        XCTAssertLessThanOrEqual(
            Double(bytes), Double(referenceBytes) * 1.05,
            "the preview plane must stay inside the float32 budget: "
                + "\(bytes) vs \(referenceBytes)")
        // The no-new-cache-class pin: merged products ride the STANDARD
        // preview/full policies — enforceBudget's five tiers unchanged.
        XCTAssertTrue(PipeResolution.preview.cachesIntermediatePlanes)
        XCTAssertTrue(PipeResolution.thumbnail.cachesIntermediatePlanes)
        XCTAssertFalse(PipeResolution.full.cachesIntermediatePlanes)
        XCTAssertFalse(PipeResolution.export.cachesIntermediatePlanes)
    }
}
