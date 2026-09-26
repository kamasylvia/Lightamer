import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// MonochromeGridLeg (Plan 05-05-T2) — monochrome bilateral grid 腿的 GPU
// 编排：filter 纹理 → splat/blur/slice（BilateralGrid3D kernels）→ in-place
// 回写 filter 纹理（monochrome.c:225-229 CPU 形；CL 腿 :274-280 经 dev_tmp
// 中转——我方 slice 写单平面后 blit 回源，等价语义）。
//
// dt 映射（monochrome.c:220-223）：
//   scale = max(iscale/roi.scale, 1)（CPU；CL :260 无 max——D5 记录）；
//   σ_r = 250（与 scale 无关）；σ_s = 20/scale；detail = −1。
// scale 折算走 `roi.scale ÷ piece.iscale`（05-01 API；L021——禁对 dscIn
// ×scale；分块==整幅门是直接验证，半径漂移即缝）。
//
// L018：grid ping-pong 双缓冲（device buffer）；L014：调用方 fence 覆盖读回。
// ─────────────────────────────────────────────────────────────────────────

public enum MonochromeGridLeg {

    /// monochrome σ 参数（monochrome.c:220-223 CPU 形，max 钳制）。
    /// - Parameters:
    ///   - roiScale: 本 run 平面 scale（roi.scale）。
    ///   - iscale: 入口 scale（piece.iscale；05-01 API）。
    /// - Returns: (sigmaS, sigmaR, detail)。
    public static func sigmas(roiScale: Float, iscale: Float) -> (Float, Float, Float) {
        let scale = max(iscale / max(roiScale, 1e-9), 1.0)
        return (20.0 / scale, 250.0, -1.0)
    }

    /// CL 形 scale（无 max 钳制；monochrome.c:260——D5 记录偏离）。
    public static func sigmasCL(roiScale: Float, iscale: Float) -> (Float, Float, Float) {
        let scale = iscale / max(roiScale, 1e-9)
        return (20.0 / scale, 250.0, -1.0)
    }

