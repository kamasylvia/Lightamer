@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// LiquifyParityTests (Plan 06-06, IOP-GEO-05) — the liquify warp module.
///
/// REFERENCE PROVENANCE (L017 route ① — dt-cli cannot drive liquify, an
/// interactive module; 06-RESEARCH §9): the references are CPU-SYNTHESIZED
/// float64 transcriptions of dt's formulas, written INDEPENDENTLY in the
/// tests (the implementation under test shares only the dt source, never
/// code, with these references):
/// - T1: the collapsed per-cell stamp formulas (linear / radial grow /
///   radial shrink) vs a float64 grid reference, gate <1e-6 (plan);
/// - T2: the warp kernel vs a float64 field+lanczos3 resampler, gate <1e-5
///   (warp class, ashift precedent) + empty-path BYTE identity;
/// - T5: forced tiling == whole plane <1e-6; track B zero increment.
///
/// ANTI-VACUUM: every test runs a real comparison loop with `compared > 0`
/// guards (L020 ③). L014: every GPU readback drains first.
///
/// COORDINATE AUDIT (L020): the tests resolve paths against a NOMINAL frame
/// and recompute the stamp center/extent independently — a field-grid ↔
/// kernel-sampling domain mismatch would break the parity tests below.
final class LiquifyParityTests: XCTestCase {

    private static let frame = SIMD2<Double>(600, 400)

    // MARK: - shared reference pieces (float64, independent of the impl)

    /// Independent float64 cubic-bezier + x-reparameterized profile — the
    /// dt build_lookup_table boundary conditions (f(0)=1, f(d)=0, smooth
    /// ends) computed WITHOUT reusing LiquifyDistortionField code. The
    /// polyline samples dt's t = i/n positions (interpolate_cubic_bezier
    /// step 1/n, liquify.c:753-759) — same ALGORITHM, independent code.
    private func referenceLookup(distance: Int, c1: Double, c2: Double) -> [Double] {
        let n = distance + 2
        var pts = [SIMD2<Double>](repeating: .zero, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let mt = 1 - t
            pts[i] = SIMD2(
                3 * mt * mt * t * c1 + 3 * mt * t * t * c2 + t * t * t * 1,
                mt * mt * mt * 1 + 3 * mt * mt * t * 1 + 3 * mt * t * t * 0 + 0)
        }
        pts[n - 1] = SIMD2(1, 0)
        var out = [Double](repeating: 0, count: distance + 1)
        out[0] = 1.0
        var j = 1
        for i in 1..<distance {
            let x = Double(i) / Double(distance)
            while j < n - 1 && pts[j].x < x { j += 1 }
            let dx = pts[j].x - pts[j - 1].x
            let frac = dx > 0 ? (x - pts[j - 1].x) / dx : 0
            // dt liquify.c:858-861 verbatim — the formula anchors at the
            // RIGHT sample (y[j] + frac·(y[j] − y[j−1])), a dt quirk that
            // slightly over-extrapolates within each segment. Transcribed
            // as-is on both sides (fidelity rule, D-06-06-T1-6).
            out[i] = pts[j].y + frac * (pts[j].y - pts[j - 1].y)
        }
        out[distance] = 0.0
        return out
    }

    /// Reference stamp resolution for a LONE node (no interpolation):
    /// strength vector × 0.5, radius × max(frame).
    private func referenceStamp(_ d: LiquifyPathData) -> (
        center: SIMD2<Int>, iradius: Int, strength: SIMD2<Double>, type: LiquifyWarpType
    ) {
        let p = SIMD2<Double>(Double(d.point.x) * Self.frame.x, Double(d.point.y) * Self.frame.y)
        let s = SIMD2<Double>(
            Double(d.strength.x - d.point.x) * Self.frame.x,
            Double(d.strength.y - d.point.y) * Self.frame.y) * 0.5
        let rd = d.radius - d.point
        let r = Double((rd.x * rd.x + rd.y * rd.y).squareRoot()) * max(Self.frame.x, Self.frame.y)
        return (
            SIMD2(Int(p.x.rounded()), Int(p.y.rounded())), Int(r.rounded()), s, d.warpType
        )
    }

