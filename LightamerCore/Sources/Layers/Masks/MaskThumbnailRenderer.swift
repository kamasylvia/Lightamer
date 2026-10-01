import CoreGraphics
import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// MaskThumbnailRenderer (Plan M2-7-2 T1, KD-1; M2MASK-06, D-M2-7-CONTEXT-3 A)
// — the GPU thumbnail pass behind the Mask Groups panel / layer-row chip.
//
// ONE assembly entry: `MaskCombiner.assembleUnmasked` runs UNCHANGED at the
// thumbnail window (drawn rasterizer + parametric blendif + raster store all
// ride their production legs). The two blendif sampling planes are a
// HORIZONTAL LINEAR RAMP (x ∈ [0,1]) written same-value into below/top — the
// drawn leg ignores its inputs, the raster leg resamples its PNG to the
// window, and the parametric leg evaluated over the ramp IS the "selection
// window visualization" (no curve re-drawing — the kernel stays the single
// source). `layerOpacity: 1` — a thumbnail shows the SHAPE, not the layer's
// opacity. The ramp is a CPU-written `.shared` texture (zero GPU submit —
// the L031 discipline) and is REUSED per window size inside the cache.
//
// Cache (KD-1): in-process LRU keyed by `spec.stableHash() ⊕ size bucket ⊕
// window dims` — an edit flips the stable hash (old entry LRU-evicts, zero
// invalidation code), and the dims fold the window ASPECT (same hash,
// different window = different key — the checker-M4 aspect rule). NOT
// persisted: a thumbnail recomputes at O(thumbnail pixels). The raster PNG's
// integrity stays the existing `RasterMaskRef.maskHash`'s job — the
// thumbnail never re-verifies it.
//
// Readback (L014): getBytes runs behind a committed command-buffer fence —
// the same sync-helper shape RasterMaskStore/FollowEdges use
// (`waitUntilCompleted` is unavailable in async contexts).
//
// AC9 red line: the renderer creates NO device and NO command queue — every
// GPU surface arrives through the caller's `MetalContext` (the single
// routing point; grep-pinned).
//
// No App/UI dependency, no pipeline state of its own (the caller builds the
// GeometryPointMapper over the layer's base chain — the
// LayerCompositeDriver/compose precedent) → Core-unit-testable.
// ─────────────────────────────────────────────────────────────────────────────

/// One cache identity: the spec content hash ⊕ the size bucket ⊕ the exact
/// thumbnail window dims (the dims carry the aspect — checker M4).
public struct MaskThumbnailCacheKey: Hashable, Sendable {
    public let specHash: UInt64
    public let sizeBucket: Int
    public let width: Int
    public let height: Int

    public init(specHash: UInt64, sizeBucket: Int, width: Int, height: Int) {
        self.specHash = specHash
        self.sizeBucket = sizeBucket
        self.width = width
        self.height = height
    }
}

/// The renderer's process-local LRU (`cacheLimit` entries). The panel owns
/// one instance; `render` takes it `inout` (the call stays on the caller's
/// actor — the struct is deliberately non-Sendable). Ramp textures are NOT
/// cached here: a cached texture's region would taint the inout storage and
/// block the ownership transfer into the nonisolated assembly; a fresh ramp
/// is one 25 KB memset (the "进程内复用" reading narrows to the BITMAP cache
/// — recorded in DECISIONS).
public struct MaskThumbnailCache {

    /// The bitmap store (LRU-ordered).
    private var entries: [MaskThumbnailCacheKey: CGImage] = [:]
    private var order: [MaskThumbnailCacheKey] = []

    public init() {}

    /// The entry budget (KD-1's 悬决回填: 64).
    public static let defaultLimit = 64

    /// The active limit (injectable for tests).
    public var limit: Int = MaskThumbnailCache.defaultLimit

    public var count: Int { entries.count }

    /// Lookup + LRU touch. nil = miss.
    public mutating func image(for key: MaskThumbnailCacheKey) -> CGImage? {
        guard let image = entries[key] else { return nil }
        touch(key)
        return image
    }

    /// Insert (or replace) + LRU front + evict the tail beyond `limit`.
    public mutating func insert(_ image: CGImage, for key: MaskThumbnailCacheKey) {
        if entries[key] == nil { order.append(key) }
        entries[key] = image
        touch(key)
        while order.count > limit, let evicted = order.first {
            order.removeFirst()
            entries[evicted] = nil
        }
    }

