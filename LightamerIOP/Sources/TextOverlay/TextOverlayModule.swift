import CoreText
import Foundation
import LightamerCore
import Metal
import simd

// ─────────────────────────────────────────────────────────────────────────
// TextOverlayModule — Plan 08-5 T2, IOP-FX-05 (op "textOverlay", v50 slot
// 66.7 — the SECOND Lightamer-native V50Order row, the 66.5–67.0 gap).
//
// The editing-time TEXT LAYER (multi-line content / font / size / color /
// normalized position / rotation / opacity) — deliberately INDEPENDENT of
// the yiyin watermark (77.0, the terminal-segment final-output watermark;
// ZERO yiyin-face changes — D-08-CONTEXT-9). Slot 66.7 < 70.0 → the layer-
// mask eligibility is structural (LayerCompositeDriver.terminalTailFloor).
//
//   - render path: CoreText layout → gray-AA coverage → r8Unorm texture →
//     the text_overlay_composite kernel (uniform linear color + opacity,
//     inverse-rotation coverage sample, source-over in the working RGB).
//     NO color matrix (research §11.2 — COLOR-2 does not apply).
//   - texture cache: keyed by StableHash(textParams ⊕ longEdge) — L013
//     (Swift Hasher banned); the rasterization re-runs only on a MISS.
//   - NEUTRAL: empty (whitespace-only) content draws NOTHING — the routed
//     blit identity (cache-neutral, exposure-0EV style). The seed instance
//     is ENABLED with the empty default (unlike the non-identity creative
//     modules — the empty face IS the identity).
//   - L031: the kernel dispatch rides makeEncoder; the identity takes
//     makeRoutedCommandBuffer — the ONE acquisition points.
// ─────────────────────────────────────────────────────────────────────────

public enum TextOverlayKernel {
    public static let compositeFunction = "text_overlay_composite"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class TextOverlayModule: IOPModule {

    public struct Params: Codable, Hashable, Sendable {
        /// The overlay content; "\n" separates lines. Empty/whitespace =
        /// the neutral face (nothing drawn).
        public var content: String
        /// The font face: user-installed (YiyinFontStore) names resolve
        /// first, then system families (CoreText falls back to the default
        /// for unknown names — never a failure).
        public var fontName: String
        /// Font size in px of a 1000-px LONG-EDGE reference (the plane-
        /// proportional semantics — D-08-5-T2-2).
        public var fontSize: Float
        /// Extra inter-line spacing as a fraction of the line height.
        public var lineSpacing: Float
        /// The text color, LINEAR working-space RGB (no color matrix).
        public var colorR: Float
        public var colorG: Float
        public var colorB: Float
        /// The block-CENTER position, normalized to the plane, y from the
        /// TOP (the image-space convention).
        public var posX: Float
        public var posY: Float
        /// Rotation about the block center, degrees counterclockwise.
        public var rotationDegrees: Float
        /// The overlay opacity [0, 1].
        public var opacity: Float

        public init(
            content: String = "",
            fontName: String = "Helvetica",
            fontSize: Float = 60,
            lineSpacing: Float = 0,
            colorR: Float = 1, colorG: Float = 1, colorB: Float = 1,
            posX: Float = 0.5, posY: Float = 0.5,
            rotationDegrees: Float = 0,
            opacity: Float = 1
        ) {
            self.content = content
            self.fontName = fontName
            self.fontSize = fontSize
            self.lineSpacing = lineSpacing
            self.colorR = colorR
            self.colorG = colorG
            self.colorB = colorB
            self.posX = posX
            self.posY = posY
            self.rotationDegrees = rotationDegrees
            self.opacity = opacity
        }
    }

    public static let opName = "textOverlay"

    /// The Lightamer-native slot (V50Order 66.7) — between skinSmooth 66.5
    /// and splittoning 67.0; < the 70.0 terminal floor → layer-mask
    /// eligible (the essential division from yiyin watermark 77.0).
    public static let iopOrder: Float = 66.7

    public static let flags: IOPFlags = [.supportsBlending]
    public static let defaultColorspace: IOPColorspace = .RGB

    struct CompositeUniforms {
        var width: UInt32
        var height: UInt32
        var blockW: UInt32
        var blockH: UInt32
        var posX: Float
        var posY: Float
        var rotationRadians: Float
        var opacity: Float
        var colorR: Float
        var colorG: Float
        var colorB: Float
    }

    /// The injected font store (the YiyinFontStore reuse face — the same
    /// user-font directory convention).
    public let fontStore: YiyinFontStore

    // The coverage-texture cache (L013: StableHash over the canonical
    // params bytes ⊕ the long edge; MISS re-rasterizes, HIT reuses —
    // PSO unchanged).
    private struct CoverageCacheEntry {
        var texture: any MTLTexture
        var hash: UInt64
        var blockW: Int
        var blockH: Int
    }

    private var coverageCache: CoverageCacheEntry?
    private var cacheHits = 0
    private var cacheMisses = 0

    private var committed: Params?

    public init(fontStore: YiyinFontStore = YiyinFontStore()) {
        self.fontStore = fontStore
    }

    // MARK: - test seams

    var cacheHitsForTesting: Int { cacheHits }
    var cacheMissesForTesting: Int { cacheMisses }
    var coverageTextureForTesting: (any MTLTexture)? { coverageCache?.texture }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        committed = params
        piece.data = nil
    }

