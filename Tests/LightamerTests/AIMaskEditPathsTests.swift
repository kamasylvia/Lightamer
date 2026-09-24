@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// AI-07 五条覆盖路径 E2E (Plan 07-3 T4) — "可编辑非黑箱" at the CONTENT
// level (L020 防空转): every path asserts plane-direction changes, cache
// bookkeeping, or byte-level payload facts — never "a mask exists".
//
// The five user override paths (07-RESEARCH §4):
//   (a) drawn 笔画 union/difference 修补  → group combine ⊗ raster intersect
//   (b) parametric ⊓ 收紧               → three-payload ⊗ assembly
//   (c) invert                          → RasterMaskRef.invert (load leg)
//   (d) 羽化重 bake                      → bake(featherRadius:) soft edge
//   (e) refine 点重生成                   → same maskID overwrite re-bake
//
// All five reuse the Phase 6 machinery — Phase 7 ships ZERO new mask
// primitives beyond the bake feather (07-CONTEXT). The AI "generation" is
// simulated by baking a synthetic plane through the SAME bake pipeline the
// real service feeds (the inference legs are pinned by the 07-1/07-2
// suites and the GUI round).
@MainActor
final class AIMaskEditPathsTests: XCTestCase {

    private var tempDirectory: URL!
    private var metal: MetalContext!
    private var cache: PipeCache!
    private var imageID: UUID!
    private var layerID: UUID!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("aimaskedit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("no Metal GPU")
        }
        metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        cache = PipeCache()
        imageID = UUID()
        layerID = UUID()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Synthetic planes

    private let size = (w: 32, h: 32)

    /// Half-plane mask: 1 where x < fraction of the width.
    private func leftPlane(_ fraction: Float) -> AIMaskPlane {
        AIMaskPlane(
            width: size.w, height: size.h,
            floats: (0..<(size.w * size.h)).map { i in
                (Float(i % size.w) + 0.5) / Float(size.w) < fraction ? 1 : 0
            })
    }

