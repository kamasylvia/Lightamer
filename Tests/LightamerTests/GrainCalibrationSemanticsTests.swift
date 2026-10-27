@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// GrainCalibrationSemanticsTests (Plan M9-2 T4 — IOPParity):
//
//   1. THE CALIBRATION PROBE (LIGHTAMER_PERF_PROBE-gated, skip by
//      default — the one-shot calibration action): a synthetic
//      net-density-1.0 gray plane through the PRODUCTION GrainModule at
//      the default scale, a 48 µm-equivalent box-filter DENSITY scan
//      (the microdensitometer's aperture simulation), a sweep over the
//      strength domain, and the inverse interpolation onto each
//      published RMS — printing the curve + the solved recommended
//      strengths for the JSON (the run that filled the table is
//      registered in M9-2-DECISIONS).
//   2. THE SEMANTICS GATE (always on): at each calibrated film's
//      RECOMMENDED strength, the same gray plane's box-scanned RMS
//      lands in the published value's band (the ±0.5 (1000×-scale)
//      aperture-band tolerance + the simplified-aperture note —
//      DECISIONS registers the measured residuals).
// ─────────────────────────────────────────────────────────────────────────────

final class GrainCalibrationSemanticsTests: XCTestCase {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var tableURL: URL {
        Self.repoRoot.appendingPathComponent(
            "Resources/FilmProfilesBW/grain_calibration.json")
    }

