import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// MonochromeModule (Plan 05-05-T1, IOP-COLOR-06) — dt `monochrome`
// （v50 64.0，Lab 域），逐段直译自
//   - src/iop/monochrome.c（params v2 :47-53 = 16B；_color_filter :168-175；
//     _envelope :177-195；CPU process :197-239；tiling :294-317；
//     commit :319-332 passthrough；GUI :371-581 Lab 色度色轮）
//   - data/kernels/basic.cl:2992-3035（monochrome_filter/monochrome CL 腿）
// （树 dc58cf0ba1）。
//
// SIGMA² 裁决（plan 纪律；RESEARCH §5.3；05-05-DECISIONS D1）：
// - CPU `sigma2 = 2·(size·128)²`（monochrome.c:205）；
// - CL  `sigma2 = (size·128)²`（monochrome.c:257）——dt 自身分歧（差 2 倍
//   滤波宽度），golden 钉 CPU 版（dt-cli 无 OpenCL 走 CPU 路径）。
// - uniforms[2] = sigma2CPU；kernel 头注同步记录 CL 偏差。
//
// 中性 SEED（plan T1 要求论证入 DECISIONS；D2）：size→∞ ⇒ sigma²→∞ ⇒
// filter→1（RE 直接复用同一 uniforms 值）；但 a/b/highlights 非恒等
// 参数（highlights 默认 0 ⇒ t ≡ 1 ⇒ out = f·in/100·in，非恒等）——故
// seed DISABLED（colorbalancergb D1 / channelmixerrgb D1 同处置；
// dt `default_enabled` 无显式 FALSE，但默认参数 size=2 红滤镜非中性，
// 默认链恒等只能经 disabled piece 成立）。
//
// DIVERGENCE（记录）：dt_fast_expf vs 精确 exp（kernel 头注；D3）。
// 默认值 DIVERGENCE（记录）：dt $DEFAULT (a=0,b=0,size=2,highlights=0)；
// 我方 Params() 同值（size=2 非恒等——DISABLED seed 故无中性冲突；
// 面板 reset 行恢复 dt 默认）。
//
// ROI（L020/L021）：monochrome ROI 恒等（dt 无 modify_roi 覆盖；空间支持
// 全靠 tiling_callback :294-317 的 halo/budget 声明）——modifyROIOut/In
// 恒等；dscIn 已含 entry 缩放，钩子内禁再 ×scale；tileHalo 见 T2。
// SEED: DISABLED（上）。
// ─────────────────────────────────────────────────────────────────────────

