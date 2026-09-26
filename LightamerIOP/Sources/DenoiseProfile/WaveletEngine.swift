import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// WaveletEngine (Plan 05-07-T3) — the denoiseprofile band-loop orchestrator
// and the NLMeans-leg driver. Mirrors:
//   - process_wavelets (denoiseprofile.c:1423-1658, the CPU FORM — the
//     dt-cli authority path): precondition → per-band {decompose → reduce
//     sum_y2 → Bayesshrink (CPU) → synthesize-accumulate} → residue fold →
//     backtransform. The band accumulator is a ZEROED device float4 BUFFER
//     (dt zeroes `out` at :1556 then accumulates) — the L018-legal RMW
//     surface; the chain planes double-buffer as read→write texture PAIRS
//     (decompose reads buf1, writes coarse→buf2 + detail; swap :1574-1576).
//   - process_nlmeans (_cl, :1975-2255): VST precondition → Goossens offset
//     loop reusing the 05-06 nlmeans kernels VERBATIM (dist with
//     norm2=(1,1,1), horiz, accu — dt shares the same Goossens structure
//     across both programs) + the denoiseprofile vert variant (single-
//     pixel distance boost + central weight + norm−2, denoiseprofile.cl:
//     197-252) → finish/finish_v2 (fused backtransform).
// Per-band sum_y2 readback fences (L014) — dt reads dev_r back per band
// too (:2433).
// ─────────────────────────────────────────────────────────────────────────

enum WaveletEngine {

    /// Per-run working set (per-size cached by the module): two chain
    /// planes + one detail plane (textures, read+write usage — never the
    /// SAME texture on both sides of an encoder) + the float4 accumulator
    /// + the reduce partials/result buffers.
    struct Scratch {
        let chainA: any MTLTexture
        let chainB: any MTLTexture
        let detail: any MTLTexture
        let residue: any MTLTexture
        let accu: any MTLBuffer
        let partials: any MTLBuffer
        let sumY2: any MTLBuffer
        let filter: any MTLBuffer       // 25-float B3 a-trous base (host-built)
        let matrixFwd: any MTLBuffer    // 9-float toY0U0V0 (contents per run)
        let matrixInv: any MTLBuffer    // 9-float toRGB
        let nlPlane: any MTLTexture   // NLMeans leg: the VST plane (dist input)
        let nlBuckets: any MTLBuffer  // 4 single-channel buckets (dt NUM_BUCKETS)
        let nlU2: any MTLBuffer       // float4 accumulator
        let width: Int
        let height: Int
        let planeBytes: Int
    }

