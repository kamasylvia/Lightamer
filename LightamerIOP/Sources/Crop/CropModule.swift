import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// CROP — the framing window (Plan 04-02-T1, IOP-GEO-01).
//
// Darktable reference: `src/iop/crop.c` (tree dc58cf0ba1)
//   - params v3     :61-69   cx/cy/cw/ch fractions + ratio_n/ratio_d
//   - MIN_CROP_SIZE :44      0.01 (fraction) / 4px floor
//   - modify_roi_out:517-531 fraction → px, `MAX(4, …)` width floor
//   - modify_roi_in :576-592 offset add-back + clamp to bufIn
//   - process       :594-608 `dt_iop_copy_image_roi` (fast path: same-size
//                            memcpy — `imagebuf.c:188-223`)
//   - commit_params :617-656 CLAMP + ratio → aspect derivation
//   - flags         :145-150 ALLOW_TILING | TILING_FULL_ROI | ONE_INSTANCE |
//                            ALLOW_FAST_PIPE (+ GUI-only bits, unported)
//   - v50 slot 24.5 (`iop_order.c`): after toneequal (24.0, "last module
//     that need enlarged roi_in") — ROI negotiation IS that comment.
//
// Lightamer mapping (RESEARCH §2.1):
// - Fraction params are resolution-blind: PREVIEW/FULL ladders agree with
//   zero module awareness (the forward walk multiplies by the level size).
// - `process` is the dt fast path — negotiated windows are same-size by
//   construction (commit clamps params into [0,1]), so the whole plane
//   blits origin-to-origin. No export-pipe ratio aligner (`:533-560`):
//   Phase 11 EXP-03 owns it; `ratioN/ratioD` ride along inert until then
//   (the overlay enforces the ratio at EDIT time instead).
// - The blit runs on its own command buffer (same-queue FIFO keeps it
//   ordered; explicit endEncoding before commit — L008). There is no
//   `.metal` file for this module: the copy is a blit, not a kernel.
//
// INTENTIONAL DIVERGENCES:
// 1. **Hash covers the RAW params, geometry uses the CLAMPED params.**
//    dt clamps into `d` (the data) while `p` (the params) keep user
//    values. Mirrored here: `committed` is the clamped working copy,
//    `piece.paramsHash` digests the raw params — so record hashes
//    (ModuleInstance) and box hashes can never diverge (D-H4).
// 2. **No `aspect` derivation at commit.** dt folds ratio → aspect for the
//    export aligner; without the aligner the derivation has no consumer.
//    The bits round-trip for Phase 11.
// 3. **`reloadDefaults` returns full-frame.** dt seeds from `usercrop`
//    (fresh images: full frame) — same value, minus the dev-image lookup.
// ─────────────────────────────────────────────────────────────────────────

/// dt `ORIENTATION_*` bits are flip's; crop's only constant is the minimum
/// window (`crop.c:44`).
public enum CropLimits {
    /// Minimum crop width/height as a fraction of the plane (`MIN_CROP_SIZE`).
    public static let minFraction: Float = 0.01
    /// Minimum crop width/height in pixels (`MAX(4, …)` floor, `:532-533`).
    public static let minPixels = 4
}

public final class CropModule: IOPModule {

    /// dt `dt_iop_crop_params_t` v3 mirror (`crop.c:61-69`). Fractions of
    /// the upstream plane; `left/top` = the window origin (dt cx/cy),
    /// `right/bottom` = the absolute right/bottom EDGES (dt cw/ch — crop.c
    /// stores edges, not size; `modify_roi_out` derives `cw − cx`). Full
    /// frame = 0/0/1/1. `ratioN/ratioD` = the pinned aspect preset
    /// (-1/-1 = freehand; (0,0) legacy free; (1,0) original-image) —
    /// inert until the Phase-11 export aligner (EXP-03).
    public struct Params: Codable, Hashable, Sendable {
        public var left: Float
        public var top: Float
        public var right: Float
        public var bottom: Float
        public var ratioN: Int
        public var ratioD: Int

        public init(
            left: Float = 0,
            top: Float = 0,
            right: Float = 1,
            bottom: Float = 1,
            ratioN: Int = -1,
            ratioD: Int = -1
        ) {
            self.left = left
            self.top = top
            self.right = right
            self.bottom = bottom
            self.ratioN = ratioN
            self.ratioD = ratioD
        }

        /// The neutral full-frame window (cache-neutral seed identity).
        public static let fullFrame = Params()
    }

    public static let opName = "crop"

    /// Darktable v50 order slot 24.5 — after every module that may widen
    /// `roi_in` (toneequal 24.0), before graduatednd (25.0).
    public static let iopOrder: Float = 24.5

