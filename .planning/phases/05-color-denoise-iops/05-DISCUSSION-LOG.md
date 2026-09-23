# Phase 5: Color & Denoise iops - Discussion Log

> **Audit trail only.**

**Date:** 2026-09-21（planner 轮裁决）— 2026-09-23（05-08 签核核对）
**Phase:** 5-Color & Denoise iops
**Mode:** 8 项 Open Questions 全部在 plan 期裁决（D-05-CONTEXT-1..8，全采纳 RESEARCH 推荐——既定授权模式）；执行期决策落各 plan DECISIONS。

---

## 过程摘要

- planner 轮（2026-09-21）：12 需求 → 11 dt 模块映射 + 关键勘误（denoiseprofile = post-demosaic RGB 域非 raw）+ 8 OQ 裁决定稿。
- 执行（2026-09-21..23）：05-01 基建 → 05-02/03/04（wave 2）→ 05-05 → 05-06 → 05-07 → W6 GUI 修复轮 → **05-08（本 plan，签核轮）**。
- 签核核对（2026-09-23，夜间 subagent executor）：SC#1-4 逐条证据指针见下节。

## 05-08 SC#1-4 签核核对（2026-09-23，ROADMAP §Phase 5 逐条，证据指针）

- **SC#1**（colorbalancergb / color calibration / channel mixer / color zones / monochrome(含色彩滤镜) / velvia / vibrance / color contrast 全部 match Darktable references）✅：
  `ColorBalanceRGBParityTests`（05-02 轨 A + dt 三证据 + XMP blob 采纳）+
  `ChannelMixerRGBParityTests`/`ChannelMixerColorContrastParityTests`（05-03：dt-cli 采纳 12/12 + blob 52B→88B 修复轮 F1）+
  `ColorZonesParityTests`（05-04 hue sweep 全环 + LUT 双闸）+
  `MonochromeParityTests`（05-05：filter+envelope 全链 + grid 腿交叉）+
  `VelviaParityTests`/`VibranceParityTests`（05-04 采纳复验 + 饱和 fixture）+
  manifest 逐模块节（channelmixerrgb/channelmixer/colorcontrast/vibrance/velvia/colorzones/monochrome 各节 + Phase 5 总账 11/11）。
  SC#1 口径注记：「color contrast/correction curves」交付本体 = colorcontrast（56.0）；rgbcurve/rgblevels 划出（D-05-CONTEXT-1，REQUIREMENTS IOP-COLOR-09 行注记）。
- **SC#2**（profiled raw denoise match + per-camera profile from EXIF/metadata——spike 正式验证）✅：
  `DenoiseProfileParityTests`（05-07：8 case × 3 fixture，VST 三变体 + eaw 波列 + Bayesshrink + NLMeans 腿）+
  SC#2 闭环 = 加噪→去噪 golden（05-01 种子化 Poisson-Gaussian 加噪集）+ **剖面错配方向断言**（低 ISO 剖面去高 ISO 噪声 → 欠去噪方向断言）+
  剖面加载 = `NoiseProfileStore`（EXIF maker/model/ISO 匹配 + 线性插值 + generic 回落，`NoiseProfileStoreTests` 手算向量）+
  Phase 1 spike 量化收口行（manifest「SC#2 结论行」）。
- **SC#3**（NLMeans / bilateral / hot-pixel+dark-frame+chromatic reduction 全部去噪不损细节——torture images）✅（含口径注记）：
  `NLMeansParityTests`（torture 加噪集 parity ≤5.7e-6 + 细节保持：strength 单调 + luma/chroma 半边方向门）+
  `BilateralParityTests`（本 plan：torture 加噪 fixture parity 9/9 <1e-6 + delta 脉冲响应剖面 + 平场恒等 + σ→0 恒等）+
  chromatic noise 半边 = 05-06 chroma 参数 + 05-07 Y0U0V0 模式（`testChromaZeroLumaOnlySmoothing` / denoiseprofile 色度腿）；
  **IOP-DENOISE-04 需求注记行**（VALIDATION「Per-Requirement Annotations」）：hot pixels/dark-frame = 正式 defer（D-05-08-T4-1，Bayer 域 + CIRAW 无 despeckle 键双重证据，需求解释权裁决非缺口）；cacorrect 复议维持 defer、与 Phase 6 无关。
