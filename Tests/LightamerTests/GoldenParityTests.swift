@testable import LightamerCore
import CoreGraphics
import CoreImage
import LightamerIOP
import Metal
import XCTest

// GoldenParityTests (Plan 03-01-T3) — the Phase 3 dual-track golden
// harness. Reuse entry points for later plans (03-02..03-06):
//
//   TRACK A (algorithm parity) — `runTrackA(fixture:params:)`:
//     canonical fixture EXR → Lightamer pipe (colorin + TARGET MODULE with
//     pinned params) → float32 linear Rec2020 plane, vs the dt-cli golden
//     output EXR (input/golden/output/<case>__<fixture>.exr) per pixel.
//     Regenerate the golden tree with `bash input/golden/regenerate.sh`.
//     Tolerance constants (plan): element-wise pure math <1e-5 RELATIVE;
//     iterative/filter modules (toneequal EIGF, shadhi) <1e-4 + ΔE<1.0
//     p99 — add those constants next to this comment when those plans
//     consume the harness.
//
//   TRACK B (display-correctness regression) — `runTrackB(...)`:
//     the Phase 2 D-COL1 dual criteria (gray neutrality + ColorSync
//     cross-consistency, linear domain) with the NEW MODULE inserted into
//     the default chain at its v50 slot — proves the terminal trio
//     semantics survive the iop insertion.
//
//   Track A helpers: `UncompressedEXR` (float32 reader/writer — the format
//   regenerate.sh pins via --configdir), `goldenDir`, `requireGolden`.
//
// Lesson discipline: L014 (drain before CPU readback), L013 (params hash
// via ParamsCoding — asserted in CPUDerivationTests), L006/L008 untouched.
// Golden files are REGENERABLE, never committed — missing tree ⇒ XCTSkip
// with an explicit reason (never silent pass); a PRESENT but stale tree
// (PIZ-compressed outputs) also skips with the regenerate instruction.
final class GoldenParityTests: XCTestCase {

    /// Plan tolerance for element-wise pure-math modules (exposure/WB…).
    private enum ParityTolerance {
        static let elementwiseRelative: Float = 1e-5
    }

    /// The repo-root-relative golden tree.
    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/LightamerTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("input/golden", isDirectory: true)

    /// Skip (explicit, never silent) when the golden tree has not been
    /// generated on this machine.
    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`bash input/golden/regenerate.sh` (Plan 03-01-T2)"
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

    /// Same-queue FIFO drain (L014): dispatch helpers only commit — CPU
    /// readback must wait for a trailing fence buffer.
    private func drain(_ metal: MetalContext) {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
    }

    // MARK: - Minimal uncompressed float32 EXR I/O

    /// The EXR flavor `regenerate.sh` pins (NO_COMPRESSION, float32, scanline,
    /// single part). Reading is hand-rolled to stay bit-exact: ImageIO's EXR
    /// leg re-quantizes through half-float CGImages, which would swamp the
    /// 1e-5 relative gate. A PIZ (or otherwise compressed) file fails the
    /// parse — that means the golden tree was generated without the pinned
    /// conf; the error tells the reader to re-run regenerate.sh.
    /// (internal, not private: TemperatureParityTests reuses it — Plan 03-02.)
    struct UncompressedEXR {
        var width: Int
        var height: Int
        /// RGB, row-major, channel-last (converted from the file's chlist).
        var rgb: [Float]

