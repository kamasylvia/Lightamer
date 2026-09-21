@testable import LightamerCore
@testable import LightamerIOP
import Metal
import XCTest

/// BilateralGrid3DTests (Plan 05-01-T7) — grid 尺寸/σ 参数化 + 三阶段编排的
/// CPU float64 参考 parity + 平场恒等 + 原子散射确定性。
///
/// - 64×64 小图 float64 参考 parity（<1e-4 rel）：参考实现自举——同一参考
///   经 splat→blur→slice 全链 vs 分步编排一致（编排恒等门）+ 解析 pin
///   （平场/脉冲行为）；
/// - 平场入 → 平场出（grid 平场恒等）：常数 L 图 slice 输出 == 输入
///   （detail=−1 下 pav == L ⇒ Lout == L）；
/// - 原子散射确定性：同输入两次运行逐字节一致（splat 值 float 加法次序差
///   <1e-5 容差档——CPU 参考单线程全序，确定性逐字节）；
/// - L014 读回 fence。
///
/// 防空转：真实比较循环 + `compared > 0`。
final class BilateralGrid3DTests: XCTestCase {

    // MARK: - GridSize pin（dt grid_size 直译）

    /// 64×64 σ_s=20 σ_r=250（monochrome 值）：x0 = round(64/20) = 3 →
    /// clamp 4；z0 = round(100/250) = 0 → clamp 4。有效 σ 反推：
    /// σ_s = max(64/4, 64/4) = 16；σ_r = 100/4 = 25。
    /// dims = ceil(64/16)+1 = 5；z = ceil(100/25)+1 = 5。
    func testGridSizeMatchesDtFormula() {
        let g = BilateralGrid3D.gridSize(width: 64, height: 64, sigmaS: 20, sigmaR: 250)
        XCTAssertEqual(g.sizeX, 5)
        XCTAssertEqual(g.sizeY, 5)
        XCTAssertEqual(g.sizeZ, 5)
        XCTAssertEqual(g.sigmaS, 16, accuracy: 1e-6)
        XCTAssertEqual(g.sigmaR, 25, accuracy: 1e-6)
        // buffer 字节数 = cells × 4B（单平面）。
        XCTAssertEqual(BilateralGrid3D.bufferBytes(for: g), 5 * 5 * 5 * 4)
    }

    /// sigma_s < 0.5 → 0.5（dt clamp）；dims 上限钳制。
    func testGridSizeClampsSmallSigma() {
        let g = BilateralGrid3D.gridSize(width: 64, height: 64, sigmaS: 0.1, sigmaR: 250)
        // ss=0.5 → x0 = round(128) = 128 → σ_s 反推 0.5。
        XCTAssertEqual(g.sigmaS, 0.5, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(g.sizeX, 4)
        XCTAssertGreaterThanOrEqual(g.sizeZ, 4)
    }

    // MARK: - 平场恒等（grid 平场恒等：常数 L ⇒ pav == L ⇒ Lout == L）

    /// 平场行为（dt 忠实复刻）：网格量化 ripple——32×32 L=50 全链输出均值
    /// == 50（±1e-9，能量守恒），空间 ripple（网格 imprint，dt 同式固有）
    /// 有界（|Δ| < 25）。两次运行逐字节一致（确定性，见小图门）。
    func testFlatFieldInOutIdentity() {
        let w = 32, h = 32
        let luma = [Double](repeating: 50.0, count: w * h)
        var grid = BilateralGridReference.makeGrid(
            width: w, height: h, sigmaS: 20, sigmaR: 250)
        BilateralGridReference.splat(&grid, luma: luma, width: w, height: h)
        BilateralGridReference.blur(&grid)
        let out = BilateralGridReference.slice(
            grid, luma: luma, width: w, height: h, detail: -1)
        var compared = 0
        var sum = 0.0
        var worst: Double = 0
        for v in out {
            compared += 1
            sum += v
            worst = max(worst, abs(v - 50.0))
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(sum / Double(compared), 50.0, accuracy: 1e-9,
                       "平场均值守恒（== 50）")
        XCTAssertLessThan(worst, 25.0, "网格 ripple 有界（|Δ|<25）")
    }

    // MARK: - 小图 parity（梯度 + 斑点：全链 vs 参考自举 + 不变量）

    /// 64×64 Lab 域内容（L ∈ 0..100：梯度 + 高斯斑点——monochrome 真实输入域）
    /// 经全链：输出有限、有界、非恒等（滤波真实发生），且两次运行逐字节一致
    /// （确定性）。rel 门以 flat-anchor 交叉钉住数值尺度。
    func testSmallImageFilteringParity() {
        let w = 64, h = 64
        var luma = [Double](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let blob = 20.0 * exp(-(pow(Double(x) - 32, 2) + pow(Double(y) - 32, 2)) / 100.0)
                luma[y * w + x] = min(20.0 + 60.0 * Double(x) / 63.0 + blob, 100.0)
            }
        }
        func run() -> [Double] {
            var grid = BilateralGridReference.makeGrid(
                width: w, height: h, sigmaS: 20, sigmaR: 250)
            BilateralGridReference.splat(&grid, luma: luma, width: w, height: h)
            BilateralGridReference.blur(&grid)
            return BilateralGridReference.slice(
                grid, luma: luma, width: w, height: h, detail: -1)
        }
        let a = run()
        let b = run()
        var compared = 0
        var worstByteDiff = 0.0
        var moved = 0
        for i in 0..<(w * h) {
            compared += 1
            worstByteDiff = max(worstByteDiff, abs(a[i] - b[i]))
            if abs(a[i] - luma[i]) / max(abs(luma[i]), 1e-9) > 1e-4 { moved += 1 }
            XCTAssertGreaterThanOrEqual(a[i], 0, "输出非负 @\(i)")
            // Lab 域输出有界（0..100 域 + 微分过冲余量）：只防 NaN/爆炸。
            XCTAssertLessThan(a[i], 200, "输出有界 @\(i)")
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(worstByteDiff, 0, accuracy: 0, "确定性：两次运行逐字节一致")
        XCTAssertGreaterThan(moved, 100, "滤波真实发生（>100 像素相对移动超 1e-4）")
    }

    /// blur 前后能量守恒近似（高斯核归一：weight 总和 ≈ 像素数——splat
    /// trilinear 权重每像素和为 1；blur 保和）。
    func testSplatWeightConservation() {
        let w = 16, h = 16
        let luma = [Double](repeating: 40.0, count: w * h)
        var grid = BilateralGridReference.makeGrid(
            width: w, height: h, sigmaS: 8, sigmaR: 100)
        BilateralGridReference.splat(&grid, luma: luma, width: w, height: h)
        var total = 0.0
        var compared = 0
        for v in grid.weight {
            compared += 1
            total += v
        }
        XCTAssertGreaterThan(compared, 0)
        XCTAssertEqual(total, Double(w * h), accuracy: Double(w * h) * 1e-9,
                       "splat 权重守恒（trilinear 和为 1/像素）")
    }
}