public enum MonochromeKernel {
    public static let filterFunction = "monochrome_filter"
    public static let applyFunction = "monochrome_apply"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class MonochromeModule: IOPModule {

    /// dt `dt_iop_monochrome_params_t` v2 verbatim（monochrome.c:47-53）。
    public struct Params: Codable, Hashable, Sendable {
        /// dt `a`（滤镜色相点 Lab-a；dt $DEFAULT 0；色轮 ±128）。
        public var a: Float
        /// dt `b`（滤镜色相点 Lab-b；dt $DEFAULT 0）。
        public var b: Float
        /// dt `size`（滤镜半径；dt $DEFAULT 2.0；GUI 滚轮 ∈[0.5, 3.0]）。
        public var size: Float
        /// dt `highlights`（高光保留；dt $MIN 0 $MAX 1 $DEFAULT 0）。
        public var highlights: Float

        public init(a: Float = 0, b: Float = 0, size: Float = 2, highlights: Float = 0) {
            self.a = a
            self.b = b
            self.size = size
            self.highlights = highlights
        }
    }

    public static let opName = "monochrome"

    /// Darktable v50 order slot 64.0.
    public static let iopOrder: Float = 64.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .Lab

    /// Uniforms（float4 ×1 = 16B）：(a, b, sigma2CPU, highlights)。
    /// sigma2CPU = 2·(size·128)²（monochrome.c:205 CPU 版）。
    static let uniformsCount = 4

    /// sigma2CPU（monochrome.c:205；CL 腿 :257 无 2× 系数——D1）。
    /// `internal` for derivation tests.
    static func sigma2CPU(size: Float) -> Float {
        2 * (size * 128) * (size * 128)
    }

    /// sigma2CL（monochrome.c:257；偏离记录——D1）。
    /// `internal` for the divergence pin.
    static func sigma2CL(size: Float) -> Float {
        (size * 128) * (size * 128)
    }

    private let device: (any MTLDevice)?
    private var pieceBuffer: (any MTLBuffer)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params`（:319-332 passthrough）+ sigma² 预计算。
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)

        guard let resolved = device ?? MTLCreateSystemDefaultDevice() else {
            piece.data = nil
            return
        }
        if pieceBuffer == nil || committed != params {
            var floats = [Float](repeating: 0, count: Self.uniformsCount)
            floats[0] = params.a
            floats[1] = params.b
            floats[2] = Self.sigma2CPU(size: params.size)
            floats[3] = params.highlights
            if pieceBuffer == nil {
                pieceBuffer = resolved.makeBuffer(
                    length: Self.uniformsCount * MemoryLayout<Float>.size,
                    options: .storageModeShared
                )
            }
            if let buffer = pieceBuffer {
                floats.withUnsafeBytes {
                    buffer.contents().copyMemory(
                        from: $0.baseAddress!,
                        byteCount: Self.uniformsCount * MemoryLayout<Float>.size
                    )
                }
            }
            committed = params
        }
        piece.data = pieceBuffer
    }

    // MARK: - ROI (L020/L021 — identity; dt has no modify_roi overrides)

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    // MARK: - Tile seam (T2: halo ≈ 2σ_s 向上取整；B/px = 16 + grid 摊销)

    /// dt tiling_callback :315 `overlap = ceil(4·σ_s)`——grid 半径覆盖值。
    /// `internal` for tiling tests. σ_s 折算走 `roi.scale ÷ piece.iscale`
    /// （05-01 API；dt `iscale/roi.scale` 同构，见 T2）。
    static func halo(sigmaS: Float) -> Int {
        Int((4 * sigmaS).rounded(.up))
    }

    /// 有效 σ_s（monochrome.c:298-299：σ_s = 20/scale，σ_r = 250）。
    /// scale = roi.scale ÷ piece.iscale（禁对 dscIn ×scale——L021）。
    /// `internal` for tiling tests.
    static func effectiveSigmaS(roiScale: Float, iscale: Float) -> Float {
        let scale = max(roiScale / max(iscale, 1e-9), 1e-9)
        return 20 / scale
    }

    /// dt tiling_callback :309-310 `factor = 2 + bilat_mem/basebuffer`
    /// （CPU）/ `factor_cl = 3 + bilat_mem/basebuffer`（CL；GPU 腿对偶）。
    /// `internal` for tiling tests.
    static func workingSetBytesPerPixel(gridBytes: Int, outputPixels: Int) -> Int {
        guard outputPixels > 0 else { return 16 }
        return 16 + gridBytes / outputPixels
    }

    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        let sigmaS = Self.effectiveSigmaS(roiScale: roi.scale, iscale: piece.iscale)
        return Self.halo(sigmaS: sigmaS)
    }

    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        // T2 定值：grid dims 由 dscIn 平面尺寸 + σ_s/σ_r 推导；
        // dscIn 为空（未 stamp）时回落 T2 §FULL@σ_s=20 参考值 20 B/px。
        let w = max(piece.dscIn.width, 1)
        let h = max(piece.dscIn.height, 1)
        let sigmaS = Self.effectiveSigmaS(roiScale: 1.0, iscale: piece.iscale)
        let grid = BilateralGrid3D.gridSize(
            width: w, height: h, sigmaS: sigmaS, sigmaR: 250)
        // CL 对偶 memory_use = 2 buffers（bilateral.c:94-96 HAVE_OPENCL 腿）。
        let gridBytes = 2 * BilateralGrid3D.bufferBytes(for: grid)
        return Self.workingSetBytesPerPixel(gridBytes: gridBytes, outputPixels: w * h)
    }

    // MARK: - Process (filter → grid → apply; grid 腿见 T2)

    /// T1 验证形态：filter → apply（grid 腿 T2 接入前 bypass——filter 纹理
    /// 直驱 apply；T2 后 process 经 grid；两者由 `useGridSmoothing` 开关）。
    var useGridSmoothing = true

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        guard let buffer = piece.data else { return }
        let w = input.width, h = input.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let filterTex = metal.device.makeTexture(descriptor: descriptor)
        else {
            throw MetalError.deviceUnavailable
        }
        // Pass 1 — filter（monochrome.c:212-217 CPU 形 / basic.cl:2992 CL 形）。
        try await metal.dispatch2DTexture(
            functionName: MonochromeKernel.filterFunction,
            input: input,
            output: filterTex
        ) { encoder in
            encoder.setBuffer(buffer, offset: 0, index: 0)
        }
        if useGridSmoothing {
            // Pass 2 — bilateral grid 腿（T2；monochrome.c:220-229）。
            try await MonochromeGridLeg.smooth(
                filter: filterTex, width: w, height: h,
                roiScale: roiIn.scale, iscale: piece.iscale, metal: metal)
        }
        // Pass 3 — apply（monochrome.c:232-238 / basic.cl:3011）。
        let session = try await metal.makeEncoder(functionName: MonochromeKernel.applyFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(filterTex, index: 1)
        session.encoder.setTexture(output, index: 2)
        session.encoder.setBuffer(buffer, offset: 0, index: 0)
        session.encoder.dispatchThreads(
            MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    // MARK: - CPU reference (Double mirror for parity tests)

    /// dt `_color_filter`（:168-175）在 Double（精确 exp；dt_fast_expf 偏离
    /// 见 D3）。`sigma2` 由调用方按 CPU 版传入（sigma2CPU）。
    public static func colorFilter(
        ai: Double, bi: Double, a: Double, b: Double, sigma2: Double
    ) -> Double {
        let t = min(max(((ai - a) * (ai - a) + (bi - b) * (bi - b)) / sigma2, 0), 1)
        return exp(-t)
    }

    /// dt `_envelope`（:177-195）在 Double。
    public static func envelope(_ L: Double) -> Double {
        let x = min(max(L / 100.0, 0), 1)
        let beta = 0.6
        if x < beta {
            let tmp = x / beta - 1.0
            return 1.0 - tmp * tmp
        }
        let tmp1 = (1.0 - x) / (1.0 - beta)
        let tmp2 = tmp1 * tmp1
        let tmp3 = tmp2 * tmp1
        return 3.0 * tmp2 - 2.0 * tmp3
    }

    /// dt process apply 腿（:232-238）在 Double：
    /// `t = tt + (1−tt)·(1−highlights)`；`Lout = (1−t)·Lin + t·F·Lin/100`
    /// （F = 平滑后 filter，dt :237 `out·(1/100)·in`）。
    public static func applyValue(
        lin: Double, fSmooth: Double, highlights: Double
    ) -> Double {
        let tt = envelope(lin)
        let t = tt + (1.0 - tt) * (1.0 - highlights)
        return (1.0 - t) * lin + t * fSmooth * lin / 100.0
    }
}