    /// The collapsed per-cell reference formula (see
    /// LiquifyDistortionField.deposit — derived from dt liquify.c:978-1013).
    private func referenceField(
        _ d: LiquifyPathData
    ) -> (origin: SIMD2<Int>, size: SIMD2<Int>, values: [SIMD2<Double>], compared: Int) {
        let (center, iradius, strength, type) = referenceStamp(d)
        let lookup = referenceLookup(
            distance: iradius * LiquifyPathData.lookupOversample, c1: Double(d.control1),
            c2: Double(d.control2))
        let side = 2 * iradius + 1
        let origin = SIMD2(center.x - iradius, center.y - iradius)
        var values = [SIMD2<Double>](
            repeating: .zero, count: side * side)
        var compared = 0
        let shrinkSign: Double = type == LiquifyWarpType.radialShrink ? -1 : 1
        for oy in 0..<side {
            for ox in 0..<side {
                let dx = ox - iradius, dy = oy - iradius
                let dist = (Double(dx * dx) + Double(dy * dy)).squareRoot()
                let idist = Int((dist * Double(LiquifyPathData.lookupOversample)).rounded())
                guard idist < iradius * LiquifyPathData.lookupOversample else { continue }
                let profile = lookup[idist]
                var vec: SIMD2<Double>
                if type == LiquifyWarpType.linear {
                    vec = -strength * profile
                } else {
                    let g = shrinkSign * (strength.x * strength.x + strength.y * strength.y).squareRoot() * profile / Double(iradius)
                    vec = SIMD2(-g * Double(dx), -g * Double(dy))
                }
                values[oy * side + ox] = vec
                compared += 1
            }
        }
        return (origin, SIMD2(side, side), values, compared)
    }

    private func assertFieldMatchesReference(
        _ data: LiquifyPathData, tolerance: Double = 1e-6,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let field = LiquifyDistortionField.build(
            paths: [data], frame: Self.frame,
            bounds: SIMD2(Int(Self.frame.x), Int(Self.frame.y)))
        let reference = referenceField(data)
        guard let field else {
            return XCTFail("field must build for a live stamp", file: file, line: line)
        }
        XCTAssertGreaterThan(reference.compared, 0, "防空转 guard", file: file, line: line)
        XCTAssertEqual(field.forward.origin, reference.origin, "extent origin", file: file, line: line)
        XCTAssertEqual(field.forward.width, reference.size.x, "extent width", file: file, line: line)
        XCTAssertEqual(field.forward.height, reference.size.y, "extent height", file: file, line: line)
        var maxErr = 0.0
        var compared = 0
        var worst = (i: 0, j: 0, gx: 0.0, gy: 0.0, rx: 0.0, ry: 0.0, dx: 0, dy: 0)
        for j in 0..<reference.size.y {
            for i in 0..<reference.size.x {
                let got = field.forward.vectors[j * field.forward.width + i]
                let ref = reference.values[j * reference.size.x + i]
                let ex = abs(Double(got.x) - ref.x), ey = abs(Double(got.y) - ref.y)
                if max(ex, ey) > maxErr {
                    maxErr = max(ex, ey)
                    worst = (i, j, Double(got.x), Double(got.y), ref.x, ref.y,
                             i - reference.size.x / 2, j - reference.size.y / 2)
                }
                compared += 1
            }
        }
        if maxErr >= tolerance {
            print("[06-06 DEBUG] worst cell grid(\(worst.i),\(worst.j)) offset(\(worst.dx),\(worst.dy)): "
                + "got (\(worst.gx),\(worst.gy)) ref (\(worst.rx),\(worst.ry))")
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard", file: file, line: line)
        XCTAssertLessThan(
            maxErr, tolerance,
            "field vs float64 reference \(maxErr) (gate \(tolerance), \(compared) cells)",
            file: file, line: line)
        print(
            "[06-06 T1] \(data.type) stamp: maxErr \(maxErr) over \(compared) cells (gate \(tolerance))"
        )
    }

    // MARK: - T1: three warp types vs the analytic reference (<1e-6)

    func testRadialGrowFieldAnalyticReference() {
        // Radial grow: anchor at frame center, radius 0.1 (=60 px), strength
        // handle 0.025 off the anchor (=15 px × 0.5 = 7.5 px gain).
        let data = LiquifyPathData(
            type: .moveTo, warpType: .radialGrow,
            point: SIMD2(0.5, 0.5),
            strength: SIMD2(0.525, 0.5),
            radius: SIMD2(0.6, 0.5))
        assertFieldMatchesReference(data)
    }

    func testRadialShrinkFieldAnalyticReference() {
        let data = LiquifyPathData(
            type: .moveTo, warpType: .radialShrink,
            point: SIMD2(0.4, 0.6),
            strength: SIMD2(0.425, 0.6),
            radius: SIMD2(0.5, 0.6))
        assertFieldMatchesReference(data)
    }

    func testLinearFieldAnalyticReference() {
        // Strength vector 0.025 × 600 × 0.5 = 7.5 px peak — kept under the
        // float32 storage ulp of the 1e-6 absolute gate (an 18.75 px peak
        // would round at ~1.9e-6; recorded in DECISIONS as the test's value
        // budget, not an implementation bound).
        let data = LiquifyPathData(
            type: .moveTo, warpType: .linear,
            point: SIMD2(0.5, 0.5),
            strength: SIMD2(0.525, 0.5),
            radius: SIMD2(0.6, 0.5))
        assertFieldMatchesReference(data)
    }

    /// Directional structure (independent of the profile table): radial grow
    /// points TOWARD the center (backward sampling ⇒ magnification), shrink
    /// points AWAY, linear is uniform. Center cell is zero for radial.
    func testWarpDirectionStructure() throws {
        let frame = SIMD2<Double>(600, 400)
        func probe(_ type: LiquifyWarpType) throws -> DisplacementField {
            let data = LiquifyPathData(
                type: .moveTo, warpType: type,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.55, 0.5),
                radius: SIMD2(0.6, 0.5))
            return try XCTUnwrap(LiquifyDistortionField.build(
                paths: [data], frame: frame, bounds: SIMD2(600, 400)))
        }
        for type in [LiquifyWarpType.radialGrow, LiquifyWarpType.radialShrink] {
            let field = try probe(type)
            // The stamp center in grid coords.
            let cx = 300 - field.forward.origin.x
            let cy = 200 - field.forward.origin.y
            let centerCell = field.forward.vectors[cy * field.forward.width + cx]
            XCTAssertEqual(centerCell.x, 0, accuracy: 1e-6, "\(type): center zero")
            XCTAssertEqual(centerCell.y, 0, accuracy: 1e-6, "\(type): center zero")
            // A cell right of the center: radial displacement must be
            // horizontal (cross product 0) and INWARD for grow.
            let probeCell = field.forward.vectors[cy * field.forward.width + cx + 10]
            XCTAssertLessThan(abs(probeCell.y), 1e-5, "\(type): radial direction")
            if type == LiquifyWarpType.radialGrow {
                XCTAssertLessThan(probeCell.x, 0, "grow points toward the center")
            } else {
                XCTAssertGreaterThan(probeCell.x, 0, "shrink points away from the center")
            }
        }
        let linear = try probe(.linear)
        let cx = 300 - linear.forward.origin.x
        let cy = 200 - linear.forward.origin.y
        // Linear pushes along the (purely horizontal here) strength vector.
        let left = linear.forward.vectors[cy * linear.forward.width + cx - 10]
        let right = linear.forward.vectors[cy * linear.forward.width + cx + 10]
        XCTAssertEqual(left.x, right.x, accuracy: 1e-6, "linear field is uniform")
        XCTAssertEqual(left.y, 0, accuracy: 1e-6)
        XCTAssertLessThan(left.x, 0, "linear opposes the strength vector")
    }

