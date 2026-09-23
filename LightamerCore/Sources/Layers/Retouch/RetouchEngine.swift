import Foundation
import Metal

// ─────────────────────────────────────────────────────────────────────────────
// RetouchEngine (Plan 06-07 T2/T3) — the stroke-application pipeline behind
// the retouch layer's composite leg. One layer render = the STROKES applied
// in order over the evolving input plane (dt `rt_process_forms` form order,
// retouch.c); the layer's blend triple then composites the result like any
// adjustment layer (the driver owns that part).
//
// Per stroke (dt `_retouch_clone`/`_retouch_blur`/`_retouch_fill`/`_retouch_heal`):
//   1. the stroke's MaskForm shape rasterizes into a window-sized
//      PREMULTIPLIED effective-opacity plane through the 06-03 drawn-mask
//      rasterizer (content-anchored — the stroke's mask IS the shape);
//   2. the algorithm builds its replacement content (clone: the evolving
//      plane sampled at the source offset; blur: a CROP of the stroke bbox
//      through `GaussianBlur`; fill: the constant; heal: the T3 Laplacian
//      patch solve) — the crop keeps patch work O(patch), dt's
//      `roi_mask_scaled` shape;
//   3. `retouch_apply` masked-pastes: out = below·(1−m) + replacement·m.
//
// Kernel ABI single source: `RetouchKernels.metal` (the MSL structs); the
// Swift mirrors here pin the same field order.
// ─────────────────────────────────────────────────────────────────────────────

/// Swift mirror of the MSL `RetouchApplyUniforms` (chunk-packed identically).
struct RetouchApplyUniforms {
    var fillColor: SIMD4<Float>
    var sampleOffsetPx: SIMD2<Float>
    var altOriginPx: SIMD2<Float>
    var mode: UInt32
    var altIsWindow: UInt32
    var _pad: (UInt32, UInt32) = (0, 0)

    init(mode: UInt32, fillColor: SIMD4<Float> = .zero,
         sampleOffsetPx: SIMD2<Float> = .zero, altOriginPx: SIMD2<Float> = .zero,
         altIsWindow: Bool = false) {
        self.mode = mode
        self.fillColor = fillColor
        self.sampleOffsetPx = sampleOffsetPx
        self.altOriginPx = altOriginPx
        self.altIsWindow = altIsWindow ? 1 : 0
    }
}

/// Swift mirror of the MSL `HealStepUniforms`.
struct HealStepUniforms {
    var w: Float
    var _pad0: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
    var size: SIMD2<UInt32>
    var parity: UInt32
    var _pad3: UInt32 = 0
}

public enum RetouchEngine {

    /// dt `max_heal_iter` default (retouch.c:117 — $DEFAULT 2000).
    public static let maxHealIterations = 2000

    /// The SOR error readback batch: reset-accumulate-read ONCE per this
    /// many HALF-steps (each read = a fence sync, L014 — per-step syncs
    /// would dominate the patch latency; the batched threshold scales the
    /// exit bound linearly).
    static let healErrorBatch = 25

    // MARK: - Hashing (StableHash ONLY — L013)

    /// The stroke list's identity hash: canonical JSON (sortedKeys) bytes ⊕
    /// StableHash — the same canonical-bytes discipline as the 06-03
    /// maskVersionHash (a stroke edit flips exactly this, the leg's cache
    /// key, and every composite prefix above the layer).
    public static func strokeListHash(_ strokes: [RetouchStroke]) -> UInt64 {
        guard !strokes.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(strokes) else { return 0 }
        var hash = StableHash.fnvOffsetBasis
        hash = data.withUnsafeBytes { StableHash.combine(hash, $0) }
        return hash
    }

    // MARK: - Geometry (ROI extension — the source ∪ target AABB seam)

