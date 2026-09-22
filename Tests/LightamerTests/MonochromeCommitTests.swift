@testable import LightamerCore
@testable import LightamerIOP
import XCTest

// MonochromeCommitTests (Plan 05-05-T1) — CPU 推导门：
// sigma² CPU 版预计算（monochrome.c:205 2×）、CL 偏离 pin（:257 无 2×）、
// committed-buffer 写、Double 参考点值（_color_filter/_envelope/apply）、
// 中性恒等论证（size→∞ ⇒ filter→1；DISABLED seed——D2）。
final class MonochromeCommitTests: XCTestCase {

    // MARK: - sigma² derivation (CPU vs CL divergence pin)

    /// monochrome.c:205 — size 2 ⇒ sigma2CPU = 2·(256)² = 131072。
    func testSigma2CPUMatchesDtCPUFormula() {
        XCTAssertEqual(
            Double(MonochromeModule.sigma2CPU(size: 2)), 131072, accuracy: 1e-3)
    }

    /// monochrome.c:257 — CL 腿无 2×：65536（偏离 pin，D1）。
    func testSigma2CLDivergencePinned() {
        XCTAssertEqual(
            Double(MonochromeModule.sigma2CL(size: 2)), 65536, accuracy: 1e-3)
        XCTAssertEqual(
            MonochromeModule.sigma2CPU(size: 2),
            2 * MonochromeModule.sigma2CL(size: 2), accuracy: 1e-3)
    }

    /// commitParams 写 uniforms (a, b, sigma2CPU, highlights)。
    func testCommitWritesCPUUniforms() async {
        let module = MonochromeModule()
        var piece = IOPiece()
        module.commitParams(
            MonochromeModule.Params(a: 32, b: 64, size: 2.3, highlights: 0.5),
            into: &piece)
        let floats = piece.data!.contents().assumingMemoryBound(to: Float.self)
        XCTAssertEqual(floats[0], 32, accuracy: 1e-6)
        XCTAssertEqual(floats[1], 64, accuracy: 1e-6)
        XCTAssertEqual(
            floats[2], MonochromeModule.sigma2CPU(size: 2.3), accuracy: 1e-1)
        XCTAssertEqual(floats[3], 0.5, accuracy: 1e-6)
    }

    // MARK: - Double reference spot values

    /// _color_filter 手算：ai=bi=0，a=b=0 ⇒ t=0 ⇒ f=1。
    func testColorFilterCenterIsOne() {
        let sigma2 = Double(MonochromeModule.sigma2CPU(size: 2))
        XCTAssertEqual(
            MonochromeModule.colorFilter(ai: 0, bi: 0, a: 0, b: 0, sigma2: sigma2),
            1.0, accuracy: 1e-12)
    }

    /// _color_filter 手算：(ai,bi)=(256,0)，(a,b)=(0,0)，sigma2=131072 ⇒
    /// t = 65536/131072 = 0.5 ⇒ f = exp(−0.5) = 0.606531。
    func testColorFilterSpotValue() {
        let sigma2 = Double(MonochromeModule.sigma2CPU(size: 2))
        XCTAssertEqual(
            MonochromeModule.colorFilter(ai: 256, bi: 0, a: 0, b: 0, sigma2: sigma2),
            0.6065306597, accuracy: 1e-9)
    }

    /// _color_filter clamp：远点 ⇒ t 钳制 1 ⇒ f = exp(−1) = 0.367879。
    func testColorFilterClampsAtOne() {
        let sigma2 = Double(MonochromeModule.sigma2CPU(size: 2))
        XCTAssertEqual(
            MonochromeModule.colorFilter(ai: 1000, bi: 1000, a: 0, b: 0, sigma2: sigma2),
            exp(-1.0), accuracy: 1e-12)
    }

    /// _envelope 手算：L=0 ⇒ 0；L=60 (=β) ⇒ 1；L=100 ⇒ 0。
    func testEnvelopeSpotValues() {
        XCTAssertEqual(MonochromeModule.envelope(0), 0, accuracy: 1e-12)
        XCTAssertEqual(MonochromeModule.envelope(60), 1.0, accuracy: 1e-12)
        XCTAssertEqual(MonochromeModule.envelope(100), 0, accuracy: 1e-12)
        // L=30（x=0.3<β）：tmp = 0.5−1 = −0.5 ⇒ 1−0.25 = 0.75。
        XCTAssertEqual(MonochromeModule.envelope(30), 0.75, accuracy: 1e-12)
    }

    /// apply 腿手算：Lin=50，F=100（filter 全通），highlights=0 ⇒
    /// tt=envelope(50)=0.972222；t = tt+(1−tt)·1 = 1 ⇒ Lout = 50。
    func testApplySpotValue() {
        let tt = MonochromeModule.envelope(50) // 0.972222…
        XCTAssertEqual(tt, 0.9722222222, accuracy: 1e-9)
        XCTAssertEqual(
            MonochromeModule.applyValue(lin: 50, fSmooth: 100, highlights: 0),
            50.0, accuracy: 1e-9)
    }

