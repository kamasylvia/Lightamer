import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// BORDERS — the yiyin 印框 canvas module (Plan 08-01, YIYIN-01; v50 slot
// 76.0 — ALREADY in the V50Order table, zero rows inserted).
//
// NO DARKTABLE-CODE COUNTERPART (the dt `borders.c` reference informed ROI
// semantics only — L020: our backward walk carries upstream-relative xy,
// the crop.c frame convention). The functional spec is the yiyin seven-
// step composition pipeline (RESEARCH §1; `/Volumes/UNITEK/Documents/
// Development/yiyin` v1.7.1, read-only): expand the canvas around the main
// image, fill the band with a solid color or a blurred backdrop, round the
// main image corners, drop a shadow — every knob expressed as a PERCENT so
// the layout is resolution-independent (float64 mirror in `YiyinLayout`).
//
// DOMAIN: display-referred terminal segment (colorout 70.0 → borders 76.0
// → watermark 77.0 → gamma 78.0 — D-08-CONTEXT 继承定案). Input plane =
// linear display-gamut RGB (the colorout output); the solid color is
// converted through the ColorOutModule-source profile (YiyinColor, T3).
//
// ROI (L020/L021): a GEOMETRY-EXPANDING module — `modifyROIOut` grows the
// ROI to the canvas (`YiyinLayoutRecord.canvasSize`); `modifyROIIn` maps a
// canvas-region request back onto the main-image rect (1:1 — yiyin never
// rescales the main image, it grows the canvas instead). `dscIn` is ALREADY
// this run's plane extent (entry-scaled) — never re-multiplied by scale.
// The module is TERMINAL-SEGMENT/BASE-ONLY: the LAYER-06 layer-internal
// geometry rejecter covers it naturally (the terminal segment belongs to
// no layer).
//
// SEED (enabled-neutral): rate 100 / margin 0 / no aspect / no landscape /
// radius nil / shadow nil → the canvas coincides with the main image →
// byte-identical blit (cache-neutral, exposure-0EV style). The identity is
// PARAM-based, never formula-based: the yiyin ceil-quirk makes the raw
// formula grow e.g. a 7px-wide canvas (ceil(3×(7/3)) = 8).
// ─────────────────────────────────────────────────────────────────────────

public final class BordersModule: IOPModule {

    /// The background band fill. `.solid` carries an sRGB hex (#rrggbb —
    /// the yiyin `solid_color`, converted to the display domain at render,
    /// COLOR-2); `.blur` carries the blur amount percent (the yiyin
    /// `bg_blur`, default 100 — σ mapping per D-08-CONTEXT-6).
    public enum BackdropMode: Codable, Hashable, Sendable {
        case solid(color: String)
        case blur(amount: Double)
    }

    /// Canvas aspect reset (the yiyin `bg_rate` pair). nil = follow the
    /// main image.
    public struct AspectRatio: Codable, Hashable, Sendable {
        public var w: Int
        public var h: Int

        public init(w: Int, h: Int) {
            self.w = w
            self.h = h
        }
    }

    public struct Params: Codable, Hashable, Sendable {
        /// Background mode (yiyin `solid_bg` toggle + `solid_color`/`bg_blur`).
        public var mode: BackdropMode
        /// Main-image width as % of the canvas width (yiyin
        /// `main_img_w_rate`, default 90 — the canvas grows so the main
        /// image never exceeds this share).
        public var mainImageWidthRate: Double
        /// Minimal top/bottom margin as % of the canvas height (yiyin
        /// `mini_top_bottom_margin`, default 0).
        public var miniTopBottomMargin: Double
        /// Canvas aspect reset (yiyin `bg_rate`; nil = follow main).
        public var aspectRatio: AspectRatio?
        /// 竖转横 landscape output (yiyin `landscape`; MUTUALLY EXCLUSIVE
        /// with aspectRatio — commit force-clears it, yiyin
        /// `onBGRateChange`, actions/index.svelte).
        public var landscapeOutput: Bool
        /// Corner radius as % of the main-image height (yiyin `radius`,
        /// default 2.1, input cap 50; nil = square path — `radius_show`).
        public var cornerRadius: Double?
        /// Shadow blur as % of the main-image height (yiyin `shadow`,
        /// default 6, input cap 50; nil = no shadow — `shadow_show`).
        public var shadow: Double?
        /// The text bottom slot as a fraction of the canvas height (yiyin
        /// `:512` constant 0.027, parameterized for 08-2's watermark).
        public var textBottomOffset: Double
        /// Blur-mode adaptive dark overlay (yiyin brightness 4-tier mask,
        /// web `image-tool/index.ts:28-46`).
        public var adaptiveBackdrop: Bool

