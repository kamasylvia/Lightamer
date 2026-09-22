@testable import LightamerCore
import LightamerIOP
import Metal
import XCTest

/// NoiseFixtureStatisticsTests (Plan 05-01-T5) — 加噪器统计检验 + 新 fixture
/// 落盘证据。
///
/// 加噪器（`gen_fixtures.poisson_gaussian_noise`）：`var = a·I + b` 逐通道独立
/// 高斯（`random.Random(seed)` Box-Muller，stdlib 确定性）。本套件对加噪
/// fixture 实测：逐通道分箱回归（均值箱 vs 方差）斜率 ≈a、截距 ≈b（容差
/// ±10%），均值无偏（|Δ| < 0.01）。
///
/// 防空转：真实比较循环（逐像素分箱累加）+ `compared > 0`。
final class NoiseFixtureStatisticsTests: XCTestCase {

    private static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input/golden", isDirectory: true)

    private func requireGolden(_ path: String) throws -> URL {
        let url = Self.goldenDir.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip(
                "golden artifact missing: input/golden/\(path) — run "
                    + "`python3 input/golden/fixtures/gen_fixtures.py raw input/golden/fixtures`"
            )
        }
        return url
    }

    /// 剖面钉参 authority（bundle 值硬编码交叉——与 gen_fixtures.NOISE_TIERS 同源）。
    private static let tiers: [(name: String, a: [Double], b: [Double])] = [
        ("iso125",
         [7.65705497686894e-06, 1.54601975602981e-06, 2.30077680147848e-06],
         [2.00608030560566e-09, 3.03636277807135e-09, 4.74823179066283e-09]),
        ("iso1600",
         [2.99037019802356e-05, 8.86355041404361e-06, 1.37779541937624e-05],
         [4.43124422276964e-08, 2.60617465248865e-08, 3.62731233591954e-08]),
    ]

    /// gray_staircase 加噪集：12 中性阶（0.02..1.0）天然分箱——每阶箱内实测
    /// 方差 vs 该阶均值做最小二乘（方差 = a·均值 + b），斜率 ≈a、截距 ≈b
    /// （±10%），均值无偏（加噪均值 vs clean 阶值 |Δ| < 0.01）。
    func testNoisyGrayStaircaseVarianceMatchesProfile() async throws {
        var compared = 0
        for tier in Self.tiers {
            let noisyURL = try requireGolden(
                "fixtures/gray_staircase__noisy_\(tier.name)_s20260921.exr")
            let cleanURL = try requireGolden("fixtures/gray_staircase.exr")
            let noisy = try GoldenParityTests.UncompressedEXR.load(noisyURL)
            let clean = try GoldenParityTests.UncompressedEXR.load(cleanURL)
            XCTAssertEqual(noisy.width, clean.width)
            XCTAssertEqual(noisy.height, clean.height)
            let levels: [Float] = [
                0.02, 0.04, 0.07, 0.10, 0.18, 0.25,
                0.35, 0.50, 0.65, 0.80, 0.90, 1.00,
            ]
            let blockW = noisy.width / levels.count
            for c in 0..<3 {
                var xs: [Double] = []
                var ys: [Double] = []
                var meanBiasWorst = 0.0
                for (li, level) in levels.enumerated() {
                    var sum = 0.0, sum2 = 0.0, n = 0
                    for y in 0..<noisy.height {
                        for x in (li * blockW)..<((li + 1) * blockW) {
                            let v = Double(noisy.rgb[(y * noisy.width + x) * 3 + c])
                            sum += v
                            sum2 += v * v
                            n += 1
                            compared += 1
                        }
                    }
                    let mean = sum / Double(n)
                    let variance = max(sum2 / Double(n) - mean * mean, 0)
                    xs.append(mean)
                    ys.append(variance)
                    meanBiasWorst = max(meanBiasWorst, abs(mean - Double(level)))
                }
                XCTAssertLessThan(
                    meanBiasWorst, 0.01, "\(tier.name) ch\(c): 均值无偏 |Δ|<0.01")
                let (slope, intercept) = leastSquares(xs: xs, ys: ys)
                XCTAssertEqual(
                    slope, tier.a[c], accuracy: abs(tier.a[c]) * 0.10,
                    "\(tier.name) ch\(c): 回归斜率 ≈a (±10%)")
                // 截距门：b ~ 1e-9..1e-8，回归外推截距的标准误（σ²/√N 外推到
                // x=0，杠杆 ~x̄/σx ≈ 2.5）达数 e-8 量级——b 本身只有 2e-9，
                // 故截距只断言数量级（|Δ| < 6e-8 ≈ b 最大档位的 1.5×），
                // 斜率门承担主证据。
                XCTAssertLessThan(
                    abs(intercept - tier.b[c]), 6e-8,
                    "\(tier.name) ch\(c): 回归截距数量级 ≈b (|Δ|<6e-8)")
            }
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// ramp 加噪集恒等 exist 门：文件可读 + dims 与 clean 一致（统计门已由
    /// staircase 承担；此处钉 6 张加噪 EXR 全部落盘）。
    func testAllNoisyFixturesExistWithCleanDims() throws {
        let sources = ["ramp_8ev", "flat_-4ev", "flat_-8ev", "gray_staircase"]
        var compared = 0
        for src in sources {
            let clean = try GoldenParityTests.UncompressedEXR.load(
                try requireGolden("fixtures/\(src).exr"))
            for tier in Self.tiers {
                let noisy = try GoldenParityTests.UncompressedEXR.load(
                    try requireGolden("fixtures/\(src)__noisy_\(tier.name)_s20260921.exr"))
                compared += 1
                XCTAssertEqual(noisy.width, clean.width, "\(src) \(tier.name) 宽")
                XCTAssertEqual(noisy.height, clean.height, "\(src) \(tier.name) 高")
            }
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// hue sweep / delta 脉冲 / torture 落盘门：dims + 内容指纹（sweep 首列红、
    /// 末列近红环闭合；delta 中心白 + 1/4 黑；torture 非恒定）。
    func testNewFixtureSetExistsWithContentPins() throws {
        var compared = 0
        let sweep = try GoldenParityTests.UncompressedEXR.load(
            try requireGolden("fixtures/hue_sweep.exr"))
        XCTAssertEqual(sweep.width, 360)
        XCTAssertEqual(sweep.height, 64)
        // 首列 H=0 → 红（05-04 PEDELTA：S=0.999，非 1.0 — 最小通道 0.001，
        // 相对度量良态；hue 环覆盖不变）；180 列 H=0.5 → 青。
        compared += 1
        XCTAssertEqual(Double(sweep.rgb[0]), 1.0, accuracy: 1e-6, "sweep 首列 R")
        XCTAssertEqual(Double(sweep.rgb[1]), 0.001, accuracy: 1e-6, "sweep 首列 G")
        let cyan = 180 * 3
        XCTAssertEqual(Double(sweep.rgb[cyan]), 0.001, accuracy: 1e-6, "sweep 180 列 R")
        XCTAssertEqual(Double(sweep.rgb[cyan + 2]), 1.0, accuracy: 1e-6, "sweep 180 列 B")

        let delta = try GoldenParityTests.UncompressedEXR.load(
            try requireGolden("fixtures/delta_impulse.exr"))
        XCTAssertEqual(delta.width, 64)
        XCTAssertEqual(delta.height, 64)
        let center = (32 * 64 + 32) * 3
        compared += 1
        XCTAssertEqual(Double(delta.rgb[center]), 1.0, accuracy: 0, "中心白脉冲")
        let black = (16 * 64 + 16) * 3
        XCTAssertEqual(Double(delta.rgb[black]), 0.0, accuracy: 0, "1/4 黑脉冲")
        XCTAssertEqual(Double(delta.rgb[0]), 0.18, accuracy: 1e-6, "背景中灰")

        let torture = try GoldenParityTests.UncompressedEXR.load(
            try requireGolden("fixtures/shadow_torture.exr"))
        XCTAssertEqual(torture.width, 96)
        XCTAssertEqual(torture.height, 96)
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in torture.rgb {
            compared += 1
            lo = min(lo, v)
            hi = max(hi, v)
        }
        XCTAssertGreaterThan(hi, lo, "torture 非恒定（含噪声）")
        XCTAssertGreaterThan(lo, -0.05, "torture 下界 sane")
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - 最小二乘

    private func leastSquares(xs: [Double], ys: [Double]) -> (slope: Double, intercept: Double) {
        let n = Double(xs.count)
        let sx = xs.reduce(0, +), sy = ys.reduce(0, +)
        let sxx = xs.reduce(0) { $0 + $1 * $1 }
        let sxy = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = n * sxx - sx * sx
        precondition(denom != 0)
        let slope = (n * sxy - sx * sy) / denom
        return (slope, (sy - slope * sx) / n)
    }
}
