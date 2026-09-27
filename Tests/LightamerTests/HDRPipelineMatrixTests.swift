@testable import LightamerCore
import CoreImage
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// HDRPipelineMatrixTests (Plan 08-1 T7; RESEARCH §13) — the HDR-04
// verification-matrix BASE (the lut3d column lands with 08-5; the full
// dt-golden cross-reference for filmicrgb/sigmoid stays with the Phase 3
// suite, which pins those modules against the dt-generated EXRs).
//
// Rows delivered here (the matrix's first two lines + the preview budget
// probe):
//   1. The shadow-torture HDR content (the Phase 2 golden harness's
//      fixture, round-tripped through the REAL raster decode) through
//      [colorin, exposure(+1EV), filmicrgb, sigmoid, toneequal(0)] —
//      structural invariants: FINITENESS through the whole chain (no NaN
//      at any stage; the >1.0 scene values flow through), NON-COLLAPSE,
//      and the toneequal-zero-params identity at the tail (≤1e-4 per
//      point — the local-Laplacian stage must not bend an HDR document).
//   2. The known-value float32 patch (0.001/0.5/1.0/4.0/16.0/65504 gray
//      steps + an RGB sweep) through [colorin, exposure] — the EXACT
//      CPU float32 reference (×2^EV per point; the element-wise 1e-5
//      Phase 3 tolerance), pins the HDR values surviving the pipe
//      UNCLAMPED (clamping belongs to gamma alone).
//
// EXECUTION-SCOPE NOTE (D-08-1-T7, recorded): the plan's "float32 CPU
// reference point-parity" for the filmicrgb/sigmoid legs of the CHAIN is
// the Phase 3 golden shape — that shape's reference generator is the dt
// side (input/golden/regenerate.sh), which does not emit COMBINED-chain
// artifacts. The base pins the structural invariants + the analytic
// exposure reference; extending the dt generator for the combined chain
// is the 08-5 close-out item.
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

    // MARK: - The preview float32 budget probe (RESEARCH §13.2)

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
    }
}