    /// The stroke shape's ANCHOR in decode-normalized coordinates (the
    /// clone/heal source translation reference).
    static func formAnchor(_ form: MaskForm) -> SIMD2<Double> {
        switch form.kind {
        case let .ellipse(e): return SIMD2(Double(e.center.x), Double(e.center.y))
        case let .path(p):
            guard !p.nodes.isEmpty else { return .zero }
            var sum = SIMD2<Double>.zero
            for node in p.nodes {
                sum += SIMD2(Double(node.corner.x), Double(node.corner.y))
            }
            return sum / Double(p.nodes.count)
        case .brush, .gradient: return .zero
        }
    }

    /// The stroke shape's conservative HALF-EXTENT in decode-normalized
    /// units (the 1.25 safety factor absorbs lens aspect stretch — the
    /// crop is a compute bound, the mask plane is exact).
    static func formHalfExtent(_ form: MaskForm) -> SIMD2<Double> {
        let margin = 1.25
        switch form.kind {
        case let .ellipse(e):
            return SIMD2(
                Double(e.radiusX) * margin + 0.01,
                Double(e.radiusY) * margin + 0.01)
        case let .path(p):
            guard !p.nodes.isEmpty else { return SIMD2(0.01, 0.01) }
            var lo = SIMD2<Double>(repeating: Double.greatestFiniteMagnitude)
            var hi = -lo
            for node in p.nodes {
                for point in [node.corner, node.ctrl1, node.ctrl2] {
                    lo = SIMD2(min(lo.x, Double(point.x)), min(lo.y, Double(point.y)))
                    hi = SIMD2(max(hi.x, Double(point.x)), max(hi.y, Double(point.y)))
                }
            }
            let center = (lo + hi) / 2
            return (hi - center) * margin + 0.01
        case .brush, .gradient: return SIMD2(0.01, 0.01)
        }
    }

    /// The SOURCE ∪ TARGET extent of a stroke set, in composite-frame
    /// PIXELS (D-06-07-T2-2): every clone/heal source patch must be inside
    /// the composite render region or the paste reads invented pixels (the
    /// 源区黑边 red line). nil when no stroke carries a source.
    /// The caller unions this into the window/hint BEFORE the base run.
    public static func strokeExtent(
        strokes: [RetouchStroke], mapper: GeometryPointMapper
    ) -> (min: SIMD2<Double>, max: SIMD2<Double>)? {
        var lo = SIMD2<Double>(repeating: Double.greatestFiniteMagnitude)
        var hi = -lo
        var any = false
        for stroke in strokes {
            let half = formHalfExtent(stroke.form)
            var centers: [SIMD2<Double>] = [formAnchor(stroke.form)]
            if let source = stroke.source {
                centers.append(SIMD2(Double(source.x), Double(source.y)))
            }
            for center in centers {
                // Project the anchor (content-anchored, D-06-CONTEXT-7) and
                // express the extent in composite pixels.
                let projected = mapper.forward(normalized: center) * mapper.outputSize
                let delta = half * mapper.outputSize
                lo = SIMD2(min(lo.x, projected.x - delta.x), min(lo.y, projected.y - delta.y))
                hi = SIMD2(max(hi.x, projected.x + delta.x), max(hi.y, projected.y + delta.y))
                any = true
            }
        }
        return any ? (lo, hi) : nil
    }

    // MARK: - Stroke application (the layer leg)

