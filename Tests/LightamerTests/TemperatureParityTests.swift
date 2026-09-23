@testable import LightamerCore
import CoreGraphics
import CoreImage
import Foundation
import LightamerIOP
import Metal
import XCTest

// TemperatureParityTests (Plan 03-02-T2/T6) — track A + track B for the WB
// temperature iop, reusing the 03-01 dual-track harness patterns
// (GoldenParityTests: UncompressedEXR reader, decodeFixtureEXR, drain).
//
// REFERENCE PROVENANCE (host finding, manifest "dt-cli host finding"):
// darktable-cli in this build environment emits spatially corrupted float
// output for spatially-varying images (EXR channel-plane mislayout; PFM/TIFF
// horizontal smear; uniform images exact; exposure+ramp EXR is the 03-01
// exception that passed). The temperature track-A references are therefore
// SYNTHESIZED by gen_fixtures.py (`refs` mode): canonical fixture × pinned
// gains in float64 — the exact evaluation of the shared per-pixel semantic
// (whitebalance_4f). dt's side is pinned by three independent pieces of
// evidence:
//   1. XMP adoption: the library DB `op_params` hex equals the pinned blob
//      (verified in regenerate.sh debugging; `--core -d params` shows the
//      module committed enabled with those params).
//   2. Uniform-flat PFM probes: dt-cli output on flat_0ev/-4ev/-8ev equals
//      fixture × gains to <1e-5 (testTemperatureProbeMatchesReference —
//      the per-pixel semantic check on the cases dt exports exactly).
//   3. The Kelvin→gains math is CPU-locked in CPUDerivationTests against
//      the C harness built from dt's own tables + lcms2.
final class TemperatureParityTests: XCTestCase {

    private enum ParityTolerance {
        static let elementwiseRelative: Float = 1e-5
    }

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
                    + "`bash input/golden/regenerate.sh` (Plan 03-02)"
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

    // MARK: - PFM reader (dt-cli probe verification)

    /// Minimal PFM reader for the dt-cli probes: "PF\n<w> <h>\n<scale>\n"
    /// (dt pads the scale line with '0's to a 16-byte boundary — parse the
    /// float prefix), RGB channel order, rows stored bottom-up, little-
    /// endian when scale < 0.
    private struct PFMFile {
        var width: Int
        var height: Int
        /// RGB, row-major TOP-down (the file stores rows bottom-up).
        var rgb: [Float]

        static func load(_ url: URL) throws -> PFMFile {
            let data = try Data(contentsOf: url)
            guard let magicRange = data.range(of: Data("PF\n".utf8)) else {
                throw PFMError.badHeader
            }
            var pos = magicRange.upperBound
            guard let whEnd = data[pos...].firstIndex(of: UInt8(ascii: "\n")) else {
                throw PFMError.badHeader
            }
            let wh = String(decoding: data[pos..<whEnd], as: UTF8.self)
                .split(separator: " ").compactMap { Int($0) }
            guard wh.count == 2 else { throw PFMError.badHeader }
            pos = data.index(after: whEnd)
            guard let scaleEnd = data[pos...].firstIndex(of: UInt8(ascii: "\n")) else {
                throw PFMError.badHeader
            }
            // The scale token may carry dt's zero padding: "-1.0" + "0…" —
            // Double(String) parses the longest valid prefix ("−1.00000…"
            // parses fine; the padding cannot form a longer number).
            let scale = Double(String(decoding: data[pos..<scaleEnd], as: UTF8.self))
                ?? -1.0
            pos = data.index(after: scaleEnd)
            let width = wh[0], height = wh[1]
            let count = width * height * 3
            guard data.count - pos >= count * 4 else { throw PFMError.truncated }
            var floats = [Float](repeating: 0, count: count)
            data[pos...].prefix(count * 4).withUnsafeBytes { src in
                _ = floats.withUnsafeMutableBytes { dst in
                    memcpy(dst.baseAddress!, src.baseAddress!, count * 4)
                }
            }
            if scale > 0 { // big-endian per PFM convention — byteswap
                for i in 0..<count {
                    floats[i] = Float(bitPattern: floats[i].bitPattern.byteSwapped)
                }
            }
            // bottom-up → top-down
            var rgb = [Float](repeating: 0, count: count)
            for row in 0..<height {
                let src = (height - 1 - row) * width * 3
                let dst = row * width * 3
                for k in 0..<(width * 3) {
                    rgb[dst + k] = floats[src + k]
                }
            }
            return PFMFile(width: width, height: height, rgb: rgb)
        }

