import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// LIQUIFY — portrait liquify warp (Plan 06-06 T2, IOP-GEO-05).
//
// Darktable reference: `src/iop/liquify.c` (tree dc58cf0ba1):
//   - v50 slot 18.0 (`iop_order.c` — after clipping 17.0, before spots 19.0;
//     V50OrderTests pins the neighborhood)
//   - flags :313-315 (SUPPORTS_BLENDING only — dt does NOT allow tiling;
//     Lightamer declares the halo but keeps the amortized working set small,
//     D-06-06-T2-2)
//   - operation_tags :317-323 = DISTORT | GEOMETRY, filter :325-327 =
//     DECORATION | CROPPING (Lightamer has no tag system yet — the tags are
//     recorded here as the dt-source annotation; the pipe does not consume
//     them)
//   - RGB domain (:329-334 default_colorspace IOP_CS_RGB)
//   - process :1390-1415 = copy whole roi → build global distortion map →
//     warp the extent (GPU leg = `warp_kernel`, LiquifyKernels.metal)
//   - modify_roi_in :1213-1285 = extend the input roi by the stamp extent ∪
//     roi_out, clamp to the pipe plane
//
// FRAME CONVENTION (L020/L021): `dscIn` is THIS run's plane pixels; params
// are fractions of the module's entry frame (LiquifyDistortionField header)
// resolved against `dscIn` — no iscale rescale exists anywhere in the chain
// (the normalized storage folds it), and the field grid shares the kernel's
// sampling domain exactly.
//
// INTENTIONAL DIVERGENCES:
// 1. **Empty paths = blit identity** (the NORMAL path — RESEARCH Risk 9):
//    dt copies the roi then no-ops the map; the blit here is byte-identical
//    and cache-neutral (the seed carries an enabled empty instance).
// 2. **Per-run uniform/map/ktable MTLBuffers** (D2, ashift precedent): the
//    80-byte uniform + the grid exceed setBytes territory — the 176-byte
//    setBytes async-encoder race (06-03 forensics) pins everything to
//    MTLBuffers.
// 3. **Field cache** (the plan's 仅参数变化重建): keyed on (paramsHash, run
//    geometry, roiOut) — `fieldBuildCount` is the test probe.
// ─────────────────────────────────────────────────────────────────────────────

/// Kernel-name + bundle-anchor convenience (the `AshiftKernel` pattern).
public enum LiquifyKernel {
    public static let functionName = "liquify_warp"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class LiquifyModule: IOPModule {

    /// dt `dt_iop_liquify_params_t` (`nodes[MAX_NODES]`) — Lightamer carries
    /// the live path list + the resampling kernel choice (dt takes it from
    /// the interpolation userpref; Lightamer pins it per instance,
    /// D-06-06-T2-3).
    public struct Params: Codable, Hashable, Sendable {
        /// Path elements, ≤ MAX_NODES (dt's array is exactly 100 slots with
        /// the first INVALIDATED as terminator; Lightamer stores the live
        /// prefix — same information, no dead tail).
        public var paths: [LiquifyPathData]
        /// Resampling kernel family (default lanczos3 — dt's highest-quality
        /// warp table; plan names lanczos3/bicubic as the kernels).
        public var interpolation: LiquifyInterpolation

        public init(
            paths: [LiquifyPathData] = [],
            interpolation: LiquifyInterpolation = .lanczos3
        ) {
            precondition(
                paths.count <= LiquifyPathData.maxNodes,
                "liquify paths exceed dt MAX_NODES (\(paths.count) > \(LiquifyPathData.maxNodes))")
            self.paths = paths
            self.interpolation = interpolation
        }

        /// The cache-neutral seed: no paths = the blit identity.
        public static let neutral = Params()
    }

    public static let opName = "liquify"

    /// Darktable v50 slot 18.0 — a base-chain warp BEFORE the tone stages
    /// (exposure 21.0), AFTER the geometric rectifiers (clipping 17.0).
    public static let iopOrder: Float = 18.0

    /// dt flags (:313-315): blending-capable only (no ALLOW_TILING in dt —
    /// the tile seam below declares the halo for the Lightamer tile driver
    /// without forcing engagement, D-06-06-T2-2).
    public static let flags: IOPFlags = [.supportsBlending]

    public static let defaultColorspace: IOPColorspace = .RGB

    /// dt kdesc resolution (liquify.c:1470 — the kernel table's steps per
    /// tap interval).
    static let kdescResolution = 100

    /// The committed working copy (CropModule/AshiftModule pattern — the
    /// ROI hooks read it; GOTCHA: `ModuleBox.setParams` is the only commit
    /// path).
    private var committed: Params = Params()

    // MARK: field cache (仅参数变化重建 — the plan's cache assertion)

    private struct FieldCache {
        var key: FieldKey
        var field: DisplacementField
    }

    private struct FieldKey: Equatable {
        var paramsHash: UInt64
        var planeW: Int, planeH: Int
        var roiX: Int, roiY: Int, roiW: Int, roiH: Int
        var interpolation: LiquifyInterpolation
    }

    private var cache: FieldCache?

    /// Test probe: how many times the displacement grid was (re)built.
    private(set) var fieldBuildCount = 0

    public init() {}

    /// dt `reload_defaults` — an empty path list (no liquify edits on a
    /// fresh image).
    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        committed = params
        piece.paramsHash = StableHash.hash(ParamsCoding.encode(params))
        piece.data = nil
        cache = nil  // the cache key includes the hash; drop eagerly anyway
    }

