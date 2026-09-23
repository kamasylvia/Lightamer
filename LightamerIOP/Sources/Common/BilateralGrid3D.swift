import Foundation
import LightamerCore
import Metal

// ─────────────────────────────────────────────────────────────────────────
// BilateralGrid3D (Plan 05-01-T7) — dt 3D bilateral grid 共享件（OQ4 裁决 (a)）。
//
// dt 对照（树 dc58cf0ba1）：
// - `src/common/bilateral.c`：grid_size（:47-89）/ splat（:211-287）/
//   blur_line + blur_line_z（:330-400）/ blur 编排（:403-416：x→y 高斯 + z
//   −2 阶导）/ slice（:419-457，detail=−1 双线性滤波基底）/
//   slice_to_output（:460-488，monochrome 消费形）
// - `data/kernels/bilateral.cl`：grid kernel（splat/blur_line/blur_line_z/
//   slice/slice_to_output 的 CL 对偶；splat 用 local 聚合 + atomic_add_f）
// - monochrome 消费（monochrome.c:221-226）：sigma_r=250（与 scale 无关）、
//   sigma_s=20/scale、detail=−1。
//
// Lightamer 映射：
// - 网格 dims = Swift 侧 `GridSize` 纯推导（grid_size 直译，L_range=100）；
// - splat/blur/slice 三阶段 = `BilateralGrid3DKernels.metal` 三 kernel
//   （splat 原子散射走 HistogramReduce 同模式——device atomic_uint 累加；
//   blur/slice 平铺直译）；
// - CPU float64 参考实现 = `BilateralGridReference`（同文件 `#if DEBUG`
///  外亦可用——小图逐式复算，测试 target 内消费）。
//
// 本 plan 不接任何 IOP 模块（消费责任 05-05 monochrome）。
// ─────────────────────────────────────────────────────────────────────────

/// 网格 dims（dt `dt_bilateral_t` 的尺寸半：size_x/y/z + 有效 sigma）。
public struct BilateralGridSize: Sendable, Equatable {
    public var sizeX: Int
    public var sizeY: Int
    public var sizeZ: Int
    public var sigmaS: Float
    public var sigmaR: Float

    public init(sizeX: Int, sizeY: Int, sizeZ: Int, sigmaS: Float, sigmaR: Float) {
        self.sizeX = sizeX
        self.sizeY = sizeY
        self.sizeZ = sizeZ
        self.sigmaS = sigmaS
        self.sigmaR = sigmaR
    }

    public var cellCount: Int { sizeX * sizeY * sizeZ }
}

public enum BilateralGrid3D {

    public static let splatFunction = "bilateral3d_splat"
    public static let blurLineFunction = "bilateral3d_blur_line"
    public static let blurLineZFunction = "bilateral3d_blur_line_z"
    public static let sliceFunction = "bilateral3d_slice"

    /// dt `dt_bilateral_grid_size`（bilateral.c:47-89）直译：
    /// L_range=100；sigma_s < 0.5 → 0.5；dims clamp x/y∈[4,3000]、z∈[4,50]；
    /// 有效 sigma 由 clamp 后 dims 反推。
    public static func gridSize(
        width: Int, height: Int, sigmaS: Float, sigmaR: Float, lRange: Float = 100
    ) -> BilateralGridSize {
        var ss = max(sigmaS, 0.5)
        let x0 = min(max(Int((Float(width) / ss).rounded()), 4), 3000)
        let y0 = min(max(Int((Float(height) / ss).rounded()), 4), 3000)
        let z0 = min(max(Int((lRange / sigmaR).rounded()), 4), 50)
        ss = max(Float(height) / Float(y0), Float(width) / Float(x0))
        let sr = lRange / Float(z0)
        let sx = Int((Float(width) / ss).rounded(.up)) + 1
        let sy = Int((Float(height) / ss).rounded(.up)) + 1
        let sz = Int((lRange / sr).rounded(.up)) + 1
        return BilateralGridSize(sizeX: sx, sizeY: sy, sizeZ: sz, sigmaS: ss, sigmaR: sr)
    }

