# Plan 05-06 Decisions — nlmeans（v50 29.0，Lab）

> 执行裁决与定值表。依据：dt 树 dc58cf0ba1（nlmeans.c / nlmeans.cl /
> nlmeans_core.c / common.h 逐行核对）；偏离 plan 文本处均注明理由。

## D-05-06-T1-1: threadgroup block size = 128（T1）

- **裁决**：horiz/vert 滑窗的 workgroup 尺寸（两维共用一值）定 **128**；
  threadgroupMemoryLength = (blockSize + 2P) × 4B。
- **依据**：plan 强制的尺寸扫描测试
  `NLMeansParityTests.testWorkgroupSizeScanAllByteIdentical`——{64,128,256,512}
  全组合输出**逐字节一致**（正确性对全值成立，性能不在夜间实测范围——dt 由
  `dt_opencl_local_buffer_opt` 探测、2^16 cell 预算：128 block + 2P ≤ 2^16
  cells 全程富余）。dt 每维独立 opt（h/v blocksize 可不同）；MSL 单值扫描
  已覆盖双维 kernel 正确性，双维独立优化留 PERF 轮。
- **Reversibility**: reversible — 单常量（`NLMeansModule.threadgroupBlockSize`）。

## D-05-06-T1-2: MSL 标量参数结构体化（T1 工程事实）

- **裁决**：五 kernel 的标量参数（width/height/q/P/sharpness/norm2/weight）
  全部并入每 kernel 一个 `constant Struct& [[buffer(N)]]`。
- **原因**：MSL 禁止标量参数挂 `[[buffer(N)]]`（首编译 20 errors 实锤）；
  Swift 侧逐字段镜像布局（FinishParams 显式 float2 pad 对齐 float4）。

## D-05-06-T2-1: seed DISABLED——plan「strength=0 恒等」前提证伪（T2）

- **裁决**：seed 加入 `editingDefaultInstances()` 时 **enabled: false**。
  **修正 plan T2 文本**「strength=0 恒等 → 中性 seed enabled」。
- **证伪论证**（三点）：
  1. dt 自身出厂即停用——nlmeans.c **无 `default_enabled()` 覆盖**（dt iop
     默认 disabled）；
  2. strength=0 ⇒ sharpness = 3000/(1+0) = 3000，w = fast_mexp2f(dist·3000)：
     相似 patch（dist→0）的 w→**1**——平滑照样发生（0.448 Lab L 位移实测，
     GeometryGolden 走查期数据），非恒等；
  3. commit 钳制 `MAX(0.0001, luma/chroma)`（nlmeans.c:415-416）⇒ finish
     混合权重永不为 0 ⇒ 任何有限参数都有非零输出偏移。
  → 恒等只能经 disabled piece 成立（colorbalancergb D1 / monochrome D2 同
  处置）。T3 极限门相应改为「方向门」（flat+strength0 恒等 <1e-4 + 单调 +
  邻域均值方向），逐字节恒等门只在 dist≡0 的平场成立。
- **Reversibility**: reversible — seed 行翻转即可（无格式锁）。

## D-05-06-T2-2: 预览降载三件套常量钉死（T2）

| 件 | 值 | 依据 |
|---|---|---|
| ① K clamp | PREVIEW/THUMBNAIL 管 `K = min(3, ceil(7·scale))` | denoiseprofile.c:1626-1631 同构（dt nlmeans 本体无 clamp——Lightamer 增强，RESEARCH §3.2 载明） |
| ② decimate | 偏移表 skip-parity：counter 起 1、pre-increment、奇→skip（K=3: 28→**14** 偏移） | nlmeans_core.c:103-118 CPU 原形逐位镜像——**非空间半采样**（U2 保持稠密，finish 无需 guard）；dt GPU 腿未实现 decimate，本口径为 plan 指定的 GPU 实现 |
| ③ D-C3 梯子 | **零改动**——04 期已通用化（setLiveParams→PREVIEW 桶渲染、commit 后 idempotent 当前档重渲），nlmeans 仅经 piece.pipeType 消费 | plan「若已通用化则只接参数」分支成立 |

