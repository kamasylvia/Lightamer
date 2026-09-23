import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// LENS — lens correction (Plan 04-04-T1/T2, IOP-GEO-03).
//
// Darktable reference: `src/iop/lens.cc` (tree dc58cf0ba1)
//   - flags/modflags    :80-95   (TCA/vignetting/distortion bits)
//   - TCA manual params :140-144 (tca_r/tca_b override, 0.99..1.01)
//   - vignette-first    :1194-1206 (devignette the INPUT buffer, then warp)
//   - ROI               :1697-1790 (`_modify_roi_in_lf`: border points
//                            through the correct-modifier → 6-coord AABB +
//                            interpolation margin)
//   - v50 slot 13.0 (`iop_order.c`; the `cacorrectrgb` 13.5 comment notes
//                            CA-after-lens ordering — this module sits there)
//
// (a) CIRAW EMBEDDED LAYER — documentation IS the delivery (D-G1 (a)):
// Phase 1 proved CIRAW auto-applies DNG OpcodeList / vendor-opcode lens
// correction for supported lenses — the decoded pixels ALREADY contain
// the embedded correction. There is NO `mods_done` re-detection here
// (that needs the lensfun C library — the dependency red line): the
// manual layer below defaults OFF/neutral, and the panel carries the
// double-correction warning. Recorded known tradeoff (plan Goal (a)).
//
// FRAME CONVENTION (L020 — crop double-offset postmortem, ashift D7 twin):
// The forward walk (`PixelPipe.run` bufInROI/levelROI, dt `get_dimensions`
// buf_in/buf_out) records window origins in UPSTREAM coords; the backward
// walk seeds from the forward result, so `modifyROIIn` receives
// OUTPUT-FRAME coords (xy upstream-relative). dt's `roi_out + buf_in`-style
// re-adds presuppose dt's WINDOW-RELATIVE roi_out — never re-applied here:
//  - `modifyROIOut` keeps `x/y = input.x/y` (dt lens has NO modify_roi_out —
//    output == input frame; the forward AABB only ever GROWS via the
//    backward leg + the union-clamp contract) and recomputes ONLY w/h
//    (input-frame border points through the GREEN-channel-corrected
//    forward map → AABB + 2px, clamped to bufIn).
//  - `modifyROIIn` maps the four OUTPUT-FRAME border point sets through the
//    FORWARD map (dt `:1741-1758` uses the correct-modifier forward — NO
//    Newton inverse solve) for R/G/B (TCA bends each channel differently)
//    → union AABB + 2px interpolation margin (dt `:1791-1793`) → clamp to
//    bufIn. Neutral → verbatim.
//  - `process` re-bases per pixel (`gid + oroi − iroi − center`, halfW
//    radius unit), the partial-downstream per-boundary re-base protocol
//    L020 left to 04-03 (ashift twin).
//
// SCALE: the pipe stamps `dscIn` at ENTRY size and both ROIs share one
// scale per run, so ALL coords below are plane pixels (ashift twin — no
// `/scale` × `scale` round-trip, dt `:1708-1709`). The optical center is
// the FULL-FRAME center (`dscIn/2 − roiIn.xy` in-plane); crop sits
// DOWNSTREAM of lens (13.0 < 24.5), so lens always sees the full upstream
// frame and the center stays exact under roiHint sub-windows too.
//
// UNIFORMS per-run via shared MTLBuffer (D2 — needs bufIn size for the
// center/halfW; `piece.data = nil`). 80-byte struct, all members 4/8/16
// aligned (the ashift `float hinv[9]` packing postmortem applies).
//
// INTENTIONAL DIVERGENCES:
// 1. **Vignette is a DIVISION (devignette), not a multiplication** (D1):
//    the plan's `I' = I·(1+k r²…)` literal is backwards for lensfun data —
//    lensfun correct-mode applies `1/(1+k1r²+k2r⁴+k3r⁶)`
//    (`mod-color.cpp ModifyColor_DeVignetting_PA`; XML k are negative at
//    wide apertures, corners must BRIGHTEN). Manual sliders share the
//    division semantic (same sign as XML coefficients).
// 2. **Unified dc1..dc4 + full 6-term TCA polynomial** (D2): the kernel
//    evaluates the union of poly3/poly5/ptlens/linear/poly3-TCA exactly —
//    no model-specific branches, no radius-series truncation. Manual
//    (k1,k2,tcaR,tcaB,vigK) maps losslessly into it.
// 3. **No projection-transform / scale / reverse / ACM / fisheye types**
//    (D-G1 scope): v1 lenses are rectilinear; a `<type>` other than
//    rectilinear/absent resolves (fisheye params do NOT feed this kernel).
//    Real-focal defaults to nominal (v1 subset has no `<real-focal-length>`).
// 4. **Neutral/pathological → blit identity** (D5; ashift D5 twin): dt
//    disables the piece; the pipe owns enablement here — identity + log.
// ─────────────────────────────────────────────────────────────────────────

