import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// BilateralModule (Plan 05-08, IOP-DENOISE-03) — dt `bilateral`
// ("surface blur", v50 10.0, RGB 域), ported from
//   - src/iop/bilateral.cc (:52-58 params 20B; :121-318 三档 process;
//     :320-327 `_compute_sigmas`; :352-372 tiling_callback) (tree dc58cf0ba1)
//   - data/kernels/bilateral.cl (3D grid 的 edge/blur 形 → 5 维推广)
// 参见 BilateralKernels.metal 头注（两档 kernel 直译细节）。
//
// `_compute_sigmas` 逐行核（bilateral.cc:320-327，RESEARCH 标 Med confidence
// 在此钉死；逐字段对照表入 05-08-DECISIONS D-05-08-T1-1）：
//   sigma[0] = data->sigma[0] * scale / iscale;   // scale = roi_in->scale
//   sigma[1] = data->sigma[1] * scale / iscale;   // data->sigma[0..1] = radius
//   sigma[2..4] = data->sigma[2..4];              // = red/green/blue（不折算）
// → Swift 映射 σs = radius × (roi.scale ÷ piece.iscale)（L021 合规标量式——
// 禁 dscIn ×scale）；σr/g/b 全尺度恒定。process 调用点 :258 传
// (roi_in->scale, piece->iscale)，与 tileHalo 的取值源一致 → 整幅/分块执行
// 同 σ，分块==整幅的结构前提。
//
// 两档路径（dt :265-271 逐行）：
//   prad = (int)(3·max(σx,σy) + 1)          // σx==σy==σs；C int 截断
//   rad  = MIN(prad, MIN(w,h) − 2·prad)      // 平面太小则收缩
//   rad < 1 || (rad ≤ 6 && thumb) → identity copy（dt :268-271；thumb 跳档
//       语义 = dt_pipe_is_thumb → 本实现按 piece.pipeType == .thumbnail，
//       DECISIONS D-05-08-T1-2）
//   rad ≤ 6 → DIRECT stamp（bilateral.cc:175-254）
//   else    → 5D GRID（dt CPU = permutohedral lattice；本实现 = 稠密 5D
//       网格 + OQ7 预算协商——见 `gridPlan`/D-05-08-T2-1）
//
// SEED（D-05-08-T1-3）：DISABLED —— plan 原文「σ→0 恒等 → 中性 seed
// enabled」的前件不成立：params radius $MIN 1.0（σ→0 不可达，rad=4 仍平滑），
// 无零参恒等 → colorbalancergb D1 / nlmeans D-05-06-T2-1 同处置（identity
// 只经 disabled piece 成立）。dt 侧 bilateral.cc 无 default_enabled 覆写
// （dt 默认启用——我们按项目 seed 纪律 DISABLED，差异记录 DECISIONS）。
//
// ROI（L020/L021）：identity（dt 无 modify_roi 覆写——空间支持全靠
// tiling overlap=rad）。
// ─────────────────────────────────────────────────────────────────────────

public enum BilateralKernel {
    public static let directFunction = "bilateral_direct"
    public static let splatFunction = "bilateral5d_splat"
    public static let blurLineFunction = "bilateral5d_blur_line"
    public static let sliceFunction = "bilateral5d_slice"
    public static let metalBundle = Bundle(for: IOPBundleMarker.self)
}

public final class BilateralModule: IOPModule {

    /// dt `dt_iop_bilateral_params_t` verbatim (bilateral.cc:52-58, 20B).
    public struct Params: Codable, Hashable, Sendable {
        /// dt `radius` ($MIN 1.0 $MAX 50.0 $DEFAULT 15.0; GUI soft range 1-30).
        public var radius: Float
        /// dt `reserved`（20B blob 版式保位；无语义）.
        public var reserved: Float
        /// dt `red` ($MIN 0.0001 $MAX 1.0 $DEFAULT 0.005; soft max 0.1).
        public var red: Float
        /// dt `green`（同上）.
        public var green: Float
        /// dt `blue`（同上）.
        public var blue: Float

