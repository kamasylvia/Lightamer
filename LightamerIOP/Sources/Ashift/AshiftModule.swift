import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// ASHIFT — rotate + perspective (Plan 04-03-T2, IOP-GEO-02).
//
// Darktable reference: `src/iop/ashift.c` (tree dc58cf0ba1)
//   - params      :272-291  (rotation/lensshift/shear/f_length/crop_factor
//                            + orthocorr/aspect/mode/cropmode + cl/cr/ct/cb;
//                            Lightamer keeps the GENERIC subset —
//                            04-03-DECISIONS D1)
//   - `_homography`:756-979 (10-step synthesis; forward, inverted on ask)
//   - `_isneutral`  :985-999 (eps 1e-4 over rotation/shifts/shear/aspect/
//                            clip — the module's neutral predicate)
//   - `commit_params:5588-5626` (GENERIC fold: f_length_kb=28,
//                            orthocorr=0, aspect=1)
//   - `modify_roi_out:1142-1211` (forward corners → AABB × clip → floor;
//                            <4px → disable)
//   - `modify_roi_in :1213-1285` (inverse corners + clip offset → AABB +
//                            2× interpolation margin → clamp bufIn)
//   - CPU leg     :3522-3566 / CL leg :3659-3703 (inverse per-output-pixel
//                            backward sample + clip re-base)
//   - v50 slot 15.0 (`iop_order.c:319`), BEFORE flip (16.0) — the pipe
//                            sorts it there (V50OrderTests pins the chain).
//
// FRAME CONVENTION (L020 — the crop double-offset postmortem):
// The forward walk (`PixelPipe.run` `bufInROI`/`levelROI`, dt
// `get_dimensions` buf_in/buf_out) records window origins in UPSTREAM
// coords; the backward walk seeds from the forward result, so
// `modifyROIIn` receives OUTPUT-FRAME coords (xy upstream-relative).
// dt's `roi_in = roi_out + buf_in·cx`-style re-adds presuppose dt's
// WINDOW-RELATIVE roi_out — never re-applied here:
//  - `modifyROIOut` keeps `x/y = input.x/y` (dt `:1148` `*roi_out =
//    *roi_in` verbatim) and recomputes ONLY w/h (forward AABB of the
//    input rect × inner clip → floor, dt `:1190-1194`).
//  - `modifyROIIn` maps the four OUTPUT-FRAME corners (roi.xy + clip +
//    0/w/h extents, dt `:1249-1250`) through the INVERSE matrix into the
//    INPUT frame (dt `:1261-1262`, no buf_in re-add) → AABB + 2×
//    interpolation margin (dt `:1272-1277`, `iw1` = bilinear 1 tap) →
//    clamp to bufIn (dt `:1281-1284`).
//  - `process` re-bases per pixel (`oroi.xy + clip → Hinv → − iroi.xy`),
//    dt `distort_backtransform` semantics — the partial-downstream
//    per-boundary re-base protocol L020 left to 04-03.
//
// SCALE (Intentional divergence — Homography.swift header): the pipe
// stamps `dscIn` at ENTRY size and both ROIs share one scale per run, so
// H is built at plane size and ALL coords below are plane pixels. No
// `/scale` × `scale` round-trip (dt `:3545-3556`); multi-resolution stays
// proportional, and the forward/inverse pair stays exactly consistent.
//
// EXIF division of labor (04-03-T0 decision (3)): 90° steps are flip's
// (reloadDefaults seeds from DecodedImage); ashift handles fine rotation
// + perspective only.
//
// INTENTIONAL DIVERGENCES:
// 1. **Mode locked GENERIC** (D1): orthocorr/aspect/mode/cropmode/lines
//    GUI-fit machinery unported; fLength/cropFactor ride inert for
//    sidecar fidelity.
// 2. **Uniforms per-run via setBytes** (D2): the homography needs the
//    bufIn size (`_homography` center/focal terms) only known at process
//    time — FlipModule setBytes precedent. `piece.data = nil`.
// 3. **Bilinear border: clamp taps, transparent outside** (D4): dt's
//    border lives behind the interpolation dispatch; the Swift↔Python
//    synthesized pair pins this semantic.
// 4. **Neutral/pathological → blit identity** (D5): dt sets
//    `piece->enabled = FALSE`; the pipe owns enablement here — the
//    module renders identity + logs, never crashes.
// ─────────────────────────────────────────────────────────────────────────

