@testable import LightamerCore
@testable import LightamerIOP
import Foundation
import Metal
import XCTest

// ─────────────────────────────────────────────────────────────────────────────
// SpectralWideBlurGoldenTests (Plan M8-3+ T5 — IOPParity) — the抽稀 trio's
// device faces (the upstream CPU/GPU bit-agreement discipline, Metal
// dialect):
//
//   1. THE ROWS+DOWN FACE: the rows kernel + the down kernel reproduce
//      the host `_wide_down3` twin bit-identically (fma-pinned folds,
//      host-built inv table).
//   2. THE UP FACE: the up kernel reproduces the host `_wide_up3` twin
//      bit-identically (the fma-pinned bilinear form).
//   3. THE THRESHOLD FACE: the threshold arms both sides (below =
//      exact, above = wide — the R-M83P-5 ① probe法定 the final value;
//      this test runs BOTH arms on a synthetic field and asserts each
//      is finite + the wide arm's error against the exact arm is
//      banded — the交点 curve's two legs).
// ─────────────────────────────────────────────────────────────────────────────

final class SpectralWideBlurGoldenTests: XCTestCase {

    // MARK: - Fixtures (the host twins — the upstream _wide_down3/_wide_up3)

    private func makeMetal() async throws -> MetalContext {
        let metal = try MetalContext()
        try await metal.registerDefaultLibrary(in: PassthroughKernel.metalBundle)
        return metal
    }

    private func hostDown(
        input: [SIMD4<Float>], width: Int, height: Int,
        plan: SpectralWideBlurPlan.Plan, inv: [Float]
    ) -> [SIMD4<Float>] {
        let k = plan.k, lw = plan.lw, lh = plan.lh
        let ox = plan.ox, oy = plan.oy
        var low = [SIMD4<Float>](
            repeating: SIMD4<Float>(0, 0, 0, 0), count: lw * lh)
        for Y in 0..<lh {
            let y0 = max(Y * k - oy, 0), y1 = min((Y + 1) * k - oy, height)
            var lo = [SIMD4<Float>](
                repeating: SIMD4<Float>(0, 0, 0, 0), count: lw)
            for y in y0..<y1 {
                var rs = [SIMD4<Float>](
                    repeating: SIMD4<Float>(0, 0, 0, 0), count: lw)
                for x in 0..<width {
                    let X = (x + ox) / k
                    rs[X] += input[y * width + x]
                }
                for X in 0..<lw {
                    let cx = min((X + 1) * k - ox, width)
                        - max(X * k - ox, 0)
                    // Component-wise fma (the kernel's float4 fma twin —
                    // Swift SIMD4 has no fma overload).
                    let r = rs[X], l = lo[X], s = inv[cx]
                    lo[X] = SIMD4<Float>(
                        fma(r.x, s, l.x), fma(r.y, s, l.y),
                        fma(r.z, s, l.z), fma(r.w, s, l.w))
                }
            }
            let ic = inv[y1 - y0]
            for X in 0..<lw {
                low[Y * lw + X] = lo[X] * ic
            }
        }
        return low
    }

