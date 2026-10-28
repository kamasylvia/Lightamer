import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// UPRIGHT — Guided Upright perspective correction (Plan M9-3-T2, M9GEO-02).
//
// A NEW op (v50 slot 15.5 — after ashift 15.0, before flip 16.0; the
// add-only V50Order discipline, filmPlacement 20.8 precedent) that solves
// and applies the user-drawn-guide perspective correction. The VANISHING-
// POINT MATH lives in Core (`UprightMath`, Plan M9-3-T1, lightcraft MIT
// port); this module is the pipe citizen around it.
//
// STRUCTURE TEMPLATE: AshiftModule (the dt GENERIC warp citizen). Zero
// new kernels: the process leg RIDES the existing generic backward
// homography warp `ashift_warp` (AshiftKernels.metal:79 — uniforms three
// float4 rows + pixel centers + clamp-edge bilinear taps + transparent
// outside), dispatched through the SAME function-name constant
// (`AshiftModule.swift:73` string-constant shape; the Registry PSO list
// already warms the name — "perspective share one kernel" precedent,
// Registry.swift:517). AshiftKernels.metal itself is ZERO-DIFF.
//
// COORDINATE SYSTEM (CONTEXT red line 6): guides persist in the op's
// INPUT-FRAME normalized 0..1 coordinates (lens → flip is BEFORE ashift
// 15.0, so the upright input frame = post-ashift too; the viewport ⇄
// this frame mapping rides GeometryPointMapper's `.homography` segment —
// the ONLY mapping channel, no second mapping point). The solve runs in
// the centred-normalized domain (UprightMath), then is rescaled to plane
// pixels for the kernel (D_out · H_centred · D_in⁻¹, Double math,
// Float32 uniforms — the ashift compose same-position conversion).
//
// PERSISTENCE: `Params` rides the existing per-instance `paramsData`
// base64 encoding (M2-1 colormatch "Params direct-store" precedent) —
// ZERO sidecar schema touch. The solve is NEVER cached (D-M9G-3):
// guides ARE the truth, the closed-form f64 solve re-derives bitwise
// identically on demand (μs-level); upstream's `upright_transform`
// persistence exists for the AUTO mode family, which is deliberately
// not ported (research/UPSTREAM-QUEUE.md).
//
// OFF = IDENTITY (v2 MIN-2, pinned semantics): an enabled off instance
// renders identity (byte-exact blit) AND its params persist legally —
// upright joins the editing seed, so instance paramsData is always
// written (ashift/flip same shape); there is deliberately NO
// "off doesn't write the sidecar" branch (the pristine convention is a
// DRT/film document-record semantics, not an instance-params one).
//
// INTENTIONAL DIVERGENCES (all shared with AshiftModule's ledger):
// 1. **Uniforms per-run via a shared MTLBuffer** (D2 shape): the H needs
//    the plane size only known at process time. The 80-byte struct rides
//    a makeBuffer upload (the stack-addressed setBytes raced the async-
//    committed encoder — the all-transparent warp postmortem).
// 2. **Bilinear border: clamp taps, transparent outside** (D4): the
//    kernel's existing semantic.
// 3. **Neutral/pathological → blit identity** (D5): the pipe owns
//    enablement; the module renders identity + logs, never crashes.
// ─────────────────────────────────────────────────────────────────────────

/// Kernel-name + bundle-anchor convenience (`AshiftKernel` shape — the
/// DELIBERATE shared-name form: upright dispatches the existing generic
/// warp; the PSO cache dedupes, zero new Metal).
public enum UprightKernel {
    /// The SHARED generic backward homography warp (AshiftKernels.metal).
    /// Zero new kernels (M9-3 red line: `git diff AshiftKernels.metal`
    /// stays empty).
    public static let functionName = "ashift_warp"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class UprightModule: IOPModule {

    /// One user-drawn guide: two endpoints in the op's INPUT-FRAME
    /// normalized 0..1 coordinates (Double ×4 — the solve domain keeps
    /// f64; L013 needs no hash here because Params ride StableHash over
    /// the JSON encoding). ≤4 guides (the upstream Guided cap; the module
    /// truncates defensively).
    public struct Guide: Codable, Hashable, Sendable {
        public var ax: Double
        public var ay: Double
        public var bx: Double
        public var by: Double

        public init(ax: Double = 0, ay: Double = 0, bx: Double = 0, by: Double = 0) {
            self.ax = ax
            self.ay = ay
            self.bx = bx
            self.by = by
        }

        public static let zero = Guide()
    }

    /// The solve mode. Exactly two cases (D-M9G-3: Guided only — future
    /// auto modes ADD a case, the compile-time extension point, DrtMethod
    /// precedent).
    public enum Mode: String, Codable, Hashable, Sendable {
        /// No correction (identity; the default seed state).
        case off
        /// Solve from the user's guides (≤4).
        case guided
    }

    public struct Params: Codable, Hashable, Sendable {
        public var mode: Mode
        public var guides: [Guide]

        public init(mode: Mode = .off, guides: [Guide] = []) {
            self.mode = mode
            self.guides = guides
        }

        /// The neutral identity (cache-neutral seed).
        public static let neutral = Params()
    }

    public static let opName = "upright"

    /// M9-3: v50 slot 15.5 — after ashift (15.0), before flip (16.0): the
    /// upright consumes the manually-rotated frame (guides are drawn on
    /// what the user sees), and flip/crop consume the upright output AABB.
    public static let iopOrder: Float = 15.5

    /// The ashift flags subset: tiling-eligible, single-instance,
    /// fast-pipe member (geometric, no blending).
    public static let flags: IOPFlags = [.allowTiling, .oneInstance, .allowFastPipe]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// The committed working copy (the geometry the ROI hooks read).
    /// Owned by the box's isolation domain. GOTCHA: `ModuleBox.setParams`
    /// is the ONLY commit path.
    private var committed: Params = Params()

    public init() {}

    /// Fresh images start OFF (identity; the panel drives the seed
    /// instance, exposure-0EV style).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// Park the working copy + hash the RAW params (D-H4). The solve is
    /// deliberately NOT committed here (D-M9G-3: closed-form f64 re-derive
    /// on demand — bitwise identical, μs-level; no cache, no invalidation).
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = params
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
    }

