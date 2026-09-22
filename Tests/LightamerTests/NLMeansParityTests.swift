@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// NLMeansParityTests (Plan 05-06) — T1 kernel-group gates first, T3/T4
// golden + tiling + chroma legs layered on top:
//
//   T1 (this file's scan/smoke half):
//   - workgroup size scan {64,128,256,512}: all combinations byte-identical
//     (correctness gate BEFORE locking the threadgroup block size — plan
//     纪律 "scan 不过不锁定参数"; dt probes dt_opencl_local_buffer_opt with
//     a 2^16-cell budget, Metal pins an explicit value in DECISIONS);
//   - flat-field → flat-field identity smoke (noise-free flat ⇒ dist=0 ⇒
//     w=gh(0)=fast_mexp2f(0)=1.0 exactly ⇒ out = neighborhood mean = in,
//     within the Lab powr-chain + box-sum rounding);
//   - noise direction probe: seeded noise IS smoothed (non-vacuous).
//
// L014: every readback drains the queue first. 防空转: all loops carry
// `compared > 0` assertions.
final class NLMeansParityTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: NLMeansKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Texture helpers (direct engine drives — no pipe)

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int,
        pixel: (Int, Int) -> SIMD4<Float>
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        var floats = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let px = pixel(x, y)
                floats[(y * width + x) * 4 + 0] = px.x
                floats[(y * width + x) * 4 + 1] = px.y
                floats[(y * width + x) * 4 + 2] = px.z
                floats[(y * width + x) * 4 + 3] = px.w
            }
        }
        floats.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func readRGBA(_ tex: any MTLTexture, metal: MetalContext) -> [Float] {
        drain(metal) // L014
        var floats = [Float](repeating: 0, count: tex.width * tex.height * 4)
        floats.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return floats
    }

    /// Deterministic pseudo-noise in [−0.5, 0.5) (hash flow — same input
    /// every scan leg; NOT the golden noise fixture, just scan fodder).
    private func pseudoNoise(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 73856093 ^ y &* 19349663)
        h = h &* 2654435761 &+ 0x9E3779B9
        return Float(h >> 9) / Float(UInt32.max >> 9) - 0.5
    }

    /// Gradient + pseudo-noise field (linear Rec2020-ish, [0,1]).
    private func makeNoisyTexture(
        _ metal: MetalContext, width: Int, height: Int, noiseAmp: Float
    ) throws -> any MTLTexture {
        try makeTexture(metal, width: width, height: height) { x, y in
            let base = 0.05 + 0.85 * Float(x) / Float(max(width - 1, 1))
            let v = max(min(base + noiseAmp * pseudoNoise(x, y), 1), 0)
            return SIMD4(v, v, v, 1)
        }
    }

    private func makeScratch(
        _ metal: MetalContext, width: Int, height: Int
    ) throws -> NLMeansModule.Scratch {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let planeBytes = width * height * MemoryLayout<Float>.size
        return NLMeansModule.Scratch(
            lab: try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor)),
            u2: try XCTUnwrap(
                metal.device.makeBuffer(length: width * height * 16, options: .storageModeShared)),
            buckets: try XCTUnwrap(
                metal.device.makeBuffer(length: planeBytes * 4, options: .storageModeShared)),
            planeBytes: planeBytes)
    }

    private func denoise(
        _ metal: MetalContext, input: any MTLTexture, blockSize: Int
    ) async throws -> [Float] {
        let output = try makeTexture(metal, width: input.width, height: input.height) { _, _ in
            SIMD4(0, 0, 0, 1)
        }
        let scratch = try makeScratch(metal, width: input.width, height: input.height)
        try await NLMeansModule.denoise(
            input: input, output: output,
            radius: 2, strength: 50, luma: 0.5, chroma: 1,
            roiScale: 0.4, iscale: 1.0,  // P=1, K=3 → 28 offsets (scan keeps it fast)
            pipeType: .full, metal: metal, blockSize: blockSize, scratch: scratch)
        return readRGBA(output, metal: metal)
    }

    // MARK: - T1 ① workgroup size scan

    /// threadgroup block size ∈ {64,128,256,512} on the SAME input: all
    /// four outputs BYTE-identical (the sliding-window wings must produce
    /// exactly the same box sums at every workgroup shape — a correctness
    /// gate, not a tolerance gate).
    func testWorkgroupSizeScanAllByteIdentical() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 64
        let input = try makeNoisyTexture(metal, width: width, height: height, noiseAmp: 0.05)

        var baseline: [Float]?
        var compared = 0
        var mismatchBytes = 0
        for blockSize in [64, 128, 256, 512] {
            let out = try await denoise(metal, input: input, blockSize: blockSize)
            compared += 1
            if let baseline {
                XCTAssertEqual(out.count, baseline.count)
                for i in 0..<out.count where out[i].bitPattern != baseline[i].bitPattern {
                    mismatchBytes += 1
                }
            } else {
                baseline = out
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(mismatchBytes, 0, "scan legs must be byte-identical (got \(mismatchBytes) diffs)")
    }

    // MARK: - T1 ② flat-field identity smoke

    /// Noise-free flat ⇒ dist=0 ⇒ w=gh(0)=fast_mexp2f(0)=1.0 EXACTLY ⇒
    /// out = box mean = in (within Lab powr-chain ~2ulp + box-sum rounding;
    /// gate 1e-4 rel — far inside the denoise 1e-3 family tier).
    func testFlatFieldIdentitySmoke() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48
        let input = try makeTexture(metal, width: width, height: height) { _, _ in
            SIMD4(0.18, 0.18, 0.18, 1)
        }
        let out = try await denoise(metal, input: input, blockSize: 128)
        var compared = 0
        var maxRel: Float = 0
        for i in 0..<(width * height) {
            for c in 0..<3 {
                compared += 1
                let o = out[i * 4 + c]
                maxRel = max(maxRel, abs(o - 0.18) / 0.18)
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(maxRel, 1e-4, "flat identity smoke: maxRel=\(maxRel)")
    }

    // MARK: - T1 ③ noise direction probe (non-vacuous)

    /// Seeded noise IS smoothed: output closer to the noise-free ramp than
    /// the noisy input is (RMS-to-truth strictly decreases).
    func testNoiseIsSmoothedTowardTruth() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 64
        var truth = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                truth[y * width + x] = 0.05 + 0.85 * Float(x) / Float(width - 1)
            }
        }
        let noisy = try makeNoisyTexture(metal, width: width, height: height, noiseAmp: 0.08)
        let out = try await denoise(metal, input: noisy, blockSize: 128)

        func rmsToTruth(_ values: [Float]) -> Float {
            var acc: Float = 0
            for y in 0..<height {
                for x in 0..<width {
                    let v = values[(y * width + x) * 4]
                    let d = v - truth[y * width + x]
                    acc += d * d
                }
            }
            return (acc / Float(width * height)).squareRoot()
        }
        let noisyRGBA = readRGBA(noisy, metal: metal)
        let rmsIn = rmsToTruth(noisyRGBA)
        let rmsOut = rmsToTruth(out)
        XCTAssertGreaterThan(rmsIn, 0.01, "fixture must actually carry noise")
        XCTAssertLessThan(
            rmsOut, rmsIn * 0.8,
            "denoise must move toward truth: rmsIn=\(rmsIn) rmsOut=\(rmsOut)")
    }

    // MARK: - T2 preview-downgrade constants (DECISIONS pins)

    /// K clamp 3 + decimate on PREVIEW/THUMBNAIL, full K=7 on FULL:
    /// the derivation table pinned at multiple scales (nlmeans.c:171-172
    /// dt shapes; clamp = denoiseprofile.c:1626-1631 shape; decimate skip
    /// parity = nlmeans_core.c:103-118).
    func testPreviewDowngradeDerivations() {
        var compared = 0
        // FULL: K = ceil(7·scale) at several scales; P = ceil(radius·scale).
        for (roiScale, iscale) in [(Float(1.0), Float(1.0)), (Float(0.5), Float(1.0)), (Float(1.0), Float(0.25)), (Float(2.0), Float(1.0)), (Float(0.3), Float(1.0))] {
            let kFull = NLMeansModule.fullSearchRadius(roiScale: roiScale, iscale: iscale)
            XCTAssertEqual(
                kFull, Int((7 * NLMeansModule.radiusScale(roiScale: roiScale, iscale: iscale)).rounded(.up)),
                "FULL K formula @scale \(roiScale)/\(iscale)")
            let kPipe = NLMeansModule.searchRadius(roiScale: roiScale, iscale: iscale, pipeType: .full)
            XCTAssertEqual(kPipe, kFull, "FULL keeps the formula K")
            compared += 1
            // PREVIEW/THUMBNAIL clamp to 3.
            for tier in [PipeResolution.preview, .thumbnail] {
                XCTAssertEqual(
                    NLMeansModule.searchRadius(roiScale: roiScale, iscale: iscale, pipeType: tier),
                    min(3, kFull), "clamp K=3 @\(tier) scale \(roiScale)/\(iscale)")
                XCTAssertTrue(NLMeansModule.decimates(pipeType: tier), "\(tier) decimates")
                compared += 1
            }
            XCTAssertFalse(NLMeansModule.decimates(pipeType: .full), "FULL never decimates")
        }
        // 手算 pins：FULL scale1 → K=7 → 120 offsets；PREVIEW scale1 →
        // K=3 → 28 raw → decimate → 14（跳双留单——首偏移保留）。
        XCTAssertEqual(NLMeansModule.offsets(K: 7, decimate: false).count, 120)
        XCTAssertEqual(NLMeansModule.offsets(K: 3, decimate: false).count, 28)
        let decimated = NLMeansModule.offsets(K: 3, decimate: true)
        XCTAssertEqual(decimated.count, 14)
        XCTAssertEqual(decimated.first?.qx, -3, "first offset kept")
        XCTAssertEqual(decimated.first?.qy, -3, "first offset kept")
        // FULL 满血趟数：120×4 + finish = 481；PREVIEW 降载：14×4+1 = 57。
        XCTAssertEqual(NLMeansModule.offsets(K: 7, decimate: false).count * 4 + 1, 481)
        XCTAssertEqual(decimated.count * 4 + 1, 57)
        // sharpness = 3000/(1+strength)（nlmeans.c:173）。
        XCTAssertEqual(NLMeansModule.sharpness(strength: 0), 3000, accuracy: 1e-4)
        XCTAssertEqual(NLMeansModule.sharpness(strength: 50), 3000.0 / 51.0, accuracy: 1e-5)

        XCTAssertGreaterThan(compared, 0)
    }

    /// Tile seam pins (L020/L021): halo = P+K from the RUN-level
    /// roi.scale ÷ piece.iscale — identical for plane-level and any tile
    /// ROI at the same scale (K/P are run constants, not tile functions);
    /// working set = 80 B/px (factor 5.0 × 16 — dt 4.0 + the module-local
    /// Lab plane dt gets for free from its pipeline).
    func testTileSeamConstantsAndTileInvariance() async throws {
        let module = NLMeansModule()
        var piece = IOPiece()
        piece.iscale = 1.0
        piece.dscIn = IOPBufferDesc(width: 512, height: 384)
        await module.commitParams(NLMeansModule.Params(), into: &piece)

        let planeROI = ROI(x: 0, y: 0, width: 512, height: 384, scale: 1.0)
        let halo = module.tileHalo(roi: planeROI, piece: piece)
        // P = ceil(2·1) = 2, K = ceil(7·1) = 7 → halo 9 (dt tiling :339).
        XCTAssertEqual(halo, 9)
        XCTAssertEqual(module.tileWorkingSetBytesPerPixel(piece: piece), 80)

        // K/P 由 iscale 派生不随 tile 变：任意 tile 子窗 ROI（同 scale）
        // 的 halo 与整幅一致——分块==整幅门的几何前提。
        let tileROIs = [
            ROI(x: 128, y: 96, width: 128, height: 96, scale: 1.0),
            ROI(x: 0, y: 0, width: 100, height: 64, scale: 1.0),
            ROI(x: 384, y: 288, width: 128, height: 96, scale: 1.0),
        ]
        for tile in tileROIs {
            XCTAssertEqual(
                module.tileHalo(roi: tile, piece: piece), 9,
                "halo must not depend on the tile rect")
        }
        // scale 补偿：roi.scale 2 / iscale 1 → scale=min(2,2)/1 = 2 →
        // P=4, K=14 → halo 18；entry iscale 0.5 被 dt 公式的 fmax(·,1)
        // 钳到 1（half-scale run 不放大半径）。
        XCTAssertEqual(NLMeansModule.patchRadius(radius: 2, roiScale: 2, iscale: 1), 4)
        XCTAssertEqual(NLMeansModule.fullSearchRadius(roiScale: 2, iscale: 1), 14)
        let scaledPiece = IOPiece()
        var scaledPieceMut = scaledPiece
        scaledPieceMut.iscale = 0.5
        scaledPieceMut.dscIn = IOPBufferDesc(width: 1024, height: 768)
        await module.commitParams(NLMeansModule.Params(), into: &scaledPieceMut)
        XCTAssertEqual(
            module.tileHalo(roi: ROI(x: 0, y: 0, width: 1024, height: 768, scale: 2.0), piece: scaledPieceMut),
            18, "scale = min(2,2)/max(0.5,1) = 2 → P=4, K=14")
    }

    /// 100MP FULL budget preview (the 05-01 placeholder formalized):
    /// 11648×8736 @80 B/px ≈ 8.14GB > 512MB → the tile grid must engage
    /// with >1 tiles and every tile within the 3GB budget.
    func testFullResolutionTileGridEngages() {
        let fullW = 11648, fullH = 8736
        let budget = 512 << 20
        // Untiled working set: 100MP × 80 = 8.14GB > 3GB budget — tiling
        // is MANDATORY (the TilingPlan first heavy consumer).
        XCTAssertGreaterThan(
            Double(fullW * fullH * 80), 3.0e9, "100MP FULL must exceed the budget")
        let tiles = TilingPlan.tiles(
            forWidth: fullW, height: fullH, maxTileBytes: budget,
            bytesPerPixel: 80, overlap: 9)
        var compared = 0
        var maxTileBytes = 0
        XCTAssertGreaterThan(tiles.count, 1, "分块真的发生（grid >1）")
        for tile in tiles {
            compared += 1
            XCTAssertGreaterThan(tile.width, 0)
            XCTAssertGreaterThan(tile.height, 0)
            maxTileBytes = max(maxTileBytes, (tile.width + 2 * 9) * (tile.height + 2 * 9) * 16)
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(
            Double(maxTileBytes), 3.0e9,
            "tile working set (halo-widened read planes) <3GB: \(maxTileBytes)")
    }
}