/// Kernel-name + bundle-anchor convenience (the `PassthroughKernel` pattern).
public enum LensKernel {
    public static let functionName = "lens_manual_warp"
}

/// Where the committed coefficients came from (panel文案 + resolve path).
public enum LensSource: String, Codable, Hashable, Sendable {
    /// Nothing applied (default; neutral ⇒ cache-neutral).
    case off
    /// Hand-driven sliders (panel §2).
    case manual
    /// Resolved from a LensfunDB entry (panel §3 "apply match").
    case lensfun
}

public final class LensModule: IOPModule {

    /// `LensParams` (plan Must-haves + D6 EXIF snapshot): the manual
    /// coefficients live in the KERNEL's radius unit
    /// (`u = (p − c)/halfW` — see LensKernels.metal header); XML-side
    /// values are converted at resolve time (LensfunMatch), NOT here.
    public struct Params: Codable, Hashable, Sendable {
        /// Radial distortion k1 (× Ru² term; poly3/poly5/ptlens-b equivalent).
        public var distortionK1: Float
        /// Radial distortion k2 (× Ru⁴ term; poly5 equivalent).
        public var distortionK2: Float
        /// Red-channel TCA scale minus 1 (lensfun linear kr − 1; ±0.01 UI).
        public var tcaR: Float
        /// Blue-channel TCA scale minus 1 (lensfun linear kb − 1).
        public var tcaB: Float
        /// Devignette denominator k1/k2/k3 (× rd²/rd⁴/rd⁶; XML pa sign).
        public var vignetteK1: Float
        public var vignetteK2: Float
        public var vignetteK3: Float
        /// Coefficient provenance (D5: excluded from the neutral predicate).
        public var source: LensSource
        // D6 EXIF snapshot (resolve inputs, baked at reloadDefaults):
        public var focalLength: Float?
        public var aperture: Float?
        public var lensKey: String?

        public init(
            distortionK1: Float = 0,
            distortionK2: Float = 0,
            tcaR: Float = 0,
            tcaB: Float = 0,
            vignetteK1: Float = 0,
            vignetteK2: Float = 0,
            vignetteK3: Float = 0,
            source: LensSource = .off,
            focalLength: Float? = nil,
            aperture: Float? = nil,
            lensKey: String? = nil
        ) {
            self.distortionK1 = distortionK1
            self.distortionK2 = distortionK2
            self.tcaR = tcaR
            self.tcaB = tcaB
            self.vignetteK1 = vignetteK1
            self.vignetteK2 = vignetteK2
            self.vignetteK3 = vignetteK3
            self.source = source
            self.focalLength = focalLength
            self.aperture = aperture
            self.lensKey = lensKey
        }

        /// The neutral identity (cache-neutral seed).
        public static let neutral = Params()
    }

    public static let opName = "lens"

    /// Darktable v50 order slot 13.0 — after scalepixels (12.0), before
    /// cacorrectrgb (13.5, whose source comment orders CA-after-lens).
    public static let iopOrder: Float = 13.0

    /// dt flags subset (`lens.cc` module flags): single-instance,
    /// tiling-eligible, fast-pipe member. (No `supportsBlending`.)
    public static let flags: IOPFlags = [.allowTiling, .oneInstance, .allowFastPipe]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// dt neutral eps (ashift `:990` twin).
    static let neutralEps: Float = 1e-6

