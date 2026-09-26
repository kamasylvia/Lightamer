# Plan 05-07 Summary — denoiseprofile（IOP-DENOISE-01，v50 9.0，RGB post-demosaic）

**执行**：T1、T2-T4 由前一班 subagent 完成（provider 停滞被回收前已提交）；
T5 中途在制品 + T6 全部由 2026-09-23 续跑 executor 完成。**状态：完成**
（全套 **581 tests / 3 skip / 0 fail**，收工前 touch + build-for-testing 重编
复跑；基线 553 → +28。GUI 走查 PASS，GUI-12 复发确认沿用既有号）。

## 任务完成表

| 任务 | commit | 验证数字 |
|---|---|---|
| T1 float64 参考先行 | `2ccbae6` | 波列链（VST 三变体 + eaw 逐 band + Bayesshrink + 软阈值 + backtransform）+ NLMeans 腿包夹 + force 曲线量化全链 Python float64；参考自测（平场恒等 + 单 band 手算卷积） |
| T2-T4 kernel + 模块 + 剖面接线 + 波列 tiling | `7e2cd39` | VST 三变体/backtransform/eaw/reduce/vert 变体/finish（MSL float3 对齐 pad 已修）；band 双缓冲（L018）+ 每 band fence（L014）；v12 镜像 + AUTO infer 手算对照 + NoiseProfileStore 消费 + halo=2^max_scale；DerivationTests 18 全绿 |
| T5 SC#2 golden 闭环 + parity | `0e90f23` | **8 case × 3 fixture parity maxRel ≤ 9e-6**（门 1e-3，compared>0 + 跨 fixture 非空转）；SC#2 clean-truth 基线：noisy 0.00175 → 正确剖面 **0.00071** < generic 0.00075 < ISO125 错配 **0.00111**（①②方向全过）；tiling==整幅 maxRel=0.0 + FULL Δfootprint 分块封顶；kernel 修三处（reduce_second count 语义 / compensateStrength 分腿 / 截断语义） |
| T5 dt 三证据 + manifest | `2c8ee20` + `a0ca553` | **采纳 8/8**：`params v. 12: version ok params ok` + DB hex **byte-identical**（416B）+ 平场探针 ≤4.5e-7（strong 档 2.4e-4，bias 进 delta）；环境受阻预期经 05-06 conf（opencl=false）**解除**（D-05-07-T5-4）；manifest denoiseprofile 节 + **SC#2 = PASS** 结论行落账 |
| T6 面板 + wiring + 轨 B + PERF | `ab198ab` | 面板（mode/VARIANCE 禁用注记/profile 三态/7 滑块/Y0U0V0\|RGB/force 曲线双 tab）+ 31 catalog 键 + a11y + 280pt；PanelWiring +1（拖动=1 commit + mode/profile 离散单 commit + 归零还原 pristine hash）；轨 B disabled 插链（GeometryGolden 5/5）；PERF7 波列引擎 31 趟 41.7ms + FULL 35 tiles → perf.md |
| GUI 走查 + zh 显示名 | `d5576fe` | 去噪（剖面）行注册（v50 序正确）+ zh 标签随轮落位 + 面板 AX 全达（7 滑块全 dt $DEFAULT）+ 启用拉普拉斯 −5.6% + 强度 live tick −24.8% + PERF7/GUI-13 settle 协议 → FINDINGS 登记（GUI-12 复发沿用） |

## 验收标准对照

- [x] float64 参考先行落库（gen_fixtures `refs-denoiseprofile` 可复跑）；kernel
      逐 band parity + 终图双门——8×3 ≤ 9e-6
- [x] VST 往返 <1e-6 + 方差稳定化统计检验（DerivationTests testVSTRoundTrip
      NoiseFree / testVSTStabilizesPoissonVariance）；三兼容 bool params 位保留 +
      legacy 不移植头注
- [x] L018 双缓冲合规（grep 无 read_write RMW 于 band 累加路径；accu 走
      device float4 buffer 程序序 RMW）；band 数 = max_scale 推导断言
      （512×384→6 / 2048×1536→7 / 64×64→3 同公式）
- [x] NLMeans 腿：P=0 退化点检 + norm/scattering 手算对照；dist/horiz/accu
      零复制复用 05-06 kernel 群（norm2=(1,1,1)）
- [x] 剖面接线：Auto/手动 ISO/generic 链 + highlight-pres 补偿公式（metadata
      源 v1 缺 → shift 0 头注）+ AUTO infer 手算对照
- [x] SC#2 闭环：正确剖面 SNR > generic + 错配欠去噪方向断言 + compared>0
      ——manifest SC#2 = PASS 行落账（05-08 引用）
- [x] 波列 tiling：分块==整幅 <1e-3（实测 0.0）+ halo=2^max_scale + FULL
      Δfootprint 分块封顶（35 tiles / 0.059GB ≪ 3GB）
- [x] dt 三证据（416B blob 三件套 8/8）+ manifest 节 + 平场探针（容差档）
- [x] 面板（mode/profile/force 曲线）+ PanelWiring +1 + catalog + a11y +
      GUI 走查登记
- [x] 轨 B 双判据不回归（GeometryGolden 5/5）；PERF 落 `.work/plans/05-07/
      perf.md`；全 suite 绿 **581/3skip/0fail**

## 新增/改动文件（续跑班增量）

- `LightamerIOP/Sources/DenoiseProfile/`：Kernels.metal（reduce_second 修复）、
  Module.swift（compensateStrength 分腿 + 截断 + forceRow/forceCurveSamples
  public）、WaveletEngine.swift（reduce2 + TEMP DEBUG 清除）
- `Tests/LightamerTests/DenoiseProfileParityTests.swift`（新建 8 测试）、
  `DenoiseProfileDerivationTests.swift`（签名跟随）、`PanelWiringTests.swift`
  （+1）、`GeometryGoldenTests.swift`（轨 B 插链）、`PreviewChainPerfTests.swift`
  （+testWaveletsEnginePassBudget）
- `App/Sources/Lightamer/UI/Inspector/DenoiseProfilePanelView.swift`（新）、
  `InspectorView.swift`（zh 标签）、`InspectorState.swift`（provider）
- `input/golden/fixtures/gen_fixtures.py`（wb_scaled + NLM wb fold + 截断同步修）、
  `input/golden/manifest.md`（denoiseprofile 节 + SC#2 行）
- `.work/plans/05-07/`（adoption 8 case 证据 + run_adoption.py + perf.md）

## 遗留 / 风险

1. **GUI-12（中，沿用既有号，05-08 前修）**：30 行模块列表把 denoiseprofile
   面板体完全挤出可视区（AX 径可达、视觉不可见）——moduleList 滚动约束
   同修（与 nlmeans 面板同因）。
2. **GUI-13（高，05-08 前必修，05-06 立案）**：启用 commit + 立即拖动并发
   竞态——本轮 settle 8s 协议规避，未复现；coordinator 侧串行化待修。
3. wb 策略分歧（D-05-07-T2-1）：v1 wb ≡ (1,1,1)，真实 CIRAW WB 增益接入
   留管线级 stamp（参数化已就绪）。
4. highlight-preservation ISO shift 的 metadata 源（`exif_highlight_preservation`）
   CaptureMetadata 尚无字段——公式已移植并单测，shift 恒 0；Phase 6+ 元数据
   扩展时接线。
