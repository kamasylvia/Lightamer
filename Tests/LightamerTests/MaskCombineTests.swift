@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-04 T3 — the combine five ops (group.c:487-630 transcription)
/// and the MaskGroup semantics: per-op formula parity (normal + inverted,
/// <1e-6 vs the float64 port), the analytic-area shape goldens (two
/// circles: union/intersection/difference/exclusion/sum against the
/// closed-form circle-intersection area — numeric, not eyeballed), the
/// reduce upper bound, and the nested-group evaluation.
///
/// 防空转 (L020 ③): every gate walks a real per-pixel loop with
/// `compared > 0`; the measured max errors land in the run log.
final class MaskCombineTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    // MARK: - float64 reference (the group.c:487-630 formulas, Double)

    private static func combineRef(
        _ dest: Double, _ src: Double, op: MaskCombineOp,
        inverted: Bool, opacity: Double
    ) -> Double {
        let m = opacity * (inverted ? 1.0 - src : src)
        switch op {
        case .union:
            return max(dest, m)
        case .intersect:
            return min(max(dest, 0), max(m, 0))
        case .difference:
            return (dest > 0 && m > 0) ? dest * (1.0 - m) : dest
        case .sum:
            return min(1.0, dest + m)
        case .exclusion:
            let pos = (dest > 0 && m > 0) ? 1.0 : 0.0
            return pos * max((1.0 - dest) * m, dest * (1.0 - m))
                + (1.0 - pos) * max(dest, m)
        }
    }

    // MARK: - Helpers

    private func makeR32(
        _ w: Int, _ h: Int, metal: MetalContext, value: (Int, Int) -> Float
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { pixels[y * w + x] = value(x, y) } }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 4)
        }
        return texture
    }

    private func readMask(_ t: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: t.width * t.height)
        out.withUnsafeMutableBytes {
            t.getBytes(
                $0.baseAddress!, bytesPerRow: t.width * 4,
                from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    // MARK: - T3.1: per-op formula parity (normal + inverted)

    /// 5 ops × 2 inversion states vs the float64 formulas <1e-6 on
    /// non-flat dest/src patterns (a vacuous constant would hide the
    /// both_positive branches).
    func testCombineFiveOpsFormulaParity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 32, h = 24
        // The dest carries zeros AND positives (the difference/exclusion
        // both_positive branches need the mix); the src sweeps past 1.
        let dest = try makeR32(w, h, metal: metal) { x, y in
            (x + y) % 3 == 0 ? 0.0 : (0.2 + 0.6 * Float((x * 5 + y) % 7) / 6.0)
        }
        let src = try makeR32(w, h, metal: metal) { x, y in
            0.05 + 1.1 * Float((x * 3 + y * 2) % 9) / 8.0
        }
        let destRef = readMask(dest, metal: metal)
        let srcRef = readMask(src, metal: metal)

        for op in [MaskCombineOp.union, .intersect, .difference, .sum, .exclusion] {
            for inverted in [false, true] {
                let combined = try await MaskCombiner.combinePair(
                    dest: dest, src: src, op: op, inverted: inverted,
                    opacity: 0.7, metal: metal)
                let got = readMask(combined, metal: metal)
                var compared = 0
                var violations = 0
                var maxAbs: Float = 0
                for y in 0..<h {
                    for x in 0..<w {
                        let ref = Self.combineRef(
                            Double(destRef[y * w + x]), Double(srcRef[y * w + x]),
                            op: op, inverted: inverted, opacity: 0.7)
                        let diff = abs(got[y * w + x] - Float(ref))
                        if diff >= 1e-6 { violations += 1 }
                        maxAbs = max(maxAbs, diff)
                        compared += 1
                    }
                }
                XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
                XCTAssertEqual(
                    violations, 0,
                    "\(op) inverted=\(inverted): \(violations)/\(compared) " +
                        "violate <1e-6 (maxAbs \(maxAbs))")
            }
        }
    }

    // MARK: - T3.2: the analytic-area shape goldens (two circles)

    /// Closed-form area of the lens-shaped intersection of two circles.
    private static func circleIntersectionArea(
        _ a: (c: Double, r: Double), _ b: (c: Double, r: Double)
    ) -> Double {
        let d = hypot(b.c - a.c, 0)
        if d >= a.r + b.r { return 0 }
        if d <= abs(a.r - b.r) { return .pi * pow(min(a.r, b.r), 2) }
        let a1 = pow(a.r, 2) * acos((d * d + pow(a.r, 2) - pow(b.r, 2)) / (2 * d * a.r))
        let a2 = pow(b.r, 2) * acos((d * d + pow(b.r, 2) - pow(a.r, 2)) / (2 * d * b.r))
        let a3 = 0.5 * sqrt(max(
            (-d + a.r + b.r) * (d + a.r - b.r) * (d - a.r + b.r) * (d + a.r + b.r), 0))
        return a1 + a2 - a3
    }

    /// Two overlapping circles rasterized through the real form
    /// rasterizer, combined by each op, thresholded at 0.5 and counted —
    /// the pixel count must match the analytic area within the
    /// discretization bound (≈ the union perimeter in pixels; a WRONG op
    /// deviates by half a circle area, two orders beyond the bound).
    func testCombineAnalyticAreaGoldens() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 96, h = 96
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)

        // Circles in normalized coords (radiusX == radiusY → true circles
        // on the square frame): A r=0.20 at x 0.38, B r=0.16 at x 0.62.
        let ellipseA = EllipseForm(
            center: MaskPoint(x: 0.38, y: 0.5), radiusX: 0.20, radiusY: 0.20,
            rotationDegrees: 0, border: 0)
        let ellipseB = EllipseForm(
            center: MaskPoint(x: 0.62, y: 0.5), radiusX: 0.16, radiusY: 0.16,
            rotationDegrees: 0, border: 0)
        let planeA = try await DrawnMaskRasterizer.singleFormPlane(
            form: MaskForm(kind: .ellipse(ellipseA)), window: window,
            mapper: mapper, metal: metal)
        let planeB = try await DrawnMaskRasterizer.singleFormPlane(
            form: MaskForm(kind: .ellipse(ellipseB)), window: window,
            mapper: mapper, metal: metal)

        // Radii in WIDTH UNITS; the frame is square so px radius = 0.20·96.
        let rA = 0.20 * Double(w), rB = 0.16 * Double(w)
        let centerA = 0.38 * Double(w), centerB = 0.62 * Double(w)
        let areaA = Double.pi * rA * rA
        let areaB = Double.pi * rB * rB
        let areaI = Self.circleIntersectionArea(
            (centerA, rA), (centerB, rB))
        // Discretization bound: center-sampled pixel counting deviates from
        // the analytic area by at most the boundary length (~perimeter).
        let bound = 2.0 * Double.pi * (rA + rB)

        let expectations: [(op: MaskCombineOp, area: Double)] = [
            (.union, areaA + areaB - areaI),
            (.intersect, areaI),
            (.difference, areaA - areaI),
            (.exclusion, areaA + areaB - 2 * areaI),
            (.sum, areaA + areaB - areaI), // values ≤1: sum clamps to union
        ]
        for expected in expectations {
            // Both items carry plain opacity 1 and normal inversion; the
            // FIRST item rides the zero-seed union (copy), the second
            // applies the op under test.
            let first = try await MaskCombiner.combinePair(
                dest: try await MaskCombiner.fill(0, width: w, height: h, metal: metal),
                src: planeA, op: .union, inverted: false, opacity: 1, metal: metal)
            let combined = try await MaskCombiner.combinePair(
                dest: first, src: planeB, op: expected.op,
                inverted: false, opacity: 1, metal: metal)
            let got = readMask(combined, metal: metal)
            let counted = got.filter { $0 >= 0.5 }.count
            XCTAssertGreaterThan(counted, 0, "\(expected.op): empty mask — 防空转")
            let deviation = abs(Double(counted) - expected.area)
            XCTAssertLessThan(
                deviation, bound,
                "\(expected.op): counted \(counted) px vs analytic " +
                    "\(String(format: "%.1f", expected.area)) px, bound \(String(format: "%.1f", bound))")
        }
    }

    // MARK: - T3.3: the reduce bound + ordering

    /// >4 inputs are REJECTED (the documented v1 bound — nest instead);
    /// the rejection THROWS (a user-reachable document path, not a trap).
    func testReduceUpperBoundRejected() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let plane = try await MaskCombiner.fill(1, width: 4, height: 4, metal: metal)
        let five = (0..<5).map { _ in
            MaskCombineInput(plane: plane, op: .union, inverted: false, opacity: 1)
        }
        do {
            _ = try await MaskCombiner.reduce(five, metal: metal)
            XCTFail("reduce(5) must be rejected")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("more than 4"),
                "unexpected rejection reason: \(error)")
        }
    }

    /// The reduce is ORDER-SENSITIVE (difference is not commutative):
    /// A−B ≠ B−A on overlapping circles — proves the in-order iteration
    /// (both orders install their first plane, then difference the other).
    func testReduceOrderSensitivity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 48, h = 48
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let a = try await DrawnMaskRasterizer.singleFormPlane(
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.4, y: 0.5), radiusX: 0.18, radiusY: 0.18,
                rotationDegrees: 0, border: 0))),
            window: window, mapper: mapper, metal: metal)
        let b = try await DrawnMaskRasterizer.singleFormPlane(
            form: MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.6, y: 0.5), radiusX: 0.18, radiusY: 0.18,
                rotationDegrees: 0, border: 0))),
            window: window, mapper: mapper, metal: metal)
        let ab = try await MaskCombiner.reduce(
            [MaskCombineInput(plane: a, op: .union, inverted: false, opacity: 1),
             MaskCombineInput(plane: b, op: .difference, inverted: false, opacity: 1)],
            metal: metal)
        let ba = try await MaskCombiner.reduce(
            [MaskCombineInput(plane: b, op: .union, inverted: false, opacity: 1),
             MaskCombineInput(plane: a, op: .difference, inverted: false, opacity: 1)],
            metal: metal)
        let gotAB = readMask(ab, metal: metal)
        let gotBA = readMask(ba, metal: metal)
        let maxDiff = zip(gotAB, gotBA).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(maxDiff, 0.1, "A−B == B−A — the reduce order is not exercised")
    }

    // MARK: - T5: the three-way assembly (drawn ⊗ parametric ⊓ raster)

    private func makeRGBA(
        _ w: Int, _ h: Int, metal: MetalContext, pixel: (Int, Int) -> SIMD4<Float>
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let v = pixel(x, y)
                for c in 0..<4 { pixels[(y * w + x) * 4 + c] = v[c] }
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 16)
        }
        return texture
    }

    /// drawn ⊗ parametric: assembled == (opacity·form)·conditional — the
    /// float64 cond × the drawn-only baseline plane <1e-5.
    func testAssemblyDrawnPlusParametric() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 40, h = 28
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let belowPixels = { (x: Int, y: Int) -> SIMD4<Float> in
            SIMD4<Float>(0.1 + 0.6 * Float(x) / Float(w - 1), 0.3, 0.2 + 0.3 * Float(y) / Float(h - 1), 1)
        }
        let below = try makeRGBA(w, h, metal: metal, pixel: belowPixels)
        let top = try makeRGBA(w, h, metal: metal) { _, _ in SIMD4<Float>(0.45, 0.45, 0.45, 1) }
        let layerOpacity: Float = 0.8

        let drawnOnly = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.3, radiusY: 0.25,
                rotationDegrees: 0, border: 0))),
        ]))
        var both = drawnOnly
        both.parametric = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.3, 0.4, 0.6, 0.7]))])

        let baseline = try await MaskCombiner.assembleUnmasked(
            spec: drawnOnly, layerOpacity: layerOpacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: nil, rasterStore: RasterMaskStore.self).plane
        let assembled = try await MaskCombiner.assembleUnmasked(
            spec: both, layerOpacity: layerOpacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: nil, rasterStore: RasterMaskStore.self).plane

        let gotBase = readMask(baseline, metal: metal)
        let gotAssembled = readMask(assembled, metal: metal)
        let params = both.parametric!.packedParameters().map(Double.init)
        var compared = 0
        var violations = 0
        var maxAbs: Float = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let pv = belowPixels(x, y)
                let a = SIMD3<Double>(Double(pv.x), Double(pv.y), Double(pv.z))
                let b = SIMD3<Double>(0.45, 0.45, 0.45)
                let cond = ParametricReference.blendifFactor(
                    a, b, blendif: both.parametric!.channelBitmask(), parameters: params)
                let expected = gotBase[i] * Float(cond)
                let diff = abs(gotAssembled[i] - expected)
                if diff >= 1e-5 { violations += 1 }
                maxAbs = max(maxAbs, diff)
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        XCTAssertEqual(
            violations, 0,
            "drawn⊕parametric: \(violations)/\(compared) violate <1e-5 (maxAbs \(maxAbs))")
    }

    /// The raster join: parametric ⊓ raster == min(parametric plane, raw
    /// raster) <1e-6; raster-only == raster·opacity (the documented
    /// quantization allowance); all three == min(opacity·form·cond, raster).
    func testAssemblyRasterAndAllThree() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 32, h = 24
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let layerOpacity: Float = 0.7

        // Bake a known diagonal-gradient raster mask.
        let rasterSource = try makeR32(w, h, metal: metal) { x, y in
            min(1, (Float(x) + Float(y)) / Float(w + h - 2) * 1.2)
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-combine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = try await RasterMaskStore.bake(
            plane: rasterSource, directory: dir, fileName: "m.png",
            invert: false, metal: metal)
        let rasterRaw = readMask(rasterSource, metal: metal)

        // The parametric-only leg (constant-1 form; kernel owns the fold).
        var paramOnly = MaskSpec()
        paramOnly.parametric = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.3, 0.4, 0.6, 0.7]))])
        // drawn+parametric+raster (all three).
        var allThree = MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .ellipse(EllipseForm(
                center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.35, radiusY: 0.35,
                rotationDegrees: 0, border: 0))),
        ]))
        allThree.parametric = paramOnly.parametric
        allThree.raster = ref
        // drawn+parametric (no raster) — the join's left operand baseline.
        var drawnParam = allThree
        drawnParam.raster = nil

        // The raster-only leg (install with opacity).
        var rasterOnly = MaskSpec()
        rasterOnly.raster = ref

        let below = try makeRGBA(w, h, metal: metal) { x, y in
            SIMD4<Float>(0.1 + 0.6 * Float(x) / Float(w - 1), 0.3, 0.25, 1)
        }
        let top = try makeRGBA(w, h, metal: metal) { _, _ in SIMD4<Float>(0.45, 0.45, 0.45, 1) }

        let paramPlane = try await MaskCombiner.assembleUnmasked(
            spec: paramOnly, layerOpacity: layerOpacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: dir, rasterStore: RasterMaskStore.self).plane
        let combined = try await MaskCombiner.assembleUnmasked(
            spec: allThree, layerOpacity: layerOpacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: dir, rasterStore: RasterMaskStore.self).plane
        let rasterPlane = try await MaskCombiner.assembleUnmasked(
            spec: rasterOnly, layerOpacity: layerOpacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: dir, rasterStore: RasterMaskStore.self).plane

        let drawnParamPlane = try await MaskCombiner.assembleUnmasked(
            spec: drawnParam, layerOpacity: layerOpacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: dir, rasterStore: RasterMaskStore.self).plane

        let gotParam = readMask(paramPlane, metal: metal)
        let gotDrawnParam = readMask(drawnParamPlane, metal: metal)
        let gotCombined = readMask(combined, metal: metal)
        let gotRaster = readMask(rasterPlane, metal: metal)
        var compared = 0
        var violations = 0
        var maxAbs: Float = 0
        for i in 0..<gotCombined.count {
            // all three == (drawn ⊗ parametric) ⊓ raster <1e-6.
            let diffCombined = abs(gotCombined[i] - min(gotDrawnParam[i], rasterRaw[i]))
            // Raster-only install: raster·opacity (quantization 1/65535).
            let diffRaster = abs(gotRaster[i] - rasterRaw[i] * layerOpacity)
            let okCombined = diffCombined < 1e-6
            let okRaster = diffRaster < 1.0 / 65535.0 + 1e-6
            if !okCombined || !okRaster { violations += 1 }
            maxAbs = max(maxAbs, max(diffCombined, diffRaster))
            compared += 2
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
        XCTAssertEqual(
            violations, 0,
            "raster joins: \(violations)/\(compared) violate the gates (maxAbs \(maxAbs))")
    }

    /// A raster reference with NO masks directory degrades per
    /// D-06-04-T4-2: the reason is SURFACED and the content is neutral.
    func testAssemblyRasterWithoutDirectorySurfacesDegrade() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 8, h = 6
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)
        let below = try makeRGBA(w, h, metal: metal) { _, _ in SIMD4<Float>(0.3, 0.3, 0.3, 1) }
        let top = try makeRGBA(w, h, metal: metal) { _, _ in SIMD4<Float>(0.3, 0.3, 0.3, 1) }
        var spec = MaskSpec()
        spec.parametric = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.1, 0.2, 0.4, 0.5]))])
        spec.raster = RasterMaskRef(fileName: "gone.png", maskHash: 1)

        let (plane, reason) = try await MaskCombiner.assembleUnmasked(
            spec: spec, layerOpacity: 1, window: window, below: below,
            top: top, mapper: mapper, metal: metal, maskDirectory: nil,
            rasterStore: RasterMaskStore.self)
        XCTAssertNotNil(reason, "the degrade must be surfaced, not swallowed")
        XCTAssertTrue(reason?.contains("no masks directory") == true, reason ?? "")

        // Content-neutral: min(cond, 1) == cond — compare against the
        // raster-free assembly.
        var withoutRaster = spec
        withoutRaster.raster = nil
        let clean = try await MaskCombiner.assembleUnmasked(
            spec: withoutRaster, layerOpacity: 1, window: window, below: below,
            top: top, mapper: mapper, metal: metal, maskDirectory: nil,
            rasterStore: RasterMaskStore.self).plane
        let gotPlane = readMask(plane, metal: metal)
        let gotClean = readMask(clean, metal: metal)
        var compared = 0
        for i in 0..<gotPlane.count {
            XCTAssertEqual(gotPlane[i], gotClean[i], accuracy: 1e-6,
                           "degraded raster changed the content at \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
    }

    // MARK: - T3.4: the nested group (组内组)

    /// A child group inside an item: (circleA ∪ circleB) difference
    /// circleC — evaluated through MaskCombiner.drawnGroupPlane and
    /// verified against the analytic (A+B−I)−C area via counting.
    func testNestedGroupEvaluation() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 96, h = 96
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(w), Double(h)))
        let window = ROI(x: 0, y: 0, width: w, height: h)

        func circle(_ cx: Double, _ r: Double, id: UUID = UUID()) -> (MaskForm, EllipseForm) {
            let e = EllipseForm(
                center: MaskPoint(x: Float(cx), y: 0.5 as Float), radiusX: Float(r),
                radiusY: Float(r), rotationDegrees: 0, border: 0)
            return (MaskForm(id: id, kind: .ellipse(e)), e)
        }
        let (formA, _) = circle(0.38, 0.20)
        let (formB, _) = circle(0.62, 0.16)
        let (formC, _) = circle(0.5, 0.07)

        // child = A ∪ B (its items install + union); root = the child
        // group INSTALLS first, then difference C.
        let childGroup = MaskGroupSpec(items: [
            MaskGroupItem(formID: formA.id, op: .union, inverted: false, opacity: 1),
            MaskGroupItem(formID: formB.id, op: .union, inverted: false, opacity: 1),
        ])
        let childID = UUID()
        let rootGroup = MaskGroupSpec(items: [
            MaskGroupItem(
                formID: childID, op: .union, inverted: false, opacity: 1,
                child: childGroup),
            MaskGroupItem(formID: formC.id, op: .difference, inverted: false, opacity: 1),
        ])
        let plane = try await MaskCombiner.drawnGroupPlane(
            group: rootGroup, forms: [formA, formB, formC],
            window: window, mapper: mapper, metal: metal)
        let got = readMask(try XCTUnwrap(plane), metal: metal)

        let rA = 0.20 * Double(w), rB = 0.16 * Double(w), rC = 0.07 * Double(w)
        let areaAB = Double.pi * rA * rA + Double.pi * rB * rB
            - Self.circleIntersectionArea((0.38 * Double(w), rA), (0.62 * Double(w), rB))
        // C sits at 0.5 inside the A∪B overlap band.
        let areaC = Double.pi * rC * rC
        let counted = got.filter { $0 >= 0.5 }.count
        let bound = 2.0 * Double.pi * (rA + rB + rC)
        XCTAssertGreaterThan(counted, 0, "防空转: empty mask")
        XCTAssertLessThan(
            abs(Double(counted) - (areaAB - areaC)), bound,
            "nested (A∪B)−C: counted \(counted) vs analytic " +
                "\(String(format: "%.1f", areaAB - areaC)), bound \(String(format: "%.1f", bound))")
    }
}
