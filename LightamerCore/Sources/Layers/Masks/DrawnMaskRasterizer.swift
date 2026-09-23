import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// DrawnMaskRasterizer (Plan 06-03 T4/T5) — the GPU side of the drawn mask:
// one drawn form → a window-sized r32Float plane whose red channel is the
// PREMULTIPLIED effective opacity (clamp[0,1] × gopacity — the 06-02
// composite contract D-06-02-T5-3), content-anchored through the
// GeometryPointMapper.
//
// Pipeline per mask plane (kernels in MaskRasterKernels.metal):
//   ellipse/gradient/path → `mask_raster_analytic` (per-pixel closed form)
//   brush                 → `mask_stamp_*` render pass (additive blender,
//                           the T1 spike decision D-06-03-T1-1)
//   then                  → `mask_fold` (saturate + × gopacity)
//
// The CONTENT-ANCHOR leg: the analytic kernel and the stamp fragments both
// evaluate the form in DECODE-frame normalized coordinates — window pixels
// convert through the mapper's inverse (the projective composite uniform +
// radial lens leg); stamp quad FEET map through the mapper's forward.
//
// Caching: the plane keys on (imageID, pipeType, layerID, maskVersionHash,
// roi) at `maskPosition` — a mask edit flips only this key (chain planes
// never notice); a chain edit keeps the mask plane resident.
//
// v1 scope (06-03): a SINGLE form rasterizes (the first in
// `DrawnMaskSpec.forms`; the group shell's combine semantics land in 06-4
// — 06-03-DECISIONS). Stamps accumulate within one BrushStroke only.
// ─────────────────────────────────────────────────────────────────────────────

/// Swift mirror of the MSL `MaskRasterUniforms` (10 float4 + 1 uint4 —
/// every member a 16-byte chunk, the ashift packing-postmortem pattern).
struct MaskRasterUniforms {
    var rows0: SIMD4<Float>     // PRE stage row 0 (mid_n → pre-lens decode_n)
    var rows1: SIMD4<Float>     // row 1
    var rows2: SIMD4<Float>     // row 2
    var lens: SIMD4<Float>      // k1, k2, hasLens, aspect (frameH/frameW)
    var frame: SIMD4<Float>     // frameW, frameH, winOriginX, winOriginY (px)
    var window: SIMD4<Float>    // winW, winH, outW, outH (composite frame)
    var form0: SIMD4<Float>     // ellipse: center.x, center.y (wu), rx, ry | gradient: anchor
    var form1: SIMD4<Float>     // rotationDeg, border, compression, curvature
    var misc: SIMD4<Float>      // formType (0 ellipse, 1 path, 2 gradient), gradState, 0, 0
    var bands: SIMD4<UInt32>    // rowBegin, rowEnd, 0, 0
    // Plan 06-06-T3 staged decomposition (liquify's inverse legs between
    // the crop⁻¹ and flip/ashift⁻¹ projective stages — 16-byte chunks, the
    // packing-postmortem pattern).
    var post0: SIMD4<Float>     // POST stage row 0 (composite_n → mid_n)
    var post1: SIMD4<Float>     // row 1
    var post2: SIMD4<Float>     // row 2
    var liq0: SIMD4<Float>      // grid originX, originY (mid px), gridW, gridH
    var liq1: SIMD4<Float>      // hasLiquify, midW, midH, 0

