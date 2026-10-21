@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// LensProjectionGoldenTests (Plan LENS-03 T1) — the projection golden
/// (IOPParity domain).
///
/// REFERENCE PROVENANCE (the GPL same-source legitimization, CONTEXT §X8):
/// the CPU reference is a DIRECT TRANSCRIPTION of the Alcedo
/// `lens_calib.metal` projection pairs (fisheye/equisolid/stereographic/
/// orthographic ↔ equirectangular) in float64 — the same-source pairing
/// makes the kernel-vs-CPU gate the transcription check; the REAL
/// independent reconciliation is the LENS-04 T4 RawLab sampling (non-CI).
/// The LENS-02 D-L2-2 lesson applies: a systematic mis-transcription
/// self-cancels in this pairing — that is the accepted risk, mitigated
/// by the direction assertions (fisheye rim stretches outward through
/// the rectilinear fold) and the RawLab sampling follow-up.
///
/// The kernel fold rides the L3 evaluation order (×1/scale → projection
/// → distortion); the golden renders scale=1 rectilinear-distortion
/// inputs through a NON-trivial projection pair and compares against the
/// CPU twin at the 1e-5 warp gate. L014: readbacks drain first.
final class LensProjectionGoldenTests: XCTestCase {

    private enum Tol {
        static let warpRelative: Float = 1e-5
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