    // MARK: - T1: path interpolation (line/curve chains, 0.1 relocation)

    /// A MOVE→LINE chain interpolates stamps between the endpoints at
    /// |radius|·0.1 steps; every interpolated stamp deposits at 0.1×
    /// strength (dt STAMP_RELOCATION). Verified against the reference
    /// formula with the relocation factor folded in.
    func testLinePathInterpolationAndRelocation() throws {
        var move = LiquifyPathData.moveTo(SIMD2(0.25, 0.5))
        move.radius = SIMD2(0.35, 0.5)  // 0.1 × 600 = 60 px radius handle
        var line = LiquifyPathData.lineTo(SIMD2(0.75, 0.5))
        line.strength = SIMD2(0.8, 0.5)
        line.radius = SIMD2(0.85, 0.5)
        let stamps = LiquifyDistortionField.interpolateStamps(
            paths: [move, line], frame: Self.frame)
        XCTAssertGreaterThan(stamps.count, 5, "a 300 px path with r=60 stamps > 5 stamps")
        // Interpolated stamps carry 0.1× of the mixed strength: the mixed
        // strength magnitude stays ≤ max(|0.5·v1|, |0.5·v2|) = 37.5 px here
        // (v = 150 px × 0.5), so every interpolated stamp ≤ 3.75 px; the lone
        // full-strength stamps do not exist in a chain (move is not lone).
        var maxMag = 0.0
        for stamp in stamps {
            XCTAssertEqual(stamp.point.y, 200, accuracy: 1e-9, "stamps ride the line")
            maxMag = max(maxMag, LiquifyDistortionField.length(stamp.strength))
        }
        XCTAssertLessThan(maxMag, 3.75 + 1e-9, "0.1× STAMP_RELOCATION applied")
        // The chain's first stamp sits at the move point (t=0).
        XCTAssertEqual(stamps[0].point.x, 150, accuracy: 1e-9)
        // End-to-end: the full field builds and matches a re-deposit of the
        // same stamps (deposit is deterministic; the assertion pins the
        // pipeline plumbing, the per-cell math is covered above).
        let field = try XCTUnwrap(
            LiquifyDistortionField.build(
                paths: [move, line], frame: Self.frame, bounds: SIMD2(600, 400)),
            "chain field must build")
        var nonzero = 0
        for v in field.forward.vectors where v.x != 0 || v.y != 0 { nonzero += 1 }
        XCTAssertGreaterThan(nonzero, 0, "防空转: chain field must move pixels")
    }