    init(mapper: GeometryPointMapper, window: ROI, form: MaskForm) {
        // Staged decomposition: `pre` carries the full fold when no liquify
        // segment exists (bit-compatible with the historical single matrix);
        // with one, the crop⁻¹ part splits into `post` and the liquify grid
        // legs between the stages.
        let staged = mapper.stagedInverseComposite
        let m = staged.pre
        rows0 = SIMD4(Float(m[0, 0]), Float(m[0, 1]), Float(m[0, 2]), 0)
        rows1 = SIMD4(Float(m[1, 0]), Float(m[1, 1]), Float(m[1, 2]), 0)
        rows2 = SIMD4(Float(m[2, 0]), Float(m[2, 1]), Float(m[2, 2]), 0)
        post0 = SIMD4(Float(staged.post[0, 0]), Float(staged.post[0, 1]), Float(staged.post[0, 2]), 0)
        post1 = SIMD4(Float(staged.post[1, 0]), Float(staged.post[1, 1]), Float(staged.post[1, 2]), 0)
        post2 = SIMD4(Float(staged.post[2, 0]), Float(staged.post[2, 1]), Float(staged.post[2, 2]), 0)
        if let field = staged.field {
            liq0 = SIMD4(
                Float(field.forward.origin.x), Float(field.forward.origin.y),
                Float(field.forward.width), Float(field.forward.height))
            liq1 = SIMD4(1, Float(staged.mid.x), Float(staged.mid.y), 0)
        } else {
            liq0 = SIMD4(0, 0, 0, 0)
            liq1 = SIMD4(0, Float(staged.mid.x), Float(staged.mid.y), 0)
        }
        let lp = mapper.lensParams
        let aspect = Self.aspectOf(mapper)
        lens = SIMD4(
            Float(lp?.k1 ?? 0), Float(lp?.k2 ?? 0), lp != nil ? 1 : 0, Float(aspect))
        frame = SIMD4(
            Float(mapper.frameSize.x), Float(mapper.frameSize.y),
            Float(window.x), Float(window.y))
        self.window = SIMD4(
            Float(window.width), Float(window.height),
            Float(mapper.outputSize.x), Float(mapper.outputSize.y))
        switch form.kind {
        case let .ellipse(e):
            // center/anchor ride NORMALIZED (the kernel converts to width
            // units; dt's gradient evaluates the anchor on full-frame px)
            form0 = SIMD4(e.center.x, e.center.y, Float(e.radiusX), Float(e.radiusY))
            form1 = SIMD4(e.rotationDegrees, e.border, 0, 0)
            misc = SIMD4(0, 0, 0, 0)
        case let .gradient(g):
            form0 = SIMD4(g.anchor.x, g.anchor.y, 0, 0)
            form1 = SIMD4(g.rotationDegrees, 0, g.compression, g.curvature)
            misc = SIMD4(2, g.state == .linear ? 0 : 1, 0, 0)
        case .path:
            form0 = SIMD4(0, 0, 0, 0)
            form1 = SIMD4(0, 0, 0, 0)
            misc = SIMD4(1, 0, 0, 0)
        case .brush:
            form0 = SIMD4(0, 0, 0, 0)
            form1 = SIMD4(0, 0, 0, 0)
            misc = SIMD4(0, 0, 0, 0)
        }
        bands = SIMD4(0, UInt32.max, 0, 0)
    }

    private static func aspectOf(_ mapper: GeometryPointMapper) -> Double {
        mapper.frameSize.x > 0 ? mapper.frameSize.y / mapper.frameSize.x : 1
    }
}

public enum DrawnMaskRasterizer {

    // MARK: - Key hash (06-05: maskVersion ⊕ mapper geometry state)

    /// The mask-plane key hash: `MaskSpec.stableHash()` ⊕ the mapper's
    /// geometry-state hash (FNV fold — StableHash only, L013). The 06-03
    /// key was mask-version only; the 06-06 leftover ① audit showed an
    /// ashift/liquify param change (same roi) could HIT a stale plane —
    /// the geometry state is part of the rasterization INPUT (the inverse
    /// point map), so it belongs in the key.
    static func foldKeyHash(spec: MaskSpec, mapper: GeometryPointMapper) -> UInt64 {
        var h = spec.stableHash()
        var m = mapper.stableHash()
        h = withUnsafeBytes(of: &m) { StableHash.combine(h, $0) }
        return h
    }

    // MARK: - Entry (cached)

    /// The DRAWN-only optional entry (06-05 display overlay): nil when the
    /// spec carries no drawable drawn forms (parametric/raster-only specs
    /// return nil — the display tint is a drawn-mask affordance in v1).
    public static func planeIfDrawn(
        spec: MaskSpec,
        layerOpacity: Float,
        window: ROI,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        cache: PipeCache,
        imageID: UUID,
        pipeType: PipeResolution,
        layerID: UUID
    ) async throws -> (any MTLTexture)? {
        guard spec.hasDrawnForms else { return nil }
        let (plane, _) = try await plane(
            spec: spec, layerOpacity: layerOpacity, window: window,
            mapper: mapper, metal: metal, cache: cache, imageID: imageID,
            pipeType: pipeType, layerID: layerID)
        return plane
    }