    /// The neutral predicate: NO paths = identity (also true when every
    /// stamp degenerates — the field builder returns nil and process blits).
    func isNeutral(_ p: Params) -> Bool {
        p.paths.isEmpty
    }

    // MARK: kernel table (dt :1470-1497)

    /// The resampling kernel table: `size·resolution + 1` samples; kmix
    /// blends adjacent samples in the kernel (LiquifyKernels.metal).
    static func kernelTable(_ interpolation: LiquifyInterpolation) -> (
        table: [Float], resolution: Int
    ) {
        let size = interpolation.kernelSize
        if interpolation == .bilinear {
            // dt :1472-1477: kdesc {1, 1}, k = [1, 0].
            return ([1, 0], 1)
        }
        let resolution = Self.kdescResolution
        var k = [Float](repeating: 0, count: size * resolution + 1)
        for i in 0...size * resolution {
            let x = Float(i) / Float(resolution)
            switch interpolation {
            case .bilinear: k[i] = 0  // unreachable — handled above
            case .bicubic: k[i] = Self.bicubic(0.5, x)
            case .lanczos2: k[i] = Self.lanczos(2, x)
            case .lanczos3: k[i] = Self.lanczos(3, x)
            }
        }
        return (k, resolution)
    }

    /// dt lanczos (:1424-1431).
    static func lanczos(_ a: Float, _ x: Float) -> Float {
        let ax = abs(x)
        if ax >= a { return 0 }
        if ax < Float.ulpOfOne { return 1 }
        let pi = Float.pi
        return (a * sin(pi * x) * sin(pi * x / a)) / (pi * pi * x * x)
    }

    /// dt bicubic (:1433-1441) — the bicubic convolution algorithm, a = 0.5
    /// at the call site.
    static func bicubic(_ a: Float, _ x: Float) -> Float {
        let ax = abs(x)
        if ax <= 1 { return ((a + 2) * ax - (a + 3)) * ax * ax + 1 }
        if ax < 2 { return ((a * ax - 5 * a) * ax + 8 * a) * ax - 4 * a }
        return 0
    }

    // MARK: field access (cached)

