@testable import LightamerCore
import CoreGraphics
import CoreImage
import LightamerIOP
import Metal
import XCTest

// Plan 02-04-07 — the terminal trio unit layer: registry default chain,
// identity kernel bit-fidelity, the colorout matrix known points, the
// gamma TRC table, the display-tail format, and DisplayProfile resolution.
// The D-COL1 dual-criteria golden harness lives in `GoldenColorTests`.

final class TerminalTrioTests: XCTestCase {

    /// Named tolerances (the golden constants live in GoldenColorTests).
    private enum Tolerance {
        static let matrixKnownPoint = 1e-3
        static let gamma8Bit: UInt8 = 1 // ±1/255 TRC table quantization
        static let copyBitExact = 0.0
    }

    private func makeMetal() throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        return try MetalContext()
    }

    /// Same-queue FIFO drain (02-03 lesson): the dispatch helpers only
    /// commit — CPU readback must wait for a trailing fence buffer.
    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    /// float32 RGBA texture filled from `pixels` (row-major, 4 floats/px).
    private func floatTexture(
        _ pixels: [[Float]], width: Int, height: Int, metal: MetalContext
    ) -> any MTLTexture {
        let flat = pixels.flatMap { $0 }
        precondition(flat.count == width * height * 4)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let texture = metal.device.makeTexture(descriptor: descriptor)!
        flat.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16
            )
        }
        return texture
    }

    /// Read back a float32 RGBA texture (drain first!).
    private func readFloat(_ texture: any MTLTexture) -> [Float] {
        var buffer = [Float](repeating: 0, count: texture.width * texture.height * 4)
        buffer.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return buffer
    }

    /// Read back an 8-bit texture as (r, g, b) tuples — unpacks the BGRA
    /// byte order of `.bgra8Unorm` memory layout.
    private func readRGB8(_ texture: any MTLTexture) -> [(UInt8, UInt8, UInt8)] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        var out: [(UInt8, UInt8, UInt8)] = []
        for i in stride(from: 0, to: bytes.count, by: 4) {
            out.append((bytes[i + 2], bytes[i + 1], bytes[i])) // R, G, B
        }
        return out
    }

    // ── 02-04-01: registry ───────────────────────────────────────────────

    func testDefaultChainIsTerminalTrioInV50Order() async throws {
        let registry = ModuleRegistry.makeDefault()
        let chain = await registry.makeDefaultChain()
        XCTAssertEqual(chain.count, 3, "default chain = [colorin, colorout, gamma]")
        XCTAssertEqual(chain.map(\.opName), ["colorin", "colorout", "gamma"])
        let orders = chain.map(\.iopOrder)
        XCTAssertEqual(orders, [28.0, 70.0, 78.0], "v50 order preserved")
        // Sorted invariant (28.0 < 70.0 < 78.0).
        XCTAssertEqual(orders, orders.sorted(), "chain must be v50-sorted")
        // Boxes are fresh instances per call (single-owner contract).
        let chain2 = await registry.makeDefaultChain()
        XCTAssertNotEqual(chain[0].instanceID, chain2[0].instanceID)
    }

    func testUnknownOpReturnsNil() async throws {
        let registry = ModuleRegistry.makeDefault()
        let box = await registry.makeBox(opName: "nonexistent")
        XCTAssertNil(box, "unknown op → nil (02-06 degrade path consumes this)")
    }

    func testMakeBoxInjectsPersistedInstanceID() async throws {
        let registry = ModuleRegistry.makeDefault()
        let id = UUID()
        let box = await registry.makeBox(opName: "colorin", instanceID: id)
        XCTAssertEqual(box?.instanceID, id, "sidecar/sidecar-anchor UUID restored")
    }

    func testIOPPopulateRegistersTestGainInDebug() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: TestGainModule.opName)
        #if DEBUG
        XCTAssertNotNil(box, "testgain registered by populate in DEBUG")
        #else
        XCTAssertNil(box, "testgain compiled out of Release — unknown op")
        #endif
    }

    // ── 02-04-02: colorin identity ───────────────────────────────────────

    func testTerminalCopyBitIdentity() async throws {
        let metal = try makeMetal()
        let module = ColorInModule()
        var piece = IOPiece()
        await module.commitParams(.init(), into: &piece)

        // Pattern with denormals-ish odd values — bit-exactness probe
        // (2 pixels × RGBA, one row).
        let values: [Float] = [0, 1, 0.25, 2.0, 65504, 1e-30, -0.5, 3.14159]
        let input = floatTexture([values], width: 2, height: 1, metal: metal)
        let output = floatTexture([[0, 0, 0, 0, 0, 0, 0, 0]], width: 2, height: 1, metal: metal)
        try await module.process(
            input: input, output: output,
            roiIn: ROI(width: 2, height: 1, scale: 1),
            roiOut: ROI(width: 2, height: 1, scale: 1),
            piece: &piece, metal: metal
        )
        drain(metal)
        let inBits = readFloat(input).map(\.bitPattern)
        let outBits = readFloat(output).map(\.bitPattern)
        XCTAssertEqual(inBits, outBits, "terminal_copy must round-trip bits exactly")
    }

    func testColorInIdentityParamsHashIsStable() async throws {
        // D-H4: empty-params hash is the FNV of "{}"-ish JSON — constant
        // across instances (cache keys stable across chain rebuilds).
        let a = ColorInModule()
        let b = ColorInModule()
        var pieceA = IOPiece()
        var pieceB = IOPiece()
        await a.commitParams(.init(), into: &pieceA)
        await b.commitParams(.init(), into: &pieceB)
        XCTAssertEqual(pieceA.paramsHash, pieceB.paramsHash)
        XCTAssertNotEqual(pieceA.paramsHash, 0, "committed hash must be real, not the zero default")
    }

    // ── 02-04-03: colorout known points ─────────────────────────────────

    /// Dispatch colorout with an explicit profile over a 3×1 texture whose
    /// rows are pure Rec2020 red, green, blue (alpha 1).
    private func coloroutKnownPoints(
        profile: ColorOutModule.OutputProfile, metal: MetalContext
    ) async throws -> [[Float]] {
        let module = ColorOutModule()
        var piece = IOPiece()
        await module.commitParams(.init(outputProfile: profile), into: &piece)
        let input = floatTexture(
            [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1]], width: 3, height: 1, metal: metal
        )
        let output = floatTexture(
            [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], width: 3, height: 1, metal: metal
        )
        try await module.process(
            input: input, output: output,
            roiIn: ROI(width: 3, height: 1, scale: 1),
            roiOut: ROI(width: 3, height: 1, scale: 1),
            piece: &piece, metal: metal
        )
        drain(metal)
        let flat = readFloat(output)
        // Each pixel = 4 floats (RGBA); we want the leading RGB triple.
        return (0..<3).map { row in Array(flat[row * 4..<(row * 4 + 3)]) }
    }

    func testColorOutMatrixKnownPointsP3() async throws {
        let metal = try makeMetal()
        let rows = try await coloroutKnownPoints(profile: .displayP3, metal: metal)
        // Rec2020 → P3 linear, derived constants (see ColorOutModule.swift
        // header; generator `.work/02-04/matrix-derive.swift`).
        let expected: [[Float]] = [
            [1.343930183, -0.066855841, 0.003750840],
            [-0.282585998, 1.077337009, -0.019626716],
            [-0.061344185, -0.010481169, 1.015875875],
        ]
        for (row, want) in zip(rows, expected) {
            for (got, exp) in zip(row, want) {
                XCTAssertEqual(Double(got), Double(exp), accuracy: Tolerance.matrixKnownPoint)
            }
        }
    }

    func testColorOutMatrixKnownPointsSRGB() async throws {
        let metal = try makeMetal()
        let rows = try await coloroutKnownPoints(profile: .sRGB, metal: metal)
        let expected: [[Float]] = [
            [1.661272640, -0.126189204, -0.017014775],
            [-0.588487320, 1.134531230, -0.100723728],
            [-0.072785321, -0.008342025, 1.117738502],
        ]
        for (row, want) in zip(rows, expected) {
            for (got, exp) in zip(row, want) {
                XCTAssertEqual(Double(got), Double(exp), accuracy: Tolerance.matrixKnownPoint)
            }
        }
    }

    func testColorOutPreservesGrayExactly() async throws {
        let metal = try makeMetal()
        let module = ColorOutModule()
        var piece = IOPiece()
        await module.commitParams(.init(outputProfile: .displayP3), into: &piece)
        let input = floatTexture([[0.5, 0.5, 0.5, 1]], width: 1, height: 1, metal: metal)
        let output = floatTexture([[0, 0, 0, 0]], width: 1, height: 1, metal: metal)
        try await module.process(
            input: input, output: output,
            roiIn: ROI(width: 1, height: 1, scale: 1),
            roiOut: ROI(width: 1, height: 1, scale: 1),
            piece: &piece, metal: metal
        )
        drain(metal)
        let px = readFloat(output)
        for channel in 0..<3 {
            XCTAssertEqual(
                Double(px[channel]), 0.5, accuracy: 1e-5,
                "gray must survive the gamut matrix to float precision (D-COL1 precondition)"
            )
        }
    }

    func testColorOutCommitFoldsDisplayStableID() async throws {
        // The terminal-invalidation atom: same params, different resolved
        // display → DIFFERENT paramsHash (a display change must flip the
        // ≥colorout cache keys).
        let module = ColorOutModule()
        var piece = IOPiece()
        module.displayProfileOverride = .displayP3
        await module.commitParams(.init(outputProfile: .display), into: &piece)
        let p3Hash = piece.paramsHash
        module.displayProfileOverride = .sRGB
        await module.commitParams(.init(outputProfile: .display), into: &piece)
        let srgbHash = piece.paramsHash
        XCTAssertNotEqual(p3Hash, srgbHash, "display change ⇒ colorout paramsHash change")
        // Identical resolved display ⇒ identical hash (determinism).
        module.displayProfileOverride = .displayP3
        await module.commitParams(.init(outputProfile: .display), into: &piece)
        XCTAssertEqual(piece.paramsHash, p3Hash)
    }

    // ── 02-04-04: gamma TRC + tail format ────────────────────────────────

    func testGammaTRCTable() async throws {
        let metal = try makeMetal()
        let module = GammaModule()
        var piece = IOPiece()
        await module.commitParams(.init(), into: &piece)

        // The five plan values (+ one negative clamp probe).
        let linear: [Float] = [0.0, 0.04045, 0.5, 1.0, 2.0, -0.25]
        let input = floatTexture(
            linear.map { [$0, $0, $0, 1] }, width: linear.count, height: 1, metal: metal
        )
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: GammaModule.outputPixelFormat,
            width: linear.count, height: 1, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let output = metal.device.makeTexture(descriptor: descriptor)!

        try await module.process(
            input: input, output: output,
            roiIn: ROI(width: linear.count, height: 1, scale: 1),
            roiOut: ROI(width: linear.count, height: 1, scale: 1),
            piece: &piece, metal: metal
        )
        drain(metal)
        let rgb = readRGB8(output)

        func srgbEncode(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
        let expected: [Double] = [
            0.0, // 0.0 → 0.0
            srgbEncode(0.04045), // linear leg: ≈0.04045/12.92
            srgbEncode(0.5), // ≈0.7354
            1.0, // 1.0 → 1.0
            1.0, // 2.0 → clamp
            0.0, // negative → clamp low
        ]
        XCTAssertEqual(expected[2], 0.735357, accuracy: 0.001, "0.5 → ≈0.7354 per plan")
        for (i, want) in expected.enumerated() {
            let want8 = UInt8((want * 255).rounded())
            let values = [rgb[i].0, rgb[i].1, rgb[i].2]
            XCTAssertEqual(
                Set(values).count, 1,
                "gray input must stay gray through the TRC (patch \(i))"
            )
            for v in values {
                XCTAssertLessThanOrEqual(
                    abs(Int(v) - Int(want8)), Int(Tolerance.gamma8Bit),
                    "TRC(\(linear[i])) → \(v), expected ≈\(want8)"
                )
            }
        }
    }

    // ── Display tail through the real pipe ───────────────────────────────

    /// The default chain committed for an EXPLICIT displayP3 target
    /// (deterministic across hosts — the screen-dependent `.display`
    /// resolution is the coordinator's business, not the harness's).
    static func makeCommittedDefaultChain(
        registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile
    ) async -> [any ModuleBoxing] {
        let chain = await registry.makeDefaultChain()
        if let colorout = chain.first(where: { $0.opName == ColorOutModule.opName })
            as? ModuleBox<ColorOutModule> {
            await colorout.setParams(.init(outputProfile: outputProfile))
        }
        for box in chain where box.opName == ColorInModule.opName {
            if let colorin = box as? ModuleBox<ColorInModule> {
                await colorin.setParams(.init())
            }
        }
        for box in chain where box.opName == GammaModule.opName {
            if let gamma = box as? ModuleBox<GammaModule> {
                await gamma.setParams(.init())
            }
        }
        return chain
    }

    func testPipeTailProducesBgra8Unorm() async throws {
        let metal = try makeMetal()
        let cache = PipeCache()
        let chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: ModuleRegistry.makeDefault(), outputProfile: .displayP3
        )
        let ci = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 192))
        let image = DecodedImage(
            ciImage: ci, rawTech: RAWTechnicalParams(), capture: CaptureMetadata(),
            segmentationSkyMatte: nil, decoderVersionUsed: .v8
        )
        let (output, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: cache, metal: metal, longEdge: 128
        )
        XCTAssertEqual(
            output.pixelFormat, GammaModule.outputPixelFormat,
            "gamma-tail pipe output must be the display format"
        )
    }

    // ── DisplayProfile resolution ────────────────────────────────────────

    func testDisplayProfileKnownSpaces() {
        XCTAssertEqual(DisplayProfile.resolve(nil), .sRGB, "nil falls back to the safe encoding")
        XCTAssertEqual(DisplayProfile.resolve(.sRGB), .sRGB)
        XCTAssertEqual(DisplayProfile.resolve(.displayP3), .displayP3)
        // Distinct stableIDs per fast path (cache-key atom).
        XCTAssertNotEqual(DisplayProfile.displayP3.stableID, DisplayProfile.sRGB.stableID)
        // Fallback stableID is content-stable (ICC bytes) and distinct.
        // (genericLab: a non-RGB, definitely-unmatched system space.)
        let odd = CGColorSpace(name: CGColorSpace.genericLab)!
        let fallback = DisplayProfile.resolve(NSColorSpace(cgColorSpace: odd))
        guard case .colorSyncFallback = fallback else {
            return XCTFail("generic RGB must resolve to the ColorSync fallback")
        }
        XCTAssertNotEqual(fallback.stableID, DisplayProfile.sRGB.stableID)
        XCTAssertNotEqual(fallback.stableID, DisplayProfile.displayP3.stableID)
    }

    func testDisplayProfileCurrentOnThisHost() throws {
        let profile = DisplayProfile.current()
        switch profile {
        case .displayP3, .sRGB:
            // The plan's happy path: a built-in P3/sRGB panel. Host-true.
            XCTAssertEqual(profile.stableID, DisplayProfile.displayP3.stableID,
                           "this host's fast path is P3")
        case .colorSyncFallback:
            // Host variance guard (plan): external/nonstandard panel → the
            // precise path is CORRECT behavior; log and pass.
            AppError.logger.info(
                "display resolve test: host panel is not a known fast path — \(profile.label, privacy: .public)"
            )
        }
    }
}