    static func makeScratch(
        width: Int, height: Int, metal: MetalContext
    ) throws -> Scratch {
        func plane(_ usage: MTLTextureUsage) throws -> any MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: width, height: height,
                mipmapped: false)
            d.usage = usage
            d.storageMode = .shared
            guard let t = metal.device.makeTexture(descriptor: d) else {
                throw MetalError.bufferAllocationFailed(width * height * 16)
            }
            return t
        }
        let readWrite: MTLTextureUsage = [.shaderRead, .shaderWrite]
        let planeBytes = width * height * MemoryLayout<Float>.size
        guard
            let accu = metal.device.makeBuffer(
                length: planeBytes * 4, options: .storageModeShared),
            let partials = metal.device.makeBuffer(
                length: groupCount(width, height) * 16, options: .storageModeShared),
            let sumY2 = metal.device.makeBuffer(
                length: 16, options: .storageModeShared),
            let filter = metal.device.makeBuffer(
                length: 25 * MemoryLayout<Float>.size, options: .storageModeShared),
            let matrixFwd = metal.device.makeBuffer(
                length: 9 * MemoryLayout<Float>.size, options: .storageModeShared),
            let matrixInv = metal.device.makeBuffer(
                length: 9 * MemoryLayout<Float>.size, options: .storageModeShared),
            let nlBuckets = metal.device.makeBuffer(
                length: planeBytes * 4 * 4, options: .storageModeShared),
            let nlU2 = metal.device.makeBuffer(
                length: planeBytes * 4, options: .storageModeShared)
        else {
            throw MetalError.bufferAllocationFailed(planeBytes * 14)
        }
        FilterB3.filter25.withUnsafeBytes {
            filter.contents().copyMemory(
                from: $0.baseAddress!, byteCount: 25 * MemoryLayout<Float>.size)
        }
        return Scratch(
            chainA: try plane(readWrite), chainB: try plane(readWrite),
            detail: try plane(readWrite), residue: try plane(readWrite),
            accu: accu, partials: partials, sumY2: sumY2,
            filter: filter, matrixFwd: matrixFwd, matrixInv: matrixInv,
            nlPlane: try plane(readWrite), nlBuckets: nlBuckets, nlU2: nlU2,
            width: width, height: height, planeBytes: planeBytes)
    }

    private static func groupCount(_ w: Int, _ h: Int) -> Int {
        ((w + 15) / 16) * ((h + 15) / 16)
    }

    // MARK: - Wavelets leg (T3)

    /// The full wavelets chain. `vst`/`backtransform`/`thrsAt` closures come
    /// from the module (mode/color-mode/uniforms resolved per commit);
    /// `force` rides along for Bayesshrink. Band count = the caller-derived
    /// maxScale (the 20% rule on the RUN-level dscIn — tile-stable, L021).
    static func wavelets(
        input: any MTLTexture,
        output: any MTLTexture,
        maxScale: Int,
        useNewVST: Bool,
        colorModeRGB: Bool,
        vst: VSTUniforms,
        force: [[Float]],
        npixels: Int,
        metal: MetalContext,
        scratch: Scratch
    ) async throws {
        let width = input.width
        let height = input.height

        // Pass 0 — the variance-stabilizing transform (precondition trio).
        // The Y0U0V0 matrices ride to the GPU in the per-run scratch
        // buffers (shared storage: host write precedes every GPU command).
        if let fwd = vst.matrixY0U0V0, let inv = vst.matrixToRGB {
            fwd.withUnsafeBytes {
                scratch.matrixFwd.contents().copyMemory(
                    from: $0.baseAddress!, byteCount: 9 * MemoryLayout<Float>.size)
            }
            inv.withUnsafeBytes {
                scratch.matrixInv.contents().copyMemory(
                    from: $0.baseAddress!, byteCount: 9 * MemoryLayout<Float>.size)
            }
        }
        switch (useNewVST, colorModeRGB) {
        case (false, _):
            try await preconditionLegacy(input: input, to: scratch.chainA,
                                         width: width, height: height,
                                         vst: vst, metal: metal)
        case (true, true):
            try await preconditionV2(input: input, to: scratch.chainA,
                                     width: width, height: height,
                                     vst: vst, metal: metal, y0u0v0: false,
                                     matrixFwd: scratch.matrixFwd)
        case (true, false):
            try await preconditionV2(input: input, to: scratch.chainA,
                                     width: width, height: height,
                                     vst: vst, metal: metal, y0u0v0: true,
                                     matrixFwd: scratch.matrixFwd)
        }

        // Zero the band accumulator ONCE (dt :1556 dt_iop_image_fill 0).
        memset(scratch.accu.contents(), 0, width * height * 16)

        var buf1 = scratch.chainA
        var buf2 = scratch.chainB
        let varf = (Float(70.0)).squareRoot() / 16.0 // dt :1561 "about 0.5"

        for s in 0..<maxScale {
            let sigmaBand = pow(varf, Float(s))
            let invSigma2 = 1.0 / (sigmaBand * sigmaBand)

            // decompose: buf1 → coarse(buf2) + detail (25-tap edge-aware).
            var params = DNDecomposeParams(
                width: UInt32(width), height: UInt32(height),
                scale: UInt32(s), inv_sigma2: invSigma2)
            let dec = try await metal.makeEncoder(
                functionName: DenoiseProfileKernel.decompose)
            dec.encoder.setTexture(buf1, index: 0)
            dec.encoder.setTexture(buf2, index: 1)
            dec.encoder.setTexture(scratch.detail, index: 2)
            dec.encoder.setBytes(&params, length: MemoryLayout<DNDecomposeParams>.stride, index: 0)
            dec.encoder.setBuffer(scratch.filter, offset: 0, index: 1)
            dec.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            dec.encoder.endEncoding()
            dec.commandBuffer.commit()

            // reduce: sum of squares of the UN-thresholded detail.
            var rparams = DNReduceFirstParams(width: UInt32(width), height: UInt32(height))
            let r1 = try await metal.makeEncoder(
                functionName: DenoiseProfileKernel.reduceFirst)
            r1.encoder.setTexture(scratch.detail, index: 0)
            r1.encoder.setBuffer(scratch.partials, offset: 0, index: 0)
            r1.encoder.setBytes(&rparams, length: MemoryLayout<DNReduceFirstParams>.stride, index: 1)
            r1.encoder.setThreadgroupMemoryLength(16 * 16 * 16, index: 0)
            r1.encoder.dispatchThreadgroups(
                MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            r1.encoder.endEncoding()
            r1.commandBuffer.commit()

            let r2 = try await metal.makeEncoder(
                functionName: DenoiseProfileKernel.reduceSecond)
            r2.encoder.setBuffer(scratch.partials, offset: 0, index: 0)
            r2.encoder.setBuffer(scratch.sumY2, offset: 0, index: 1)
            var reduce2 = DNReduceSecondParams(
                count: UInt32(((width + 15) / 16) * ((height + 15) / 16)))
            r2.encoder.setBytes(&reduce2, length: MemoryLayout<DNReduceSecondParams>.stride, index: 2)
            r2.encoder.setThreadgroupMemoryLength(256 * 16, index: 0)
            r2.encoder.dispatchThreadgroups(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            r2.encoder.endEncoding()
            r2.commandBuffer.commit()

            // L014 fence + CPU Bayesshrink (dt reads dev_r back per band,
            // :2433-2443).
            let fence = try? metal.makeRoutedCommandBuffer()
            fence?.commit()
            _ = await fence?.completed()
            var sumY2 = SIMD4<Float>(repeating: 0)
            withUnsafeMutableBytes(of: &sumY2) { dst in
                memcpy(dst.baseAddress!, scratch.sumY2.contents(), 16)
            }
            let thrs = DenoiseProfileModule.bayesshrink(
                sumY2: SIMD3(sumY2.x, sumY2.y, sumY2.z), npixels: npixels,
                scale: s, maxScale: maxScale, force: force, modeRGB: colorModeRGB)

            // synthesize-accumulate: accu += softthresh(detail) (device
            // buffer RMW, program order — dt CPU `out += boost·amount`).
            var sparams = DNSynthesizeParams(
                width: UInt32(width), height: UInt32(height),
                align_pad: (0, 0),
                threshold: SIMD4(thrs.x, thrs.y, thrs.z, 0),
                boost: SIMD4(1, 1, 1, 1))
            let syn = try await metal.makeEncoder(
                functionName: DenoiseProfileKernel.synthesizeAccum)
            syn.encoder.setTexture(scratch.detail, index: 0)
            syn.encoder.setBuffer(scratch.accu, offset: 0, index: 0)
            syn.encoder.setBytes(&sparams, length: MemoryLayout<DNSynthesizeParams>.stride, index: 1)
            syn.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            syn.encoder.endEncoding()
            syn.commandBuffer.commit()

            // swap (dt :1574-1576).
            swap(&buf1, &buf2)
        }

        // Residue fold: residue = accu + buf1 (coarsest) — dt :1579-1582.
        var rparams = DNReduceFirstParams(width: UInt32(width), height: UInt32(height))
        let add = try await metal.makeEncoder(functionName: DenoiseProfileKernel.addResidue)
        add.encoder.setBuffer(scratch.accu, offset: 0, index: 0)
        add.encoder.setTexture(buf1, index: 0)
        add.encoder.setTexture(scratch.residue, index: 1)
        add.encoder.setBytes(&rparams, length: MemoryLayout<DNReduceFirstParams>.stride, index: 1)
        add.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        add.encoder.endEncoding()
        add.commandBuffer.commit()

        // Inverse VST → output.
        let bias = vst.bias - 0.5 * Foundation.log(Double(vst.inScale))
        switch (useNewVST, colorModeRGB) {
        case (false, _):
            var p = DNBacktransformParams(
                width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
                a: vst.aaLegacy, sigma2: vst.sigma2Legacy)
            let bt = try await metal.makeEncoder(functionName: DenoiseProfileKernel.backtransform)
            bt.encoder.setTexture(scratch.residue, index: 0)
            bt.encoder.setTexture(output, index: 1)
            bt.encoder.setBytes(&p, length: MemoryLayout<DNBacktransformParams>.stride, index: 0)
            bt.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            bt.encoder.endEncoding()
            bt.commandBuffer.commit()
        case (true, true):
            var p = DNBacktransformV2Params(
                width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
                a: vst.aScalar, p: vst.p, b: vst.bScalar,
                bias: Float(bias), align_pad2: (0, 0, 0), wb: vst.wbScaled)
            let bt = try await metal.makeEncoder(functionName: DenoiseProfileKernel.backtransformV2)
            bt.encoder.setTexture(scratch.residue, index: 0)
            bt.encoder.setTexture(output, index: 1)
            bt.encoder.setBytes(&p, length: MemoryLayout<DNBacktransformV2Params>.stride, index: 0)
            bt.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            bt.encoder.endEncoding()
            bt.commandBuffer.commit()
        case (true, false):
            var p = DNBacktransformV2Params(
                width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
                a: vst.aScalar, p: vst.p, b: vst.bScalar,
                bias: Float(bias), align_pad2: (0, 0, 0), wb: vst.wbScaled)
            let bt = try await metal.makeEncoder(functionName: DenoiseProfileKernel.backtransformY0U0V0)
            bt.encoder.setTexture(scratch.residue, index: 0)
            bt.encoder.setTexture(output, index: 1)
            bt.encoder.setBytes(&p, length: MemoryLayout<DNBacktransformV2Params>.stride, index: 0)
            bt.encoder.setBuffer(scratch.matrixInv, offset: 0, index: 1)
            bt.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            bt.encoder.endEncoding()
            bt.commandBuffer.commit()
        }
    }

    // MARK: - NLMeans leg (T4)

    /// VST → Goossens offsets (scattering-aware, dt nlmeans_core.c:84-120 +
    /// denoiseprofile old-CL enumeration) → finish/finish_v2.
    static func nlMeansLeg(
        input: any MTLTexture,
        output: any MTLTexture,
        useNewVST: Bool,
        vst: VSTUniforms,
        P: Int,
        K: Int,
        scattering: Float,
        norm: Float,
        centralPixelWeight: Float,
        metal: MetalContext,
        scratch: Scratch,
        blockSize: Int = NLMeansModule.threadgroupBlockSize
    ) async throws {
        let width = input.width
        let height = input.height

        switch useNewVST {
        case false:
            try await preconditionLegacy(input: input, to: scratch.nlPlane,
                                         width: width, height: height,
                                         vst: vst, metal: metal)
        case true:
            // RGB-only in the NLMeans leg (dt nlmeans_precondition_cl has
            // no Y0U0V0 branch).
            try await preconditionV2(input: input, to: scratch.nlPlane,
                                     width: width, height: height,
                                     vst: vst, metal: metal, y0u0v0: false,
                                     matrixFwd: scratch.matrixFwd)
        }

        memset(scratch.nlU2.contents(), 0, width * height * 16)

        // Reused 05-06 nlmeans kernels need THEIR uniform layouts — local
        // mirrors of the NLMeansModule function-scoped structs (the MSL
        // layouts are the authority: all-scalar, 4-byte aligned).
        var distParams = DNDistParams(
            width: UInt32(width), height: UInt32(height), qx: 0, qy: 0,
            nL2: 1, nC2: 1) // norm2 = (1,1,1): plain RGB distance
        var boxParams = DNBoxParams(
            width: UInt32(width), height: UInt32(height), p: Int32(P))
        var vertParams = DNVertParams(
            width: UInt32(width), height: UInt32(height), P: Int32(P),
            norm: norm, central_pixel_weight: centralPixelWeight,
            align_pad: (0, 0))
        var accuParams = DNAccuParams(
            width: UInt32(width), height: UInt32(height), qx: 0, qy: 0)

        var state = 0
        func bucketNext() -> Int {
            let current = state
            state = current >= 3 ? 0 : current + 1
            return current
        }

        for (qx, qy) in DenoiseProfileModule.scatteredOffsets(
            K: K, scattering: scattering) {
            distParams.qx = Int32(qx)
            distParams.qy = Int32(qy)
            accuParams.qx = Int32(qx)
            accuParams.qy = Int32(qy)

            let b0 = bucketNext()
            let dist = try await metal.makeEncoder(functionName: NLMeansKernel.distFunction)
            dist.encoder.setTexture(scratch.nlPlane, index: 0)
            dist.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b0, index: 0)
            withUnsafeMutableBytes(of: &distParams) {
                dist.encoder.setBytes($0.baseAddress!, length: $0.count, index: 1)
            }
            dist.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            dist.encoder.endEncoding()
            dist.commandBuffer.commit()

            let b1 = bucketNext()
            let gridW = ((width + blockSize - 1) / blockSize) * blockSize
            let horiz = try await metal.makeEncoder(functionName: NLMeansKernel.horizFunction)
            horiz.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b0, index: 0)
            horiz.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b1, index: 1)
            withUnsafeMutableBytes(of: &boxParams) {
                horiz.encoder.setBytes($0.baseAddress!, length: $0.count, index: 2)
            }
            horiz.encoder.setThreadgroupMemoryLength(
                (blockSize + 2 * P) * MemoryLayout<Float>.size, index: 0)
            horiz.encoder.dispatchThreadgroups(
                MTLSize(width: gridW / blockSize, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: blockSize, height: 1, depth: 1))
            horiz.encoder.endEncoding()
            horiz.commandBuffer.commit()

            // The denoiseprofile vert VARIANT (single-pixel distance boost
            // comes from the RAW dist bucket b0 — dt passes dev_U4).
            let b2 = bucketNext()
            let gridH = ((height + blockSize - 1) / blockSize) * blockSize
            let vert = try await metal.makeEncoder(functionName: DenoiseProfileKernel.vert)
            vert.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b1, index: 0)
            vert.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b0, index: 1)
            vert.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b2, index: 2)
            withUnsafeMutableBytes(of: &vertParams) {
                vert.encoder.setBytes($0.baseAddress!, length: $0.count, index: 3)
            }
            vert.encoder.setThreadgroupMemoryLength(
                (blockSize + 2 * P) * MemoryLayout<Float>.size, index: 0)
            vert.encoder.dispatchThreadgroups(
                MTLSize(width: width, height: gridH / blockSize, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: blockSize, depth: 1))
            vert.encoder.endEncoding()
            vert.commandBuffer.commit()

            let accu = try await metal.makeEncoder(functionName: NLMeansKernel.accuFunction)
            accu.encoder.setTexture(scratch.nlPlane, index: 0)
            accu.encoder.setBuffer(scratch.nlU2, offset: 0, index: 0)
            accu.encoder.setBuffer(scratch.nlBuckets, offset: scratch.planeBytes * b2, index: 1)
            withUnsafeMutableBytes(of: &accuParams) {
                accu.encoder.setBytes($0.baseAddress!, length: $0.count, index: 2)
            }
            accu.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            accu.encoder.endEncoding()
            accu.commandBuffer.commit()
        }

        // finish: normalize + fused backtransform (dt :2200-2213).
        let bias = Float(vst.bias - 0.5 * Foundation.log(Double(vst.inScale)))
        if useNewVST {
            var p = DNFinishV2Params(
                width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
                a: vst.aScalar, p: vst.p, b: vst.bScalar,
                bias: bias, align_pad2: (0, 0, 0), wb: vst.wbScaled)
            let fin = try await metal.makeEncoder(functionName: DenoiseProfileKernel.finishV2)
            fin.encoder.setTexture(input, index: 0)
            fin.encoder.setBuffer(scratch.nlU2, offset: 0, index: 0)
            fin.encoder.setTexture(output, index: 1)
            withUnsafeMutableBytes(of: &p) {
                fin.encoder.setBytes($0.baseAddress!, length: $0.count, index: 1)
            }
            fin.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            fin.encoder.endEncoding()
            fin.commandBuffer.commit()
        } else {
            var p = DNFinishParams(
                width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
                a: vst.aaLegacy, sigma2: vst.sigma2Legacy)
            let fin = try await metal.makeEncoder(functionName: DenoiseProfileKernel.finish)
            fin.encoder.setTexture(input, index: 0)
            fin.encoder.setBuffer(scratch.nlU2, offset: 0, index: 0)
            fin.encoder.setTexture(output, index: 1)
            withUnsafeMutableBytes(of: &p) {
                fin.encoder.setBytes($0.baseAddress!, length: $0.count, index: 1)
            }
            fin.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            fin.encoder.endEncoding()
            fin.commandBuffer.commit()
        }
    }

    // MARK: - Precondition dispatchers (shared by both legs)

    private static func preconditionLegacy(
        input: any MTLTexture, to dest: any MTLTexture,
        width: Int, height: Int, vst: VSTUniforms, metal: MetalContext
    ) async throws {
        var params = DNPreconditionParams(
            width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
            a: vst.aaLegacy, sigma2: vst.sigma2Legacy)
        let enc = try await metal.makeEncoder(functionName: DenoiseProfileKernel.precondition)
        enc.encoder.setTexture(input, index: 0)
        enc.encoder.setTexture(dest, index: 1)
        withUnsafeMutableBytes(of: &params) {
            enc.encoder.setBytes($0.baseAddress!, length: $0.count, index: 0)
        }
        enc.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.encoder.endEncoding()
        enc.commandBuffer.commit()
    }

    private static func preconditionV2(
        input: any MTLTexture, to dest: any MTLTexture,
        width: Int, height: Int, vst: VSTUniforms, metal: MetalContext,
        y0u0v0: Bool, matrixFwd: any MTLBuffer
    ) async throws {
        var params = DNPreconditionV2Params(
            width: UInt32(width), height: UInt32(height), align_pad: (0, 0),
            a: vst.aScalar, p: vst.p, b: vst.bScalar, wb: vst.wbScaled)
        let enc = try await metal.makeEncoder(
            functionName: y0u0v0
                ? DenoiseProfileKernel.preconditionY0U0V0
                : DenoiseProfileKernel.preconditionV2)
        enc.encoder.setTexture(input, index: 0)
        enc.encoder.setTexture(dest, index: 1)
        withUnsafeMutableBytes(of: &params) {
            enc.encoder.setBytes($0.baseAddress!, length: $0.count, index: 0)
        }
        if y0u0v0 {
            enc.encoder.setBuffer(matrixFwd, offset: 0, index: 1)
        }
        enc.encoder.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.encoder.endEncoding()
        enc.commandBuffer.commit()
    }
}