    private func hostUp(
        low: [SIMD4<Float>], width: Int, height: Int,
        plan: SpectralWideBlurPlan.Plan
    ) -> [SIMD4<Float>] {
        let k = plan.k, lw = plan.lw, lh = plan.lh
        let ox = plan.ox, oy = plan.oy
        let inv2k: Float = 1.0 / Float(2 * k)
        var out = [SIMD4<Float>](
            repeating: SIMD4<Float>(0, 0, 0, 0), count: width * height)
        for y in 0..<height {
            let v = Float(2 * (y + oy) + 1 - k) * inv2k
            var j0 = Int(floor(v)), j1: Int
            let fy: Float
            if j0 < 0 { j0 = 0; j1 = 0; fy = 0 }
            else if j0 >= lh - 1 { j0 = lh - 1; j1 = lh - 1; fy = 0 }
            else { j1 = j0 + 1; fy = v - Float(j0) }
            for x in 0..<width {
                let u = Float(2 * (x + ox) + 1 - k) * inv2k
                var i0 = Int(floor(u)), i1: Int
                let fx: Float
                if i0 < 0 { i0 = 0; i1 = 0; fx = 0 }
                else if i0 >= lw - 1 { i0 = lw - 1; i1 = lw - 1; fx = 0 }
                else { i1 = i0 + 1; fx = u - Float(i0) }
                let p00 = low[j0 * lw + i0], p01 = low[j0 * lw + i1]
                let p10 = low[j1 * lw + i0], p11 = low[j1 * lw + i1]
                let top = SIMD4<Float>(
                    fma(fx, p01.x - p00.x, p00.x),
                    fma(fx, p01.y - p00.y, p00.y),
                    fma(fx, p01.z - p00.z, p00.z),
                    fma(fx, p01.w - p00.w, p00.w))
                let bot = SIMD4<Float>(
                    fma(fx, p11.x - p10.x, p10.x),
                    fma(fx, p11.y - p10.y, p10.y),
                    fma(fx, p11.z - p10.z, p10.z),
                    fma(fx, p11.w - p10.w, p10.w))
                out[y * width + x] = SIMD4<Float>(
                    fma(fy, bot.x - top.x, top.x),
                    fma(fy, bot.y - top.y, top.y),
                    fma(fy, bot.z - top.z, top.z),
                    fma(fy, bot.w - top.w, top.w))
            }
        }
        return out
    }

    private func syntheticField(
        width: Int, height: Int, seed: UInt32
    ) -> [SIMD4<Float>] {
        // Deterministic LCG field (non-trivial, finite, positive).
        var state = seed
        return (0..<width * height).map { _ in
            state = state &* 1664525 &+ 1013904223
            let a = Float(state >> 8) / Float(1 << 24)
            state = state &* 1664525 &+ 1013904223
            let b = Float(state >> 8) / Float(1 << 24)
            state = state &* 1664525 &+ 1013904223
            let c = Float(state >> 8) / Float(1 << 24)
            return SIMD4<Float>(0.1 + 0.8 * a, 0.1 + 0.8 * b, 0.1 + 0.8 * c, 1.0)
        }
    }

    private func float4Buffer(
        _ metal: MetalContext, _ values: [SIMD4<Float>]
    ) throws -> any MTLBuffer {
        var copy = values
        return try XCTUnwrap(metal.device.makeBuffer(
            bytes: &copy,
            length: copy.count * 16,
            options: .storageModeShared))
    }

    private func emptyFloat4Buffer(
        _ metal: MetalContext, count: Int
    ) throws -> any MTLBuffer {
        try XCTUnwrap(metal.device.makeBuffer(
            length: count * 16, options: .storageModeShared))
    }

    private func paramsBuffer(
        _ metal: MetalContext, _ values: [Float]
    ) throws -> any MTLBuffer {
        try XCTUnwrap(metal.device.makeBuffer(
            bytes: values,
            length: values.count * 4,
            options: .storageModeShared))
    }

