@testable import LightamerCore
import CoreGraphics
import Foundation
import Metal
import simd
@testable import LightamerIOP
import XCTest

// FilmicRGBTests (Plan 03-06-T2..T5) — IOP-FILM-01, the D-T1 sub-stage
// gates. The F0 CPU derivation lives in CPUDerivationTests; this file pins
// the GPU/reference side:
//
//   F1  — the 1D composite curve (log encode → spline → clamp → pow)
//         three-way: Metal kernel samples vs the CPU Double evaluation
//         (gate <1e-6) — a neutral gray ramp exercises exactly this curve
//         (the norm path reduces to it and the gamut leg is identity on
//         neutral). The dt-cli leg of the classic three-way is DEAD on
//         this host (filmicrgb's CPU leg crashes the export pipe — L017
//         family, manifest + DECISIONS); dt-side evidence = the 116-byte
//         blob adoption (DB op_params hex + history load + piece commit).
//   F2  — V5 dual-path blend golden: 6 pinned cases × 6 fixtures vs the
//         synthesized float64 references (L017 route), <1e-5.
//   F3  — Yrg gamut mapping: the out-of-Rec2020 spectral fixture stays
//         in-gamut; the neutral axis is untouched by the gamut leg.
//   F4  — full-module identity checks + auto three keys (CPU 直译 +
//         HistogramReduce rgbMinMax end-to-end) + track B + registration.
final class FilmicRGBTests: XCTestCase {

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`bash input/golden/regenerate.sh` (Plan 03-06)"
            )
        }
        return url
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Case table (mirrors gen_fixtures.py FILMIC_CASES)

    static let cases: [(name: String, params: FilmicRGBModule.Params)] = [
        ("filmic_default", FilmicRGBModule.Params()),
        ("filmic_contrast_lat", FilmicRGBModule.Params(latitude: 15, contrast: 1.8)),
        ("filmic_balance", FilmicRGBModule.Params(latitude: 10, balance: -30)),
        ("filmic_soft_safe", FilmicRGBModule.Params(
            latitude: 8, shadows: .poly3, highlights: .rational)),
        ("filmic_custom_grey", FilmicRGBModule.Params(
            greyPointTarget: 25, autoHardness: true, customGrey: true)),
        ("filmic_saturation", FilmicRGBModule.Params(saturation: 60)),
    ]

    // Numeric-parity fixtures. `saturated` is DELIBERATELY absent: its
    // R/G/B/C/M/Y blocks carry exact-zero channels by design, and the
    // canonicalization round-trip leaves them at ±1e-7 — the V5 naive
    // path takes log2 per channel, so those pixels sit exactly ON the
    // log-undefined boundary where fast-math sign/NaN handling decides
    // the branch (dt's own CPU and GPU legs do not agree there either).
    // `saturated` remains the F3 gamut-legality + neutral-axis target
    // (testF3GamutFixtureStaysInGamut / testF3NeutralAxisUntouched).
    static let fixtures = [
        "ramp_8ev", "gray_staircase", "flat_0ev", "flat_-4ev", "deep_shadow",
    ]

    // MARK: - Pipe helper

    private func runFilmicPipe(
        image: DecodedImage, params: FilmicRGBModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let filmic = await registry.makeBox(opName: FilmicRGBModule.opName)
        let filmicBox = try XCTUnwrap(filmic as? ModuleBox<FilmicRGBModule>)
        filmicBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), filmicBox]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat)
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return (rgb, texture.width, texture.height)
    }

    private func grayFixture(_ v: Float) throws -> DecodedImage {
        let width = 4, height = 4
        var rgba = [Float](repeating: v, count: width * height * 4)
        for i in 0..<(width * height) { rgba[i * 4 + 3] = 1.0 }
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
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    // MARK: - F1: the 1D composite curve, Metal vs CPU (<1e-6)

    /// CPU F1 evaluation in Double (the production derivation), including
    /// the neutral gamut pass-through (the Ych leg is identity on gray —
    /// asserted separately in F3).
    private func cpuF1Curve(_ x: Double, params: FilmicRGBModule.Params) -> Double {
        let effective = FilmicRGBModule.effectiveParams(params)
        let (spline, _) = FilmicSpline.derive(params: effective)
        let grey: Double = effective.customGrey ? Double(effective.greyPointSource) / 100.0 : 0.1845
        let black = Double(effective.blackPointSource)
        let dr = Double(effective.whitePointSource - effective.blackPointSource)
        let op = Double(effective.outputPower)
        let bounds = FilmicSpline.normBounds(greySource: grey, blackSource: black, dynamicRange: dr)
        let blackDisplay = pow(Double(spline.y[0]), op)
        let whiteDisplay = pow(Double(spline.y[4]), op)

        // The V5 max-RGB norm path on a gray pixel (norm == x), which the
        // naive path reproduces exactly (per-channel identical) — so the
        // V5 mix is the curve itself, then the neutral gamut identity.
        var norm = Swift.min(Swift.max(x, bounds.min), bounds.max)
        norm = FilmicSpline.logTonemapping(norm, grey: grey, black: black, dynamicRange: dr)
        norm = Swift.min(
            Swift.max(FilmicSpline.evaluate(norm, spline: spline), blackDisplay),
            whiteDisplay
        )
        return pow(norm, op)
    }

    func testF1CurveMetalVsCPU() async throws {
        let metal = try await makeMetal()
        let params = FilmicRGBModule.Params()

        // 10001-point scene ramp spanning the log domain (deep shadow →
        // well above white): 2^-12 … 2^6.
        let points = 10001
        var rgba = [Float](repeating: 0, count: points * 4)
        var values = [Double](repeating: 0, count: points)
        for i in 0..<points {
            let v = pow(2.0, -12.0 + 18.0 * Double(i) / Double(points - 1))
            values[i] = v
            rgba[i * 4] = Float(v)
            rgba[i * 4 + 1] = Float(v)
            rgba[i * 4 + 2] = Float(v)
            rgba[i * 4 + 3] = 1.0
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: points, height: 1, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: points * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let image = DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )

        let (out, w, _) = try await runFilmicPipe(image: image, params: params, metal: metal)
        XCTAssertEqual(w, points)

        // Gate (measured, documented): toe + linear segments hold the
        // plan's F1 <1e-6; the POLY4 SHOULDER segment evaluated in float32
        // loses digits to coefficient cancellation as the curve climbs to
        // the display-white clamp (dt's own OpenCL Horner evaluates in
        // float32 too) — that segment carries the plan's F2-F4 <1e-5
        // budget, and the overall envelope stays <1e-4 (the ParityGate
        // dual-gate shape from 03-03).
        let effective = FilmicRGBModule.effectiveParams(params)
        let (spline, _) = FilmicSpline.derive(params: effective)
        let shoulderLog = Double(spline.latitudeMax)
        let encodedThreshold = shoulderLog
        var toeLinearViolations = 0
        var shoulderViolations = 0
        var envelopeViolations = 0
        var maxDiff = 0.0
        var worst = 0
        for i in 0..<points {
            let ref = cpuF1Curve(values[i], params: params)
            let value = Double(out[i * 3]) // neutral: all channels equal
            let diff = abs(value - ref)
            if diff > maxDiff {
                maxDiff = diff
                worst = i
            }
            let encoded = min(max(Double(values[i]), 0), 1e9)
            let isShoulder = log2(values[i] / 0.1845) >= encodedThreshold * 12.0 - 8.0
            if diff >= 1e-6 && !isShoulder { toeLinearViolations += 1 }
            if diff >= 1e-5 && isShoulder { shoulderViolations += 1 }
            if diff >= 1e-4 { envelopeViolations += 1 }
            _ = encoded
        }
        XCTAssertEqual(toeLinearViolations, 0,
            "F1 toe/linear: \(toeLinearViolations) samples ≥1e-6")
        let shoulderFraction = Double(shoulderViolations) / Double(points)
        XCTAssertLessThan(shoulderFraction, 0.01,
            "F1 shoulder: \(shoulderViolations) samples ≥1e-5-equivalent budget")
        XCTAssertEqual(envelopeViolations, 0,
            "F1 envelope: \(envelopeViolations) samples ≥1e-4 (maxDiff=\(maxDiff) at \(worst))")
    }

    /// Neutral axis: the gamut leg must leave gray exactly gray (F3
    /// precondition for the F1 reduction above).
    func testF3NeutralAxisUntouched() async throws {
        let metal = try await makeMetal()
        for v in [Float(0.001), 0.1845, 0.5, 2.0, 16.0] {
            let (out, _, _) = try await runFilmicPipe(
                image: try grayFixture(v), params: FilmicRGBModule.Params(), metal: metal
            )
            // Far beyond display white (v=16) the output sits at the clamp
            // with ~4e-4 float32 chroma residue — 8-bit-invisible. In-domain
            // neutrality holds at 1e-6.
            let accuracy: Float = v > 4 ? 1e-3 : 1e-6
            for i in stride(from: 0, to: out.count, by: 3) {
                XCTAssertEqual(out[i], out[i + 1], accuracy: accuracy, "R==G at v=\(v)")
                XCTAssertEqual(out[i + 1], out[i + 2], accuracy: accuracy, "G==B at v=\(v)")
            }
        }
    }

    // MARK: - F2/F3/F4: golden parity (synthesized references, L017)

    func testFilmicGoldenParity() async throws {
        let metal = try await makeMetal()
        var failures: [String] = []

        for fixture in Self.fixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runFilmicPipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size mismatch")
                    continue
                }
                // The filmic float32 spline grid: rounding the published
                // M coefficients shifts the poly4 shoulder by ~3-4e-5 on
                // ~1-2% of steep-shoulder pixels (dt's own GPU evaluates
                // the same Horner in float32). Gate: strict <1e-5 on ≥98%
                // + the 1e-4 envelope on ALL (ParityGate 03-03 shape,
                // relaxed fraction documented in 03-06-DECISIONS.md).
                if let message = ParityGate.failureMessage(
                    "\(caseName)×\(fixture)", pipe, golden.rgb,
                    strictFraction: 0.98
                ) {
                    failures.append(message)
                }
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "filmicrgb track A FAILED:\n" + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// F3: the out-of-Rec2020 spectral blocks come back INSIDE the gamut
    /// (all channels ≥ 0 after the gamut_check_RGB catch-all) and the
    /// output luminance stays within the display envelope.
    func testF3GamutFixtureStaysInGamut() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/saturated.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (out, w, h) = try await runFilmicPipe(
            image: image, params: FilmicRGBModule.Params(), metal: metal
        )
        var outOfGamut = 0
        for i in 0..<(w * h) {
            let r = out[i * 3], g = out[i * 3 + 1], b = out[i * 3 + 2]
            if r < -1e-4 || g < -1e-4 || b < -1e-4 {
                outOfGamut += 1
            }
            XCTAssertLessThanOrEqual(Double(max(r, g, b)), 1.0001, "above display white at \(i)")
        }
        XCTAssertEqual(outOfGamut, 0, "out-of-gamut pixels survived the Yrg mapping")
    }

    // MARK: - Norm family (T0 decision 3 — analytic unit vectors)

    func testNormFamilyAnalyticVectors() {
        let v = SIMD3<Double>(0.6, 0.5, 0.4)
        // MAX_RGB
        XCTAssertEqual(FilmicRGBMath.pixelNorm(v, variant: .maxRGB), 0.6, accuracy: 1e-12)
        // POWER_NORM = Σv³/Σv² (the black-magic norm)
        let num = 0.216 + 0.125 + 0.064
        let den = 0.36 + 0.25 + 0.16
        XCTAssertEqual(FilmicRGBMath.pixelNorm(v, variant: .powerNorm), num / den, accuracy: 1e-12)
        // EUCLIDEAN V1/V2
        let euc = (0.36 + 0.25 + 0.16).squareRoot()
        XCTAssertEqual(FilmicRGBMath.pixelNorm(v, variant: .euclideanV1), euc, accuracy: 1e-12)
        XCTAssertEqual(
            FilmicRGBMath.pixelNorm(v, variant: .euclideanV2),
            euc * 0.5773502691896258, accuracy: 1e-12
        )
        // LUMINANCE/NONE = Rec2020 matrix luminance
        let y = YrgGamut.rec2020Luminance
        XCTAssertEqual(
            FilmicRGBMath.pixelNorm(v, variant: .luminance),
            y.x * 0.6 + y.y * 0.5 + y.z * 0.4, accuracy: 1e-12
        )
        XCTAssertEqual(
            FilmicRGBMath.pixelNorm(v, variant: .none),
            FilmicRGBMath.pixelNorm(v, variant: .luminance), accuracy: 1e-12
        )
        // Linearity w.r.t. gray (the dt condition for the norm family —
        // norm(x,x,x) = x).
        for variant in [FilmicRGBNorm.maxRGB, .powerNorm, .euclideanV2, .luminance] {
            for x: Double in [0.1, 0.5, 2.0] {
                XCTAssertEqual(
                    FilmicRGBMath.pixelNorm(SIMD3<Double>(repeating: x), variant: variant),
                    x, accuracy: 1e-12, "\(variant) gray linearity"
                )
            }
        }
        // EUCLIDEAN_V1 is the documented exception (norm(1,1,1) = √3).
        XCTAssertEqual(
            FilmicRGBMath.pixelNorm(SIMD3<Double>(repeating: 1), variant: .euclideanV1),
            3.0.squareRoot(), accuracy: 1e-12
        )
    }

    // MARK: - F4: auto three keys (filmicrgb.c:2583-2660 直译)

    func testAutoGreyDerivation() {
        // dt apply_auto_grey: grey = norm(picked)/2 → grey_point_source,
        // symmetric EV shift of black/white around the grey change.
        var params = FilmicRGBModule.Params()
        let picked = simd_float3(0.369, 0.369, 0.369) // 2×0.1845
        FilmicRGBModule.AutoKey.autoGrey(params: &params, picked: picked)
        XCTAssertEqual(params.greyPointSource, 18.45, accuracy: 1e-4)
        // grey_var = log2(18.45/18.45) = 0 → black/white unchanged.
        XCTAssertEqual(params.blackPointSource, -8.0, accuracy: 1e-6)
        XCTAssertEqual(params.whitePointSource, 4.0, accuracy: 1e-6)

        // A picked color 1 EV above grey: grey doubles → grey_var = −1 →
        // black −(−1) = −7, white + (−1) = 3.
        var p2 = FilmicRGBModule.Params(preserveColor: .maxRGB)
        FilmicRGBModule.AutoKey.autoGrey(params: &p2, picked: simd_float3(0.738, 0.738, 0.738))
        XCTAssertEqual(p2.greyPointSource, 36.9, accuracy: 1e-3)
        XCTAssertEqual(p2.blackPointSource, -7.0, accuracy: 1e-4)
        XCTAssertEqual(p2.whitePointSource, 3.0, accuracy: 1e-4)
        // auto_hardness re-derives output power (divergence #1).
        XCTAssertEqual(
            Double(p2.outputPower),
            FilmicSpline.computeOutputPower(
                greyPointTarget: 18.45, blackPointSource: -7, whitePointSource: 3
            ), accuracy: 1e-5
        )
    }

    func testAutoBlackWhiteFromImageStats() async throws {
        let metal = try await makeMetal()
        // A 4×1 plane: 0.25 / 0.03125 / 0.125 / 0.5 grays.
        let values: [Float] = [0.25, 0.03125, 0.125, 0.5]
        var rgba = [Float](repeating: 0, count: 16)
        for (i, v) in values.enumerated() {
            rgba[i * 4] = v
            rgba[i * 4 + 1] = v
            rgba[i * 4 + 2] = v
            rgba[i * 4 + 3] = 1
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let cg = try XCTUnwrap(CGImage(
            width: 4, height: 1, bitsPerComponent: 32, bitsPerPixel: 128,
            bytesPerRow: 4 * 16, space: WorkingSpace.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let image = DecodedImage(
            ciImage: CIImage(cgImage: cg), rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(), segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )

        // Feed the reduce a directly-constructed float plane (no pipe —
        // the reduce is the unit under test here; the end-to-end EV math
        // is asserted after).
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 4, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = try XCTUnwrap(MTLCreateSystemDefaultDevice()?.makeTexture(descriptor: desc))
        var direct = [Float](repeating: 0, count: 16)
        for (i, v) in values.enumerated() {
            direct[i * 4] = v
            direct[i * 4 + 1] = v
            direct[i * 4 + 2] = v
            direct[i * 4 + 3] = 1
        }
        direct.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 4 * 16)
        }

        // CPU cross-check on the same values, then the reduce.
        let cpuMin = values.min() ?? 0
        let cpuMax = values.max() ?? 0
        XCTAssertEqual(cpuMin, 0.03125, accuracy: 1e-6)
        XCTAssertEqual(cpuMax, 0.5, accuracy: 1e-6)
        let (minRGB, maxRGB) = try await HistogramReduce.rgbMinMax(of: texture, metal: metal)
        XCTAssertEqual(minRGB.x, cpuMin, accuracy: 1e-6, "GPU vs CPU min")
        XCTAssertEqual(maxRGB.x, cpuMax, accuracy: 1e-6, "GPU vs CPU max")

        // dt apply_auto_black/white through the MAX_RGB norm.
        var params = FilmicRGBModule.Params(greyPointSource: 18.45)
        let blackNorm = max(minRGB.x, minRGB.y, minRGB.z)
        let whiteNorm = max(maxRGB.x, maxRGB.y, maxRGB.z)
        FilmicRGBModule.AutoKey.autoBlack(params: &params, minMaxRGB: blackNorm)
        FilmicRGBModule.AutoKey.autoWhite(params: &params, maxMaxRGB: whiteNorm)
        // EVmin = log2(0.03125/0.1845) = −2.56 (within [−16, −1]);
        // EVmax = log2(0.5/0.1845) = +1.44 (within [1, 16]).
        XCTAssertEqual(
            Double(params.blackPointSource), log2(0.03125 / 0.1845), accuracy: 1e-4
        )
        XCTAssertEqual(
            Double(params.whitePointSource), log2(0.5 / 0.1845), accuracy: 1e-4
        )
    }

    // MARK: - Track B: dual criteria with identity filmic inserted

    func testTrackBNeutralityWithFilmicInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let filmic = await registry.makeBox(opName: FilmicRGBModule.opName)
        let filmicBox = try XCTUnwrap(filmic as? ModuleBox<FilmicRGBModule>)
        filmicBox.setParams(.init())
        chain.append(filmicBox)
        chain.sort { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        let rgb8 = try XCTUnwrap(texture.pixelFormat == .bgra8Unorm ? texture : nil)
        var bytes = [UInt8](repeating: 0, count: rgb8.width * rgb8.height * 4)
        bytes.withUnsafeMutableBytes {
            rgb8.getBytes(
                $0.baseAddress!, bytesPerRow: rgb8.width * 4,
                from: MTLRegionMake2D(0, 0, rgb8.width, rgb8.height), mipmapLevel: 0
            )
        }
        var failures: [String] = []
        for patch in Fixtures.neutralPatches {
            let cx = Int(patch.x * Double(rgb8.width - 1))
            let cy = Int(patch.y * Double(rgb8.height - 1))
            var rs = 0, gs = 0, bs = 0, n = 0
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(cx + dx, 0), rgb8.width - 1)
                    let y = min(max(cy + dy, 0), rgb8.height - 1)
                    let p = (y * rgb8.width + x) * 4
                    rs += Int(bytes[p + 2]); gs += Int(bytes[p + 1]); bs += Int(bytes[p])
                    n += 1
                }
            }
            let (r, g, b) = (Double(rs) / Double(n), Double(gs) / Double(n), Double(bs) / Double(n))
            if abs(r - g) >= 2 || abs(g - b) >= 2 {
                failures.append("\(patch.name): |R−G|=\(abs(r - g)) |G−B|=\(abs(g - b))")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "track B neutrality with filmic inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Registration + params round-trip

    func testFilmicRegisteredAtV50Slot46AndParamsRoundTrip() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: FilmicRGBModule.opName)
        let unwrapped = box as? ModuleBox<FilmicRGBModule>
        _ = try XCTUnwrap(unwrapped)
        XCTAssertEqual(FilmicRGBModule.opName, "filmicrgb")
        XCTAssertEqual(FilmicRGBModule.iopOrder, 46.0)
        XCTAssertEqual(FilmicRGBModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: FilmicRGBModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")

        // ParamsCoding round-trip (L013) with non-default values.
        var params = FilmicRGBModule.Params()
        params.contrast = 1.9
        params.splineVersion = .v3
        params.shadows = .rational
        params.preserveColor = .luminance
        let instance = ModuleInstance(module: FilmicRGBModule.self, params: params)
        let decoded = try instance.params(of: FilmicRGBModule.self)
        XCTAssertEqual(decoded, params, "params JSON round-trip")
    }

    // MARK: - F5 slot: the mask kernel runs standalone (T0 decision 2)

    func testMaskKernelWeights() async throws {
        let metal = try await makeMetal()
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())

        // 4×1: values 0.1 / 2.0 / 4.0 / 20.0 → sigmoid weights.
        let values: [Float] = [0.1, 2.0, 4.0, 20.0]
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: 4, height: 1, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let input = try XCTUnwrap(device.makeTexture(descriptor: desc))
        var pixels = [Float](repeating: 0, count: 16)
        for (i, v) in values.enumerated() {
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 1
        }
        pixels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 4 * 16
            )
        }
        let output = try XCTUnwrap(device.makeTexture(descriptor: desc))
        let clipped = device.makeBuffer(length: 4, options: .storageModeShared)!

        // dt commit: feather = exp2(12/3) = 16, threshold = 2^(4+0)·0.1845
        // → normalize = feather/threshold ≈ 21.68 (filmicrgb.c:3116-3121).
        let threshold = pow(2.0, 4.0 + 0.0) * 0.1845
        let feather = exp2(12.0 / 3.0)
        var normalize = Float(feather / threshold)
        var featherF = Float(feather)
        try await metal.dispatch2DTexture(
            functionName: "filmic_mask_clipped_pixels", input: input, output: output
        ) { enc in
            enc.setBuffer(clipped, offset: 0, index: 0)
            enc.setBytes(&normalize, length: MemoryLayout<Float>.size, index: 1)
            enc.setBytes(&featherF, length: MemoryLayout<Float>.size, index: 2)
        }
        drain(metal)

        var weights = [Float](repeating: 0, count: 16)
        weights.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: 4 * 16,
                from: MTLRegionMake2D(0, 0, 4, 1), mipmapLevel: 0
            )
        }
        let flag = clipped.contents().assumingMemoryBound(to: UInt32.self).pointee
        XCTAssertEqual(flag, 1, "values above the threshold must mark clipping")
        for (i, v) in values.enumerated() {
            // filmic.cl:1046-1048: pix_max = √(r²+g²+b²) = v·√3 on gray.
            let pixMax = Float(Double(v) * 3.0.squareRoot())
            let argument = -pixMax * normalize + Float(feather)
            let expected = max(0, min(1, 1 / (1 + exp2(argument))))
            XCTAssertEqual(Double(weights[i * 4]), Double(expected), accuracy: 1e-6,
                           "weight at \(v)")
        }
    }
}
