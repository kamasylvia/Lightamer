---
phase: 8
plan: "08-4"
title: "EDR 显示输出（W2，独立显示腿）：viewport 级 HDR opt-in toggle——16F blit PSO 变体（EditorMTKView 预留位兑现）+ wantsExtendedDynamicRangeContent + extendedLinearSRGB + 终端段 SDR 钳制旁路（SoftProofStage 同位语义）+ headroom 查询/跨屏失效/无余量徽标 + SDR 逐字节不变断言 + EDR on 不进 export/history/sidecar 三断言（XDR/外接目检 Manual-Only 登记）"
wave: 2
depends_on: []
autonomous: true
requirements: [IOP-HDR-05]
files_modified:
  - App/Sources/Lightamer/UI/EditorMTKView.swift                # 预留位兑现（:20-21 注释位）：blit PSO `.bgra8Unorm`（:294-306）加 `.rgba16Float` 变体（两 PSO 共存 toggle 择一）+ on 时 `wantsExtendedDynamicRangeContent=true` + `colorspace = extendedLinearSRGB` + display colorspace 跟随逻辑（:334-341）EDR on 分支跳过附加
  - App/Sources/Lightamer/UI/EDRControlView.swift               # 新建：HDR 预览 toggle + headroom 徽标（SoftProofControlView.swift 同位先例形状；headroom=1.0「当前显示器无 EDR 余量」徽标）
  - App/Sources/Lightamer/State/EDRHeadroomMonitor.swift        # 新建：`NSScreen.maximumExtendedDynamicRangeColorComponentValue` 查询 + `NSWindow.didChangeScreenNotification`/`NSApplication.didChangeScreenParametersNotification` 订阅 → 视图失效重查
  - LightamerCore/Sources/Pipe/PixelPipe.swift                  # 终端段短路开关：EDR on 时 gamma/colorout 后 SDR 钳制旁路（13-2 SoftProofStage 显示腿 runtime override 同位语义；off 分支零代码路径差）
  - Tests/LightamerTests/EDRViewportTests.swift                 # 新建：P4 API 复验（rgba16Float+EDR flag+extendedLinearSRGB 全通）/SDR off blit 快照逐字节/EDR on 三不进断言/PSO 变体存在性
  - .work/gsd/phases/08-hdr-stacking-effects/08-4-SUMMARY.md
  - .work/gsd/phases/08-hdr-stacking-effects/08-4-DECISIONS.md
  - TODO.md                                                     # 08-4 勾选
  - LESSONS.md                                                  # 如踩坑
---

# Plan 08-4 — EDR 显示输出（W2，独立显示腿）

> 背景：IOP-HDR-05 = **显示腿 opt-in 开关，永不进 export 链与 history**（D-08-CONTEXT-12；soft proof
> 显示腿 runtime override 同位语义，13-2 SoftProofStage 先例）。viewport 现状 `.bgra8Unorm`，
> `EditorMTKView.swift:20-21` 注释明确「`.rgba16Float` reserved for the Phase 8 EDR viewport」——本
> plan 兑现预留位。HDR 管线本体零新架构（float32 全链是 Phase 2 现状，IOP-HDR-04 由 08-1/08-5 承
> 担）；本 plan 只做显示端四件事：16F PSO + EDR flag/色空间、终端段旁路、headroom 联动、SDR 逐字
> 节不变断言。**HDR 导出深度（HEIC gain map / AVIF PQ/HLG）defer Phase 11**（ROADMAP Notes 明文授
> 权）——本 plan 禁碰 export 面。
> 内部任务序刚性：T1 PSO/toggle → T2 终端旁路 → T3 headroom → T4 断言套件 → T5 收口（T4 依赖
> T1-T3 全部落位）。

## read_first