// MARK: - Uniform bundle (commit-derived; module-scoped derivations write it)

/// The VST uniform set for one run (dt computes ALL of these at
/// process_wavelets :1482-1548 / nlmeans_precondition_cl :1706-1745 — run-
/// level constants; the scale/iscale inputs are run stamps, L021).
struct VSTUniforms {
    /// v2 path: a = a[1]·compensate_p broadcast; b = b[1] broadcast.
    var aScalar: SIMD4<Float>
    var bScalar: SIMD4<Float>
    /// Adaptive p per channel = max(shadows + 0.1·log(inScale/wb), 0).
    var p: SIMD4<Float>
    /// wb AFTER the strength·compensate_strength·inScale fold.
    var wbScaled: SIMD4<Float>
    /// legacy path: aa = a[1]·wb, bb = b[1]·wb; sigma2 = (bb/aa)².
    var aaLegacy: SIMD4<Float>
    var bbLegacy: SIMD4<Float>
    var sigma2Legacy: SIMD4<Float>
    /// bias = params.bias (the −0.5·log(inScale) fold happens at dispatch —
    /// dt passes it inside the kernel arg).
    var bias: Double
    /// inScale = fmin(roi.scale/iscale, 1) (wavelets) / the nlmeans
    /// 3-clamp variant for the NLMeans leg.
    var inScale: Float
    /// Y0U0V0 matrices (strength-divided / strength-multiplied, row-major
    /// 9 floats); nil for the RGB path.
    var matrixY0U0V0: [Float]?
    var matrixToRGB: [Float]?
}