    private mutating func touch(_ key: MaskThumbnailCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// The renderer. `@MainActor` ON PURPOSE: the panel drives it from view
/// tasks, and the `inout MaskThumbnailCache` parameter must stay inside one
/// isolation domain across the await (Swift 6 region isolation) — the same
/// single-writer shape every editor-side caller already lives in.
@MainActor
public enum MaskThumbnailRenderer {

    /// The size bucket (KD-1's 悬决回填: the 96–128 band's midpoint).
    public static let thumbLongEdge = 112

    /// The aspect-preserving thumbnail window for a layer window at a
    /// bucket (checker M4: the thumbnail window is the LAYER WINDOW scaled,
    /// never a square — a square window distorts every normalized shape).
    /// Both edges floor at 2 so the GPU legs stay well-formed.
    public static func thumbnailSize(
        forLayerWindow window: SIMD2<Int>, bucket: Int = MaskThumbnailRenderer.thumbLongEdge
    ) -> SIMD2<Int> {
        let w = max(1, window.x), h = max(1, window.y)
        let longEdge = Double(max(w, h))
        let scale = Double(max(2, min(bucket, Int(longEdge)))) / longEdge
        return SIMD2(
            max(2, Int((Double(w) * scale).rounded())),
            max(2, Int((Double(h) * scale).rounded())))
    }

    /// Render (or fetch) the spec's thumbnail: an 8-bit grayscale CGImage
    /// (the alpha plane semantics = the gray display, "像素真实优先"). nil
    /// when the spec carries no payload — the panel shows its placeholder
    /// frame (never a crash, never a quiet blank frame).
    ///
    /// `mapper` is CALLER-BUILT (KD-1): compose the layer's base-chain
    /// geometry AT THE THUMBNAIL FRAME (`frameSize` = the layer window at
    /// thumbnail scale — the compose seam is resolution-scaled, so segments
    /// carry thumbnail-scale pixels) and the renderer reads the window from
    /// `mapper.outputSize`. The drawn/raster legs map through it; the
    /// renderer never builds pipeline state (the Core-unit-testable
    /// discipline).
    @discardableResult
    public static func render(
        spec: MaskSpec,
        size: Int,
        metal: MetalContext,
        mapper: GeometryPointMapper,
        maskDirectory: URL?,
        cache: inout MaskThumbnailCache
    ) async throws -> CGImage? {
        guard spec.hasAnyPayload else { return nil }
        let width = max(1, Int(mapper.outputSize.x.rounded()))
        let height = max(1, Int(mapper.outputSize.y.rounded()))
        let key = MaskThumbnailCacheKey(
            specHash: spec.stableHash(), sizeBucket: size,
            width: width, height: height)
        if let hit = cache.image(for: key) { return hit }

        let window = ROI(x: 0, y: 0, width: width, height: height, scale: 1.0)
        // Fresh ramps each call; ownership transfers through the `sending`
        // boundary below (never touched again on this side).
        let below = try rampTexture(width: width, height: height, metal: metal)
        let top = try rampTexture(width: width, height: height, metal: metal)
        // The single assembly entry, production legs unchanged. Layer
        // opacity 1: the thumbnail shows the shape, not the slider.
        let (plane, _) = try await assembleThumbnailPlane(
            spec: spec, window: window, below: below, top: top,
            mapper: mapper, metal: metal, maskDirectory: maskDirectory)
        guard let image = grayImage(from: plane, metal: metal) else { return nil }
        cache.insert(image, for: key)
        return image
    }

    // MARK: - The ramp inputs (KD-1)

    /// The cross-isolation boundary (the coordinator's
    /// `applyMaskOverlayIfRequested` `sending` shape): the caller transfers
    /// the ramp planes' ownership in; the UNCHANGED assembleUnmasked entry
    /// runs the production legs. `layerOpacity` is pinned to 1 (the
    /// thumbnail shows the shape, not the slider).
    private static func assembleThumbnailPlane(
        spec: MaskSpec,
        window: ROI,
        below: sending any MTLTexture,
        top: sending any MTLTexture,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        maskDirectory: URL?
    ) async throws -> (any MTLTexture, String?) {
        try await MaskCombiner.assembleUnmasked(
            spec: spec, layerOpacity: 1, window: window,
            below: below, top: top, mapper: mapper, metal: metal,
            maskDirectory: maskDirectory, rasterStore: RasterMaskStore.self)
    }

    /// The horizontal linear ramp x ∈ [0,1] (CPU-written `.shared` texture —
    /// a memset, not a GPU submit; L031-safe). RGBA32 working-space shape:
    /// the blendif kernel reads float4 and luma-weights .rgb, so the ramp
    /// value goes into ALL THREE channels with alpha 1 (a monochrome ramp's
    /// luma IS the ramp value).
    private static func rampTexture(
        width: Int, height: Int, metal: MetalContext
    ) throws -> any MTLTexture {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        if width > 1 {
            for x in 0..<width {
                let value = Float(x) / Float(width - 1)
                for y in 0..<height {
                    let base = (y * width + x) * 4
                    pixels[base + 0] = value
                    pixels[base + 1] = value
                    pixels[base + 2] = value
                    pixels[base + 3] = 1
                }
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(width * height * 16)
        }
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: raw.baseAddress!, bytesPerRow: width * 16)
        }
        return texture
    }

    // MARK: - The fenced readback → 8-bit gray CGImage (L014)

    /// Fence → r32Float readback → linear ×255 → gray8 CGImage. Sync shape
    /// (`waitUntilCompleted` is unavailable in async contexts — the
    /// RasterMaskStore readPlane precedent).
    static func grayImage(
        from plane: any MTLTexture, metal: MetalContext
    ) -> CGImage? {
        let width = plane.width, height = plane.height
        guard width >= 1, height >= 1 else { return nil }
        let fence = metal.commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted() // L014
        var floats = [Float](repeating: -1, count: width * height)
        floats.withUnsafeMutableBytes {
            plane.getBytes(
                $0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var pixels = [UInt8](repeating: 0, count: width * height)
        for index in 0..<pixels.count {
            let value = min(max(floats[index], 0), 1)
            pixels[index] = UInt8((Double(value) * 255.0).rounded())
        }
        let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        return context?.makeImage()
    }
}
