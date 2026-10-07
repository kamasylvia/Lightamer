import LightamerCore
import Metal
import os
import simd

// ─────────────────────────────────────────────────────────────────────────────
// ScopeReduce (Plan M2-3-3 T3, D6) — the editor scope reductions
// (`HistogramReduce`'s Common family extension; the same two-pass shape):
//
//   • histogram(of:metal:) — the 256-bin × 4 channel (R/G/B/luma) COUNTING
//     histogram of the PREVIEW output plane → a Sendable value (≤4 KB).
//   • waveform(of:metal:) — the per-column luma-band counts written into a
//     small r16Uint present texture (width ≤1080, height 256) — the display
//     carrier, never a CPU plane.
//
// Kernel names live in `ScopeReduceKernels.metal`. Queue discipline (L031):
// every command buffer comes from MetalContext's routed acquisition
// (`makeEncoder` / `makeRoutedCommandBuffer`) — never a second queue.
// Readback discipline (L014): the histogram buffer is read only after a
// committed fence completes; the waveform texture is fenced before it is
// handed to the display face.
// ─────────────────────────────────────────────────────────────────────────────

public enum ScopeReduce {

    public static let bins = 256
    public static let channelCount = 4
    public static let maxWaveformWidth = 1080
    public static let waveformHeight = 256

    /// The Rec.709 luma weights (the kernel's `scope_luma_weights` mirror —
    /// the CPU test reference quotes the same constants).
    public static let lumaWeights = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    private static let threadgroupSize = 16

    /// Kernel function names (`ScopeReduceKernels.metal`).
    public enum Kernel {
        public static let histogramPartial = "scope_histogram_partial"
        public static let histogramTotal = "scope_histogram_total"
        public static let waveformAccumulate = "scope_waveform_accumulate"
        public static let waveformTotal = "scope_waveform_total"
    }

    /// The counting histogram (channel-major: R, G, B, luma; each 256 bins
    /// of exact pixel counts — normalization belongs to the draw layer).
    public struct Histogram: Equatable, Sendable {
        public let perChannel: [[UInt32]]

        public init(perChannel: [[UInt32]]) {
            self.perChannel = perChannel
        }

        /// The L013-safe deterministic byte face (the determinism
        /// assertion hashes through this).
        public var flattened: [UInt32] {
            perChannel.flatMap { $0 }
        }
    }

    /// The binning mirror (the kernel's `scope_bin` — Float32 truncation,
    /// the test-parity contract).
    public static func bin(_ value: Float) -> Int {
        let clamped = min(max(value, 0), 1)
        return min(Int(clamped * 255.0), 255)
    }

    /// The Rec.709 luma mirror (the kernel's dot — same Float32 sequence).
    public static func luma(_ rgb: SIMD3<Float>) -> Float {
        simd_dot(rgb, lumaWeights)
    }

    // MARK: - Histogram