    /// Bake a plane into the sidecar raster channel (the SAME pipeline the
    /// real AI service feeds: plane → r32Float texture → bake).
    private func bake(
        _ plane: AIMaskPlane, fileName: String, invert: Bool = false,
        feather: Float = 0
    ) async throws -> RasterMaskRef {
        try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(from: plane, metal: metal),
            directory: tempDirectory, fileName: fileName,
            invert: invert, featherRadius: feather, metal: metal)
    }

    /// The working-space RGBA plane for the parametric leg's luma sampling:
    /// TOP half at luma 0.5 (inside the 0.3-0.7 blendif window), bottom
    /// half at 0.05 (outside — the tighten leg must zero it).
    private func makeTopBrightPlane() async throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, width: size.w, height: size.h,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.deviceUnavailable
        }
        var pixels = [Float](repeating: 0, count: size.w * size.h * 4)
        for y in 0..<size.h {
            for x in 0..<size.w {
                let luma: Float = Float(y) < Float(size.h) / 2 ? 0.5 : 0.05
                let i = (y * size.w + x) * 4
                pixels[i + 0] = luma
                pixels[i + 1] = luma
                pixels[i + 2] = luma
                pixels[i + 3] = 1
            }
        }
        pixels.withUnsafeBytes {
            texture.replace(
                region: MTLRegionMake2D(0, 0, size.w, size.h), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: size.w * 16)
        }
        return texture
    }

    /// The assembled effective mask plane bytes (the composite's OWN
    /// assembly path — not a reimplementation). `below`/`top` are the
    /// blendif sampling planes (the composite feeds the real planes; the
    /// raster-only paths never touch them).
    private func effective(
        _ spec: MaskSpec, below: (any MTLTexture)? = nil, top: (any MTLTexture)? = nil
    ) async throws -> [Float] {
        let window = ROI(x: 0, y: 0, width: size.w, height: size.h, scale: 1.0)
        let mapper = GeometryPointMapper.compose(
            boxes: [], frameSize: SIMD2(Double(size.w), Double(size.h)))
        // TextureBox: the driver's @unchecked-Sendable ownership wrapper —
        // the caller's planes are read-only inside the assembly.
        let belowBox = below.map(TextureBox.init)
        let topBox = top.map(TextureBox.init)
        let belowPlane: any MTLTexture
        if let belowBox { belowPlane = belowBox.texture }
        else { belowPlane = try await MaskCombiner.fill(1, width: size.w, height: size.h, metal: metal) }
        let topPlane: any MTLTexture
        if let topBox { topPlane = topBox.texture }
        else { topPlane = try await MaskCombiner.fill(1, width: size.w, height: size.h, metal: metal) }
        let (plane, _, degraded) = try await MaskCombiner.effectivePlane(
            spec: spec, layerOpacity: 1.0, window: window,
            below: belowPlane, top: topPlane, mapper: mapper, metal: metal,
            cache: cache, imageID: imageID, pipeType: .preview, layerID: layerID,
            maskDirectory: tempDirectory)
        XCTAssertNil(degraded, "the AI-mask assembly must load cleanly")
        return Self.readPlane(plane, width: size.w, height: size.h, metal: metal)
    }

    /// L014-fenced plane read-back (SYNC helper — waitUntilCompleted is
    /// unavailable from async contexts; the RasterMaskStore pattern).
    nonisolated private static func readPlane(
        _ texture: any MTLTexture, width: Int, height: Int, metal: MetalContext
    ) -> [Float] {
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()
        var floats = [Float](repeating: -1, count: width * height)
        floats.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return floats
    }

    private func sample(_ floats: [Float], _ nx: Float, _ ny: Float) -> Float {
        let x = min(size.w - 1, max(0, Int(nx * Float(size.w))))
        let y = min(size.h - 1, max(0, Int(ny * Float(size.h))))
        return floats[y * size.w + x]
    }

    // MARK: - (a) drawn 笔画 union/difference 修补

    /// The user patches the AI mask with drawn strokes: the drawn GROUP
    /// (brush union − ellipse difference) intersects the raster payload —
    /// a drawn difference REMOVES a region, the raster bound still holds
    /// (drawing cannot resurrect what the AI mask excludes).
    func testDrawnPatchDifferenceRepairDirection() async throws {
        let ref = try await bake(leftPlane(0.5), fileName: "ai-patch.png")

        let brush = MaskForm(kind: .brush(BrushStroke(
            points: [
                BrushPoint(
                    corner: MaskPoint(x: 0.1, y: 0.5), ctrl1: MaskPoint(x: 0.1, y: 0.5),
                    ctrl2: MaskPoint(x: 0.9, y: 0.5)),
                BrushPoint(
                    corner: MaskPoint(x: 0.9, y: 0.5), ctrl1: MaskPoint(x: 0.9, y: 0.5),
                    ctrl2: MaskPoint(x: 0.9, y: 0.5)),
            ],
            radius: 0.12, hardness: 1.0, density: 1.0, opacity: 1.0)))
        let ellipse = MaskForm(kind: .ellipse(EllipseForm(
            center: MaskPoint(x: 0.25, y: 0.5), radiusX: 0.07, radiusY: 0.1,
            rotationDegrees: 0, border: 0)))
        let spec = MaskSpec(
            drawn: DrawnMaskSpec(
                forms: [brush, ellipse],
                group: MaskGroupSpec(items: [
                    MaskGroupItem(formID: brush.id, op: .union, inverted: false, opacity: 1),
                    MaskGroupItem(formID: ellipse.id, op: .difference, inverted: false, opacity: 1),
                ])),
            raster: ref)

        let floats = try await effective(spec)
        XCTAssertEqual(sample(floats, 0.4, 0.5), 1.0, accuracy: 0.01,
                       "raster ∩ band, outside the difference → kept")
        XCTAssertEqual(sample(floats, 0.25, 0.5), 0.0, accuracy: 0.01,
                       "the drawn difference REMOVES its region")
        XCTAssertEqual(sample(floats, 0.4, 0.08), 0.0, accuracy: 0.01,
                       "raster but outside the band → the patch cannot extend")
        XCTAssertEqual(sample(floats, 0.8, 0.5), 0.0, accuracy: 0.01,
                       "band but outside the raster → the patch cannot resurrect")
    }

    // MARK: - (b) parametric ⊓ 收紧

    /// A parametric payload TIGHTENS the AI mask: effective = raster ⊓
    /// luma-selection (top-bright ⊗ left-half raster = the top-left
    /// quadrant, everywhere else 0).
    func testParametricIntersectTightensRaster() async throws {
        let ref = try await bake(leftPlane(0.5), fileName: "ai-tighten.png")
        let spec = MaskSpec(
            parametric: ParametricMask(
                domain: .luma,
                channels: [.init(
                    channel: 0, // the luma Y slot
                    curve: .init(points: [0.3, 0.4, 0.6, 0.7]))]),
            raster: ref)

        // The blendif leg samples the WORKING planes — feed the synthetic
        // top-bright plane as both (the composite feeds the real planes).
        let sampling = try await makeTopBrightPlane()
        let floats = try await effective(spec, below: sampling, top: sampling)
        XCTAssertEqual(sample(floats, 0.25, 0.25), 1.0, accuracy: 0.01,
                       "bright ∩ raster → kept")
        XCTAssertEqual(sample(floats, 0.25, 0.75), 0.0, accuracy: 0.01,
                       "dark side → the parametric leg TIGHTENS the AI mask")
        XCTAssertEqual(sample(floats, 0.75, 0.25), 0.0, accuracy: 0.01,
                       "bright but outside the raster → still excluded")
        XCTAssertEqual(sample(floats, 0.75, 0.75), 0.0, accuracy: 0.01)
    }

    // MARK: - (c) invert

    /// `RasterMaskRef.invert` flips the loaded plane (dt raster_mask_invert)
    /// — the pixel data stays untouched on disk (the ref alone carries the
    /// toggle, and toggling it back is byte-neutral).
    func testInvertFlipsEffectivePlane() async throws {
        let ref = try await bake(leftPlane(0.5), fileName: "ai-invert.png")
        let plain = try await effective(MaskSpec(raster: ref))
        XCTAssertEqual(sample(plain, 0.25, 0.5), 1.0, accuracy: 0.01)
        XCTAssertEqual(sample(plain, 0.75, 0.5), 0.0, accuracy: 0.01)

        var invertedRef = ref
        invertedRef.invert = true
        let flipped = try await effective(MaskSpec(raster: invertedRef))
        XCTAssertEqual(sample(flipped, 0.25, 0.5), 0.0, accuracy: 0.01,
                       "invert flips the kept side")
        XCTAssertEqual(sample(flipped, 0.75, 0.5), 1.0, accuracy: 0.01)

        // Toggling back: the original effective plane returns exactly.
        let restored = try await effective(MaskSpec(raster: ref))
        XCTAssertEqual(restored, plain, "invert off → byte-identical to the original")
    }

    // MARK: - (d) 羽化重 bake

    /// Re-baking with a feather radius: a NEW file identity (hash flip →
    /// cache invalidation) and SOFT edges — the feathered bake carries
    /// strictly-intermediate values at the boundary the crisp bake does
    /// not (the 07-1 geometry suite pins the profile; this pins the E2E
    /// direction at the file level).
    func testFeatherRebakeSoftensEdgesAndFlipsIdentity() async throws {
        let plane = leftPlane(0.5)
        let crisp = try await bake(plane, fileName: "ai-crisp.png")
        let feathered = try await bake(plane, fileName: "ai-crisp.png", feather: 3)
        XCTAssertNotEqual(feathered.maskHash, crisp.maskHash,
                          "the feather re-bake flips the file identity")

        // The two variants under separate names → compare the PIXELS.
        _ = try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(from: plane, metal: metal),
            directory: tempDirectory, fileName: "c.png",
            invert: false, featherRadius: 0, metal: metal)
        _ = try await RasterMaskStore.bake(
            plane: AIMaskResample.texture(from: plane, metal: metal),
            directory: tempDirectory, fileName: "f.png",
            invert: false, featherRadius: 3, metal: metal)
        let crispData = try Data(contentsOf: tempDirectory.appendingPathComponent("c.png"))
        let featherData = try Data(contentsOf: tempDirectory.appendingPathComponent("f.png"))
        XCTAssertNotEqual(crispData, featherData)
        let (cPixels, cw, ch) = try RasterMaskStore.decodeGray16PNG(data: crispData)
        let (fPixels, fw, fh) = try RasterMaskStore.decodeGray16PNG(data: featherData)
        XCTAssertEqual(cw, fw)
        XCTAssertEqual(ch, fh)

        // Boundary column (the x = half-width edge): the feather pulls the
        // boundary values down (Gaussian spread) while the interior — far
        // from the edge — stays byte-stable.
        func columnMean(_ pixels: [UInt16], _ x: Int) -> Double {
            var sum = 0.0
            for y in 0..<ch { sum += Double(pixels[y * cw + x]) / 65535.0 }
            return sum / Double(ch)
        }
        let edge = cw / 2
        let crispEdge = columnMean(cPixels, edge - 2)
        let featherEdge = columnMean(fPixels, edge - 2)
        XCTAssertGreaterThan(crispEdge, featherEdge,
                             "the feather pulls the boundary values down (soft edge)")
        let crispInterior = columnMean(cPixels, 2)
        let featherInterior = columnMean(fPixels, 2)
        XCTAssertEqual(crispInterior, featherInterior, accuracy: 0.01,
                       "far from the edge the feather changes nothing")
    }

    // MARK: - (e) refine 点重生成 (same maskID overwrite)

    /// The refine leg: re-baking the SAME fileName replaces the pixels,
    /// flips the reference hash (→ `MaskSpec.stableHash()` → the mask-plane
    /// cache MISSES once and hits again afterwards) — the D-07-CONTEXT-5
    /// versioning through the Phase 6 mechanism, zero new cache classes.
    func testRefineRegenerateOverwritesSameMaskIDWithCacheBookkeeping() async throws {
        var stats = await cache.stats
        let misses0 = stats.misses

        let ref1 = try await bake(leftPlane(0.5), fileName: "ai-refine.png")
        let spec1 = MaskSpec(raster: ref1)
        _ = try await effective(spec1) // cold: the plane renders
        stats = await cache.stats
        XCTAssertGreaterThan(stats.misses, misses0, "the first pass renders (cache MISS)")
        let hitsAfterFirst = stats.hits
        _ = try await effective(spec1) // warm: the identical spec HITS
        stats = await cache.stats
        XCTAssertGreaterThan(stats.hits, hitsAfterFirst,
                             "the unchanged spec hits the cached mask plane")

        // The refine: the SAME file, NEW pixels (a smaller subject).
        let ref2 = try await bake(leftPlane(0.25), fileName: "ai-refine.png")
        XCTAssertEqual(ref2.fileName, ref1.fileName, "same maskID overwrite")
        XCTAssertNotEqual(ref2.maskHash, ref1.maskHash, "hash flip")
        // The stale reference now MISMATCHES the on-disk bytes (the load
        // integrity gate would degrade — exactly why the UI always carries
        // the freshly returned ref).
        let spec2 = MaskSpec(raster: ref2)
        let missesBeforeRefine = stats.misses
        let refined = try await effective(spec2)
        stats = await cache.stats
        XCTAssertGreaterThan(stats.misses, missesBeforeRefine,
                             "the refined spec keys a NEW mask plane (MISS, no stale hit)")
        XCTAssertEqual(sample(refined, 0.1, 0.5), 1.0, accuracy: 0.01,
                       "the refined pixels are live")
        XCTAssertEqual(sample(refined, 0.4, 0.5), 0.0, accuracy: 0.01)
        XCTAssertGreaterThan(
            sample(refined, 0.1, 0.5), sample(refined, 0.4, 0.5),
            "the refine direction: the mask SHRANK (the excluded region dropped)")
    }

    // MARK: - sidecar schema 零升级 (AI 参数不落盘)

    /// The AI generation adds ONLY the `mask.raster` subtree to the
    /// document — every other layer field byte-identical, and NO
    /// AI-generation parameter (quality/seed/refine points) exists anywhere
    /// in the encoded bytes (07-CONTEXT 继承定案: the params stay UI state;
    /// only the baked pixels are edit semantics).
    func testSidecarSchemaZeroUpgradeAIParamsNeverPersist() throws {
        let ref = RasterMaskRef(fileName: "ai-subject-x.png", maskHash: 0xdeadbeef)
        let plain = AdjustmentLayer(name: "L", opacity: 0.7)
        // SAME identity — only the mask subtree may differ (NDE-1).
        let masked = AdjustmentLayer(
            id: plain.id, name: "L", opacity: 0.7, mask: MaskSpec(raster: ref))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plainDict = try JSONSerialization.jsonObject(
            with: encoder.encode(SidecarLayerRecord.record(for: plain)))
            as! [String: Any]
        var maskedDict = try JSONSerialization.jsonObject(
            with: encoder.encode(SidecarLayerRecord.record(for: masked)))
            as! [String: Any]

        // The masked layer = the plain layer + the mask subtree: removing
        // the mask key from the masked layer leaves BYTE-IDENTICAL JSON
        // (schemaVersion / every other field untouched — the ONE-WAY
        // additive rule intact).
        let maskSubtree = maskedDict.removeValue(forKey: "mask")
        XCTAssertNotNil(maskSubtree, "the AI-masked layer carries the mask key")
        let plainData = try JSONSerialization.data(
            withJSONObject: plainDict, options: [.sortedKeys])
        let maskedData = try JSONSerialization.data(
            withJSONObject: maskedDict, options: [.sortedKeys])
        XCTAssertEqual(plainData, maskedData,
                       "removing the mask subtree restores the plain layer byte-for-byte")

        // The payload itself: raster carries fileName/maskHash/invert ONLY.
        let specData = try encoder.encode(MaskSpec(raster: ref))
        let specDict = try JSONSerialization.jsonObject(with: specData) as! [String: Any]
        XCTAssertEqual(Set(specDict.keys), ["version", "raster"])
        XCTAssertEqual(
            Set((specDict["raster"] as! [String: Any]).keys), Set(["fileName", "maskHash", "invert"]))

        // 防空转 (byte-level): no AI-parameter key can appear in ANY of the
        // encoded layers.
        let json = String(decoding: specData, as: UTF8.self)
        for banned in ["quality", "seed", "refine", "includedPoint", "excludedPoint"] {
            XCTAssertFalse(json.localizedCaseInsensitiveContains(banned),
                           "AI generation parameter '\(banned)' must never persist")
        }

        // The spec round-trips (decode == encode) — the mask survives a
        // sidecar load verbatim.
        let decoded = try JSONDecoder().decode(MaskSpec.self, from: specData)
        XCTAssertEqual(decoded, MaskSpec(raster: ref))
    }
}