        public init(
            mode: BackdropMode = .solid(color: "#ffffff"),
            mainImageWidthRate: Double = 90,
            miniTopBottomMargin: Double = 0,
            aspectRatio: AspectRatio? = nil,
            landscapeOutput: Bool = false,
            cornerRadius: Double? = 2.1,
            shadow: Double? = 6,
            textBottomOffset: Double = 0.027,
            adaptiveBackdrop: Bool = true
        ) {
            self.mode = mode
            self.mainImageWidthRate = mainImageWidthRate
            self.miniTopBottomMargin = miniTopBottomMargin
            self.aspectRatio = aspectRatio
            self.landscapeOutput = landscapeOutput
            self.cornerRadius = cornerRadius
            self.shadow = shadow
            self.textBottomOffset = textBottomOffset
            self.adaptiveBackdrop = adaptiveBackdrop
        }

        /// The enabled-neutral seed (Registry.editingDefaultInstances):
        /// canvas == main image, no radius/shadow — byte-identical blit.
        public static let neutralSeed = Params(
            mode: .solid(color: "#ffffff"),
            mainImageWidthRate: 100,
            miniTopBottomMargin: 0,
            aspectRatio: nil,
            landscapeOutput: false,
            cornerRadius: nil,
            shadow: nil,
            textBottomOffset: 0.027,
            adaptiveBackdrop: true)
    }

    public static let opName = "borders"

    /// Kernel function names (`YiyinKernels.metal`; internal — the Registry
    /// prewarm list consumes the composite pass).
    static let kernelComposite = "yiyin_composite"
    static let kernelShadowSDF = "yiyin_shadow_sdf"

    /// v50 order 76.0 (V50Order table, verbatim Darktable position —
    /// between dither 75.0 and watermark 77.0; display-referred seam).
    public static let iopOrder: Float = 76.0

    /// dt flags analog: single-instance (one 印框 per image), tiling NEVER
    /// (a canvas-expanding terminal module — the tile driver's same-size
    /// contract cannot express canvas growth; see tileWorkingSet below).
    public static let flags: IOPFlags = [.oneInstance]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// The commit-clamped working copy (dt `piece->data` analog — the ROI
    /// hooks and process read THIS; the hash digests the raw params).
    private var committed: Params = Params.neutralSeed

    /// The INPUT frame origin recorded by the forward walk's
    /// `modifyROIOut` call (windowed FULL runs enter at a sub-rect of the
    /// frame — the canvas↔upstream mapping must keep that origin, L020).
    /// Default (0,0) = the full-frame/plain-pipe face. Single-owner (the
    /// box's module), mutated only by the walk, same pattern as `committed`.
    private var inputFrameOrigin: SIMD2<Int> = .zero

    /// Joint-layout injection seam (08-CONTEXT 继承定案; DECISIONS D-08-1-1):
    /// the terminal-segment assembly (08-2) may inject the jointly computed
    /// record so borders/watermark consume ONE computation. nil = compute
    /// locally from dscIn + committed params (+ empty rows). A stale
    /// override (different sourceImageSize than the run's dscIn) is
    /// discarded — the local computation is authoritative fallback.
    public var jointLayoutOverride: YiyinLayoutRecord?

    public init() {}