    /// 网格 buffer 字节数（单精度单平面；CL 对偶 `memory_use` 的 Metal 形——
    /// blur 需双缓冲时调用方 ×2）。
    public static func bufferBytes(for grid: BilateralGridSize) -> Int {
        grid.cellCount * MemoryLayout<Float>.stride
    }
}

/// CPU float64 参考实现（dt bilateral.c 逐式复刻——splat trilinear 散射 +
/// x/y 高斯 blur_line + z −2 阶导 blur_line_z + slice 三线性查表）。
/// 测试 target 内消费（小图逐式复算；64×64 parity <1e-4 rel）。
public enum BilateralGridReference {

    public struct Grid {
        public var sizeX: Int
        public var sizeY: Int
        public var sizeZ: Int
        public var sigmaS: Double
        public var sigmaR: Double
        /// dt 网格本体（加权计数，splat 缩放 + blur 核归一标定）。
        public var payload: [Double]
        /// 守恒探针平面（单位 trilinear 权重散射——dt 无此平面，参考实现
        /// 自带：splat 权重守恒 + blur 保和的验证通道，不入 slice）。
        public var weight: [Double]
    }

    public static func makeGrid(
        width: Int, height: Int, sigmaS: Double, sigmaR: Double, lRange: Double = 100
    ) -> Grid {
        var ss = max(sigmaS, 0.5)
        let x0 = min(max(Int((Double(width) / ss).rounded()), 4), 3000)
        let y0 = min(max(Int((Double(height) / ss).rounded()), 4), 3000)
        let z0 = min(max(Int((lRange / sigmaR).rounded()), 4), 50)
        ss = max(Double(height) / Double(y0), Double(width) / Double(x0))
        let sr = lRange / Double(z0)
        let sx = Int((Double(width) / ss).rounded(.up)) + 1
        let sy = Int((Double(height) / ss).rounded(.up)) + 1
        let sz = Int((lRange / sr).rounded(.up)) + 1
        let n = sx * sy * sz
        return Grid(
            sizeX: sx, sizeY: sy, sizeZ: sz, sigmaS: ss, sigmaR: sr,
            payload: [Double](repeating: 0, count: n),
            weight: [Double](repeating: 0, count: n))
    }

    private static func gridPoint(
        _ grid: Grid, i: Int, j: Int, l: Double
    ) -> (gi: Int, fx: Double, fy: Double, fz: Double) {
        let x = min(max(Double(i) / grid.sigmaS, 0), Double(grid.sizeX - 1))
        let y = min(max(Double(j) / grid.sigmaS, 0), Double(grid.sizeY - 1))
        let z = min(max(l / grid.sigmaR, 0), Double(grid.sizeZ - 1))
        let xi = min(Int(x), grid.sizeX - 2)
        let yi = min(Int(y), grid.sizeY - 2)
        let zi = min(Int(z), grid.sizeZ - 2)
        return ((xi + yi * grid.sizeX) * grid.sizeZ + zi, x - Double(xi), y - Double(yi), z - Double(zi))
    }

    /// splat（dt `dt_bilateral_splat` 单线程语义 + `bilateral.cl` splat
    /// 对偶）：网格存**加权计数**（非归一化均值）——每像素以
    /// `contrib = 100 / σ_s²` 缩放的 trilinear 权重散射（`contrib[k] ×
    /// (1−zf)/zf`，z 维在 4+4 偏移上分裂）。slice 以该网格的三线性查表
    /// `Ldiff` 经 `norm` 缩放后修正（`L + norm × Ldiff`），不做 payload/weight
    /// 比值（dt 无归一化——blur 核归一 + splat 缩放即完整标定）。
    /// - Parameter luma: 行主序 L 平面（0..100，monochrome 为 filter 输出）。
    public static func splat(_ grid: inout Grid, luma: [Double], width: Int, height: Int) {
        let scale = 100.0 / (grid.sigmaS * grid.sigmaS)
        for j in 0..<height {
            for i in 0..<width {
                let l = luma[j * width + i]
                let (gi, fx, fy, fz) = gridPoint(grid, i: i, j: j, l: l)
                // dt CPU strides (bilateral.c:204-206: ox=size_z, oy=size_x*size_z,
                // oz=1 — base idx=(xi+yi*sizeX)*sizeZ+zi 的 z-minor 布局；
                // 05-01 初版误用 CL 腿 x-minor 步长，05-05-T3 非立方网格暴露。
                let ox = grid.sizeZ, oy = grid.sizeX * grid.sizeZ, oz = 1
                let quad = [
                    (0, (1 - fx) * (1 - fy)),
                    (ox, fx * (1 - fy)),
                    (oy, (1 - fx) * fy),
                    (oy + ox, fx * fy),
                ]
                for (off, w) in quad {
                    grid.payload[gi + off] += w * (1 - fz) * scale
                    grid.payload[gi + off + oz] += w * fz * scale
                    grid.weight[gi + off] += w * (1 - fz)
                    grid.weight[gi + off + oz] += w * fz
                }
            }
        }
    }

