import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// FLIP — orientation (Plan 04-02-T2, IOP-GEO-04).
//
// Darktable reference: `src/iop/flip.c` (tree dc58cf0ba1) +
// `src/common/image.h:134-150` (orientation bits) +
// `data/kernels/basic.cl:2933-2967` (`flip` kernel).
//   - params v2     :44-47   a single `orientation` int (dt bits)
//   - flags         :91-95   ONE_INSTANCE + UNSAFE_COPY (+ tiling/GUIDES
//                            bits unported — Lightamer has no tiling flags
//                            / guides widget seams)
//   - modify_roi_out:299-313 identity + W/H swap under SWAP_XY
//   - modify_roi_in :315-350 corner backtransform (`backtransform`
//                            :183-212) → tight AABB
//   - process       :354-370 / process_cl :372-391 `dt_imageio_flip_buffers`
//                            / the `flip` kernel (`ox = FLIP_X ? w−x−1`,
//                            `oy = FLIP_Y ? h−y−1`, then XY swap)
//   - commit_params :410-425 ORIENTATION_NULL → EXIF orientation,
//                            NONE disables the piece
//   - reload_defaults:479-508 ORIENTATION_NULL default (auto)
//   - v50 slot 16.0, AFTER ashift (15.0), BEFORE crop (24.5)
//     (`iop_order.c:810-812` — "crop GUI broken if flip is done on top").
//
// The 8 states are dt's 3-bit field, enumerated verbatim:
// none(0) / flipV(1) / flipH(2) / rot180(3) / transpose(4) / rotCW90(5) /
// rotCCW90(6) / transverse(7). CCW90 = "rotate 90°" in dt's GUI wording
// (image.h:147); CW90 = "rotate -90°" (image.h:148) — the swizzle below
// follows the KERNEL order (flip-then-swap), not the distort order.
//
// Pure index remap, zero sampling — parity <1e-6 reachable (RESEARCH §2.3).
// The kernel dispatches over the INPUT plane (dt `process_cl` shape:
// `width/height` = roi_in as the grid): gid is the READ coord, the write
// coord is computed. Same-size states keep the dt fast path shape without
// a branch.
//
// INTENTIONAL DIVERGENCES:
// 1. **`.auto` resolves at `reloadDefaults`, not at commit.** dt keeps
//    NULL in params and resolves per-run against the image (`:418-419`);
//    here the EXIF seed bakes into the RECORD at defaults time, so params
//    stay self-describing across the pipe boundary (`commitParams` never
//    sees the image). A persisted/hand-built `.auto` falls back to
//    identity — future load-path wiring may resolve it, never silently
//    wrong.
// 2. **NONE never disables the piece.** dt sets `piece->enabled = FALSE`
//    (`:423-424`); the Lightamer pipe owns enablement (history records),
//    a module must not mutate it — NONE processes as identity.
// 3. **`reloadDefaults` has no legacy-flip path.** dt merges pre-v2
//    `legacy_flip` bits when the history lacks a flip entry (`:487-507`);
//    Lightamer has no legacy history — EXIF orientation is the only seed.
// ─────────────────────────────────────────────────────────────────────────

/// Kernel-name + EXIF-map convenience (the `PassthroughKernel` pattern).
public enum FlipKernel {
    /// MSL function name of the remap kernel (`FlipKernels.metal`).
    public static let functionName = "flip_apply"

    /// The LightamerIOP framework bundle anchor.
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

/// dt `dt_image_orientation_t` (`image.h:134-150`), raw values aligned for
/// XMP/blob fidelity. `.auto` = ORIENTATION_NULL (−1, "autodetect").
public enum FlipOrientation: Int, Codable, Hashable, Sendable, CaseIterable {
    /// ORIENTATION_NONE (0) — identity.
    case none = 0
    /// ORIENTATION_FLIP_VERTICALLY = FLIP_Y (1).
    case flipV = 1
    /// ORIENTATION_FLIP_HORIZONTALLY = FLIP_X (2).
    case flipH = 2
    /// ORIENTATION_ROTATE_180_DEG = FLIP_Y|FLIP_X (3).
    case rot180 = 3
    /// ORIENTATION_TRANSPOSE = SWAP_XY (4).
    case transpose = 4
    /// ORIENTATION_ROTATE_CW_90_DEG = FLIP_Y|SWAP_XY (5, "rotate −90°").
    case rotCW90 = 5
    /// ORIENTATION_ROTATE_CCW_90_DEG = FLIP_X|SWAP_XY (6, "rotate 90°").
    case rotCCW90 = 6
    /// ORIENTATION_TRANSVERSE = FLIP_Y|FLIP_X|SWAP_XY (7).
    case transverse = 7
    /// ORIENTATION_NULL (−1, "autodetect" — dt `reload_defaults` default).
    case auto = -1

