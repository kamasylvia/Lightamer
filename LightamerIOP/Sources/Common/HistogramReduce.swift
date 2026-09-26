import LightamerCore
import Metal
import os
import simd

// ─────────────────────────────────────────────────────────────────────────
// HistogramReduce (Plan 03-03-T5, Common) — the shared full-image 256-bin
// L-channel histogram (levels AUTOMATIC mode now; filmic auto black/white
// keys later, 03-06).
//
// SELECTION (RESEARCH Open#6, decision recorded per plan): the hand-
// written two-pass reduce (threadgroup partials → column totals) is the
// default — it computes the Lab L inline (shared LabMath.h) and reads
// back exactly bins×4 bytes. MPS histogram was evaluated as the
// alternative; it is NOT wired (MPSHistogram lacks the inline Lab
// conversion and would need an extra conversion pass). The interface is
// a single call, so a backend swap stays one-file.
//
// Timing: the reduce fences (L014) — the synchronous stall is recorded
// via os.signpost ("histogram-reduce"; PREVIEW bucket <2ms expected,
// over-budget records do not fail anything).
// ─────────────────────────────────────────────────────────────────────────

public enum HistogramReduce {

    public static let bins = 256
    private static let threadgroupSize = 16

    private static let signposter = OSSignposter(
        subsystem: "com.kamasylvia.lightamer", category: "metal"
    )

    /// Kernel function names (`HistogramReduceKernels.metal`).
    public enum Kernel {
        public static let partial = "histogram_partial"
        public static let total = "histogram_total"
        public static let normMinMaxPartial = "norm_minmax_partial"
        public static let normMinMaxTotal = "norm_minmax_total"
    }