    // MARK: - Neutral identity argument (size→∞ ⇒ filter→1; DISABLED seed)

    /// size→∞（1e6）⇒ sigma²→∞ ⇒ 任意色度点 filter→1（<1e-9 恒等）。
    func testSizeInfinityFilterIdentity() {
        let sigma2 = Double(MonochromeModule.sigma2CPU(size: 1e6))
        var compared = 0
        for (ai, bi) in [(0.0, 0.0), (50.0, -30.0), (-100.0, 100.0), (10.0, 120.0)] {
            compared += 1
            XCTAssertEqual(
                MonochromeModule.colorFilter(ai: ai, bi: bi, a: 0, b: 0, sigma2: sigma2),
                1.0, accuracy: 1e-9)
        }
        XCTAssertGreaterThan(compared, 0)
    }

    /// 非中性方向：色相点向蓝移（b=−64，dt 注释掉的 blue filter 预设方向）
    /// ⇒ 蓝像素 filter > 红像素 filter（输出偏冷灰——plan T1 方向断言）。
    func testBlueFilterDirectionFavorsBlue() {
        let sigma2 = Double(MonochromeModule.sigma2CPU(size: 2.3))
        let blue = MonochromeModule.colorFilter(ai: 0, bi: -60, a: 0, b: -64, sigma2: sigma2)
        let red = MonochromeModule.colorFilter(ai: 0, bi: 60, a: 0, b: -64, sigma2: sigma2)
        XCTAssertGreaterThan(blue, red, "蓝滤镜应对蓝像素响应更强")
    }

    // MARK: - σ chain (T2 scale folding)

    /// effectiveSigmaS：roi.scale ÷ iscale（05-01 API；L021）。
    func testEffectiveSigmaSFoldsScale() {
        XCTAssertEqual(
            MonochromeModule.effectiveSigmaS(roiScale: 1.0, iscale: 1.0), 20, accuracy: 1e-6)
        XCTAssertEqual(
            MonochromeModule.effectiveSigmaS(roiScale: 0.5, iscale: 1.0), 40, accuracy: 1e-6)
        // dt CPU 形 max 钳制在 GridLeg.sigmas 侧；halo 取 ceil(4σ_s)。
        XCTAssertEqual(MonochromeModule.halo(sigmaS: 20), 80)
        XCTAssertEqual(MonochromeModule.halo(sigmaS: 40), 160)
    }

    /// GridLeg.sigmas：CPU 形 max 钳制（monochrome.c:220）vs CL 形无钳制（:260）。
    func testGridLegSigmasCPUvsCL() {
        // FULL（scale=1）：两形一致。
        let cpu = MonochromeGridLeg.sigmas(roiScale: 1.0, iscale: 1.0)
        XCTAssertEqual(cpu.0, 20, accuracy: 1e-6)
        XCTAssertEqual(cpu.1, 250, accuracy: 1e-6)
        XCTAssertEqual(cpu.2, -1, accuracy: 1e-9)
        // 缩小 run（roi.scale=0.5 < iscale=1）：scale = 2 ⇒ σ_s=10，
        // 两形一致（dt CPU :220 max 钳制只在 scale<1 即放大侧生效）。
        let cpuPrev = MonochromeGridLeg.sigmas(roiScale: 0.5, iscale: 1.0)
        XCTAssertEqual(cpuPrev.0, 10, accuracy: 1e-6)
        let clPrev = MonochromeGridLeg.sigmasCL(roiScale: 0.5, iscale: 1.0)
        XCTAssertEqual(clPrev.0, 10, accuracy: 1e-6)
        // 放大 run（roi.scale=2 > iscale=1）：CPU 钳制 scale=1 ⇒ σ_s=20；
        // CL 形 scale=0.5 ⇒ σ_s=40（偏离 pin）。
        let cpuUp = MonochromeGridLeg.sigmas(roiScale: 2.0, iscale: 1.0)
        XCTAssertEqual(cpuUp.0, 20, accuracy: 1e-6)
        let clUp = MonochromeGridLeg.sigmasCL(roiScale: 2.0, iscale: 1.0)
        XCTAssertEqual(clUp.0, 40, accuracy: 1e-6)
    }

    // MARK: - V50 slot

    /// 64.0 槽位：模块静态与 V50Order 表一致。
    func testMonochromeSlotOrderConstraint() {
        XCTAssertEqual(MonochromeModule.iopOrder, 64.0, accuracy: 1e-6)
        XCTAssertEqual(V50Order.order(for: "monochrome"), 64.0)
    }
}