    /// Fetch-or-rasterize the layer's drawn mask plane for `window`.
    /// Returns the plane + whether the cache HIT (the driver's accounting).
    public static func plane(
        spec: MaskSpec,
        layerOpacity: Float,
        window: ROI,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        cache: PipeCache,
        imageID: UUID,
        pipeType: PipeResolution,
        layerID: UUID,
        rowBands: Int = 1
    ) async throws -> (plane: any MTLTexture, hit: Bool) {
        precondition(spec.hasDrawnForms, "rasterize called without drawn forms")
        precondition(window.width > 0 && window.height > 0, "empty window")
        // The key folds the MAPPER geometry state (06-05 — the 06-06
        // leftover ①): a crop/ashift/lens/liquify edit re-rasterizes the
        // plane through the new mapping instead of hitting a stale plane
        // keyed on the unchanged (maskHash, roi).
        let hash = Self.foldKeyHash(spec: spec, mapper: mapper)
        let key = PipeCacheKey.maskKey(
            imageID: imageID, pipeType: pipeType, layerID: layerID,
            maskHash: hash, roi: window)
        let byteCount = window.width * window.height * 4 // r32Float
        let statsBefore = await cache.stats
        let box = try await cache.plane(for: key, byteCount: byteCount) {
            try await Self.render(
                spec: spec, layerOpacity: layerOpacity, window: window,
                mapper: mapper, metal: metal, rowBands: rowBands)
        }
        let delta = (await cache.stats) - statsBefore
        return (box.texture, delta.hits > 0)
    }

    // MARK: - Render (the cache-miss closure)