    /// The whole layer: strokes applied in order over `input`. Returns the
    /// new plane + the number of GPU dispatches performed (the accounting
    /// seam). Stroke order = array order (dt form order).
    public static func applyStrokes(
        _ layer: RetouchLayer,
        input: any MTLTexture,
        window: ROI,
        mapper: GeometryPointMapper,
        cache: PipeCache,
        imageID: UUID,
        pipeType: PipeResolution,
        metal: MetalContext
    ) async throws -> (output: any MTLTexture, dispatches: Int) {
        var current = input
        var dispatches = 0
        for stroke in layer.strokes {
            guard RetouchStroke.isAllowedShape(stroke.form.kind) else { continue }
            // Degenerate path guard (an empty lasso rasterizes nothing).
            if case let .path(p) = stroke.form.kind, p.nodes.count < 2 { continue }

            // 1. the stroke mask plane (cached per form ⊕ mapper ⊕ roi —
            //    the same plane cache/tier the 06-03 masks use).
            let spec = MaskSpec(
                version: 1, drawn: DrawnMaskSpec(forms: [stroke.form]),
                parametric: nil, raster: nil)
            let (maskPlane, _) = try await DrawnMaskRasterizer.plane(
                spec: spec, layerOpacity: max(0, min(1, stroke.opacity)),
                window: window, mapper: mapper, metal: metal, cache: cache,
                imageID: imageID, pipeType: pipeType, layerID: layer.id)

            // 2+3. replacement content + masked paste.
            let (out, count) = try await apply(
                stroke, to: current, mask: maskPlane, window: window,
                mapper: mapper, metal: metal)
            current = out
            dispatches += count
        }
        return (current, dispatches)
    }

    /// One stroke → replacement content + masked paste.
    static func apply(
        _ stroke: RetouchStroke,
        to below: any MTLTexture,
        mask: any MTLTexture,
        window: ROI,
        mapper: GeometryPointMapper,
        metal: MetalContext
    ) async throws -> (output: any MTLTexture, dispatches: Int) {
        switch stroke.algorithm {
        case .clone:
            let offset = sourceOffset(stroke, mapper: mapper)
            return try await paste(
                below: below, alt: below, mask: mask,
                uniforms: RetouchApplyUniforms(
                    mode: 0, sampleOffsetPx: offset, altIsWindow: true),
                metal: metal)
        case .fill:
            let color = stroke.fillColor ?? .zero
            return try await paste(
                below: below, alt: below, mask: mask,
                uniforms: RetouchApplyUniforms(mode: 1, fillColor: SIMD4(color, 1)),
                metal: metal)
        case .blur:
            let sigma = max(0.1, stroke.blurRadius ?? 10.0)
            let crop = try await blurredCrop(
                below: below, stroke: stroke, window: window,
                mapper: mapper, sigma: sigma, metal: metal)
            return try await paste(
                below: below, alt: crop.texture, mask: mask,
                uniforms: RetouchApplyUniforms(
                    mode: 0, altOriginPx: SIMD2(
                        Float(crop.originInWindow.x), Float(crop.originInWindow.y))),
                metal: metal)
        case .heal:
            let result = try await healPatch(
                below: below, stroke: stroke, mask: mask, window: window,
                mapper: mapper, metal: metal)
            return try await paste(
                below: below, alt: result.texture, mask: mask,
                uniforms: RetouchApplyUniforms(
                    mode: 0, altOriginPx: SIMD2(
                        Float(result.originInWindow.x), Float(result.originInWindow.y))),
                metal: metal)
        }
    }

    /// The clone/heal source offset in WINDOW pixels: (source center −
    /// target anchor), both projected content-anchored (dt's (dx,dy)
    /// source delta, retouch.c:2999-3034 — translation-only v1).
    static func sourceOffset(
        _ stroke: RetouchStroke, mapper: GeometryPointMapper
    ) -> SIMD2<Float> {
        guard let source = stroke.source else { return .zero }
        let target = mapper.forward(normalized: formAnchor(stroke.form)) * mapper.outputSize
        let src = mapper.forward(normalized: SIMD2(Double(source.x), Double(source.y)))
            * mapper.outputSize
        return SIMD2(Float(src.x - target.x), Float(src.y - target.y))
    }

    // MARK: - blur / heal patch legs

    /// Swift mirror of the MSL `RetouchBlurUniforms` (48-byte layout — the
    /// MaskCombiner.BlurUniforms shape; the coefficients ride the SAME-SOURCE
    /// Deriche derivation pinned against LightamerIOP by a cross-check test).
    struct BlurUniforms {
        var a0: Float, a1: Float, a2: Float, a3: Float
        var b1: Float, b2: Float, coefp: Float, coefn: Float
        var width: UInt32
        var height: UInt32
        var rowEnd: UInt32
        private var _pad: UInt32 = 0
    }

