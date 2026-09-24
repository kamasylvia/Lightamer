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
    /// upstream-relative convention as crop's window origin).
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
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
    /// UPSTREAM (frame) pixels, origin-to-origin renderable by the pipe;
    /// the pipe clamps to the upstream plane (crop.c:576-592 convention).
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        if isNeutral(committed) || piece.dscIn.width <= 0 || piece.dscIn.height <= 0 {
            input = roi
            return
        }
        let record = effectiveLayout(dscIn: piece.dscIn)
        let mx = record.mainImageOrigin.x
        let my = record.mainImageOrigin.y
        let mw = record.sourceImageSize.x
        let mh = record.sourceImageSize.y
        // Upstream rect covering the requested canvas region's intersection
        // with the main image: canvasX = upstreamX + mx.
        let x0 = max(roi.x - mx, 0)
        let y0 = max(roi.y - my, 0)
        let x1 = min(roi.x + roi.width - mx, mw)
        let y1 = min(roi.y + roi.height - my, mh)
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
        // T1 delivers the skeleton + identity; the render legs land with
        // T3 (solid + composite + color), T4 (radius + shadow), T5 (blur +
        // adaptive overlay). A non-neutral commit before those tasks is a
        // programming error — typed, never a silent wrong-output blit.
        throw AppError.notImplemented("borders render legs (Plan 08-01 T3/T4/T5)")
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