    /// The neutral predicate: OFF, or nothing the solver could use. An
    /// enabled off instance stays cache-neutral (blit identity, exposure-
    /// 0EV style) while its params persist legally (the seed's paramsData
    /// is always written — ashift/flip same shape).
    func isNeutral(_ p: Params) -> Bool {
        if p.mode == .off { return true }
        let usable = p.guides.prefix(4).filter { g in
            let dx = g.bx - g.ax
            let dy = g.by - g.ay
            return (dx * dx + dy * dy) > 1e-12
        }
        return usable.isEmpty
    }

    /// guides (input-frame 0..1) → centred-normalized Segments → the
    /// solve → plane-pixel forward/inverse pair. `D_out · H_centred ·
    /// D_in⁻¹` rescales the centred-domain homography to plane pixels
    /// (L = the long edge; the ashift compose same-position conversion,
    /// Double math — Float32 only at the uniforms boundary, L006).
    func solveMatrices(
        size: SIMD2<Double>
    ) -> (forward: Mat3D, inverse: Mat3D, outSpan: SIMD2<Double>)? {
        let L = max(size.x, size.y)
        guard L > 0 else { return nil }
        let toCentred = { (p: SIMD2<Double>) -> SIMD2<Double> in
            SIMD2(
                (p.x * size.x - size.x / 2) / (L / 2),
                (p.y * size.y - size.y / 2) / (L / 2))
        }
        let segs = committed.guides.prefix(4).map { g in
            UprightMath.Segment(
                a: toCentred(SIMD2(g.ax, g.ay)),
                b: toCentred(SIMD2(g.bx, g.by)))
        }
        let centred = UprightMath.solveGuided(segs)
        let dinv = Mat3D(2 / L, 0, -size.x / L, 0, 2 / L, -size.y / L, 0, 0, 1)
        let dout = Mat3D(L / 2, 0, size.x / 2, 0, L / 2, size.y / 2, 0, 0, 1)
        let forward = Mat3D.mul(dout, Mat3D.mul(centred, dinv))
        guard let inverse = forward.inverted() else { return nil }
        // The output AABB span (plane pixels) — the mapper's outSpan and
        // the ROI hooks share this one predicate.
        let span = Self.forwardSpan(forward: forward, inSize: size)
        return (forward, inverse, span)
    }

    /// The four input corners through the forward matrix → AABB span
    /// (floored — dt `:1190-1194` shape; no inner clip, upright has none).
    static func forwardSpan(forward: Mat3D, inSize: SIMD2<Double>) -> SIMD2<Double> {
        var xm = Double.greatestFiniteMagnitude, ym = Double.greatestFiniteMagnitude
        var xM = -Double.greatestFiniteMagnitude, yM = -Double.greatestFiniteMagnitude
        for (x, y) in [
            (0.0, 0.0), (inSize.x, 0.0),
            (0.0, inSize.y), (inSize.x, inSize.y),
        ] {
            let q = forward.project(x, y)
            xm = min(xm, q.x); xM = max(xM, q.x)
            ym = min(ym, q.y); yM = max(ym, q.y)
        }
        return SIMD2(floor(xM - xm), floor(yM - ym))
    }

