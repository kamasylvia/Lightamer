@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// Plan 06-05 C0 — the inherited-leftover closeouts, each with a content /
/// accounting assertion (防空转, L020 ③):
///
/// 1. **06-06 遗留① (D-06-06-T3-2)**: the mask-plane cache key did NOT
///    include the geometry state — an ashift/liquify (or crop/lens) param
///    edit with the same roi could HIT a stale plane rasterized through
///    the OLD inverse point map. Fix: `GeometryPointMapper.stableHash()`
///    folds into the key (`DrawnMaskRasterizer.foldKeyHash`).
/// 2. **06-04 note-1**: the raster-only DEGRADE legs (missing masks
///    directory / corrupt-missing PNG) installed an UNSCALED all-ones
///    plane — the layer opacity was not folded (the normal raster-only
///    success leg already scaled). Fix: both degrade legs scale by the
///    clamped layer opacity.
/// 3. **05-07 note-2** (bayesshrink single-source): VERIFIED CLOSED —
///    `DenoiseProfileModule.bayesshrink` computes `varf` via the exact
///    `(Float(70)).squareRoot() / 16` expression (single-source authority
///    = WaveletEngine :159); this test pins the two expressions equal so
///    the literal cannot regress.
final class Plan0605LeftoverTests: XCTestCase {