    /// blur：x/y 维高斯 [1,4,6,4,1]/16 + z 维 −2 阶导 [−2,−4,+…]/16
    ///（dt `blur_line`/`blur_line_z` + `dt_bilateral_blur` 编排——in-place
    /// 双遍序，payload/weight 同施）。
    public static func blur(_ grid: inout Grid) {
        blurDim(&grid, axis: 0)
        blurDim(&grid, axis: 1)
        blurDimZ(&grid)
    }

    private static func blurDim(_ grid: inout Grid, axis: Int) {
        let (nx, ny, nz) = (grid.sizeX, grid.sizeY, grid.sizeZ)
        let w0 = 6.0 / 16.0, w1 = 4.0 / 16.0, w2 = 1.0 / 16.0
        for buf in [\.payload, \.weight] as [WritableKeyPath<Grid, [Double]>] {
            let src = grid[keyPath: buf]
            var dst = src
            func idx(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + y * nx) * nz + z }
            if axis == 0 {
                for y in 0..<ny {
                    for z in 0..<nz {
                        var t1 = src[idx(0, y, z)]
                        dst[idx(0, y, z)] = src[idx(0, y, z)] * w0 + w1 * src[idx(1, y, z)] + w2 * src[idx(2, y, z)]
                        var t2 = src[idx(1, y, z)]
                        dst[idx(1, y, z)] = src[idx(1, y, z)] * w0 + w1 * (src[idx(2, y, z)] + t1) + w2 * src[idx(min(3, nx - 1), y, z)]
                        for x in 2..<(nx - 2) {
                            let t3 = src[idx(x, y, z)]
                            dst[idx(x, y, z)] = src[idx(x, y, z)] * w0 + w1 * (src[idx(x + 1, y, z)] + t2) + w2 * (src[idx(x + 2, y, z)] + t1)
                            t1 = t2
                            t2 = t3
                        }
                        if nx > 3 {
                            let t3 = src[idx(nx - 2, y, z)]
                            dst[idx(nx - 2, y, z)] = src[idx(nx - 2, y, z)] * w0 + w1 * (src[idx(nx - 1, y, z)] + t2) + w2 * t1
                            dst[idx(nx - 1, y, z)] = src[idx(nx - 1, y, z)] * w0 + w1 * t3 + w2 * t2
                        }
                    }
                }
            } else {
                for x in 0..<nx {
                    for z in 0..<nz {
                        var t1 = src[idx(x, 0, z)]
                        dst[idx(x, 0, z)] = src[idx(x, 0, z)] * w0 + w1 * src[idx(x, 1, z)] + w2 * src[idx(x, 2, z)]
                        var t2 = src[idx(x, 1, z)]
                        dst[idx(x, 1, z)] = src[idx(x, 1, z)] * w0 + w1 * (src[idx(x, 2, z)] + t1) + w2 * src[idx(x, min(3, ny - 1), z)]
                        for y in 2..<(ny - 2) {
                            let t3 = src[idx(x, y, z)]
                            dst[idx(x, y, z)] = src[idx(x, y, z)] * w0 + w1 * (src[idx(x, y + 1, z)] + t2) + w2 * (src[idx(x, y + 2, z)] + t1)
                            t1 = t2
                            t2 = t3
                        }
                        if ny > 3 {
                            let t3 = src[idx(x, ny - 2, z)]
                            dst[idx(x, ny - 2, z)] = src[idx(x, ny - 2, z)] * w0 + w1 * (src[idx(x, ny - 1, z)] + t2) + w2 * t1
                            dst[idx(x, ny - 1, z)] = src[idx(x, ny - 1, z)] * w0 + w1 * t3 + w2 * t2
                        }
                    }
                }
            }
            grid[keyPath: buf] = dst
        }
    }

    private static func blurDimZ(_ grid: inout Grid) {
        let (nx, ny, nz) = (grid.sizeX, grid.sizeY, grid.sizeZ)
        let w1 = 4.0 / 16.0, w2 = 2.0 / 16.0
        for buf in [\.payload, \.weight] as [WritableKeyPath<Grid, [Double]>] {
            let src = grid[keyPath: buf]
            var dst = src
            func idx(_ x: Int, _ y: Int, _ z: Int) -> Int { (x + y * nx) * nz + z }
            for x in 0..<nx {
                for y in 0..<ny {
                    var t1 = src[idx(x, y, 0)]
                    dst[idx(x, y, 0)] = w1 * src[idx(x, y, 1)] + w2 * src[idx(x, y, min(2, nz - 1))]
                    var t2 = src[idx(x, y, 1)]
                    dst[idx(x, y, 1)] = w1 * (src[idx(x, y, 2)] - t1) + w2 * src[idx(x, y, min(3, nz - 1))]
                    for z in 2..<(nz - 2) {
                        let t3 = src[idx(x, y, z)]
                        dst[idx(x, y, z)] = w1 * (src[idx(x, y, z + 1)] - t2) + w2 * (src[idx(x, y, z + 2)] - t1)
                        t1 = t2
                        t2 = t3
                    }
                    if nz > 3 {
                        let t3 = src[idx(x, y, nz - 2)]
                        dst[idx(x, y, nz - 2)] = w1 * (src[idx(x, y, nz - 1)] - t2) - w2 * t1
                        dst[idx(x, y, nz - 1)] = -w1 * t3 - w2 * t2
                    }
                }
            }
            grid[keyPath: buf] = dst
        }
    }

    /// slice（dt `dt_bilateral_slice`，detail=−1 基底形）：
    /// `Lout = max(0, L + norm × Ldiff)`，`norm = −detail × σ_r × 0.04`，
    /// `Ldiff` = 网格三线性查表（dt 无归一化——splat 缩放 + blur 核归一
    /// 即完整标定；`weight` 平面保留作守恒探针，不入 slice）。
    public static func slice(
        _ grid: Grid, luma: [Double], width: Int, height: Int, detail: Double = -1
    ) -> [Double] {
        let norm = -detail * grid.sigmaR * 0.04
        // dt CPU strides（同 splat 注释；dt slice :405-407）。
        let ox = grid.sizeZ, oy = grid.sizeX * grid.sizeZ, oz = 1
        var out = [Double](repeating: 0, count: width * height)
        for j in 0..<height {
            for i in 0..<width {
                let l = luma[j * width + i]
                let (gi, fx, fy, fz) = gridPoint(grid, i: i, j: j, l: l)
                let ldiff = grid.payload[gi] * (1 - fx) * (1 - fy) * (1 - fz)
                    + grid.payload[gi + ox] * fx * (1 - fy) * (1 - fz)
                    + grid.payload[gi + oy] * (1 - fx) * fy * (1 - fz)
                    + grid.payload[gi + ox + oy] * fx * fy * (1 - fz)
                    + grid.payload[gi + oz] * (1 - fx) * (1 - fy) * fz
                    + grid.payload[gi + ox + oz] * fx * (1 - fy) * fz
                    + grid.payload[gi + oy + oz] * (1 - fx) * fy * fz
                    + grid.payload[gi + ox + oy + oz] * fx * fy * fz
                out[j * width + i] = max(0, l + norm * ldiff)
            }
        }
        return out
    }
}