    /// The dt bit field (`image.h:137-140`): bit0 = FLIP_Y, bit1 = FLIP_X,
    /// bit2 = SWAP_XY. `.auto` resolves through EXIF first (never hashed
    /// into a bit — `resolved(forEXIF:)`); as a raw fallback it is NONE.
    public var bits: Int {
        switch self {
        case .auto: return 0
        default: return rawValue
        }
    }

    /// True for the 90°-step states (dt `& ORIENTATION_SWAP_XY`).
    public var swapsXY: Bool { (bits & 0b100) != 0 }

    /// Resolve `.auto` against an EXIF orientation 1...8 (dt
    /// `dt_image_orientation_to_flip_bits`, `image.h:541-564`); unknown or
    /// missing EXIF ⇒ `.none`. Non-auto passes through untouched.
    public static func resolved(_ orientation: FlipOrientation, forEXIF exif: Int?) -> FlipOrientation {
        guard orientation == .auto else { return orientation }
        switch exif {
        case 1: return .none
        case 2: return .flipH
        case 3: return .rot180
        case 4: return .flipV
        case 5: return .transpose
        case 6: return .rotCW90
        case 7: return .transverse
        case 8: return .rotCCW90
        default: return .none
        }
    }

    /// The OUTPUT pixel read from an INPUT coord — the CPU mirror of the
    /// `flip_apply` kernel's forward map (dt `basic.cl:2948-2960` port:
    /// flip X/Y first, then swap). `w/h` are the INPUT plane dims.
    public static func outputXY(
        x: Int, y: Int, w: Int, h: Int, orientation: FlipOrientation
    ) -> (x: Int, y: Int) {
        let bits = orientation.bits
        var ox = (bits & 0b010) != 0 ? w - x - 1 : x
        var oy = (bits & 0b001) != 0 ? h - y - 1 : y
        if (bits & 0b100) != 0 { swap(&ox, &oy) }
        return (ox, oy)
    }

    /// The INPUT coord an OUTPUT pixel reads — the backward map (dt
    /// `backtransform`, `flip.c:183-212` verbatim: swap the output coord
    /// AND the dims together (`:189-196`), then flip (`:203-211`). The
    /// dims that arrive here are the OUTPUT dims (ow, oh) — the swap
    /// turns them into the input dims for the flip bounds. `modifyROIIn`
    /// and the GPU-parity test feed output corners/coords with output
    /// dims; the CPU round-trip feeds forward outputs the same way.
    public static func inputXY(
        x: Int, y: Int, ow: Int, oh: Int, orientation: FlipOrientation
    ) -> (x: Int, y: Int) {
        let bits = orientation.bits
        var ox = x, oy = y
        var w = ow, h = oh
        if (bits & 0b100) != 0 {
            swap(&ox, &oy)
            swap(&w, &h)
        }
        if (bits & 0b010) != 0 { ox = w - ox - 1 }
        if (bits & 0b001) != 0 { oy = h - oy - 1 }
        return (ox, oy)
    }
}

public final class FlipModule: IOPModule {

    /// dt `dt_iop_flip_params_t` v2 mirror (`flip.c:44-47`): one
    /// orientation. Default `.auto` = dt's `reload_defaults` seed.
    public struct Params: Codable, Hashable, Sendable {
        public var orientation: FlipOrientation
        public init(orientation: FlipOrientation = .auto) {
            self.orientation = orientation
        }
    }

    public static let opName = "flip"

    /// Darktable v50 order slot 16.0 — after ashift (15.0), before crop
    /// (24.5). `iop_order.c:810-812` hard constraint; the default chain
    /// satisfies it structurally (V50OrderTests pins it).
    public static let iopOrder: Float = 16.0

    /// dt flags subset (`flip.c:91-95`): single-instance. (No
    /// `supportsBlending` — geometric, not pixel.)
    public static let flags: IOPFlags = [.oneInstance]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// The commit-resolved orientation (divergence #1/#2: `.auto` →
    /// identity fallback; reloadDefaults bakes the EXIF seed into the
    /// record so params stay self-describing). Owned by the box's
    /// isolation domain (TestGain precedent).
    private var committed: FlipOrientation = .none

    public init() {}

