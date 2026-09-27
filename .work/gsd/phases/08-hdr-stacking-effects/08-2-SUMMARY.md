# Plan 08-2 — SUMMARY（创意效果簇 A：vignette + grain + bloom）

**完成**：2026-09-28。执行 = ZCode subagent worker（原班 agent_695a8d33，T1/T2/T4/T5）+ 续班
subagent（T3 bloom，协调者改派独立车道，撞车记录见 §5）。与 08-1（Core Session 服务）W1 正交并行。

## 1. 任务表

| 任务 | 交付 | commit |
|---|---|---|
| T1 vignette 68.0 | dt 参数面 verbatim（dither 不移植）+ OpenCL 形单 kernel + float64 参考 + 6 测试 + 面板 + 14 键 catalog | `c44a548` |
| T2 grain 65.0 | 3-octave simplex verbatim + StableHash 种子 + 确定性双断言 + 8 测试 + 面板（ISO 标注） | `366cdf4` |
| T3 bloom 61.0 | 三段 verbatim + 级联 blur + 线性阈值映射 + HDR 零特判 + 6 测试 + 面板 | `49db32c`（续班） |
| T4 接线复核 | EffectsWiringTests 5 件（层蒙版 ×3 / 恒等种子 / perf 探针）+ L031 grep + V50OrderTests 复核 + perf.md | `8842a1c` |
| T5 收口 | 全量回归 + 本 SUMMARY + DECISIONS + perf.md/TODO/PROGRESS 翻账 | 本提交 |

注：3b2881b（标题 vignette）为续班会话在竞态窗口把本班未提交的 T2 Registry/xcstrings 接线误卷
提交——内容无害（grain 注册行 + 5 键），message 错位按协调者裁决不修正；T2 模块本体仍由 `366cdf4`
提交。zh/en catalog 计 19 键（vignette 14 + grain 5）由两 commit 分摊入账。

## 2. 回归账

- 基线：1636/10skip/0fail（13-3 后）。
- 本 plan 收尾轮（T2 后、08-1 后续 WIP 搅动前）：**1694/11skip/0fail**（全套私库日志复跑确认）。
- 终轮（T4 后）：**1709/11skip/5fail**——5 个失败**全部**为 `SidecarMetadataV3Tests`（schemaVersion
  3→4 字节金样/round-trip/upgrade-diff），归因 = 并行 08-1 的**未提交** sidecar v4 迁移在制品
  （`LightamerSidecar.swift` `schemaVersionCurrent = 4` 在共享工作树被编译进测试束），非 08-2 面。
  08-2 五套件隔离复跑全绿：VignetteTests 6/6、GrainTests 8/8、BloomTests 6/6、EffectsWiringTests
  5/5、V50OrderTests 14/14。
- 在案 flake/共享环境条款（计划纪律节）：①共享 DerivedData 构建锁互撞（build db locked ×N，
  重试循环消解）；②共享 `/tmp/la-direct-tests.log` 被并行测试覆写 ×N（对策 = 私有路径副本
  `/tmp/la-082-test-direct.sh`）；③一次 8-test 中止 = metallib 断言（并行构建写同一 bundle 中截），
  重跑干净。三者均为双 executor 共享树形态，非产品缺陷，不计违约。

## 3. AC 自检（逐条）

- [x] **vignette 68.0**：参数面 verbatim（`vignette.c:57-72` 全表；dither 不移植 = D-08-CONTEXT-5③）；
  OpenCL 形单 kernel（cosine 平滑恒用，research §17.3）；float64 采样点 **1e-6** 容差全图 parity；
  brightness ± 双支路分叉断言；unbound 裁剪语义（>1.0 无钳 vs false 钳 1.0）；面板四件套（PanelView
  + Provider + InspectorState 注册 + 14 键 zh/en）。
