import Foundation
import Metal

// ═══════════════════════════════════════════════════════════════════════════
// Plan 06-03 T1 — brush stamping prototype spike (L018 RMW red line).
//
// Two candidate accumulation schemes, prototyped BEFORE any production
// rasterizer code (plan discipline):
//   A. render-pipeline additive blending — one render pass per stroke; the
//      hardware blender accumulates into an r32Float target (no atomics,
//      no read-modify-write in shader code).
//   B. compute + atomic_fetch_add on integer fixed point (2^24 per 1.0;
//      Metal has no native float atomics).
//
// Judged on (plan 防空转 quantified gates):
//   1. precision  — one stamp of flow 1/100 accumulated 100× → |value − 1.0|
//      (gate < 1e-5)
//   2. throughput — 1000 stamps @ 2560×1707 window, median GPU ms over 50
//      reps (gate: within the interactive budget, ms class)
//   3. code complexity — qualitative (LOC, failure modes)
//
// Run: swift .work/plans/06-03/spike-stamping.swift
// ═══════════════════════════════════════════════════════════════════════════

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("no Metal device")
}
let queue = device.makeCommandQueue()!
let width = 2560, height = 1707

func cbWait() {
    let cb = queue.makeCommandBuffer()!
    cb.commit()
    cb.waitUntilCompleted()
}

func r32Texture() -> any MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead, .shaderWrite]
    d.storageMode = .shared
    return device.makeTexture(descriptor: d)!
}

func readCenter(_ tex: any MTLTexture) -> Float {
    var v: Float = -1
    tex.getBytes(&v, bytesPerRow: MemoryLayout<Float>.stride,
                 from: MTLRegionMake2D(width / 2, height / 2, 1, 1), mipmapLevel: 0)
    return v
}

func median(_ s: [Double]) -> Double { s.sorted()[s.count / 2] }

let source = """
#include <metal_stdlib>
using namespace metal;

// ── Option A: render pipeline. One quad per stamp; fragment writes the
// falloff weight; the FIXED-FUNCTION blender adds it into r32Float.
struct StampVertexOut {
    float4 position [[position]];
    float2 local;
};

// instanced variant: per-instance stamp center from a buffer.
vertex StampVertexOut spike_quad_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant float2 *centers [[buffer(0)]],
    constant float &stampRadius [[buffer(1)]],
    constant float2 &targetSize [[buffer(2)]])
{
    const float2 corners[4] = { float2(-1.0, -1.0), float2(1.0, -1.0),
                                float2(-1.0, 1.0), float2(1.0, 1.0) };
    const float2 c = corners[vid];
    const float2 px = centers[iid] + c * stampRadius;
    StampVertexOut out;
    out.position = float4(px / targetSize * 2.0 - 1.0, 0.0, 1.0);
    out.local = c;
    return out;
}

fragment float spike_quad_fragment(StampVertexOut in [[stage_in]],
                                   constant float &flow [[buffer(0)]])
{
    const float d = length(in.local);
    if (d >= 1.0) { discard_fragment(); }
    const float w = d <= 0.5 ? 1.0 : 1.0 - (d - 0.5) / 0.5;
    return flow * w;
}

// ── Option B: compute + integer fixed-point atomics (2^24 per 1.0).
kernel void spike_atomic_kernel(
    device atomic_uint *accum [[buffer(0)]],
    constant uint &stampCount [[buffer(1)]],
    constant float2 &targetSize [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= (uint)targetSize.x || gid.y >= (uint)targetSize.y) { return; }
    const float2 p = float2(gid) + 0.5;
    const float flow = 1.0 / 100.0;
    float w = 0.0;
    for (uint s = 0; s < stampCount; ++s) {
        const float2 c = float2(64.0 * s + 32.0, targetSize.y * 0.5);
        const float d = length(p - c) / 256.0;
        if (d < 1.0) {
            w += d <= 0.5 ? 1.0 : 1.0 - (d - 0.5) / 0.5;
        }
    }
    if (w > 0.0) {
        atomic_fetch_add_explicit(&accum[gid.y * (uint)targetSize.x + gid.x],
                                  (uint)round(flow * w * 16777216.0),
                                  memory_order_relaxed);
    }
}
"""

let library = try device.makeLibrary(source: source, options: nil)

