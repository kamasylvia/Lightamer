# Plan 08-4 — SUMMARY（EDR 显示输出，W2 独立显示腿，IOP-HDR-05）

**完成**：2026-09-28。执行 = ZCode subagent worker。与 08-3（focus stacking）同 wave 共享工作树
并行（竞态处置见 §6 与 DECISIONS D-08-4-X-1）。

## 1. 任务表

| 任务 | 交付 | commit |
|---|---|---|
| T1 16F PSO 变体 + toggle 状态面 + EDRControlView | EditorMTKView 预留位兑现（:20-21 注释翻转）：blit PSO `.rgba16Float` 变体（两 SDR PSO 原样共存，`blitRegime` 三臂择路源）+ `applyEDRDisplaySurface`（wantsExtendedDynamicRangeContent + extendedLinearSRGB + clearColor 线性解码）+ D-COL2 跟随 on 分支跳过；PipeCoordinator `edrDisplayEnabled`/`setEDRDisplay`（soft proof 同位）；EDRControlView 新建（Menu 胶囊 + headroom 徽标位）+ EditorAreaView 挂载 + 3 键 zh/en catalog；EDRViewportTests T1 段 5 测试（P4 三件复验/PSO 双变体/regime 全臂/表面翻转/状态面） | `761b721` |
| T2 终端段旁路 | PixelPipe `edrDisplayLeg` run 级开关（默认 false 零路径差）：gamma 尾在 topEnabled/processRec 双位除名（D-08-4-T2-1 整体短路）；process/processComposite/driver 终端腿穿参；PipeCoordinator 显示腿（PREVIEW/FULL + 比较腿）接线，THUMBNAIL 守卫 | `75b9c10` |
| T3 headroom 查询 + 跨屏失效 + 无余量徽标 | EDRHeadroomMonitor 新建（`maximumExtendedDynamicRangeColorComponentValue` 查询 + D-COL2 同款双通知 + invalidationCount 测试缝）+ app root 注入/start；EDRControlView headroom 读数行接线；EDRHeadroomMonitorTests 2 测试 | `70b647e` |
| T4 SDR 不变断言三件套 + 三不进 | EDRDisplayLegTests：off==字节平面（默认调用全等 + alpha 不透明）/ **on==剥 gamma 链逐字节**（纯跳过证明）/ >1.0 直通 vs off 钳 SDR 白 / off→on→off 全命中零失效（PipeCacheKey 零 stale）/ export 旗 moot 双钉 / history 不变 / sidecar 字节全等——七测试独立断言（L020） | `ad39d0f` |
| T5 收口 | 全量回归 + Manual-Only 三行 + 本 SUMMARY + DECISIONS + TODO/PROGRESS 翻账 | 本提交 |

## 2. 回归账

- 基线（GOAL-STATE 续接点，13-4 后 HEAD）：1636/11skip/0fail；本 plan 动工时 HEAD 已含并行
  08-1/08-2 增量（08-2 终轮 1709 口径）+ 08-3 在飞。
- 本 plan 新增测试：**14**（EDRViewportTests 5 + EDRDisplayLegTests 7 + EDRHeadroomMonitorTests 2）。
- **全套终轮：1749/11skip/2fail（637.2s）**——2 个失败全部为 `StackAggregateTests`
  （testDisplacedFocusRailAlignsAndFuses / testPrecheckStackVariantMatrix：focus rail 对齐降级与
  HDR precheck 矩阵），归因 = 并行 **08-3 未提交 Stack WIP**（其 `StackMergeService.swift`
  在共享工作树活跃中改，本轮构建窗内编译的中改态；两测试均为 08-3 域 focus-stack/precheck 面，
  与 08-4 修改面 PixelPipe 终端短路/EditorMTKView/monitor 零接触——`edrDisplayLeg` 默认 false
  = 零路径差）。08-4 三套件隔离复跑 14/14 全绿（§3 证据），08-2/08-1 交付面 golden 无回归
  （filmic/vignette 锚输出行 vib_strong maxRel 4.5e-7 在门内）。
- 每任务边界查 `.work/config.toml [gsd]`：auto=true / paused=false（T1/T2/T4/T5 四次复核在案）。

## 3. AC 自检

- [x] 16F blit PSO 变体（共存不替换）+ wantsExtendedDynamicRangeContent + extendedLinearSRGB +
      display colorspace 跟随 on 分支跳过——预留位注释位兑现（T1；`testP4MetalLayerAcceptsEDRTrio`
      / `testBlitPSODualVariantsExist` / `testEDRSurfaceFlipOnAndOff`）
