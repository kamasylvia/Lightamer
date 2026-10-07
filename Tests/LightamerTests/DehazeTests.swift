@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// DehazeTests (Plan 08-5 T1, IOP-FX-04 — hazeremoval 14.0).
//
// GOLDEN AUTHORITY: `DehazeReference` — the CPU float64 twin of the whole
// chain (the ambient order statistics ARE the production routine; the
// box-approximation smoothing form is double-written per the frozen
// planner ruling). The kernel chain is compared against it tightly, and
// the synthetic-fog inversion closes the PHYSICS loop: known A0, known t
// field, linear composite I = J·t + A0·(1−t) → the dehazed Ĵ must come
// back to J within the pinned tolerance (D-08-5-T1-3).
//
// ANTI-VACUUM (L020): every comparison loop carries a compared>0 gate.
// L014: every GPU readback drains first. L031: the module dispatches only
// through makeEncoder / the routed blit.
// ─────────────────────────────────────────────────────────────────────────────

final class DehazeTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: DehazeKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) -> (any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return metal.device.makeTexture(descriptor: descriptor)!
    }

    private func fill(_ texture: any MTLTexture, _ pixels: [Float]) {
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0, withBytes: $0.baseAddress!,
                bytesPerRow: texture.width * 16)
        }
    }

    private func read(_ texture: any MTLTexture) -> [Float] {
        var pixels = [Float](
            repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0)
        }
        return pixels
    }

    @discardableResult
    private func runDehaze(
        _ module: DehazeModule, _ params: DehazeModule.Params,
        input: (any MTLTexture), metal: MetalContext
    ) async throws -> [Float] {
        let width = input.width, height = input.height
        let output = makeTexture(metal, width: width, height: height)
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: width, height: height)
        piece.dscOut = piece.dscIn
        piece.iscale = 1.0
        piece.pipeType = .preview
        module.commitParams(params, into: &piece)
        let roi = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        try await module.process(
            input: input, output: output, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal) // L014 before the CPU readback
        return read(output)
    }

    /// The synthetic-fog scene builder: the KNOWN scene J (0.15 base + a
    /// near-black dot lattice — the dark-channel prior's premise — + a
    /// bright square in the CLEAR zone) composited with the KNOWN t
    /// gradient and A0: I = J·t + A0·(1−t). The gradient's haziest edge
    /// runs to t ≈ 0 so the ambient order statistics see (near-)pure
    /// airlight — the prior's A0 candidate premise.
    private func fogFixture(
        width: Int, height: Int, a0: SIMD3<Float>, tLow: Float, tHigh: Float,
        squareValue: Float
    ) -> (hazed: [Float], scene: [Float], transmission: [Float]) {
        var hazed = [Float](repeating: 0, count: width * height * 4)
        var scene = [Float](repeating: 0, count: width * height * 4)
        var transmission = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                // J: the base + the dot lattice (the local-black premise
                // every w1 window must see) + the bright square near the
                // haziest edge (the ambient-light candidate region).
                var j = Float(0.15)
                if (x % 8 == 4) && (y % 8 == 4) { j = 0.01 }
                if x >= width * 3 / 4 && x < width * 3 / 4 + 12
                    && y >= height / 4 && y < height / 4 + 12 {
                    j = squareValue
                }
                // t: the horizontal gradient, SMALL t = the haziest edge.
                let t = tLow + (tHigh - tLow) * Float(x) / Float(max(width - 1, 1))
                transmission[y * width + x] = t
                scene[index] = j
                scene[index + 1] = j
                scene[index + 2] = j
                scene[index + 3] = 1
                hazed[index] = j * t + a0.x * (1 - t)
                hazed[index + 1] = j * t + a0.y * (1 - t)
                hazed[index + 2] = j * t + a0.z * (1 - t)
                hazed[index + 3] = 1
            }
        }
        return (hazed, scene, transmission)
    }

    // MARK: - The synthetic-fog inversion golden (research §10.4)

    func testSyntheticFogInversionGolden() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 72
        let scenarios: [(
            name: String, a0: SIMD3<Float>, tLow: Float, tHigh: Float, square: Float
        )] = [
            ("base", SIMD3(0.7, 0.75, 0.8), 0.005, 0.92, 0.5),
            ("brightA0", SIMD3(0.85, 0.88, 0.9), 0.004, 0.95, 0.45),
            ("deepHaze", SIMD3(0.6, 0.68, 0.72), 0.006, 0.9, 0.55),
        ]
        // The pinned inversion tolerance (D-08-5-T1-3): the envelope of
        // (a) the A0 order-statistic estimate's offset from the true
        // ambient, (b) the box-approximation smoothing of the transition
        // map, and (c) the dot-lattice's ≤1.5% t̂ bias.
        let inversionTolerance: Float = 0.15
        let windows = DehazeReference.windowSizes(adaptive: true, roiScale: 1.0, iscale: 1.0)
        for scenario in scenarios {
            let fixture = fogFixture(
                width: width, height: height, a0: scenario.a0,
                tLow: scenario.tLow, tHigh: scenario.tHigh,
                squareValue: scenario.square)
            let input = makeTexture(metal, width: width, height: height)
            fill(input, fixture.hazed)
            let module = DehazeModule()
            let output = try await runDehaze(
                module,
                DehazeModule.Params(strength: 1.0, distance: 1.0, adaptive: true),
                input: input, metal: metal)

            // The reference's own depth floor (the module computes its
            // ambient from the SAME routine + plane): pixels below t_min
            // are deliberately NOT restored fully (dt semantics).
            let doubles = fixture.hazed.map { Double($0) }
            let ambient = DehazeReference.ambientLight(
                doubles, planeW: width, planeH: height, w1: windows.w1)
            let tMin = Float(min(max(
                Foundation.exp(-1.0 * ambient.distanceMax), 1.0 / 1024.0), 1.0))

            var compared = 0
            var maxError: Float = 0
            var worst = (x: 0, y: 0)
            for y in 2..<(height - 2) {
                for x in 2..<(width - 2) {
                    let index = (y * width + x) * 4
                    let t = fixture.transmission[y * width + x]
                    // The restoration is depth-limited by t_min (dt
                    // semantics): only the band above the reference's own
                    // t_min floor owes a full recovery.
                    guard t >= tMin else { continue }
                    for channel in 0..<3 {
                        let error = abs(output[index + channel] - fixture.scene[index + channel])
                        if error > maxError {
                            maxError = error
                            worst = (x, y)
                        }
                        compared += 1
                    }
                }
            }
            XCTAssertGreaterThan(compared, 0, "the inversion band was empty")
            XCTAssertLessThanOrEqual(
                maxError, inversionTolerance,
                "\(scenario.name): fog inversion |Ĵ−J| = \(maxError) at \(worst)")
        }
    }

    // MARK: - The float64 parity (kernel vs the box-form reference)

    func testFloat64ChainParity() async throws {
        let metal = try await makeMetal()
        let width = 96, height = 72
        let fixture = fogFixture(
            width: width, height: height, a0: SIMD3(0.7, 0.75, 0.8),
            tLow: 0.005, tHigh: 0.92, squareValue: 0.5)
        let input = makeTexture(metal, width: width, height: height)
        fill(input, fixture.hazed)
        let params = DehazeModule.Params(strength: 0.8, distance: 0.5, adaptive: true)
        let module = DehazeModule()
        let output = try await runDehaze(module, params, input: input, metal: metal)

        // The reference consumes the SAME ambient routine + chain form.
        let windows = DehazeReference.windowSizes(adaptive: true, roiScale: 1.0, iscale: 1.0)
        let doubles = fixture.hazed.map { Double($0) }
        let ambient = DehazeReference.ambientLight(
            doubles, planeW: width, planeH: height, w1: windows.w1)
        let moduleAmbient = try XCTUnwrap(module.lastAmbientForTesting)
        print(
            "DEHAZE-PARITY-PROBE: module A0=\(moduleAmbient.a0) dmax=\(moduleAmbient.distanceMax)"
                + " ref A0=\(ambient.a0) dmax=\(ambient.distanceMax)")
        let reference = DehazeReference.fullChain(
            doubles, width: width, height: height,
            strength: Double(params.strength), distance: Double(params.distance),
            ambient: ambient, w1: windows.w1, w2: windows.w2)
        let center = (36 * width + 48) * 4
        print(
            "DEHAZE-PARITY-PROBE: center got=\(output[center]) ref=\(Float(reference[center]))"
                + " input=\(fixture.hazed[center])")
        // Stage-by-stage probe at the worst pixel's row (the box chains'
        // intermediates, kernel vs the reference stages).
        await drain(metal)
        if let tmap = module.transitionTextureForTesting,
           let sA = module.scratchAForTesting,
           let sB = module.scratchBForTesting {
            func probe(_ tex: any MTLTexture, _ x: Int, _ y: Int) -> Float {
                var row = [Float](repeating: 0, count: tex.width)
                row.withUnsafeMutableBytes {
                    tex.getBytes(
                        $0.baseAddress!, bytesPerRow: tex.width * 4,
                        from: MTLRegionMake2D(0, y, tex.width, 1), mipmapLevel: 0)
                }
                return row[x]
            }
            let (px, py) = (68, 20)
            // The reference stages at (px, py):
            var tRef = [Double](repeating: 0, count: width * height)
            for i in 0..<(width * height) {
                let r = doubles[i * 4] / ambient.a0.x
                let g = doubles[i * 4 + 1] / ambient.a0.y
                let b = doubles[i * 4 + 2] / ambient.a0.z
                tRef[i] = 1.0 - min(r, min(g, b)) * Double(params.strength)
            }
            let idx = py * width + px
            let t0 = tRef[idx]
            tRef = DehazeReference.boxMax(tRef, width: width, height: height, w: windows.w1, horizontal: true)
            let t1 = tRef[idx]
            tRef = DehazeReference.boxMax(tRef, width: width, height: height, w: windows.w1, horizontal: false)
            let t2 = tRef[idx]
            tRef = DehazeReference.boxMin(tRef, width: width, height: height, w: windows.w1, horizontal: true)
            let t3 = tRef[idx]
            tRef = DehazeReference.boxMin(tRef, width: width, height: height, w: windows.w1, horizontal: false)
            let t4 = tRef[idx]
            tRef = DehazeReference.boxMean(tRef, width: width, height: height, w: windows.w2, horizontal: true)
            let t5 = tRef[idx]
            tRef = DehazeReference.boxMean(tRef, width: width, height: height, w: windows.w2, horizontal: false)
            print(
                "DEHAZE-STAGE-PROBE (\(px),\(py)): kernel tmap=\(probe(tmap, px, py)) "
                    + "sA=\(probe(sA, px, py)) sB=\(probe(sB, px, py)) | "
                    + "ref t0=\(Float(t0)) maxX=\(Float(t1)) maxY=\(Float(t2)) "
                    + "minX=\(Float(t3)) minY=\(Float(t4)) meanX=\(Float(t5)) meanY=\(Float(tRef[idx]))")
        }

        var compared = 0
        var maxRelative: Float = 0
        var maxAbs: Float = 0
        var worstIndex = 0
        for index in stride(from: 0, to: output.count, by: 4) {
            for channel in 0..<3 {
                let expected = Float(reference[index + channel])
                let got = output[index + channel]
                let relative = abs(got - expected) / max(abs(expected), 1e-3)
                if relative > maxRelative {
                    maxRelative = relative
                    worstIndex = index + channel
                }
                maxAbs = max(maxAbs, abs(got - expected))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
        print(
            "DEHAZE-PARITY-PROBE: worstRel=\(maxRelative) at [\(worstIndex)] "
                + "got=\(output[worstIndex]) ref=\(Float(reference[worstIndex])) "
                + "maxAbs=\(maxAbs)")
        // float32 chain (8 GPU stages) vs float64 reference; the box ops
        // are contractive, the restore divides by t ≥ t_min ≥ 1/1024.
        XCTAssertLessThanOrEqual(
            maxRelative, 2e-3, "kernel vs float64 reference rel-dev \(maxRelative)")
    }

    // MARK: - The neutral face (strength 0 = the routed-blit identity)

    func testNeutralStrengthZeroIsByteIdentity() async throws {
        let metal = try await makeMetal()
        let width = 48, height = 40
        let fixture = fogFixture(
            width: width, height: height, a0: SIMD3(0.7, 0.75, 0.8),
            tLow: 0.005, tHigh: 0.92, squareValue: 0.5)
        let input = makeTexture(metal, width: width, height: height)
        fill(input, fixture.hazed)
        let module = DehazeModule()
        let output = try await runDehaze(
            module, DehazeModule.Params(strength: 0, distance: 0.2, adaptive: true),
            input: input, metal: metal)
        let inBits = read(input)
        var compared = 0
        for (index, value) in inBits.enumerated() {
            XCTAssertEqual(
                output[index].bitPattern, value.bitPattern,
                "strength 0 must be the byte identity at \(index)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertTrue(module.isNeutral(DehazeModule.Params(strength: 0)))
        XCTAssertFalse(module.isNeutral(DehazeModule.Params(strength: 0.2)))
    }

    // MARK: - The window formula (hazeremoval.c:576-583 verbatim)

    func testWindowSizesVerbatim() {
        // w1 = 2 + ⌈4·wscale⌉, w2 = 3 + ⌈6·wscale⌉; adaptive ⇒ wscale =
        // roi.scale/iscale, else 1.
        let cases: [(adaptive: Bool, roi: Double, iso: Double, w1: Int, w2: Int)] = [
            (true, 1.0, 1.0, 6, 9),
            (true, 0.5, 1.0, 4, 6),
            (true, 0.25, 1.0, 3, 5),
            (true, 0.125, 1.0, 3, 4),
            (true, 1.0, 0.5, 6, 9), // wscale = 2 clipped to 1
            (false, 0.25, 1.0, 6, 9), // non-adaptive pins wscale 1
        ]
        for entry in cases {
            let windows = DehazeReference.windowSizes(
                adaptive: entry.adaptive, roiScale: entry.roi, iscale: entry.iso)
            XCTAssertEqual(
                windows.w1, entry.w1,
                "w1 for adaptive=\(entry.adaptive) roi=\(entry.roi) iso=\(entry.iso)")
            XCTAssertEqual(
                windows.w2, entry.w2,
                "w2 for adaptive=\(entry.adaptive) roi=\(entry.roi) iso=\(entry.iso)")
        }
    }

    // MARK: - The A0 reuse + hash invalidation (the dt gui_data sync-pit answer)

    func testAmbientReuseAndHashInvalidation() async throws {
        let metal = try await makeMetal()
        let width = 64, height = 48
        let first = fogFixture(
            width: width, height: height, a0: SIMD3(0.7, 0.75, 0.8),
            tLow: 0.005, tHigh: 0.92, squareValue: 0.5)
        let module = DehazeModule()
        let params = DehazeModule.Params(strength: 0.5, distance: 0.4, adaptive: true)

        // Run ① — the first computation.
        let inputA = makeTexture(metal, width: width, height: height)
        fill(inputA, first.hazed)
        _ = try await runDehaze(module, params, input: inputA, metal: metal)
        XCTAssertEqual(module.ambientComputations, 1, "run 1 computes once")

        // Run ② — the SAME input, OWN param change (the strength-slider
        // drag, dt's motivating reuse case): the content hash holds → the
        // cached ambient rides.
        _ = try await runDehaze(
            module, DehazeModule.Params(strength: 0.9, distance: 0.4, adaptive: true),
            input: inputA, metal: metal)
        XCTAssertEqual(
            module.ambientComputations, 1,
            "an own-param change must NOT recompute the ambient statistics")

        // Run ③ — CHANGED content (a different haze): the hash invalidates
        // → recompute.
        let second = fogFixture(
            width: width, height: height, a0: SIMD3(0.85, 0.88, 0.9),
            tLow: 0.004, tHigh: 0.95, squareValue: 0.45)
        let inputB = makeTexture(metal, width: width, height: height)
        fill(inputB, second.hazed)
        _ = try await runDehaze(module, params, input: inputB, metal: metal)
        XCTAssertEqual(
            module.ambientComputations, 2,
            "a changed input must invalidate the cached ambient statistics")
    }

    // MARK: - Registration + the CLAHE non-mixing assertion

    func testRegisteredAtV50Slot14AndCLAHEAbsent() async throws {
        XCTAssertEqual(DehazeModule.opName, "hazeremoval")
        XCTAssertEqual(DehazeModule.iopOrder, 14.0)
        XCTAssertEqual(V50Order.order(for: "hazeremoval"), 14.0)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let dehaze = await registry.makeBox(opName: "hazeremoval")
        XCTAssertNotNil(dehaze, "hazeremoval must be registered (14.0)")
        // The CLAHE non-mixing pin (D-08-CONTEXT-8 ②): the v50 table's
        // `clahe` 71.0 row is a legacy PLACEHOLDER — no module registers
        // under it, so the dehaze slot can never be confused with a
        // histogram-equalization path.
        let clahe = await registry.makeBox(opName: "clahe")
        XCTAssertNil(clahe, "clahe is a legacy v50 placeholder and must stay unregistered")
    }
}