/// Kernel-name + bundle-anchor convenience (the `PassthroughKernel` pattern).
public enum AshiftKernel {
    public static let functionName = "ashift_warp"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class AshiftModule: IOPModule {

    /// dt `dt_iop_ashift_params_t` GENERIC subset (`ashift.c:272-291`,
    /// minus the SPECIFIC/GUI-fit tail — DECISIONS D1). `cl/cr/ct/cb` are
    /// the inner crop edges (dt defaults 0/1/0/1 = full frame, kept as a
    /// user shortcut; the black-corner收敛 itself stays crop's job).
    public struct Params: Codable, Hashable, Sendable {
        /// Rotation in degrees, ±45 UI range (dt ROTATION_RANGE_SOFT=180
        /// hard, ±10 default; Lightamer panel clamps ±45 — Must-have).
        public var rotation: Float
        /// dt `lensshift_v` (exp-shift units).
        public var lensShiftV: Float
        /// dt `lensshift_h` (exp-shift units).
        public var lensShiftH: Float
        /// dt `shear`.
        public var shear: Float
        /// dt `f_length` (mm); GENERIC folds ×1 (kept for sidecar fidelity).
        public var fLength: Float
        /// dt `crop_factor`; GENERIC folds ×1 (kept for sidecar fidelity).
        public var cropFactor: Float
        public var cl: Float
        public var cr: Float
        public var ct: Float
        public var cb: Float

        public init(
            rotation: Float = 0,
            lensShiftV: Float = 0,
            lensShiftH: Float = 0,
            shear: Float = 0,
            fLength: Float = 28,
            cropFactor: Float = 1,
            cl: Float = 0,
            cr: Float = 1,
            ct: Float = 0,
            cb: Float = 1
        ) {
            self.rotation = rotation
            self.lensShiftV = lensShiftV
            self.lensShiftH = lensShiftH
            self.shear = shear
            self.fLength = fLength
            self.cropFactor = cropFactor
            self.cl = cl
            self.cr = cr
            self.ct = ct
            self.cb = cb
        }

        /// The neutral full-frame identity (cache-neutral seed).
        public static let neutral = Params()
    }

    public static let opName = "ashift"

    /// Darktable v50 order slot 15.0 — after hazeremoval (14.0), before
    /// flip (16.0) (`iop_order.c:319`; 04-03 task-book constraint:
    /// rotate sits before crop).
    public static let iopOrder: Float = 15.0

    /// dt flags subset (`ashift.c:131-136`): tiling-eligible, single-
    /// instance, fast-pipe member. (No `supportsBlending` — geometric.)
    public static let flags: IOPFlags = [.allowTiling, .oneInstance, .allowFastPipe]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// dt `_isneutral` eps (`:990`).
    static let neutralEps: Float = 1e-4

    /// The committed working copy (dt `piece->data` analog — the
    /// geometry the ROI hooks read; hooks receive `piece`, not params).
    /// Owned by the box's isolation domain (CropModule precedent).
    /// GOTCHA (04-02-T3): `ModuleBox.setParams` is the ONLY commit path.
    private var committed: Params = Params()

    public init() {}

    /// Neutral seed (ashift is dt-disabled by default — `reload_defaults`
    /// sets `default_enabled = FALSE`; the Lightamer seed carries the
    /// ENABLED neutral identity exposure-0EV-style so the panel has an
    /// instance to drive — DECISIONS D6 — while staying cache-neutral).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params` GENERIC fold (`:5600-5605`) + neutral predicate
    /// (`_isneutral`); parks the working copy, hashes the RAW params
    /// (D-H4). No uniforms buffer (D2 — per-run setBytes, needs bufIn).
    public func commitParams(_ params: Params, into piece: inout IOPiece) async {
        committed = params
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    /// The GENERIC-folded focal length (dt `:5600-5602` verbatim).
    private var fLengthKB: Double { 28.0 }

    /// dt `_isneutral` (`:985-999`) over the live subset: rotation, both
    /// shifts, shear, aspect≡1, clip≡full-frame. `internal` for parity tests.
    func isNeutral(_ p: Params) -> Bool {
        let e = Double(Self.neutralEps)
        return abs(Double(p.rotation)) < e
            && abs(Double(p.lensShiftV)) < e
            && abs(Double(p.lensShiftH)) < e
            && abs(Double(p.shear)) < e
            && abs(Double(p.cl)) < e
            && abs(Double(p.cr) - 1.0) < e
            && abs(Double(p.ct)) < e
            && abs(Double(p.cb) - 1.0) < e
    }

    /// Forward matrix at the bufIn plane size (dt `:1154-1157`: forward
    /// over `piece->buf_in`). `internal` for the parity tests' hand checks.
    func forwardMatrix(bufW: Int, bufH: Int) -> Mat3D {
        Homography.compose(
            rotationDegrees: Double(committed.rotation),
            shiftV: Double(committed.lensShiftV),
            shiftH: Double(committed.lensShiftH),
            shear: Double(committed.shear),
            fLengthKB: fLengthKB,
            width: Double(bufW), height: Double(bufH))
    }

    /// Inverse matrix (dt `:1225-1228` / `:3660-3663`); identity fallback
    /// on singularity (dt `:970-977` unity on `mat3inv` error).
    func inverseMatrix(bufW: Int, bufH: Int) -> Mat3D {
        forwardMatrix(bufW: bufW, bufH: bufH).inverted() ?? .identity
    }

    /// Full-output span of the bufIn rect through the forward matrix
    /// (plane pixels) — feeds the clip-offset fullwidth (dt `:1234-1235`
    /// / `:3666-3667`: `fullwidth = buf_out.w / (cr − cl)`; buf_out IS
    /// this AABB floored × clip, so fullwidth recovers as span pre-clip).
    func fullOutputSpan(bufW: Int, bufH: Int) -> (w: Double, h: Double) {
        let fwd = forwardMatrix(bufW: bufW, bufH: bufH)
        var xm = Double.greatestFiniteMagnitude, ym = Double.greatestFiniteMagnitude
        var xM = -Double.greatestFiniteMagnitude, yM = -Double.greatestFiniteMagnitude
        for (x, y) in [
            (0.0, 0.0), (Double(bufW), 0.0),
            (0.0, Double(bufH)), (Double(bufW), Double(bufH)),
        ] {
            let q = fwd.project(x, y)
            xm = min(xm, q.x); xM = max(xM, q.x)
            ym = min(ym, q.y); yM = max(yM, q.y)
        }
        let span = max(Double(committed.cr - committed.cl), 1e-6)
        let spanY = max(Double(committed.cb - committed.ct), 1e-6)
        // buf_out.w = floor(span·clipfrac) → fullwidth = buf_out.w/clipfrac.
        return (floor((xM - xm) * span) / span, floor((yM - ym) * spanY) / spanY)
    }

    /// dt `modify_roi_out` (`:1142-1211`): `*roi_out = *roi_in` (origin
    /// preserved — the L020 frame convention), then the four INPUT-FRAME
    /// corners through the FORWARD matrix → AABB × inner clip → floor
    /// (`:1190-1194`). Neutral or pathological (<4px, dt `:1196-1210`)
    /// → keep input (identity; the process leg blits — D5).
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        if isNeutral(committed) { roi = input; return }
        let h = forwardMatrix(bufW: piece.dscIn.width, bufH: piece.dscIn.height)
        let corners = [
            (Double(input.x), Double(input.y)),
            (Double(input.x + input.width), Double(input.y)),
            (Double(input.x), Double(input.y + input.height)),
            (Double(input.x + input.width), Double(input.y + input.height)),
        ]
        var xm = Double.greatestFiniteMagnitude, ym = Double.greatestFiniteMagnitude
        var xM = -Double.greatestFiniteMagnitude, yM = -Double.greatestFiniteMagnitude
        for (x, y) in corners {
            let q = h.project(x, y)
            xm = min(xm, q.x); xM = max(xM, q.x)
            ym = min(ym, q.y); yM = max(yM, q.y)
        }
        // dt `:1190-1191`: span × clip fraction → floor. (dt's +1 is the
        // inclusive-corner span of its integer-corner loop; the corner-
        // exact AABB here folds it into the floor.)
        let w = floor((xM - xm) * Double(committed.cr - committed.cl))
        let hh = floor((yM - ym) * Double(committed.cb - committed.ct))
        guard w >= 4, hh >= 4 else {
            AppError.logger.warning(
                "ashift modifyROIOut pathological (<4px) — rendering identity")
            roi = input
            return
        }
        roi = input
        roi.width = Int(w)
        roi.height = Int(hh)
    }
    /// dt `modify_roi_in` (`:1213-1285`) under OUR walk's frame convention
    /// (L020): the incoming `roi` already carries output-FRAME coords, so
    /// the four corners go through the INVERSE matrix with the clip offset
    /// added (dt `:1249-1250` `roi_out->x + x + cx`) straight into the
    /// INPUT frame (dt `:1261-1262`, no buf_in re-add) → AABB + 2×
    /// interpolation margin (dt `:1272-1277`, `iw1` = bilinear 1 tap) →
    /// clamp to bufIn (dt `:1281-1284`). Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        if isNeutral(committed) { input = roi; return }
        let bufW = Double(piece.dscIn.width), bufH = Double(piece.dscIn.height)
        let h = inverseMatrix(bufW: piece.dscIn.width, bufH: piece.dscIn.height)
        // Clip offset in output pixels (dt `:1236-1237` `cx = scale·full·cl`;
        // scale folds to 1 — all coords are plane pixels here).
        let full = fullOutputSpan(bufW: piece.dscIn.width, bufH: piece.dscIn.height)
        let cx = full.w * Double(committed.cl)
        let cy = full.h * Double(committed.ct)
        let corners = [
            (Double(roi.x) + cx, Double(roi.y) + cy),
            (Double(roi.x + roi.width) + cx, Double(roi.y) + cy),
            (Double(roi.x) + cx, Double(roi.y + roi.height) + cy),
            (Double(roi.x + roi.width) + cx, Double(roi.y + roi.height) + cy),
        ]
        var xm = Double.greatestFiniteMagnitude, ym = Double.greatestFiniteMagnitude
        var xM = -Double.greatestFiniteMagnitude, yM = -Double.greatestFiniteMagnitude
        for (x, y) in corners {
            let q = h.project(x, y)
            xm = min(xm, q.x); xM = max(xM, q.x)
            ym = min(ym, q.y); yM = max(yM, q.y)
        }
        // dt `:1272-1277`: 2× the interpolation width (bilinear tap = 1).
        let iw1 = 1.0, iw2 = 2.0
        var ix = xm - iw1, iy = ym - iw1
        var iw = xM + iw2 - xm + 1.0, ih = yM + iw2 - ym + 1.0
        // dt `:1281-1284` clamp to bufIn.
        ix = min(max(ix, 0), floor(bufW))
        iy = min(max(iy, 0), floor(bufH))
        iw = min(max(iw, 4), floor(bufW) - ix)
        ih = min(max(ih, 4), floor(bufH) - iy)
        input = ROI(x: Int(ix.rounded(.down)), y: Int(iy.rounded(.down)),
                    width: Int(iw.rounded(.down)), height: Int(ih.rounded(.down)),
                    scale: roi.scale)
    }

