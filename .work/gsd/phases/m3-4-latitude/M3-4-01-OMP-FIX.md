# M3-4-01-OMP-FIX — omp 二次验收 error-1 修复批

> 修复对象：`M3-4-01-ACCEPTANCE-OMP.md` §三 error-1（IOP `testPlacementGainCompressesMonotonically` 红，阻塞）。
> 执行：ZCode 修复 subagent（夜间全自动授权在案；2026-10-09）。

## 结论头

**PASS / 0 error + 0 minor**（判定 = 测试重钉错误，非实现回归；修复 + IOP 全 bundle 复绿 + IOPP 定向族绿）

## 一、复现（与 omp 报告逐位一致）

`Scripts/test-direct.sh --bundle IOP FilmPlacementTests`（未重建的旧产物）：`11/0/1`，
`FilmPlacementTests.swift:202: XCTAssertEqualWithAccuracy failed: ("3.9737630818290803") is not equal to ("3.75") +/- ("1e-09")`
——实测值与 omp 独立 Python 复算的 placed(20) = 3.9737630818 逐位一致（非 stale binary、非环境漂移）。

## 二、归因判定：测试重钉错误（实现无辜）

**物理语义裁定（以 RFC-023 §9.2 exact 形为准，M3-4-01 DECISIONS §5.1「等强度重钉」为意图正本）**：

- exact 落点语义 = **场景极值 a 落于 t = a ∓ N**——落点方程是 `f(a) = K ± g(a−K; C−K) = t`，钉的是 **E = a 处**的像；`solveKnee`/`placementGain` 实现即此（`t = a − pullBack`，:191；gain 面 placed(E) = K + g(E−K; H)）。
- 单调压缩语义在 exact 锚下**完好**：g_m 对 Δ 单调升且 ≤ Δ ⟹ placed(E) 单调升、placed(E) < E、placed(E→∞) → C（中界，by-design 压缩不越界）。测试的循环断言段（:181-195）全程绿，被换掉的只有尾段。
- T1 重钉把尾段从旧的松弛渐近面（`landedEV < C + 1.0`，对 20-stop 输入恒真）换成 `placed(20) == t @1e-9`——**数学恒假命题**（恒等式成立需 Δ=∞；placed 渐近到 C = 4，永不等于 t = 3.75）。`git diff a2d3c0a..a3a34af` 亲读确认该 hunk 即改动源；DECISIONS §5.1 申报的「等强度重钉」在该测试上未兑现。
- **互证**：同语义的 golden 门（`FilmGoldenTests.swift:1435-1436`，f(a) 面断言 placedTop == a − pullBack）在 IOPParity 轮绿；`FilmPlacementKernelTests`（IOPP，同批重钉）3/0/0 绿——两文件语义一致且绿，唯本测试把采样点写错为 E=20。
- 实现文件 `FilmPlacementModule.swift` **零改动**。

**漏检根因**（与 omp §三一致，不另立）：T1 的定向轮只跑了 IOPParity；改动的 `FilmPlacementTests` 属 IOP bundle（BUNDLE-MAP :525），executor/首验/omp 三方任务范围均未覆盖 IOP——教训挂 OMP-RETRO-QUEUE（改 IOP 级测试文件的 plan，其定向轮必须含 IOP bundle）。

## 三、修复（单测重钉，随修随补）

`Tests/LightamerTests/FilmPlacementTests.swift` `testPlacementGainCompressesMonotonically` 尾段重写：

1. **exact 落点面（omp 指路的 f(a) 面）**：经 `placementGain` 采样 **E = a = 7.0 精确输入**——单通道像素 `(0.184·2^a, 0, 0)`（功率范数 (x³+0+0)/(x²+0+0) = x，Float64 实测 E 偏差 0.0），断言 `landedEV == sceneTopEV − 3.25 @1e-9`（与 golden 门 :1435 同构）。
2. **渐近面（修正数学后保留旧测试语义核心）**：20-stop 远端样本断言 `farEV < C`（渐近中界、永不越界）+ `farEV > landedEV`（极值之后分支仍单调升）。旧 `placed(20)==t` 命题废除。

Python Float64 复算（solveKnee 二分 40 + Newton 4 同构复刻）：placed(E=7) = 3.75（dev 0.0）、placed(20) = 3.9737 ∈ (t, C)——与实测全绿一致。

**附带回填**（omp §五指名，随 error-1 修复批）：`LightamerIOP/Sources/Registry.swift` :52-54 两行 doc comment 缩进回填（`9dc64ba` 误顶格；纯注释，编译中性，重建验证 TEST BUILD SUCCEEDED）。文件尾部 `FilmStatsSnapshot` 顶格 doc comment 为顶层声明正形，非回归、未动。

## 四、验证数字

| 轮 | 命令 | 结果 |
|---|---|---|
| 修复前复现 | `--bundle IOP FilmPlacementTests` | 11/0/1（:202 红，值逐位 = omp） |
| 重建 | `xcodebuild build-for-testing` | TEST BUILD SUCCEEDED |
| 修复后定向 | `--bundle IOP FilmPlacementTests` | **11/0/0** ✅ |
| 修复后全 bundle | `--bundle IOP` | **483/1/0**，peakRSS 7213MB（<8G 门，无 MEMFAIL），154s ✅ |
| 相关族 | `--bundle IOPParity FilmPlacementKernelTests` | **3/0/0** ✅ |
| 终态重建 | `xcodebuild build-for-testing`（含 Registry 回填） | TEST BUILD SUCCEEDED ✅ |
| 终态复跑 | IOP 定向 11/0/0 + IOPP 3/0/0 | ✅（committed-tree 二进制） |

## 五、会话卫生

未 push；未跑全套（任务书豁免）；测试日志 `/tmp/la-direct-tests-IOP.log` 可复核；除上列两文件外工作区零触碰。

OMP-FIX-VERDICT: PASS
