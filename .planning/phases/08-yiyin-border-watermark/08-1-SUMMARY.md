# Plan 08-1 Summary — 印框 borders 模块与终端段扩展

**Status:** Complete（T1-T6 全部执行；全套 888/6skip/0fail）
**Executed:** 2026-09-25（ZCode subagent executor）
**Commits:** T1 `feat(iop): borders 76.0 skeleton + terminal tail window` → T2 `test(iop): YiyinLayout parity vs yiyin node harness` → T3 `feat(iop): borders solid leg + display-domain color + ROI canvas growth` → T4 `feat(iop): borders rounded-corner + shadow legs` → T5 `feat(iop): borders blur backdrop + adaptive brightness overlay` → T6（本提交：orientation 钉 + PREVIEW 初测 + 收口文档）。未 push（用户指令：本地 commit 即完成态）。

## 交付内容（对照 plan 验收标准）

- [x] **终端段识别扩为 iopOrder ≥ 70.0 尾窗**（`LayerCompositeDriver.terminalTailFloor` + 可测 `splitTerminal`；唯一管线改动）+ **tail 政策回归钉**（gamma 仍 top → `.bgra8Unorm`；borders/watermark 平面 float32）+ **全量回归零破坏**（colorin 28/skinSmooth 66.5 留 base；`testTailWindowExtraction`/`testTailWindowRoutesBordersToTerminalSegmentWithLayers`）
- [x] **BordersModule 76.0 注册**（V50Order 现表槽位，零插行）+ **Params 全参数面**（solid/blur 背景、width rate、min margin、aspect 重置、landscape 竖转横、radius/shadow 0..50 上限、textBottomOffset 0.027、adaptiveBackdrop）+ **seed enabled-neutral 恒等逐字节**（参数谓词直判 blit，轨 B `testSeedIdentityIsByteExactThroughPipe`；禁用 == 无实例）+ **ParamsCoding+StableHash**（L013，`testCommitHashesRawParamsViaParamsCoding`）
- [x] **YiyinLayout float64 布局器 13 case 逐值断言**（横/竖/方 × aspect 1:1、3:2、3:4 × landscape × margin/shadow × rate 50/100 × ceil-quirk 58×7 × rows）——整数精确 / 浮点 <1e-6 / compared>0；**yiyin node harness**（`Scripts/yiyin-ref-harness.mjs`，正本仓只读）量测对照 + sharp 合成量测探针精确命中（bbox == 期望整数）；参考 JSON `.work/plans/08-01/yiyin-layout-reference.json`；**联合布局空 rows 态接口就位**（`YiyinLayoutRecord` + `jointLayoutOverride` 缝）
- [x] **纯色/模糊背景 + 圆角 SDF + 投影 + 亮度四档蒙层全腿**——平场门（白底纯色取样值精确 / 模糊 DC 增益=1 / 阴影=0 逐字节回 T3）/ 投影 alpha 剖面方向（SDF 半径精确切角、投影带单调衰减）/ 蒙层四档阈值表驱动 / σ = %×bgHeight/100×0.5 定标式（D-08-CONTEXT-6）入 DECISIONS D-08-1-8
- [x] **窗口化 FULL 画布扩展内容级断言**（32×24 窗 @ (10,8) → 画布 64×48；主图取样值 == 基线平面逐值——L020/L021 红线）+ **LAYER-06 层内纪律钉** + **orientation=6 回归钉**（直正像素驱动布局：64×32 传感器图 → 竖构图 64×128 画布）
- [x] **色彩换算走 ColorOutModule 同源 profile**（COLOR-2：sRGB hex → 线性化 → Rec2020 → P3/sRGB 显示域；白色/中性灰全目标精确；sRGB 红 → P3 已知点 0.822461969/0.033194198/0.017082631 全管线取样钉）+ **模糊腿复用 GaussianBlur 零重写**（L018；√N 多 pass 分解入包络，DECISIONS D-08-1-8）
- [x] **轨 B 中性插链零增量逐字节 + 禁用实例 == 无实例 + 全量 suite 0 fail + manifest 节 + SUMMARY/DECISIONS 落盘**