    /// Fresh images: the yiyin default config (NOT the seed identity —
    /// instances created without params show the yiyin look: 90% width,
    /// radius 2.1, shadow 6).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params`: clamp into the working copy, hash the RAW
    /// params (divergence #1, crop twin — record and box hashes agree).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = Self.clamp(params)
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil // no uniforms at commit time; process builds per-run
    }

    /// Input clamps (yiyin UI bounds): rate 1..100, margin 0..100,
    /// radius/shadow 0..50 (`onNumInputChange(v, 'radius', 50, 0, 1)` and
    /// the shadow twin, actions/index.svelte:298/316); aspect → landscape
    /// force-clear (`onBGRateChange`). `internal` for the test vectors.
    static func clamp(_ params: Params) -> Params {
        var out = params
        out.mainImageWidthRate = min(max(params.mainImageWidthRate, 1), 100)
        out.miniTopBottomMargin = min(max(params.miniTopBottomMargin, 0), 100)
        if let radius = params.cornerRadius {
            out.cornerRadius = min(max(radius, 0), 50)
        }
        if let shadow = params.shadow {
            out.shadow = min(max(shadow, 0), 50)
        }
        if params.aspectRatio != nil {
            out.landscapeOutput = false
        }
        if case .blur(let amount) = params.mode {
            out.mode = .blur(amount: min(max(amount, 0), 100))
        }
        if out.aspectRatio?.w == 0 { out.aspectRatio?.w = 1 }
        if out.aspectRatio?.h == 0 { out.aspectRatio?.h = 1 }
        return out
    }

    /// The param face of the enabled-neutral seed (the blit identity —
    /// canvas coincides with the main image, no radius, no shadow). The
    /// identity NEVER rides the yiyin formula: its ceil-quirk grows e.g.
    /// a 7px canvas (ceil(3 × (7/3)) = 8). `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        guard p.mainImageWidthRate >= 100, p.miniTopBottomMargin == 0,
            p.aspectRatio == nil, !p.landscapeOutput,
            p.cornerRadius == nil || p.cornerRadius! <= 0,
            p.shadow == nil || p.shadow! <= 0
        else { return false }
        return true
    }

    // MARK: - Layout access (the joint-record seam)

    /// The effective record for THIS run: the injected override when its
    /// source size matches `dscIn`, else the local float64 computation
    /// (empty rows — 08-1 no-watermark state; 08-2 activates rows).
    func effectiveLayout(dscIn: IOPBufferDesc) -> YiyinLayoutRecord {
        let size = SIMD2(max(dscIn.width, 1), max(dscIn.height, 1))
        if let override = jointLayoutOverride, override.sourceImageSize == size {
            return override
        }
        return YiyinLayout.layout(
            imageSize: size, borders: committed, rows: [])
    }

    /// The full render-identity predicate: the record's geometry leaves no
    /// visible band, no corner cut, no shadow (the record-based truth —
    /// stronger than `isNeutral`, covers coincidentally-identity shapes).
    func isIdentityRender(_ record: YiyinLayoutRecord) -> Bool {
        record.isIdentityCanvas
            && record.cornerRadiusPx == 0
            && record.shadowBlurPx == 0
    }

    // MARK: - ROI negotiation (L020 frame convention)

    /// Canvas growth (`modify_roi_out` semantics — dt borders.c:429-470
    /// consulted for the walk coordinate premise; the expansion itself is
    /// the yiyin canvas). The canvas rect is recorded at the frame origin
    /// (the main image sits at positive offsets inside it — same
    /// upstream-relative convention as crop's window origin). RECORDS the
    /// input origin for the windowed backward mapping.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        inputFrameOrigin = SIMD2(input.x, input.y)
        if isNeutral(committed) {
            roi = input
            return
        }
        let record = effectiveLayout(dscIn: piece.dscIn)
        roi = input
        roi.x = 0
        roi.y = 0
        roi.width = max(input.width, record.canvasSize.x)
        roi.height = max(input.height, record.canvasSize.y)
    }

    /// Map a canvas-region request back onto the main-image rect (1:1 —
    /// yiyin never rescales the main image). The returned rect is in
    /// UPSTREAM FRAME pixels — the input plane's frame origin (recorded at
    /// `modifyROIOut`) is preserved so windowed FULL runs re-enter at the
    /// right sub-rect; the pipe clamps to the upstream plane.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        if isNeutral(committed) || piece.dscIn.width <= 0 || piece.dscIn.height <= 0 {
            input = roi
            return
        }
        let record = effectiveLayout(dscIn: piece.dscIn)
        let mx = record.mainImageOrigin.x
        let my = record.mainImageOrigin.y
        let ox = inputFrameOrigin.x
        let oy = inputFrameOrigin.y
        // Upstream rect covering the requested canvas region's intersection
        // with the main image: canvasX = frameX − mx + ox.
        let x0 = max(roi.x - mx + ox, ox)
        let y0 = max(roi.y - my + oy, oy)
        let x1 = min(roi.x + roi.width - mx + ox, ox + piece.dscIn.width)
        let y1 = min(roi.y + roi.height - my + oy, oy + piece.dscIn.height)
        input = roi
        input.x = x0
        input.y = y0
        input.width = max(1, x1 - x0)
        input.height = max(1, y1 - y0)
    }

    // MARK: - Process

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        if isNeutral(committed) {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let record = effectiveLayout(dscIn: piece.dscIn)
        if isIdentityRender(record) {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        // Blur leg gate (T5 wires the proxy/overlay).
        guard case .solid(let hex) = committed.mode else {
            throw AppError.notImplemented("borders blur leg (Plan 08-01 T5)")
        }

        // ── T4 shadow leg: the SDF alpha plane → the shared Deriche IIR →
        //    the composite mixes it beneath the main image. σ mapping
        //    (DECISIONS D-08-1-4): CSS canvas `shadowBlur` ≈ 2σ —
        //    σ_shadow = 0.5 × shadowBlurPx (the ×0.5 family of
        //    D-08-CONTEXT-6). yiyin's shadow = the FULL-strength black
        //    path shadow (rgba(0,0,0,1)); the main image draws over the
        //    band it covers, so no explicit hole punch is needed (the
        //    hole exists only in yiyin's mask PNG because the PNG lands
        //    ON TOP of the main image — our composite draws the shadow
        //    BENEATH, same visual, one pass less).
        var shadow: (any MTLTexture)?
        if (committed.shadow ?? 0) > 0 {
            shadow = try await buildShadowPlane(record: record, roiOut: roiOut, metal: metal)
        }

        // ── T3 solid leg: ONE composite dispatch. Fill = the hex converted
        // through the ColorOutModule matrix family (COLOR-2); unresolved
        // hex degrades to white (yiyin `|| '#fff'`).
        let target: DisplayProfile
        if let override = displayProfileOverride {
            target = override
        } else {
            target = .current()
        }
        let fill =
            YiyinColor.linearDisplay(fromSRGBHex: hex, target: target)
            ?? SIMD3<Float>(1, 1, 1)
        try await dispatchComposite(
            input: input, output: output, roiIn: roiIn, roiOut: roiOut,
            record: record, fill: fill, overlay: nil, shadow: shadow, metal: metal)
    }

    // MARK: - Shadow plane (T4 — L018 scratch discipline)

    /// Module-owned shadow scratch, cached per canvas size (SkinSmooth's
    /// scratch pattern; single-owner — one pipe run at a time).
    private var shadowCanvasWidth = 0
    private var shadowCanvasHeight = 0
    private var shadowPlane: (any MTLTexture)?
    private var shadowBlurPlanes: (any MTLBuffer)?

    private func ensureShadowScratch(width: Int, height: Int) throws -> (any MTLBuffer) {
        guard width != shadowCanvasWidth || height != shadowCanvasHeight else {
            guard let planes = shadowBlurPlanes else {
                throw MetalError.bufferAllocationFailed(width * height * 32)
            }
            return planes
        }
        guard let resolved = resolvedDevice else {
            throw MetalError.psoCreationFailed(Self.kernelShadowSDF, nil)
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = resolved.makeTexture(descriptor: descriptor),
            let planes = resolved.makeBuffer(
                length: width * height * MemoryLayout<Float>.stride * 4 * 2,
                options: .storageModeShared)
        else {
            throw MetalError.bufferAllocationFailed(width * height * 32)
        }
        shadowPlane = texture
        shadowBlurPlanes = planes
        shadowCanvasWidth = width
        shadowCanvasHeight = height
        return planes
    }

    private var resolvedDevice: (any MTLDevice)?

    /// Stamp the rounded-rect SDF at the canvas extent and blur it IN
    /// PLACE (col pass reads the texture → planes; the store pass writes
    /// it back — same-queue FIFO orders the three command buffers, and
    /// the texture is only read in pass 1 and written in pass 3).
    func buildShadowPlane(
        record: YiyinLayoutRecord, roiOut: ROI, metal: MetalContext
    ) async throws -> (any MTLTexture) {
        if resolvedDevice == nil { resolvedDevice = metal.device }
        let width = max(roiOut.width, 1)
        let height = max(roiOut.height, 1)
        let planes = try ensureShadowScratch(width: width, height: height)
        guard let sdf = shadowPlane else {
            throw MetalError.psoCreationFailed(Self.kernelShadowSDF, nil)
        }
        let mainOrigin = SIMD2<Float>(
            Float(record.mainImageOrigin.x), Float(record.mainImageOrigin.y))
        let outOrigin = SIMD2<Float>(Float(roiOut.x), Float(roiOut.y))
        let mainSize = SIMD2<Float>(
            Float(record.sourceImageSize.x), Float(record.sourceImageSize.y))
        var u = CompositeUniforms(
            solidMode: 1, hasOverlay: 0, hasShadow: 0, hasBlurTex: 0,
            fillColor: .zero, overlayColor: .zero,
            mainOffset: mainOrigin - outOrigin, mainSize: mainSize,
            sdfCenter: mainOrigin + mainSize / 2 - outOrigin,
            sdfHalf: mainSize / 2,
            radius: Float(record.cornerRadiusPx),
            blurSigmaNorm: 0,
            outputSize: SIMD2(Float(width), Float(height)),
            blurTexSize: SIMD2(1, 1), pad0: .zero)
        guard let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<CompositeUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }

        let stamp = try await metal.makeEncoder(functionName: Self.kernelShadowSDF)
        stamp.encoder.setTexture(sdf, index: 0)
        stamp.encoder.setBuffer(buffer, offset: 0, index: 0)
        stamp.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        stamp.encoder.endEncoding()
        stamp.commandBuffer.commit()

        // The shared Deriche IIR (L018 double-buffer discipline — the
        // planes buffer IS its two device planes; zero blur rewrites).
        try await GaussianBlur.blur(
            input: sdf, output: sdf, planes: planes,
            sigma: Float(record.shadowBlurPx * 0.5), order: .zero,
            boundsMin: SIMD4(repeating: 0), boundsMax: SIMD4(repeating: 1),
            metal: metal)
        return sdf
    }

    /// The coordinator-injected display override (ColorOutModule twin): a
    /// live display change must flip the fill conversion the same way it
    /// flips colorout. nil = resolve the current screen.
    public var displayProfileOverride: DisplayProfile?

    /// The composite uniforms (MSL mirror of `YiyinCompositeUniforms`).
    struct CompositeUniforms {
        var solidMode: Int32
        var hasOverlay: Int32
        var hasShadow: Int32
        var hasBlurTex: Int32
        var fillColor: SIMD4<Float>
        var overlayColor: SIMD4<Float>
        var mainOffset: SIMD2<Float>
        var mainSize: SIMD2<Float>
        var sdfCenter: SIMD2<Float>
        var sdfHalf: SIMD2<Float>
        var radius: Float
        var blurSigmaNorm: Float
        var outputSize: SIMD2<Float>
        var blurTexSize: SIMD2<Float>
        var pad0: SIMD2<Float>
    }

    /// The single canvas-composition dispatch (T3 shape: solid fill +
    /// 1:1 main-image blit + SDF clip; T4 adds the shadow plane, T5 the
    /// blur proxy/overlay). Geometry is output-plane-relative:
    /// mainOffset = mainOrigin − roiOut.origin — the kernel samples input
    /// at p − mainOffset; the input plane already carries the frame
    /// region origin-to-origin (the input-frame origin cancels between
    /// the canvas mapping and the plane render).
    func dispatchComposite(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        record: YiyinLayoutRecord,
        fill: SIMD3<Float>,
        overlay: SIMD4<Float>?,
        shadow: (any MTLTexture)?,
        metal: MetalContext
    ) async throws {
        let mainOrigin = SIMD2<Float>(
            Float(record.mainImageOrigin.x), Float(record.mainImageOrigin.y))
        let outOrigin = SIMD2<Float>(Float(roiOut.x), Float(roiOut.y))
        var u = CompositeUniforms(
            solidMode: 1,
            hasOverlay: overlay != nil ? 1 : 0,
            hasShadow: shadow != nil ? 1 : 0,
            hasBlurTex: 0,
            fillColor: SIMD4(fill.x, fill.y, fill.z, 1),
            overlayColor: overlay ?? SIMD4(0, 0, 0, 0),
            mainOffset: mainOrigin - outOrigin,
            mainSize: SIMD2(Float(input.width), Float(input.height)),
            sdfCenter: mainOrigin + SIMD2(
                Float(record.sourceImageSize.x), Float(record.sourceImageSize.y)) / 2
                - outOrigin,
            sdfHalf: SIMD2(
                Float(record.sourceImageSize.x), Float(record.sourceImageSize.y)) / 2,
            radius: Float(record.cornerRadiusPx),
            blurSigmaNorm: 0,
            outputSize: SIMD2(Float(output.width), Float(output.height)),
            blurTexSize: SIMD2(1, 1),
            pad0: .zero)
        guard let buffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<CompositeUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }

        // auxTex: the shadow plane (T4) / blur proxy (T5); a 1×1 dummy
        // keeps the binding table total when the legs are inert.
        let aux: any MTLTexture
        if let shadow {
            aux = shadow
        } else {
            aux = try Self.dummyTexture(metal: metal)
        }
        let session = try await metal.makeEncoder(functionName: Self.kernelComposite)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(aux, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        precondition(
            8 * 8 <= session.pipelineState.maxTotalThreadsPerThreadgroup,
            "yiyin_composite threadgroup exceeds the PSO budget")
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// The 1×1 inert aux texture (binding-table filler).
    private static func dummyTexture(metal: MetalContext) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.bufferAllocationFailed(16)
        }
        return texture
    }

    /// Whole-window blit (dt `copy_image_roi` fast path — crop/skinSmooth
    /// twin). Sync (same-queue FIFO orders it; the caller's fence covers
    /// readback, L014).
    func blitIdentity(
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
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
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
        blit.endEncoding() // L008: encode close precedes commit, never defer
        commandBuffer.commit()
    }
}