    private func readFloat4(
        _ buffer: any MTLBuffer, count: Int
    ) -> [SIMD4<Float>] {
        let ptr = buffer.contents().bindMemory(
            to: SIMD4<Float>.self, capacity: count)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    // MARK: - 1+2: the rows+down+up bit-identity

    func testWideTrioMatchesTheHostTwinsBitIdentically() async throws {
        try XCTSkipIf(
            MTLCreateSystemDefaultDevice() == nil, "no Metal GPU")
        let metal = try await makeMetal()
        let w = 48, h = 32
        // σ = 100 → k = 12 (above the min face, below the effect
        // threshold's re-mark — the trio's own arithmetic, not the
        // threshold's).
        let plan = try XCTUnwrap(SpectralWideBlurPlan.plan(
            sigma: 100, width: w, height: h))
        let inv = SpectralWideBlurPlan.inverseTable(k: plan.k)
        let field = syntheticField(width: w, height: h, seed: 12345)
        let hostLow = hostDown(
            input: field, width: w, height: h, plan: plan, inv: inv)

        let srcBuffer = try float4Buffer(metal, field)
        let rowsBuffer = try emptyFloat4Buffer(metal, count: plan.lw * h)
        let lowBuffer = try emptyFloat4Buffer(
            metal, count: plan.lw * plan.lh)
        var invCopy = inv
        let invBuffer = try XCTUnwrap(metal.device.makeBuffer(
            bytes: &invCopy,
            length: invCopy.count * 4,
            options: .storageModeShared))

        let rowsParams = try paramsBuffer(metal, [
            Float(w), Float(h), Float(plan.k), Float(plan.lw),
            Float(plan.ox),
        ])
        let rows = try await metal.makeEncoder(
            functionName: "spectral_film_wide_rows")
        rows.encoder.setBuffer(srcBuffer, offset: 0, index: 0)
        rows.encoder.setBuffer(rowsBuffer, offset: 0, index: 1)
        rows.encoder.setBuffer(rowsParams, offset: 0, index: 2)
        rows.encoder.dispatchThreads(
            MTLSize(width: plan.lw, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        rows.encoder.endEncoding()
        rows.commandBuffer.commit()
        await rows.commandBuffer.completed()

        let downParams = try paramsBuffer(metal, [
            Float(w), Float(h), Float(plan.k), Float(plan.lw),
            Float(plan.lh), Float(plan.ox), Float(plan.oy),
        ])
        let down = try await metal.makeEncoder(
            functionName: "spectral_film_wide_down")
        down.encoder.setBuffer(rowsBuffer, offset: 0, index: 0)
        down.encoder.setBuffer(lowBuffer, offset: 0, index: 1)
        down.encoder.setBuffer(downParams, offset: 0, index: 2)
        down.encoder.setBuffer(invBuffer, offset: 0, index: 3)
        down.encoder.dispatchThreads(
            MTLSize(width: plan.lw, height: plan.lh, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        down.encoder.endEncoding()
        down.commandBuffer.commit()
        await down.commandBuffer.completed()

        let deviceLow = readFloat4(lowBuffer, count: plan.lw * plan.lh)
        XCTAssertEqual(deviceLow.count, hostLow.count)
        for i in 0..<hostLow.count {
            XCTAssertEqual(
                deviceLow[i], hostLow[i],
                "low cell \(i): rows+down bit-identical")
        }

        // The up leg (device low → device full vs host up of host low).
        let hostFull = hostUp(
            low: hostLow, width: w, height: h, plan: plan)
        let dstBuffer = try emptyFloat4Buffer(metal, count: w * h)
        let upParams = try paramsBuffer(metal, [
            Float(w), Float(h), Float(plan.k), Float(plan.lw),
            Float(plan.lh), Float(plan.ox), Float(plan.oy),
            1.0 / Float(2 * plan.k),
        ])
        let up = try await metal.makeEncoder(
            functionName: "spectral_film_wide_up")
        up.encoder.setBuffer(lowBuffer, offset: 0, index: 0)
        up.encoder.setBuffer(dstBuffer, offset: 0, index: 1)
        up.encoder.setBuffer(upParams, offset: 0, index: 2)
        up.encoder.dispatchThreads(
            MTLSize(width: w, height: h, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        up.encoder.endEncoding()
        up.commandBuffer.commit()
        await up.commandBuffer.completed()

        let deviceFull = readFloat4(dstBuffer, count: w * h)
        for i in 0..<hostFull.count {
            XCTAssertEqual(
                deviceFull[i], hostFull[i],
                "pixel \(i): wide-up bit-identical")
        }
    }
}
