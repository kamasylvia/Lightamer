@testable import LightamerCore
@testable import LightamerIOP
import Metal
import simd
import XCTest

/// UprightModuleParityTests (Plan M9-3-T2) — the upright op's pipe face.
///
/// REFERENCE PROVENANCE (L017 route ①, the AshiftParity warp-class shape):
/// the correction math is validated against Core's own golden gates
/// (UprightMathTests, T1) at the SOLVE level; this file validates the PIPE
/// face around it — the warp THROUGH the real `ashift_warp` kernel is
/// compared against the formula-mirrored CPU prediction (same closed-form
/// sources, gate 1e-5 warp class on a smooth interior) and against the
/// physical line-straightening spread gate on real pixels.
///
/// ANTI-VACUUM: every test below runs real pixels or real bytes — no
/// vacuous parity passes. L014: every GPU readback drains first.
final class UprightModuleParityTests: XCTestCase {

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

    private func makeTexture(
        _ metal: MetalContext, width: Int, height: Int, write pixels: [SIMD4<Float>]
    ) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: descriptor))
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0, withBytes: raw.baseAddress!,
                bytesPerRow: width * MemoryLayout<SIMD4<Float>>.stride)
        }
        return texture
    }

    private func readback(
        _ metal: MetalContext, _ texture: any MTLTexture
    ) async -> [SIMD4<Float>] {
        await drain(metal)  // L014
        let w = texture.width, h = texture.height
        var pixels = [SIMD4<Float>](repeating: .zero, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(
                raw.baseAddress!, bytesPerRow: w * MemoryLayout<SIMD4<Float>>.stride,
                from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: w, height: h, depth: 1)),
                mipmapLevel: 0)
        }
        return pixels
    }

    // MARK: - the keystone scene (720×480, three converging verticals)

    private static let width = 720
    private static let height = 480

    /// The top/bottom x of each converging vertical (top wider than the
    /// bottom — the shot-from-below keystone), interpolated per row.
    private static let lineTopX = [150.0, 360.0, 570.0]
    private static let lineBottomX = [200.0, 360.0, 520.0]

    private static func lineX(_ line: Int, atY y: Double) -> Double {
        let t = y / Double(height)
        return lineTopX[line] + (lineBottomX[line] - lineTopX[line]) * t
    }

    /// White ground + three near-black converging verticals (±1 px around
    /// each line's center).
    private static func keystonePlane() -> [SIMD4<Float>] {
        var plane = [SIMD4<Float>](
            repeating: SIMD4(0.9, 0.9, 0.9, 1.0), count: width * height)
        for y in 0..<height {
            for line in 0..<3 {
                let x = lineX(line, atY: Double(y))
                for dx in -1...1 {
                    let px = Int(x.rounded()) + dx
                    guard px >= 0, px < width else { continue }
                    plane[y * width + px] = SIMD4(0.0, 0.0, 0.0, 1.0)
                }
            }
        }
        return plane
    }

    /// Guides along the converging verticals (two well-inside endpoints per
    /// line, input-frame 0..1 — what a user would draw).
    private static func keystoneGuides() -> [UprightModule.Guide] {
        (0..<3).map { line in
            let y0 = 96.0, y1 = 384.0
            return UprightModule.Guide(
                ax: lineX(line, atY: y0) / Double(width),
                ay: y0 / Double(height),
                bx: lineX(line, atY: y1) / Double(width),
                by: y1 / Double(height))
        }
    }

    // MARK: - gate ①: off = identity, byte-exact, params persist legally

    func testOffIdentityByteExactAndParamsPersist() async throws {
        let metal = try await makeMetal()
        let plane = Self.keystonePlane()
        let width = Self.width, height = Self.height

        let box = ModuleBox(module: UprightModule(), instanceID: UUID())
        box.setParams(UprightModule.Params())  // mode off, no guides

        // v2 MIN-2: the seed-committed instance ALWAYS carries legal
        // paramsData (there is deliberately no "off omits the sidecar"
        // branch — the pristine convention is a document-record semantics).
        XCTAssertFalse(box.paramsData.isEmpty, "off instance paramsData is written")
        let decoded = try JSONDecoder().decode(UprightModule.Params.self, from: box.paramsData)
        XCTAssertEqual(decoded.mode, .off)
        XCTAssertTrue(decoded.guides.isEmpty)

        let input = try makeTexture(metal, width: width, height: height, write: plane)
        let output = try makeTexture(metal, width: width, height: height, write: [])
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: width, height: height)  // module-level probe stamp
        try await box.module.process(
            input: input, output: output,
            roiIn: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            roiOut: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            piece: &piece, metal: metal)
        let out = await readback(metal, output)
        XCTAssertEqual(out.count, plane.count)
        for i in 0..<plane.count {
            XCTAssertEqual(out[i].x, plane[i].x, accuracy: 0, "byte-exact identity at \(i)")
            XCTAssertEqual(out[i].w, plane[i].w, accuracy: 0)
        }
        // ROI hooks agree (identity negotiation)
        var roiOut = ROI()
        box.module.modifyROIOut(
            &roiOut,
            input: ROI(x: 0, y: 0, width: width, height: height, scale: 1),
            piece: piece)
        XCTAssertEqual(roiOut.width, width)
        XCTAssertNil(box.module.pointMapSegment(inputSize: SIMD2(Double(width), Double(height))),
                     "an off instance contributes no mapper segment")
    }

    // MARK: - gate ②: the real-kernel warp straightens converging verticals

    func testGuidedWarpStraightensKeystoneThroughRealKernel() async throws {
        let metal = try await makeMetal()
        let plane = Self.keystonePlane()
        let width = Self.width, height = Self.height

        let box = ModuleBox(module: UprightModule(), instanceID: UUID())
        box.setParams(UprightModule.Params(mode: .guided, guides: Self.keystoneGuides()))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: width, height: height)  // module-level probe stamp

        // ROI negotiation through the hooks (the pipe's own walk)
        let full = ROI(x: 0, y: 0, width: width, height: height, scale: 1)
        var roiOut = ROI()
        box.module.modifyROIOut(&roiOut, input: full, piece: piece)
        var roiIn = ROI()
        box.module.modifyROIIn(output: roiOut, input: &roiIn, piece: piece)
        XCTAssertGreaterThanOrEqual(roiOut.width, 4)
        XCTAssertGreaterThanOrEqual(roiOut.height, 4)

        let input = try makeTexture(metal, width: width, height: height, write: plane)
        let output = try makeTexture(
            metal, width: roiOut.width, height: roiOut.height, write: [])
        try await box.module.process(
            input: input, output: output, roiIn: roiIn, roiOut: roiOut,
            piece: &piece, metal: metal)
        let out = await readback(metal, output)

        // Physical check on real pixels: each straightened vertical spans
        // the same x in every row (the lightroom "converging verticals"
        // acceptance). Scan rows well inside the output, cluster the dark
        // runs, and measure per-line x spread (gate 1.5 px, upstream's
        // `guided_upright_from_two_vertical_guides` face).
        func lineCenters(row: Int) -> [Double]? {
            // Dark AND opaque: the kernel writes transparent (0,0,0,0)
            // outside the source domain — that black is NOT a line.
            var runs: [(first: Int, last: Int)] = []
            var current: (first: Int, last: Int)?
            for x in 0..<roiOut.width {
                let p = out[row * roiOut.width + x]
                let dark = p.w > 0.5 && p.x < 0.45
                if dark {
                    if let c = current {
                        current = (c.first, x)
                    } else {
                        current = (x, x)
                    }
                } else if let c = current {
                    runs.append(c)
                    current = nil
                }
            }
            if let c = current { runs.append(c) }
            guard runs.count == 3 else { return nil }
            return runs.map { Double($0.first + $0.last) / 2 }
        }
        for line in 0..<3 {
            var xs: [Double] = []
            for row in stride(from: 60, to: roiOut.height - 60, by: 40) {
                guard let centers = lineCenters(row: row) else {
                    XCTFail("row \(row): expected three straightened lines, got \(lineCenters(row: row) ?? [])")
                    return
                }
                xs.append(centers[line])
            }
            let spread = (xs.max()! - xs.min()!)
            XCTAssertLessThan(spread, 1.5, "line \(line) x-trace spread after the real-kernel warp")
        }

        // Formula-mirrored landing check (L017 route ①, anti-vacuum): the
        // CPU side re-derives the SAME closed form (UprightMath solve + the
        // D_out·H·D_in⁻¹ rescale) and predicts WHERE each line lands; the
        // kernel's output plane must actually be dark there (bilinear
        // landing within the 1 px line width). Comparing the kernel's
        // pixels against the prediction catches dispatch/ROI/uniforms
        // mistakes, not shared-math errors.
        let size = SIMD2<Double>(Double(width), Double(height))
        let longEdge = max(size.x, size.y)
        let centred = UprightMath.solveGuided(
            Self.keystoneGuides().map { g in
                UprightMath.Segment(
                    a: SIMD2((g.ax * size.x - size.x / 2) / (longEdge / 2),
                             (g.ay * size.y - size.y / 2) / (longEdge / 2)),
                    b: SIMD2((g.bx * size.x - size.x / 2) / (longEdge / 2),
                             (g.by * size.y - size.y / 2) / (longEdge / 2)))
            })
        let dinv = Mat3D(2 / longEdge, 0, -size.x / longEdge,
                         0, 2 / longEdge, -size.y / longEdge, 0, 0, 1)
        let dout = Mat3D(longEdge / 2, 0, size.x / 2,
                         0, longEdge / 2, size.y / 2, 0, 0, 1)
        let fwd = Mat3D.mul(dout, Mat3D.mul(centred, dinv))
        for line in 0..<3 {
            for yIn in stride(from: 110.0, through: 370.0, by: 40) {
                let q = fwd.project(Self.lineX(line, atY: yIn), yIn)
                let px = Int(q.x.rounded()), py = Int(q.y.rounded())
                guard px >= 0, px < roiOut.width, py >= 0, py < roiOut.height else { continue }
                let landed = out[py * roiOut.width + px]
                XCTAssertLessThan(
                    landed.x, 0.45,
                    "line \(line) input y=\(yIn) must land dark at (\(px),\(py))")
                XCTAssertGreaterThan(
                    landed.w, 0.5,
                    "line \(line) landing must be opaque (a transparent zero is NOT evidence)")
            }
        }
    }

    // MARK: - gate ③: params round-trip, StableHash, V50Order slot

    func testParamsRoundTripStableHashAndV50Order() throws {
        // Double-precision guide coordinates survive the JSON round trip
        // bit-for-bit (the sidecar paramsData contract).
        let guides = [
            UprightModule.Guide(ax: 0.1, ay: 0.2, bx: 0.13, by: 0.87),
            UprightModule.Guide(ax: 1.0 / 3.0, ay: 1.0 / 7.0, bx: 0.9, by: 0.11),
        ]
        let params = UprightModule.Params(mode: .guided, guides: guides)
        let data = ParamsCoding.encode(params)
        let back = try JSONDecoder().decode(UprightModule.Params.self, from: data)
        XCTAssertEqual(back, params, "guide coordinates survive encode/decode bitwise")
        // D-H4: the committed hash IS StableHash over the encoded params.
        let box = ModuleBox(module: UprightModule(), instanceID: UUID())
        box.setParams(params)
        XCTAssertEqual(box.paramsHash, StableHash.hash(data))
        XCTAssertEqual(box.paramsData, data)

        // V50Order: upright at 15.5, add-only — after ashift (15.0), before
        // flip (16.0), the existing rows byte-identical (V50OrderTests pins
        // the full table; this pins the neighborhood).
        XCTAssertEqual(V50Order.order(for: UprightModule.opName), 15.5)
        let names = V50Order.entries.map(\.opName)
        let uprightIdx = try XCTUnwrap(names.firstIndex(of: "upright"))
        XCTAssertEqual(names[uprightIdx - 1], "ashift")
        XCTAssertEqual(names[uprightIdx + 1], "flip")
        XCTAssertEqual(V50Order.order(for: "ashift"), 15.0)
        XCTAssertEqual(V50Order.order(for: "flip"), 16.0)

        // The seed carries the neutral instance (panel has something to
        // drive) and the disable set stays zero-touch (upright is
        // default-face ENABLED, D-M9G-2).
        let seed = LightamerIOPRegistry.editingDefaultInstances()
        XCTAssertTrue(seed.contains { $0.opName == UprightModule.opName })
        XCTAssertFalse(LightamerIOPRegistry.defaultFaceDisabledOpNames.contains(UprightModule.opName))
    }

    // MARK: - gate ④: the mapper segment round-trip

    func testPointMapSegmentRoundTrip() throws {
        let width = Double(Self.width), height = Double(Self.height)
        let box = ModuleBox(module: UprightModule(), instanceID: UUID())
        box.setParams(UprightModule.Params(mode: .guided, guides: Self.keystoneGuides()))
        var piece = box.makeRunPiece()
        piece.dscIn = IOPBufferDesc(width: Int(width), height: Int(height))  // probe stamp

        guard let mapped = box.module.pointMapSegment(inputSize: SIMD2(width, height)) else {
            XCTFail("a guided instance must supply a mapper segment")
            return
        }
        // outSpan agrees with the ROI negotiation (one predicate, two faces)
        var roiOut = ROI()
        box.module.modifyROIOut(
            &roiOut, input: ROI(x: 0, y: 0, width: Int(width), height: Int(height), scale: 1),
            piece: piece)
        XCTAssertEqual(mapped.outputSize.x, Double(roiOut.width))
        XCTAssertEqual(mapped.outputSize.y, Double(roiOut.height))
        guard case let .homography(fwd, inv, clip, _, outSpan) = mapped.segment else {
            XCTFail("the segment is the homography case")
            return
        }
        XCTAssertEqual(clip.x, 0, accuracy: 0)
        XCTAssertEqual(clip.y, 0, accuracy: 0)
        XCTAssertEqual(outSpan, mapped.outputSize)

        // Viewport ⇄ upright-input-frame round trip at <1 px through the
        // segment legs (the T4 overlay's mapping channel; sample points
        // across the output frame).
        var worst = 0.0
        for qy in stride(from: 40.0, to: outSpan.y - 40, by: 80) {
            for qx in stride(from: 40.0, to: outSpan.x - 40, by: 90) {
                // inverse: output pixel → input pixel (the homography leg's
                // shape: p = Hinv·(q + clip); clip is zero here)
                let shifted = inv.project(qx, qy)
                let back = fwd.project(shifted.x, shifted.y)
                worst = max(worst, ((back.x - qx) * (back.x - qx) + (back.y - qy) * (back.y - qy)).squareRoot())
            }
        }
        XCTAssertLessThan(worst, 1.0, "segment round-trip stays under 1 px")
    }
}