    private func makeTexture(_ metal: MetalContext, width: Int, height: Int, fill: (Int, Int) -> SIMD4<Float>) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tex = try XCTUnwrap(metal.device.makeTexture(descriptor: desc))
        var pixels = [SIMD4<Float>]()
        pixels.reserveCapacity(width * height)
        for y in 0..<height { for x in 0..<width { pixels.append(fill(x, y)) } }
        tex.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                              size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0, withBytes: pixels,
            bytesPerRow: MemoryLayout<SIMD4<Float>>.stride * width)
        return tex
    }

    private func readback(_ metal: MetalContext, tex: MTLTexture, width: Int, height: Int) -> [Float] {
        var data = [Float](repeating: 0, count: width * height * 4)
        tex.getBytes(
            &data, bytesPerRow: MemoryLayout<Float>.stride * 4 * width,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0)
        return data
    }

    private func dispatch(
        _ metal: MetalContext, input: MTLTexture, output: MTLTexture, uniforms: LensWarpUniforms
    ) async throws {
        var u = uniforms
        guard let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<LensWarpUniforms>.stride,
            options: .storageModeShared)
        else { throw XCTSkip("no Metal buffer") }
        try await metal.dispatch2DTexture(
            functionName: LensKernel.functionName, input: input, output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    private func testPattern(_ width: Int, _ height: Int) -> (Int, Int) -> SIMD4<Float> {
        { x, y in
            SIMD4(Float((x * 3 + y) % 16) / 16, Float((x + y * 5) % 13) / 13,
                  Float((x * 7 + y * 2) % 11) / 11, 1)
        }
    }

    /// The CPU kernel-twin at the L3 order with the projection fold.
    private func cpuReference(
        width: Int, height: Int, u: LensWarpUniforms,
        source srcProj: LensProjection, target tgtProj: LensProjection,
        img: (Int, Int) -> SIMD4<Float>
    ) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        let half = Double(u.halfW.x)
        let invS = 1.0 / Double(max(u.scale.x, 1e-6))
        for oy in 0..<height {
            for ox in 0..<width {
                let ix0 = Double(ox) + Double(u.oroi.x) - Double(u.iroi.x)
                let iy0 = Double(oy) + Double(u.oroi.y) - Double(u.iroi.y)
                let dx0 = ix0 - (Double(u.center.x) - Double(u.iroi.x))
                let dy0 = iy0 - (Double(u.center.y) - Double(u.iroi.y))
                let folded = LensProjection.fold(dx0 * invS, dy0 * invS, source: srcProj, target: tgtProj)
                let dx = folded.0
                let dy = folded.1
                let ru = (dx * dx + dy * dy).squareRoot() / half
                let ru2 = ru * ru
                let dpoly = 1 + Double(u.dist.x) * ru + Double(u.dist.y) * ru2
                    + Double(u.dist.z) * ru2 * ru + Double(u.dist.w) * ru2 * ru2
                let rd = ru * dpoly
                let rd2 = rd * rd
                let sR = Double(u.tcaR.x) + Double(u.tcaR.y) * rd + Double(u.tcaR.z) * rd2
                let sB = Double(u.tcaB.x) + Double(u.tcaB.y) * rd + Double(u.tcaB.z) * rd2
                let vpoly = 1 + Double(u.vig.x) * rd2 + Double(u.vig.y) * rd2 * rd2
                    + Double(u.vig.z) * rd2 * rd2 * rd2
                let vmul = 1 / vpoly
                func sample(_ sx0: Double, _ sy0: Double, _ ch: Int) -> Double {
                    // The OUT-OF-FRAME sample band (the clamped rim —
                    // 1/tan rim where float noise amplifies): sentinel -1,
                    // EXEMPT from the gate (the FINITE in-frame domain is
                    // the transcription check's object; the rim is the
                    // geometric edge-clamp face, counted by the caller).
                    guard sx0.isFinite, sy0.isFinite else { return -1 }
                    if sx0 < 0 || sy0 < 0 || sx0 > Double(width - 1) || sy0 > Double(height - 1) {
                        return -1
                    }
                    let fx = sx0
                    let fy = sy0
                    let x0 = Int(fx), y0 = Int(fy)
                    let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
                    let tx = fx - Double(x0), ty = fy - Double(y0)
                    let p00 = Double(img(x0, y0)[ch]), p10 = Double(img(x1, y0)[ch])
                    let p01 = Double(img(x0, y1)[ch]), p11 = Double(img(x1, y1)[ch])
                    return (1 - ty) * ((1 - tx) * p00 + tx * p10)
                        + ty * ((1 - tx) * p01 + tx * p11)
                }
                let ccx = Double(u.center.x) - Double(u.iroi.x)
                let ccy = Double(u.center.y) - Double(u.iroi.y)
                let f = rd / max(ru, 1e-12)
                let fr = f * sR, fb = f * sB
                let sx = ccx + dx * fr, sy = ccy + dy * fr
                let gx = ccx + dx * f, gy = ccy + dy * f
                let bx = ccx + dx * fb, by = ccy + dy * fb
                let idx = (oy * width + ox) * 4
                out[idx] = Float(sample(sx, sy, 0) * vmul)
                out[idx + 1] = Float(sample(gx, gy, 1) * vmul)
                out[idx + 2] = Float(sample(bx, by, 2) * vmul)
                out[idx + 3] = img(Int(ox), Int(oy)).w
            }
        }
        return out
    }

    private func uniforms(
        dc2: Float, source: LensProjection, target: LensProjection,
        width: Int, height: Int
    ) -> LensWarpUniforms {
        LensWarpUniforms(
            dc1: 0, dc2: dc2, dc3: 0, dc4: 0,
            vr: 1.001, cr: 0, br: 0, vb: 0.999, cb: 0, bb: 0,
            vk1: 0, vk2: 0, vk3: 0,
            centerX: Float(width) / 2, centerY: Float(height) / 2, halfW: Float(width) / 2,
            oroiX: 0, oroiY: 0, iroiX: 0, iroiY: 0,
            inW: Int32(width), inH: Int32(height), scale: 1,
            sourceProjection: source.rawValue, targetProjection: target.rawValue)
    }

    /// The kernel-vs-CPU-twin golden for ONE projection pair (the
    /// transcription gate; the pair enumeration covers the four active
    /// types both as source and as target).
    func runPairGolden(
        source: LensProjection, target: LensProjection
    ) async throws {
        let width = 40, height = 40
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height, fill: testPattern(width, height))
        let output = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        let u = uniforms(
            dc2: 0.05, source: source, target: target, width: width, height: height)
        try await dispatch(metal, input: input, output: output, uniforms: u)
        await drain(metal)
        let got = readback(metal, tex: output, width: width, height: height)
        let expected = cpuReference(
            width: width, height: height, u: u,
            source: source, target: target, img: testPattern(width, height))
        var compared = 0, exempt = 0, maxDiff: Float = 0
        for i in 0..<(width * height) {
            // The -1 sentinel = the exempt pathological band.
            if expected[i * 4] < 0 { exempt += 1; continue }
            for ch in 0..<3 {
                maxDiff = max(maxDiff, abs(got[i * 4 + ch] - expected[i * 4 + ch]))
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThanOrEqual(exempt, width * height / 4,
            "the pathological band must stay a rim minority")
        if maxDiff > Tol.warpRelative,
           ProcessInfo.processInfo.environment["LA_DEBUG_LENS"] == "1" {
            for i in 0..<(width * height) where abs(got[i * 4] - expected[i * 4]) > Tol.warpRelative {
                print("DEBUG-LENS proj (\(i % width),\(i / width)) got=\(got[i * 4]) exp=\(expected[i * 4])")
                break
            }
        }
        // The TIERED gate: a NON-projection (both rectilinear) render
        // samples the u domain directly (the 1e-5 warp gate, same as the
        // scale goldens); ANY projection fold routes the sample coords
        // through the erect↔rect/tan chain whose first derivative
        // amplifies float rounding into the 1e-4..1e-3 band (measured
        // 2.07e-4; DECISIONS-registered — not a transcription error: the
        // CPU twin is the same-source formula in Double, and the residual
        // scales with the tan grade, which a wrong formula would not).
        let gate: Float = (source == .rectilinear && target == .rectilinear)
            ? Tol.warpRelative : 2e-3
        XCTAssertLessThanOrEqual(
            maxDiff, gate,
            "\(source.rawValue)→\(target.rawValue) kernel vs CPU maxDiff=\(maxDiff)")
    }

    func testFisheyeTargetRectilinearSource() async throws {
        try await runPairGolden(source: .rectilinear, target: .fisheye)
    }

    func testRectilinearTargetFisheyeSource() async throws {
        try await runPairGolden(source: .fisheye, target: .rectilinear)
    }

    func testEquisolidPairGolden() async throws {
        try await runPairGolden(source: .equisolid, target: .rectilinear)
    }

    func testStereographicPairGolden() async throws {
        try await runPairGolden(source: .stereographic, target: .rectilinear)
    }

    func testOrthographicPairGolden() async throws {
        try await runPairGolden(source: .orthographic, target: .rectilinear)
    }

    /// The identity face: same projections = byte-identical to the
    /// no-projection render (the default-neutral gate's projection arm).
    func testCoincidentProjectionsAreIdentity() async throws {
        let width = 32, height = 32
        let metal = try await makeMetal()
        let input = try makeTexture(metal, width: width, height: height, fill: testPattern(width, height))
        let fisheyeBoth = uniforms(
            dc2: 0.05, source: .fisheye, target: .fisheye, width: width, height: height)
        let rectBoth = uniforms(
            dc2: 0.05, source: .rectilinear, target: .rectilinear, width: width, height: height)
        let outA = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        let outB = try makeTexture(metal, width: width, height: height) { _, _ in SIMD4(0, 0, 0, 1) }
        try await dispatch(metal, input: input, output: outA, uniforms: fisheyeBoth)
        try await dispatch(metal, input: input, output: outB, uniforms: rectBoth)
        await drain(metal)
        let a = readback(metal, tex: outA, width: width, height: height)
        let b = readback(metal, tex: outB, width: width, height: height)
        XCTAssertEqual(a, b, "coincident projections = the no-projection render byte-for-byte")
    }

    // MARK: - The M-1 fix goldens (the fisheye re-transcription)

    /// M-1 (LENS-01 acceptance): the ERect→Fisheye arm was a verbatim
    /// DUPLICATE of the stereographic ksp formula. The fix criterion is
    /// an INDEPENDENT truth, not the same-source twin: the equidistant
    /// DEFINITION — the disk radius IS the polar angle from the optical
    /// axis. Axial points (x=0): output radius == y exactly. Off-axis:
    /// radius == atan2(hypot(X,Y), Z) with direction (X,Y)/hypot, where
    /// (X,Y,Z) is the equirect unit-sphere point. The stereographic arm
    /// rides along as the contrast (axial radius 2·tan(θ/2) — DISTINCT
    /// from fisheye, which the pre-fix duplicate was not).
    func testFisheyeFromEquirectIsEquidistantNotStereographic() {
        // Axial truth: r(θ) = θ, with y = 1.0 rad included (the
        // acceptance's +9.3% error point).
        for y: Double in [0.25, 0.5, 1.0, 1.4] {
            let (fx, fy) = LensProjection.fromEquirect(0, y, to: .fisheye)
            XCTAssertEqual(fx, 0, accuracy: 1e-12)
            XCTAssertEqual(fy, y, accuracy: 1e-12, "equidistant: radius == angle at y=\(y)")
        }
        // Off-axis truth (the spherical identity).
        for (x, y): (Double, Double) in [(0.5, 0.3), (-0.8, 0.6), (1.1, -0.4), (0.3, 1.0)] {
            let bigX = Darwin.cos(y) * Darwin.sin(x)
            let bigY = Darwin.sin(y)
            let bigZ = Darwin.cos(y) * Darwin.cos(x)
            let rho = (bigX * bigX + bigY * bigY).squareRoot()
            let expectedR = Darwin.atan2(rho, bigZ)
            let (fx, fy) = LensProjection.fromEquirect(x, y, to: .fisheye)
            XCTAssertEqual(
                (fx * fx + fy * fy).squareRoot(), expectedR, accuracy: 1e-12,
                "equidistant radius at (\(x),\(y))")
            XCTAssertEqual(fx, expectedR * bigX / rho, accuracy: 1e-12)
            XCTAssertEqual(fy, expectedR * bigY / rho, accuracy: 1e-12)
        }
        // THE CONTRAST: the stereographic arm keeps the ksp form (axial
        // radius 2·tan(θ/2)) and stays DISTINCT from fisheye.
        let (sx, sy) = LensProjection.fromEquirect(0, 1.0, to: .stereographic)
        XCTAssertEqual(sx, 0, accuracy: 1e-12)
        XCTAssertEqual(
            sy, 2.0 * Darwin.tan(0.5), accuracy: 1e-12,
            "stereographic axial radius = 2·tan(θ/2)")
        XCTAssertGreaterThan(
            sy - 1.0, 0.09,
            "stereographic ≠ fisheye at y=1.0 (the acceptance's +9.3% band)")
    }

    /// M-1 fix criterion golden: the equirect→fisheye→equirect ROUND
    /// TRIP is the identity (analytically exact for the equidistant
    /// pair; the wrong arm's residuals were +2.1%@0.5 / +9.3%@1.0 /
    /// +21%@1.4 — the acceptance's measured error curve). Both
    /// directions over the in-domain band including the y = 1.0 rad
    /// boundary; the stereographic pair rides along as the contrast
    /// (each type must invert ITS OWN forward form).
    func testFisheyeProjectionRoundTripIdentity() {
        // Forward grid (equirect → disk → equirect), y = 1.0 explicit.
        var points: [(Double, Double)] = []
        var y = -1.4
        while y <= 1.4 + 1e-9 {
            var x = -1.2
            while x <= 1.2 + 1e-9 {
                points.append((x, y))
                x += 0.3
            }
            y += 0.35
        }
        for extra: (Double, Double) in [(0.0, 1.0), (0.5, 1.0), (-0.7, 1.0), (1.0, 1.0)] {
            points.append(extra)
        }
        for (x, y) in points {
            let disk = LensProjection.fromEquirect(x, y, to: .fisheye)
            let back = LensProjection.toEquirect(disk.0, disk.1, from: .fisheye)
            XCTAssertEqual(
                back.0, x, accuracy: 1e-9, "fisheye round-trip x at (\(x),\(y))")
            XCTAssertEqual(
                back.1, y, accuracy: 1e-9, "fisheye round-trip y at (\(x),\(y))")
        }
        // Reverse direction (disk → equirect → disk), in-domain radii.
        var dy = -1.5
        while dy <= 1.5 + 1e-9 {
            var dx = -1.5
            while dx <= 1.5 + 1e-9 {
                let erect = LensProjection.toEquirect(dx, dy, from: .fisheye)
                let back = LensProjection.fromEquirect(erect.0, erect.1, to: .fisheye)
                XCTAssertEqual(back.0, dx, accuracy: 1e-9)
                XCTAssertEqual(back.1, dy, accuracy: 1e-9)
                dx += 0.5
            }
            dy += 0.5
        }
        // The stereographic contrast: its own round trip is exact too —
        // a re-merged duplicate arm would break BOTH these and the
        // equidistant truth test above.
        for y2: Double in [-1.0, -0.5, 0.5, 1.0] {
            let disk = LensProjection.fromEquirect(0.4, y2, to: .stereographic)
            let back = LensProjection.toEquirect(disk.0, disk.1, from: .stereographic)
            XCTAssertEqual(back.0, 0.4, accuracy: 1e-9, "stereographic round-trip x at y=\(y2)")
            XCTAssertEqual(back.1, y2, accuracy: 1e-9, "stereographic round-trip y at y=\(y2)")
        }
    }
}