- 趟数表：FULL 满血 120×4+1 = **481**；PREVIEW 降载 14×4+1 = **57**
  （实测 430.9ms vs 57.8ms @2048²，**7.5×**——`.work/plans/05-06/perf.md`）。
- pipeType 到达模块的通道：`IOPiece.pipeType`（dt `piece->pipe->type` 镜像），
  PixelPipe.run 与 iscale 同点一次 stamp，tile 驱动禁改写（测试
  `IOPieceIscaleTests.testThreeTiersStampPipeType` + `testForcedTilingPreservesIscale`）。
- **Reversibility**: reversible — 三件全部是模块内派生函数分支。

## D-05-06-T3-1: tile seam 定值 + Lab 域 +1 pass 记账（T2/T3）

| 量 | 值 | 依据 |
|---|---|---|
| tileHalo | **P + K**（P=ceil(radius·scale)，K=ceil(7·scale)，scale=fmin(roi.scale,2)/fmax(iscale,1)） | nlmeans.c:333-334,339；测试 pin 9 @defaults、18 @scale2 |
| tileWorkingSetBytesPerPixel | **80** | dt tiling factor 2+1+0.25×4 = 4.0（nlmeans.c:336）+ **模块内 Lab 平面 1.0**（dt 从管线免费拿 Lab，我们自付一趟 lab_forward）= 5.0 × 16B（05-01 预演占位值正式化） |
| K/P tile 不变性 | halo 对任意 tile 子窗 ROI 恒同值（run 级常量） | dt 用 piece->iscale 同源；`testTileSeamConstantsAndTileInvariance` 钉住 |

- Lab 域实现口径：模块内 `nlmeans_lab_forward` 一趟进 Lab、finish 内联
  Lab→Rec2020 出（LabMath.h 共享常量）——与 dt 管线级转换逐像素等价
  （03-03 D-T6 内联先例），代价 = +1 pass，已计入 80 B/px 与 perf 数字。

## D-05-06-T5-1: 面板滑块范围 = dt soft-max 交互域（T5）

- **裁决**：radius 0...4（dt soft_max 4，nlmeans.c:435）、strength 0...100
  （dt soft_max 100，:439）、luma/chroma 0...1。
- 硬最大（10 / 100000）经 params API 仍可达（golden case nlmeans_patch4
  radius=4、测试 strength=1e5 直接驱动 Params）；GUI 表面积与 dt 一致。
- **Reversibility**: reversible。

## D-05-06-T5-2: GUI-13——启用 commit + 立即拖动 tick 并发崩溃（T5 走查发现）

- **现象**：AX 点行圈启用后 ~2s 内 AX set 滑块 → SIGABRT，`Data._Representation`
  over-release @ `ModuleBox.setParams`（崩溃报告
  `.work/plans/05-06/adoption/Lightamer-2026-09-22-231800.ips`）。
- **归因**：D-H1 live 路径的 box 并发突变——ModuleBox `@unchecked Sendable`
  注释假定「coordinator 单一 owner」，enable-commit 与 live-tick 两路 Task
  未串行化时前提被破坏。**栈无 nlmeans 帧**：同 plumbing 服务所有模块，
  非 nlmeans 特有（settle 后同操作不复现）。
- **处置**：FINDINGS GUI-13（优先级高，05-08 SC#4 拖动门签核前必修——
  coordinator 侧串行化或 box 突变加锁）；非本 plan 范围（不动 02-05 产权）。

## 偏离账（对 plan 文本）

| plan 原文 | 实际 | 决策号 |
|---|---|---|
| seed「strength=0 恒等 → enabled」 | DISABLED（恒等不存在） | D-05-06-T2-1 |
| T3「strength=0 恒等逐字节」 | 平场恒等 <1e-4 + 噪场方向门（单调/邻域均值） | D-05-06-T2-1 |
| factor_cl 5.0×16=80 的出处（RESEARCH 记 dt 5.0） | 本 dt 树 tiling factor=4.0；80 = 4.0 + 模块 Lab 平面 1.0（结构成立，非照抄） | D-05-06-T3-1 |
| decimate「dist/accu 按 2 步进」 | offset-list skip-parity（CPU 原形镜像；空间步进会留稀疏 U2 除零面） | D-05-06-T2-2 |