        static func load(_ url: URL) throws -> UncompressedEXR {
            let data = try Data(contentsOf: url)
            var pos = 0
            func magicInt() throws -> UInt32 {
                guard pos + 4 <= data.count else { throw EXRFormatError.truncated }
                let v = data.subdata(in: pos..<pos + 4).withUnsafeBytes {
                    $0.load(as: UInt32.self)
                }
                pos += 4
                return v.littleEndian
            }
            guard try magicInt() == 20000630 else { throw EXRFormatError.notEXR }
            let version = try magicInt()
            // version bits: 0-7 = 2 (scanline); 0x200 tiled, 0x800
            // non-image (deep), 0x1000 multipart — none supported here.
            guard version & 0xFF == 2, version & 0x1E00 == 0
            else { throw EXRFormatError.unsupported("multi-part/tiled/deep EXR") }

            func cString() throws -> String {
                guard let end = data[pos...].firstIndex(of: 0) else { throw EXRFormatError.truncated }
                let s = String(decoding: data[pos..<end], as: UTF8.self)
                pos = end + 1
                return s
            }
            var channels: [(name: String, pixelType: UInt32)] = []
            var dataWindow: (Int, Int, Int, Int)?
            var compression: UInt8 = 0
            while data[pos] != 0 {
                let name = try cString()
                let type = try cString()
                guard pos + 4 <= data.count else { throw EXRFormatError.truncated }
                let size = Int(data.subdata(in: pos..<pos + 4).withUnsafeBytes {
                    $0.load(as: UInt32.self).littleEndian
                })
                pos += 4
                let value = data.subdata(in: pos..<pos + size)
                switch (name, type) {
                case ("channels", "chlist"):
                    var p = 0
                    while p < value.count && value[p] != 0 {
                        guard let e = value[p...].firstIndex(of: 0) else { throw EXRFormatError.truncated }
                        let n = String(decoding: value[p..<e], as: UTF8.self)
                        p = e + 1
                        let pt = value.subdata(in: p..<p + 4).withUnsafeBytes {
                            $0.load(as: UInt32.self).littleEndian
                        }
                        p += 4 + 1 + 3 + 8 // pixelType + pLinear + reserved + x/ySampling
                        channels.append((n, pt))
                    }
                case ("compression", "compression"):
                    compression = value[value.startIndex]
                case ("dataWindow", "box2i"):
                    let ints = value.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }
                    dataWindow = (Int(ints[0]), Int(ints[1]), Int(ints[2]), Int(ints[3]))
                default:
                    break
                }
                pos += size
            }
            pos += 1 // header terminator

            guard compression == 0 else {
                throw EXRFormatError.unsupported(
                    "compression=\(compression) — regenerate the golden tree: "
                        + "bash input/golden/regenerate.sh (pins float32/uncompressed)"
                )
            }
            guard let dw = dataWindow, channels.allSatisfy({ $0.pixelType == 2 })
            else { throw EXRFormatError.unsupported("non-float32 channels or missing dataWindow") }

            let width = dw.2 - dw.0 + 1
            let height = dw.3 - dw.1 + 1
            let offsets: [UInt64] = try (0..<height).map { i in
                let o = pos + i * 8
                return data.subdata(in: o..<o + 8).withUnsafeBytes {
                    $0.load(as: UInt64.self).littleEndian
                }
            }
            // Per-channel planes in file order, then remapped by name.
            var planes: [String: [Float]] = [:]
            for (line, offset) in offsets.enumerated() {
                let o = Int(offset)
                let y = Int(data.subdata(in: o..<o + 4).withUnsafeBytes { $0.load(as: Int32.self).littleEndian })
                let size = Int(data.subdata(in: o + 4..<o + 8).withUnsafeBytes { $0.load(as: Int32.self).littleEndian })
                precondition(y == line, "unexpected scanline order")
                let rowBytes = data.subdata(in: o + 8..<o + 8 + size)
                let floatsPerLine = size / 4
                let pixels = floatsPerLine / channels.count
                precondition(pixels == width, "scanline width mismatch")
                var index = 0
                for (name, _) in channels {
                    var plane = [Float](repeating: 0, count: width)
                    plane.withUnsafeMutableBytes { dst in
                        rowBytes.withUnsafeBytes { src in
                            for x in 0..<width {
                                let s = (x * channels.count + index) * 4
                                dst.storeBytes(
                                    of: src.loadUnaligned(fromByteOffset: s, as: Float.self),
                                    toByteOffset: x * 4, as: Float.self
                                )
                            }
                        }
                    }
                    planes[name, default: []].append(contentsOf: plane)
                    index += 1
                }
            }
            guard let r = planes["R"], let g = planes["G"], let b = planes["B"] else {
                throw EXRFormatError.unsupported("missing R/G/B channel (found: \(planes.keys))")
            }
            var rgb = [Float](repeating: 0, count: width * height * 3)
            for i in 0..<(width * height) {
                rgb[i * 3] = r[i]
                rgb[i * 3 + 1] = g[i]
                rgb[i * 3 + 2] = b[i]
            }
            return UncompressedEXR(width: width, height: height, rgb: rgb)
        }