    /// dt `modify_roi_out` shape (AshiftModule L020 frame convention):
    /// origin preserved, ONLY w/h recomputed (forward AABB of the input
    /// rect → floor). Neutral or pathological (<4px) → keep input.
    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        if isNeutral(committed) { roi = input; return }
        let size = SIMD2<Double>(Double(piece.dscIn.width), Double(piece.dscIn.height))
        guard let m = solveMatrices(size: size) else {
            roi = input
            return
        }
        guard m.outSpan.x >= 4, m.outSpan.y >= 4 else {
            AppError.logger.warning(
                "upright modifyROIOut pathological (<4px) — rendering identity")
            roi = input
            return
        }
        roi = input
        roi.width = Int(m.outSpan.x)
        roi.height = Int(m.outSpan.y)
    }

    /// dt `modify_roi_in` under OUR walk's frame convention (L020): the
    /// four OUTPUT-FRAME corners through the INVERSE matrix (no inner-clip
    /// offset — upright has none) → AABB + 2× interpolation margin → clamp
    /// to bufIn. Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        if isNeutral(committed) { input = roi; return }
        let size = SIMD2<Double>(Double(piece.dscIn.width), Double(piece.dscIn.height))
        guard let m = solveMatrices(size: size) else {
            input = roi
            return
        }
        let corners = [
            (Double(roi.x), Double(roi.y)),
            (Double(roi.x + roi.width), Double(roi.y)),
            (Double(roi.x), Double(roi.y + roi.height)),
            (Double(roi.x + roi.width), Double(roi.y + roi.height)),
        ]
        var xm = Double.greatestFiniteMagnitude, ym = Double.greatestFiniteMagnitude
        var xM = -Double.greatestFiniteMagnitude, yM = -Double.greatestFiniteMagnitude
        for (x, y) in corners {
            let q = m.inverse.project(x, y)
            xm = min(xm, q.x); xM = max(xM, q.x)
            ym = min(ym, q.y); yM = max(ym, q.y)
        }
        // dt `:1272-1277`: 2× the interpolation width (bilinear tap = 1).
        let iw1 = 1.0, iw2 = 2.0
        var ix = xm - iw1, iy = ym - iw1
        var iw = xM + iw2 - xm + 1.0, ih = yM + iw2 - ym + 1.0
        ix = min(max(ix, 0), floor(size.x))
        iy = min(max(iy, 0), floor(size.y))
        iw = min(max(iw, 4), floor(size.x) - ix)
        ih = min(max(ih, 4), floor(size.y) - iy)
        input = ROI(x: Int(ix.rounded(.down)), y: Int(iy.rounded(.down)),
                    width: Int(iw.rounded(.down)), height: Int(ih.rounded(.down)),
                    scale: roi.scale)
    }

    /// The mask point-mapping segment (Plan 06-03 T2 seam — the ONLY
    /// viewport ⇄ upright-input-frame channel; the mapper body itself is
    /// zero-diff). nil when neutral/singular; the <4px pathological gate
    /// mirrors `modifyROIOut` (identity there ⇒ identity here).
    public func pointMapSegment(
        inputSize: SIMD2<Double>
    ) -> (segment: GeometrySegment, outputSize: SIMD2<Double>)? {
        guard !isNeutral(committed) else { return nil }
        guard let m = solveMatrices(size: inputSize) else { return nil }
        guard m.outSpan.x >= 4, m.outSpan.y >= 4 else { return nil }
        return (
            .homography(
                forward: m.forward, inverse: m.inverse,
                clip: SIMD2(0, 0), inSize: inputSize, outSpan: m.outSpan),
            m.outSpan)
    }

    /// Neutral or pathological → blit identity (D5). Else the single-pass
    /// `ashift_warp` backward sampling over the OUTPUT plane (the uniforms
    /// carry clip 0/0 — upright has no inner crop). The clip-free segment
    /// means output x IS output-frame x.
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
        // The forward hook doubles as the pathological detector (the same
        // <4px gate — one predicate, no second math).
        var probe = ROI()
        modifyROIOut(&probe, input: ROI(x: 0, y: 0, width: piece.dscIn.width,
                                        height: piece.dscIn.height, scale: roiOut.scale),
                     piece: piece)
        if probe.width < 4 || probe.height < 4 {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        let size = SIMD2<Double>(Double(piece.dscIn.width), Double(piece.dscIn.height))
        guard let m = solveMatrices(size: size) else {
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }
        var uniforms = AshiftWarpUniforms(
            hinv: m.inverse,
            oroiX: Int32(roiOut.x), oroiY: Int32(roiOut.y),
            clipX: 0, clipY: 0,
            iroiX: Int32(roiIn.x), iroiY: Int32(roiIn.y),
            inW: Int32(input.width), inH: Int32(input.height))
        guard let buffer = metal.device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<AshiftWarpUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        try await metal.dispatch2DTexture(
            functionName: UprightKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
    }

    /// Whole-window blit (AshiftModule's D5 fallback, mechanically mirrored
    /// here — that module's copy is private to its file and the sealed-face
    /// discipline keeps it untouched). Sync; the caller's fence covers
    /// readback (L014).
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
        blit.endEncoding() // L008: encode close precedes commit, never defer
        commandBuffer.commit()
    }
}