    /// Compute the 256-bin histogram of the input's Lab L channel
    /// (float32 RGBA linear-Rec2020 texture). Fences before readback —
    /// synchronous per call (L014).
    public static func histogramL(
        of input: any MTLTexture, metal: MetalContext
    ) async throws -> [UInt32] {
        let state = signposter.beginInterval("histogram-reduce")
        defer {
            signposter.endInterval("histogram-reduce", state)
        }

        let width = input.width
        let height = input.height
        let tgWidth = (width + threadgroupSize - 1) / threadgroupSize
        let tgHeight = (height + threadgroupSize - 1) / threadgroupSize
        let nPartials = tgWidth * tgHeight

        guard let partialsBuffer = metal.device.makeBuffer(
            length: nPartials * bins * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ), let totalBuffer = metal.device.makeBuffer(
            length: bins * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ) else {
            throw MetalError.deviceUnavailable
        }

        // Pass 1: threadgroup partials (one 16×16 group per pixel block).
        let pass1 = try await metal.makeEncoder(functionName: Kernel.partial)
        pass1.encoder.setTexture(input, index: 0)
        pass1.encoder.setBuffer(partialsBuffer, offset: 0, index: 0)
        pass1.encoder.dispatchThreadgroups(
            MTLSize(width: tgWidth, height: tgHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: threadgroupSize, depth: 1)
        )
        pass1.encoder.endEncoding()
        pass1.commandBuffer.commit()

        // Pass 2: one thread per bin sums the partials (same queue →
        // ordered after pass 1 without a wait).
        let pass2 = try await metal.makeEncoder(functionName: Kernel.total)
        pass2.encoder.setBuffer(partialsBuffer, offset: 0, index: 0)
        pass2.encoder.setBuffer(totalBuffer, offset: 0, index: 1)
        var nPartialsU32 = UInt32(nPartials)
        pass2.encoder.setBytes(&nPartialsU32, length: MemoryLayout<UInt32>.size, index: 2)
        pass2.encoder.dispatchThreads(
            MTLSize(width: bins, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
        )
        pass2.encoder.endEncoding()
        pass2.commandBuffer.commit()

        // L014 fence: the CPU readback must wait for in-flight writes.
        // (async context → the awaitable completed() form, per the 03-02
        // summary's pickColor precedent)
        let fence = try? metal.makeRoutedCommandBuffer()
        fence?.commit()
        _ = await fence?.completed()

        var histogram = [UInt32](repeating: 0, count: bins)
        histogram.withUnsafeMutableBytes { dst in
            memcpy(dst.baseAddress!, totalBuffer.contents(), bins * MemoryLayout<UInt32>.size)
        }
        return histogram
    }

    /// The percentile → levels derivation (dt levels.c:212-250 verbatim
    /// shape). `percentiles` are in [0, 100].
    public static func percentileLevels(
        histogram: [UInt32], percentiles: (Float, Float, Float), bins: Int = HistogramReduce.bins
    ) -> [Float] {
        let total = histogram.reduce(0, +)
        let pcts = [percentiles.0, percentiles.1, percentiles.2]
        // dt: thr = (float)total * percentile / 100.0f (float32 math)
        var thresholds = [Float](repeating: 0, count: 3)
        for k in 0..<3 {
            thresholds[k] = Float(total) * pcts[k] / 100.0
        }
        var levels = [Float](repeating: -1, count: 3) // dt's UNINIT marker
        var n = 0
        for i in 0..<bins {
            n += Int(histogram[i])
            for k in 0..<3 where levels[k] < 0 && Float(n) >= thresholds[k] {
                levels[k] = Float(i) / Float(bins - 1)
            }
        }
        if levels[2] < 0 { levels[2] = 1.0 } // dt's numerical guard
        let center = Double(pcts[1]) / 100.0
        levels[1] = Float(
            (1.0 - center) * Double(levels[0]) + center * Double(levels[2])
        )
        return levels
    }

    // MARK: - Per-channel RGB min/max (Plan 03-06-T5)

    /// The full-image per-channel min/max (dt's `picked_color_min/max`
    /// whole-preview semantics — the filmic auto black/white keys).
    /// Fences before readback (L014).
    public static func rgbMinMax(
        of input: any MTLTexture, metal: MetalContext
    ) async throws -> (min: simd_float3, max: simd_float3) {
        let state = signposter.beginInterval("rgb-minmax-reduce")
        defer {
            signposter.endInterval("rgb-minmax-reduce", state)
        }

        let width = input.width
        let height = input.height
        let tgWidth = (width + threadgroupSize - 1) / threadgroupSize
        let tgHeight = (height + threadgroupSize - 1) / threadgroupSize
        let nPartials = tgWidth * tgHeight

        guard let partialsMin = metal.device.makeBuffer(
            length: nPartials * 4 * MemoryLayout<Float>.size,
            options: .storageModeShared
        ), let partialsMax = metal.device.makeBuffer(
            length: nPartials * 4 * MemoryLayout<Float>.size,
            options: .storageModeShared
        ), let result = metal.device.makeBuffer(
            length: 8 * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalError.deviceUnavailable
        }

        // Pass 1: threadgroup partials.
        let pass1 = try await metal.makeEncoder(functionName: Kernel.normMinMaxPartial)
        pass1.encoder.setTexture(input, index: 0)
        pass1.encoder.setBuffer(partialsMin, offset: 0, index: 0)
        pass1.encoder.setBuffer(partialsMax, offset: 0, index: 1)
        pass1.encoder.dispatchThreadgroups(
            MTLSize(width: tgWidth, height: tgHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: threadgroupSize, depth: 1)
        )
        pass1.encoder.endEncoding()
        pass1.commandBuffer.commit()

        // Pass 2: fold the partials (same queue → ordered after pass 1).
        let pass2 = try await metal.makeEncoder(functionName: Kernel.normMinMaxTotal)
        pass2.encoder.setBuffer(partialsMin, offset: 0, index: 0)
        pass2.encoder.setBuffer(partialsMax, offset: 0, index: 1)
        pass2.encoder.setBuffer(result, offset: 0, index: 2)
        var nPartialsU32 = UInt32(nPartials)
        pass2.encoder.setBytes(&nPartialsU32, length: MemoryLayout<UInt32>.size, index: 3)
        pass2.encoder.dispatchThreads(
            MTLSize(width: 4, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 4, height: 1, depth: 1)
        )
        pass2.encoder.endEncoding()
        pass2.commandBuffer.commit()

        // L014 fence before the CPU readback.
        let fence = try? metal.makeRoutedCommandBuffer()
        fence?.commit()
        _ = await fence?.completed()

        let floats = result.contents().assumingMemoryBound(to: Float.self)
        let minV = simd_float3(floats[0], floats[1], floats[2])
        let maxV = simd_float3(floats[4], floats[5], floats[6])
        return (minV, maxV)
    }
}