1. `.work/gsd/phases/08-hdr-stacking-effects/08-RESEARCH.md`——§7（RQ-08-7 终形全文：管线形状/
   headroom 联动/非 XDR 屏行为/SDR 不变断言四条——本 plan 规格正本）、§0 P4 行（EDR spike 全通：
   rgba16Float + wantsExtendedDynamicRangeContent + extendedLinearSRGB；本机 SDR headroom 1.0/1.0；
   toggle 合法 + >1.0 值合成器钳 SDR 白）、§16 R1（COLOR-4 → Manual-Only 登记）
2. `.work/gsd/phases/08-hdr-stacking-effects/08-CONTEXT.md`——D-08-CONTEXT-12（裁决四条全项）+
   继承定案节（13-2 交付面：LinearVariantCache/extendedLinearSRGB workalike 底座）+ 验证与红线节
   （SDR 不变断言三件套字面）
3. `App/Sources/Lightamer/UI/EditorMTKView.swift`——:20-21（预留位注释原文）/ :27（Coordinator
   per-frame state 所有权）/ :292-306（blit PSO 构建位——`.bgra8Unorm` 加 16F 变体处）/ :334-341
   （display colorspace 跟随逻辑——EDR on 跳过附加位）
4. `LightamerCore/Sources/Pipe/Terminal/SoftProofStage.swift`——13-2 显示腿 runtime override 先例
   （toggle 形态 + 三不进断言形状正本：不进 export/history/sidecar）
5. `LightamerCore/Sources/Pipe/Terminal/ColorOutModule.swift:294`——extendedLinearSRGB 既有消费点
   （13-2 色彩批交付面）+ `LightamerCore/Sources/Foundation/DisplayProfile.swift:161,188`（extended
   LinearSRGB workalike 单例）
6. `App/Sources/Lightamer/UI/SoftProofControlView.swift`——显示腿控制条 UI 先例（EDRControlView
   同位形状）
7. `LESSONS.md` L020（内容级断言）/ L031（多队列纪律——blit 提交照常走 Coordinator 既有路由，本
   plan 无新提交源；若实现中发现需要即停手报告）+ `AGENTS.md`（Phase 执行模型 + 暂停机制）

## 纪律（强制）

- **每任务独立提交**（Conventional Commits，只 add 本任务申报文件）；`caffeinate -dis` 包裹一切构建。
- **单测命令** = `Scripts/test-direct.sh '<Class>'`；**判据 = Executed 计数行 + failures 行**，
  Executed 0 = 判据失败。
- **每任务边界检查 `.work/config.toml [gsd]` 开关（`auto`/`paused`）**——commit 后、下一任务前。
- **不 push**；**构建勿加 `-derivedDataPath`**；**每新建源/测试文件后跑 `tuist generate`**（11-03
  教训）。
- **回归基线 = 1553/9skip/0fail**（13-3 后基线）；每任务全套 suite 绿；本 plan 收尾轮 = 1553 + 新增，
  0 fail。**在案 flake 归因条款**：`LayerE2ERoundTripTests` / `ToneEqualPerf` 负载型 flake 若现，隔离
  ×3 归因单列入 SUMMARY，不计违约。
- **SDR 不变 = 硬闸（执行期不得放宽）**：① EDR toggle **off** = 零代码路径差（16F PSO/旁路仅在
  on 分支可达）——既有渲染 golden 矩阵全绿为每任务前置 + 新增 blit 快照 hash 相等断言；② EDR
  **on** 永不进 export（导出 golden 逐位不变）/ 不进 history（无新项）/ 不写 sidecar（字节不变）
  三断言（soft proof 四断言形状）。
- **EDR 是 viewport 级 runtime override，非文档参数**：不进任何 Codable/history/hash 面；与 soft
  proof 同位（两者叠加行为 = on 分支互斥裁决执行期决策）。
- **XDR 目检 + 外接 HDR 双实测 = Manual-Only**（P4 环境无 XDR 屏已证 headroom=1.0 行为）——本 plan
  交付 API 面 + 单测 + 徽标；目检项登记 Manual-Only 汇总（08-5 T5 签核表汇总），**不得**因无 XDR
  屏阻断交付（R1 消解路径）。