    /// grid 腿 in-place 平滑：filter 纹理（L = 100·f）经 grid 后回写。
    public static func smooth(
        filter: any MTLTexture, width: Int, height: Int,
        roiScale: Float, iscale: Float, metal: MetalContext
    ) async throws {
        let (sigmaS, sigmaR, detail) = sigmas(roiScale: roiScale, iscale: iscale)
        let grid = BilateralGrid3D.gridSize(
            width: width, height: height, sigmaS: sigmaS, sigmaR: sigmaR)
        let cells = grid.cellCount
        guard cells > 0 else { return }
        guard let gridA = metal.device.makeBuffer(
            length: cells * MemoryLayout<Float>.stride, options: .storageModeShared),
            let gridB = metal.device.makeBuffer(
                length: cells * MemoryLayout<Float>.stride, options: .storageModeShared)
        else {
            throw MetalError.bufferAllocationFailed(cells * 4)
        }
        // 零填充（splat 原子加累积——L018 buffer 纪律：调用方清零）。
        memset(gridA.contents(), 0, cells * MemoryLayout<Float>.stride)
        var uniforms = BilateralGridUniforms(
            sizeX: Int32(grid.sizeX), sizeY: Int32(grid.sizeY), sizeZ: Int32(grid.sizeZ),
            sigmaS: grid.sigmaS, sigmaR: grid.sigmaR, detail: detail,
            width: Int32(width), height: Int32(height))
        guard let uniformBuffer = metal.device.makeBuffer(
            bytes: &uniforms, length: MemoryLayout<BilateralGridUniforms>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        // splat（filter L → gridA）。
        do {
            let session = try await metal.makeEncoder(functionName: BilateralGrid3D.splatFunction)
            session.encoder.setTexture(filter, index: 0)
            session.encoder.setBuffer(gridA, offset: 0, index: 0)
            session.encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
            session.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding()
            session.commandBuffer.commit()
        }
        // blur：x → y（高斯）→ z（−2 阶导），ping-pong（dt blur 编排 :380-394）。
        var ping = gridA, pong = gridB
        // x 维：ny×nz 线程。
        try await blurAxis(
            input: ping, output: pong, axis: 0,
            nx: grid.sizeX, ny: grid.sizeY, nz: grid.sizeZ,
            uniformBuffer: uniformBuffer, metal: metal)
        swap(&ping, &pong)
        // y 维：nx×nz 线程。
        try await blurAxis(
            input: ping, output: pong, axis: 1,
            nx: grid.sizeX, ny: grid.sizeY, nz: grid.sizeZ,
            uniformBuffer: uniformBuffer, metal: metal)
        swap(&ping, &pong)
        // z 维：nx×ny 线程。
        do {
            let session = try await metal.makeEncoder(functionName: BilateralGrid3D.blurLineZFunction)
            session.encoder.setBuffer(ping, offset: 0, index: 0)
            session.encoder.setBuffer(pong, offset: 0, index: 1)
            session.encoder.setBuffer(uniformBuffer, offset: 0, index: 2)
            session.encoder.dispatchThreads(
                MTLSize(width: grid.sizeX, height: grid.sizeY, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding()
            session.commandBuffer.commit()
        }
        swap(&ping, &pong)
        // slice：filter → filter（in-place 回写经单平面中转——slice kernel
        // 读 in 写 out 双纹理；CL 腿 :278 经 dev_tmp 中转同构）。
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let sliced = metal.device.makeTexture(descriptor: descriptor) else {
            throw MetalError.deviceUnavailable
        }
        do {
            let session = try await metal.makeEncoder(functionName: BilateralGrid3D.sliceFunction)
            session.encoder.setTexture(filter, index: 0)
            session.encoder.setTexture(sliced, index: 1)
            session.encoder.setBuffer(ping, offset: 0, index: 0)
            session.encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
            session.encoder.dispatchThreads(
                MTLSize(width: width, height: height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            session.encoder.endEncoding()
            session.commandBuffer.commit()
        }
        // sliced → filter（blit 回写）。
        guard let commandBuffer = try? metal.makeRoutedCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw MetalError.deviceUnavailable
        }
        blit.copy(
            from: sliced, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: filter, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding() // L008
        commandBuffer.commit()
    }

    private static func blurAxis(
        input: any MTLBuffer, output: any MTLBuffer, axis: Int32,
        nx: Int, ny: Int, nz: Int,
        uniformBuffer: any MTLBuffer, metal: MetalContext
    ) async throws {
        var axisCopy = axis
        guard let axisBuffer = metal.device.makeBuffer(
            bytes: &axisCopy, length: MemoryLayout<Int32>.stride,
            options: .storageModeShared)
        else {
            throw MetalError.deviceUnavailable
        }
        let session = try await metal.makeEncoder(functionName: BilateralGrid3D.blurLineFunction)
        session.encoder.setBuffer(input, offset: 0, index: 0)
        session.encoder.setBuffer(output, offset: 0, index: 1)
        session.encoder.setBuffer(uniformBuffer, offset: 0, index: 2)
        session.encoder.setBuffer(axisBuffer, offset: 0, index: 3)
        // 调度：axis=0（x 维）铺 (ny,nz)；axis=1（y 维）铺 (nx,nz)
        // （kernel 头注；05-01 T7 workgroup 选型）。
        let (dw, dh) = axis == 0 ? (ny, nz) : (nx, nz)
        session.encoder.dispatchThreads(
            MTLSize(width: max(dw, 1), height: max(dh, 1), depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }
}

/// BilateralGridUniforms 的 Swift 镜像（BilateralGrid3DKernels.metal 同布局）。
struct BilateralGridUniforms {
    var sizeX: Int32
    var sizeY: Int32
    var sizeZ: Int32
    var sigmaS: Float
    var sigmaR: Float
    var detail: Float
    var width: Int32
    var height: Int32
}