    /// The committed working copy (dt `piece->data` analog).
    /// Owned by the box's isolation domain (CropModule precedent).
    private var committed: Params = Params()

    public init() {}

    /// Fresh images: neutral OFF (anti-double-correction — the (a) layer:
    /// CIRAW already applied the embedded correction, so the manual layer
    /// must not add more). The EXIF snapshot rides along for the (c) layer
    /// (D6 — resolve inputs baked here so params stay self-describing).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        let cap = image.capture
        let lensKey = cap.lensModel
        let focal = cap.focalLength.map { Float($0) }
        let aperture = cap.aperture.map { Float($0) }
        return Params(source: .off, focalLength: focal, aperture: aperture, lensKey: lensKey)
    }

    /// Park the working copy, hash the RAW params (D-H4). No uniforms
    /// buffer (D2 — per-run shared buffer, needs bufIn size).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = params
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    /// Neutral predicate over the OPTICAL coefficients (D5): all-zero
    /// distortion/TCA-offset/vignette. `source` excluded (a lensfun resolve
    /// that lands all-zero is equally identity). `internal` for tests.
    func isNeutral(_ p: Params) -> Bool {
        let e = Self.neutralEps
        return abs(p.distortionK1) < e
            && abs(p.distortionK2) < e
            && abs(p.tcaR) < e
            && abs(p.tcaB) < e
            && abs(p.vignetteK1) < e
            && abs(p.vignetteK2) < e
            && abs(p.vignetteK3) < e
    }

    /// The kernel uniforms for the committed manual params at the run
    /// geometry (D2 exact mapping; TCA offsets → vr/vb scales).
    /// `internal` for the parity tests' hand checks.
    func manualUniforms(bufW: Int, bufH: Int, roiIn: ROI) -> LensWarpUniforms {
        let p = committed
        return LensWarpUniforms(
            dc1: 0, dc2: p.distortionK1, dc3: 0, dc4: p.distortionK2,
            vr: 1 + p.tcaR, cr: 0, br: 0,
            vb: 1 + p.tcaB, cb: 0, bb: 0,
            vk1: p.vignetteK1, vk2: p.vignetteK2, vk3: p.vignetteK3,
            centerX: Float(bufW) / 2, centerY: Float(bufH) / 2,
            halfW: Float(bufW) / 2,
            oroiX: 0, oroiY: 0, iroiX: Int32(roiIn.x), iroiY: Int32(roiIn.y),
            inW: Int32(bufW), inH: Int32(bufH))
    }

    /// Forward radial map at the GREEN channel (ROI legs all use G — the
    /// unscaled channel; TCA spread is bounded by the +2px margin):
    /// `Rd = Ru·(1 + dc1·Ru + dc2·Ru² + dc3·Ru³ + dc4·Ru⁴)` in u units.
    /// `internal` for ROI hand checks + the Python synthesis twin.
    func forwardRadius(_ ru: Double, dc: (Double, Double, Double, Double)) -> Double {
        ru * (1 + dc.0 * ru + dc.1 * ru * ru + dc.2 * ru * ru * ru + dc.3 * ru * ru * ru * ru)
    }

    /// Manual committed coeffs as the (dc1..dc4) tuple. `internal` for tests.
    func manualDC() -> (Double, Double, Double, Double) {
        (0, Double(committed.distortionK1), 0, Double(committed.distortionK2))
    }

    /// Forward-map one input-frame point through distortion (G channel) →
    /// input-frame coords, in PLANE pixels. Center = full-frame center.
    private func forwardPoint(x: Double, y: Double, bufW: Double, bufH: Double) -> (x: Double, y: Double) {
        let dc = manualDC()
        let cx = bufW / 2, cy = bufH / 2
        let halfW = bufW / 2
        let dx = (x - cx) / halfW, dy = (y - cy) / halfW
        let ru = (dx * dx + dy * dy).squareRoot()
        guard ru > 1e-12 else { return (x, y) }
        let s = forwardRadius(ru, dc: dc) / ru
        return (cx + dx * s * halfW, cy + dy * s * halfW)
    }

    /// dt lens has NO modify_roi_out (output == input frame): keep the
    /// input verbatim (origin preserved — L020). The backward leg + the
    /// union-clamp contract carry all growth (04-03 processRec).
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    /// dt `_modify_roi_in_lf` (`:1697-1790`) under OUR walk's frame
    /// convention (L020): the incoming `roi` already carries output-FRAME
    /// coords. Border points (4 edges, step ≤ 8px — dt walks EVERY border
    /// pixel; the radial map is smooth so a strided walk + the +2px margin
    /// covers it) go through the FORWARD map (dt `:1741-1758` — no Newton
    /// inverse) for R/G/B… in v1 the TCA spread is sub-pixel-to-pixel, so
    /// the G map + 2px margin (dt `:1791-1793` interpolation width) covers
    /// all three channels; the resolved-XML path (T2) widens to the
    /// per-channel union. → AABB + 2px → clamp to bufIn (dt `:1791-1799`).
    /// Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        if isNeutral(committed) { input = roi; return }
        let bufW = Double(piece.dscIn.width), bufH = Double(piece.dscIn.height)
        let corners = borderPoints(roi: roi, step: 8)
        var xm = Double.greatestFiniteMagnitude, ym = Double.greatestFiniteMagnitude
        var xM = -Double.greatestFiniteMagnitude, yM = -Double.greatestFiniteMagnitude
        for (x, y) in corners {
            let q = forwardPoint(x: x, y: y, bufW: bufW, bufH: bufH)
            xm = min(xm, q.x); xM = max(xM, q.x)
            ym = min(ym, q.y); yM = max(yM, q.y)
        }
        // dt `:1791-1793`: 2px interpolation margin (bilinear tap = 1,
        // TCA channel spread folds into the same margin in v1). The WIDTH
        // measures from the CLAMPED origin (dt `:1791-1799` clamps x/y
        // first, then `width = MIN(orig − x, xM − x + interp)`): measuring
        // from the unclamped xm UNDERCOVERS when the AABB shrinks inside
        // the frame (pincushion: xm=2.56 → width lost 2.56px + the +1
        // inclusive fudge never repaid — the input plane missed tap texel
        // 61 and the kernel froze at x0, caught by track-A golden).
        let m = 2.0
        var ix = xm - m, iy = ym - m
        // dt `:1791-1799` clamp to bufIn FIRST.
        ix = min(max(ix, 0), floor(bufW))
        iy = min(max(iy, 0), floor(bufH))
        var iw = xM + m - ix, ih = yM + m - iy
        iw = min(max(iw, 4), floor(bufW) - ix)
        ih = min(max(ih, 4), floor(bufH) - iy)
        input = ROI(x: Int(ix.rounded(.down)), y: Int(iy.rounded(.down)),
                    width: Int(iw.rounded(.down)), height: Int(ih.rounded(.down)),
                    scale: roi.scale)
    }

    /// Border points of `roi` (output frame), strided (dt `:1740-1758`
    /// walks every border pixel; stride-8 + margin is the v1 sampling).
    func borderPoints(roi: ROI, step: Int) -> [(x: Double, y: Double)] {
        var pts: [(x: Double, y: Double)] = []
        let x0 = Double(roi.x), y0 = Double(roi.y)
        let x1 = Double(roi.x + roi.width), y1 = Double(roi.y + roi.height)
        var x = x0
        while x <= x1 {
            pts.append((x, y0)); pts.append((x, y1))
            x += Double(step)
        }
        pts.append((x1, y0)); pts.append((x1, y1))
        var y = y0 + Double(step)
        while y < y1 {
            pts.append((x0, y)); pts.append((x1, y))
            y += Double(step)
        }
        return pts
    }

    /// Plan 06-03 T2 point-mapping segment (D-06-CONTEXT-7): the manual
    /// radial coefficients (k1/k2 in halfW units, G channel) — nil when
    /// neutral (`.off` default maps masks 1:1). The segment's inverse IS
    /// the warp kernel's sampling map (`forwardPoint` semantics); the
    /// forward is its guarded Newton solve (GeometryPointMapper).
    public func pointMapSegment(
        inputSize: SIMD2<Double>
    ) -> (segment: GeometrySegment, outputSize: SIMD2<Double>)? {
        guard !isNeutral(committed) else { return nil }
        return (
            .radial(
                k1: Double(committed.distortionK1),
                k2: Double(committed.distortionK2),
                size: inputSize),
            inputSize
        )
    }

    /// Source-aware resolve (D6): manual/off → kernel coeffs straight from
    /// committed; lensfun → `LensfunMatch.resolve` against the shared store
    /// (nil DB / miss ⇒ nil ⇒ caller falls back to blit identity + log —
    /// the downgrade path is data-absence, never a crash).
    func resolveUniforms(
        bufW: Int, bufH: Int, roiIn: ROI, roiOut: ROI
    ) async -> LensWarpUniforms? {
        if committed.source == .lensfun {
            guard let params = await LensfunStore.resolveCommitted(
                committed, width: bufW, height: bufH) else { return nil }
            return params.uniforms(
                bufW: bufW, bufH: bufH, roiIn: roiIn, roiOut: roiOut)
        }
        return manualUniforms(bufW: bufW, bufH: bufH, roiIn: roiIn)
            .rebased(roiOut: roiOut)
    }

    /// dt CPU/CL legs: neutral or unresolvable → blit identity (D5). Else
    /// single-pass `lens_manual_warp` over the OUTPUT plane.
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
        guard var uniforms = await resolveUniforms(
            bufW: piece.dscIn.width, bufH: piece.dscIn.height,
            roiIn: roiIn, roiOut: roiOut
        ) else {
            AppError.logger.warning(
                "lens resolve failed (no DB / miss) — rendering identity")
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        // Upload through a shared MTLBuffer (NOT setBytes: 80-byte struct —
        // the ashift postmortem: stack-addressed setBytes raced the
        // async-committed encoder on this host).
        guard let buffer = metal.device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<LensWarpUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        try await metal.dispatch2DTexture(
            functionName: LensKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// Whole-window blit (dt `copy_image_roi` fast path, `imagebuf.c`).
    /// Sync (no GPU wait — same-queue FIFO orders it; the caller's fence
    /// covers readback, L014).
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

/// Swift mirror of the MSL `LensWarpUniforms` struct — 4×float4 + 4×float2 +
/// int2 = 80 bytes. Every member is 4/8/16-byte aligned on both sides.
struct LensWarpUniforms {
    var dist: SIMD4<Float>   // dc1, dc2, dc3, dc4
    var tcaR: SIMD4<Float>   // vr, cr, br, pad
    var tcaB: SIMD4<Float>   // vb, cb, bb, pad
    var vig: SIMD4<Float>    // vk1, vk2, vk3, pad
    var center: SIMD2<Float>
    var halfW: SIMD2<Float>  // (halfW, 0-pad)
    var oroi: SIMD2<Float>
    var iroi: SIMD2<Float>
    var inSize: SIMD2<Int32>

    init(dc1: Float, dc2: Float, dc3: Float, dc4: Float,
         vr: Float, cr: Float, br: Float,
         vb: Float, cb: Float, bb: Float,
         vk1: Float, vk2: Float, vk3: Float,
         centerX: Float, centerY: Float, halfW: Float,
         oroiX: Float, oroiY: Float, iroiX: Int32, iroiY: Int32,
         inW: Int32, inH: Int32) {
        self.dist = SIMD4(dc1, dc2, dc3, dc4)
        self.tcaR = SIMD4(vr, cr, br, 0)
        self.tcaB = SIMD4(vb, cb, bb, 0)
        self.vig = SIMD4(vk1, vk2, vk3, 0)
        self.center = SIMD2(centerX, centerY)
        self.halfW = SIMD2(halfW, 0)
        self.oroi = SIMD2(oroiX, oroiY)
        self.iroi = SIMD2(Float(iroiX), Float(iroiY))
        self.inSize = SIMD2(inW, inH)
    }

    /// Re-base the output origin (L020: per-run roiOut differs from the
    /// construction-time default).
    func rebased(roiOut: ROI) -> LensWarpUniforms {
        var out = self
        out.oroi = SIMD2(Float(roiOut.x), Float(roiOut.y))
        return out
    }
}