- **COLOR-4 纪律**：headroom>1.0 「not as a different color space」（SC#3 字面）——extendedLinearSRGB
  直接用（显示器原生 EDR 色彩空间查询无稳定公开 API，WWDC 惯例路径，research §7.1 择优定案），
  禁自创色彩空间换算。
- RESEARCH/CONTEXT 未覆盖细节（toggle 与 soft proof 并存语义、徽标文案、16F drawable 的
  clearColor 适配）标注**执行期决策**入 `08-4-DECISIONS.md`，不臆造。

## Tasks

### T1 16F blit PSO 变体 + toggle 状态面 + EDRControlView

- **action**
  1. `EditorMTKView`：blit PSO 构建位（:294-306）加 `.rgba16Float` 变体（与 `.bgra8Unorm` 两 PSO
     共存，toggle 择一——禁替换现 PSO）；EDR on 时 `CAMetalLayer.wantsExtendedDynamicRangeContent
     = true` + `colorspace = CGColorSpace(name: .extendedLinearSRGB)`（P4 全通 API）。
  2. **display colorspace 跟随逻辑分叉**（:334-341）：EDR on 时跳过 display colorspace 附加
     （compositor 不再匹配，值即显示意图——research §7.1）；off 分支行为逐字节不变。
  3. toggle 状态面 = viewport 级 runtime override（非文档参数；挂 Coordinator 既有 runtime override
     位，SoftProofStage 同位）；`EDRControlView` 新建（SoftProofControlView 先例形状）：toggle +
     headroom 徽标位。
  4. **P4 API 复验测试**：测试宿主内构造 CAMetalLayer 接受 `.rgba16Float` + EDR flag +
     extendedLinearSRGB 三件全通断言（macOS 27.0 行为钉）。
- **证据**：`EDRViewportTests`——PSO 双变体存在性 + toggle off 择 bgra8 / on 择 rgba16F；layer
  flag/色空间 on/off 状态断言；P4 复验三件全通。

### T2 终端段旁路（SDR 钳制短路）

- **action**
  1. `PixelPipe` 终端段短路开关：EDR on 时 gamma/colorout 后**不进 SDR 钳制**（>1.0 值直通
     drawable；13-2 SoftProofStage 显示腿 override 同位语义）——off 分支零代码路径差（开关默认
     off = 今日行为）。
  2. EDR on 时 display tint/D-COL2 附加跳过（与 T1 色空间分叉同支）。
  3. toggle off 快照对比前置：本任务 commit 前，既有渲染 golden 矩阵全绿（硬闸①）。
- **证据**：`EDRViewportTests` 扩段——off 短路不触发（blit 输出与既有输出 hash 相等）；on 短路
  触发（合成 >1.0 值 patch 直通断言，CPU 探针面）；golden 矩阵回归全绿记录。

### T3 headroom 查询 + 跨屏失效 + 无余量徽标

- **action**
  1. 新建 `App/Sources/Lightamer/State/EDRHeadroomMonitor.swift`：
     `NSScreen.maximumExtendedDynamicRangeColorComponentValue` 查询（window 所在屏优先）+
     `NSWindow.didChangeScreenNotification` / `NSApplication.didChangeScreenParametersNotification`
     订阅 → 视图失效重查（跨屏拖动重查——research §7.2）。
  2. **headroom=1.0 行为**（P4 实测）：toggle 保持合法（无自动回落）；>1.0 值被合成器钳到 SDR 白
     ——UI 显示「当前显示器无 EDR 余量」徽标；headroom 值随 EDRControlView 展示。
  3. 跨屏拖动用例（单测可测面：模拟 screen 变更通知 → monitor 失效回调断言）。
- **证据**：`EDRViewportTests` 扩段——headroom 查询值合法域断言 + 通知驱动失效回调 + 1.0 徽标
  状态位；EDRControlView 状态机走查。

### T4 SDR 不变断言三件套 + EDR on 三不进