        enum PFMError: Error { case badHeader, truncated }
    }

    /// The canonical fixture values (expected input to both sides).
    private func fixtureValue(_ fixture: String, x: Int, y: Int) throws -> Float {
        switch fixture {
        case "ramp_8ev": return Float(pow(2.0, -8.0 + Double(x) / 8.0))
        case "flat_0ev": return 0.5
        case "flat_-4ev": return Float(0.5 * pow(2.0, -4.0))
        case "flat_-8ev": return Float(0.5 * pow(2.0, -8.0))
        default: throw XCTSkip("no analytic value for \(fixture)")
        }
    }

    // MARK: - Track A: Lightamer vs the synthesized references

    /// The temperature 钉参组 (manifest maps these to the dt blobs; the
    /// synthesized references carry the same gains).
    private static let temperatureCases: [(name: String, params: TemperatureModule.Params)] = [
        ("temperature_default", TemperatureModule.Params(red: 1, green: 1, blue: 1, preset: .asShot)),
        ("temperature_r120_b080", TemperatureModule.Params(red: 1.2, green: 1.0, blue: 0.8, preset: .user)),
        ("temperature_r070_b140", TemperatureModule.Params(red: 0.7, green: 1.0, blue: 1.4, preset: .user)),
        ("temperature_spot_warm", TemperatureModule.Params(red: 1.35, green: 1.0, blue: 0.77, preset: .spot)),
    ]

    private static let trackAFixtures = [
        "ramp_8ev", "flat_0ev", "flat_-4ev", "flat_-8ev", "gray_staircase",
    ]

