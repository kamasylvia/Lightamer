# Plan 08-1 SUMMARY — 堆栈簇底座 + HDR merge（W1，堆栈簇依赖根）

**执行**：ZCode executor subagent worker（2026-09-28；`auto=true/paused=false` 全程）
**提交**（7 个，未 push，全部 Conventional Commits）：

| commit | 任务 | 内容 |
|---|---|---|
| `7825089` | T1 | StackMergeService actor 骨架（ExportQueue 结构孪生：专属低优先级队列 + cancel epoch 三 gate + (done,total) 进度窗 + 显式 retry + 三失败分型）+ SessionBrowserView「HDR 合并…」menu/dialog/回调接线 + test-direct.sh grep `-a` 修复 + CIRAW 100MP 解码首测（perf.md 开账） |
| `15da1e5` | T2 | MTBAlign（research §2.1 参数定表 + 收缩窗 + 自适应底层/level-0 低纹理两处 fixture 路径学钉）+ ExifPrecheck（§2.4 矩阵 + §1.2 交集带比例自检） |
| `8abfc07` | T3 | HDRMergeMath（权重终形/HOLE/ghost 残差数学，CPU 纯函数 golden 正本）+ BandStreamer（行带几何 + 累积面足迹契约 + float TIFF writer） |
| `7f7e92b` | T4 | GhostMaskWriter（3×3 膨胀 2 轮 + 16-bit PNG 落 RasterMaskRef 形态 + Ghost Suppression 层栈） |
| `1dc1556` | T5+T6 | 生产 mergeLeg 全链（EXIF 预检 → MTB → Robertson 带流 → ExportNamer 防撞落位 → ghost PNG → 诞生 sidecar）+ SessionTreeScanner `.lra.masks/` 排除 + App 完成钩（toast/reconcile/reload）+ sidecar v4 provenance + ProvenanceReplay（漂移/重放/等价） |
| `e4ce37b` | T7 | HDRPipelineMatrixTests 基座（4 测试）+ perf.md 对账列 |
| T8 收口 | T8 | 本提交：SUMMARY/DECISIONS/TODO/PROGRESS/xcstrings(8 键 zh+en) |

**回归**：基线 1636/10skip/0fail → 本 plan 五套件 52 测试**全绿**（StackMergeServiceTests 11 +
MTBAlignTests 14 + HDRMergeMathTests 15 + ProvenanceV4Tests 8 + HDRPipelineMatrixTests 4）。
**收尾轮全 suite 实况 = 1746/11skip/13 fail**（04:43 独立 log /tmp/la-081-final2.log）——13 个
失败**全部属并行 worker 在制品，非本 plan 面**：FocusStackTests 7（08-3，含 1 crash
`Index out of range` 中止早前一轮）+ StackAggregateTests 3（08-3）+ EDRDisplayLegTests 1
（08-4）+ PanelWiringTests.testYiyinCatalogSmoke 2（yiyin catalog 空数据）。本 plan 类零失败、
1636 基线面零新增失败。ToneEqualPerf 负载型 flake 隔离单跑绿（在案条款归因）。

## 验收标准逐条

- [x] `StackMergeService`：actor + 专属队列（自包含域，L031 措辞遵守）+ cancel epoch 三 gate/
      progressHook/显式 retry + 三失败分型 + 源只读断言（mtime+bytes）——`StackMergeServiceTests`
- [x] MTB 对齐：参数定表逐项 + (17,-11)/(-9,23) 精确命中（含 4×/0.25× 曝光差）+ 收缩窗 +
      降级标注 + 倾转旋钮位（v1 平移 only）——`MTBAlignTests`
- [x] EXIF 预检矩阵（严格/必须不同/override 放行）+ 运行时比例自检（>5% 降级）——`MTBAlignTests`
- [x] Robertson 合并：双门高斯权（σ=0.2 参数化 + weightNoiseFloor 默认关）+ HOLE 黑输出 +
      weight-map + holeFraction + **行带流式**（内存常量断言 28/41 B/px）+ float TIFF 写——
      `HDRMergeMathTests`
