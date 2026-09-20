# 04-05 DECISIONS — detail 四模块执行决策记录

> Plan 未覆盖点的裁决记录（任务书指令：写入本文件并继续，不停下等确认）。
> T0 三条按 plan 决策记录走（见 DISCUSSION-LOG 04-05-T0 节）；以下为实现期细化与分歧。

## 04-05-T0 任务书与 plan 文件的模块清单分歧（先行裁决）

- **D-04-05-T0-0 模块清单以 plan 文件为准**：任务书正文 parenthetical 写
  "sharpen + localcontrast + cacorrect + cacorrectrgb"，但 04-05-PLAN.md 的
  Goal/Tasks/Artifacts 全篇是 sharpen + local contrast + highpass/soften +
  equalizer（5 ops，IOP-DETAIL-01..04）。任务书同时指令"逐字执行" plan 文件。
  裁决 = 按 plan 文件交付 5 ops。`cacorrect`（v50 5.0）是 **Bayer raw 域**
  模块（`IOP_CS_RAW`，`piece->filters` mosaic 语义，1300 行 RawTherapee 移植）——
  Lightamer 管线输入是 CIRAW 已显影域，无 Bayer 访问，不可移植（与 rotatepixels
  同类"参照物勘误"）；`cacorrectrgb`（13.5，manifold guided）在 plan 内无 task，
  其横向 CA 语义已被 04-04 lens TCA 滑块覆盖。两者 defer（Phase 5 denoise 视
  Bayer 访问方案再议，不在本 plan）。

## 04-05-T0 三口径（plan 推荐采纳）

- **D-04-05-T0-1 luma 域 = Lab L（采纳 plan 推荐）**：sharpen / local contrast /
  highpass / equalizer 走 Lab（LabMath.h 融合，shadhi/colisa 前例）；soften 例外
  走 RGB 线性域（dt `default_colorspace RGB` 字面）。"与管线 scene-referred 纯度
  分歧"记为 intentional divergence，进各模块头（T1 acceptance）。
- **D-04-05-T0-2 local contrast golden 验收口径（采纳）**：合成 float64 公式参考
  + detail=0 精确恒等门 + 内容方向断言（合成台阶图）。dt-cli 参考不可用是 D-G3
  的必然代价（guided ≠ bilateral/local-laplacian），非缺陷。
- **D-04-05-T0-3 equalizer v1 纯高斯带（采纳）**：不接 edge-aware 权重（dt eaw
  `gweight`）；偏差写模块头注记；EIGF 权重接入作 stretch（未做）。

## 实现裁决（plan 未覆盖/与源码核对后的勘误）

- **D1 sharpen blur 基座 = Deriche IIR（plan 字面），与 dt FIR 分歧**：dt sharpen
  的 blur 是截断 FIR（`init_gaussian_kernel` rad taps，`sharpen.c:111-123`），而
  plan Goal 指定复用 GaussianBlur（Deriche IIR 双平面）。合成参考镜像 IIR 侧
  （`dt_gauss_coeffs` + column-row recursion），parity 证"实现正确"而非"与 dt
  逐值一致"。σ 换算取 dt 有效值：commit `d->radius = 2.5·p->radius` 再除回，
  得 **σ = p->radius × scale**（`sharpen.c:160-161,376` 代入），rad = min(12,
  ceil(2.5·radius·scale))（MAXR 12，`:138`）。
- **D2 sharpen 默认值分歧（plan 字面勘误）**：plan 写"dt 默认 0 中性"；dt 源码
  `$DEFAULT` 实为 2.0/0.5/0.5（`sharpen.c:45-47`，且无 `default_enabled=FALSE`）。
  缓存中性要求压倒 dt 默认：`Params()` 默认 `amount=0`（blit 恒等快路径），头注记。
- **D3 highpass 参数面（plan 字面勘误）**：plan T3 写"contrast/center/radius 三参"；
  dt `dt_iop_highpass_params_t` 只有 **sharpness + contrast**（`highpass.c:41-45`），
  无 center/radius。按源码两参实现。plan 验收"全零参恒等"不成立（contrast=0 →
  全 50 灰，`_blend` 公式）：修正验收 = disabled 实例恒等（创意模块，seed disabled）
  + 公式 parity。mix 公式取 CL 腿（`highpass.cl:157`，
  `o.x = 50+((0.5a+0.5b)−50)·contrast_scale`，a/b 归零），contrast_scale =
  (contrast/100)·7.5（`:155`；CPU 腿 `:289` 的 ×0.5 是 packed-L 双遍记账差，
  CL 腿为准——双遍 `_blend` 全覆盖等价单遍 CL mix）。