- **SC#4**（全 color/denoise 模块 PREVIEW 60fps 拖动；100MP denoise 工作集超预算时 tiling fallback 承重）✅-with-判定：
  **拖动门两链实测**（`PreviewChainPerfTests.testPhase5DragGateTwoChains`，Debug，帧型=稳定 imageID + params tick 全链重渲）：
  ① color 七件全启用链拖 vibrance = **4.8ms 中位**（4.3-6.7，预算 16.6ms 余量 3.5×，**60fps 达标**）；
  ② denoise 单件启用链（nlmeans @ defaults，降载 57 趟档）拖 strength = **85.7ms 中位**——**未达标**。
  降载杠杆已兑现（05-06 引擎级 57 趟 57.8ms vs 满血 481 趟 430.9ms，7.5×；PSO 预热 + 稳定 input 04-07 兑现）→ 按 D-05-CONTEXT-6 触发条件，**Open#9 应急判定 = 成立**；判定依据同时表明 nlmeans 链成本在 NLMeans 本征趟数（Lab 往返共享每模块仅省 2 趟，对缺口贡献 ~5%），应急 plan 启动不改变 60fps 结论——判定依据落 `.work/05/perf.md` + DECISIONS D-05-08-T6-1 后**本 plan 收口**（应急工作不在本 plan 内，移交 Phase 6+/独立 perf plan）。
  **tiling fallback 承重** ✅：nlmeans/denoiseprofile/bilateral/monochrome 四消费者「强制分块==整幅」四套件全绿（<1e-3；bilateral 实测 4.5e-7 且 grid 计数>1）+ MemoryBudgetTests FULL Δfootprint 有界（toneequal 352MB / denoiseprofile 35 tiles / bilateral 摊销 OQ7 门）。

## 05-08 过程决策补充（详版见 05-08-DECISIONS.md）

- OQ7 定稿（D-05-08-T2-1）：grid_bytes = Π cells × 16B、预算 1.5GB、100MP 默认档放粗 ×9.23 → 1.47GB、回落 = TilingPlan 分块（dt maxbuf 对应物）、UI 软上限拒绝。
- grid 档双参考结构（D-05-08-T2-2）：同算法 float64 参考 <1e-3 正门（实测 ~8e-7）+ vs 精确公式包络测量（cell=σ 粒度固有，dt lattice 同族）；range 维不做 grid blur（稠密格 adaptation）。
- 移植缺陷两处归档（D-05-08-T2-3）：线解码步长/位权混用 + 标量滚动 tmp 跨通道复用——均移植期引入，修复后全门绿。
- IOP-DENOISE-04 defer 决议（D-05-08-T4-1）：chromatic 已交付；hotpixels/dark-frame 正式 defer；cacorrect 维持 defer（与 Phase 6 无关）。
- GUI 验收轮汇总（T6.4）：W1-W7 全轮闭环（GUI-1..13 全闭，FINDINGS.md 2026-09-23）；本 plan bilateral 面板自动化覆盖 = PanelWiring 54/54（dispatch + 拖动=1 commit + 复位还原）+ zh/en catalog + Inspector zh 显示名同轮；bilateral 真机视觉走查（RAW 载入/展开/AX 拖动/screencapture 量化）= Manual-Only 挂账（L011 口径，AX 路径本轮探查未贯通，待专门 GUI 轮），denoise tile 缝双保险 = 自动门（分块==整幅 4.5e-7）+ 05-06/05-07 目检已录。
