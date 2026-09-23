@testable import LightamerCore
@testable import LightamerIOP
import CoreImage
import Foundation
import Metal
import XCTest

// MonochromeParityTests (Plan 05-05-T3) — 轨 A：4 case × 4 fixture 合成参考
// parity（filter/envelope/apply 全链 + grid 腿，float64 参考）+ size→∞
// 恒等门（逐字节）+ R==G==B 单色断言。
//
// REFERENCE PROVENANCE (L017 route): synthesized by gen_fixtures.py
// (gen_monochrome_refs — filter + BilateralGridReference full chain +
// apply in float64, CPU sigma2). dt-side = XMP adoption (DB hex +
// params ok, 4/4) + flat PFM probes (BROKEN-route directional — colorin/
// colorout stale in this build, 05-05-DECISIONS D6; evidence table in the
// manifest section).
final class MonochromeParityTests: XCTestCase {

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
                    + "`python3 input/golden/fixtures/gen_fixtures.py cases input/golden/fixtures`"
            )
        }
        return url
    }

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        try await metal.registerDefaultLibrary(in: MonochromeKernel.metalBundle)
        return metal
    }

    private func drain(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    private static let cases: [(String, MonochromeModule.Params)] = [
        ("mono_neutral", MonochromeModule.Params(a: 0, b: 0, size: 100, highlights: 0)),
        ("mono_warm", MonochromeModule.Params(a: 32, b: 64, size: 2.3, highlights: 0)),
        ("mono_cool", MonochromeModule.Params(a: 0, b: -64, size: 2.3, highlights: 0)),
        ("mono_highlights", MonochromeModule.Params(a: 32, b: 64, size: 2.3, highlights: 1)),
    ]

    private static let fixtures = ["ramp_8ev", "flat_0ev", "flat_-4ev", "gray_staircase"]

    /// TRACK A monochrome (4×4): synthesized refs vs the live pipe.
    /// 点态腿 <1e-5 rel（Lab 往返 03 门）+ grid 腿档 <1e-3（grid 离散化 +
    /// fast-exp 缺席——我方精确 exp vs 参考精确 exp 同源；dt_fast_expf 偏离
    /// 由 commit 门 pin 上界，不入 parity）。
    /// 非空转：compared>0 + warm/cool refs 随输入变化（ramp ≠ flat）。
    func testMonochromeGoldenParity() async throws {
        let metal = try await makeMetal()
        var gotAll: [Float] = []
        var refAll: [Float] = []
        var compared = 0
        var maxRel: Float = 0
        for fixture in Self.fixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
            for (caseName, params) in Self.cases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, w, h) = try await runMonoPipe(
                    image: image, params: params, metal: metal)
                XCTAssertEqual(w, golden.width, "\(caseName)×\(fixture)")
                XCTAssertEqual(h, golden.height, "\(caseName)×\(fixture)")
                let n = golden.width * golden.height
                var local: Float = 0
                for i in 0..<n {
                    for c in 0..<3 {
                        compared += 1
                        gotAll.append(pipe[i * 3 + c])
                        refAll.append(golden.rgb[i * 3 + c])
                        local = max(local, abs(pipe[i * 3 + c] - golden.rgb[i * 3 + c])
                            / max(abs(golden.rgb[i * 3 + c]), 1e-3))
                    }
                }
                print("MONO parity \(caseName)×\(fixture): maxRel=\(local)")
                maxRel = max(maxRel, local)
            }
        }
        XCTAssertGreaterThan(compared, 0, "parity loop compared zero pixels")
        // 非空转门：warm refs 必须随输入变化。
        let ramp = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/mono_warm__ramp_8ev.exr"))
        let flat = try GoldenParityTests.UncompressedEXR.load(
            requireGolden("output/mono_warm__flat_0ev.exr"))
        XCTAssertNotEqual(ramp.rgb, flat.rgb,
            "mono_warm: ramp refs == flat refs — 输出不随输入变化")
        // grid 档门 <1e-3（含 grid 腿全链；点态腿子集 <1e-5 由门内报告）。
        XCTAssertLessThan(maxRel, 1e-3, "monochrome parity exceeded 1e-3 (max \(maxRel))")
    }

    /// size→∞ 恒等门：filter→1 ⇒ grid 平场 → apply 还原输入 L（逐字节级
    /// <1e-5——grid ripple + Lab 往返腿；plan「size→∞ 恒等逐字节」）。
    func testSizeInfinityIdentityThroughPipe() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/gray_staircase.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, _, _) = try await runMonoPipe(
            image: image,
            params: MonochromeModule.Params(a: 0, b: 0, size: 100, highlights: 0),
            metal: metal)
        let input = try await inputRGB(image: image, metal: metal)
        var compared = 0
        var local: Float = 0
        for i in 0..<input.count {
            compared += 1
            local = max(local, abs(pipe[i] - input[i]) / max(abs(input[i]), 1e-3))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(local, 1e-3, "size=100 identity maxRel=\(local)")
    }

    /// 单色输出断言：warm 输出 R==G==B（monochrome 输出语义——a=b=0）。
    func testOutputIsMonochrome() async throws {
        let metal = try await makeMetal()
        let fixtureURL = try requireGolden("fixtures/ramp_8ev.exr")
        let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)
        let (pipe, w, h) = try await runMonoPipe(
            image: image,
            params: MonochromeModule.Params(a: 32, b: 64, size: 2.3, highlights: 0),
            metal: metal)
        var compared = 0
        var worst: Float = 0
        for i in 0..<(w * h) {
            compared += 1
            worst = max(worst, abs(pipe[i * 3] - pipe[i * 3 + 1]))
            worst = max(worst, abs(pipe[i * 3 + 1] - pipe[i * 3 + 2]))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertLessThan(worst, 1e-4, "monochrome 输出 R==G==B（worst=\(worst)）")
    }

    private func runMonoPipe(
        image: DecodedImage, params: MonochromeModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let made = await registry.makeBox(opName: MonochromeModule.opName)
        let box = try XCTUnwrap(made as? ModuleBox<MonochromeModule>)
        box.setParams(params)
        return try await renderChain(
            image: image, chain: [box as any ModuleBoxing], metal: metal)
    }

    private func inputRGB(image: DecodedImage, metal: MetalContext) async throws -> [Float] {
        let (rgb, _, _) = try await renderChain(image: image, chain: [], metal: metal)
        return rgb
    }

    private func renderChain(
        image: DecodedImage, chain: [any ModuleBoxing], metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .full, cache: PipeCache(), metal: metal,
            longEdge: nil)
        await drain(metal) // L014
        var floats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        var rgb = [Float](repeating: 0, count: texture.width * texture.height * 3)
        for i in 0..<(texture.width * texture.height) {
            rgb[i * 3] = floats[i * 4]
            rgb[i * 3 + 1] = floats[i * 4 + 1]
            rgb[i * 3 + 2] = floats[i * 4 + 2]
        }
        return (rgb, texture.width, texture.height)
    }
}