    public static func histogram(
        of input: any MTLTexture, metal: MetalContext
    ) async throws -> Histogram {
        guard input.width > 0, input.height > 0 else {
            return Histogram(perChannel: [[], [], [], []])
        }
        let width = input.width
        let height = input.height
        let tgWidth = (width + threadgroupSize - 1) / threadgroupSize
        let tgHeight = (height + threadgroupSize - 1) / threadgroupSize
        let nPartials = tgWidth * tgHeight
        let slots = bins * channelCount

        guard let partialsBuffer = metal.device.makeBuffer(
            length: nPartials * slots * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ), let totalBuffer = metal.device.makeBuffer(
            length: slots * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ) else {
            throw MetalError.deviceUnavailable
        }

        // Pass 1: threadgroup partials (one 16×16 group per pixel block).
        let pass1 = try await metal.makeEncoder(functionName: Kernel.histogramPartial)
        pass1.encoder.setTexture(input, index: 0)
        pass1.encoder.setBuffer(partialsBuffer, offset: 0, index: 0)
        pass1.encoder.dispatchThreadgroups(
            MTLSize(width: tgWidth, height: tgHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: threadgroupSize, depth: 1)
        )
        pass1.encoder.endEncoding()
        pass1.commandBuffer.commit()

        // Pass 2: one thread per (channel, bin) slot sums the partials
        // (same queue → ordered after pass 1).
        let pass2 = try await metal.makeEncoder(functionName: Kernel.histogramTotal)
        pass2.encoder.setBuffer(partialsBuffer, offset: 0, index: 0)
        pass2.encoder.setBuffer(totalBuffer, offset: 0, index: 1)
        var nPartialsU32 = UInt32(nPartials)
        pass2.encoder.setBytes(&nPartialsU32, length: MemoryLayout<UInt32>.size, index: 2)
        pass2.encoder.dispatchThreads(
            MTLSize(width: slots, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 128, height: 1, depth: 1)
        )
        pass2.encoder.endEncoding()
        pass2.commandBuffer.commit()

        // L014 fence before the CPU readback (the rgbMinMax precedent).
        let fence = try? metal.makeRoutedCommandBuffer()
        fence?.commit()
        _ = await fence?.completed()

        let words = totalBuffer.contents().assumingMemoryBound(to: UInt32.self)
        var perChannel: [[UInt32]] = []
        for channel in 0..<channelCount {
            var channelBins: [UInt32] = []
            channelBins.reserveCapacity(bins)
            for bin in 0..<bins {
                channelBins.append(words[channel * bins + bin])
            }
            perChannel.append(channelBins)
        }
        return Histogram(perChannel: perChannel)
    }

    // MARK: - Waveform

    /// The per-column luma-band counts, written into a small `r16Uint`
    /// texture (width = min(source width, 1080), height 256). Fenced
    /// before return (L014) — the caller displays it directly.
    public static func waveform(
        of input: any MTLTexture, metal: MetalContext
    ) async throws -> any MTLTexture {
        let outWidth = min(max(input.width, 1), maxWaveformWidth)
        let outHeight = waveformHeight
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Uint, width: outWidth, height: outHeight,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let output = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.deviceUnavailable
        }
        guard input.width > 0, input.height > 0 else {
            return output
        }

        let width = input.width
        let height = input.height
        let tgWidth = (width + threadgroupSize - 1) / threadgroupSize
        let tgHeight = (height + threadgroupSize - 1) / threadgroupSize
        let cells = outWidth * outHeight

        guard let partialsBuffer = metal.device.makeBuffer(
            length: cells * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        ) else {
            throw MetalError.deviceUnavailable
        }

        // Host-side zero (the kernel contract): the shared-buffer write
        // completes before the committed pass executes — no in-kernel zero
        // phase, no ownership races (integer atomic adds are then purely
        // order-independent).
        memset(partialsBuffer.contents(), 0, cells * MemoryLayout<UInt32>.size)

        // Pass 1: the tile accumulation (every pixel → exactly one cell).
        let pass1 = try await metal.makeEncoder(functionName: Kernel.waveformAccumulate)
        pass1.encoder.setTexture(input, index: 0)
        pass1.encoder.setBuffer(partialsBuffer, offset: 0, index: 0)
        var outWidthU32 = UInt32(outWidth)
        pass1.encoder.setBytes(&outWidthU32, length: MemoryLayout<UInt32>.size, index: 1)
        pass1.encoder.dispatchThreadgroups(
            MTLSize(width: tgWidth, height: tgHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: threadgroupSize, depth: 1)
        )
        pass1.encoder.endEncoding()
        pass1.commandBuffer.commit()

        // Pass 2: copy the counts into the present texture (same queue →
        // ordered after pass 1).
        let pass2 = try await metal.makeEncoder(functionName: Kernel.waveformTotal)
        pass2.encoder.setBuffer(partialsBuffer, offset: 0, index: 0)
        pass2.encoder.setTexture(output, index: 0)
        pass2.encoder.dispatchThreads(
            MTLSize(width: outWidth, height: outHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1)
        )
        pass2.encoder.endEncoding()
        pass2.commandBuffer.commit()

        // L014 fence: the texture leaves only after the writes complete.
        let fence = try? metal.makeRoutedCommandBuffer()
        fence?.commit()
        _ = await fence?.completed()

        return output
    }
}