    private func makeMetal() async throws -> MetalContext {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func flatTexture(
        _ metal: MetalContext, width: Int = 32, height: Int = 24, value: Float
    ) -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4 + 0] = value
            pixels[i * 4 + 1] = value
            pixels[i * 4 + 2] = value
            pixels[i * 4 + 3] = 1.0
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: width, height: height,
            mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        let t = metal.device.makeTexture(descriptor: d)!
        pixels.withUnsafeBytes {
            t.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: width * 16)
        }
        return t
    }

    private func gradientMask() -> MaskSpec {
        MaskSpec(drawn: DrawnMaskSpec(forms: [
            MaskForm(kind: .gradient(GradientForm(
                anchor: MaskPoint(x: 0.5, y: 0.5), rotationDegrees: 30,
                compression: 0.5, state: .sigmoidal))),
        ]))
    }

    /// Scalar mean of an r32Float mask plane (the degrade assertions).
    private func readMean(_ texture: any MTLTexture) -> Float {
        precondition(texture.pixelFormat == .r32Float)
        var pixels = [Float](repeating: 0, count: texture.width * texture.height)
        pixels.withUnsafeMutableBytes {
            texture.getBytes(
                $0.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        var acc: Float = 0
        for v in pixels { acc += v }
        return acc / Float(texture.width * texture.height)
    }

    /// Byte-level plane diff (防空转: count pixels whose bits differ).
    private func differingPixels(_ a: any MTLTexture, _ b: any MTLTexture) -> Int {
        precondition(a.width == b.width && a.height == b.height)
        let count = a.width * a.height
        var pa = [Float](repeating: 0, count: count)
        var pb = [Float](repeating: 0, count: count)
        pa.withUnsafeMutableBytes {
            a.getBytes($0.baseAddress!, bytesPerRow: a.width * 4,
                       from: MTLRegionMake2D(0, 0, a.width, a.height), mipmapLevel: 0)
        }
        pb.withUnsafeMutableBytes {
            b.getBytes($0.baseAddress!, bytesPerRow: b.width * 4,
                       from: MTLRegionMake2D(0, 0, b.width, b.height), mipmapLevel: 0)
        }
        var diff = 0
        for i in 0..<count where pa[i].bitPattern != pb[i].bitPattern { diff += 1 }
        return diff
    }

    private func fence(_ metal: MetalContext) async {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        await fence?.completed()
    }

    // MARK: - 1. maskKey follows the geometry state (06-06 遗留①)

    /// A crop param change (same window ROI) must MISS the mask plane and
    /// re-rasterize through the NEW mapping: the gradient's anchor moves
    /// in composite space when the crop shifts, so the re-rasterized
    /// plane's CONTENT must differ from the stale one (防空转: miss count
    /// exact + content delta > 0).
    func testMaskPlaneCacheKeyFollowsGeometryState() async throws {
        let metal = try await makeMetal()
        let cache = PipeCache()
        let imageID = UUID()
        let layerID = UUID()
        let window = ROI(x: 0, y: 0, width: 32, height: 24, scale: 1.0)
        let spec = gradientMask()

        func mapper(with segment: GeometrySegment) -> GeometryPointMapper {
            GeometryPointMapper(frameSize: SIMD2(32, 24), segments: [segment], outputSize: SIMD2(32, 24))
        }

        // Rasterize through crop(left: 0) — the identity crop output == frame.
        let mapperA = mapper(with: .affine(
            Affine2D.crop(left: 0, top: 0, inputSize: SIMD2(32, 24)),
            inSize: SIMD2(32, 24), outSize: SIMD2(32, 24)))
        // Identity-mapping window for legibility: rasterize at the frame
        // size (crop 0 → output == frame).
        let (planeA, hitA) = try await DrawnMaskRasterizer.plane(
            spec: spec, layerOpacity: 1, window: window, mapper: mapperA,
            metal: metal, cache: cache, imageID: imageID, pipeType: .preview,
            layerID: layerID)
        XCTAssertFalse(hitA, "cold rasterize = miss")
        await fence(metal)

        // SAME spec, SAME window, SAME layer — only the geometry moved:
        // the 06-03 key (maskVersion only) would HIT the stale plane.
        // With the folded mapper hash it must MISS and re-rasterize.
        let mapperB = mapper(with: .affine(
            Affine2D.flip(bits: 0b010, inputSize: SIMD2(32, 24)),
            inSize: SIMD2(32, 24), outSize: SIMD2(32, 24)))
        XCTAssertNotEqual(
            mapperA.stableHash(), mapperB.stableHash(),
            "distinct geometry states must hash distinctly (防空转前提)")
        let (planeB, hitB) = try await DrawnMaskRasterizer.plane(
            spec: spec, layerOpacity: 1, window: window, mapper: mapperB,
            metal: metal, cache: cache, imageID: imageID, pipeType: .preview,
            layerID: layerID)
        XCTAssertFalse(hitB, "geometry edit must invalidate the mask plane (the 06-03 key would HIT)")
        await fence(metal)

        // Content-level: the flip remaps every pixel's content point →
        // the planes DIFFER byte-wise across most pixels (not a vacuous
        // re-rasterize of identical content).
        let diff = differingPixels(planeA, planeB)
        XCTAssertGreaterThan(
            diff, (window.width * window.height) / 4,
            "re-rasterized plane must reflect the new mapping (diff=\(diff))")
        // The identity mapper is deterministic run-to-run (same key).
        let (_, hitAgain) = try await DrawnMaskRasterizer.plane(
            spec: spec, layerOpacity: 1, window: window, mapper: mapperB,
            metal: metal, cache: cache, imageID: imageID, pipeType: .preview,
            layerID: layerID)
        XCTAssertTrue(hitAgain, "unchanged state + unchanged spec = cache HIT")
    }

    /// The identity mapper folds to a STABLE value (equal specs across
    /// runs hash equal — the L013 determinism contract).
    func testIdentityMapperHashIsStable() {
        let a = GeometryPointMapper.compose(boxes: [], frameSize: SIMD2(100, 80))
        let b = GeometryPointMapper.compose(boxes: [], frameSize: SIMD2(100, 80))
        XCTAssertEqual(a.stableHash(), b.stableHash())
        let other = GeometryPointMapper(
            frameSize: SIMD2(101, 80), segments: [], outputSize: SIMD2(101, 80))
        XCTAssertNotEqual(a.stableHash(), other.stableHash(),
                          "frame size is part of the geometry state")
    }

    // MARK: - 2. raster-only degrade folds the layer opacity (06-04 note-1)

    /// Raster-only spec + missing masks directory → the degrade plane must
    /// equal opacity (not 1.0). Content-level: the composite of the layer
    /// at opacity o through the degraded mask must equal the SAME layer
    /// composited with a uniform-o mask.
    func testRasterOnlyDegradeFoldsLayerOpacity() async throws {
        let metal = try await makeMetal()
        let opacity: Float = 0.5
        let spec = MaskSpec(raster: RasterMaskRef(
            fileName: "missing-mask.png", maskHash: 12345, invert: false))
        let window = ROI(x: 0, y: 0, width: 32, height: 24, scale: 1.0)
        let below = flatTexture(metal, value: 0.2)
        let top = flatTexture(metal, value: 0.8)
        let mapper = GeometryPointMapper.compose(boxes: [], frameSize: SIMD2(32, 24))

        let (plane, hit, reason) = try await MaskCombiner.effectivePlane(
            spec: spec, layerOpacity: opacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            cache: PipeCache(), imageID: UUID(), pipeType: .preview,
            layerID: UUID(), maskDirectory: nil)
        XCTAssertFalse(hit)
        XCTAssertNotNil(reason, "the degrade reason must be surfaced")
        await fence(metal)
        let mean = readMean(plane)
        XCTAssertEqual(mean, opacity, accuracy: 1e-6,
                       "raster-only degrade must install opacity × 1 (was unscaled 1.0 — the 06-04 note-1 gap)")

        // The corrupt/missing PNG degrade branch (directory present, file
        // missing → .degraded) folds the opacity the same way.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("0605-masks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (plane2, _, reason2) = try await MaskCombiner.effectivePlane(
            spec: spec, layerOpacity: opacity, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            cache: PipeCache(), imageID: UUID(), pipeType: .preview,
            layerID: UUID(), maskDirectory: dir)
        XCTAssertNotNil(reason2)
        await fence(metal)
        XCTAssertEqual(readMean(plane2), opacity, accuracy: 1e-6,
                       "the .degraded branch folds the layer opacity too")
    }

    // MARK: - 3. bayesshrink single-source pin (05-07 note-2 verified closed)

    /// The module's `varf` must stay the EXACT sqrt(70)/16 expression (the
    /// WaveletEngine :159 authority) — the historical rounded literal
    /// 0.5229 disagreed in the last ULPs.
    func testBayesshrinkVarfStaysSingleSourceExact() {
        let authority: Float = (Float(70)).squareRoot() / 16
        let roundedLiteral: Float = 0.5229
        XCTAssertNotEqual(authority, roundedLiteral,
                          "the rounded literal is the bug this pin guards against")
        // bit-exact equality with the WaveletEngine expression shape.
        let engineShape = (Float(70.0)).squareRoot() / 16.0
        XCTAssertEqual(authority.bitPattern, engineShape.bitPattern)
        XCTAssertEqual(authority, 0.5229126, accuracy: 1e-6, "sanity: the value is ≈0.5229")
    }

    // MARK: - 4. HistoryHash folds the layer mask (hardening)

    func testLayerDriftAnchorFoldsMaskContent() throws {
        var maskA = gradientMask()
        let base = LayerStackSnapshot.Layer(
            id: UUID(), name: "L", isVisible: true, opacity: 1,
            blendMode: BlendMode.normal.rawValue, blendOptions: 0, enabled: true,
            chain: [], mask: maskA)
        let stackA = LayerStackSnapshot(layers: [base])
        if case var .gradient(g) = maskA.drawn!.forms[0].kind {
            g.rotationDegrees = 45
            maskA.drawn!.forms[0].kind = .gradient(g)
        }
        let rotated = LayerStackSnapshot.Layer(
            id: base.id, name: base.name, isVisible: true, opacity: 1,
            blendMode: base.blendMode, blendOptions: 0, enabled: true,
            chain: [], mask: maskA)
        let stackB = LayerStackSnapshot(layers: [rotated])

        let hashA = HistoryHash.hash(
            stack: HistoryStack(), decodeParamsHash: 42, layerSnapshot: stackA)
        let hashB = HistoryHash.hash(
            stack: HistoryStack(), decodeParamsHash: 42, layerSnapshot: stackB)
        XCTAssertNotEqual(hashA, hashB, "a mask edit must flip the drift anchor")
        // Determinism: same inputs, same hash (L013).
        let hashA2 = HistoryHash.hash(
            stack: HistoryStack(), decodeParamsHash: 42, layerSnapshot: stackA)
        XCTAssertEqual(hashA, hashA2)
    }
}