        /// Write the same pinned flavor (failure-path dumps: abs-diff maps).
        static func writeDiff(
            _ diff: [Float], width: Int, height: Int, to url: URL
        ) throws {
            var out = Data()
            var magic: UInt32 = 20000630
            out.append(contentsOf: withUnsafeBytes(of: &magic) { Data($0) })
            var version: UInt32 = 2
            out.append(contentsOf: withUnsafeBytes(of: &version) { Data($0) })
            func attr(_ name: String, _ type: String, _ payload: Data) {
                out.append(Data(name.utf8) + [0] + Data(type.utf8) + [0])
                var size = UInt32(payload.count).littleEndian
                out.append(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
                out.append(payload)
            }
            var chlist = Data()
            for name in ["B", "G", "R"] {
                chlist.append(Data(name.utf8) + [0])
                var pt = UInt32(2).littleEndian
                chlist.append(contentsOf: withUnsafeBytes(of: &pt) { Data($0) })
                chlist.append(contentsOf: [0, 0, 0, 0]) // pLinear + reserved
                var one = Int32(1).littleEndian
                chlist.append(contentsOf: withUnsafeBytes(of: &one) { Data($0) })
                chlist.append(contentsOf: withUnsafeBytes(of: &one) { Data($0) })
            }
            chlist.append(0)
            attr("channels", "chlist", chlist)
            attr("compression", "compression", Data([0]))
            var win = [Int32(0), Int32(0), Int32(width - 1), Int32(height - 1)]
                .map { $0.littleEndian }
            attr(
                "dataWindow", "box2i",
                win.withUnsafeBufferPointer { Data(buffer: $0) }
            )
            attr(
                "displayWindow", "box2i",
                win.withUnsafeBufferPointer { Data(buffer: $0) }
            )
            attr("lineOrder", "lineOrder", Data([0]))
            var oneF = Float(1.0)
            attr(
                "pixelAspectRatio", "float",
                withUnsafeBytes(of: &oneF) { Data($0) }
            )
            attr("screenWindowCenter", "v2f", Data(repeating: 0, count: 8))
            attr(
                "screenWindowWidth", "float",
                withUnsafeBytes(of: &oneF) { Data($0) }
            )
            out.append(0)
            let rowBytes = width * 3 * 4
            let headerEnd = out.count + 8 * height
            for line in 0..<height {
                var offset = UInt64(headerEnd + line * (8 + rowBytes)).littleEndian
                out.append(contentsOf: withUnsafeBytes(of: &offset) { Data($0) })
            }
            for line in 0..<height {
                var y = Int32(line).littleEndian
                var size = Int32(rowBytes).littleEndian
                out.append(contentsOf: withUnsafeBytes(of: &y) { Data($0) })
                out.append(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
                let base = line * width * 3
                for x in 0..<width {
                    // B, G, R (chlist order); input holds R,G,B.
                    for c in [2, 1, 0] {
                        var v = Float(diff[(base + x) * 3 + c])
                        out.append(contentsOf: withUnsafeBytes(of: &v) { Data($0) })
                    }
                }
            }
            try out.write(to: url)
        }
    }

    /// Build the pipe input from the fixture's EXACT float32 values.
    ///
    /// HOST FINDING (2026-09-19, macOS 27): ImageIO's EXR decode
    /// (CGImageSource → CGImage) scrambles float32 EXR content per channel
    /// (each channel arrives at a different sub-sampled column offset — the
    /// same corruption for files written by darktable AND by our own
    /// generator; probed in /tmp via CGImageSource+CGContext and CIContext).
    /// dt (libopenexr) and the reference reads are exact, so the DECODER is
    /// the outlier. The pipe leg therefore consumes the fixture via the
    /// hand-rolled reader + a float32 CGImage built from the raw bytes
    /// (CGImageCreate — no ImageIO decoder involved) tagged linear Rec2020
    /// (= the working space ⇒ identity conversion in the CI input leg).
    /// Lesson candidate for LESSONS.md.
    static func decodeFixtureEXR(_ url: URL) throws -> DecodedImage {
        let exr = try UncompressedEXR.load(url)
        let n = exr.width * exr.height
        var rgba = [Float](repeating: 1.0, count: n * 4) // alpha = 1 (premultiplied no-op)
        for i in 0..<n {
            rgba[i * 4] = exr.rgb[i * 3]
            rgba[i * 4 + 1] = exr.rgb[i * 3 + 1]
            rgba[i * 4 + 2] = exr.rgb[i * 3 + 2]
        }
        var data = Data(capacity: rgba.count * 4)
        for value in rgba {
            var le = value.bitPattern.littleEndian
            data.append(contentsOf: withUnsafeBytes(of: &le) { Data($0) })
        }
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw EXRFormatError.truncated
        }
        // WorkingSpace.colorSpace = LINEAR Rec2020. NOT CGColorSpace
        // .itur_2020 — that constant carries the BT.1886 gamma-2.4 TRC and
        // CI would gamma-decode the already-linear values (v^2.4 crush —
        // found via the 2^-19.2 signature at v(0)).
        let cs = WorkingSpace.colorSpace
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let cg = CGImage(
            width: exr.width, height: exr.height,
            bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: exr.width * 16,
            space: cs, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else {
            throw EXRFormatError.unsupported("CGImage float32 creation rejected")
        }
        return DecodedImage(
            ciImage: CIImage(cgImage: cg),
            rawTech: RAWTechnicalParams(),
            capture: CaptureMetadata(),
            segmentationSkyMatte: nil,
            decoderVersionUsed: .v8
        )
    }

    private enum EXRFormatError: Error, CustomStringConvertible {
        case truncated, notEXR, unsupported(String)

        var description: String {
            switch self {
            case .truncated: return "EXR truncated"
            case .notEXR: return "not an EXR file"
            case .unsupported(let why): return "unsupported EXR: \(why)"
            }
        }
    }

    // MARK: - Track A: dt-cli parity

    /// The exposure 钉参组 (manifest.md maps these to the dt blobs).
    private static let exposureCases: [(name: String, params: ExposureModule.Params)] = [
        ("exposure_plus1ev", ExposureModule.Params(exposure: 1.0)),
        ("exposure_minus2ev", ExposureModule.Params(exposure: -2.0)),
        ("exposure_black01", ExposureModule.Params(black: 0.1)),
        // compensate_exposure_bias=1 on the dt side; the EXR fixtures carry
        // no EXIF bias (dt's bias source reads 0), and Lightamer reserves
        // the bit (module header divergence #4) — the pinned case still
        // exercises the combination's scale math on both sides.
        ("exposure_combo", ExposureModule.Params(black: -0.02, exposure: 0.5)),
    ]

    /// Plan T6 scope: the tone 主靶 (ramp) + 平场 flats.
    private static let trackAFixtures = ["ramp_8ev", "flat_0ev", "flat_-4ev", "flat_-8ev"]

    /// TRACK A for exposure (Plan 03-01-T6 — the Phase 3 tracer): every
    /// (fixture × case) golden output vs the Lightamer pipe, per-pixel
    /// relative error < 1e-5.
    func testExposureGoldenParityAgainstDarktableCLI() async throws {
        let metal = try await makeMetal()
        var maxRelative: Float = 0
        var worst: (String, Int, Float, Float) = ("", 0, 0, 0)
        var failures: [String] = []

        for fixture in Self.trackAFixtures {
            let fixtureURL = try requireGolden("fixtures/\(fixture).exr")
            let image = try Self.decodeFixtureEXR(fixtureURL)

            for (caseName, params) in Self.exposureCases {
                let goldenURL = try requireGolden("output/\(caseName)__\(fixture).exr")
                let golden = try UncompressedEXR.load(goldenURL)
                let pipe = try await runExposurePipe(
                    image: image, params: params, metal: metal
                )
                guard pipe.width == golden.width, pipe.height == golden.height else {
                    failures.append("\(caseName)×\(fixture): size \(pipe.width)×\(pipe.height) vs golden \(golden.width)×\(golden.height)")
                    continue
                }
                let n = golden.width * golden.height
                for i in 0..<n {
                    for c in 0..<3 {
                        let dt = golden.rgb[i * 3 + c]
                        let la = pipe.rgb[i * 3 + c]
                        let rel = abs(la - dt) / max(abs(dt), 1e-9)
                        if rel > maxRelative {
                            maxRelative = rel
                            worst = ("\(caseName)×\(fixture)", i, la, dt)
                        }
                        if rel >= ParityTolerance.elementwiseRelative {
                            let (x, y) = (i % golden.width, i / golden.width)
                            if failures.count < 12 {
                                failures.append(
                                    "\(caseName)×\(fixture) (\(x),\(y)) ch\(c): "
                                        + "lightamer=\(la) dt=\(dt) rel=\(rel)"
                                )
                            }
                        }
                    }
                }
            }
        }

        if !failures.isEmpty {
            dumpFailure(tag: "exposure-parity", detail: failures.joined(separator: "\n"))
        }
        XCTAssertLessThan(
            Double(maxRelative), Double(ParityTolerance.elementwiseRelative),
            "exposure golden parity exceeded \(ParityTolerance.elementwiseRelative) relative "
                + "(max \(maxRelative) at \(worst.0) sample \(worst.1): la=\(worst.2) dt=\(worst.3))\n"
                + failures.prefix(6).joined(separator: "\n")
        )
    }

    /// The Lightamer leg: canonical fixture → [colorin, exposure] pipe →
    /// float32 linear-Rec2020 plane (RGBA) mapped to an RGB triple plane.
    private func runExposurePipe(
        image: DecodedImage, params: ExposureModule.Params, metal: MetalContext
    ) async throws -> UncompressedEXR {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let colorin = await registry.makeBox(opName: ColorInModule.opName)
        let exposure = await registry.makeBox(opName: ExposureModule.opName)
        let exposureBox = try XCTUnwrap(exposure as? ModuleBox<ExposureModule>, "exposure must be registered")
        exposureBox.setParams(params)
        let chain = [try XCTUnwrap(colorin), exposureBox]

        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal) // L014: fence before CPU readback
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
        return UncompressedEXR(width: texture.width, height: texture.height, rgb: rgb)
    }

