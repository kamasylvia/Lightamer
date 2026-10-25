@testable import LightamerCore
import Darwin
import Foundation
import Metal
import simd
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralPerfProbeTests (Plan M8-1b T4 — IOPParity, the *PerfProbe* domain
// pattern) — the ENV-GATED probe batch behind LIGHTAMER_PERF_PROBE=1 (skipped
// in the default suite — these are observation records, not regression gates;
// the GradeEnvelopePerfProbe precedent). Run manually:
//
//   LIGHTAMER_PERF_PROBE=1 Scripts/test-direct.sh --bundle IOPParity \
//     'SpectralPerfProbeTests'
//
// RESEARCH §4.3's five probes:
//   ① tc table build cost (the 28-profile full set + the per-pair median)
//     + the fitted-spectrum white-point scatter;
//   ② kernel microbench — synthetic 100MP full frame with SEGMENT signposts
//     (A / blur / B) against the 40-160 ms budget band (a real-image leg
//     rides the vendored 160×120 gradient fixture — the 100MP face itself
//     is synthetic, the GradeEnvelopePerfProbe precedent);
//   ③ the corr decimation verdict data — phys_footprint peak at 1/4 vs 1/8
//     + the fidelity spread between the two (the M8-1B-DECISIONS 双门);
//   ④ the spectral arm's ramp sentinel (FNV-1a over the fused-chain output)
//     + the legacy density-kernel sentinel constant pinned unchanged;
//   ⑤ the nail divergence assembly (the T3 nail measurements, re-run and
//     printed as one record).
//
// L014: every segment's clock is read only after a command-buffer fence.
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralPerfProbeTests: XCTestCase {

    private func probeEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "manual probe — set LIGHTAMER_PERF_PROBE=1 (RESEARCH §4.3)")
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
    }

    // MARK: - Fixtures (memoized — the engine's coefficient memo makes the
    // second build cheap)

    private static let fixtureBox = ProbeFixtureBox()

    /// The tables memo box (the class-instance form — the mutable state
    /// stays off the global-actor checker).
    private final class ProbeFixtureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SpectralFilmTables?
        func tables(make: () throws -> SpectralFilmTables) throws -> SpectralFilmTables {
            lock.lock()
            defer { lock.unlock() }
            if let value { return value }
            lock.unlock()
            let made = try make()
            lock.lock()
            value = made
            lock.unlock()
            return made
        }
    }

    private static func tables() throws -> SpectralFilmTables {
        try fixtureBox.tables {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let profiles = root.appendingPathComponent("Resources/FilmProfiles/profiles")
            let film = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_400.json"))
            let paper = try FilmProfile.load(
                profiles.appendingPathComponent("kodak_portra_endura.json"))
            return try SpectralBuildEngine.build(
                film: film, paper: paper,
                parameters: SpectralBuildEngine.Parameters())
        }
    }

    private func makePayloads(_ metal: MetalContext, width: Int, height: Int,
                              decimation: Int) throws -> SpectralGPUPayloads {
        try SpectralGPUPayloads(
            device: metal.device, tables: Self.tables(),
            couplers: Self.couplers, decimation: decimation,
            frameWidth: width, frameHeight: height)
    }

    private static let couplers: SpectralCouplerParams = {
        var c = SpectralCouplerParams()
        c.active = true
        c.matrix = [0.52, 0.06, 0.03, 0.05, 0.59, 0.04, 0.02, 0.05, 0.28]
        c.donorLM = true
        c.donorK = SIMD3<Float>(3.4, 3.4, 3.0)
        c.donorDref = SIMD3<Float>(0.8, 0.85, 0.75)
        c.recvLM = true
        c.recvKr = SIMD3<Float>(1.7, 2.1, 1.5)
        c.recvCref = SIMD3<Float>(0.3, 0.4, 0.2)
        return c
    }()

    // MARK: - Texture helpers

    private func texture(_ metal: MetalContext, width: Int, height: Int,
                         write: Bool) throws -> any MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, write ? .shaderWrite : .shaderRead]
        desc.storageMode = .shared
        return try XCTUnwrap(metal.device.makeTexture(descriptor: desc))
    }

    private func readback(_ texture: any MTLTexture) -> [Float] {
        let w = texture.width, h = texture.height
        var data = [Float](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: w * 4 * MemoryLayout<Float>.stride,
                from: MTLRegion(origin: MTLOrigin(),
                                size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return data
    }

    private func fence(_ metal: MetalContext) async {
        let f = metal.commandQueue.makeCommandBuffer()
        f?.commit()
        await f?.completed()
    }

    /// One fused-chain run (A → blur row → blur col → B) with per-segment
    /// signposts, each clocked behind a fence (L014).
    private func runChain(
        _ metal: MetalContext, payloads: SpectralGPUPayloads,
        input: any MTLTexture, output: any MTLTexture,
        corrA: any MTLTexture, corrBlur1: any MTLTexture, corrBlur2: any MTLTexture
    ) async throws -> (aMs: Double, blurMs: Double, bMs: Double, totalMs: Double) {
        let cw = payloads.corrWidth, ch = payloads.corrHeight
        let w = input.width, h = input.height

        var t0 = DispatchTime.now()
        let sessionA = try await metal.makeEncoder(functionName: "spectral_film_stage_a")
        sessionA.encoder.setTexture(input, index: 0)
        sessionA.encoder.setTexture(corrA, index: 1)
        sessionA.encoder.setTexture(payloads.tcLutTexture, index: 2)
        sessionA.encoder.setBuffer(payloads.curvesBuffer, offset: 0, index: 0)
        sessionA.encoder.setBuffer(payloads.constBlockBuffer, offset: 0, index: 1)
        sessionA.encoder.setBuffer(payloads.uniformsBuffer, offset: 0, index: 2)
        sessionA.encoder.dispatchThreads(
            MTLSize(width: cw, height: ch, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        sessionA.encoder.endEncoding()
        sessionA.commandBuffer.commit()
        await sessionA.commandBuffer.completed()
        var t1 = DispatchTime.now()

        for (src, dst) in [(corrA, corrBlur1), (corrBlur1, corrBlur2)] {
            let blur = try await metal.makeEncoder(functionName: "spectral_film_blur_row")
            blur.encoder.setTexture(src, index: 0)
            blur.encoder.setTexture(dst, index: 1)
            blur.encoder.setBuffer(payloads.blurWeightsBuffer, offset: 0, index: 0)
            blur.encoder.setBuffer(payloads.uniformsBuffer, offset: 0, index: 2)
            blur.encoder.dispatchThreads(
                MTLSize(width: cw, height: ch, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            blur.encoder.endEncoding()
            blur.commandBuffer.commit()
            await blur.commandBuffer.completed()
            // the second pass runs the COLUMN kernel on the row's output
            let blur2 = try await metal.makeEncoder(functionName: "spectral_film_blur_col")
            blur2.encoder.setTexture(dst, index: 0)
            blur2.encoder.setTexture(src, index: 1)
            blur2.encoder.setBuffer(payloads.blurWeightsBuffer, offset: 0, index: 0)
            blur2.encoder.setBuffer(payloads.uniformsBuffer, offset: 0, index: 2)
            blur2.encoder.dispatchThreads(
                MTLSize(width: cw, height: ch, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            blur2.encoder.endEncoding()
            blur2.commandBuffer.commit()
            await blur2.commandBuffer.completed()
        }
        // the blurred field lands back in corrA (the ping-pong wrote it last)
        var t2 = DispatchTime.now()

        let sessionB = try await metal.makeEncoder(functionName: "spectral_film_stage_b")
        sessionB.encoder.setTexture(input, index: 0)
        sessionB.encoder.setTexture(output, index: 1)
        sessionB.encoder.setTexture(corrA, index: 2)
        sessionB.encoder.setTexture(payloads.tcLutTexture, index: 3)
        let buffers: [any MTLBuffer] = [
            payloads.curvesBuffer, payloads.printCurvesBuffer,
            payloads.printLut, payloads.printSx, payloads.printSy,
            payloads.printSz, payloads.printCmin, payloads.printCmax,
            payloads.scanLut, payloads.scanSx, payloads.scanSy,
            payloads.scanSz, payloads.scanCmin, payloads.scanCmax,
            payloads.cmaxBuffer, payloads.constBlockBuffer, payloads.uniformsBuffer,
        ]
        for (i, b) in buffers.enumerated() { sessionB.encoder.setBuffer(b, offset: 0, index: i) }
        sessionB.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        sessionB.encoder.endEncoding()
        sessionB.commandBuffer.commit()
        await sessionB.commandBuffer.completed()
        let t3 = DispatchTime.now()

        func ms(_ from: DispatchTime, _ to: DispatchTime) -> Double {
            Double(to.uptimeNanoseconds - from.uptimeNanoseconds) / 1e6
        }
        return (ms(t0, t1), ms(t1, t2), ms(t2, t3), ms(t0, t3))
    }

    // MARK: - probe ①: tc build cost + white-point scatter

    func testProbe1TcBuildCostAndWhiteScatter() throws {
        try probeEnabled()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent("Resources/FilmProfiles/profiles")
        let names = try XCTUnwrap(try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { $0.lastPathComponent }
            .sorted())
        let paper = try FilmProfile.load(
            directory.appendingPathComponent("kodak_portra_endura.json"))

        var timings: [Double] = []
        var started = Date()
        for name in names {
            let film = try FilmProfile.load(directory.appendingPathComponent(name))
            let t0 = DispatchTime.now()
            _ = try SpectralBuildEngine.build(
                film: film, paper: paper,
                parameters: SpectralBuildEngine.Parameters())
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
            timings.append(ms)
        }
        let sorted = timings.sorted()
        let median = sorted[sorted.count / 2]
        let total = -started.timeIntervalSinceNow
        print("PERF-PROBE|spectral-tc|pairs=\(names.count)|totalMs=\(total * 1000)|" +
            "medianMs=\(median)|minMs=\(sorted.first!)|maxMs=\(sorted.last!) " +
            "(Debug-test context; the -O production cost is the M8-1a ~17.5 s record)")

        // the fitted-spectrum white-point scatter (the X1 quality gate's
        // observation face): the REBUILT chromaticity at the named
        // illuminant cells (the SpectralTcFit named-cell face — grid-index
        // sampling would truncate half a cell and read the neighbor)
        let axis = SpectralConstantsData.wavelengthsNm
        let cmfs = SpectralConstantsData.cmfs
        var worstScatter = 0.0
        for (name, x, y) in [("D55", 0.33243163892154926, 0.34744439893064605),
                             ("D65", 0.3127, 0.3290)] {
            let fit = SpectralTcFit.fitCell(x: x, y: y, axis: axis, cmfs: cmfs)
            let rebuilt = SpectralTcFit.rebuiltChromaticity(
                coefficients: fit.coefficients, axis: axis, cmfs: cmfs)
            let scatter = max(abs(rebuilt.x - x), abs(rebuilt.y - y))
            worstScatter = max(worstScatter, scatter)
            print("PERF-PROBE|spectral-tc|whiteScatter|\(name)|maxComp=\(scatter)")
        }
        print("PERF-PROBE|spectral-tc|whiteScatter|worst=\(worstScatter)|band=2e-5")
        XCTAssertLessThanOrEqual(worstScatter, 2e-5,
            "the named-cell band (the M8-1a measured ≤5.3e-6 actuals)")
    }

    // MARK: - probe ②: 100MP kernel microbench with segment signposts

    func testProbe2KernelMicrobench100MP() async throws {
        try probeEnabled()
        let metal = try MetalContext()
        let width = 10_000, height = 10_000  // 100MP
        let payloads = try makePayloads(metal, width: width, height: height,
                                        decimation: 4)

        let input = try texture(metal, width: width, height: height, write: false)
        let output = try texture(metal, width: width, height: height, write: true)
        let cw = payloads.corrWidth, ch = payloads.corrHeight
        let corrA = try texture(metal, width: cw, height: ch, write: true)
        let blur1 = try texture(metal, width: cw, height: ch, write: true)
        let blur2 = try texture(metal, width: cw, height: ch, write: true)

        // the synthetic ramp (row-wise, memcpy-shaped construction — the
        // GradeEnvelopePerfProbe precedent)
        var pixels = [Float](repeating: 0, count: width * 4)
        for x in 0..<width {
            pixels[x * 4 + 0] = 0.1 + 0.7 * Float(x) / Float(width - 1)
            pixels[x * 4 + 1] = 0.2
            pixels[x * 4 + 2] = 0.3
            pixels[x * 4 + 3] = 1.0
        }
        pixels.withUnsafeBytes {
            for y in 0..<height {
                input.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: y, z: 0),
                                      size: MTLSize(width: width, height: 1, depth: 1)),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: 0)
            }
        }
        await fence(metal)

        // warm one pass, then 3 timed runs; the median is the record
        _ = try await runChain(metal, payloads: payloads, input: input,
                               output: output, corrA: corrA, corrBlur1: blur1,
                               corrBlur2: blur2)
        var runs: [(aMs: Double, blurMs: Double, bMs: Double, totalMs: Double)] = []
        for _ in 0..<3 {
            runs.append(try await runChain(
                metal, payloads: payloads, input: input, output: output,
                corrA: corrA, corrBlur1: blur1, corrBlur2: blur2))
        }
        let med = { (values: [Double]) -> Double in values.sorted()[values.count / 2] }
        let a = med(runs.map { $0.aMs })
        let blur = med(runs.map { $0.blurMs })
        let b = med(runs.map { $0.bMs })
        let total = med(runs.map { $0.totalMs })
        print("PERF-PROBE|spectral-100MP|FULL|total=\(String(format: "%.1f", total))ms|" +
            "A=\(String(format: "%.1f", a))ms|blur=\(String(format: "%.1f", blur))ms|" +
            "B=\(String(format: "%.1f", b))ms|budget=40-160ms")
        XCTAssertGreaterThan(total, 0)

        // the real-pixel leg: the vendored gradient fixture through the same
        // chain (a small real image — the content face, not the budget face)
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/TestFixtures/float32-gradient.tif")
        if FileManager.default.fileExists(atPath: fixtureURL.path),
            let ci = CIImage(contentsOf: fixtureURL) {
            let ciw = Int(ci.extent.width), cih = Int(ci.extent.height)
            let render = try XCTUnwrap(CIContext(options: nil))
            var rgba = [Float](repeating: 0, count: ciw * cih * 4)
            render.render(ci,
                toBitmap: &rgba, rowBytes: ciw * 4 * MemoryLayout<Float>.stride,
                bounds: ci.extent, format: .RGBAf, colorSpace: WorkingSpace.colorSpace)
            let fixtureIn = try texture(metal, width: ciw, height: cih, write: false)
            rgba.withUnsafeBytes {
                fixtureIn.replace(
                    region: MTLRegion(origin: MTLOrigin(),
                                      size: MTLSize(width: ciw, height: cih, depth: 1)),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: ciw * 4 * MemoryLayout<Float>.stride)
            }
            let fw = try makePayloads(metal, width: ciw, height: cih, decimation: 4)
            let fixtureOut = try texture(metal, width: ciw, height: cih, write: true)
            let fc1 = try texture(metal, width: fw.corrWidth, height: fw.corrHeight, write: true)
            let fc2 = try texture(metal, width: fw.corrWidth, height: fw.corrHeight, write: true)
            let fc3 = try texture(metal, width: fw.corrWidth, height: fw.corrHeight, write: true)
            let fixtureRun = try await runChain(
                metal, payloads: fw, input: fixtureIn,
                                                output: fixtureOut, corrA: fc1,
                                                corrBlur1: fc2, corrBlur2: fc3)
            print("PERF-PROBE|spectral-fixture|\(ciw)x\(cih)|" +
                "total=\(String(format: "%.2f", fixtureRun.totalMs))ms")
            let out = readback(fixtureOut)
            var finite = true
            for v in out where !v.isFinite { finite = false; break }
            XCTAssertTrue(finite, "the real-fixture render must stay finite")
        }
    }

    // MARK: - probe ③: corr decimation verdict data (footprint + fidelity)

    /// The in-process phys_footprint (the /usr/bin/time ru_maxrss family —
    /// the kernel-accounted high-water face, sampled at the allocation peaks).
    private func physFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
    }

    func testProbe3CorrDecimationFootprintAndFidelity() async throws {
        try probeEnabled()
        let metal = try MetalContext()
        let width = 10_000, height = 10_000

        // the fidelity face first (small, exact): the full chain at 1/4 vs
        // 1/8 on a 512² ramp — the corr 高频损失 spread at MATCHED physical
        // blur (the cell radius scales with the decimation so both arms
        // blur over the same physical width)
        var fidelity: Double = 0
        var outputs: [[Float]] = []
        for decimation in [1, 2, 4, 8] {
            // matched PHYSICAL blur: a constant sigma of 4 FULL pixels —
            // the cell-unit sigma shrinks as the cells grow
            var c = Self.couplers
            c.blurSigma = 4.0 / Float(decimation)
            c.blurRadius = max(1, Int((12.0 / Float(decimation)).rounded(.up)))
            let payloads = try SpectralGPUPayloads(
                device: metal.device, tables: Self.tables(), couplers: c,
                decimation: decimation, frameWidth: 512, frameHeight: 512)
            let input = try texture(metal, width: 512, height: 512, write: false)
            var px = [Float](repeating: 0, count: 512 * 512 * 4)
            for y in 0..<512 {
                for x in 0..<512 {
                    let i = (y * 512 + x) * 4
                    px[i + 0] = 0.12 + 0.6 * Float(x) / 511
                    px[i + 1] = 0.18 + 0.4 * Float(y) / 511
                    px[i + 2] = 0.25
                    px[i + 3] = 1.0
                }
            }
            px.withUnsafeBytes {
                input.replace(
                    region: MTLRegion(origin: MTLOrigin(),
                                      size: MTLSize(width: 512, height: 512, depth: 1)),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: 512 * 4 * MemoryLayout<Float>.stride)
            }
            let output = try texture(metal, width: 512, height: 512, write: true)
            let c1 = try texture(metal, width: payloads.corrWidth,
                                 height: payloads.corrHeight, write: true)
            let c2 = try texture(metal, width: payloads.corrWidth,
                                 height: payloads.corrHeight, write: true)
            let c3 = try texture(metal, width: payloads.corrWidth,
                                 height: payloads.corrHeight, write: true)
            _ = try await runChain(metal, payloads: payloads, input: input,
                                   output: output, corrA: c1, corrBlur1: c2, corrBlur2: c3)
            outputs.append(readback(output))
        }
        // the convergence ladder: every arm vs the FULL-RES corr face
        // (ds = 1 — the probe-only对照臂, H-M2 forbids it in production)
        func maxAbsDiff(_ x: [Float], _ y: [Float]) -> Double {
            var m = 0.0
            for (a, b) in zip(x, y) { m = max(m, abs(Double(a) - Double(b))) }
            return m
        }
        let full = outputs[0]
        for (idx, ds) in [1, 2, 4, 8].enumerated() {
            let d = maxAbsDiff(full, outputs[idx])
            if ds == 4 { fidelity = d }
            print("PERF-PROBE|spectral-corr|fidelity|ds=\(ds)VsFull|maxAbs=\(d)")
        }
        print("PERF-PROBE|spectral-corr|fidelity|ds4VsDs8|maxAbs=\(maxAbsDiff(outputs[2], outputs[3]))")

        // the footprint face at 100MP: allocate the chain faces per
        // decimation and sample the phys_footprint peak
        let input = try texture(metal, width: width, height: height, write: false)
        let output = try texture(metal, width: width, height: height, write: true)
        var peaks: [Int: Int64] = [:]
        for decimation in [4, 8] {
            let payloads = try makePayloads(metal, width: width, height: height,
                                            decimation: decimation)
            let cw = payloads.corrWidth, ch = payloads.corrHeight
            let corrA = try texture(metal, width: cw, height: ch, write: true)
            let b1 = try texture(metal, width: cw, height: ch, write: true)
            let b2 = try texture(metal, width: cw, height: ch, write: true)
            await fence(metal)
            let peak = physFootprint()
            peaks[decimation] = peak
            let planeMB = cw * ch * 16 / 1_048_576
            print("PERF-PROBE|spectral-corr|footprint|ds=\(decimation)|" +
                "corrPlane=\(planeMB)MB|physFootprintMB=\(peak / 1_048_576)")
            _ = try await runChain(metal, payloads: payloads, input: input,
                                   output: output, corrA: corrA, corrBlur1: b1,
                                   corrBlur2: b2)
        }
        print("PERF-PROBE|spectral-corr|verdict|ds4=\(peaks[4]! / 1_048_576)MB|" +
            "ds8=\(peaks[8]! / 1_048_576)MB|fidelityMaxAbs=\(fidelity)|gate=8192MB")
    }

    // MARK: - probe ④: the ramp sentinel + the legacy baseline pin

    func testProbe4RampSentinelAndLegacyBaseline() async throws {
        try probeEnabled()
        let metal = try MetalContext()
        let width = 512, height = 512
        let payloads = try makePayloads(metal, width: width, height: height,
                                        decimation: 4)
        let input = try texture(metal, width: width, height: height, write: false)
        var px = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                px[i + 0] = 0.12 + 0.6 * Float(x) / Float(width - 1)
                px[i + 1] = 0.18 + 0.4 * Float(y) / Float(height - 1)
                px[i + 2] = 0.25
                px[i + 3] = 1.0
            }
        }
        px.withUnsafeBytes {
            input.replace(
                region: MTLRegion(origin: MTLOrigin(),
                                  size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: width * 4 * MemoryLayout<Float>.stride)
        }
        let output = try texture(metal, width: width, height: height, write: true)
        let c1 = try texture(metal, width: payloads.corrWidth,
                             height: payloads.corrHeight, write: true)
        let c2 = try texture(metal, width: payloads.corrWidth,
                             height: payloads.corrHeight, write: true)
        let c3 = try texture(metal, width: payloads.corrWidth,
                             height: payloads.corrHeight, write: true)
        _ = try await runChain(metal, payloads: payloads, input: input,
                               output: output, corrA: c1, corrBlur1: c2, corrBlur2: c3)
        let out = readback(output)
        let sentinel = out.withUnsafeBytes {
            StableHash.combine(StableHash.fnvOffsetBasis, $0)
        }
        print("PERF-PROBE|spectral-sentinel|ramp512|\(sentinel)|" +
            "(the spectral arm's ramp plane hash — M8-2 registers it beside the " +
            "legacy 14_365_179_805_968_017_957, which stays untouched)")

        // the legacy sentinel constant, re-read from the deterministic
        // golden's source (the pin face — the density kernel's own
        // FilmDeterminismTests keeps gating it; this records the value the
        // spectral arm must NOT disturb)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Tests/LightamerTests/FilmDeterminismTests.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("14_365_179_805_968_017_957"),
                      "the legacy ramp sentinel must stay pinned unchanged")
    }

    // MARK: - probe ⑤: the nail divergence assembly

    func testProbe5NailDivergenceAssembly() throws {
        try probeEnabled()
        let metal = try MetalContext()
        let payloads = try makePayloads(metal, width: 48, height: 32, decimation: 4)
        let consts = bufferFloats(payloads.constBlockBuffer)
        let mIn = Array(consts[SpectralGPUPayloads.ConstBlockOffset.mIn
            ..< SpectralGPUPayloads.ConstBlockOffset.mIn + 9])

        // nail ①: bare two-rounding vs the pinned fma over the ramp plane
        var differingRows = 0, totalRows = 0
        var worst: Float = 0
        for i in 0..<(48 * 32) {
            let f = Float(i) / Float(48 * 32)
            let rgb = [0.15 + 0.6 * f, 0.15 + 0.4 * f, 0.15 + 0.2 * f]
            for r in 0..<3 {
                let bare = mIn[r * 3] * rgb[0] + mIn[r * 3 + 1] * rgb[1]
                    + mIn[r * 3 + 2] * rgb[2]
                let pinned = fmaf(mIn[r * 3], rgb[0],
                    fmaf(mIn[r * 3 + 1], rgb[1], mIn[r * 3 + 2] * rgb[2]))
                totalRows += 1
                if bare.bitPattern != pinned.bitPattern {
                    differingRows += 1
                    worst = max(worst, abs(bare - pinned))
                }
            }
        }
        print("PERF-PROBE|nail-assembly|fma|bareVsPinned=\(differingRows)/\(totalRows)|" +
            "worstAbs=\(worst)")

        // nail ②: the reciprocal family (the stored host-double-once face
        // vs the float re-derivation across a synthetic sweep)
        var reciprocalDiffs = 0, sweep = 0
        while sweep < 2_000 {
            let lo = 0.1 + 0.01 * Float(sweep)
            let hi = 16.0 + 0.05 * Float(sweep)
            if Float(1.0 / (Double(hi) - Double(lo))).bitPattern
                != (Float(1.0) / (hi - lo)).bitPattern {
                reciprocalDiffs += 1
            }
            sweep += 1
        }
        print("PERF-PROBE|nail-assembly|reciprocal|differingSweeps=\(reciprocalDiffs)/2000|" +
            "(the stored-reciprocal discipline's payoff face)")

        // nail ③: the shared polynomial through the device — the T3 battery
        // records the identity; here the HOST-side accuracy anchor prints
        var worstPoly = 0.0
        for k in 0..<64 {
            let x = Float(pow(10.0, -5.0 + 5.0 * Double(k) / 63.0))
            let got = SpectralLogMath.log10f(x)
            let want = Float(log10(Double(x)))
            worstPoly = max(worstPoly, abs(Double(got) - Double(want)))
        }
        print("PERF-PROBE|nail-assembly|polynomial|hostVsLibmMaxAbs=\(worstPoly)|" +
            "(device identity = the T3 bit-exact record)")
    }

    private func bufferFloats(_ buffer: any MTLBuffer) -> [Float] {
        let count = buffer.length / MemoryLayout<Float>.stride
        return Array(
            UnsafeBufferPointer(
                start: buffer.contents().assumingMemoryBound(to: Float.self),
                count: count))
    }
}