    /// The bezier chain: MOVE→CURVE interpolates along the cubic with
    /// arc-length parameterization (dt INTERPOLATION_POINTS=100). Radius is
    /// set explicitly (a zero radius would stall dt's arc loop — the
    /// implementation breaks instead, D-06-06-T1-5).
    func testCurvePathInterpolation() {
        var move = LiquifyPathData.moveTo(SIMD2(0.25, 0.5))
        move.radius = SIMD2(0.35, 0.5)
        let curve = LiquifyPathData.curveTo(
            SIMD2(0.75, 0.5),
            ctrl1: SIMD2(0.42, 0.2), ctrl2: SIMD2(0.58, 0.8))
        var withRadius = curve
        withRadius.radius = SIMD2(0.85, 0.5)
        let stamps = LiquifyDistortionField.interpolateStamps(
            paths: [move, withRadius], frame: Self.frame)
        XCTAssertGreaterThan(stamps.count, 5, "curve chain must stamp")
        // First stamp at the move point, last advances along the curve.
        XCTAssertEqual(stamps[0].point.x, 150, accuracy: 1e-9)
        XCTAssertEqual(stamps[0].point.y, 200, accuracy: 1e-9)
        XCTAssertGreaterThan(
            stamps[stamps.count - 1].point.x, 300, "last stamp advances along the curve")
        // Zero-radius chain terminates via the guard (no hang, stamps may be
        // the single t=0 entry then stop).
        let degenerate = LiquifyDistortionField.interpolateStamps(
            paths: [LiquifyPathData.moveTo(SIMD2(0.25, 0.5)), curve], frame: Self.frame)
        XCTAssertFalse(degenerate.isEmpty, "guard terminates instead of hanging")
    }

    /// Profile boundary conditions (dt build_lookup_table contract):
    /// f(0) = 1, f(distance) = 0.
    func testLookupTableBoundaryConditions() throws {
        let table = try XCTUnwrap(LiquifyDistortionField.buildLookupTable(
            distance: 600, control1: 0.5, control2: 0.75))
        XCTAssertEqual(table[0], 1.0, "f(0) = 1")
        XCTAssertEqual(table[600], 0.0, "f(distance) = 0")
        // Monotone-decreasing profile for the default controls (the bezier's
        // y falls from 1 to 0).
        var violations = 0
        for i in 1..<600 where table[i] > table[i - 1] + 1e-9 { violations += 1 }
        XCTAssertEqual(violations, 0, "default profile must be monotone-decreasing")
    }


    // MARK: - T2: warp kernel + module (GPU vs float64 resampler)

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