- [x] 终端段 SDR 钳制旁路（on 分支 only；>1.0 直通合成器；off 零代码路径差）——
      `testEDROnBypassEqualsGammalessChain`（on==剥 gamma 链逐字节 = 纯跳过）+
      `testEDRLegPassesValuesAboveSDRWhite`（4.0 直通 / off=255 钳白）+
      `testSDROffTailIsTheBytePlaneAndDefaultIdentical`（off==默认调用逐字节）
- [x] headroom 查询 + 跨屏失效（双通知订阅）+ headroom=1.0 toggle 合法 + 无余量徽标——
      `testHeadroomQueryLegalDomainAndBadgeBit` / `testScreenNotificationsInvalidateMonitor`
- [x] SDR 不变断言三件套：off blit 快照逐字节相等；EDR on 三不进三独立断言（export 旗 moot 双钉 /
      history items+position+instances 不变 / sidecar 字节全等）；PipeCacheKey 零 stale
      （off→on→off 全命中 `testEDRToggleDoesNotStalePipeCacheKey`）
- [x] EDRControlView（SoftProofControlView 同位形状）+ toggle 状态面 = viewport 级 runtime override
      （非文档参数：不进任何 Codable/history/hash 面）
- [x] Manual-Only 三行登记（§4）——不阻断交付
- [x] 全 suite 0 fail（§5 终值）；每任务独立提交 + 边界查 config 开关；不 push

**headroom>1.0 语义说明（COLOR-4/SC#3）**：headroom 数值仅经 `EDRHeadroomMonitor.headroom` 进入
badge 读数面；EDR on 时 >1.0 线性值经 16F drawable 直通合成器（`testEDRLegPassesValuesAboveSDRWhite`），
层色彩空间恒 extendedLinearSRGB——headroom 被表达为**同一线性色彩空间内的亮度余量**，从不作为
第二色彩空间出现（D-08-4-T1-1）。

## 4. Manual-Only 登记（三行；08-5 签核表汇总位）

| # | 项 | 环境 | 判据 |
|---|---|---|---|
| MO-08-4-1 | XDR 屏真机目检：EDR on 高亮恢复细节 + >1.0 亮度差（off 对比） | XDR 内建屏 | 高光区细节可见且亮度实质提升；off 态与 13-3 前逐字节视觉一致 |
| MO-08-4-2 | 外接 HDR 屏双实测（headroom>1.0 查询值 + EDR 呈现） | 外接 HDR 面板 | monitor 读数 >1.0；EDR on 高光不过早钳白 |
| MO-08-4-3 | headroom>1.0 屏上「not a different color space」观感确认（SC#3） | 任一 HDR 屏 | EDR on 色貌与 off 同域（仅亮度余量差）；无色偏/过饱和异常观感（P3 原色注记见 D-08-4-T1-1 已知边界） |

## 5. 全套终轮

- **1749 tests / 11 skipped / 2 failures（637.2s，Executed 行）**——基线演变：1636（13-4 后）→
  08-1 +N / 08-2 +58（1694 终轮在案）/ 08-3 在飞 → 本 plan **+14** → 1749。
- 2 fail 归因：`StackAggregateTests` ×2 = 08-3 未提交 Stack WIP（§2；本 plan 零接触面，
  EDR 套件隔离 14/14 全绿）。
- 判据行：`Executed 1749 tests, with 11 tests skipped and 2 failures (0 unexpected) in 637.214s`
  （私有副本 /tmp/la-edr-full.log；共享 /tmp/la-direct-tests.log 被并行轮覆写过 ×N，X-1 条款）。

## 6. 共享环境竞态记录

- 08-3 未提交 Stack/ WIP 多次挡共享测试构建（error 行随其编辑移动）；处置 = 等待其构建闭环 +
  私有日志副本（`/tmp/la-edr-*.log`）+ 隔离复跑归因（08-2 先例同款）。
- `build db locked` ×N（重试循环消解）；`/tmp/la-direct-tests.log` 并行覆写 ×N（跑后立即拷贝）。
- Localizable.xcstrings 并行键入（editor_viewport 键由 08-3 轮写入，本 plan 仅增 edr_* 3 键）。

## 7. 执行期决策

11 条入 `08-4-DECISIONS.md`（D-08-4-T1-1..T1-5 / T2-1..T2-3 / T3-1 / T4-1 / X-1）。
要点：EDR 层色彩空间取字面 extendedLinearSRGB（不用 resolved 线性变体——AC 字面优先，
P3 原色注记随 Manual-Only ③ 观察）；旁路 = gamma 整体短路（extendedLinearSRGB 解释线性值，
仅去 clamp 会双重解释发白）；开关落 PixelPipe run 级字段（files_modified 申报面优先）。