## 验证数字

| 面 | 数字 |
|---|---|
| 全套（终轮） | **888 tests / 6 skipped / 0 failed**（基线 864 → 888 +24：T1 10 + T2 3 + T3 9 + T4 4 + T5 6 + T6 2；T2/T3 提交时全套分别 864/0、876/0） |
| 布局 parity | 13 case × 逐值（整数精确/浮点 <1e-6）+ ceil-quirk 钉 + sharp 探针 bbox 精确命中 |
| 色彩 COLOR-2 | 白/灰全目标精确（D-COL1）；P3 已知点 ±1e-6（纯函数）/ ±1e-5（全管线取样） |
| 轨 B | 中性插链 == 无实例逐字节；禁用 == 无实例；shadow 0 == shadow nil 逐字节 |
| ROI | 80×60 增长向量 + 画布→frame 回映射向量 + 窗口化 (10,8,32,24)→(0,0,64,48) 内容级（主图 == 基线 1:1） |
| SDF/投影 | 圆角切角内容级（弧外=填充/弧内=主图）+ 投影带单调衰减 + SDF alpha 剖面（内 1/外 0） |
| 模糊/蒙层 | DC 增益=1；带内容区分度；四档边界表驱动；暗背景增亮数值预测命中 |
| 缓存语义 | 参数编辑 proxy+blur 双命中（共享 PipeCache+稳定 imageID）；换图重建 |
| PREVIEW 初测 | 只记不设门（Debug、含 CI 解码与 PSO 冷干扰；正式 benchmark 8-3 perf.md）：solid ≈ 250-270ms / radius+shadow ≈ 280-380ms / blur+overlay 首测 23.8s → √N 分解后仍 ~160s（模块腿级：proxy+blur ≈ 7.3s、composite ≈ 1.8s @ 5.4Mpx 画布）——**SC 门 = 8-3 真机拖动 + 观感定标** |

## 遗留 / 风险（对表）

1. **blur 腿 Debug 初测偏重**（~160s/帧 全链、模块腿 ~7.3s）：PSO 冷 + 21-pass 分解 + CI 解码干扰混杂；8-3 正式 benchmark（perf.md，只记不设门）+ 观感定标（D-08-CONTEXT-6 允许微调）时一并处置（候选：pass 数上限与 σ/pass 包络再平衡、proxy 长边降档、模糊腿管线单 CB 合并提交）。
2. **GoldenColor 既有 flake**（L018 类 CI 腿浮动，GOAL-STATE/GUI-23 在册）：本轮全套首跑出现 1 次、单跑绿、复跑全套绿——与本 plan 无关，留档复估。
3. **蒙层/模糊的线性域 vs yiyin 编码域代数差**：观感容差带（DECISIONS D-08-1-5/D-08-1-6），8-3 GUI 轮 Manual-Only 目检。
4. **borders 层链优雅拒绝**：当前靠提取保证 + L021 precondition 背板（D-08-1-9）；如需报错式拒绝，8-2/后续并入槽位拒绝集合。
5. **联合布局 rows 激活**：8-2 落 watermark rows 后激活（`jointLayoutOverride` 缝已就位；rows 腿公式已按 yiyin `:543-545` 末行膨胀 quirk 实现并有 harness 对照 case）。
6. **水印半边（77.0）**：08-2；**导出接线**：Phase 11（D-08-CONTEXT-7）。

## 关键文件

- `LightamerCore/Sources/Pipe/LayerCompositeDriver.swift`（尾窗，唯一管线改动）
- `LightamerIOP/Sources/Yiyin/{BordersModule,YiyinLayout,YiyinColor,YiyinKernels.metal}.swift`
- `LightamerIOP/Sources/Registry.swift`（注册 + 种子 + prewarm）
- `Scripts/yiyin-ref-harness.mjs`；`Tests/LightamerTests/{YiyinBordersTests,YiyinLayoutTests}.swift`
- 决策正本：`08-1-DECISIONS.md`（D-08-1-1..10）；参考 JSON：`.work/plans/08-01/yiyin-layout-reference.json`