    // MARK: - neutral

    /// Empty/whitespace content draws nothing — the routed-blit identity.
    /// `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        p.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The cache key: canonical params bytes ⊕ the long edge (the raster
    /// size changes with the plane even at fixed params).
    static func cacheKey(_ params: Params, longEdge: Int) -> UInt64 {
        let encoded = ParamsCoding.encode(params)
        var data = Data(capacity: encoded.count + 8)
        data.append(encoded)
        withUnsafeBytes(of: UInt32(longEdge).littleEndian) { data.append(contentsOf: $0) }
        return StableHash.hash(data)
    }

    // MARK: - process

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let params = committed else {
            throw MetalError.psoCreationFailed(TextOverlayKernel.compositeFunction, nil)
        }
        if isNeutral(params) {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let width = input.width
        let height = input.height
        let longEdge = max(width, height)

        // ── the coverage cache (StableHash key) ─────────────────────────
        let key = Self.cacheKey(params, longEdge: longEdge)
        var blockW = 0
        var blockH = 0
        if let cached = coverageCache, cached.hash == key {
            cacheHits += 1
            blockW = cached.blockW
            blockH = cached.blockH
        } else {
            cacheMisses += 1
            guard let coverage = TextRasterizer.rasterize(
                content: params.content, fontName: params.fontName,
                fontSize: Double(params.fontSize),
                lineSpacing: Double(params.lineSpacing),
                longEdge: longEdge, store: fontStore)
            else {
                // Raced past the neutral check (a whitespace edge case) —
                // the identity is the honest output.
                try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
                return
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: coverage.width,
                height: coverage.height, mipmapped: false)
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
                throw MetalError.deviceUnavailable
            }
            coverage.bytes.withUnsafeBytes {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, coverage.width, coverage.height),
                    mipmapLevel: 0, withBytes: $0.baseAddress!,
                    bytesPerRow: coverage.width)
            }
            coverageCache = CoverageCacheEntry(
                texture: texture, hash: key,
                blockW: coverage.width, blockH: coverage.height)
            blockW = coverage.width
            blockH = coverage.height
        }
        guard let coverageTexture = coverageCache?.texture else {
            throw MetalError.psoCreationFailed(TextOverlayKernel.compositeFunction, nil)
        }

        // ── the composite ────────────────────────────────────────────────
        var uniforms = CompositeUniforms(
            width: UInt32(width), height: UInt32(height),
            blockW: UInt32(blockW), blockH: UInt32(blockH),
            posX: params.posX, posY: params.posY,
            rotationRadians: params.rotationDegrees * Float.pi / 180,
            opacity: params.opacity,
            colorR: params.colorR, colorG: params.colorG, colorB: params.colorB)
        guard let buffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<CompositeUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        let session = try await metal.makeEncoder(
            functionName: TextOverlayKernel.compositeFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(coverageTexture, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding() // L008
        session.commandBuffer.commit()
    }

    /// Whole-window routed blit (the empty-content identity). L031: the
    /// command buffer comes from makeRoutedCommandBuffer() — the ONE
    /// queue-acquisition point.
    private func blitIdentity(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        metal: MetalContext
    ) throws {
        let dx = roiOut.x - roiIn.x
        let dy = roiOut.y - roiIn.y
        guard dx >= 0, dy >= 0 else { return }
        let width = min(roiOut.width, roiIn.width, output.width, max(0, input.width - dx))
        let height = min(roiOut.height, roiIn.height, output.height, max(0, input.height - dy))
        guard width > 0, height > 0 else { return }
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: input, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: dx, y: dy, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: output, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008
        commandBuffer.commit()
    }
}