    /// dt flags subset (`crop.c:145-150`): tiling-eligible, single-instance,
    /// fast-pipe member. (No `supportsBlending` — geometric, not pixel.)
    public static let flags: IOPFlags = [.allowTiling, .oneInstance, .allowFastPipe]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// The commit-clamped working copy (dt `piece->data` analog — the
    /// geometry the ROI hooks read; hooks receive `piece`, not params).
    /// Owned by the box's isolation domain (TestGain `committedGain`
    /// precedent — single-owner, never cross-task). GOTCHA (04-02-T3):
    /// `ModuleBox.setParams` is the ONLY commit path — a directly
    /// constructed module never receives `commitParams` until the box
    /// commits, so its hooks read the full-frame default. Tests drive
    /// boxes (registry-made or `ModuleBox(module:)` + `setParams`).
    private var committed: Params = Params()

    public init() {}

    /// Fresh images frame the whole shot (dt `reload_defaults` reads
    /// `usercrop`, which is full-frame until the user crops).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params` (`:635-654`): clamp fractions into range, park
    /// the working copy, hash the RAW params (divergence #1 — D-H4).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = Self.clamp(params)
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil // window copy needs no uniforms
    }

    /// dt `commit_params` CLAMP half (`:635-638`): cx/cy ∈ [0, 1−MIN],
    /// cw/ch ∈ [MIN, 1]. `internal` for the parity tests' clamp vectors.
    static func clamp(_ params: Params) -> Params {
        let m = CropLimits.minFraction
        var out = params
        out.left = min(max(params.left, 0), 1 - m)
        out.top = min(max(params.top, 0), 1 - m)
        out.right = min(max(params.right, m), 1)
        out.bottom = min(max(params.bottom, m), 1)
        return out
    }

    /// dt `modify_roi_out` (`:522-533`, minus the Phase-11 export aligner):
    /// `*roi_out = *roi_in`, then RELATIVE offsets — x/y do NOT add the
    /// input origin (04-01 CropStub alignment fix).
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        let c = committed
        roi = input
        roi.x = max(0, Int(Float(input.width) * c.left))
        roi.y = max(0, Int(Float(input.height) * c.top))
        roi.width = max(
            CropLimits.minPixels, Int(Float(input.width) * (c.right - c.left)))
        roi.height = max(
            CropLimits.minPixels, Int(Float(input.height) * (c.bottom - c.top)))
    }

    /// dt `modify_roi_in` (`:576-592`) under OUR walk's frame convention.
    /// dt's backward walk hands `roi_out` window-RELATIVE (origin at the
    /// window corner) so its `+= buf_in·cx` re-add is correct there; our
    /// backward walk seeds from the FORWARD result, where `modifyROIOut`
    /// already recorded the window origin in upstream coords (`roi.x =
    /// input.width·left`, dt get_dimensions `buf_out` semantics) and the
    /// recursion renders the negotiated window origin-to-origin. Re-adding
    /// the origin here double-offsets the window (golden parity caught it:
    /// the pipe read the [0.75..1] corner instead of [0.25..0.75]). So:
    /// KEEP `roi` verbatim (its xy IS the crop origin upstream), clamp
    /// into the upstream plane (`piece.dscIn`, dt `buf_in`). Partial
    /// downstream requests (frame re-basing per geometry boundary) are
    /// 04-03's protocol work — the exercised path is full-window.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
        // 04-06 D-GUI-1: `dscIn` is ALREADY the entry-scaled plane extent
        // (PixelPipe.run stamps bufInROI per level — 760×507 at the 760
        // bucket, scale 0.08). Multiplying by `roi.scale` AGAIN collapsed
        // every scale<1 full-frame clamp to 60×40 → negotiated roiIn 60×40
        // → process blitted 60×40 origin-to-origin into the 760×507 plane,
        // rest zeros (GUI-1 near-black, only the TL corner lit — the blit's
        // vertical flip puts it bottom-left on screen). Scale 1.0 masked
        // it (×1.0 identity), which is why all golden/crop tests stayed
        // green. Clamp straight to dscIn (same-run plane pixels).
        let iw = Double(piece.dscIn.width)
        let ih = Double(piece.dscIn.height)
        input.x = min(max(input.x, 0), Int(iw.rounded(.down)))
        input.y = min(max(input.y, 0), Int(ih.rounded(.down)))
        input.width = min(input.width, max(1, Int(iw.rounded(.down)) - input.x))
        input.height = min(input.height, max(1, Int(ih.rounded(.down)) - input.y))
    }

    /// dt `process` (`:594-602`) = the `copy_image_roi` WINDOW path
    /// (`imagebuf.c:188-223`). The pipe hands `input` ALREADY extracted to
    /// the negotiated window (roiIn-sized, origin-to-origin — the
    /// recursion rendered it), so for the full-window path
    /// `roiIn.xy == roiOut.xy` and the blit is origin-to-origin (dt fast
    /// path: same-size whole-buffer copy). The residual offset uses dt's
    /// `copy_image_roi` sign (`dx = roi_out − roi_in`, `imagebuf.c:194`)
    /// for any negotiated case where the two disagree. Product is an
    /// INDEPENDENT plane (never alias upstream — FULL ping-pong scratch
    /// reuses it; cache semantics demand an owned product). Encoder
    /// failure throws (L008: no silent planes).
    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
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
