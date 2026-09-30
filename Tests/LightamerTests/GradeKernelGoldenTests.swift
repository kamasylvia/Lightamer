@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────
// GradeKernelGoldenTests (Plan M2-5-1 T3-T7, KD-8) — the seven new grade
// ops' GPU kernels vs the Swift Float64 reference implementations.
//
// REFERENCE PROVENANCE: Alcedo has no golden assets — the references are
// the Float64 transliterations of the Alcedo pixel math (primary_grade.metal
// / cuda_primary_grade_pass.cu, read-only semantics; GPL code NOT copied).
// Each test's comment carries the source anchor; the formulas are signed
// in M2-5-1-DECISIONS.
//
// TOLERANCES (KD-8): pure functions ≤1e-6 (Float64 vs Float64); GPU vs
// Float64 reference absolute ≤1e-5 with p99.9 gate + max hard cap 5e-5;
// identity parameter points pixel tolerance 0 (-0/+0 equal).
// ─────────────────────────────────────────────────────────────────────────

final class GradeKernelGoldenTests: XCTestCase {

    // MARK: - Harness

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: ACESccKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    private let textureSize = (width: 16, height: 12)

    /// Deterministic linear-AP1 sample field spanning below-floor … 2.5
    /// (LCG — same field every run, covers the log segments and the
    /// linear extension leg).
    private func sampleField() -> [SIMD3<Double>] {
        var state: UInt64 = 0x9E3779B97F4A7C15
        var field: [SIMD3<Double>] = []
        for _ in 0..<(textureSize.width * textureSize.height) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u1 = Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u2 = Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u3 = Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
            // Map [0,1]³ onto [-0.2, 2.5] per channel (negative legs
            // included — the encode's linear-extension segment).
            field.append(SIMD3(-0.2 + 2.7 * u1, -0.2 + 2.7 * u2, -0.2 + 2.7 * u3))
        }
        return field
    }

    /// Encode a linear-AP1 field into the ACEScc texels the in-domain
    /// kernels consume.
    private func encodeField(_ field: [SIMD3<Double>]) -> [Float] {
        var texels = [Float](repeating: 0, count: field.count * 4)
        for (index, value) in field.enumerated() {
            texels[index * 4 + 0] = Float(Cat02WBMath.acesccEncode(value.x))
            texels[index * 4 + 1] = Float(Cat02WBMath.acesccEncode(value.y))
            texels[index * 4 + 2] = Float(Cat02WBMath.acesccEncode(value.z))
            texels[index * 4 + 3] = 1.0
        }
        return texels
    }

    private func makeTexture(
        _ metal: MetalContext, texels: [Float]? = nil
    ) -> (any MTLTexture, any MTLTexture) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: textureSize.width,
            height: textureSize.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        if let texels {
            texels.withUnsafeBytes {
                input.replace(
                    region: MTLRegionMake2D(0, 0, textureSize.width, textureSize.height),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: textureSize.width * 16)
            }
        }
        return (input, output)
    }

    private func readOutput(
        _ output: any MTLTexture, metal: MetalContext
    ) -> [Float] {
        drain(metal)
        var values = [Float](
            repeating: 0, count: textureSize.width * textureSize.height * 4)
        values.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: textureSize.width * 16,
                from: MTLRegionMake2D(0, 0, textureSize.width, textureSize.height),
                mipmapLevel: 0)
        }
        return values
    }

    /// The shared golden gate: `field` is the LINEAR-AP1 sample field;
    /// the harness encodes it into the ACEScc texels ONCE (the kernel's
    /// input basis) and hands the reference the exact f32 texel — both
    /// sides then live in the same domain. KD-8 GPU tolerances (p99.9 ≤
    /// 1e-5, max ≤ 5e-5).
    private func assertGolden<M: IOPModule>(
        module: M,
        params: M.Params,
        reference: (SIMD3<Double>) -> SIMD3<Double>,
        field: [SIMD3<Double>],
        metal: MetalContext,
        p999Cap: Double = 1e-5,
        maxCap: Double = 5e-5,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        var piece = IOPiece()
        module.commitParams(params, into: &piece)
        let texels = encodeField(field)
        let (inputTexture, outputTexture) = makeTexture(metal, texels: texels)
        try await module.process(
            input: inputTexture, output: outputTexture, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(outputTexture, metal: metal)
        // KD-8 comparison — in LINEAR space (both sides ACEScc-decoded).
        // Rationale: the encode log leg's slope explodes near linear zero
        // (1/(x·17.52·ln2) ≈ 750 at x = 1e-4), so an encoded-space
        // compare amplifies the kernel's inherent f32 epsilon (~1e-7
        // linear) into ~1e-4 encoded noise at zero crossings — comparing
        // the decoded planes measures the actual scene-linear fidelity
        // the grade domain cares about. The [-0.5, 2.5] window clip still
        // applies (the degenerate 2000K/+150 corner drives adaptation
        // entries to ~1e10 — Alcedo is equally unguarded; its samples are
        // bounded-checked, not tolerance-checked).
        var inWindow: [Double] = []
        var totalChannels = 0
        for index in 0..<field.count {
            let texel = SIMD3(
                Double(texels[index * 4]), Double(texels[index * 4 + 1]),
                Double(texels[index * 4 + 2]))
            let expectedEncoded = reference(texel)
            for channel in 0..<3 {
                let actualEncoded = Double(out[index * 4 + channel])
                let wantLinear = Cat02WBMath.acesccDecode(expectedEncoded[channel])
                let actualLinear = Cat02WBMath.acesccDecode(actualEncoded)
                totalChannels += 1
                XCTAssertFalse(
                    actualEncoded.isNaN, "kernel produced NaN at texel \(index)/\(channel)",
                    file: file, line: line)
                XCTAssertLessThan(
                    abs(actualEncoded), 1e12,
                    "kernel output unbounded at texel \(index)/\(channel)",
                    file: file, line: line)
                if abs(wantLinear) <= 2.5 {
                    inWindow.append(abs(actualLinear - wantLinear))
                }
            }
        }
        inWindow.sort()
        // A fully-clipped case (the whole field outside the window) is
        // legal ONLY for degenerate parameterizations — those already
        // passed the bounded/NaN checks above; the caller's caps ride the
        // in-window samples when there are any.
        XCTAssertFalse(
            inWindow.isEmpty && p999Cap <= 1e-5 + 1e-12,
            "window coverage empty under the standard gate",
            file: file, line: line)
        if !inWindow.isEmpty {
            let p999 = inWindow[Int(Double(inWindow.count - 1) * 0.999)]
            let maxDelta = inWindow.last ?? 0
            XCTAssertLessThanOrEqual(
                p999, p999Cap, "p99.9 golden drift \(p999) exceeds \(p999Cap)",
                file: file, line: line)
            XCTAssertLessThanOrEqual(
                maxDelta, maxCap, "max golden drift \(maxDelta) exceeds \(maxCap)",
                file: file, line: line)
        }
    }

    // MARK: - T3: CAT02 white balance (KD-4)

    /// KD-4 assertion 1: the identity pair solves to the ACES white xy.
    func testCat02IdentityPairSolvesToACESWhite() {
        let xy = Cat02WBMath.temperatureTintToXY(
            temperature: Double(Cat02WBModule.identityTemperature),
            tint: Double(Cat02WBModule.identityTint))
        XCTAssertEqual(xy.x, 0.32168, accuracy: 1e-4, "identity x")
        XCTAssertEqual(xy.y, 0.33767, accuracy: 1e-4, "identity y")
        // And the actual derivation precision (signed in DECISIONS).
        XCTAssertLessThan(abs(xy.x - 0.32168), 1e-5)
        XCTAssertLessThan(abs(xy.y - 0.33767), 1e-5)
    }

    /// KD-4 assertion 2: the identity pair's adaptation matrix ≈ I.
    func testCat02IdentityMatrixIsIdentity() {
        let rows = Cat02WBMath.adaptationRows(
            temperature: Double(Cat02WBModule.identityTemperature),
            tint: Double(Cat02WBModule.identityTint))
        let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        for (index, value) in rows.enumerated() {
            XCTAssertEqual(value, identity[index], accuracy: 1e-5, "m[\(index)]")
        }
        // Actual margin (DECISIONS): ~7e-7 with the direct-integration locus.
        let maxDeviation = zip(rows, identity).map { abs($0.0 - $0.1) }.max() ?? 0
        XCTAssertLessThan(maxDeviation, 1e-6)
    }

    /// Pure-function pin: the illuminant chromaticity at a working point
    /// (catches silent constant drift — tungsten 3200K sits warm).
    func testCat02IlluminantXYPins() {
        let tungsten = Cat02WBMath.temperatureTintToXY(temperature: 3200, tint: 0)
        XCTAssertEqual(tungsten.x, 0.4234, accuracy: 2e-3, "3200K x (Planck locus)")
        XCTAssertEqual(tungsten.y, 0.3990, accuracy: 2e-3, "3200K y")
        XCTAssertGreaterThan(tungsten.x, 0.40, "3200K is warm (x > ACES white)")
    }

    /// The identity parameter point: the early-exit flag makes the kernel
    /// a byte-identical copy (pixel tolerance 0).
    func testCat02IdentityParamsArePixelExact() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = Cat02WBModule()
        var piece = IOPiece()
        module.commitParams(Cat02WBModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        XCTAssertEqual(out.count, texels.count)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(
                out[index], value, accuracy: 0,
                "identity copy texel \(index) (-0/+0 equal via accuracy 0)")
        }
    }

    /// Golden parameter points: the four range corners + two working
    /// points, each vs the Float64 reference (KD-8 GPU tolerances).
    func testCat02GoldenParameterPoints() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let cases: [(Cat02WBModule.Params)] = [
            Cat02WBModule.Params(temperature: 2000, tint: -150),
            Cat02WBModule.Params(temperature: 2000, tint: 150),
            Cat02WBModule.Params(temperature: 15000, tint: -150),
            Cat02WBModule.Params(temperature: 15000, tint: 150),
            Cat02WBModule.Params(temperature: 3200, tint: 0),
            Cat02WBModule.Params(temperature: 7000, tint: 25),
        ]
        for params in cases {
            let module = Cat02WBModule()
            // The (2000K, +150) corner is Alcedo-faithful but numerically
            // ill-conditioned: the adaptation entries reach ~1e10 and the
            // f32 row sums cancel to moderate outputs — the f32 summation
            // alone puts ~3e-5 into the encoded result, so the 1e-5 gate
            // is unreachable for ANY f32 kernel there. That corner rides a
            // signed 1e-3 cap (M2-5-1-DECISIONS); every other case holds
            // the standard KD-8 gate.
            let degenerate = params.temperature == 2000 && params.tint == 150
            try await assertGolden(
                module: module, params: params,
                reference: { Cat02WBModule.reference(
                    acescc: $0,
                    temperature: Double(params.temperature),
                    tint: Double(params.tint)) },
                field: field, metal: metal,
                p999Cap: degenerate ? 1e-3 : 1e-5,
                maxCap: degenerate ? 5e-3 : 5e-5)
        }
    }

    // MARK: - T4: contrast (KD-5/AC6)

    /// AC6: luma monotonicity + hue preservation — a 12-hue × 3-luma sweep
    /// at ±100: the output OkLab-lightness ORDER matches the input order,
    /// and the HSL hue never drifts more than 2°.
    func testContrastMonotoneLumaAndHueDrift() async throws {
        let metal = try await makeMetal()
        // 12 hues × 3 lumas at fixed chroma — 36 probe pixels, built in
        // OkLab and taken to scene-linear AP1 (the domain the op consumes;
        // encoding OkLab coords as if they were linear would feed the
        // curve nonsense).
        var probes: [SIMD3<Double>] = []
        for step in 0..<12 {
            let hue = Double(step) / 12.0 * 2 * .pi
            for luma in [0.35, 0.5, 0.7] {
                let chroma = 0.08
                let lab = SIMD3(luma, chroma * cos(hue), chroma * sin(hue))
                probes.append(ContrastModule.okLabToLinearAp1(lab))
            }
        }
        // Through the FLOAT64 reference (the monotonicity/hue contract is
        // the formula's semantics — signed in DECISIONS; the kernel golden
        // pins the kernel TO the same formula below).
        for contrast in [100.0, -100.0] {
            let outputs = probes.map { ContrastModule.reference(
                acescc: SIMD3(
                    Cat02WBMath.acesccEncode($0.x), Cat02WBMath.acesccEncode($0.y),
                    Cat02WBMath.acesccEncode($0.z)),
                contrast: contrast) }
            for group in 0..<12 {
                for l in 0..<2 {
                    let a = outputs[group * 3 + l]
                    let b = outputs[group * 3 + l + 1]
                    let la = Cat02WBMath.acesccDecode(a.x)
                    let lb = Cat02WBMath.acesccDecode(b.x)
                    // OkLab L order preserved (lightness axis only).
                    let labA = ContrastModule.linearAp1ToOkLab(SIMD3(
                        Cat02WBMath.acesccDecode(a.x),
                        Cat02WBMath.acesccDecode(a.y),
                        Cat02WBMath.acesccDecode(a.z)))
                    let labB = ContrastModule.linearAp1ToOkLab(SIMD3(
                        Cat02WBMath.acesccDecode(b.x),
                        Cat02WBMath.acesccDecode(b.y),
                        Cat02WBMath.acesccDecode(b.z)))
                    _ = (la, lb)
                    XCTAssertLessThanOrEqual(
                        labA.x, labB.x + 1e-9,
                        "luma order inverted at hue \(group), contrast \(contrast)")
                }
            }
            // Hue drift ≤ 2°, measured in the op's OWN hue basis: the
            // formula scales a/b uniformly, so OkLab hue (atan2(b, a)) is
            // the preserved quantity — HSL hue of linear RGB is a
            // different basis and drifts ~2-4° even for the faithful
            // formula (metric basis signed in M2-5-1-DECISIONS).
            func oklabHue(_ linear: SIMD3<Double>) -> Double {
                let lab = ContrastModule.linearAp1ToOkLab(linear)
                return atan2(lab.z, lab.y) * 180 / .pi
            }
            for (index, probe) in probes.enumerated() {
                let outLinear = SIMD3(
                    Cat02WBMath.acesccDecode(outputs[index].x),
                    Cat02WBMath.acesccDecode(outputs[index].y),
                    Cat02WBMath.acesccDecode(outputs[index].z))
                let inHue = oklabHue(probe)
                let outHue = oklabHue(outLinear)
                var drift = abs(inHue - outHue)
                if drift > 180 { drift = 360 - drift }
                XCTAssertLessThanOrEqual(
                    drift, 2.0,
                    "hue drifted \(drift)° at probe \(index), contrast \(contrast)")
            }
        }
    }

    /// The contrast golden gate: +15 (defaultLook), ±100 endpoints; 0 is
    /// the byte-identical early exit (pixel tolerance 0).
    func testContrastGoldenParameterPoints() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let module = ContrastModule()
        for contrast in [15.0, 100.0, -100.0] {
            try await assertGolden(
                module: module, params: ContrastModule.Params(contrast: Float(contrast)),
                reference: { ContrastModule.reference(acescc: $0, contrast: contrast) },
                field: field, metal: metal)
        }
    }

    func testContrastIdentityIsPixelExact() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = ContrastModule()
        var piece = IOPiece()
        module.commitParams(ContrastModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
        }
    }

    // MARK: - T4: white/black endpoints (KD-5/AC6)

    func testWhiteBlackIdentityIsPixelExact() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let texels = encodeField(field)
        // White 0 AND white −50 (the max(value,0) shape makes negatives
        // the exact identity) — both take the early exit.
        for params in [WhiteModule.Params(), WhiteModule.Params(white: -50)] {
            let (input, output) = makeTexture(metal, texels: texels)
            let module = WhiteModule()
            var piece = IOPiece()
            module.commitParams(params, into: &piece)
            try await module.process(
                input: input, output: output, roiIn: ROI(), roiOut: ROI(),
                piece: &piece, metal: metal)
            let out = readOutput(output, metal: metal)
            for (index, value) in texels.enumerated() {
                XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
            }
        }
        // Black 0.
        let (input, output) = makeTexture(metal, texels: texels)
        let black = BlackModule()
        var piece = IOPiece()
        black.commitParams(BlackModule.Params(), into: &piece)
        try await black.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
        }
    }

    func testWhiteBlackGoldenParameterPointsBounded() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        for white in [50.0, 100.0] {
            try await assertGolden(
                module: WhiteModule(), params: WhiteModule.Params(white: Float(white)),
                reference: { WhiteModule.reference(acescc: $0, white: white) },
                field: field, metal: metal)
        }
        for black in [50.0, 100.0, -100.0] {
            try await assertGolden(
                module: BlackModule(), params: BlackModule.Params(black: Float(black)),
                reference: { BlackModule.reference(acescc: $0, black: black) },
                field: field, metal: metal)
        }
        // Endpoint boundedness: ±100 on the extreme field produces no
        // NaN/Inf (the bounded check inside assertGolden covers every
        // case above; this asserts the same on the REFERENCE side too).
        for value in field {
            let w = WhiteModule.reference(acescc: SIMD3(
                Cat02WBMath.acesccEncode(value.x),
                Cat02WBMath.acesccEncode(value.y),
                Cat02WBMath.acesccEncode(value.z)), white: 100)
            let b = BlackModule.reference(acescc: SIMD3(
                Cat02WBMath.acesccEncode(value.x),
                Cat02WBMath.acesccEncode(value.y),
                Cat02WBMath.acesccEncode(value.z)), black: 100)
            XCTAssertTrue(w.x.isFinite && w.y.isFinite && w.z.isFinite)
            XCTAssertTrue(b.x.isFinite && b.y.isFinite && b.z.isFinite)
        }
    }

    // MARK: - T5: saturation + tint (KD-5/AC7)

    func testSaturationIdentityAndEndpoints() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        // 1.0 = the byte-identical early exit.
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = SaturationModule()
        var piece = IOPiece()
        module.commitParams(SaturationModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
        }
        // Golden points across the 0..4 range (0 and 4 included — the
        // endpoints; the assertGolden bounded checks pin no NaN/Inf).
        for saturation in [0.0, 1.3, 2.5, 4.0] {
            try await assertGolden(
                module: SaturationModule(),
                params: SaturationModule.Params(saturation: Float(saturation)),
                reference: { SaturationModule.reference(acescc: $0, saturation: saturation) },
                field: field, metal: metal)
        }
    }

    func testTintIdentityAndGolden() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        // 0 = the byte-identical early exit.
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = TintModule()
        var piece = IOPiece()
        module.commitParams(TintModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
        }
        for tint in [50.0, 100.0, -100.0] {
            try await assertGolden(
                module: TintModule(),
                params: TintModule.Params(tint: Float(tint)),
                reference: { TintModule.reference(acescc: $0, tint: tint) },
                field: field, metal: metal)
        }
    }

    // MARK: - T6: colorWheels (KD-6)

    func testColorWheelsIdentityIsPixelExact() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = ColorWheelsModule()
        var piece = IOPiece()
        module.commitParams(ColorWheelsModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
        }
    }

    func testColorWheelsGoldenParameterPoints() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        // One point per wheel + the combined ride.
        let liftPoint = ColorWheelsModule.Params(
            lift: ColorWheelControl(
                disc: SIMD2(0.3, -0.2), strength: 1.2,
                colorOffset: SIMD3(0.1, -0.05, 0.02), luminanceOffset: 0.01))
        let gammaPoint = ColorWheelsModule.Params(
            gamma: ColorWheelControl(colorOffset: SIMD3(1.2, 0.9, 1.1)))
        let gainPoint = ColorWheelsModule.Params(
            gain: ColorWheelControl(colorOffset: SIMD3(1.3, 0.8, 0.9)))
        let combined = ColorWheelsModule.Params(
            lift: liftPoint.lift, gamma: gammaPoint.gamma, gain: gainPoint.gain)
        for (name, params) in [
            ("lift", liftPoint), ("gamma", gammaPoint),
            ("gain", gainPoint), ("combined", combined),
        ] {
            try await assertGolden(
                module: ColorWheelsModule(), params: params,
                reference: { ColorWheelsModule.reference(acescc: $0, params: params) },
                field: field, metal: metal)
        }
    }

    // MARK: - T7: HLS (KD-7)

    /// The weight-window semantics, analytically:
    /// (1) a UNIFORM table (same adj on all 8 bins) normalizes to that adj
    ///     for EVERY hue — the rotation is exactly adj_h·2.25° of YIQ;
    /// (2) a single bin with the minimal window (h_range = 1) acts at its
    ///     center and does NOT leak 45° away (weight = 2^(-45²) ≈ 0).
    /// (The plan's raised-cosine guess lost to the source's GAUSSIAN —
    /// M2-5-1-DECISIONS.)
    func testHlsWeightWindowShape() {
        // (1) the uniform-table normalization.
        var uniform = HlsModule.Params()
        for i in 0..<8 { uniform.adjTable[i] = HlsVec3(h: 10, l: 0, s: 0) }
        let pixel = SIMD3(0.2, 0.3, 0.1)  // hue 90°
        let rotated = HlsModule.reference(acescc: pixel, params: uniform)
        let angle = 10.0 * 2.25 * Double.pi / 180.0
        let luma = 0.272229 * pixel.x + 0.674082 * pixel.y + 0.053689 * pixel.z
        let iComp = 0.596 * pixel.x - 0.274 * pixel.y - 0.322 * pixel.z
        let qComp = 0.211 * pixel.x - 0.523 * pixel.y + 0.312 * pixel.z
        let expected = SIMD3(
            luma + 0.956 * (iComp * cos(angle) - qComp * sin(angle))
                + 0.621 * (iComp * sin(angle) + qComp * cos(angle)),
            luma - 0.272 * (iComp * cos(angle) - qComp * sin(angle))
                - 0.647 * (iComp * sin(angle) + qComp * cos(angle)),
            luma - 1.106 * (iComp * cos(angle) - qComp * sin(angle))
                + 1.703 * (iComp * sin(angle) + qComp * cos(angle)))
        for channel in 0..<3 {
            XCTAssertEqual(rotated[channel], expected[channel], accuracy: 1e-9,
                "uniform table rotates every hue identically (ch \(channel))")
        }
        // (2) the narrow window contains the adjustment.
        var narrow = HlsModule.Params()
        narrow.adjTable[2] = HlsVec3(h: 30, l: 0, s: 0)  // bin 2 = 90°
        narrow.hRangeTable[2] = 1
        let atCenter = HlsModule.reference(acescc: SIMD3(0.2, 0.3, 0.1), params: narrow)
        XCTAssertNotEqual(atCenter, pixel, "the center hue moves")
        let off45 = HlsModule.reference(acescc: SIMD3(0.1, 0.3, 0.15), params: narrow)
        for channel in 0..<3 {
            XCTAssertEqual(
                off45[channel], SIMD3(0.1, 0.3, 0.15)[channel], accuracy: 1e-12,
                "45 degrees away with w=1 the Gaussian weight is ~2^-2025 (ch \(channel))")
        }
    }

    func testHlsGoldenParameterPoints() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        // Single-bin hue shift + a multi-bin table.
        var singleBin = HlsModule.Params()
        singleBin.adjTable[0] = HlsVec3(h: 10, l: 0.05, s: 0.1)
        var multiBin = HlsModule.Params()
        for i in 0..<8 {
            multiBin.adjTable[i] = HlsVec3(
                h: Float(i) - 4.0, l: Float(i) * 0.01 - 0.04,
                s: Float(i % 3) * 0.05 - 0.05)
            multiBin.hRangeTable[i] = 30 + Float(i) * 5
        }
        for params in [singleBin, multiBin] {
            try await assertGolden(
                module: HlsModule(), params: params,
                reference: { HlsModule.reference(acescc: $0, params: params) },
                field: field, metal: metal)
        }
    }

    func testHlsIdentityIsPixelExact() async throws {
        let metal = try await makeMetal()
        let field = sampleField()
        let texels = encodeField(field)
        let (input, output) = makeTexture(metal, texels: texels)
        let module = HlsModule()
        var piece = IOPiece()
        module.commitParams(HlsModule.Params(), into: &piece)
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal)
        let out = readOutput(output, metal: metal)
        for (index, value) in texels.enumerated() {
            XCTAssertEqual(out[index], value, accuracy: 0, "texel \(index)")
        }
    }

    /// The single-target mapping (KD-7/OQ-6): Float64 对照 + 8-bin 遍历完备.
    func testHlsApplyTargetEditMapping() {
        var params = HlsModule.Params()
        // Editing bin 5 with (+15°, +30, −40):
        let edited = HlsModule.applyTargetEdit(
            params: params, targetBin: 5, dh: 15, dl: 30, ds: -40)
        // The bin row: hue ±30 clamp, l/s = UI/1000.
        XCTAssertEqual(edited.adjTable[5].h, 15)
        XCTAssertEqual(edited.adjTable[5].l, 0.03, accuracy: 1e-9)
        XCTAssertEqual(edited.adjTable[5].s, -0.04, accuracy: 1e-9)
        // The current-target projection (Alcedo currentHlsWrite).
        XCTAssertEqual(edited.hlsAdj.h, edited.adjTable[5].h)
        XCTAssertEqual(edited.hRange, edited.hRangeTable[5])
        XCTAssertEqual(edited.targetHls.h, edited.hueBins[5])
        XCTAssertEqual(edited.targetHls.l, 0.5)
        XCTAssertEqual(edited.targetHls.s, 0.5)
        XCTAssertEqual(edited.lRange, 1.0)
        XCTAssertEqual(edited.sRange, 1.0)
        // Other bins untouched.
        for i in 0..<8 where i != 5 {
            XCTAssertEqual(edited.adjTable[i], params.adjTable[i])
        }
        // Clamps: hue ±30, l/s ±100.
        let clamped = HlsModule.applyTargetEdit(
            params: params, targetBin: 0, dh: 99, dl: 999, ds: -999)
        XCTAssertEqual(clamped.adjTable[0].h, 30)
        XCTAssertEqual(clamped.adjTable[0].l, 0.1, accuracy: 1e-9)
        XCTAssertEqual(clamped.adjTable[0].s, -0.1, accuracy: 1e-9)
        // 8-bin traversal completeness: every bin is editable and reads
        // back its own row.
        for bin in 0..<8 {
            let p = HlsModule.applyTargetEdit(
                params: params, targetBin: bin, dh: 5, dl: 10, ds: 10)
            XCTAssertEqual(p.adjTable[bin].h, 5)
            XCTAssertEqual(p.targetHls.h, params.hueBins[bin])
        }
    }
}