    // MARK: - Failure dump (Plan T3: diff table + EXR dump to .work/plans/03-01/)

    private func dumpFailure(tag: String, detail: String) {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".work/plans/03-01", isDirectory: true)
            .appendingPathComponent("parity-dump-\(Int(Date().timeIntervalSince1970))-\(tag)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? detail.write(to: dir.appendingPathComponent("diff-table.txt"), atomically: true, encoding: .utf8)
        AppError.logger.error("golden parity failure dump: \(dir.path, privacy: .public)")
    }

    // MARK: - Track B: Phase 2 dual criteria with the new iop inserted

    /// The default chain with `exposure` inserted at its v50 slot — the
    /// chain shape Phase 3 modules will actually ship in.
    private func makeChainWithExposure(
        registry: ModuleRegistry, outputProfile: ColorOutModule.OutputProfile
    ) async throws -> [any ModuleBoxing] {
        await LightamerIOPRegistry.populate(registry)
        var chain = await TerminalTrioTests.makeCommittedDefaultChain(
            registry: registry, outputProfile: outputProfile
        )
        let exposure = await registry.makeBox(opName: ExposureModule.opName)
        let exposureBox = try XCTUnwrap(exposure as? ModuleBox<ExposureModule>)
        exposureBox.setParams(.init()) // default = identity passthrough
        chain.append(exposureBox)
        return chain.sorted { ($0.iopOrder, $0.multiPriority) < ($1.iopOrder, $1.multiPriority) }
    }

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
            out.append((bytes[i + 2], bytes[i + 1], bytes[i])) // BGRA → RGB
        }
        return out
    }

    private func sample3x3(
        _ rgb: [(UInt8, UInt8, UInt8)], width: Int, height: Int, x: Double, y: Double
    ) -> (r: Double, g: Double, b: Double) {
        let cx = Int((x * Double(width - 1)).rounded())
        let cy = Int((y * Double(height - 1)).rounded())
        var rs = 0.0, gs = 0.0, bs = 0.0, n = 0
        for dy in -1...1 {
            for dx in -1...1 {
                let px = min(max(cx + dx, 0), width - 1)
                let py = min(max(cy + dy, 0), height - 1)
                let p = rgb[py * width + px]
                rs += Double(p.0); gs += Double(p.1); bs += Double(p.2); n += 1
            }
        }
        return (rs / Double(n), gs / Double(n), bs / Double(n))
    }

    /// Criterion 1: gray-patch neutrality through the FULL chain (exposure
    /// inserted) — channel spread < 2/255 per patch + level sanity.
    func testTrackBNeutralityWithExposureInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget() // may throw XCTSkip (bundled)
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        let chain = try await makeChainWithExposure(
            registry: ModuleRegistry.makeDefault(), outputProfile: .displayP3
        )
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        let rgb = readRGB8(texture)
        let (w, h) = (texture.width, texture.height)

        var failures: [String] = []
        func srgbEncode(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }
        for patch in Fixtures.neutralPatches {
            let s = sample3x3(rgb, width: w, height: h, x: patch.x, y: patch.y)
            let rg = abs(s.r - s.g), gb = abs(s.g - s.b)
            if rg >= 2 || gb >= 2 {
                failures.append("\(patch.name): |R−G|=\(rg) |G−B|=\(gb)")
            }
            let want = srgbEncode(patch.expectedLinearRec2020.0) * 255.0
            if abs((s.r + s.g + s.b) / 3 - want) > 2 {
                failures.append("\(patch.name): level \((s.r + s.g + s.b) / 3) vs ≈\(want)")
            }
        }
        XCTAssertTrue(
            failures.isEmpty,
            "track B criterion 1 (neutrality with exposure inserted) FAILED:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// Criterion 2 (linear flavor): chain minus gamma (exposure inserted) vs
    /// a CIContext ColorSync direct render into linear-P3 — the Phase 2
    /// cross-consistency semantics must survive the iop insertion.
    func testTrackBCrossConsistencyLinearWithExposureInserted() async throws {
        let metal = try await makeMetal()
        let url = try Fixtures.neutralTarget()
        let decoder = RAWDecoder()
        let image = try await decoder.decode(url)
        var chain = try await makeChainWithExposure(
            registry: ModuleRegistry.makeDefault(), outputProfile: .displayP3
        )
        chain = chain.filter { $0.opName != GammaModule.opName }
        let (texture, _) = try await RenderPipeline.process(
            image: image, instances: chain, imageID: UUID(),
            resolution: .preview, cache: PipeCache(), metal: metal,
            longEdge: nil
        )
        drain(metal)
        XCTAssertEqual(texture.pixelFormat, WorkingSpace.pixelFormat, "no gamma tail → float32")
        var pipeFloats = [Float](repeating: 0, count: texture.width * texture.height * 4)
        pipeFloats.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 16,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }

        guard let p3 = CGColorSpace(name: CGColorSpace.displayP3) else {
            throw XCTSkip("system Display P3 colorspace unavailable")
        }
        let scaled = image.ciImage
        let w = Int(scaled.extent.width), h = Int(scaled.extent.height)
        let linearP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? p3
        let context = CIContext(options: [
            .workingColorSpace: WorkingSpace.colorSpace,
            .outputColorSpace: linearP3,
        ])
        var baseline = [Float](repeating: 0, count: w * h * 4)
        baseline.withUnsafeMutableBytes {
            context.render(
                scaled, toBitmap: $0.baseAddress!, rowBytes: w * 16,
                bounds: scaled.extent, format: CIFormat.RGBAf,
                colorSpace: linearP3
            )
        }

        var maxDiff: Float = 0
        var worst = (0, 0)
        for i in 0..<min(pipeFloats.count, baseline.count) {
            let d = abs(pipeFloats[i] - baseline[i])
            if d > maxDiff {
                maxDiff = d
                worst = (i / 4 % texture.width, i / 4 / texture.width)
            }
        }
        XCTAssertLessThan(
            Double(maxDiff), 0.004,
            "track B criterion 2 (linear, exposure inserted): pipe vs ColorSync diverges "
                + "\(maxDiff) (worst at \(worst.0),\(worst.1))"
        )
    }

    /// CIContext render needs the SOURCE colorspace as the bitmap's declared
    /// space when comparing linear domains (mirrors the 02-04 harness's
    /// linearFloat flavor). Placeholder retained for the Phase 3 plans that
    /// extend the track-B baseline flavors.
    private func contextWorkingSpaceFallback(_ p3: CGColorSpace) -> CGColorSpace {
        p3
    }

    // MARK: - Registration (T5 acceptance)

    func testExposureRegisteredAtV50Slot21() async throws {
        let registry = ModuleRegistry.makeDefault()
        await LightamerIOPRegistry.populate(registry)
        let box = await registry.makeBox(opName: ExposureModule.opName)
        let exposureBox = try XCTUnwrap(box as? ModuleBox<ExposureModule>)
        XCTAssertEqual(ExposureModule.opName, "exposure")
        XCTAssertEqual(ExposureModule.iopOrder, 21.0)
        XCTAssertEqual(ExposureModule.defaultColorspace, .RGB)
        let id = UUID()
        let restored = await registry.makeBox(opName: ExposureModule.opName, instanceID: id)
        XCTAssertEqual(restored?.instanceID, id, "identity-restoring init wired")
        _ = exposureBox
    }

    /// The GPU leg of the module acceptance: 0.25 gray +1EV → 0.5 ± 1e-6
    /// through the actual kernel (dispatch → drain → readback, L014).
    func testExposureKernelHalfStop() async throws {
        let metal = try await makeMetal()
        let module = ExposureModule()
        var piece = IOPiece()
        module.commitParams(ExposureModule.Params(exposure: 1.0), into: &piece)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 4, height: 4, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        let input = metal.device.makeTexture(descriptor: descriptor)!
        let output = metal.device.makeTexture(descriptor: descriptor)!
        var pixels = [Float](repeating: 0.25, count: 4 * 4 * 4)
        for i in 0..<(4 * 4) { pixels[i * 4 + 3] = 1.0 } // opaque alpha; kernel passes it through
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
        for (i, v) in out.enumerated() {
            let expected: Float = i % 4 == 3 ? 1.0 : 0.5 // alpha passthrough
            XCTAssertEqual(v, expected, accuracy: 1e-6, "sample \(i)")
        }
    }
}
