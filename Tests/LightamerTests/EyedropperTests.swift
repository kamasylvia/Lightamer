@testable import LightamerCore
@testable import Lightamer
@testable import LightamerIOP
import CoreGraphics
import CoreImage
import Foundation
import LightamerIOP
import Metal
import simd
import XCTest

// EyedropperTests (Plan 03-02-T5/T6) — the D-T4 color sampling plumbing:
//
//   viewport click → aspect-fit normalized uv (`PipeCoordinator
//   .viewportUV`) → LINEAR pipe plane re-run (cache-hit dominated; the
//   display segment colorout+gamma is dropped) → queue fence (L014) →
//   5×5 area mean (`sampleArea`, dt AREA picker semantics) → gains =
//   normalize(1/picked) (dt temperature.c:1933-1955).
//
// Acceptance per plan: neutral fixture sampling matches the CPU expectation
// <1e-5; 20 rapid picks are fence-safe (no crash, no dirty read); sampling
// never mutates the sampled textures; a blue-cast flat neutralizes
// end-to-end through the solved gains.
@MainActor
final class EyedropperTests: XCTestCase {

    private var tempDirectory: URL!
    private var editorState: EditorState!
    private var coordinator: PipeCoordinator!
    private var metal: MetalContext!
    private var cache: PipeCache!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("eyedropper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("no Metal GPU") }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        cache = PipeCache()
        editorState = EditorState()
        coordinator = PipeCoordinator()
        editorState.attach(pipeCoordinator: coordinator)
        coordinator.attach(editorState: editorState)
        coordinator.attach(registry: makeRegistry())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    private func makeRegistry() -> ModuleRegistry {
        let registry = ModuleRegistry.makeDefault()
        return registry
    }

    // MARK: - Fixtures

    /// A flat image of the given linear RGB (float32 CGImage path, L016).
    private func flatImage(_ rgb: SIMD3<Float>, width: Int = 64, height: Int = 64) throws -> DecodedImage {
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = rgb.x
            rgba[i * 4 + 1] = rgb.y
            rgba[i * 4 + 2] = rgb.z
            rgba[i * 4 + 3] = 1.0
        }
        return try image(fromRGBA: rgba, width: width, height: height)
    }

