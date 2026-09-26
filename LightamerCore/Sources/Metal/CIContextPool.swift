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

    /// GUI-22 (2026-09-24): the input-plane render memo. CIRAWFilter-backed
    /// CIImages RE-EXECUTE on every `render(toBitmap:)` call
    /// (`cacheIntermediates: false`), and the re-execution is NOT
    /// byte-stable on this host — speckle-level variance (~0.06% of float
    /// bytes, byte-max 255) that local-contrast iops amplify (measured 18%
    /// plane divergence through `shadhi`). Combined with the session
    /// cache's budget eviction (a 2560px PREVIEW family is ~1.9 GB —
    /// families evict each other mid-session), any input-plane MISS
    /// re-rendered a DIFFERENT speckle variant: warm-undo vs cold-load
    /// renders of the same state diverged stably per path (GUI-22's three
    /// iron facts). The memo freezes the input plane per
    /// (CIImage identity, size): the CI chain executes AT MOST ONCE per
    /// image instance and scale — every later miss reuses the identical
    /// texture. The value keeps the CIImage alive so the ObjectIdentifier
    /// key can never alias a new image at a recycled address. Bounded by
    /// `clearCaches()` (the load-switch CI sweep).
    private struct InputPlaneMemoEntry {
        let image: CIImage
        let texture: any MTLTexture
        var byteCount: Int { texture.width * texture.height * WorkingSpace.bytesPerPixel }
    }

    /// The memo key: the caller's CONTENT dedupe key (imageID ⊕ decode
    /// params hash — unifies re-decodes of the same file) or the CIImage
    /// identity (callers without a content key). The entry holds the CIImage
    /// strongly so an identity key can never alias a recycled instance.
    private enum MemoKey: Hashable {
        case identity(ObjectIdentifier)
        /// GUI-22 re-verify note: the size rides IN the key — the full-extent
        /// leg (FULL) and the longEdge leg (PREVIEW/THUMBNAIL) previously
        /// shared `.content`, alternating requests overwrote each other and
        /// re-executed CIRAW (variant drift window).
        case content(UInt64, width: Int, height: Int)
    }
    private var inputPlaneMemo: [MemoKey: InputPlaneMemoEntry] = [:]

    /// The sub-domain memo key (`renderRegion`'s GUI-22 freeze): the memo
    /// key + the exact request.
    private struct SubRegionKey: Hashable {
        let dedupe: MemoKey
        let x: CGFloat, y: CGFloat
        let width: CGFloat, height: CGFloat
        let scale: CGFloat
    }
    private var inputSubRegionMemo: [SubRegionKey: InputPlaneMemoEntry] = [:]

    /// LRU handle for the memo trims. The memo DELIBERATELY SURVIVES
    /// `clearCaches()` — that sweep exists for CI/RawCamera INTERNAL state
    /// (the D-32 multi-GB accumulation), while these are OUR bounded planes;
    /// wiping them on a same-image reload (the sidecar-restore cold path)
    /// would re-execute CIRAW and reintroduce GUI-22's speckle variant.
    /// Bounded instead by `memoCapacity` (≈3 × 70MB @2560 — well inside the
    /// session budget).
    private enum MemoHandle: Hashable {
        case plane(MemoKey)
        case subRegion(SubRegionKey)
    }

    private func memoEntry(_ handle: MemoHandle) -> InputPlaneMemoEntry? {
        switch handle {
        case let .plane(key): return inputPlaneMemo[key]
        case let .subRegion(key): return inputSubRegionMemo[key]
        }
    }

    private func memoEvict(_ handle: MemoHandle) {
        switch handle {
        case let .plane(key): inputPlaneMemo.removeValue(forKey: key)
        case let .subRegion(key): inputSubRegionMemo.removeValue(forKey: key)
        }
    }
    /// BYTE-bounded (a count cap would hold ~3 GB at the 60MP FULL scale —
    /// 962 MB/plane). Evicts LRU-oldest down to the cap, tolerating a
    /// single oversized plane (the evictUnderBudget pattern).
    private static let memoByteCap = 512 * 1024 * 1024
    private var memoLRU: [MemoHandle] = []

    private func memoTouch(_ handle: MemoHandle) {
        memoLRU.removeAll { $0 == handle }
        memoLRU.append(handle)
        var total = memoLRU.reduce(0) { $0 + (memoEntry($1)?.byteCount ?? 0) }
        while total > Self.memoByteCap && memoLRU.count > 1 {
            let evicted = memoLRU.removeFirst()
            total -= memoEntry(evicted)?.byteCount ?? 0
            memoEvict(evicted)
        }
    }

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
        // GUI-22: the input-plane memos SURVIVE this sweep (bounded by
        // `memoCapacity`, see `MemoHandle`) — same-image reloads (sidecar
        // cold restore) must reuse the FROZEN plane, not re-execute CIRAW.
        ciContext.clearCaches()
        AppError.logger.debug("CIContextPool.clearCaches: ciContext.clearCaches() done")
    }

    /// Internal test seam (Plan 11-03 T4, R8): the queue THIS pool's fences
    /// hang on — the export pool must report `exportCommandQueue` (a fence
    /// on the wrong queue is a silent race, the R8 false-green shape).
    internal func debugFenceQueue() -> any MTLCommandQueue {
        commandQueue
    }

    internal func renderToTexture(
        _ image: CIImage, dedupeKey: UInt64? = nil
    ) throws -> RenderedTexture {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else {
            throw AppError.decodeFailed("CIImage has an empty extent")
        }
        // GUI-22: render-once memo (see `inputPlaneMemo`) — the full-extent
        // leg keys on the dedupe key (content identity: imageID ⊕ decode
        // hash — unifies RE-DECODES of the same file) or the image identity.
        let w = Int(extent.width), h = Int(extent.height)
        let key = dedupeKey.map { MemoKey.content($0, width: w, height: h) }
            ?? .identity(ObjectIdentifier(image))
        if let memo = inputPlaneMemo[key] {
            memoTouch(.plane(key))
            return RenderedTexture(texture: memo.texture)
        }
        let rendered = try renderScaled(
            image, width: w, height: h, signpost: "render"
        )
        inputPlaneMemo[key] = InputPlaneMemoEntry(image: image, texture: rendered.texture)
        memoTouch(.plane(key))
        return rendered
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
    internal func renderToTexture(
        _ image: CIImage, longEdge: Int, dedupeKey: UInt64? = nil
    ) throws -> RenderedTexture {
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
        // GUI-22: render-once memo (see `inputPlaneMemo`) — the scaled leg
        // keys on the ORIGINAL image identity (the `transformed(by:)` chain
        // below mints a fresh CIImage per call, so it cannot be the key) +
        // the target size. A hit hands back the FROZEN first-render plane:
        // the CIRAW re-execution speckle variance can never leak into a
        // re-rendered input plane again.
        let key = dedupeKey.map { MemoKey.content($0, width: scaledWidth, height: scaledHeight) }
            ?? .identity(ObjectIdentifier(image))
        if let memo = inputPlaneMemo[key] {
            memoTouch(.plane(key))
            return RenderedTexture(texture: memo.texture)
        }
        // CI is lazy: the transform folds into the ONE bitmap render below.
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rendered = try renderScaled(
            scaled, width: scaledWidth, height: scaledHeight, signpost: "render-scaled",
            scale: scale
        )
        inputPlaneMemo[key] = InputPlaneMemoEntry(image: image, texture: rendered.texture)
        memoTouch(.plane(key))
        return rendered
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
        _ image: CIImage, region: CGRect, scale: CGFloat = 1.0, dedupeKey: UInt64? = nil
    ) throws -> RenderedTexture {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1 else {
            throw AppError.decodeFailed("CIImage has an empty extent")
        }
        // GUI-22: render-once memo (see `inputPlaneMemo`) — the SUB-DOMAIN
        // leg is the one the PREVIEW bucket actually takes for large
        // images (the scaled entry ROI is "smaller than the full extent",
        // so `processRec` routes here, NOT to the whole-frame legs). Keyed
        // on the image identity + the exact (region, scale) request — a
        // hit hands back the FROZEN first-render plane so the CIRAW
        // re-execution speckle variance can never leak into a re-rendered
        // input plane.
        let regionKey = SubRegionKey(
            dedupe: dedupeKey.map {
                MemoKey.content($0, width: Int(extent.width), height: Int(extent.height))
            } ?? .identity(ObjectIdentifier(image)),
            x: region.origin.x, y: region.origin.y,
            width: region.width, height: region.height, scale: scale)
        if let memo = inputSubRegionMemo[regionKey] {
            memoTouch(.subRegion(regionKey))
            return RenderedTexture(texture: memo.texture)
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
        let rendered = try renderWindowed(
            windowed, bounds: scale == 1.0 ? clipped : CGRect(
                x: 0, y: 0, width: clipped.width * scale,
                height: clipped.height * scale),
            width: outWidth, height: outHeight, signpost: "render-region")
        inputSubRegionMemo[regionKey] = InputPlaneMemoEntry(image: image, texture: rendered.texture)
        memoTouch(.subRegion(regionKey))
        return rendered
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
    /// output space is a default; the per-render parameter wins). The
    /// `.downMirrored` orientation tag undoes CI's bottom-up texture read
    /// (the L029 host finding — without it this leg's output was vertically
    /// mirrored; it never slept through a production flow because the fast
    /// path covers sRGB/P3, but the parity test below pins both legs to the
    /// same rows). Cost 10-30ms at 2560px (CPU round trip) — acceptable for
    /// the one-shot screen-change path, never the drag hot path (fast path
    /// covers it).
    internal func convertTexture(
        _ input: any MTLTexture,
        toLinearSpace target: CGColorSpace
    ) throws -> RenderedTexture {
        // L029 close-out (11-05): the caller renounces `input` across the
        // actor hop — this leg consumes the plane read-only.
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

        // The plane IS linear Rec2020 (the pipe interior, FOUND-02); the
        // `.downMirrored` tag undoes CI's bottom-up texture read (the L029
        // row-order host finding — the export twin got the same fix in
        // 11-02; this leg slept unfixed until the 11-05 close-out batch).
        guard let image = CIImage(mtlTexture: input, options: [
            .colorSpace: WorkingSpace.colorSpace, // the plane IS linear Rec2020 (FOUND-02)
        ])?.oriented(.downMirrored) else {
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

    /// The EXPORT colorout leg (Plan 11-03 T2): convert a float32 linear-
    /// Rec2020 TEXTURE into a fresh float32 texture whose pixels are
    /// converted to `target` — primaries + white + TRC in ONE ColorSync
    /// render (the OQ-11-2 ruling: the in-pipe colorout performs the whole
    /// conversion; the exit leg is then an identity). `target` is ANY
    /// CGColorSpace: the display-TRC variant for the quantized tiers or the
    /// LINEAR variant for TIFF 32f (the caller — ExportChainBuilder — picks
    /// via `ExportColorSpaceMapper`).
    ///
    /// **The `convertTexture` sister WITH the row-order fix (L029):** the
    /// 11-02 host finding proved `CIImage(mtlTexture:)` reads bottom-up —
    /// the bare `convertTexture` lands its output vertically mirrored
    /// (dormant on the display leg, which L029 pinned). This leg carries
    /// the `.oriented(.downMirrored)` correction so the export chain NEVER
    /// consumes the defective twin (forbidden by the L029 discipline).
    ///
    /// The fence rides THIS pool's commandQueue — the 11-03 export pool is
    /// instantiated with `exportCommandQueue` (R8: a fence on the wrong
    /// queue is a silent race).
    internal func convertToEncodedTexture(
        _ input: any MTLTexture,
        target: CGColorSpace
    ) throws -> RenderedTexture {
        let width = input.width
        let height = input.height
        guard width >= 1, height >= 1 else {
            throw AppError.decodeFailed("convertToEncodedTexture: degenerate texture \(width)×\(height)")
        }
        // Cross-queue ordering — same discipline as convertTexture /
        // renderToEncodedBitmap (L014/GUI-22): CI reads on its own internal
        // queue; the empty committed+waited buffer orders every prior write
        // on OUR queue first.
        let fence = commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        // The plane IS linear Rec2020 (the pipe interior, FOUND-02); the
        // `.downMirrored` tag undoes CI's bottom-up texture read (the 11-02
        // row-order host finding — see the class header + L029).
        guard let image = CIImage(mtlTexture: input, options: [
            .colorSpace: WorkingSpace.colorSpace,
        ])?.oriented(.downMirrored) else {
            throw AppError.decodeFailed("CIImage(mtlTexture:) failed for the export colorout leg")
        }
        let signposter = Self.signposter
        let interval = signposter.beginInterval("colorout-export", id: signposter.makeSignpostID())
        defer { signposter.endInterval("colorout-export", interval) }

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

    // ───────────────────────────────────────────────────────────────────────
    // The EXPORT exit leg (Plan 11-02 T2) — the `convertTexture` sister.
    // ───────────────────────────────────────────────────────────────────────
    /// The exit leg's CPU handoff: float32 RGBA pixels ALREADY ENCODED in the
    /// target color space (primaries + white + TRC applied by the one
    /// ColorSync render below). Sendable value — the quantizer consumes it
    /// (Plan 11-02 T1's packed faces) without any GPU object aboard.
    internal struct EncodedBitmap: Sendable {
        /// float32 RGBA, `rowBytes * height` bytes, host-endian.
        public let data: Data
        public let width: Int
        public let height: Int
        public let rowBytes: Int
    }

    /// Render a pixelpipe OUTPUT TEXTURE into a float32 CPU bitmap whose
    /// pixels are ENCODED in `target` — the single exit conversion (COLOR-2
    /// matrix family's CI leg reuse, RESEARCH §3.2): ColorSync performs
    /// primaries + white + TRC in THIS one render; no texture is created
    /// (the export leg never returns to the GPU — direct CPU handoff).
    /// `input` rides the `TextureBox` renounce wrap (the ColorOutModule
    /// precedent): the plane is consumed by this call — the fence orders
    /// prior writes, then CI reads it; the caller must not touch it after.
    ///
    /// **sourceColorSpace contract (checker E3)**: what the incoming plane
    /// already IS, tag-wise.
    /// - Default `WorkingSpace.colorSpace`: the plane is linear Rec2020 (the
    ///   raw pipe tail, gamma stripped) — the render converts it to `target`
    ///   (the conversion happens here, exactly once).
    /// - The 11-03 export chain passes the TARGET color space instead: its
    ///   `colorout` stage already overrode its target to the export profile,
    ///   so the arriving plane is ALREADY target-encoded and this render is
    ///   an IDENTITY (byte-preserving pass through ColorSync). Pinning the
    ///   parameter to WorkingSpace there would re-encode already-encoded
    ///   values — a systematic color cast. The dual-state golden test pins
    ///   both states and their DIFFERENCE (the reverse assertion).
    ///
    /// Disciplines carried over from `convertTexture`:
    /// 1. CROSS-QUEUE FENCE (L014/GUI-22): CI renders on its own internal
    ///    queue while `input` may have kernel writes still in flight on OUR
    ///    serial queue — the empty committed+waited buffer below orders
    ///    every prior write before CI touches the texture. The fence hangs
    ///    on THIS POOL's commandQueue (R8: 11-03 instantiates the export
    ///    pool with `exportCommandQueue` — a fence on the wrong queue is a
    ///    silent race, the false-green/black-plane shape).
    /// 2. `cacheIntermediates: false` (CIRAW-4) — set once at `init`.
    /// 3. CPU bitmap leg semantics (host finding, header note): cost 10-30ms
    ///    at 2560px — acceptable for the one-shot full-res export path,
    ///    never a drag-hot-path candidate.
    internal func renderToEncodedBitmap(
        _ input: TextureBox,
        sourceColorSpace: CGColorSpace = WorkingSpace.colorSpace,
        toSpace target: CGColorSpace
    ) throws -> EncodedBitmap {
        let width = input.texture.width
        let height = input.texture.height
        guard width >= 1, height >= 1 else {
            throw AppError.decodeFailed("renderToEncodedBitmap: degenerate texture \(width)×\(height)")
        }
        // Discipline 1 — the fence (see doc comment; convertTexture:477-479 twin).
        let fence = commandQueue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        // The plane is tagged with what it already is — NOT a constant
        // WorkingSpace (the checker E3 contract above). HOST FINDING (11-02
        // probe, pinned by the row-order golden): `CIImage(mtlTexture:)`
        // reads the texture BOTTOM-UP in CI's origin convention, so the bare
        // render lands the bitmap VERTICALLY MIRRORED vs the texture's row
        // order. The leg's contract is "bitmap rows == texture rows" — the
        // mirror is undone here with the matching orientation tag so no
        // consumer (quantizer/encoder/11-03) ever sees the flip.
        guard let image = CIImage(mtlTexture: input.texture, options: [
            .colorSpace: sourceColorSpace,
        ])?.oriented(.downMirrored) else {
            throw AppError.decodeFailed("CIImage(mtlTexture:) failed for the export exit leg")
        }
        let signposter = Self.signposter
        let interval = signposter.beginInterval("render-exit-encoded", id: signposter.makeSignpostID())
        defer { signposter.endInterval("render-exit-encoded", interval) }

        // Direct CPU handoff: no texture allocation, the quantizer consumes
        // this Data (Discipline 3).
        let rowBytes = width * WorkingSpace.bytesPerPixel
        let byteCount = rowBytes * height
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        ciContext.render(
            image,
            toBitmap: buffer,
            rowBytes: rowBytes,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: CIFormat.RGBAf,
            colorSpace: target
        )
        let data = Data(
            bytesNoCopy: buffer,
            count: byteCount,
            deallocator: .custom { _, _ in
                buffer.deallocate()
            })
        return EncodedBitmap(data: data, width: width, height: height, rowBytes: rowBytes)
    }
}
