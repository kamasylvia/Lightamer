---
phase: 4
plan: "04-04"
title: "lens correction（IOP-GEO-03，槽位 13.0，D-G1 三层）—— SUMMARY"
status: complete
executed: 2026-09-21
tests: "358 tests, 3 skipped, 0 failures (full LightamerTests; 验收独立实跑 2026-09-21)"
---

# Plan 04-04 SUMMARY — lens correction（三层：内嵌直通 / 手动滑块 / Lensfun XML 只读）

## Goal 达成

交付 IOP-GEO-03（D-G1 三层）：(a) CIRAW 内嵌校正直通（零代码，模块头 +
面板注记文档化、防双补）；(b) 手动滑块融合 kernel `lens_manual_warp`
（径向畸变 dc1..dc4 + 逐通道 TCA + devignette 除法，一 pass）；(c) Lensfun
XML 只读集成（XMLParser + EXIF 匹配 + Hermite/IDW 插值 + 系数归一，喂同一
kernel）。槽位 13.0（cacorrectrgb 13.5 注释对齐）。

## Tasks（11 commits）

| Task | Commit | 状态 | 证据 |
|---|---|---|---|
| T0 checkpoint 三口径 | `49d5c9e` | ✅ | DISCUSSION-LOG 04-04-T0 + 04-04-DECISIONS.md D-04-04-T0-1..3 + D1–D9 |
| T1 kernel + 模块 + 注册 | `39eb6ab` | ✅ | LensKernels.metal + LensModule.swift + Registry（ashift 误删后由 `1441a0e` 恢复） |
| T2 解析/匹配/插值 + 子集 | `d5dac6a` | ✅ | LensfunDBTests 15/15 + fixtures/lensfun 4 文件 + match-ledger（`20ce7a8`） |
| T3 统一出口 + 面板 + 下载 | `3f40bfe` + `918285c` | ✅ | LensPanelView 三段 + catalog 20 keys + PanelWiring +2 + launch hook |
| T4 golden + 双真 bug + 签收 | `bf90785` + `f68e114` + `0848d81` + `4c9e708` | ✅ | LensParityTests 7/7 + manifest lens 节 + ROI +1 + 轨 B 链含 lens |

## 验收标准逐条自验（plan Verification 表）

- **IOP-GEO-03 golden+unit（T1/T2/T4）**：合成 float64 参考 parity
  <1e-5 相对/<1e-5 绝对 + k=0 恒等逐值 + vignette 解析点检 + CA 方向 +
  XML 解析钉参 ✅（LensParityTests 7/7：6 case × 4 fixture = 24 路实比对，
  anti-vacuum compared>0；LensfunDBTests 15/15：d-factor/Hermite/IDW 手算值）。
- **D-G1 三层完整性（T1/T3）**：(a) 模块头 + 面板注记文档化；(b)(c) 同一
  kernel 逐分量一致 ✅（`testUnifiedExitMatchesManual`：同系数双门
  maxDiff ≤1e-6；降级路径无数据 → 恒等 + 手动可用）。
- **ROI 非零外扩（T1）**：forward AABB + 中性恒等缓存零扰动 ✅
  （`testLensShrinkNegotiationBoundsInput`：pincushion → (0,0,62,62)；
  `testNeutralROIIdentity` + `testNonzeroROIGrows`）。
- **轨 B 回归（T4）**：ColorSync 中性度 + 交叉一致性 ✅
  （GeometryGolden track B 链已含 neutral lens，4/4 全绿）。
- **手动校正视觉（T4）**：04-VALIDATION Manual-Only 表登记 ✅
  （DSC00012/DSC09991 建筑直线，L011 口径 pending-manual）。

## 关键修复（排障记录，教训沉淀候选）

1. **ROI 宽度从未 clamp 原点起算（模块级）**：`modifyROIIn` 宽度按
   `xM + m − xm + 1`（xm 未 clamp）——收缩 AABB 下丢 xm 像素
   （pincushion xm=2.56 → 输入平面 61 宽缺 tap 列 61，kernel 在 x0 冻结，
   ramp x=63 以 0.952381 精确签名抓获）。修复 = 从 CLAMPED 原点起算
   （dt `:1791-1799` 字面 `width = MIN(orig−x, xM−x+interp)`），得 63 宽。
2. **子域 renderRegion 的 ROI 直通 CI 坐标（管线级）**：ROI（左上原点）
   未翻直接当 CI bounds（左下原点）——渲染 file row H−M+r 而非
   region.y+r。y 不变 fixtures（ramp/flat/灰阶）全盲，checkerboard
   以整行翻转抓获。修复 = `region.y = extent.maxY − ryTop − rh`
   （extent 相对，CIRAW 非零原点同样正确）。全 suite 358 绿验证无回归（验收独立实跑）。
3. **ashift 注册误删（流程）**：T1 整段替换吞掉 ashift register +
   prewarm（seed 行幸存）→ 全套 8 失败（makeBox nil）。修复 =
   `1441a0e` 加回两段。教训：Registry 类共享文件改动后跑全套，
   不只跑本 plan 子集。
4. **XMLParser delegate 漏 camera/lens 入库分支**： insulated 内联测试
   同样 0 条目（hermetic 不背锅）→ 补 `didEndElement` 两分支。
5. **lens mount 引用/start 条目冲突**：`<mount>` 在 lens 内是文本引用，
   顶层才是条目——start 按 curLens 区分，end 按分支入库。
6. **Float 存储容差**：kr/vr 类 1e-9 断言对 Float32 存储过紧 → 1e-6。
7. **fixtureDir 少一层 deletingLastPathComponent**：`#filePath` 深 4 层，
   不是 3 层（与 goldenDir 同式）。

## 全绿闸门

- 全 suite：**358 tests, 3 skipped, 0 failures**（2026-09-21 终轮，
  验收独立实跑更正；omp 自报 355 为运行中计数。04-03 时 331 → +24：
  LensfunDB 15 + LensParity 7 + PanelWiring 2 + V50Order 1 + ROI 1，
  减探针退役）。
- 04-VALIDATION IOP-GEO-03 行 + D-G1 行 + 轨 B 行 ✅；Manual-Only：
  镜头校正视觉登记（L011 口径 pending-manual）。
- 下游影响：04-06（SC#2 签核——Lensfun open decision 落地证据就绪）；
  子域 CI 翻转修复惠及一切 shrink-ROI 路径（crop hint/未来 sharpen）。

## 过程记录

- 本文件 + 各提交 body + 04-04-DECISIONS.md + `.work/plans/04-04/match-ledger.md`；
  调试探针（LensDumpProbe/行列 dump/CI 坐标探针脚本）已全部退役，
  无 `.work/plans/04-04/` 日志留存（排障全在提交说明；match-ledger 为交付物保留）。