- [x] ghost mask：k=3 拒绝 |L̂−clean|<0.02 + 膨胀 PNG 落 RasterMaskRef + Ghost Suppression 层 +
      deGhost:false 零开销档——`HDRMergeMathTests`
- [x] 产物落位：会话根 `<stem>_hdr.tif`（stem 大小写保持）+ ExportNamer 递增防撞 + grid 可见性
      三行 + **E2E 全链可编辑**（真实生产 leg：合成 bracket → 产物 → walk 可见 → RAWDecoder
      保深 → history/sidecar round-trip 零漂移）——`ProvenanceV4Tests`
- [x] sidecar v4：optional provenance 终表 + round-trip（decimal String wire 断言）+ v3 手写档
      零害 + 源漂移标脏（一字节翻转 → 单源命中）+ 重放同参等价（provenanceHash）+ UInt64String/
      relPath 纪律——`ProvenanceV4Tests`
- [x] HDR-04 矩阵基座：已知值逐点（exposure 解析参考 1e-5）+ **65504→131008 无钳制存活** +
      toneequal(0) 全链尾恒等（maxDev=0.0）+ torture 有限性诊断；lut3d 列留 08-5——
      `HDRPipelineMatrixTests`
- [x] perf.md：解码首测（101.8MP align-pass 0.96–1.93s / merge-pass 0.92–0.99s，R7 解除）+
      全程秒表（24MP 实测 73.5s Debug + 归因注记）+ 各段对账列（只记不设门）
- [x] 每任务独立提交 + 边界查 config 开关（auto=true/paused=false 全程）+ 不 push +
      fixture 落 /tmp（禁 UNITEK）+ SUMMARY/DECISIONS 落盘

## Manual-Only 登记（不阻塞）

1. **真 RAW bracket 灰卡两点标定**（research §1.2 R2 消解的单次确认项）：本机无真三脚架
   bracket 样张；合成 float TIFF bracket 走通了生产 leg 全链，CIRAW 单张（101.8MP）已实测，
   但 per-image boost/tone 预修饰的实拍验证需真 bracket——待样张供件后一次确认。
2. **HDR menu/dialog/toast 真机观感走查**（含 N=3 弱统计文案）：GUI 层声明式接线以
   coordinator seam 测试钉（`testCoordinatorHDRMergeSeamReachesService`），视觉走查归统一
   GUI 验收轮。

## 移交 08-3 / 08-5

- **08-3**（focus stacking/堆栈降噪）：`StackMergeService` 骨架（legs 注入缝、进度窗、cancel/
  retry）、`MTBAlign`、`ExifPrecheck`、`BandStreamer` 全复用；新 kind 走 `MergeKind` 分派
  （非 hdrMerge 在生产 leg 顶部 typed `.notImplemented` 位替换末端段）。
- **08-5**（收口）：①lut3d 矩阵列 ②CI input 腿 RGBAh 对 sub-1e-4 HDR 值下溢（D-08-1-13①）
  ③torture 96×96 管线黑平面分歧（D-08-1-13②）④24MP/100MP Release 口径全程秒表
  ⑤preview float32 预算正式结论。

## 偏离与勘误

1. plan T3「CGImageDestination 分行 append」不可行（ImageIO 无 scanline append）→ 整帧
   finalize + tmp 晋升（D-08-1-2，语义等价：单产物、原子、不覆盖）。
2. research §6「逐行带解码」→ 整帧解码 + 带级消费（D-08-1-1，CIRAW 无逐行能力；R3 红线与
   恒量内存主张完整保留）。
3. plan 基线两处笔误（1636 vs 1553）按 R1 修订版 1636 执行；SessionBrowserView 路径修正
   （UI/）按 R1 落地。
4. T5/T6 因数据面耦合（service 尾段同写 provenance sidecar）合并为一个提交（自洽性优先，
   消息内分标两任务战果）。
5. 并行 worker 构建竞争（08-2/08-4/08-3 同仓 in-flight 文件）以轮询等待处理，未触碰他方
   文件；xcstrings 提交延后至他方键落定（协调者并行冲突规则的执行）。