    /// The gray staircase fixture pattern (12 neutral steps, 10px blocks —
    /// the WB 吸管靶 from the golden fixture set, built in-test).
    private func staircaseImage(width: Int = 120, height: Int = 120) throws -> DecodedImage {
        let levels: [Float] = [0.02, 0.04, 0.07, 0.10, 0.18, 0.25, 0.35, 0.50, 0.65, 0.80, 0.90, 1.00]
        var rgba = [Float](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = levels[min(Int(Float(x) / (Float(width) / Float(levels.count))), levels.count - 1)]
                let i = (y * width + x) * 4
                rgba[i] = v; rgba[i + 1] = v; rgba[i + 2] = v; rgba[i + 3] = 1.0
            }
        }
        return try image(fromRGBA: rgba, width: width, height: height)
    }

    private func image(fromRGBA rgba: [Float], width: Int, height: Int) throws -> DecodedImage {
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

    /// Load with the colorin-only chain (identity — the linear plane equals
    /// the synthetic values, no terminal display segment in the way).
    private func loadColorinOnly(_ image: DecodedImage) async throws {
        let url = tempDirectory.appendingPathComponent("pick-\(UUID().uuidString).exr")
        let registry = makeRegistry()
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        try await coordinator.load(url: url, decoded: image, instances: [colorinBox], metal: metal)
    }

    /// The viewport POINT of texture pixel (px, py) for a viewport exactly
    /// matching the fitted image (aspect 1:1 — the synthetic fixtures are
    /// square, so the fit fills the viewport).
    private func viewportPoint(px: Int, py: Int, textureSize: Int, viewport: CGFloat) -> CGPoint {
        let uv = (Double(px) + 0.5) / Double(textureSize)
        let uvY = (Double(py) + 0.5) / Double(textureSize)
        return CGPoint(x: uv * Double(viewport), y: uvY * Double(viewport))
    }

    // MARK: - viewportUV mapping

    func testViewportUVSquareFit() {
        // square image in a square viewport → identity mapping
        let uv = PipeCoordinator.viewportUV(
            at: CGPoint(x: 50, y: 25), viewportSize: CGSize(width: 100, height: 100),
            textureSize: SIMD2(64, 64)
        )
        XCTAssertNotNil(uv)
        XCTAssertEqual(uv!.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(uv!.y, 0.25, accuracy: 1e-9)
    }

    func testViewportUVLetterboxRejectsOutsideClicks() {
        // Tall image (aspect 0.5) in a wide viewport (aspect 2.0): the fit
        // is height-constrained — the image occupies a 50px-wide centered
        // band [75, 125]; x = 50 lands in the LEFT letterbox band.
        let uvOutside = PipeCoordinator.viewportUV(
            at: CGPoint(x: 50, y: 50), viewportSize: CGSize(width: 200, height: 100),
            textureSize: SIMD2(64, 128)
        )
        XCTAssertNil(uvOutside, "click in the letterbox band must be rejected")
        let uvInside = PipeCoordinator.viewportUV(
            at: CGPoint(x: 100, y: 50), viewportSize: CGSize(width: 200, height: 100),
            textureSize: SIMD2(64, 128)
        )
        XCTAssertNotNil(uvInside)
        XCTAssertEqual(uvInside!.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(uvInside!.y, 0.5, accuracy: 1e-9)
    }

    // MARK: - End-to-end sampling

    /// Neutral staircase fixture: sampling any neutral point returns the
    /// fixture value (CPU expectation) to <1e-5 (plan gate).
    func testPickColorMatchesCPUExpectation() async throws {
        try await loadColorinOnly(try staircaseImage())
        // Render once so the pipe cache is warm (as the app does on load).
        _ = editorState.displayTexture

        let textureSize = 120
        let viewport: CGFloat = 600

        for (px, py) in [(5, 5), (45, 60), (95, 100)] {
            let level = [0.02, 0.04, 0.07, 0.10, 0.18, 0.25, 0.35, 0.50, 0.65, 0.80, 0.90, 1.00][px / 10]
            let pickedOpt = await coordinator.pickColor(
                at: viewportPoint(px: px, py: py, textureSize: textureSize, viewport: viewport),
                viewportSize: CGSize(width: viewport, height: viewport)
            )
            let picked = try XCTUnwrap(pickedOpt)
            XCTAssertLessThan(abs(Double(picked.x) - level), 1e-5, "px(\(px),\(py)) R")
            XCTAssertLessThan(abs(Double(picked.y) - level), 1e-5, "px(\(px),\(py)) G")
            XCTAssertLessThan(abs(Double(picked.z) - level), 1e-5, "px(\(px),\(py)) B")
        }
    }

    /// 20 rapid picks: no crash, consistent values, and the PREVIEW texture
    /// content is byte-identical before/after (sampling never pollutes).
    func testRapidPicksAreFenceSafeAndNonPolluting() async throws {
        try await loadColorinOnly(try flatImage(SIMD3(0.25, 0.25, 0.25)))
        _ = editorState.displayTexture
        let display = try XCTUnwrap(editorState.displayTexture)

        // L014: the load's render may still be in flight — fence before the
        // CPU snapshot (the same discipline the picks themselves follow).
        drain(metal)
        let before = textureBytes(display)

        let viewport: CGFloat = 640
        var last: simd_float3?
        for i in 0..<20 {
            let px = (i * 7) % 64, py = (i * 11) % 64
            let pickedOpt = await coordinator.pickColor(
                at: viewportPoint(px: px, py: py, textureSize: 64, viewport: viewport),
                viewportSize: CGSize(width: viewport, height: viewport)
            )
            let picked = try XCTUnwrap(pickedOpt)
            XCTAssertLessThan(abs(picked.x - 0.25), 1e-5, "pick \(i)")
            last = picked
        }
        XCTAssertNotNil(last)

        let after = textureBytes(display)
        XCTAssertEqual(before, after, "sampling must not pollute the PREVIEW texture (L014 readback)")
    }

    /// Blue-cast flat: pick → gains = normalize(1/picked) → apply the
    /// temperature module → re-pick the rendered output = NEUTRAL (the T6
    /// end-to-end criterion, Track-B 中性度 style at linear precision).
    func testBlueCastFixtureNeutralizesThroughSolvedGains() async throws {
        // blue-cast flat: green channel = 0.25, red 0.8×, blue 1.2×
        let cast = SIMD3<Float>(0.2, 0.25, 0.3)
        try await loadColorinOnly(try flatImage(cast))
        _ = editorState.displayTexture

        let pickedOpt = await coordinator.pickColor(
            at: CGPoint(x: 300, y: 300), viewportSize: CGSize(width: 600, height: 600)
        )
        let picked = try XCTUnwrap(pickedOpt)
        let gains = WhiteBalanceMath.gainsFromPicked(picked)

        // apply the solved gains through the REAL pipe: load a fresh
        // coordinator chain [colorin, temperature] with the solved params
        let registry = makeRegistry()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let temperature = await registry.makeBox(opName: TemperatureModule.opName)
        let colorinBox = try XCTUnwrap(colorin as? ModuleBox<ColorInModule>)
        colorinBox.setParams(.init())
        let temperatureBox = try XCTUnwrap(temperature as? ModuleBox<TemperatureModule>)
        temperatureBox.setParams(TemperatureModule.Params(gains: gains, preset: .spot))

        let image = try flatImage(cast)
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: [colorinBox, temperatureBox], imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal, longEdge: nil
        )
        drain(metal)
        var floats = [Float](repeating: 0, count: 4 * 4)
        floats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: 4 * 16,
                from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0
            )
        }
        let neutral = simd_float3(floats[0], floats[1], floats[2])
        // neutralized: all channels equal (to float32 multiply precision)
        XCTAssertLessThan(abs(neutral.x - neutral.y), 1e-5, "R vs G after WB")
        XCTAssertLessThan(abs(neutral.y - neutral.z), 1e-5, "G vs B after WB")
        XCTAssertEqual(gains.y, 1.0, "green gain normalized")
    }

    // MARK: - Helpers

    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    private func textureBytes(_ texture: any MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 16)
        bytes.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return bytes
    }
}