        public init(
            radius: Float = 15, reserved: Float = 15,
            red: Float = 0.005, green: Float = 0.005, blue: Float = 0.005
        ) {
            self.radius = radius
            self.reserved = reserved
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public static let opName = "bilateral"

    /// Darktable v50 order slot 10.0（demosaic 8.0 → denoiseprofile 9.0 →
    /// bilateral 10.0 → … → colorin 28.0；V50Order 现表）。
    public static let iopOrder: Float = 10.0

    public static let flags: IOPFlags = [.supportsBlending, .allowTiling]
    public static let defaultColorspace: IOPColorspace = .RGB

    // MARK: - Pure derivations (bilateral.cc 逐行——internal 供测试钉参)

    /// dt MAX_DIRECT_STAMP_RADIUS (bilateral.cc:48).
    public static let maxDirectStampRadius = 6

    /// dt `_compute_sigmas` :320-327 → 空间 σ（σx==σy，dt :352-353 两行同式
    /// 同值；scale=roi.scale，iscale=piece.iscale）。L021：标量补偿式，
    /// dscIn 禁再 ×scale。
    static func spatialSigma(radius: Float, roiScale: Float, iscale: Float) -> Float {
        radius * roiScale / iscale
    }

    /// dt :259 `fmaxf(sigma[0], sigma[1]) < 0.1f` → copy（σs 太小 = 无操作）。
    static func identityBelowSigma(spatialSigma: Float) -> Bool {
        spatialSigma < 0.1
    }

    /// dt :265 `prad = (int)(3.0f * fmaxf(sigma[0], sigma[1]) + 1.0f)`（C 截断）。
    static func stampRadius(spatialSigma: Float) -> Int {
        Int(3 * spatialSigma + 1)
    }

    /// dt :266 `rad = MIN(prad, MIN(roi_out->width, roi_out->height) - 2*prad)`。
    static func clampedStampRadius(prad: Int, width: Int, height: Int) -> Int {
        min(prad, min(width, height) - 2 * prad)
    }

    /// 两档路径决策（dt :265-271 逐行；纯函数供测试断言路径切换）。
    public enum Leg: Equatable, Sendable {
        case identity
        case direct(rad: Int)
        case grid(rad: Int)

        /// dt tiling_callback :370 `overlap = rad`（identity 项 dt 亦按 rad
        /// 报 overlap——本实现 identity → 0，免无谓 halo；DECISIONS 注记）。
        public var halo: Int {
            switch self {
            case .identity: return 0
            case .direct(let rad): return rad
            case .grid(let rad): return rad
            }
        }
    }

    static func leg(
        spatialSigma: Float, roiWidth: Int, roiHeight: Int, pipeType: PipeResolution
    ) -> Leg {
        if identityBelowSigma(spatialSigma: spatialSigma) { return .identity }
        let prad = stampRadius(spatialSigma: spatialSigma)
        let rad = clampedStampRadius(prad: prad, width: roiWidth, height: roiHeight)
        if rad < 1 { return .identity }
        // dt :268-271：thumbnail 上直连档直接跳过（CPU naive 太慢）；grid 档
        // dt 对 thumbnail 照跑。本实现按 pipeType 决策（D-05-08-T1-2）。
        if rad <= maxDirectStampRadius && pipeType == .thumbnail { return .identity }
        if rad <= maxDirectStampRadius { return .direct(rad: rad) }
        return .grid(rad: rad)
    }

    // MARK: - OQ7：5D grid 预算（D-05-08-T2-1 定稿，plan 期决策 T）

    /// 单格 payload 字节数：float4（w·r, w·g, w·b, w）= 16B。
    public static let gridCellBytes = 16

    /// OQ7 预算：单次执行的 5D 网格 buffer 上界（plane 级协商；分块由
    /// TilingPlan 按 `tileWorkingSetBytesPerPixel` 摊销自动承接——dt maxbuf
    /// 对应物）。1.5GB：FULL tile working 预算族（MemoryBudgetTests
    /// Δfootprint <3GB 门）半值，M 系列 32GB+ 统一内存安全位。
    public static let gridMemoryBudgetBytes = 1_500_000_000

    /// 网格 dims（dt src/common/bilateral.c:47-89 `dt_bilateral_grid_size`
    /// 的 5 维推广）：spatial = ⌈ext/σs⌉+1（clamp [4,3000]，dt 同款上下限）；
    /// range = ⌈1/σc⌉+1（值域 [0,1]，clamp 下限 4）。有效 σ 由 clamp 后 dims
    /// 反推（dt 同形：ss = max(w/x0, h/y0)；σc = 1/(cells−1)——kernel 端
    /// p/σc ∈ [0, cells−1] 的映射自洽要求）。
    public static func gridDims(
        width: Int, height: Int, sigmaS: Double, sigmaR: Double, sigmaG: Double, sigmaB: Double
    ) -> (cells: (Int, Int, Int, Int, Int), sigma: (Double, Double, Double, Double)) {
        func spatialCells(_ ext: Double, _ s: Double) -> Int {
            min(max(Int((ext / s).rounded(.up)) + 1, 4), 3000)
        }
        func rangeCells(_ s: Double) -> Int {
            max(Int((1.0 / s).rounded(.up)) + 1, 4)
        }
        let (sr, sg, sb) = (sigmaR, sigmaG, sigmaB)
        let (cr, cg, cb) = (rangeCells(sr), rangeCells(sg), rangeCells(sb))
        // dt :64-65 反推有效 σs（clamp 命中时放大；未命中时 ≈σs 微缩——dt 同形）。
        let ss = max(Double(width) / Double(spatialCells(Double(width), sigmaS)),
                     Double(height) / Double(spatialCells(Double(height), sigmaS)))
        let cx = spatialCells(Double(width), ss)
        let cy = spatialCells(Double(height), ss)
        return ((cx, cy, cr, cg, cb), (ss, 1.0 / Double(cr - 1), 1.0 / Double(cg - 1), 1.0 / Double(cb - 1)))
    }

    /// OQ7 网格预算协商（D-05-08-T2-1）：grid_bytes = Πᵢ cellsᵢ × 16B；
    /// 超预算 → σ 等比放粗 c = (bytes/budget)^(1/5)·1.05 重算（dt 3D grid
    /// dim-clamp/re-derive 语义的预算泛化），≤8 轮必收敛（dims 下限
    /// 4⁵=1024 格 =16KB ≪ budget）。`coarsening` 记有效 σ 放大倍数
    /// （1.0 = 未放粗）。
    public static func gridPlan(
        width: Int, height: Int,
        sigmaS: Double, sigmaR: Double, sigmaG: Double, sigmaB: Double,
        budgetBytes: Int = gridMemoryBudgetBytes
    ) -> (cells: (Int, Int, Int, Int, Int), sigma: (Double, Double, Double, Double), bytes: Int, coarsening: Double) {
        var (ss, sr, sg, sb) = (sigmaS, sigmaR, sigmaG, sigmaB)
        var coarsening = 1.0
        for _ in 0..<8 {
            let (cells, sigma) = gridDims(width: width, height: height, sigmaS: ss, sigmaR: sr, sigmaG: sg, sigmaB: sb)
            let bytes = cells.0 * cells.1 * cells.2 * cells.3 * cells.4 * gridCellBytes
            if bytes <= budgetBytes {
                return (cells, sigma, bytes, coarsening)
            }
            let c = pow(Double(bytes) / Double(budgetBytes), 1.0 / 5.0) * 1.05
            ss *= c; sr *= c; sg *= c; sb *= c
            coarsening *= c
        }
        let (cells, sigma) = gridDims(width: width, height: height, sigmaS: ss, sigmaR: sr, sigmaG: sg, sigmaB: sb)
        let bytes = cells.0 * cells.1 * cells.2 * cells.3 * cells.4 * gridCellBytes
        return (cells, sigma, bytes, coarsening)
    }

    // MARK: - 直连档空间核（CPU 预算——dt :183-192 同序）

    /// 归一空间权 m = exp(−(l²+k²)/(2σs²))，整窗求和后逐项除（dt 先累加
    /// weight 再 m /= weight 的次序保真；σ 只用 σx——dt :190 单 σ 形）。
    static func directSpatialWeights(sigmaS: Float, rad: Int) -> [Float] {
        let wd = 2 * rad + 1
        var m = [Float](repeating: 0, count: wd * wd)
        var weight: Float = 0
        for l in -rad...rad {
            for k in -rad...rad {
                let v = exp(-Float(l * l + k * k) / (2 * sigmaS * sigmaS))
                m[(l + rad) * wd + (k + rad)] = v
                weight += v
            }
        }
        for i in m.indices { m[i] /= weight }
        return m
    }

    // MARK: - Tile seam（L020/L021——ROI 恒等；dt tiling_callback :352-372）

    public func modifyROIOut(_ roi: inout ROI, input: ROI, piece: IOPiece) {
        roi = input
    }

    public func modifyROIIn(output roi: ROI, input: inout ROI, piece: IOPiece) {
        input = roi
    }

    /// dt tiling_callback :370 `overlap = rad`（run-level σ 折算——tile 驱动
    /// 以平面 ROI 评估一次，tile 内 piece.iscale/roi.scale 不变）。
    public func tileHalo(roi: ROI, piece: IOPiece) -> Int {
        let sigmaS = Self.spatialSigma(radius: currentRadius, roiScale: roi.scale, iscale: piece.iscale)
        let leg = Self.leg(
            spatialSigma: sigmaS, roiWidth: roi.width, roiHeight: roi.height,
            pipeType: piece.pipeType)
        return leg.halo
    }

    /// dt tiling_callback :355-368 factor 族的 B/px 形：直连/恒等档 = 32
    /// （factor 2.0 的平面半账 + 窗权 buffer 摊销——plan 钉值）；grid 档 =
    /// 32 + plane 级协商 grid_bytes 摊销到全平面像素（dt hash_bytes/(16·px)
    /// 同形）。σ 取 roi.scale=1.0（FULL 最坏保守；piece.dscIn = 平面几何
    /// run-level 常量——L020）。TilingPlan 据此把 grid 档 FULL 大图自动
    /// 分块（dt maxbuf 对应物——超预算承重路径，OQ7 回落腿 ②）。
    public func tileWorkingSetBytesPerPixel(piece: IOPiece) -> Int {
        let planePixels = max(1, piece.dscIn.width * piece.dscIn.height)
        let sigmaS = Self.spatialSigma(radius: currentRadius, roiScale: 1.0, iscale: piece.iscale)
        let leg = Self.leg(
            spatialSigma: sigmaS, roiWidth: piece.dscIn.width, roiHeight: piece.dscIn.height,
            pipeType: piece.pipeType)
        guard case .grid = leg else { return 32 }
        let plan = Self.gridPlan(
            width: piece.dscIn.width, height: piece.dscIn.height,
            sigmaS: Double(sigmaS), sigmaR: Double(currentRed),
            sigmaG: Double(currentGreen), sigmaB: Double(currentBlue))
        return 32 + plan.bytes / planePixels
    }

    /// Radius / range σ for the seam + process derivations（params live in
    /// the box, not the piece — commitParams stamps; defaults = dt defaults）.
    private var currentRadius: Float = 15
    private var currentRed: Float = 0.005
    private var currentGreen: Float = 0.005
    private var currentBlue: Float = 0.005

    // MARK: - Commit

    private let device: (any MTLDevice)?
    private var committed: Params?

    public init(device: (any MTLDevice)? = nil) {
        self.device = device
    }

    public func reloadDefaults(image: DecodedImage) async -> Params {
        Params()
    }

    /// dt `commit_params`（bilateral.cc:326-335）: radius→sigma[0..1]、
    /// red/green/blue→sigma[2..4]（reserved 不参与）。本模块 uniforms 在
    /// process 期按参数直构（直连权 buffer + 5D 网格 dims 依赖 run-level
    /// roi），commit 只记 paramsHash + seam 派生值。
    public func commitParams(_ params: Params, into piece: inout IOPiece) {
        let encoded = ParamsCoding.encode(params)
        piece.paramsHash = StableHash.hash(encoded)
        currentRadius = params.radius
        currentRed = params.red
        currentGreen = params.green
        currentBlue = params.blue
        committed = params
    }

    // MARK: - Scratch（per-size cache；.shared——L018 defect 3）

    struct Scratch {
        let weights: (any MTLBuffer)?   // 直连档 (2r+1)² 归一空间权
        let gridA: any MTLBuffer        // 5D ping-pong A（splat 目标，预清零）
        let gridB: any MTLBuffer        // 5D ping-pong B
        let cellCount: Int
    }

    private var scratch: (Scratch, weightsLen: Int, cells: Int)?

    // MARK: - Process

    public func process(
        input: any MTLTexture,
        output: any MTLTexture,
        roiIn: ROI,
        roiOut: ROI,
        piece: inout IOPiece,
        metal: MetalContext
    ) async throws {
        let params = committed ?? Params()
        let sigmaS = Self.spatialSigma(radius: params.radius, roiScale: roiIn.scale, iscale: piece.iscale)
        let leg = Self.leg(
            spatialSigma: sigmaS, roiWidth: roiOut.width, roiHeight: roiOut.height,
            pipeType: piece.pipeType)
        switch leg {
        case .identity:
            // dt :268-271 copy 路径（terminal_copy input@0 → output@1）。
            try await metal.dispatch2DTexture(
                functionName: TerminalKernels.copy, input: input, output: output)
        case .direct(let rad):
            try await processDirect(
                input: input, output: output, sigmaS: sigmaS,
                sigmaR: params.red, sigmaG: params.green, sigmaB: params.blue,
                rad: rad, metal: metal)
        case .grid:
            try await processGrid(
                input: input, output: output, roiIn: roiIn,
                sigmaS: sigmaS, params: params,
                planeWidth: max(1, piece.dscIn.width), planeHeight: max(1, piece.dscIn.height),
                metal: metal)
        }
    }

    // 直连档（bilateral.cc:175-254 对偶——kernel 主体在 BilateralKernels.metal）。
    private func processDirect(
        input: any MTLTexture, output: any MTLTexture,
        sigmaS: Float, sigmaR: Float, sigmaG: Float, sigmaB: Float,
        rad: Int, metal: MetalContext
    ) async throws {
        let weights = Self.directSpatialWeights(sigmaS: sigmaS, rad: rad)
        let owned = try makeScratch(weightsLength: weights.count, cellCount: 0, metal: metal)
        if let wbuf = owned.weights {
            weights.withUnsafeBytes {
                wbuf.contents().copyMemory(from: $0.baseAddress!, byteCount: weights.count * 4)
            }
        }
        struct DirectUniforms {
            var width: Int32
            var height: Int32
            var radius: Int32
            var isig2r: Float
            var isig2g: Float
            var isig2b: Float
        }
        var u = DirectUniforms(
            width: Int32(input.width), height: Int32(input.height), radius: Int32(rad),
            isig2r: 1 / (2 * sigmaR * sigmaR), isig2g: 1 / (2 * sigmaG * sigmaG),
            isig2b: 1 / (2 * sigmaB * sigmaB))
        let session = try await metal.makeEncoder(functionName: BilateralKernel.directFunction)
        session.encoder.setTexture(input, index: 0)
        session.encoder.setTexture(output, index: 1)
        if let wbuf = owned.weights {
            session.encoder.setBuffer(wbuf, offset: 0, index: 0)
        }
        session.encoder.setBytes(&u, length: MemoryLayout<DirectUniforms>.stride, index: 1)
        session.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        session.encoder.endEncoding()
        session.commandBuffer.commit()
    }

    // 5D grid 档：splat → blur×5（ping-pong）→ slice。
    // 网格 dims 按 PLANE 协商（piece.dscIn——run-level 常量，tile 与整幅同
    // σ/cells 语义）；坐标平面锚定（kernel 端 (gid+offset)/σ，offset = 本矩
    // 形平面原点 − 基 cell·σ 平移——cell 对齐切分，分块==整幅的结构前提）。
    private func processGrid(
        input: any MTLTexture, output: any MTLTexture, roiIn: ROI,
        sigmaS: Float, params: Params,
        planeWidth: Int, planeHeight: Int,
        metal: MetalContext
    ) async throws {
        let plan = Self.gridPlan(
            width: planeWidth, height: planeHeight,
            sigmaS: Double(sigmaS), sigmaR: Double(params.red),
            sigmaG: Double(params.green), sigmaB: Double(params.blue))
        let sigma = plan.sigma

        // 本矩形的平面锚定 cell 基（spatial 维；range 维全域覆盖）。
        let baseX = min(Int((Double(roiIn.x) / sigma.0).rounded(.down)), plan.cells.0 - 4)
        let baseY = min(Int((Double(roiIn.y) / sigma.0).rounded(.down)), plan.cells.1 - 4)
        // 本地 spatial cells：本矩形覆盖 + pentalinear/blur ±2 格余量。
        let localX = max(4, min(plan.cells.0 - baseX, Int((Double(input.width) / sigma.0).rounded(.up)) + 3))
        let localY = max(4, min(plan.cells.1 - baseY, Int((Double(input.height) / sigma.0).rounded(.up)) + 3))
        let planeCells = [plan.cells.0, plan.cells.1, plan.cells.2, plan.cells.3, plan.cells.4]
        let localCells = [localX, localY, plan.cells.2, plan.cells.3, plan.cells.4]
        let cellCount = localCells.reduce(1, *)

        let owned = try makeScratch(weightsLength: 0, cellCount: cellCount, metal: metal)
        // splat 目标清零（.shared host memset——NLMeans 同法；blur out-of-place
        // 整格覆写，ping-pong 双面预清仅 A 必须，B 一并清兜 blur 未写格）。
        memset(owned.gridA.contents(), 0, cellCount * 16)
        memset(owned.gridB.contents(), 0, cellCount * 16)

        struct GridUniforms {
            var width: Int32
            var height: Int32
            var originX: Int32
            var originY: Int32
            var baseX: Int32
            var baseY: Int32
            var cellsX: Int32
            var cellsY: Int32
            var cellsR: Int32
            var cellsG: Int32
            var cellsB: Int32
            var sigmaS: Float
            var sigmaR: Float
            var sigmaG: Float
            var sigmaB: Float
        }
        // 平面锚定浮点采样 + 整数基 cell 减算——tile 与整幅逐位同相位。
        var u = GridUniforms(
            width: Int32(input.width), height: Int32(input.height),
            originX: Int32(roiIn.x), originY: Int32(roiIn.y),
            baseX: Int32(baseX), baseY: Int32(baseY),
            cellsX: Int32(localCells[0]), cellsY: Int32(localCells[1]),
            cellsR: Int32(localCells[2]), cellsG: Int32(localCells[3]), cellsB: Int32(localCells[4]),
            sigmaS: Float(sigma.0), sigmaR: Float(sigma.1), sigmaG: Float(sigma.2), sigmaB: Float(sigma.3))

        // splat → gridA
        let splat = try await metal.makeEncoder(functionName: BilateralKernel.splatFunction)
        splat.encoder.setTexture(input, index: 0)
        splat.encoder.setBuffer(owned.gridA, offset: 0, index: 0)
        splat.encoder.setBytes(&u, length: MemoryLayout<GridUniforms>.stride, index: 1)
        splat.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        splat.encoder.endEncoding()
        splat.commandBuffer.commit()

        // blur ×2 ping-pong（仅 spatial 维 x/y——稠密网格 adaptation：range
        // 维不做 blur，值桶保持桶内均值，域响应由 slice 五线性插值承载；
        // dt lattice 全维 blur 是稀疏格的填充需求，稠密格上会把值桶互相
        // 抹平（域有效 σ ×~1.4），D-05-08-T2-2 记录）。2 次交换后输出在 B。
        var src: any MTLBuffer = owned.gridA
        var dst: any MTLBuffer = owned.gridB
        for axis in 0..<2 {
            let lines = cellCount / localCells[axis]
            var axWidth = (Int32(axis), Int32(min(lines, 8192)))
            let rows = (lines + Int(axWidth.1) - 1) / Int(axWidth.1)
            let blur = try await metal.makeEncoder(functionName: BilateralKernel.blurLineFunction)
            blur.encoder.setBuffer(src, offset: 0, index: 0)
            blur.encoder.setBuffer(dst, offset: 0, index: 1)
            blur.encoder.setBytes(&u, length: MemoryLayout<GridUniforms>.stride, index: 2)
            blur.encoder.setBytes(&axWidth, length: MemoryLayout<(Int32, Int32)>.stride, index: 3)
            blur.encoder.dispatchThreads(
                MTLSize(width: Int(axWidth.1), height: rows, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
            blur.encoder.endEncoding()
            blur.commandBuffer.commit()
            (src, dst) = (dst, src)
        }

        // slice：2 次 (src,dst) 交换后 src = 末次 blur 输出。
        let slice = try await metal.makeEncoder(functionName: BilateralKernel.sliceFunction)
        slice.encoder.setTexture(input, index: 0)
        slice.encoder.setTexture(output, index: 1)
        slice.encoder.setBuffer(src, offset: 0, index: 0)
        slice.encoder.setBytes(&u, length: MemoryLayout<GridUniforms>.stride, index: 1)
        slice.encoder.dispatchThreads(
            MTLSize(width: input.width, height: input.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        slice.encoder.endEncoding()
        slice.commandBuffer.commit()
    }

    private func makeScratch(weightsLength: Int, cellCount: Int, metal: MetalContext) throws -> Scratch {
        if let (cached, wl, c) = scratch, c == cellCount,
            (weightsLength == 0 || wl == weightsLength) {
            return cached
        }
        let weights: (any MTLBuffer)? = weightsLength > 0
            ? metal.device.makeBuffer(length: weightsLength * 4, options: .storageModeShared)
            : nil
        let fallback = metal.device.makeBuffer(length: 16, options: .storageModeShared)
        let gridA = cellCount > 0
            ? metal.device.makeBuffer(length: cellCount * 16, options: .storageModeShared)
            : fallback
        let gridB = cellCount > 0
            ? metal.device.makeBuffer(length: cellCount * 16, options: .storageModeShared)
            : fallback
        guard let a = gridA, let b = gridB else {
            throw MetalError.bufferAllocationFailed(max(cellCount * 32, 16))
        }
        let made = Scratch(weights: weights, gridA: a, gridB: b, cellCount: cellCount)
        scratch = (made, weightsLength, cellCount)
        return made
    }
}

// MARK: - CPU float64 参考（直连公式精确形——测试 target 消费；与
// gen_fixtures.py 的 bilateral_reference 同式双实现）

public enum BilateralSurfaceReference {

    /// 精确 bilateral 窗口公式（bilateral.cc:219-247 float64 形——两档共同
    /// 参考：直连档 <1e-5 / grid 档 <1e-3）。边界 rad 圈原样拷出（dt
    /// :210-217）。
    public static func bilateral(
        _ rgb: [Double], width: Int, height: Int,
        sigmaS: Double, sigmaR: Double, sigmaG: Double, sigmaB: Double
    ) -> [Double] {
        let rad = Int(3 * sigmaS + 1)
        var out = [Double](repeating: 0, count: width * height * 3)
        let isig2 = [1 / (2 * sigmaR * sigmaR), 1 / (2 * sigmaG * sigmaG), 1 / (2 * sigmaB * sigmaB)]
        // 归一空间核（dt 同序）。
        let wd = 2 * rad + 1
        var m = [Double](repeating: 0, count: wd * wd)
        var wsum = 0.0
        for l in -rad...rad {
            for k in -rad...rad {
                let v = exp(-Double(l * l + k * k) / (2 * sigmaS * sigmaS))
                m[(l + rad) * wd + (k + rad)] = v
                wsum += v
            }
        }
        for i in m.indices { m[i] /= wsum }
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 3
                if y < rad || y >= height - rad || x < rad || x >= width - rad {
                    out[o] = rgb[o]; out[o + 1] = rgb[o + 1]; out[o + 2] = rgb[o + 2]
                    continue
                }
                var res = [Double](repeating: 0, count: 3)
                var sumw = 0.0
                for l in -rad...rad {
                    for k in -rad...rad {
                        let q = ((y + l) * width + (x + k)) * 3
                        var diff = 0.0
                        for c in 0..<3 {
                            let d = rgb[o + c] - rgb[q + c]
                            diff += d * d * isig2[c]
                        }
                        let w = m[(l + rad) * wd + (k + rad)] * exp(-diff)
                        for c in 0..<3 { res[c] += rgb[q + c] * w }
                        sumw += w
                    }
                }
                for c in 0..<3 { out[o + c] = res[c] / sumw }
            }
        }
        return out
    }
}