- **action**
  1. **SDR off 逐字节**：blit 快照对比测试——toggle off 渲染 texture hash == 既有输出 hash（既有
     golden + 新增快照双保险；L014 读回 fence 惯例）。
  2. **EDR on 三不进**（soft proof 四断言形状）：导出 golden 逐位不变（on 状态导出 == off 导出）；
     history 无新项；sidecar 字节不变。三断言独立用例，禁合并断言（L020 内容级）。
  3. **像素格式交接断言**：16F drawable 上 blit 输入纹理（管线输出 float32 平面）采样路径零改
     （直渲腿只换附件格式，管线输出面不感知——零管线改动断言：EDR toggle 不 stale PipeCacheKey）。
- **证据**：`EDRViewportTests` 全套绿；既有渲染/导出 golden 全量复跑记录（SUMMARY 贴计数）。

### T5 全量回归 + Manual-Only 登记 + SUMMARY + DECISIONS

- **action**：全 suite 终轮（基线 **1553/9skip/0fail** + 新增，0 fail；flake 条款见纪律节）；
  **Manual-Only 登记三行**（入 SUMMARY + 08-5 签核表汇总位）：①XDR 屏真机目检（高亮恢复细节 +
  >1.0 亮度差）②外接 HDR 屏双实测 ③headroom>1.0 屏上「not a different color space」观感确认；
  TODO.md 08-4 勾选；`08-4-SUMMARY.md`（任务表/commit 表/证据/Manual-Only 行）；`08-4-DECISIONS.md`
  （toggle 与 soft proof 并存语义、徽标文案、clearColor 适配、通知去抖、其余执行期决策）；新教训
  候选评估入 LESSONS。
- **证据**：测试计数（1553 → N，0 fail）；Manual-Only 三行落档；SUMMARY + DECISIONS 落盘。

## Verification

| 验收面 | 判据 | 命令 |
|---|---|---|
| PSO/toggle | 双 PSO 共存 / layer flag+色空间分叉 / P4 复验三件 | `Scripts/test-direct.sh 'EDRViewportTests'` |
| 终端旁路 | off 零路径差 hash 相等 / on >1.0 直通 / golden 矩阵绿 | `Scripts/test-direct.sh 'EDRViewportTests'`（旁路段） |
| headroom | 查询合法域 / 通知失效 / 1.0 徽标 | `Scripts/test-direct.sh 'EDRViewportTests'`（headroom 段） |
| 三件套 | off 逐字节 / on 三不进独立断言 / 缓存键零 stale | `Scripts/test-direct.sh 'EDRViewportTests'`（断言段） |
| 回归 | 全 suite 0 fail（基线 1553+新增） | `caffeinate -dis Scripts/test-direct.sh`（全套） |

## 验收标准（Acceptance）

- [ ] 16F blit PSO 变体（共存不替换）+ `wantsExtendedDynamicRangeContent` + extendedLinearSRGB +
      display colorspace 跟随 on 分支跳过——预留位注释位兑现
- [ ] 终端段 SDR 钳制旁路（on 分支 only；>1.0 直通合成器；off 零代码路径差 hash 相等）
- [ ] headroom 查询 + 跨屏失效（双通知订阅）+ headroom=1.0 toggle 合法 + 无余量徽标
- [ ] SDR 不变断言三件套：off blit 快照逐字节相等；EDR on 不进 export（导出 golden 逐位不变）/
      不进 history（无新项）/ 不写 sidecar（字节不变）三独立断言；PipeCacheKey 零 stale
- [ ] EDRControlView（SoftProofControlView 同位形状）+ toggle 状态面 = viewport 级 runtime override
      （非文档参数）
- [ ] Manual-Only 三行登记（XDR 目检 / 外接 HDR / headroom>1.0 观感）——不阻断交付
- [ ] 全 suite 0 fail（1553+新增）；每任务独立提交 + 边界查 config 开关；不 push；SUMMARY +
      DECISIONS 落盘