    /// Build (or reuse) the displacement grid for this run. nil = nothing
    /// to do (no stamps intersect the output roi) — the caller blits.
    private func field(
        piece: IOPiece, roiOut: ROI, plane: SIMD2<Double>
    ) -> DisplacementField? {
        let key = FieldKey(
            paramsHash: piece.paramsHash,
            planeW: piece.dscIn.width, planeH: piece.dscIn.height,
            roiX: roiOut.x, roiY: roiOut.y, roiW: roiOut.width, roiH: roiOut.height,
            interpolation: committed.interpolation)
        if let cache, cache.key == key { return cache.field }
        guard let field = LiquifyDistortionField.build(
            paths: committed.paths, frame: plane,
            boundsOrigin: SIMD2(roiOut.x, roiOut.y),
            boundsSize: SIMD2(roiOut.width, roiOut.height))
        else {
            cache = nil
            return nil
        }
        fieldBuildCount += 1
        cache = FieldCache(key: key, field: field)
        return field
    }

    // MARK: ROI negotiation (dt modify_roi_in :1213-1285)

    /// dt semantics under OUR walk's frame convention (L020): start from the
    /// output roi, extend by the stamp extent (stamps NOT entirely outside
    /// the roi — dt `_get_map_extent`), add the interpolation margin (a low,
    /// a+1 high — the ashift D4 tap pattern), clamp to bufIn (plane pixels —
    /// NO ×scale, L021). Neutral → verbatim.
    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        if isNeutral(committed) { input = roi; return }
        let plane = SIMD2<Double>(Double(piece.dscIn.width), Double(piece.dscIn.height))
        let stamps = LiquifyDistortionField.interpolateStamps(
            paths: committed.paths, frame: plane)
        guard let extent = LiquifyDistortionField.stampExtent(
            of: stamps, boundsOrigin: SIMD2(roi.x, roi.y),
            boundsSize: SIMD2(roi.width, roi.height))
        else {
            input = roi
            return
        }
        let a = committed.interpolation.kernelSize
        let x0 = min(roi.x, extent.origin.x) - a
        let y0 = min(roi.y, extent.origin.y) - a
        let x1 = max(roi.x + roi.width, extent.origin.x + extent.size.x) + a + 1
        let y1 = max(roi.y + roi.height, extent.origin.y + extent.size.y) + a + 1
        // Clamp to bufIn (dt :1281-1284; L021 — dscIn IS plane pixels).
        let cx0 = min(max(x0, 0), piece.dscIn.width)
        let cy0 = min(max(y0, 0), piece.dscIn.height)
        let cx1 = min(max(x1, 4), piece.dscIn.width)
        let cy1 = min(max(y1, 4), piece.dscIn.height)
        input = ROI(
            x: cx0, y: cy0, width: max(1, cx1 - cx0), height: max(1, cy1 - cy0),
            scale: roi.scale)
    }

    // MARK: tile seam (D-06-06-T2-2)

    /// The halo = the displacement upper bound + the kernel taps. Computed
    /// from the PATHS (cheap — no field build): each stamp deposits at most
    /// 0.5·|strength − point| (the 0.1 relocation only shrinks).
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        if isNeutral(committed) { return 0 }
        var maxDisp = 0.0
        for d in committed.paths {
            let dx = Double(d.strength.x - d.point.x) * Double(piece.dscIn.width)
            let dy = Double(d.strength.y - d.point.y) * Double(piece.dscIn.height)
            maxDisp = max(maxDisp, 0.5 * (dx * dx + dy * dy).squareRoot())
        }
        guard maxDisp > 0 else { return 0 }
        return Int(maxDisp.rounded(.up)) + committed.interpolation.kernelSize + 1
    }

    /// The amortized grid cost (8 B per extent cell over the plane). Small
    /// maps stay under the tile budget (dt's no-tiling default for typical
    /// liquify edits); full-frame warps on 100MP FULL legitimately engage
    /// the tile driver.
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        if isNeutral(committed) { return 0 }
        let plane = SIMD2<Double>(Double(piece.dscIn.width), Double(piece.dscIn.height))
        let stamps = LiquifyDistortionField.interpolateStamps(
            paths: committed.paths, frame: plane)
        guard let extent = LiquifyDistortionField.stampExtent(
            of: stamps, boundsOrigin: .zero,
            boundsSize: SIMD2(piece.dscIn.width, piece.dscIn.height))
        else { return 0 }
        let bytes = Double(extent.size.x * extent.size.y) * 8
        let area = Double(piece.dscIn.width * piece.dscIn.height)
        return Int((bytes / area).rounded(.up))
    }

    // MARK: mask point-mapping segment (Plan 06-06 T3 — the 6-3
    // reservation realized; D-06-CONTEXT-7 content anchoring)

    /// The displacement segment at FULL map coordinates (the mapper works
    /// in frame pixels; the field is built over the whole stamp extent —
    /// no roi clipping, mask points can sample anywhere). nil when neutral
    /// (empty paths = NO segment — the normal path stays the identity by
    /// omission, RESEARCH Risk 9).
    public func pointMapSegment(
        inputSize: SIMD2<Double>
    ) -> (segment: GeometrySegment, outputSize: SIMD2<Double>)? {
        guard !isNeutral(committed) else { return nil }
        guard let field = LiquifyDistortionField.build(
            paths: committed.paths, frame: inputSize,
            boundsOrigin: .zero,
            boundsSize: SIMD2(Int(inputSize.x.rounded(.up)), Int(inputSize.y.rounded(.up))))
        else { return nil }
        return (.liquify(field), inputSize)
    }

    // MARK: process (dt process :1390-1415 + the CL leg :1452-1520)

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        let plane = SIMD2<Double>(Double(piece.dscIn.width), Double(piece.dscIn.height))
        guard !isNeutral(committed),
              let field = field(piece: piece, roiOut: roiOut, plane: plane)
        else {
            // Empty/degenerate paths = the byte-identical blit (D-06-06-T2-1;
            // dt's copy leg :1400-1403).
            try blitIdentity(input: input, output: output, roiIn: roiIn, roiOut: roiOut, metal: metal)
            return
        }

        // Uniforms + grid + kernel table as MTLBuffers (the setBytes race
        // lesson — divergence 2). Rois struct: 3×int4 + int2 = 56 B.
        struct Rois {
            var roiIn: SIMD4<Int32>
            var roiOut: SIMD4<Int32>
            var extent: SIMD4<Int32>
            var kdesc: SIMD2<Int32>
        }
        let (table, resolution) = Self.kernelTable(committed.interpolation)
        var rois = Rois(
            roiIn: SIMD4(Int32(roiIn.x), Int32(roiIn.y), Int32(roiIn.width), Int32(roiIn.height)),
            roiOut: SIMD4(Int32(roiOut.x), Int32(roiOut.y), Int32(roiOut.width), Int32(roiOut.height)),
            extent: SIMD4(
                Int32(field.forward.origin.x), Int32(field.forward.origin.y),
                Int32(field.forward.width), Int32(field.forward.height)),
            kdesc: SIMD2(Int32(committed.interpolation.kernelSize), Int32(resolution)))
        guard
            let roisBuffer = metal.device.makeBuffer(
                bytes: &rois, length: MemoryLayout<Rois>.stride,
                options: .storageModeShared),
            let mapBuffer = metal.device.makeBuffer(
                bytes: field.forward.vectors,
                length: field.forward.vectors.count * MemoryLayout<SIMD2<Float>>.stride,
                options: .storageModeShared),
            let tableBuffer = metal.device.makeBuffer(
                bytes: table, length: table.count * MemoryLayout<Float>.stride,
                options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        // Field grid ↔ kernel sampling domain (L020 same-domain): the grid
        // is indexed by FRAME pixels (cell = framePos − extent.origin) and
        // the kernel samples input at framePos − roiIn.origin + warp — the
        // exact LiquifyDistortionField.deposit coordinate premise.
        try await metal.dispatch2DTexture(
            functionName: LiquifyKernel.functionName,
            input: input,
            output: output
        ) { encoder in
            encoder.setBuffer(roisBuffer, offset: 0, index: 0)
            encoder.setBuffer(mapBuffer, offset: 0, index: 1)
            encoder.setBuffer(tableBuffer, offset: 0, index: 2)
        }
    }

    /// Whole-window blit (the copy leg; AshiftModule pattern). Sync — the
    /// caller's fence covers readback (L014).
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