- [x] **grain 65.0**：3-octave simplex verbatim（f/a 表 + ×32 缩域 + Gustavson 全表直译）；paper_resp
  包络（解析形，D-08-2-2）；luma 域注入（Rec2020 系数，RGB 等量=亮度颗粒）；seed = StableHash(params ⊕
  imageIdentity)（L013，D-08-2-1 载体注记）；确定性双断言**逐字节**（同图同参两次 == bit-exact；同参异图
  必异）；功率谱锚（zoom 无关形，前两 octave 峰在位，D-08-2-6 裁剪注记）；scale ISO 标注（×213.2）。
- [x] **bloom 61.0**（续班交付）：threshold→级联 blur→screen 三段；线性域映射终式（luma/4·scale、
  (thr/100)³、strength 指数形保留）；点光源半径/幅值 golden；HDR >1.0 零特判（公式值钉死）；面板四件套。
- [x] **三模块层蒙版局部化**（terminalTailFloor 68/65/61 < 70 资格）：EffectsWiringTests ×3——蒙版内
  内容级生效 + 蒙版外**逐字节**不变（normal blend op=0 归约位）。
- [x] **中性种子恒等逐字节**：vignette/grain ENABLED-neutral 走 makeRoutedCommandBuffer blit 逐字节；
  bloom 无零参恒等 → DISABLED 种子逐字节（creative disposition，D-08-2-B4 续班注记）。
- [x] **L031 路由 grep 零自建**：三模块目录 `commandQueue`/裸 `makeCommandBuffer()` 零命中；全部提交走
  `makeEncoder`（vignette :261 / grain :209 / bloom :218-268）+ identity blit 走 `makeRoutedCommandBuffer`
  （vignette :290 / grain :236）。
- [x] **V50OrderTests 全绿零移动**（14/14）：61.0/65.0/68.0 槽位既有；新行义务在 08-5 text overlay。
- [x] **60fps preview 预算不回退**：perf.md 08-2 节（vignette 26.0 / grain 25.8 / bloom 27.8 ms 整链
  @2560px Debug，只记不设门；级联 0.29s@100MP P5 参考对账注记）。
- [x] **zh/en catalog**：19 键三组（vignette 14 / grain 5 / bloom 5 由续班 commit）全量 L025。
- [x] **每任务独立提交 + 边界查 config**（auto=true/paused=false 全程）+ 不 push + SUMMARY/DECISIONS 落盘。

## 4. Manual-Only 预定项（R4）

- **bloom 默认手感观感轮**：线性域阈值映射（/4 白锚 + 立方曲线）无 dt 直接对照，默认参数的观感校准 =
  Manual-Only 观感轮预定项（数值锚已按 research §9.2 钉死，手感校准不改结构）。
- grain 手感（strength/scale 组合观感）同轮顺带目检；vignette 无域适配、dt 直映，无需观感轮。
- pristine 图 grain 图案跨启动重掷（D-08-2-1 载体注记的已知 wart，sidecar 首写后冻结）——观感轮确认
  是否需要升级为 sidecar imageID 直通。

## 5. 撞车/协调记录

- W1 双 plan 并行 + 同 plan 双会话竞态：本班（T1/T2/T4/T5）与续班（T3）曾短暂双写；协调者裁决 =
  T3 归续班、T1/T2/T4/T5 归本班（PROGRESS.log 02:1x 行）。共享 DerivedData + 共享 /tmp 日志 +
  共享 git 工作树的三重竞态面见 §2 条款。
- 本班为解锁共享构建对 08-1 在制品做过一次最小编译修复（`StackMergeService.swift` actor 内显式自身
  类型引用 → 去前缀），**留工作区未提交，归属 08-1**（T3 续班 BandStreamer 先例同款）。

## 6. 证据指针

- 测试：`Tests/LightamerTests/{VignetteTests,GrainTests,BloomTests,EffectsWiringTests}.swift`
- L031 grep 输出：§3 第 6 条（全文见 EffectsWiringTests 头注 + 本 SUMMARY 提交 diff）
- perf：`.work/gsd/phases/08-hdr-stacking-effects/perf.md` 08-2 节
- 决策：`.work/gsd/phases/08-hdr-stacking-effects/08-2-DECISIONS.md`（D-08-2-1..6 + 续班 B1-B5 收编）