    // MARK: - The probe plumbing (the GrainTests dispatch form)

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: GrainKernel.metalBundle)
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

    private func runGrainGray(
        _ strength: Double, metal: MetalContext, side: Int = 512
    ) async throws -> [Float] {
        // Net diffuse density 1.0 ⇒ linear transmission 10^-1 = 0.1
        // (the publishers' granularity aperture convention).
        let gray: Float = 0.1
        var pixels = [Float](repeating: 0, count: side * side * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = gray
            pixels[i + 1] = gray
            pixels[i + 2] = gray
            pixels[i + 3] = 1.0
        }
        var params = GrainModule.Params()
        params.strength = Float(strength)
        let module = GrainModule(imageIdentity: UUID(
            uuidString: "A92A6411-CA00-4000-8000-000000000001")!)
        var piece = IOPiece()
        piece.dscIn = IOPBufferDesc(width: side, height: side)
        piece.dscOut = piece.dscIn
        piece.iscale = 1.0
        module.commitParams(params, into: &piece)
        let inTexture = makeTexture(metal, width: side, height: side)
        let outTexture = makeTexture(metal, width: side, height: side)
        pixels.withUnsafeBytes {
            inTexture.replace(
                region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: side * 16)
        }
        let roi = ROI(x: 0, y: 0, width: side, height: side, scale: 1.0)
        try await module.process(
            input: inTexture, output: outTexture, roiIn: roi, roiOut: roi,
            piece: &piece, metal: metal)
        await drain(metal) // L014
        var out = [Float](repeating: 0, count: side * side * 4)
        out.withUnsafeMutableBytes {
            outTexture.getBytes(
                $0.baseAddress!, bytesPerRow: side * 16,
                from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        }
        return out
    }

    /// The 48 µm aperture's box-filter density scan (the
    /// microdensitometer simulation): mean the LINEAR transmission over
    /// each box, convert to density, and return the RMS of the density
    /// deviations × 1000 (the publishers' scale).
    ///
    /// SIMPLIFIED APERTURE (DECISIONS-registered): the box rides the
    /// render lattice at 6×6 px — the default-scale grain's sampling
    /// equivalent of the 48 µm window at the digitization magnification;
    /// the absolute aperture calibration is approximate, the RELATIVE
    /// ordering (what the strength axis moves) is exact.
    private static func boxDensityRms(
        _ pixels: [Float], side: Int, box: Int = 6
    ) -> Double {
        precondition(pixels.count == side * side * 4)
        var densities = [Double]()
        densities.reserveCapacity((side - box) * (side - box))
        let step = 2  // decimate the scan (the RMS is stationary)
        for y0 in stride(from: 0, to: side - box, by: step) {
            for x0 in stride(from: 0, to: side - box, by: step) {
                var sum = 0.0
                for dy in 0..<box {
                    for dx in 0..<box {
                        let i = ((y0 + dy) * side + (x0 + dx)) * 4
                        sum += Double(pixels[i])
                    }
                }
                let meanTransmission = sum / Double(box * box)
                densities.append(-Foundation.log10(max(meanTransmission, 1e-9)))
            }
        }
        let n = Double(densities.count)
        let mean = densities.reduce(0, +) / n
        let variance = densities.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return Foundation.sqrt(variance) * 1000
    }

    // MARK: - 1: the one-shot calibration probe (PERF_PROBE-gated)

    func testCalibrationProbeSolvesRecommendedStrengths() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIGHTAMER_PERF_PROBE"] == "1",
            "the one-shot calibration probe (run with LIGHTAMER_PERF_PROBE=1)")
        let metal = try await makeMetal()

        // The sweep: 21 strengths across the domain.
        var curve: [(Double, Double)] = []
        for s in stride(from: 0.0, through: 100.0, by: 5.0) {
            let out = try await runGrainGray(s, metal: metal)
            let rms = Self.boxDensityRms(out, side: 512)
            curve.append((s, rms))
            print("M92-GRAIN-PROBE|strength \(s)|boxRMS \(rms)")
        }
        // Monotone segments sanity (the inverse premise).
        for (a, b) in zip(curve, curve.dropFirst()) {
            XCTAssertTrue(b.1 >= a.1 - 0.05,
                          "the strength axis is monotone in the box RMS "
                            + "(\(a) → \(b))")
        }
        // The inverse interpolation onto each published RMS.
        let published: [String: Int] = [
            "kodak_tri_x_400": 17, "kodak_tmax_100": 8,
            "fujifilm_neopan_acros_100_ii": 7,
        ]
        for (id, target) in published {
            let solved = Self.interpolate(curve, onto: Double(target))
            print("M92-GRAIN-PROBE|\(id)|published \(target)|solved strength \(solved)")
            XCTAssertNotNil(solved, "\(id): the target is inside the sweep band")
        }
    }

    private static func interpolate(
        _ curve: [(Double, Double)], onto target: Double
    ) -> Double? {
        // Linear interpolation on the first bracketing segment (the
        // curve is monotone above the noise floor).
        for (a, b) in zip(curve, curve.dropFirst()) {
            if a.1 <= target && target <= b.1 && b.1 > a.1 {
                let t = (target - a.1) / (b.1 - a.1)
                return a.0 + t * (b.0 - a.0)
            }
        }
        return nil
    }

    // MARK: - 2: the semantics gate (always on)

    func testRecommendedStrengthsReproducePublishedRmsInBand() async throws {
        let metal = try await makeMetal()
        let table = try GrainCalibration.load(url: tableURL)
        // The band: ±2.0 on the 1000× scale (the aperture simplification
        // + the render-lattice sampling — the measured residuals and the
        // band's rationale are registered in M9-2-DECISIONS).
        let band = 2.0
        for id in ["kodak_tri_x_400", "kodak_tmax_100",
                   "fujifilm_neopan_acros_100_ii"] {
            let entry = try XCTUnwrap(table[id], "\(id): in the table")
            let target = try XCTUnwrap(entry.publishedRms)
            let strength = try XCTUnwrap(
                entry.recommendedStrength, "\(id): recommendation present")
            let out = try await runGrainGray(strength, metal: metal)
            let rms = Self.boxDensityRms(out, side: 512)
            XCTAssertLessThanOrEqual(
                abs(rms - Double(target)), band,
                "\(id): recommended strength \(strength) reproduces the "
                    + "published RMS \(target) (measured \(rms))")
        }
    }
}