    /// The RGBA 3-pass Deriche blur over a crop (dt `dt_gaussian_blur_4c`
    /// shape — the `retouch_blur_col/row/store` kernels; Core cannot import
    /// LightamerIOP's `GaussianBlur`, the MaskCombiner precedent applies).
    static func rgbaBlur(
        input: any MTLTexture, sigma: Float, metal: MetalContext
    ) async throws -> any MTLTexture {
        if sigma <= 0 { return input } // the IIR degenerates at sigma 0
        let w = input.width, h = input.height
        let output = try makePlane(
            width: w, height: h, usage: [.shaderRead, .shaderWrite], metal: metal)
        let planeBytes = w * h * MemoryLayout<Float>.stride * 4
        guard let planes = metal.device.makeBuffer(
            length: planeBytes * 2, options: .storageModeShared) else {
            throw MetalError.bufferAllocationFailed(planeBytes * 2)
        }
        let c = MaskCombiner.maskGaussCoeffs(sigma: sigma)
        var uniforms = BlurUniforms(
            a0: c.a0, a1: c.a1, a2: c.a2, a3: c.a3,
            b1: c.b1, b2: c.b2, coefp: c.coefp, coefn: c.coefn,
            width: UInt32(w), height: UInt32(h), rowEnd: UInt32.max)

        // Pass 1 — columns (texture → plane half 0).
        let col = try await metal.makeEncoder(functionName: "retouch_blur_col")
        var colUniforms = uniforms
        col.encoder.setTexture(input, index: 0)
        col.encoder.setBytes(&colUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
        col.encoder.setBuffer(planes, offset: 0, index: 1)
        col.encoder.dispatchThreads(
            MTLSize(width: w, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(256, col.pipelineState.maxTotalThreadsPerThreadgroup),
                height: 1, depth: 1))
        col.encoder.endEncoding()
        col.commandBuffer.commit()

        // Pass 2 — rows (plane 0 → plane 1; two planes, no aliasing).
        let row = try await metal.makeEncoder(functionName: "retouch_blur_row")
        var rowUniforms = uniforms
        row.encoder.setBuffer(planes, offset: 0, index: 0)
        row.encoder.setBuffer(planes, offset: planeBytes, index: 1)
        row.encoder.setBytes(&rowUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 2)
        row.encoder.dispatchThreads(
            MTLSize(width: h, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: min(256, row.pipelineState.maxTotalThreadsPerThreadgroup),
                height: 1, depth: 1))
        row.encoder.endEncoding()
        row.commandBuffer.commit()

        // Pass 3 — store (plane 1 → texture).
        let store = try await metal.makeEncoder(functionName: "retouch_blur_store")
        var storeUniforms = uniforms
        store.encoder.setBuffer(planes, offset: planeBytes, index: 0)
        store.encoder.setBytes(&storeUniforms, length: MemoryLayout<BlurUniforms>.stride, index: 1)
        store.encoder.setTexture(output, index: 0)
        store.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        store.encoder.endEncoding()
        store.commandBuffer.commit()
        return output
    }

    /// Gaussian-blur a crop of the stroke bbox (dt `_retouch_blur`:
    /// dt_gaussian_blur_4c over roi_mask_scaled — the crop keeps the
    /// FULL-fit working set O(patch); blurring the whole plane instead
    /// would allocate 2 extra 1.63GB planes and break the ≤3GB budget).
    static func blurredCrop(
        below: any MTLTexture, stroke: RetouchStroke, window: ROI,
        mapper: GeometryPointMapper, sigma: Float, metal: MetalContext
    ) async throws -> (texture: any MTLTexture, originInWindow: SIMD2<Int>) {
        let halo = Double(ceil(sigma * 3)) + 2
        let rect = patchRect(stroke, window: window, mapper: mapper, halo: halo)
        let crop = try blitCrop(
            from: below, pixelFormat: WorkingSpace.pixelFormat, rect: rect, metal: metal)
        let out = try await rgbaBlur(input: crop, sigma: sigma, metal: metal)
        return (out, SIMD2(Int(rect.origin.x), Int(rect.origin.y)))
    }

    /// The heal leg (T3): dt `_retouch_heal` (retouch.c:3665-3698) —
    /// source/target patch pair → `dt_heal` solve → masked paste of the
    /// healed patch. Returns the healed PATCH (the caller pastes it).
    static func healPatch(
        below: any MTLTexture, stroke: RetouchStroke, mask: any MTLTexture,
        window: ROI, mapper: GeometryPointMapper, metal: MetalContext
    ) async throws -> (texture: any MTLTexture, originInWindow: SIMD2<Int>) {
        let rect = patchRect(stroke, window: window, mapper: mapper, halo: 2)
        let offset = sourceOffset(stroke, mapper: mapper)

        // The patch pair (dt rt_copy_in_to_out at (0,0) and (dx,dy)).
        let targetCrop = try blitCrop(
            from: below, pixelFormat: WorkingSpace.pixelFormat, rect: rect, metal: metal)
        // Source rect clamped into the plane (frame-edge strokes sample the
        // nearest valid origin — dt's roi clamps, retouch.c:3057-3060).
        let srcOriginX = min(
            max(0, rect.origin.x + Double(offset.x)),
            Double(below.width - Int(rect.width)))
        let srcOriginY = min(
            max(0, rect.origin.y + Double(offset.y)),
            Double(below.height - Int(rect.height)))
        let sourceCrop = try blitCrop(
            from: below, pixelFormat: WorkingSpace.pixelFormat,
            rect: CGRect(x: srcOriginX, y: srcOriginY, width: rect.width, height: rect.height),
            metal: metal)
        let maskCrop = try blitCrop(
            from: mask, pixelFormat: .r32Float, rect: rect, metal: metal)

        let healed = try await healSolve(
            target: targetCrop, source: sourceCrop, mask: maskCrop, metal: metal)
        return (healed, SIMD2(Int(rect.origin.x), Int(rect.origin.y)))
    }

    /// `dt_heal` (heal.c:354-422): pattern = target − source (`_heal_sub`),
    /// red/black SOR Laplacian to convergence (`_heal_laplace_loop`),
    /// healed = source + solution (`_heal_add`). GPU single-step dispatch +
    /// CPU iteration loop; the early exit reads the batched atomic error
    /// (L014: every readback after a committed + waited buffer).
    static func healSolve(
        target: any MTLTexture, source: any MTLTexture,
        mask: any MTLTexture, metal: MetalContext
    ) async throws -> any MTLTexture {
        let w = target.width, h = target.height
        var a = try makePlane(width: w, height: h, usage: [.shaderRead, .shaderWrite], metal: metal)
        var b = try makePlane(width: w, height: h, usage: [.shaderRead, .shaderWrite], metal: metal)

        // pattern = target − source, into BOTH ping-pong planes (the second
        // leg copies — an untouched pass-through writes it anyway, but the
        // first black sweep must read a valid pattern; explicit copy).
        try await dispatchBinary("heal_subtract", top: target, bottom: source, out: a, metal: metal)
        try await dispatchBinary("heal_subtract", top: target, bottom: source, out: b, metal: metal)

        // The SOR factor (heal.c:380): w = (2 − 1/(0.1575·√nmask + 0.8))·¼
        // from the ACTIVE (masked) cell count.
        let nmask = try await Self.activeMaskCount(mask: mask, metal: metal)
        let wFactor = nmask > 0
            ? (2.0 - 1.0 / (0.1575 * sqrt(Float(nmask)) + 0.8)) * 0.25
            : 0.25
        // err_exit = ε²·w² with ε = 0.1/255 (heal.c:384-386).
        let errExit = powf(0.1 / 255.0 * wFactor, 2)

        guard let errBuffer = metal.device.makeBuffer(length: MemoryLayout<Float>.stride) else {
            throw MetalError.bufferAllocationFailed(MemoryLayout<Float>.stride)
        }

        var iterations = 0
        var converged = false
        while iterations < maxHealIterations && !converged {
            let batch = min(Self.healErrorBatch, Self.maxHealIterations - iterations)
            try await fillZero(errBuffer, metal: metal)
            for _ in 0..<batch {
                try await healStep(
                    in: a, out: b, mask: mask, parity: 0, w: wFactor,
                    errBuffer: errBuffer, metal: metal)
                try await healStep(
                    in: b, out: a, mask: mask, parity: 1, w: wFactor,
                    errBuffer: errBuffer, metal: metal)
                iterations += 1
            }
            // dt compares per-iteration err = red + black residual against
            // err_exit (heal.c:392-396). The batch sums the SAME quantity
            // for `batch` iterations into one accumulator — the AVERAGE
            // per-iteration residual gates the exit (lag ≤ 1 batch, the
            // DECISIONS note).
            let average = try await readScalar(errBuffer, metal: metal) / Float(batch)
            if average < errExit { converged = true }
        }
        // healed = source + solution (`_heal_add`).
        let healed = try makePlane(width: w, height: h, usage: [.shaderRead, .shaderWrite], metal: metal)
        try await dispatchBinary("heal_add", top: a, bottom: source, out: healed, metal: metal)
        return healed
    }

    /// Batch-exit bookkeeping hook (kept explicit for the DECISIONS note —
    /// the batch loop's error gate compares the LAST half-step residual
    /// against errExit, matching dt's per-iteration `err < err_exit` within
    /// a factor the parity sweep conserves).
    static func batchExitGuard(_ iterations: Int) -> Int { iterations }

    /// One parity half-step dispatch (`heal_laplace_step`). FIFO queue
    /// ordering chains the ping-pong (the GaussianBlur pass pattern) — the
    /// error accumulator rides buffer 1.
    static func healStep(
        in input: any MTLTexture, out: any MTLTexture, mask: any MTLTexture,
        parity: UInt32, w: Float, errBuffer: any MTLBuffer, metal: MetalContext
    ) async throws {
        var u = HealStepUniforms(
            w: w, size: SIMD2(UInt32(input.width), UInt32(input.height)), parity: parity)
        let session = try await metal.makeEncoder(functionName: "heal_laplace_step")
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(mask, index: 1)
        session.encoder.setTexture(out, index: 2)
        session.encoder.setBytes(&u, length: MemoryLayout<HealStepUniforms>.stride, index: 0)
        session.encoder.setBuffer(errBuffer, offset: 0, index: 1)
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    // MARK: - shared plumbing

    /// One masked-paste dispatch (`retouch_apply`).
    static func paste(
        below: any MTLTexture,
        alt: any MTLTexture,
        mask: any MTLTexture,
        uniforms: RetouchApplyUniforms,
        metal: MetalContext
    ) async throws -> (any MTLTexture, Int) {
        let out = try makePlane(
            width: below.width, height: below.height,
            usage: [.shaderRead, .shaderWrite], metal: metal)
        var u = uniforms
        let session = try await metal.makeEncoder(functionName: "retouch_apply")
        session.encoder.setTexture(below, index: 0)
        session.encoder.setTexture(alt, index: 1)
        session.encoder.setTexture(mask, index: 2)
        session.encoder.setTexture(out, index: 3)
        session.encoder.setBytes(&u, length: MemoryLayout<RetouchApplyUniforms>.stride, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: out.width, height: out.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
        return (out, 1)
    }

    /// One trivial binary kernel dispatch (heal_subtract/heal_add).
    static func dispatchBinary(
        _ function: String, top: any MTLTexture, bottom: any MTLTexture,
        out: any MTLTexture, metal: MetalContext
    ) async throws {
        let session = try await metal.makeEncoder(functionName: function)
        session.encoder.setTexture(top, index: 0)
        session.encoder.setTexture(bottom, index: 1)
        session.encoder.setTexture(out, index: 2)
        session.encoder.dispatchThreads(
            MTLSize(width: out.width, height: out.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    static func makePlane(
        width: Int, height: Int, pixelFormat: MTLPixelFormat = WorkingSpace.pixelFormat,
        usage: MTLTextureUsage, metal: MetalContext
    ) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        d.usage = usage
        d.storageMode = .shared
        guard let t = metal.device.makeTexture(descriptor: d) else {
            throw MetalError.bufferAllocationFailed(width * height * 4)
        }
        return t
    }

    /// A blit copy of `rect` (in `src` pixel coords) into a fresh texture.
    static func blitCrop(
        from src: any MTLTexture, pixelFormat: MTLPixelFormat,
        rect: CGRect, metal: MetalContext
    ) throws -> any MTLTexture {
        let w = max(1, Int(rect.width)), h = max(1, Int(rect.height))
        let dst = try makePlane(
            width: w, height: h, pixelFormat: pixelFormat,
            usage: [.shaderRead, .shaderWrite], metal: metal)
        guard let cb = metal.commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: src, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: Int(rect.origin.x), y: Int(rect.origin.y), z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: dst, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit()
        return dst
    }

    /// Blit-fill a buffer with zero bytes (the error accumulator reset).
    static func fillZero(_ buffer: any MTLBuffer, metal: MetalContext) throws {
        guard let cb = metal.commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else {
            throw MetalError.deviceUnavailable
        }
        blit.__fill(buffer, range: NSRange(location: 0, length: buffer.length), value: 0)
        blit.endEncoding()
        cb.commit()
    }

    /// Fence + read one Float from a shared-storage buffer (L014: the read
    /// happens only after `waitUntilCompleted`).
    static func readScalar(_ buffer: any MTLBuffer, metal: MetalContext) async throws -> Float {
        guard let cb = metal.commandQueue.makeCommandBuffer() else {
            throw MetalError.deviceUnavailable
        }
        cb.commit()
        await cb.completed()
        let value = buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee
        return value
    }

    /// The stroke's patch rect in WINDOW pixel coords (+ halo margin),
    /// clamped into the window. The blur/heal patch (dt `roi_mask_scaled`).
    static func patchRect(
        _ stroke: RetouchStroke, window: ROI, mapper: GeometryPointMapper,
        halo: Double
    ) -> CGRect {
        let anchor = mapper.forward(normalized: formAnchor(stroke.form)) * mapper.outputSize
        let half = formHalfExtent(stroke.form) * mapper.outputSize + SIMD2(halo, halo)
        let origin = anchor - half - SIMD2(Double(window.x), Double(window.y))
        let size = half * 2
        let x0 = max(0, origin.x), y0 = max(0, origin.y)
        let x1 = min(Double(window.width), origin.x + size.x)
        let y1 = min(Double(window.height), origin.y + size.y)
        return CGRect(
            x: x0, y: y0,
            width: max(1, x1 - x0), height: max(1, y1 - y0))
    }

    /// The ACTIVE (masked) cell count of a patch mask plane — one fenced
    /// CPU readback of the small r32Float patch (feeds heal.c:380's SOR
    /// factor; L014 fence discipline).
    static func activeMaskCount(
        mask: any MTLTexture, metal: MetalContext
    ) async throws -> Int {
        guard let cb = metal.commandQueue.makeCommandBuffer() else {
            throw MetalError.deviceUnavailable
        }
        cb.commit()
        await cb.completed()
        let count = mask.width * mask.height
        var bytes = [Float](repeating: 0, count: count)
        bytes.withUnsafeMutableBytes {
            mask.getBytes(
                $0.baseAddress!, bytesPerRow: mask.width * MemoryLayout<Float>.stride,
                from: MTLRegionMake2D(0, 0, mask.width, mask.height), mipmapLevel: 0)
        }
        return bytes.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
    }
}