    /// dt CPU/CL legs (`:3522-3566` / `:3659-3703`): neutral or
    /// pathological → blit identity (D5; dt's `_isneutral` copy short-
    /// circuit `:3651-3657` + the disable-piece path). Else single-pass
    /// `ashift_warp` over the OUTPUT plane (dt dispatches over roi_out).
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
        // The forward hook doubles as the pathological detector (same <4px
        // gate — one predicate, no second math).
        var probe = ROI()
        modifyROIOut(&probe, input: ROI(x: 0, y: 0, width: piece.dscIn.width,
                                        height: piece.dscIn.height, scale: roiOut.scale),
                     piece: piece)
        if probe.width < 4 || probe.height < 4 {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let h = inverseMatrix(bufW: piece.dscIn.width, bufH: piece.dscIn.height)
        // Clip offset in output pixels at run size (dt CL `:3666-3669`:
        // fullwidth = buf_out.w / (cr − cl); cx = scale·fullwidth·cl).
        let full = fullOutputSpan(bufW: piece.dscIn.width, bufH: piece.dscIn.height)
        let cx = Float(full.w * Double(committed.cl))
        let cy = Float(full.h * Double(committed.ct))
        var uniforms = AshiftWarpUniforms(
            hinv: h,
            oroiX: Int32(roiOut.x), oroiY: Int32(roiOut.y),
            clipX: cx, clipY: cy,
            iroiX: Int32(roiIn.x), iroiY: Int32(roiIn.y),
            inW: Int32(input.width), inH: Int32(input.height))
        // Upload through a shared MTLBuffer (NOT setBytes: the 80-byte
        // struct exceeds the single-digit setBytes path the small-uniform
        // modules use, and a stack-addressed setBytes upload raced the
        // async-committed encoder on this host — diagnosed 2026-09-20
        // when every warp pixel read back pre-dispatch zeros).
        guard let buffer = metal.device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<AshiftWarpUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        try await metal.dispatch2DTexture(
            functionName: AshiftKernel.functionName,
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

/// Swift mirror of the MSL `AshiftWarpUniforms` struct — three float4 ROWS
/// (dt row-major `math.h` order in xyz, 16-byte rows) + int2 + float2 +
/// int2 + int2 = 80 bytes. Every member is 4/8/16-byte aligned on both
/// sides — the scalar-array packing question is designed out (the
/// all-transparent warp postmortem: a `float hinv[9]` constant array may
/// stride 16 on the MSL side while Swift packs 4, silently shifting every
/// field after it).
struct AshiftWarpUniforms {
    var hrow0: SIMD4<Float>
    var hrow1: SIMD4<Float>
    var hrow2: SIMD4<Float>
    var oroi: SIMD2<Int32>
    var clip: SIMD2<Float>
    var iroi: SIMD2<Int32>
    var inSize: SIMD2<Int32>

    init(hinv h: Mat3D,
         oroiX: Int32, oroiY: Int32, clipX: Float, clipY: Float,
         iroiX: Int32, iroiY: Int32, inW: Int32, inH: Int32) {
        self.hrow0 = SIMD4(Float(h[0, 0]), Float(h[0, 1]), Float(h[0, 2]), 0)
        self.hrow1 = SIMD4(Float(h[1, 0]), Float(h[1, 1]), Float(h[1, 2]), 0)
        self.hrow2 = SIMD4(Float(h[2, 0]), Float(h[2, 1]), Float(h[2, 2]), 0)
        self.oroi = SIMD2(oroiX, oroiY)
        self.clip = SIMD2(clipX, clipY)
        self.iroi = SIMD2(iroiX, iroiY)
        self.inSize = SIMD2(inW, inH)
    }
}