- **D4 highpass/soften blur 基座分歧**：dt 两模块的 blur 都是 `dt_box_mean`
  （8 iterations），plan 指定复用 GaussianBlur IIR。σ 取 dt CL 相关式
  σ = √((radius·(radius+1)·8+2)/3)（`highpass.c:140`，BOX_ITERATIONS=8），合成
  参考镜像 IIR 侧。soften 半径链：mrad = hypot(dscIn)·0.01（dt
  `piece->iwidth·iscale` 的管内对应——toneequal blending 用 dscIn 同前例；
  crop 在 soften 上游故 dscIn = 窗口几何，full/window 语义差注记）、
  rad = mrad·min(100,size+1)/100、radius = min(mrad, ceil(rad·scale))。
- **D5 soften mix 与线性混合方向**：`dt_iop_image_linear_blend(out, amt, in)` =
  `buf = amt·buf + (1−amt)·other`（`imagebuf.c:452`），调用位 `buf=blurred`、
  `other=in` → **out = amt·blurred + (1−amt)·in**，与 `soften_mix`
  （`original·(1−a) + clip(processed)·a`）一致。平场恒等探针钉参：
  saturation=100 + brightness=0（factor 1）→ overexposed+blur 保平场 → 任意 amount
  恒等。dt-cli probe 免跑：平场恒等对任何 DC=1 blur 实现恒成立（vacuous），
  变化图必触 L017——结论先验，合成单轨，落账此处。
- **D6 local contrast 半径/域半径映射（dt 无直接对应）**：dt bilateral 的 sigma_s
  是 grid 空间单位，无像素对应。v1 自定：`sigmaS` = 全分辨率像素半径（sharpen
  式，×scale 生效值），默认 20（clarity 式大半径）；`sigmaR` → EIGF feathering
  eps = sigmaR²·4（默认 sigmaR=0.5 → eps=1，toneequal 默认 feathering 倒数同值）。
  EIGF 腿 = no-mask 单迭代（toneequal kernel 名复用 + 自有 scratch；quantization
  恒 0——mask 路径 Phase 6）。`midtone` 不移植（D-G3 无 laplacian 腿）。
- **D7 双常数语义（D-G5 文档项）**：ROI 外扩 halo = blur 可见支撑
  （sharpen/highpass/soften：ceil(3σ)；localcontrast：ceil(3r)+8，ds 重采样边距；
  equalizer：固定 64 = 3·16 + ds 链边距）——面向"不取全图"；`tileHalo` =
  toneequal 式 4r+65 系（IIR 跑道 14.5σ，<1e-6 分块==整幅门）——面向 tiling。
  同一模块两数并存，注释各钉一处。
- **D8 equalizer 通道与恒等**：金字塔只跑 L（a/b 直通；sharpen 前例。dt 3 通道各
  挂曲线为 stretch）。6 增益 = 5 残差带 + coarse（σ₀=1 递倍 1/2/4/8/16）。
  全零增益 → blit 恒等快路径（exact）；金字塔重组本身只保 <1e-5（float 舍入，
  非逐字节——plan"逐字节"字面修正为快路径 exact + 重组 <1e-5）。
- **D9 neutral 快路径统一**：sharpen（amount=0 或 radius≤0）、localcontrast
  （detail=0）、equalizer（全零增益）、soften（amount=0）→ blit 恒等，不碰
  scratch（缓存零扰动 + PERF）。highpass 无恒等参（D3）→ 恒等只经 disabled。
- **D10 XMP 钉参组范围**：sharpen/highpass/soften/bilat 生成 XMP（dt blob 版式
  校验 + 字段映射落 manifest；dt-side 无 adoption 实证——Lab 链 broken-route
  前科 + L017，XMP 仅作参数文档）。equalizer 不生成 XMP（v1 单组增益与 dt
  3×6 曲线无干净镜像，强行 blob 无意义；落账此处）。
- **D11 seeds**：sharpen（amount=0 enabled）、bilat（detail=0 enabled）、
  equalizer（全零 enabled，快路径恒等）进 `editingDefaultInstances`（面板有实例
  可驱 + 缓存零扰动，ashift D6 同款）；highpass/soften 进 seed 但 **disabled**
  （创意模块，plan T3 字面）。
