import CoreImage
import Metal
import os

/// The CIImage → MTLTexture bridge (internal to Core — RESEARCH §9 internal
/// surface: only Core's RAWDecoder/pixelpipe path uses it; the app reaches it
/// through `MetalContext.renderToTexture`).
///
/// - ONE `CIContext` per `MTLDevice` (WWDC "Optimize the Core Image
///   pipeline") — this actor owns it for the app's lifetime.
/// - Working/output color space = `WorkingSpace.colorSpace` (linear Rec2020,
///   FOUND-02); output pixels land in `WorkingSpace.pixelFormat`
///   (`.rgba32Float`, float32 RGBA — L006: no half on shadow-sensitive
///   paths).
/// - `cacheIntermediates: false` is MANDATORY (CIRAW-4): lazy CIImage chains
///   on 100MP otherwise hold gigabytes of ROI descriptors.
///
/// ⚠ HOST FINDING (re-verified by the Plan 02-01 spike, 2026-09-19):
/// `CIContext.render(_:toMTLTexture:)` is a SILENT NO-OP on this
/// macOS 27.0 / Apple M4 host — it completes in 0.0ms having enqueued NO
/// work. The Plan 02-01 warm-up hypothesis is REFUTED: with a fresh context
/// per round, the direct path wrote empty 6/6 cold AND 6/6 after a throwaway
/// warm-up render (owned command buffer + completed-wait, race-free
/// readback), with a real CIRAW-backed image, AND with a DEFAULT CIContext +
/// rgba8Unorm + deviceRGB (option set ruled out). Full methodology + raw
/// numbers: `.work/plans/02-01/spike-render-leg.md`.
///
/// Decision (spike, quoted verbatim): `Decision: bitmap —
/// CIContext.render(_:toMTLTexture:) is a silent no-op on this host (macOS
/// 27.0 / Apple M4): 0/6 non-empty cold AND 0/6 post-warm-up with an owned
/// command buffer (0.0ms = CI enqueues no work), EMPTY with a real
/// CIRAW-backed image, and EMPTY even on a DEFAULT CIContext + rgba8Unorm +
/// deviceRGB; warm-up does not make the direct path reliable, so the decode
/// leg keeps bitmap+replace (CIContextPool, Phase 1 workaround) for PREVIEW
/// and FULL. The drag hot path is all-Metal regardless of this outcome
/// (research §5 — the spike only decides the decode leg and the FULL path).`
///
/// This bridge therefore renders to a float32 CPU buffer and stages it into
/// the shared texture via `replace(region:)` — byte-correct, ~16-20ms at the
/// 2560px PREVIEW bucket and ~0.3s at 60MP (spike Test B medians). The
/// bitmap path is BOTH the primary and the fallback; re-test the direct
/// texture path only on a future macOS point release.
internal actor CIContextPool {

    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let ciContext: CIContext

    /// D-31: the render leg of the vertebra is signposted ("decode" lives in
    /// RAWDecoder/EditorState; "render" here).
    private static let signposter = OSSignposter(subsystem: "com.kamasylvia.lightamer", category: "metal")

    init(device: any MTLDevice, commandQueue: any MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: WorkingSpace.colorSpace,   // linear Rec2020 (FOUND-02)
            .outputColorSpace: WorkingSpace.colorSpace,
            .workingFormat: CIFormat.RGBAh,                // CI-internal half working format; the cast to float32 happens at the render step
            .cacheIntermediates: false,                    // CIRAW-4
        ])
    }

    /// Render `image` into a freshly allocated `.rgba32Float` texture sized
    /// to the image extent, with pixels in linear Rec2020 (FOUND-02).
    /// Ownership handoff is carried by `RenderedTexture` (same documented
    /// `@unchecked Sendable` pattern as `MetalContext.ComputeEncoderSession`):
    /// the pool retains nothing; the receiver owns the texture exclusively.
    internal struct RenderedTexture: @unchecked Sendable {
        let texture: any MTLTexture
    }

    /// D-C1 layer 2 (Plan 02-06-05): drop the CI/RawCamera internal
    /// per-camera state that the spike-b cross-decode accumulation
    /// (4.3-5.4GB) flagged as an accumulator. PSO caches (MetalContext)
    /// are deliberately NOT touched — MB-scale, clearing them would stall
    /// the next dispatches on PSO rebuilds.
    internal func clearCaches() {
        ciContext.clearCaches()
        AppError.logger.debug("CIContextPool.clearCaches: ciContext.clearCaches() done")
    }

    internal func renderToTexture(_ image: CIImage) throws -> RenderedTexture {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else {
            throw AppError.decodeFailed("CIImage has an empty extent")
        }
        return try renderScaled(
            image, width: Int(extent.width), height: Int(extent.height), signpost: "render"
        )
    }

    /// Scale-at-entry render (Plan 02-03-02; the mirror of Darktable's
    /// entry resampling, `pixelpipe_hb.c:1930-1999`): the CIImage is
    /// transformed to the requested long edge FIRST and rendered ONCE at
    /// that size — never render 100MP then downscale. This is the PREVIEW/
    /// THUMBNAIL input-plane builder.
    ///
    /// Spike evidence (02-01 Test C, `.work/plans/02-01/spike-render-leg.md`):
    /// scaled rendering gives NO reliable decode-time win — medians were
    /// inverted (scaled-2560 922ms vs full-60MP 304ms on DSC09991.ARW) with
    /// 10–20× run-to-run variance, because `cacheIntermediates:false` makes
    /// CIRAW re-execute per render and its internal state thrashes across
    /// alternating scales. The win of this path is MEMORY: a 2560px float32
    /// input plane is ~70MB vs 1.55GB at 60MP (the spike-b plane-multiplication
    /// guard), which is why the ladder (D-C3) still matters for footprint.
    /// First-render seconds are a one-time decode cost (Phase 3 UX affords
    /// the progress indicator; do not add one per-render).
    ///
    /// - Parameters:
    ///   - image: the decoded CIImage (any extent).
    ///   - longEdge: target long edge in pixels. The result never exceeds
    ///     the source extent (`scale` clamps at 1.0 — small images render
    ///     at their native size; no upscale).
    internal func renderToTexture(_ image: CIImage, longEdge: Int) throws -> RenderedTexture {
        guard longEdge >= 1 else {
            throw AppError.decodeFailed("renderToTexture(longEdge:) needs a positive long edge, got \(longEdge)")
        }
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width >= 1, height >= 1 else {
            throw AppError.decodeFailed("CIImage has an empty extent")
        }
        // Downscale-only fit: the long edge lands exactly on the target
        // (or at 1.0 for images already smaller than it).
        let scale = min(
            CGFloat(longEdge) / CGFloat(max(width, 1)),
            CGFloat(longEdge) / CGFloat(max(height, 1)),
            1.0
        )
        guard scale.isFinite, scale > 0 else {
            throw AppError.decodeFailed("degenerate scale computing longEdge \(longEdge) for \(width)×\(height)")
        }
        let scaledWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let scaledHeight = max(1, Int((CGFloat(height) * scale).rounded()))
        // CI is lazy: the transform folds into the ONE bitmap render below.
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return try renderScaled(
            scaled, width: scaledWidth, height: scaledHeight, signpost: "render-scaled",
            scale: scale
        )
    }

    /// Sub-domain render (04-01-T4; dt base-buffer ROI mirror): render the
    /// `region`-of-`image` window into a `region.size` texture — CI is lazy
    /// so the crop folds into the ONE bitmap render (no full-frame buffer,
    /// no window copy — the D-G2 read). `region` is in the SOURCE extent's
    /// pixel coords; the bitmap bounds keep the region ORIGIN (not
    /// re-based to zero) so source-anchored content — CIRAW tiles,
    /// lens-opcode warps — samples at true coords.
    ///
    /// Scale composes (`scale < 1` downsamples the window for PREVIEW/
    /// THUMBNAIL legs): the output is `region.size × scale`, the bitmap
    /// bounds stay source-anchored.
    internal func renderRegion(
        _ image: CIImage, region: CGRect, scale: CGFloat = 1.0
    ) throws -> RenderedTexture {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else {
            throw AppError.decodeFailed("CIImage has an empty extent")
        }
        // Clamp the requested window into the extent (negotiated far edges
        // may touch the frame edge exactly — dt CLAMP upper bound is
        // INCLUSIVE, so intersect-then-require-nonempty, never throw on
        // edge touch). Threat model: a module bug requesting a fully
        // outside window still throws below.
        let clampedOrigin = CGPoint(
            x: min(max(region.origin.x, extent.origin.x), extent.maxX - 1),
            y: min(max(region.origin.y, extent.origin.y), extent.maxY - 1))
        let clampedSize = CGSize(
            width: min(region.width, extent.maxX - clampedOrigin.x),
            height: min(region.height, extent.maxY - clampedOrigin.y))
        let clipped = CGRect(origin: clampedOrigin, size: clampedSize)
        guard scale.isFinite, scale > 0 else {
            throw AppError.decodeFailed("renderRegion: degenerate scale \(scale)")
        }
        let outWidth = max(1, Int((clipped.width * scale).rounded()))
        let outHeight = max(1, Int((clipped.height * scale).rounded()))
        let windowed: CIImage
        if scale == 1.0 {
            windowed = image
        } else {
            // Scale about the region origin: content lands at (0,0) at the
            // output size while the BITMAP bounds below stay anchored.
            let toOrigin = CGAffineTransform(
                translationX: -clipped.origin.x, y: -clipped.origin.y)
            let down = CGAffineTransform(scaleX: scale, y: scale)
            windowed = image.transformed(by: toOrigin.concatenating(down))
        }
        return try renderWindowed(
            windowed, bounds: scale == 1.0 ? clipped : CGRect(
                x: 0, y: 0, width: clipped.width * scale,
                height: clipped.height * scale),
            width: outWidth, height: outHeight, signpost: "render-region")
    }

    /// Windowed bitmap leg: like `renderScaled` but the bitmap `bounds`
    /// differ from the (0,0)-based output texture — the D-G2 sub-domain
    /// primitive. Bounds origin stays source-anchored at scale 1.0.
    private func renderWindowed(
        _ image: CIImage,
        bounds: CGRect,
        width: Int,
        height: Int,
        signpost: StaticString
    ) throws -> RenderedTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(width * height * WorkingSpace.bytesPerPixel)
        }
        let interval = Self.signposter.beginInterval(signpost, id: Self.signposter.makeSignpostID())
        defer { Self.signposter.endInterval(signpost, interval) }
        let rowBytes = width * WorkingSpace.bytesPerPixel
        let byteCount = rowBytes * height
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { buffer.deallocate() }
        ciContext.render(
            image,
            toBitmap: buffer,
            rowBytes: rowBytes,
            bounds: bounds,
            format: CIFormat.RGBAf,
            colorSpace: WorkingSpace.colorSpace
        )
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: rowBytes
        )
        return RenderedTexture(texture: texture)
    }

    /// The shared bitmap+replace leg (host finding: direct
    /// `render(_:toMTLTexture:)` is a silent no-op on this host — see the
    /// decision header). Renders `image` into a fresh `.rgba32Float` texture
    /// of exactly `width × height`; signpost name distinguishes the
    /// full-extent ("render") and scaled ("render-scaled") callers so the
    /// decode-at-scale cost is measurable in Instruments (D-31).
    private func renderScaled(
        _ image: CIImage,
        width: Int,
        height: Int,
        signpost: StaticString,
        scale: CGFloat? = nil
    ) throws -> RenderedTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat, // .rgba32Float
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared // METAL-4: Apple Silicon UMA
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            // 100MP float32 RGBA ≈ 1.6GB — allocation failure = budget
            // exceeded; the Phase 2 tiling path (D-20) engages later.
            throw MetalError.bufferAllocationFailed(width * height * WorkingSpace.bytesPerPixel)
        }

        let signposter = Self.signposter
        let interval = signposter.beginInterval(signpost, id: signposter.makeSignpostID())
        defer { signposter.endInterval(signpost, interval) }
        if let scale {
            AppError.logger.debug(
                "render-scaled \(width)×\(height) (scale \(scale, privacy: .public))"
            )
        }

        let rowBytes = width * WorkingSpace.bytesPerPixel
        let byteCount = rowBytes * height
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { buffer.deallocate() }

        // Bitmap render (see host-finding note): float32 RGBA pixels in the
        // linear Rec2020 output space — the pixelpipe format, byte-exact.
        ciContext.render(
            image,
            toBitmap: buffer,
            rowBytes: rowBytes,
            bounds: image.extent,
            format: CIFormat.RGBAf,
            colorSpace: WorkingSpace.colorSpace
        )
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: rowBytes
        )
        return RenderedTexture(texture: texture)
    }

    /// The colorout ColorSync leg (Plan 02-04-03): converts a float32
    /// linear-Rec2020 TEXTURE into a fresh float32 texture of the same
    /// dimensions whose pixels are LINEAR values in `target` — ColorSync
    /// performs the full-ICC gamut conversion (primaries + white), while
    /// the TRC encode stays with the gamma module (D-COL4: colorout output
    /// is linear, unclamped). `target` must be a LINEAR colorspace (see
    /// `DisplayProfile.linearCGColorSpace`).
    ///
    /// Mechanism: `CIImage(mtlTexture:options:)` tags the texture with the
    /// working space, then the SAME bitmap+replace leg as `renderScaled`
    /// renders with the per-call `colorSpace:` override (the context-level
    /// output space is a default; the per-render parameter wins). Cost
    /// 10-30ms at 2560px (CPU round trip) — acceptable for the one-shot
    /// screen-change path, never the drag hot path (fast path covers it).
    internal func convertTexture(
        _ input: any MTLTexture,
        toLinearSpace target: CGColorSpace
    ) throws -> RenderedTexture {
        let width = input.width
        let height = input.height
        guard width >= 1, height >= 1 else {
            throw AppError.decodeFailed("convertTexture: degenerate texture \(width)×\(height)")
        }
        // CROSS-QUEUE ORDERING (Plan 02-06 host finding): CI renders on its
        // OWN internal queue, but `input` may have kernel writes still
        // IN FLIGHT on OUR serial queue (dispatch2DTexture commits without
        // waiting). Without a fence, the ColorSync leg race-reads freshly
        // allocated (zeroed) planes — deterministic-looking per flow shape
        // (the 5-dispatch restore render lost the race 4/4; the shorter
        // live-edit render won it 2/2). An empty committed buffer waits for
        // every prior write on our queue before CI touches the texture.
        let fence = commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        guard let image = CIImage(mtlTexture: input, options: [
            .colorSpace: WorkingSpace.colorSpace, // the plane IS linear Rec2020 (FOUND-02)
        ]) else {
            throw AppError.decodeFailed("CIImage(mtlTexture:) failed for the colorout ColorSync leg")
        }
        let signposter = Self.signposter
        let interval = signposter.beginInterval("colorout-colorsync", id: signposter.makeSignpostID())
        defer { signposter.endInterval("colorout-colorsync", interval) }

        let rowBytes = width * WorkingSpace.bytesPerPixel
        let byteCount = rowBytes * height
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        defer { buffer.deallocate() }
        ciContext.render(
            image,
            toBitmap: buffer,
            rowBytes: rowBytes,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: CIFormat.RGBAf,
            colorSpace: target
        )

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: WorkingSpace.pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(byteCount)
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: buffer,
            bytesPerRow: rowBytes
        )
        return RenderedTexture(texture: texture)
    }
}