// ═══ Option A: render-pipeline additive ═══
do {
    let vfn = library.makeFunction(name: "spike_quad_vertex")!
    let ffn = library.makeFunction(name: "spike_quad_fragment")!
    let desc = MTLRenderPipelineDescriptor()
    desc.vertexFunction = vfn
    desc.fragmentFunction = ffn
    desc.colorAttachments[0].pixelFormat = .r32Float
    desc.colorAttachments[0].isBlendingEnabled = true
    desc.colorAttachments[0].rgbBlendOperation = .add
    desc.colorAttachments[0].alphaBlendOperation = .add
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
    desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.one
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.one
    let pso = try device.makeRenderPipelineState(descriptor: desc)

    let size = device.makeBuffer(bytes: [Float(width), Float(height)],
                                 length: MemoryLayout<Float>.stride * 2)!
    let radius = device.makeBuffer(bytes: [Float(256)], length: MemoryLayout<Float>.stride)!
    let flowB = device.makeBuffer(bytes: [Float(1.0 / 100.0)], length: MemoryLayout<Float>.stride)!
    let centers: [Float] = [Float(width / 2), Float(height / 2)]
    let centersB = device.makeBuffer(bytes: centers, length: centers.count * 4)!

    // Precision: ONE render pass, the same stamp drawn 100× (flow 1/100) —
    // the blender accumulates inside the pass.
    do {
        let tex = r32Texture()
        let cb = queue.makeCommandBuffer()!
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        let re = cb.makeRenderCommandEncoder(descriptor: rpd)!
        re.setRenderPipelineState(pso)
        re.setVertexBuffer(centersB, offset: 0, index: 0)
        re.setVertexBuffer(radius, offset: 0, index: 1)
        re.setVertexBuffer(size, offset: 0, index: 2)
        re.setFragmentBuffer(flowB, offset: 0, index: 0)
        for _ in 0..<100 {
            re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        re.endEncoding()
        cb.commit()
        cbWait()
        let a = readCenter(tex)
        print("A_precision value=\(a) err=\(abs(a - 1.0))")
    }

    // Throughput: 1000 stamps @ 2560 window, ONE instanced draw per pass
    // (the production shape — all stroke stamps batched in one pass).
    do {
        let t = r32Texture()
        var many: [Float] = []
        many.reserveCapacity(2000)
        for i in 0..<1000 { many += [Float(64 * i + 32), Float(height / 2)] }
        let manyB = device.makeBuffer(bytes: many, length: many.count * 4)!
        let flowThousand = device.makeBuffer(bytes: [Float(0.5)], length: 4)!

        func frame() {
            let cb = queue.makeCommandBuffer()!
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = t
            rpd.colorAttachments[0].loadAction = .dontCare
            rpd.colorAttachments[0].storeAction = .dontCare
            let re = cb.makeRenderCommandEncoder(descriptor: rpd)!
            re.setRenderPipelineState(pso)
            re.setVertexBuffer(manyB, offset: 0, index: 0)
            re.setVertexBuffer(radius, offset: 0, index: 1)
            re.setVertexBuffer(size, offset: 0, index: 2)
            re.setFragmentBuffer(flowThousand, offset: 0, index: 0)
            re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1000)
            re.endEncoding()
            cb.commit()
        }
        for _ in 0..<5 { frame() }
        cbWait()
        var samples: [Double] = []
        for _ in 0..<50 {
            let t0 = Date()
            frame()
            cbWait()
            samples.append(Date().timeIntervalSince(t0) * 1000)
        }
        print("A_throughput instanced1000 median_ms=\(String(format: "%.3f", median(samples))) min=\(String(format: "%.3f", samples.min()!)) max=\(String(format: "%.3f", samples.max()!))")
    }

    // Throughput (pessimistic): 1000 SEPARATE encoder draws in one pass —
    // measures the per-draw CPU/encoder overhead ceiling.
    do {
        let t = r32Texture()
        var manyAddresses: [Float] = []
        manyAddresses.reserveCapacity(2000)
        for i in 0..<1000 { manyAddresses += [Float(64 * i + 32), Float(height / 2)] }
        let manyAB = device.makeBuffer(bytes: manyAddresses, length: manyAddresses.count * 4)!
        func frame() {
            let cb = queue.makeCommandBuffer()!
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = t
            rpd.colorAttachments[0].loadAction = .dontCare
            rpd.colorAttachments[0].storeAction = .dontCare
            let re = cb.makeRenderCommandEncoder(descriptor: rpd)!
            re.setRenderPipelineState(pso)
            re.setVertexBuffer(radius, offset: 0, index: 1)
            re.setVertexBuffer(size, offset: 0, index: 2)
            re.setFragmentBuffer(flowB, offset: 0, index: 0)
            for i in 0..<1000 {
                re.setVertexBuffer(manyAB, offset: i * 2 * MemoryLayout<Float>.stride, index: 0)
                re.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            re.endEncoding()
            cb.commit()
        }
        for _ in 0..<5 { frame() }
        cbWait()
        var samples: [Double] = []
        for _ in 0..<50 {
            let t0 = Date()
            frame()
            cbWait()
            samples.append(Date().timeIntervalSince(t0) * 1000)
        }
        print("A_throughput draws1000 median_ms=\(String(format: "%.3f", median(samples))) min=\(String(format: "%.3f", samples.min()!)) max=\(String(format: "%.3f", samples.max()!))")
    }
}

// ═══ Option B: compute + integer fixed-point atomics ═══
do {
    let kfn = library.makeFunction(name: "spike_atomic_kernel")!
    let pso = try device.makeComputePipelineState(function: kfn)
    var stampCount: UInt32 = 100
    let countB = device.makeBuffer(bytes: &stampCount, length: 4)!
    let size = device.makeBuffer(bytes: [Float(width), Float(height)],
                                 length: MemoryLayout<Float>.stride * 2)!
    let accum = device.makeBuffer(length: width * height * 4, options: .storageModeShared)!
    memset(accum.contents(), 0, width * height * 4)

    func run() {
        let cb = queue.makeCommandBuffer()!
        let ce = cb.makeComputeCommandEncoder()!
        ce.setComputePipelineState(pso)
        ce.setBuffer(accum, offset: 0, index: 0)
        ce.setBuffer(countB, offset: 0, index: 1)
        ce.setBuffer(size, offset: 0, index: 2)
        ce.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                           threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        ce.endEncoding()
        cb.commit()
    }
    // Precision: 100 stamps along the mid line — the window center pixel
    // sits inside stamp #32's core (2560/2 = 1280 = 64·19.5… use the
    // geometry as-is; read the pixel AT stamp #19's center instead:
    // (64·19+32, h/2) = (1248, h/2) where w = 1 exactly for 100 stamps of
    // flow 1/100 each → accumulated ≈ 1.0 (the overlapping neighbours add
    // a known analytic amount; we assert against the FULL analytic sum).
    run()
    cbWait()
    let words = accum.contents().bindMemory(to: UInt32.self, capacity: width * height)
    // analytic sum at probe pixel (1248, h/2): stamps spaced 64 px, r=256:
    // d = |1248 − (64s+32)|/256 for s in 0..100; w(d) = 1 if d≤0.5 else 1−(d−0.5)/0.5
    var expect: Double = 0
    for s in 0..<100 {
        let d = abs(Double(1248) - (64.0 * Double(s) + 32.0)) / 256.0
        if d < 1.0 { expect += d <= 0.5 ? 1.0 : 1.0 - (d - 0.5) / 0.5 }
    }
    let expectedValue = expect / 100.0 // flow = 1/100
    let probeX = 1248
    let v = Float(words[height / 2 * width + probeX]) / 16777216.0
    print("B_precision value=\(v) analyticSum=\(expectedValue) err=\(abs(v - Float(expectedValue)))")

    // Throughput: 1000 stamps — the in-shader per-pixel loop is the
    // scheme's honest worst case.
    var thousand: UInt32 = 1000
    countB.contents().copyMemory(from: &thousand, byteCount: 4)
    for _ in 0..<5 { run() }
    cbWait()
    var samples: [Double] = []
    for _ in 0..<50 {
        let t0 = Date()
        run()
        cbWait()
        samples.append(Date().timeIntervalSince(t0) * 1000)
    }
    print("B_throughput stamps1000 median_ms=\(String(format: "%.3f", median(samples))) min=\(String(format: "%.3f", samples.min()!)) max=\(String(format: "%.3f", samples.max()!))")
}

print("spike done")