    static func render(
        spec: MaskSpec,
        layerOpacity: Float,
        window: ROI,
        mapper: GeometryPointMapper,
        metal: MetalContext,
        rowBands: Int
    ) async throws -> any MTLTexture {
        guard spec.hasDrawnForms else {
            throw AppError.unsupportedFile("no drawn form to rasterize")
        }

        func makePlane(_ usage: MTLTextureUsage) throws -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r32Float, width: window.width, height: window.height,
                mipmapped: false)
            d.usage = usage
            d.storageMode = .shared
            guard let t = metal.device.makeTexture(descriptor: d) else {
                throw MetalError.bufferAllocationFailed(window.width * window.height * 4)
            }
            return t
        }
        let accumulator = try makePlane([.shaderRead, .shaderWrite, .renderTarget])
        let final = try makePlane([.shaderRead])
        // Plan 06-06-T3: ONE liquify displacement-grid buffer per render
        // (bound at the kernels' new slots; a dummy when the mapper has no
        // liquify segment — MSL requires a valid binding either way).
        let liqGrid = try Self.liquifyGridBuffer(mapper: mapper, metal: metal)

        // v1 plane composition (06-03): ALL brush strokes of the spec
        // accumulate IN ORDER into one additive pass each (the eraser =
        // the negative-density stroke); ONE analytic shape (the first
        // non-brush form) fills the base. Cross-form combine ops = 06-4.
        // rowBands > 1 = the tile-seam driver: the SAME kernel dispatched
        // per row band (write band via the uniform gate) — the T8 gate
        // compares this partition against whole-plane execution.
        let forms = spec.drawn?.forms ?? []
        var analyticDispatched = false
        var brushDispatched = false
        for form in forms {
            switch form.kind {
            case .ellipse, .gradient:
                guard !analyticDispatched else { continue }
                analyticDispatched = true
                var uniforms = MaskRasterUniforms(mapper: mapper, window: window, form: form)
                if rowBands > 1 {
                    try await dispatchAnalyticBanded(
                        uniforms: uniforms, accumulator: accumulator,
                        bands: rowBands, metal: metal, liqGrid: liqGrid)
                } else {
                    uniforms.bands = SIMD4(0, UInt32.max, 0, 0)
                    try await dispatchAnalytic(
                        uniforms: uniforms, accumulator: accumulator, metal: metal,
                        liqGrid: liqGrid)
                }
            case let .path(path):
                guard !analyticDispatched else { continue }
                analyticDispatched = true
                var uniforms = MaskRasterUniforms(mapper: mapper, window: window, form: form)
                uniforms.form1.y = path.border
                let points = flattenPath(path, aspect: aspectOf(mapper))
                if rowBands > 1 {
                    try await dispatchAnalyticBanded(
                        uniforms: uniforms, accumulator: accumulator,
                        bands: rowBands, metal: metal, polyline: points,
                        liqGrid: liqGrid)
                } else {
                    uniforms.bands = SIMD4(0, UInt32.max, 0, 0)
                    try await dispatchAnalytic(
                        uniforms: uniforms, accumulator: accumulator, metal: metal,
                        polyline: points, liqGrid: liqGrid)
                }
            case let .brush(stroke):
                // The FIRST brush form clears the accumulator; every later
                // one LOADS (additive accumulate — the eraser subtracts
                // from what the earlier strokes painted).
                try await renderStamps(
                    stroke: stroke, window: window, mapper: mapper,
                    accumulator: accumulator, metal: metal,
                    clear: !brushDispatched, liqGrid: liqGrid)
                brushDispatched = true
            }
        }
        guard analyticDispatched || forms.contains(where: {
            if case .brush = $0.kind { return true } else { return false }
        }) else {
            throw AppError.unsupportedFile("no rasterizable form")
        }

        // Fold: saturate + premultiply (gopacity × form opacity — the
        // first form's stroke opacity; cross-form opacity = 06-4).
        let formOpacity: Float
        if case let .brush(stroke) = forms.first?.kind { formOpacity = stroke.opacity } else { formOpacity = 1 }
        try await fold(
            accumulator: accumulator, final: final,
            opacity: max(0, min(1, layerOpacity)) * max(0, min(1, formOpacity)),
            rowBands: rowBands, metal: metal)
        return final
    }

    private static func aspectOf(_ mapper: GeometryPointMapper) -> Double {
        mapper.frameSize.x > 0 ? mapper.frameSize.y / mapper.frameSize.x : 1
    }

    // MARK: - Liquify grid buffer (Plan 06-06-T3)

    /// The displacement grid of the mapper's liquify segment as an MTLBuffer
    /// (float2 per cell) — or a 16-byte dummy when absent (the kernels take
    /// a valid binding either way; the hasLiquify flag gates the leg).
    private static func liquifyGridBuffer(
        mapper: GeometryPointMapper, metal: MetalContext
    ) throws -> any MTLBuffer {
        var field: DisplacementField?
        for segment in mapper.segments {
            if case let .liquify(f) = segment { field = f }
        }
        guard let field else {
            var dummy = SIMD4<Float>(0, 0, 0, 0)
            guard let buffer = metal.device.makeBuffer(
                bytes: &dummy, length: MemoryLayout<SIMD4<Float>>.stride,
                options: .storageModeShared)
            else { throw MetalError.deviceUnavailable }
            return buffer
        }
        var vectors = field.forward.vectors
        guard let buffer = metal.device.makeBuffer(
            bytes: &vectors,
            length: max(1, vectors.count) * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        return buffer
    }

    // MARK: - Analytic dispatch (ellipse / path / gradient)

    private static func dispatchAnalytic(
        uniforms: MaskRasterUniforms,
        accumulator: any MTLTexture,
        metal: MetalContext,
        polyline: [SIMD2<Float>]? = nil,
        liqGrid: any MTLBuffer
    ) async throws {
        // The 176-byte uniform struct rides a SHARED MTLBuffer — never
        // setBytes: the stack-addressed large-struct setBytes upload raced
        // the async-committed encoder on this host (the 04-03 ashift
        // postmortem; every pixel read pre-dispatch garbage).
        var u = uniforms
        guard let uniformBuffer = metal.device.makeBuffer(
            bytes: &u, length: MemoryLayout<MaskRasterUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        var points = polyline ?? []
        var count = UInt32(points.count)
        var empty: Float = 0
        let session = try await metal.makeEncoder(functionName: "mask_raster_analytic")
        session.encoder.setTexture(accumulator, index: 0)
        session.encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        session.encoder.setBuffer(liqGrid, offset: 0, index: 3)
        if !points.isEmpty {
            session.encoder.setBytes(&points, length: points.count * 8, index: 1)
            session.encoder.setBytes(&count, length: 4, index: 2)
        } else {
            session.encoder.setBytes(&empty, length: 4, index: 1)
            session.encoder.setBytes(&count, length: 4, index: 2)
        }
        session.encoder.dispatchThreads(
            MTLSize(width: accumulator.width, height: accumulator.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    /// Band-partitioned analytic dispatch (the tile-seam driver, T8):
    /// `bands` row-band dispatches of the SAME kernel over the SAME plane,
    /// the band gate narrowing each write.
    static func dispatchAnalyticBanded(
        uniforms: MaskRasterUniforms,
        accumulator: any MTLTexture,
        bands: Int,
        metal: MetalContext,
        polyline: [SIMD2<Float>]? = nil,
        liqGrid: any MTLBuffer
    ) async throws {
        let rows = accumulator.height
        let perBand = Int(ceil(Double(rows) / Double(max(1, bands))))
        var start = 0
        while start < rows {
            var u = uniforms
            u.bands = SIMD4(UInt32(start), UInt32(min(rows, start + perBand)), 0, 0)
            try await dispatchAnalytic(
                uniforms: u, accumulator: accumulator, metal: metal,
                polyline: polyline, liqGrid: liqGrid)
            start += perBand
        }
    }

    // MARK: - Path flattening (bézier loop → polyline, width units)

    /// Flatten the closed bézier node loop into a polyline in WIDTH-UNIT
    /// coords (x, y·aspect) — the kernel's SDF domain. 24 samples/cubic.
    static func flattenPath(_ path: PathForm, aspect: Double) -> [SIMD2<Float>] {
        let nodes = path.nodes
        guard nodes.count >= 2 else { return [] }
        func wu(_ p: MaskPoint) -> SIMD2<Float> {
            SIMD2(p.x, Float(Double(p.y) * aspect))
        }
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(nodes.count * 24)
        let steps = 24
        for i in 0..<nodes.count {
            let a = nodes[i]
            let b = nodes[(i + 1) % nodes.count]
            let p0 = wu(a.corner), p1 = wu(a.ctrl2), p2 = wu(b.ctrl1), p3 = wu(b.corner)
            for k in 0..<steps {
                let t = Float(Double(k) / Double(steps))
                let mt = 1 - t
                let x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x
                    + 3 * mt * t * t * p2.x + t * t * t * p3.x
                let y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y
                    + 3 * mt * t * t * p2.y + t * t * t * p3.y
                out.append(SIMD2(x, y))
            }
        }
        return out
    }

    // MARK: - Brush stamps (the T1-decided render-pipeline additive leg)

    /// One flattened strip vertex: the WINDOW foot pixel (the falloff
    /// domain is reconstructed in the fragment from [[position]] through
    /// the inverse-content chain — no attribute interpolation error).
    struct StampVertexData {
        var windowPos: SIMD2<Float>
    }

    private static func renderStamps(
        stroke: BrushStroke,
        window: ROI,
        mapper: GeometryPointMapper,
        accumulator: any MTLTexture,
        metal: MetalContext,
        clear: Bool,
        liqGrid: any MTLBuffer
    ) async throws {
        let aspect = aspectOf(mapper)
        let stamps = stampsForStroke(stroke, aspect: aspect)
        guard !stamps.isEmpty else { return }

        // Quad expansion: each stamp's image-space bounding square (padded
        // 1.6× for the non-affine interpolation slack of homography/radial
        // segments) maps FORWARD through the mapper for the window foot.
        let pad = 1.6
        var vertices: [StampVertexData] = []
        vertices.reserveCapacity(stamps.count * 4)
        for stamp in stamps {
            let c = SIMD2<Double>(Double(stamp.imagePos.x), Double(stamp.imagePos.y))
            let rx = Double(stroke.radius) * pad
            let ry = Double(stroke.radius) / aspect * pad
            // strip order: BL, BR, TL, TR
            let corners: [SIMD2<Double>] = [
                c + SIMD2(-rx, -ry), c + SIMD2(rx, -ry),
                c + SIMD2(-rx, ry), c + SIMD2(rx, ry),
            ]
            for corner in corners {
                let composite = mapper.forward(normalized: corner)
                let wpos = SIMD2(
                    composite.x * Double(accumulator.width) - Double(window.x),
                    composite.y * Double(accumulator.height) - Double(window.y))
                vertices.append(StampVertexData(
                    windowPos: SIMD2(Float(wpos.x), Float(wpos.y))))
            }
        }

        var verts = vertices
        guard let vertexBuffer = metal.device.makeBuffer(
            bytes: &verts, length: verts.count * MemoryLayout<StampVertexData>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        var winSize = SIMD2<Float>(Float(accumulator.width), Float(accumulator.height))
        guard let winBuffer = metal.device.makeBuffer(
            bytes: &winSize, length: MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        // Per-instance profile: (cx, cy, radius, hardness) in the IMAGE
        // domain, passed as FLAT varyings; the fragment's weight = (flow,
        // aspect). flow = density; the ERASER is the negative-density
        // stroke (subtractive accumulate). The fragment reconstructs the
        // image point from [[position]] through the raster uniforms — the
        // SAME inverse-content chain the analytic kernel uses.
        var profiles = stamps.map { stamp in
            SIMD4<Float>(stamp.imagePos.x, stamp.imagePos.y, stroke.radius, stroke.hardness)
        }
        guard let profileBuffer = metal.device.makeBuffer(
            bytes: &profiles, length: profiles.count * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        var weight = SIMD4<Float>(stroke.density, Float(aspect), 0, 0)
        guard let weightBuffer = metal.device.makeBuffer(
            bytes: &weight, length: MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }
        var uniforms = MaskRasterUniforms(
            mapper: mapper, window: window,
            form: MaskForm(kind: .brush(stroke)))
        uniforms.window = SIMD4(
            Float(accumulator.width), Float(accumulator.height),
            Float(mapper.outputSize.x), Float(mapper.outputSize.y))
        // shared buffer, bound via setFragmentBuffer (D-T4-2: never setFragmentBytes 176B — ashift race)
        guard let uniformBuffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<MaskRasterUniforms>.stride,
            options: .storageModeShared)
        else { throw MetalError.deviceUnavailable }

        guard let pso = try stampPipeline(metal: metal) else {
            throw MetalError.psoCreationFailed("mask_stamp", nil)
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = accumulator
        rpd.colorAttachments[0].loadAction = clear ? .clear : .load
        if clear {
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        rpd.colorAttachments[0].storeAction = .store
        guard let commandBuffer = metal.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
        else { throw MetalError.deviceUnavailable }
        encoder.setRenderPipelineState(pso)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(winBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(profileBuffer, offset: 0, index: 2)
        encoder.setVertexBuffer(weightBuffer, offset: 0, index: 3)
        // D-T4-2 (ashift-race form): 176B uniforms ride the shared MTLBuffer
        // above — setFragmentBytes would leave the encoder's pointee unowned
        // while the commit below may still be in flight.
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(liqGrid, offset: 0, index: 1)
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: 4,
            instanceCount: stamps.count)
        encoder.endEncoding() // L008: explicit endEncoding precedes commit
        commandBuffer.commit()
    }

    /// The stamp render PSO (the app MetalContext caches compute PSOs only
    /// — the render pipeline is the rasterizer's own, one per device). The
    /// box is the concurrency-safe static holder (Swift 6 strict
    /// concurrency: mutable global state must live in an isolated/ref-cell).
    private static let stampPSOsBox = PSOBox()

    private final class PSOBox: @unchecked Sendable {
        let lock = NSLock()
        var states: [ObjectIdentifier: any MTLRenderPipelineState] = [:]
    }

    private static func stampPipeline(
        metal: MetalContext
    ) throws -> (any MTLRenderPipelineState)? {
        stampPSOsBox.lock.lock()
        defer { stampPSOsBox.lock.unlock() }
        let key = ObjectIdentifier(metal.device)
        if let cached = stampPSOsBox.states[key] { return cached }
        let library = try? metal.device.makeDefaultLibrary(
            bundle: Bundle(for: MetalContextMarker.self))
        guard let vfn = library?.makeFunction(name: "mask_stamp_vertex"),
              let ffn = library?.makeFunction(name: "mask_stamp_fragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = .r32Float
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.one
        let pso = try metal.device.makeRenderPipelineState(descriptor: descriptor)
        stampPSOsBox.states[key] = pso
        return pso
    }

    // MARK: - Stamp generation (D-06-03-T5-1)

    struct Stamp {
        var imagePos: SIMD2<Float> // decode normalized
    }

    /// Cubic-bezier chain → stamps at 0.5·radius spacing (50% overlap —
    /// hard strokes stay continuous). flow = density per stamp; eraser =
    /// the negative-density stroke (D-06-03-T5-1).
    static func stampsForStroke(_ stroke: BrushStroke, aspect: Double) -> [Stamp] {
        func wu(_ p: MaskPoint) -> SIMD2<Double> {
            SIMD2(Double(p.x), Double(p.y) * aspect)
        }
        guard !stroke.points.isEmpty else { return [] }
        if stroke.points.count == 1 {
            let p = stroke.points[0].corner
            return [Stamp(imagePos: SIMD2(p.x, p.y))]
        }
        let radius = max(Double(stroke.radius), 1e-4)
        let spacing = 0.5 * radius
        var centers: [SIMD2<Double>] = []
        for i in 0..<(stroke.points.count - 1) {
            let a = stroke.points[i], b = stroke.points[i + 1]
            let p0 = wu(a.corner), p1 = wu(a.ctrl2), p2 = wu(b.ctrl1), p3 = wu(b.corner)
            let ddx = p3.x - p0.x, ddy = p3.y - p0.y
            let chord = (ddx * ddx + ddy * ddy).squareRoot()
            let steps = max(1, Int(ceil(chord / spacing)))
            for k in 0..<steps {
                let t = Double(k) / Double(steps)
                let mt = 1 - t
                let x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x
                    + 3 * mt * t * t * p2.x + t * t * t * p3.x
                let y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y
                    + 3 * mt * t * t * p2.y + t * t * t * p3.y
                centers.append(SIMD2(x, y))
            }
        }
        let last = stroke.points.last!
        centers.append(wu(last.corner))
        return centers.map { stamp in
            Stamp(imagePos: SIMD2(Float(stamp.x), Float(stamp.y / aspect)))
        }
    }

    // MARK: - Single-form plane (the 06-04 group-combine input leg)

    /// Rasterize ONE form into a plane with only its FORM-INTRINSIC
    /// opacity folded (a brush stroke's own opacity; analytic forms = 1) —
    /// the per-item plane `MaskCombiner.drawnGroupPlane` combines with the
    /// ITEM opacity at combine time (dt `_group_get_mask_roi`: the form's
    /// own mask build, then `opacity` inside the combine functions).
    /// No layer opacity here — the assembled plane folds it once.
    public static func singleFormPlane(
        form: MaskForm,
        window: ROI,
        mapper: GeometryPointMapper,
        metal: MetalContext
    ) async throws -> any MTLTexture {
        let spec = MaskSpec(drawn: DrawnMaskSpec(forms: [form]))
        return try await render(
            spec: spec, layerOpacity: 1, window: window,
            mapper: mapper, metal: metal, rowBands: 1)
    }

    // MARK: - Display leg (T7; dt blendop_display_channel semantics)

    /// Tint a display plane where the mask plane is set (the dt
    /// `blendop_display_channel` leg, blendop.cl:1474+): a fresh COPY is
    /// returned — the cached display plane is never mutated (write-once
    /// contract). `tint` is in the DISPLAY TEXTURE's own channel order
    /// (a .bgra8Unorm display plane takes (0, 1, 1) for yellow: B and G
    /// channels up, R down). The UI toggle + selected-layer routing land
    /// in 6-5; this is the render leg.
    public static func overlay(
        display: sending any MTLTexture,
        mask: sending any MTLTexture,
        strength: Float,
        tint: SIMD3<Float>,
        metal: MetalContext
    ) async throws -> sending any MTLTexture {
        precondition(
            display.width == mask.width && display.height == mask.height,
            "overlay: mask plane \\(mask.width)x\\(mask.height) != display \\(display.width)x\\(display.height)")
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: display.pixelFormat, width: display.width,
            height: display.height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let output = metal.device.makeTexture(descriptor: d) else {
            throw MetalError.bufferAllocationFailed(display.width * display.height * 4)
        }
        var params = SIMD4<Float>(strength, tint.x, tint.y, tint.z)
        let session = try await metal.makeEncoder(functionName: "mask_overlay_display")
        session.encoder.setTexture(display, index: 0)
        session.encoder.setTexture(mask, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return output
    }

    // MARK: - Fold (saturate + premultiply)

    private static func fold(
        accumulator: any MTLTexture,
        final: any MTLTexture,
        opacity: Float,
        rowBands: Int,
        metal: MetalContext
    ) async throws {
        let bands = rowBands > 1 ? rowBands : 1
        let rows = accumulator.height
        let perBand = Int(ceil(Double(rows) / Double(bands)))
        var start = 0
        while start < rows {
            let end = min(rows, start + perBand)
            var params = SIMD4<Float>(opacity, Float(start), Float(end), 0)
            let session = try await metal.makeEncoder(functionName: "mask_fold")
            session.encoder.setTexture(accumulator, index: 0)
            session.encoder.setTexture(final, index: 1)
            session.encoder.setBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            session.encoder.dispatchThreads(
                MTLSize(width: final.width, height: final.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding()
            session.commandBuffer.commit()
            start = end
        }
    }
}