    /// A textured synthetic (gradient × sine × deterministic noise — strong
    /// local structure so a sampling bug cannot hide).
    private func makeSyntheticTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) throws -> (input: any MTLTexture, rgb: [Double]) {
        func pseudoNoise(_ x: Int, _ y: Int) -> Double {
            var h = UInt64(x &* 374761393 &+ y &* 668265263)
            h = (h ^ (h >> 13)) &* 1274126177
            return Double(h % 1000) / 1000.0 - 0.5
        }
        var rgba = [Float](repeating: 0, count: width * height * 4)
        var rgb = [Double](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let i3 = (y * width + x) * 3
                let r = 0.1 + 0.8 * Double(x) / Double(width - 1) + 0.05 * pseudoNoise(x, y)
                let g = 0.1 + 0.8 * Double(y) / Double(height - 1) + 0.05 * pseudoNoise(x + 7919, y)
                let b = 0.3 + 0.3 * sin(Double(x) / 5.0) * cos(Double(y) / 7.0)
                    + 0.05 * pseudoNoise(x, y + 104729)
                rgb[i3] = r; rgb[i3 + 1] = g; rgb[i3 + 2] = b
                rgba[i] = Float(r); rgba[i + 1] = Float(g); rgba[i + 2] = Float(b)
                rgba[i + 3] = 1.0
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        rgba.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return (texture, rgb)
    }

    private func makeOutputTexture(
        _ metal: MetalContext, width: Int, height: Int
    ) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        let zeros = [Float](repeating: 0, count: width * height * 4)
        zeros.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    private func readRGBA(_ tex: any MTLTexture) -> [Float] {
        var floats = [Float](repeating: 0, count: tex.width * tex.height * 4)
        floats.withUnsafeMutableBytes {
            tex.getBytes(
                $0.baseAddress!, bytesPerRow: tex.width * 16,
                from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return floats
    }

    /// float64 reference resampler: per-pixel grid displacement (exact —
    /// the grid is per-pixel) + float64 lanczos3 via the same kmix TABLE
    /// semantics (the table IS dt's kernel definition; analytic evaluation
    /// of the table in Double mirrors the GPU's float32 mix).
    private func referenceWarp(
        input: [Double], width: Int, height: Int, field: DisplacementField,
        interpolation: LiquifyInterpolation
    ) -> [Double] {
        let size = interpolation.kernelSize
        let resolution = interpolation == .bilinear ? 1 : LiquifyModule.kdescResolution
        var k = [Double](repeating: 0, count: size * resolution + 1)
        if interpolation == .bilinear {
            k[0] = 1
        } else {
            for i in 0...size * resolution {
                let x = Float(Float(i) / Float(resolution))
                switch interpolation {
                case .bilinear: k[i] = 0
                case .bicubic: k[i] = Double(LiquifyModule.bicubic(0.5, x))
                case .lanczos2: k[i] = Double(LiquifyModule.lanczos(2, x))
                case .lanczos3: k[i] = Double(LiquifyModule.lanczos(3, x))
                }
            }
        }
        func kmix(_ t: Double) -> Double {
            let v = abs(t * Double(resolution))
            let flor = v.rounded(.down)
            let i = min(Int(flor), size * resolution - 1)
            let frac = v - flor
            return k[i] * (1 - frac) + k[i + 1] * frac
        }
        let a = size
        var out = [Double](repeating: 0, count: width * height * 3)
        let g = field.forward
        for py in 0..<height {
            for px in 0..<width {
                var warp = SIMD2<Double>.zero
                let cx = px - g.origin.x, cy = py - g.origin.y
                if cx >= 0, cy >= 0, cx < g.width, cy < g.height {
                    let v = g.vectors[cy * g.width + cx]
                    warp = SIMD2(Double(v.x), Double(v.y))
                }
                let inPos = SIMD2<Double>(Double(px), Double(py)) + warp
                let base = SIMD2<Int>(Int(inPos.x.rounded(.down)), Int(inPos.y.rounded(.down)))
                let fx = inPos.x - inPos.x.rounded(.down)
                let fy = inPos.y - inPos.y.rounded(.down)
                // dt warp_kernel taps: offsets 1−a … a (six for lanczos3).
                var nx = 0.0, ny = 0.0
                for i in (1 - a)...a {
                    nx += kmix(fx - Double(i))
                    ny += kmix(fy - Double(i))
                }
                var acc = SIMD3<Double>.zero
                func tap(_ ox: Int, _ oy: Int) -> SIMD3<Double> {
                    let x = min(max(base.x + ox, 0), width - 1)
                    let y = min(max(base.y + oy, 0), height - 1)
                    let idx = (y * width + x) * 4
                    return SIMD3(Double(input[idx]), Double(input[idx + 1]), Double(input[idx + 2]))
                }
                for sy in (1 - a)...a {
                    for sx in (1 - a)...a {
                        let wgt = kmix(fx - Double(sx)) * kmix(fy - Double(sy))
                        acc += tap(sx, sy) * wgt
                    }
                }
                let idx = (py * width + px) * 3
                out[idx] = acc.x / (nx * ny)
                out[idx + 1] = acc.y / (nx * ny)
                out[idx + 2] = acc.z / (nx * ny)
            }
        }
        return out
    }

    /// Warp parity: a single radial-grow stamp over the synthetic — the GPU
    /// `[liquify]` engine-direct run vs the float64 grid+lanczos3 reference,
    /// rel <1e-5 with abs floor (warp class, ashift precedent); 防空转:
    /// the warp must actually move pixels.
    func testWarpKernelParityAgainstFloat64Resampler() async throws {
        let metal = try await makeMetal()
        let (w, h) = (96, 96)
        let (inputTex, inputRGB) = try makeSyntheticTexture(metal, width: w, height: h)

        let params = LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.525, 0.5),
                radius: SIMD2(0.6, 0.5))
        ])
        let module = LiquifyModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: w, height: h)
        module.commitParams(params, into: &piece)
        let roi = ROI(width: w, height: h)
        let outputTex = try makeOutputTexture(metal, width: w, height: h)
        try await module.process(
            input: inputTex, output: outputTex, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal) // L014

        let got = readRGBA(outputTex)
        // 防空转: the warp really moved pixels.
        var moved = 0
        for i in 0..<(w * h) {
            let d = abs(Double(got[i * 4]) - inputRGB[i * 3])
            if d > 1e-4 { moved += 1 }
        }
        XCTAssertGreaterThan(moved, 100, "the stamp must displace interior pixels")

        // The reference resamples from the SAME T1-verified grid (the object
        // under test here is the RESAMPLER, not the field).
        let field = try XCTUnwrap(LiquifyDistortionField.build(
            paths: params.paths, frame: SIMD2(Double(w), Double(h)),
            boundsOrigin: .zero, boundsSize: SIMD2(w, h)))
        var refIn = [Double](repeating: 0, count: w * h * 4)
        let inBytes = readRGBA(inputTex)
        for i in 0..<(w * h * 4) { refIn[i] = Double(inBytes[i]) }
        let reference = referenceWarp(
            input: refIn, width: w, height: h, field: field,
            interpolation: .lanczos3)

        // The ashift two-key gate: rel <1e-5 AND abs >=1e-5 must BOTH hold
        // to fail (dark pixels amplify float32 dust into large rel).
        let gateRel = 1e-5, gateAbs = 1e-5
        var maxRel = 0.0
        var compared = 0
        var worst = ""
        for i in 0..<(w * h) {
            for c in 0..<3 {
                let g = Double(got[i * 4 + c])
                let r = reference[i * 3 + c]
                let diff = abs(g - r)
                let rel = diff / max(abs(r), 1e-3)
                if diff >= gateAbs { maxRel = max(maxRel, rel) }
                if rel >= gateRel && diff >= gateAbs && worst.count < 200 {
                    worst = "px(\(i % w),\(i / w)) ch\(c): got \(g) ref \(r) rel \(rel)"
                }
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
        XCTAssertLessThan(maxRel, gateRel, "warp parity \(maxRel) (gate \(gateRel)) — \(worst)")
        print("[06-06 T2] warp parity: maxRel \(maxRel) over \(compared) samples, \(moved) px moved")
    }

    /// Empty paths = BYTE identity through the full pipeline (the seed's
    /// normal state — the plan's 逐字节恒等红线, permanent regression).
    func testEmptyPathIdentityBytes() async throws {
        let metal = try await makeMetal()
        let (w, h) = (64, 64)
        let (inputTex, _) = try makeSyntheticTexture(metal, width: w, height: h)
        let module = LiquifyModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: w, height: h)
        module.commitParams(LiquifyModule.Params(), into: &piece)
        let roi = ROI(width: w, height: h)
        let outputTex = try makeOutputTexture(metal, width: w, height: h)
        try await module.process(
            input: inputTex, output: outputTex, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal)
        let a = readRGBA(inputTex)
        let b = readRGBA(outputTex)
        XCTAssertEqual(a, b, "empty-path liquify must be byte-identical (RGBA)")
        XCTAssertEqual(module.fieldBuildCount, 0, "identity path builds no field")
    }

    /// 仅参数变化重建: the same params + roi reuse the cached grid; a param
    /// change rebuilds (the plan's cache assertion).
    func testFieldCacheRebuildOnlyOnParamChange() async throws {
        let metal = try await makeMetal()
        let (w, h) = (64, 64)
        let (inputTex, _) = try makeSyntheticTexture(metal, width: w, height: h)
        let module = LiquifyModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: w, height: h)
        var params = LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5), strength: SIMD2(0.55, 0.5),
                radius: SIMD2(0.6, 0.5))
        ])
        module.commitParams(params, into: &piece)
        let roi = ROI(width: w, height: h)
        let outputTex = try makeOutputTexture(metal, width: w, height: h)
        try await module.process(
            input: inputTex, output: outputTex, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        XCTAssertEqual(module.fieldBuildCount, 1, "first run builds once")
        await drain(metal)
        // Same params, same roi: cache hit (repeat process = the ROI-walk's
        // modifyROIIn + process sequence).
        try await module.process(
            input: inputTex, output: outputTex, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal)
        XCTAssertEqual(module.fieldBuildCount, 1, "cache hit on unchanged params+roi")
        // A param change rebuilds.
        params.paths[0].radius = SIMD2(0.7, 0.5)
        module.commitParams(params, into: &piece)
        try await module.process(
            input: inputTex, output: outputTex, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal)
        XCTAssertEqual(module.fieldBuildCount, 2, "param change rebuilds")
    }

    /// modifyROIIn extends the input roi by the stamp extent + interpolation
    /// margin, clamped to the plane (dt :1213-1285 under L020/L021).
    func testModifyROIInExtendsByStampExtent() {
        let module = LiquifyModule()
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: 200, height: 200)
        // Stamp at frame fraction (0.5, 0.5) radius 0.1 → 20 px on a 200 px
        // plane (radius resolves against max(w, h)).
        var params = LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow, point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.55, 0.5), radius: SIMD2(0.6, 0.5))
        ])
        module.commitParams(params, into: &piece)
        let roi = ROI(x: 0, y: 0, width: 200, height: 200)
        var input = ROI()
        module.modifyROIIn(output: roi, input: &input, piece: piece)
        // extent = 41 px wide centered at 100 → 79..121 (2·20+1 = 41 →
        // origin 100−20=80, 80..121... center round(100)=100, iradius 20 →
        // 80..120); margin a=3 low, 4 high → 77..125.
        XCTAssertLessThanOrEqual(input.x, 77, "input extends left of the stamp")
        XCTAssertGreaterThanOrEqual(input.x + input.width, 124, "input extends right of the stamp")
        XCTAssertEqual(input.x + input.width <= 200, true, "clamped to the plane")
        // Neutral passes through.
        params = LiquifyModule.Params()
        module.commitParams(params, into: &piece)
        var input2 = ROI()
        module.modifyROIIn(output: roi, input: &input2, piece: piece)
        XCTAssertEqual(input2, roi, "neutral roi passes verbatim")
    }

    /// Seed: liquify joins ENABLED-neutral (empty paths — cache-neutral,
    /// exposure-0EV style), slot 18.0.
    func testSeedEnabledNeutral() throws {
        let seed = LightamerIOPRegistry.editingDefaultInstances()
        let liquify = try XCTUnwrap(seed.first { $0.opName == LiquifyModule.opName })
        XCTAssertTrue(liquify.enabled, "seed is ENABLED-neutral")
        XCTAssertEqual(
            try liquify.params(of: LiquifyModule.self).paths.count, 0,
            "empty paths = identity")
        XCTAssertEqual(liquify.iopOrder, 18.0)
    }

    /// The kernel tables match dt's producer (bicubic 0.5 / lanczos2 /
    /// lanczos3 at resolution 100; bilinear [1, 0] at resolution 1).
    func testKernelTables() {
        let (bilinearK, bilinearRes) = LiquifyModule.kernelTable(.bilinear)
        XCTAssertEqual(bilinearRes, 1)
        XCTAssertEqual(bilinearK, [1, 0])
        let (lanczos3, res) = LiquifyModule.kernelTable(.lanczos3)
        XCTAssertEqual(res, 100)
        XCTAssertEqual(lanczos3.count, 3 * 100 + 1)
        XCTAssertEqual(lanczos3[0], 1.0, accuracy: 1e-6)
        XCTAssertEqual(lanczos3[300], 0.0, accuracy: 1e-6, "lanczos3 vanishes at |x|=3")
        XCTAssertGreaterThan(lanczos3[50], 0.5, "table midpoint sane")
        let (bicubic, _) = LiquifyModule.kernelTable(.bicubic)
        XCTAssertEqual(bicubic[0], 1.0, accuracy: 1e-6)
        XCTAssertEqual(bicubic[200], 0.0, accuracy: 1e-6, "bicubic(0.5) vanishes at |x|=2")
    }


    // MARK: - T5: forced tiling + track B zero increment

    private func makeDecodedImage(rgb: [Double], width: Int, height: Int) throws -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = Float(rgb[i * 3])
            rgba[i * 4 + 1] = Float(rgb[i * 3 + 1])
            rgba[i * 4 + 2] = Float(rgb[i * 3 + 2])
            rgba[i * 4 + 3] = 1.0
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: width * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    /// Forced tiling == whole plane <1e-6 (the halo = displacement bound +
    /// kernel taps; the tile driver re-negotiates the read rect per tile).
    func testForcedTilingMatchesWholePlane() async throws {
        let metal = try await makeMetal()
        let (w, h) = (96, 96)
        let (inputTex, inputRGB) = try makeSyntheticTexture(metal, width: w, height: h)

        let params = LiquifyModule.Params(paths: [
            LiquifyPathData(
                type: .moveTo, warpType: .radialGrow,
                point: SIMD2(0.5, 0.5),
                strength: SIMD2(0.55, 0.5),
                radius: SIMD2(0.6, 0.5))
        ])

        func run(maxTileBytes: Int?) async throws -> [Float] {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry)
            let made = await registry.makeBox(opName: LiquifyModule.opName)
            let box = try XCTUnwrap(made as? ModuleBox<LiquifyModule>)
            box.setParams(params)
            let image = try makeDecodedImage(rgb: inputRGB, width: w, height: h)
            let (tex, _) = try await RenderPipeline.process(
                image: image, instances: [box as any ModuleBoxing], imageID: UUID(),
                resolution: .full, cache: PipeCache(), metal: metal,
                longEdge: nil, maxTileWorkingBytes: maxTileBytes)
            await drain(metal)
            return readRGBA(tex)
        }

        let whole = try await run(maxTileBytes: nil)
        let tiled = try await run(maxTileBytes: 4 << 10)  // 4KB — bpp≈1 → 强制分块
        // 分块计数 > 1 经同参 TilingPlan 复算。
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: w, height: h)
        piece.iscale = 1.0
        piece.pipeType = .full
        let module = LiquifyModule()
        module.commitParams(params, into: &piece)
        let bpp = module.tileWorkingSetBytesPerPixel(piece: piece)
        let halo = module.tileHalo(roi: ROI(width: w, height: h), piece: piece)
        let tiles = TilingPlan.tiles(
            forWidth: w, height: h, maxTileBytes: 4 << 10, bytesPerPixel: bpp, overlap: halo)
        XCTAssertGreaterThan(tiles.count, 1, "budget must force tiles (bpp=\(bpp))")
        var compared = 0
        var maxDiff: Double = 0
        for i in 0..<(w * h * 4) {
            compared += 1
            maxDiff = max(maxDiff, abs(Double(whole[i]) - Double(tiled[i])))
        }
        XCTAssertGreaterThan(compared, 0, "防空转 guard")
        XCTAssertLessThan(maxDiff, 1e-6, "tiled == whole (max \(maxDiff))")
        print("[06-06 T5] forced tiling: tiles=\(tiles.count) halo=\(halo) bpp=\(bpp) maxDiff=\(maxDiff)")
    }

    /// Track B zero increment (轨 B 空路径插链零增量): the seed's empty
    /// liquify in a FULL pipe chain renders byte-identical to the chain
    /// without it.
    func testTrackBZeroIncrementWithEmptyLiquify() async throws {
        let metal = try await makeMetal()
        let (w, h) = (64, 64)
        let (inputTex, inputRGB) = try makeSyntheticTexture(metal, width: w, height: h)

        func run(withLiquify: Bool) async throws -> [Float] {
            let registry = ModuleRegistry.makeDefault()
            await LightamerIOPRegistry.populate(registry)
            var chain: [any ModuleBoxing] = []
            if withLiquify {
                let made = await registry.makeBox(opName: LiquifyModule.opName)
                let box = try XCTUnwrap(made as? ModuleBox<LiquifyModule>)
                box.setParams(LiquifyModule.Params())  // the SEED state
                chain.append(box)
            }
            let madeColorin = await registry.makeBox(opName: ColorInModule.opName)
            let colorin = try XCTUnwrap(madeColorin as? ModuleBox<ColorInModule>)
            colorin.setParams(.init())
            chain.append(colorin)
            let image = try makeDecodedImage(rgb: inputRGB, width: w, height: h)
            let (tex, _) = try await RenderPipeline.process(
                image: image, instances: chain, imageID: UUID(),
                resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil)
            await drain(metal)
            return readRGBA(tex)
        }

        let base = try await run(withLiquify: false)
        let withEmpty = try await run(withLiquify: true)
        XCTAssertEqual(base, withEmpty,
                       "empty-path liquify in the chain = byte-identical (zero increment)")
    }

    // MARK: - T1: empty/degenerate paths

    func testEmptyPathsBuildNothing() {
        XCTAssertNil(LiquifyDistortionField.build(
            paths: [], frame: Self.frame, bounds: SIMD2(600, 400)), "empty = identity")
        // A zero-radius (degenerate) stamp builds nothing.
        let data = LiquifyPathData(
            type: .moveTo, warpType: .radialGrow, point: SIMD2(0.5, 0.5))
        XCTAssertNil(
            LiquifyDistortionField.build(
                paths: [data], frame: Self.frame, bounds: SIMD2(600, 400)),
            "degenerate stamp = identity")
        XCTAssertNil(LiquifyDistortionField.build(
            paths: [LiquifyPathData(type: .invalidated, point: SIMD2(0.5, 0.5))],
            frame: Self.frame, bounds: SIMD2(600, 400)), "invalidated terminator = identity")
    }
}