/// The 5×5 B3-spline a-trous base filter (eaw.c:122-129), host-built once.
enum FilterB3 {
    static let filter25: [Float] = [
        1, 4, 6, 4, 1,
        4, 16, 24, 16, 4,
        6, 24, 36, 24, 6,
        4, 16, 24, 16, 4,
        1, 4, 6, 4, 1,
    ].map { $0 / 256.0 }
}

/// Kernel function names (DenoiseProfileKernels.metal).
enum DenoiseProfileKernel {
    static let precondition = "dn_precondition"
    static let preconditionV2 = "dn_precondition_v2"
    static let preconditionY0U0V0 = "dn_precondition_Y0U0V0"
    static let backtransform = "dn_backtransform"
    static let backtransformV2 = "dn_backtransform_v2"
    static let backtransformY0U0V0 = "dn_backtransform_Y0U0V0"
    static let decompose = "dn_decompose"
    static let synthesizeAccum = "dn_synthesize_accum"
    static let reduceFirst = "dn_reduce_first"
    static let reduceSecond = "dn_reduce_second"
    static let addResidue = "dn_add_residue"
    static let vert = "dn_vert"
    static let finish = "dn_finish"
    static let finishV2 = "dn_finish_v2"
    static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

// MSL uniform mirrors (field-for-field; scalar structs pack identically —
// NLMeansModule precedent).
struct DNDistParams {
    var width: UInt32
    var height: UInt32
    var qx: Int32
    var qy: Int32
    var nL2: Float
    var nC2: Float
}
struct DNBoxParams {
    var width: UInt32
    var height: UInt32
    var p: Int32
}
struct DNAccuParams {
    var width: UInt32
    var height: UInt32
    var qx: Int32
    var qy: Int32
}
struct DNDecomposeParams {
    var width: UInt32
    var height: UInt32
    var scale: UInt32
    var inv_sigma2: Float
}
struct DNSynthesizeParams {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var threshold: SIMD4<Float>
    var boost: SIMD4<Float>
}
struct DNReduceFirstParams {
    var width: UInt32
    var height: UInt32
}
struct DNReduceSecondParams {
    var count: UInt32
}
struct DNVertParams {
    var width: UInt32
    var height: UInt32
    var P: Int32
    var norm: Float
    var central_pixel_weight: Float
    var align_pad: (UInt32, UInt32)
}
struct DNFinishParams {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var a: SIMD4<Float>
    var sigma2: SIMD4<Float>
}
struct DNFinishV2Params {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var a: SIMD4<Float>
    var p: SIMD4<Float>
    var b: SIMD4<Float>
    var bias: Float
    var align_pad2: (UInt32, UInt32, UInt32)
    var wb: SIMD4<Float>
}
struct DNPreconditionParams {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var a: SIMD4<Float>
    var sigma2: SIMD4<Float>
}
struct DNPreconditionV2Params {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var a: SIMD4<Float>
    var p: SIMD4<Float>
    var b: SIMD4<Float>
    var wb: SIMD4<Float>
}
struct DNBacktransformParams {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var a: SIMD4<Float>
    var sigma2: SIMD4<Float>
}
struct DNBacktransformV2Params {
    var width: UInt32
    var height: UInt32
    var align_pad: (UInt32, UInt32)
    var a: SIMD4<Float>
    var p: SIMD4<Float>
    var b: SIMD4<Float>
    var bias: Float
    var align_pad2: (UInt32, UInt32, UInt32)
    var wb: SIMD4<Float>
}