    /// dt `reload_defaults` (`:479-483`): autodetect — resolved HERE
    /// against the EXIF orientation (divergence #3 — no legacy-flip
    /// merge; EXIF is the only seed). Unknown/missing EXIF gives none.
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params(orientation: FlipOrientation.resolved(.auto, forEXIF: image.capture.orientation))
    }

    /// dt `commit_params` (`:410-424`, minus the piece-disable): the
    /// params value IS the state (reloadDefaults already resolved
    /// `.auto`); a persisted `.auto` falls back to identity — pipe-time
    /// EXIF resolution for hand-built records is future load-path wiring,
    /// not silent wrongness. Hashes the RAW params (D-H4).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = params.orientation == .auto ? .none : params.orientation
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil // orientation rides a setBytes uniform, not a buffer
    }

    /// dt `modify_roi_out` (`:299-313`): identity + W/H swap under SWAP_XY.
    /// ROI 帧约定（L020/L021）：纯几何 swap，不读 `piece.dscIn`，无 scale
    /// 换算（审计结论见 05-01-DECISIONS.md D-05-01-T1）。
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
        if committed.swapsXY {
            roi.width = input.height
            roi.height = input.width
        }
    }
    /// dt `modify_roi_in` (`:315-350`) verbatim: `backtransform` the four
    /// output corners against the FORWARD output size (`:338-339` —
    /// `buf_out × scale` = 全分辨率输出 × 管线缩放 = 本 run 平面像素) →
    /// tight AABB. Flips alone keep `(x, y, w, h)`; swaps exchange them
    /// exactly (no ±1 slop — the `:324-349` inclusive-point bookkeeping nets
    /// to the same rect).
    ///
    /// ROI 帧约定（L020/L021）：`piece.dscIn` = 本 run 平面像素（PixelPipe.run
    /// 按 bufInROI 逐级 stamp，已含 entry 缩放），禁止再 ×`roi.scale`
    /// （04-06 crop D-GUI-1 double-scale 教训——760 档曾坍缩 60×40）。
    /// dt 的 `buf_out × scale` 换算到本管线就是 swapped(dscIn) 直用。
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        // buf_out = the forward output at this level = levelROI. The
        // forward walk runs before any backward call, so dscIn at THIS
        // level still holds the FORWARD INPUT size (entry-scaled plane
        // pixels); the output size is input ± the swap. Recompute exactly
        // like modifyROIOut — NO ×scale (dscIn 已含缩放).
        var fwd = piece.dscIn
        if committed.swapsXY { swap(&fwd.width, &fwd.height) }
        let bw = fwd.width
        let bh = fwd.height
        let corners = [
            (roi.x, roi.y),
            (roi.x + roi.width - 1, roi.y),
            (roi.x, roi.y + roi.height - 1),
            (roi.x + roi.width - 1, roi.y + roi.height - 1),
        ]
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for (cx, cy) in corners {
            let back = FlipOrientation.inputXY(
                x: cx, y: cy, ow: bw, oh: bh, orientation: committed)
            minX = min(minX, back.x); minY = min(minY, back.y)
            maxX = max(maxX, back.x); maxY = max(maxY, back.y)
        }
        input = ROI(
            x: minX, y: minY,
            width: max(1, maxX - minX + 1), height: max(1, maxY - minY + 1),
            scale: roi.scale)
    }

    /// dt `process_cl` (`:372-391`): dispatch over the INPUT plane
    /// (`width/height` = roi_in as the grid); each thread reads
    /// `in[gid]` and writes `out[remap(gid)]`. `dispatch2DTexture` is
    /// WRONG here — it spans the output plane, which for SWAP_XY states
    /// is transposed (reads would run out of bounds). The low-level
    /// `makeEncoder` session spans the input dims instead (D-19).
    /// The kernel takes the orientation bits + input dims as uniforms
    /// (dt passes `width/height` + `owidth/oheight` + `orientation`).
    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        var uniforms = FlipUniforms(
            orientation: Int32(committed.bits),
            inWidth: Int32(input.width),
            inHeight: Int32(input.height))
        let session = try await metal.makeEncoder(functionName: FlipKernel.functionName)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        session.encoder.setBytes(
            &uniforms,
            length: MemoryLayout<FlipUniforms>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }
}

/// Swift mirror of the MSL `FlipUniforms` struct — 16-byte stride
/// (orientation + inWidth + inHeight + padding).
struct FlipUniforms {
    var orientation: Int32
    var inWidth: Int32
    var inHeight: Int32
    private var _pad: Int32 = 0
}