    func testTemperatureGoldenParity() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try GoldenParityTests.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.temperatureCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try GoldenParityTests.UncompressedEXR.load(goldenURL)
                let (pipe, pipeW, pipeH) = try await runTemperaturePipe(
                    image: image, params: params, metal: metal
                )
                guard pipeW == golden.width, pipeH == golden.height else {
                    failures.append("\(caseName)×\(fixture): size mismatch \(pipeW)×\(pipeH) vs \(golden.width)×\(golden.height)")
                    continue
                }
                let n = golden.width * golden.height
                for i in 0..<n {
                    for c in 0..<3 {
                        let ref = golden.rgb[i * 3 + c]
                        let la = pipe[i * 3 + c]
                        let rel = abs(la - ref) / max(abs(ref), 1e-9)
                        maxRelative = max(maxRelative, rel)
                        if rel >= ParityTolerance.elementwiseRelative, failures.count < 12 {
                            failures.append(
                                "\(caseName)×\(fixture) px\(i) ch\(c): lightamer=\(la) ref=\(ref) rel=\(rel)"
                            )
                        }
                    }
                }
            }
        }
        XCTAssertLessThan(
            Double(maxRelative), Double(ParityTolerance.elementwiseRelative),
            "temperature golden parity exceeded \(ParityTolerance.elementwiseRelative) (max \(maxRelative))\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// Lightamer leg: canonical fixture → [colorin, temperature] pipe →
    /// float32 linear-Rec2020 RGB plane (the sorted chain runs temperature
    /// (3.0) before colorin (28.0); colorin is identity on Rec2020-tagged
    /// input, matching dt's RGB-path apply).
    private func runTemperaturePipe(
        image: DecodedImage, params: TemperatureModule.Params, metal: MetalContext
    ) async throws -> ([Float], Int, Int) {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let temperature = await registry.makeBox(opName: TemperatureModule.opName)
        let temperatureBox = try XCTUnwrap(temperature as? ModuleBox<TemperatureModule>)
        temperatureBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), temperatureBox]

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

    // MARK: - dt-cli probe verification (uniform flats)

    /// The dt-cli PFM probes on the UNIFORM flats (where dt's export is
    /// trustworthy — see the host finding) must equal fixture × gains to
    /// <1e-5: dt's per-pixel semantic pinned against the same reference
    /// math the synthesized references use.
    func testTemperatureProbeMatchesReference() throws {
        for (caseName, params) in Self.temperatureCases {
            for fixture in ["flat_0ev", "flat_-4ev", "flat_-8ev"] {
                let probeURL = try requireGolden("output/pfm_probe/\(caseName)__\(fixture).pfm")
                let probe = try PFMFile.load(probeURL)
                var maxRelative: Double = 0
                for y in 0..<probe.height {
                    for x in 0..<probe.width {
                        let vin = try fixtureValue(fixture, x: x, y: y)
                        let expected = [
                            Double(vin) * Double(params.red),
                            Double(vin) * Double(params.green),
                            Double(vin) * Double(params.blue),
                        ]
                        let base = (y * probe.width + x) * 3
                        for c in 0..<3 {
                            let got = Double(probe.rgb[base + c])
                            maxRelative = max(maxRelative, abs(got - expected[c]) / max(abs(expected[c]), 1e-9))
                        }
                    }
                }
                XCTAssertLessThan(
                    maxRelative, 1e-5,
                    "\(caseName)×\(fixture): dt-cli probe diverges from fixture×gains by \(maxRelative)"
                )
            }
        }
    }

    // MARK: - Track B: dual criteria with temperature inserted

    /// Criterion 1: gray-patch neutrality with temperature (identity gains)
    /// inserted at its v50 slot — the terminal trio semantics survive.
    func testTrackBNeutralityWithTemperatureInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)

        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        var chain = try await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: .displayP3
        )
        let temperature = await registry.makeBox(opName: TemperatureModule.opName)
        let temperatureBox = try XCTUnwrap(temperature as? ModuleBox<TemperatureModule>)
        temperatureBox.setParams(.init()) // identity gains
        chain.append(temperatureBox)
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
            "track B neutrality with temperature inserted FAILED:\n" + failures.joined(separator: "\n")
        )
    }

    // MARK: - Kernel + registration

    func testTemperatureRegisteredAtV50Slot3() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: TemperatureModule.opName)
        let temperatureBox = try XCTUnwrap(box as? ModuleBox<TemperatureModule>)
        XCTAssertEqual(TemperatureModule.opName, "temperature")
        XCTAssertEqual(TemperatureModule.iopOrder, 3.0)
        XCTAssertEqual(TemperatureModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: TemperatureModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
        _ = temperatureBox
    }

    /// GPU leg: 0.5 gray × (1.2, 1.0, 0.8) → (0.6, 0.5, 0.4) through the
    /// actual kernel (dispatch → drain → readback, L014).
    func testTemperatureKernelGainApply() async throws {
        let metal = try await makeMetal()
        let module = TemperatureModule()
        var piece = IOPiece()
        let gains = TemperatureModule.Params(gains: SIMD3<Float>(1.2, 1.0, 0.8))
        module.commitParams(gains, into: &piece)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 4, height: 4, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        var pixels = [Float](repeating: 0.5, count: 4 * 4 * 4)
        for i in 0..<(4 * 4) { pixels[i * 4 + 3] = 1.0 }
        pixels.withUnsafeBytes {
            input.replace(
                region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 4 * 16
            )
        }
        try await module.process(
            input: input, output: output, roiIn: ROI(), roiOut: ROI(),
            piece: &piece, metal: metal
        )
        drain(metal)
        var out = [Float](repeating: 0, count: 4 * 4 * 4)
        out.withUnsafeMutableBytes {
            output.getBytes(
                $0.baseAddress!, bytesPerRow: 4 * 16,
                from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0
            )
        }
        let expected: [Float] = [0.6, 0.5, 0.4, 1.0]
        for i in 0..<(4 * 4) {
            for c in 0..<4 {
                XCTAssertEqual(out[i * 4 + c], expected[c], accuracy: 1e-6, "px\(i) ch\(c)")
            }
        }
    }
}
