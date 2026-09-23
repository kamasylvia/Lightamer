@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-04 T4 — the raster mask gates: bake → sidecar PNG → load
/// round-trip identity (uint16-exact through the IO), the quantization
/// bound vs the source float plane, the decimal-String hash lock, and the
/// REAL constructed failure legs (truncated PNG with a recomputed hash →
/// corrupt branch; tampered hash → mismatch branch; missing file) degrading
/// per D-06-04-T4-2, plus the sidecar payload freeze (06-03 documents
/// decode; the 06-04 spelling round-trips byte-stable).
final class RasterMaskRoundTripTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func makeR32(
        _ w: Int, _ h: Int, metal: MetalContext, value: (Int, Int) -> Float
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { pixels[y * w + x] = value(x, y) } }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let texture = try XCTUnwrap(metal.device.makeTexture(descriptor: d))
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: w * 4)
        }
        return texture
    }

    private func readMask(_ t: any MTLTexture, metal: MetalContext) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var out = [Float](repeating: 0, count: t.width * t.height)
        out.withUnsafeMutableBytes {
            t.getBytes(
                $0.baseAddress!, bytesPerRow: t.width * 4,
                from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return out
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lra-raster-mask-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - The round trip

    func testBakeLoadRoundTripIdentity() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 37, h = 23 // non-multiple sizes exercise bytesPerRow handling
        let source = try makeR32(w, h, metal: metal) { x, y in
            // ramps + HDR >1 (clamps at bake) + negatives (clamps at bake)
            0.9 * Float(x) / Float(w - 1) + 0.05 * Float(y % 3)
                + ((x + y) % 11 == 0 ? 1.4 : 0.0) + ((x * y) % 17 == 0 ? -0.2 : 0.0)
        }
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ref = try await RasterMaskStore.bake(
            plane: source, directory: dir, fileName: "mask-1.png",
            invert: false, metal: metal)
        XCTAssertEqual(ref.fileName, "mask-1.png")
        XCTAssertFalse(ref.invert)

        // The persisted hash is over the FILE BYTES (StableHash, the only
        // legal generator) and verify() is clean.
        let fileBytes = try Data(contentsOf: dir.appendingPathComponent("mask-1.png"))
        XCTAssertEqual(ref.maskHash, StableHash.hash(fileBytes))
        XCTAssertNil(RasterMaskStore.verify(ref: ref, directory: dir))

        // Load: uint16-EXACT identity + the quantization bound.
        let loaded: any MTLTexture
        if case let .plane(p) = try await RasterMaskStore.load(
            ref: ref, directory: dir, windowWidth: w, windowHeight: h, metal: metal)
        {
            loaded = p
        } else {
            return XCTFail("round-trip load degraded — the intact leg must not")
        }
        let got = readMask(loaded, metal: metal)
        let src = readMask(source, metal: metal)
        var compared = 0
        for i in 0..<src.count {
            let quantized = UInt16((Double(min(max(src[i], 0), 1)) * 65535.0).rounded())
            // uint16 identity: the loaded value decodes EXACTLY the baked one.
            XCTAssertEqual(got[i], Float(quantized) / 65535.0, accuracy: 1e-9,
                           "round-trip identity broken at \(i)")
            // The documented quantization bound vs the SOURCE float plane.
            XCTAssertEqual(
                got[i], min(max(src[i], 0), 1), accuracy: 1.0 / 65535.0 + 1e-6,
                "quantization bound exceeded at \(i)")
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
    }

    // MARK: - The degrade legs (REAL constructed failures)

    func testTamperedHashDegrades() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 16, h = 12
        let source = try makeR32(w, h, metal: metal) { x, _ in Float(x) / Float(w - 1) }
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = try await RasterMaskStore.bake(
            plane: source, directory: dir, fileName: "m.png",
            invert: false, metal: metal)

        // Swap the PNG with a DIFFERENT one (same geometry) — the file
        // bytes changed so the reference hash no longer matches.
        let other = try makeR32(w, h, metal: metal) { x, _ in 1.0 - Float(x) / Float(w - 1) }
        _ = try await RasterMaskStore.bake(
            plane: other, directory: dir, fileName: "m.png",
            invert: false, metal: metal)
        XCTAssertNotNil(RasterMaskStore.verify(ref: ref, directory: dir))

        if case let .degraded(_, reason) = try await RasterMaskStore.load(
            ref: ref, directory: dir, windowWidth: w, windowHeight: h, metal: metal)
        {
            XCTAssertTrue(reason.contains("hash mismatch"), "reason: \(reason)")
        } else {
            XCTFail("tampered file must degrade, not load")
        }
    }

    func testCorruptPNGBakesDegrade() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 16, h = 12
        let source = try makeR32(w, h, metal: metal) { x, _ in Float(x) / Float(w - 1) }
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = try await RasterMaskStore.bake(
            plane: source, directory: dir, fileName: "m.png",
            invert: false, metal: metal)

        // Construct a REALLY corrupt file: truncate the PNG to half, then
        // re-point the reference at the corrupt bytes' hash — so the
        // DECODE leg fails (not the hash leg).
        let fileURL = dir.appendingPathComponent("m.png")
        var bytes = try Data(contentsOf: fileURL)
        bytes = bytes.prefix(bytes.count / 2)
        try bytes.write(to: fileURL)
        let corruptRef = RasterMaskRef(
            fileName: ref.fileName, maskHash: StableHash.hash(bytes), invert: false)
        XCTAssertNil(RasterMaskStore.verify(ref: corruptRef, directory: dir),
                     "the corrupt file matches its own hash — decode must fail")

        if case let .degraded(_, reason) = try await RasterMaskStore.load(
            ref: corruptRef, directory: dir, windowWidth: w, windowHeight: h, metal: metal)
        {
            XCTAssertTrue(reason.contains("corrupt"), "reason: \(reason)")
        } else {
            XCTFail("a structurally broken PNG must degrade, not load")
        }
    }

    func testMissingFileDegrades() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let ref = RasterMaskRef(
            fileName: "gone.png", maskHash: 0x1234, invert: false)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(RasterMaskStore.verify(ref: ref, directory: dir)?.contains("missing"), true)
        if case let .degraded(_, reason) = try await RasterMaskStore.load(
            ref: ref, directory: dir, windowWidth: 8, windowHeight: 8, metal: metal)
        {
            XCTAssertTrue(reason.contains("missing"), "reason: \(reason)")
        } else {
            XCTFail("a missing file must degrade, not load")
        }
    }

    func testInvertLegOnLoad() async throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 16, h = 12
        let source = try makeR32(w, h, metal: metal) { x, _ in Float(x) / Float(w - 1) }
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ref = try await RasterMaskStore.bake(
            plane: source, directory: dir, fileName: "m.png",
            invert: true, metal: metal)
        XCTAssertTrue(ref.invert)
        guard case let .plane(plane) = try await RasterMaskStore.load(
            ref: ref, directory: dir, windowWidth: w, windowHeight: h, metal: metal)
        else { return XCTFail("invert load degraded") }
        let got = readMask(plane, metal: metal)
        var compared = 0
        for y in 0..<h {
            for x in 0..<w {
                XCTAssertEqual(
                    got[y * w + x], 1.0 - Float(x) / Float(w - 1), accuracy: 1e-6,
                    "invert leg wrong at \(x),\(y)")
                compared += 1
            }
        }
        XCTAssertGreaterThan(compared, 0, "防空转: nothing compared")
    }

    // MARK: - The sidecar payload freeze (T4 action 3)

    /// The 06-03 spelling (drawn payload only, no parametric/raster keys)
    /// round-trips byte-stably and the additive optionals STAY ABSENT from
    /// the canonical bytes — which pins `stableHash` stability for
    /// pre-06-04 documents (the hash consumes exactly these bytes). The
    /// 06-04 full payload also round-trips byte-stably, and the raster
    /// hash rides the decimal-String lock.
    func testSidecarPayloadFreezeForwardCompatibility() throws {
        // The 06-03-era spec: drawn only.
        let oldSpec = MaskSpec(
            version: 1,
            drawn: DrawnMaskSpec(forms: [
                MaskForm(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    kind: .ellipse(EllipseForm(
                        center: MaskPoint(x: 0.5, y: 0.5), radiusX: 0.12,
                        radiusY: 0.12, rotationDegrees: 0, border: 0))),
            ]))
        XCTAssertNil(oldSpec.parametric)
        XCTAssertNil(oldSpec.raster)

        let canonical = ParamsCoding.encode(oldSpec)
        let canonicalJSON = String(data: canonical, encoding: .utf8)!
        XCTAssertFalse(canonicalJSON.contains("parametric"), canonicalJSON)
        XCTAssertFalse(canonicalJSON.contains("raster"), canonicalJSON)
        XCTAssertFalse(canonicalJSON.contains("maskHash"), canonicalJSON)
        // Byte-stable round trip (decode → encode == the same bytes).
        let decoded = try JSONDecoder().decode(MaskSpec.self, from: canonical)
        XCTAssertEqual(ParamsCoding.encode(decoded), canonical)

        // The 06-04 full payload round-trips byte-stably too.
        var full = oldSpec
        full.parametric = ParametricMask(
            domain: .jzczhz,
            channels: [.init(channel: 8, curve: .init(points: [0.1, 0.2, 0.3, 0.4], boost: -1))],
            blurRadius: 2, contrast: 0.2, brightness: -0.1, invert: true)
        full.raster = RasterMaskRef(fileName: "abc.png", maskHash: 0xDEAD_BEEF_CAFE, invert: true)
        let once = ParamsCoding.encode(full)
        let twice = ParamsCoding.encode(
            try JSONDecoder().decode(MaskSpec.self, from: once))
        XCTAssertEqual(once, twice, "06-04 payload round-trip must be byte-stable")

        // The decimal-String lock: maskHash appears as a JSON STRING with
        // the exact decimal spelling of the UInt64.
        let json = String(data: once, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"maskHash\":\"\(String(0xDEAD_BEEF_CAFE))\""),
                      "maskHash must be a decimal String, got: \(json)")
    }

    /// Equal specs hash equal; flipping a 06-04 payload flips the hash
    /// (the mask-plane cache key follows all three payloads).
    func testMaskHashCoversAllThreePayloads() {
        var base = MaskSpec()
        base.drawn = DrawnMaskSpec(forms: [])
        let empty = base.stableHash()
        base.parametric = ParametricMask(
            domain: .luma,
            channels: [.init(channel: 0, curve: .init(points: [0.1, 0.2, 0.3, 0.4]))])
        let withParam = base.stableHash()
        base.raster = RasterMaskRef(fileName: "x.png", maskHash: 7)
        let withRaster = base.stableHash()
        XCTAssertNotEqual(empty, withParam)
        XCTAssertNotEqual(withParam, withRaster)
        // Determinism: equal spec → equal hash.
        XCTAssertEqual(MaskSpec(drawn: base.drawn, parametric: base.parametric, raster: base.raster).stableHash(),
                       withRaster)
    }
}
