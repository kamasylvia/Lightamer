# M2-11 VALIDATION INPUT — M2 closeout 签核输入汇总（2026-10-07 执行批 T1/T2 落盘）

> C 档门控第 3 停输入 = 本文件（兼 **M2 milestone 收口签核**——OQ-8-A 单文档
> 收口，`M2-11-VALIDATION.md` 为正本）。结构先例 = `M2-10-VALIDATION-INPUT.md`。
> 状态：**T1 机检 + T2 全 `--all` 终验已落账（本批）；T3 GUI 一轮四义 + T4 SC
> 对账表/挂账总汇编/签核路径随后续批补齐。**

## 一、机检两件（T1，2026-10-07 亲跑）

### 1.1 红线域零 diff（D-M2-11-CONTEXT-6，窗口 = `9586c1b..HEAD`）

checker m6 回注采纳：窗口从 9586c1b 起算（M2-11 归因纯净窗；`c573087..9586c1b`
段 M2-10-07 已核零命中，SUMMARY :64）。窗口锚 = `9586c1b`（feat(app): ai entry
points and zh strings）；窗内 commit 数 = **32**。

| 域 | 命令 | 命中数 |
|---|---|---|
| MCP | `git diff --name-only 9586c1b..HEAD -- App/Sources/Lightamer/MCP/ LightamerCore/Sources/MCP/` | **0**（M2AI-08 零改动终验成立） |
| Export | `… -- App/Sources/Lightamer/Export/ LightamerCore/Sources/Export/` | **0** |
| Version | `… -- LightamerCore/Sources/Sidecar/ LightamerCore/Sources/Library/`（M2-8 版本面 = sidecar v7 + .lalb version_ref） | **0** |

- 全窗产线 diff 亲核：`git diff --stat 9586c1b..HEAD -- LightamerIOP/ LightamerCore/ App/`
  = **唯一 `App/Sources/Lightamer/UI/Shell/WorkspaceHostView.swift`（+9/-2）**（M2-11-02
  T5 越界申报面 `bff022e`，Release 断代三修之 DEBUG probe guard）——红线域字面零命中。
- **`semantic_search` defer 维持**（OQ-12-A 签认延续；M2-11 零新增动作、零新验收面）。

### 1.2 M2 族机械扫（KD-1.3，E2 四行实况基线）

`grep -n "^- \[ \]" .work/gsd/REQUIREMENTS.md` M2 段 uncheck = **恰四行**（checker
E2 回注实况确认）：

| 行 | 项 | 关闭路径 |
|---|---|---|
| :41 | M2NODE-03（行内注记已载「严格面激活归 M2-5」+ `TODO.md` M2-5 批指针） | 翻账批补勾 + Delivered 终态注记（**执行批不越权预勾**；若 orchestrator 另有裁决则在签核面显式呈报） |
| :61 | M2DRT-06（行内注记已载 M2-6-3 终验 Delivered + 验收 PASS 指针） | 翻账批补勾（记账件） |
| :99 | M2PERF-01 | 本 VALIDATION 签核后翻账批勾 |
| :100 | M2PERF-02 | 同上 |

其余各族（M2LIB/M2GRADE/M2MASK/M2VER/M2EXP/M2AI）已翻账 Delivered 只做存在性核；
原 PERF 族 :613-620 历史行零触碰（M2-11-04 重述批纪律延续）。

## 二、全 `--all` 终验轮（T2，批准在案：plan 批 + 夜巡授权）

### 2.1 终验净轮（第 3 试，恢复协议后干净轮——终值以此为准）

**`TOTAL|2961/16/0|1081s` 单轮干净绿**（2026-10-07 09:04-09:22，build = R4 验收批
07:40 增量产物，895a352..HEAD 源码零 diff；skip 恒 16 零新增）。

| bundle | executed/skipped/failed | peakRSS | secs | L055 核读 |
|---|---|---|---|---|
| IOP | 471/1/0 | 7709 MB | 188 | 末条 Executed = All tests 总计 ✓ abnormal=0 ANE=0 |
| IOPParity | 362/3/0 | 5980 MB | 353 | ✓（贴线 bundle 5980 vs SPIKE 5788 = +3.3% 方差带内） |
| Layers | 300/3/0 | 1158 MB | 23 | ✓ |
| Library | 581/4/0 | 592 MB | 28 | ✓ |
| Sessions | 279/4/0 | 1649 MB | 75 | ✓ |
| Export | 338/1/0 | 6970 MB | 194 | ✓ |
| App | 630/0/0 | 2831 MB | 220 | ✓ |
| **TOTAL** | **2961/16/0** | max 7709 < 8192 | 1081 | 七日志 `terminated abnormally` 全零 + `ANECCompile` 全零 + 零 MEMFAIL |

- 对账三方（KD-1.4）：2955（M2-10 终值）+ **+6**（02 波 M2DefaultChainPerfTests 2 +
  03 波 FullRenderBenchmarkTests 1 + DrtTailTests 计时 2 + 04 波 MemoryBudgetTests 1）
  = **2961 精确**；bundle 位 = IOP 467+4=471 ✓ / Layers 298+2=300 ✓ / 其余五 bundle
  逐值零漂移 ✓；skip 16 按 test func 计零新增（E3 判定式 `16+Δs` 保形，Δs=0）。
  BUNDLE-MAP 历史行滞后注记：txt 合计 2942 系 M2-9/M2-10 波增行未回写 txt 所致
  （各波验收轮已各自对表），M2-11 增量四文件 `grep -c "func test"` 逐位亲核在案。
- SidecarV5 canary 本轮 **20.190s passed**（慢速绿非超时非崩；vs 晨绿 13.338s）。

### 2.2 PERF-07 终验带内复核（KD-1.2）

净轮 Sessions bundle 内：`PERF07-GATE segments1+2 10k: **0.543s** (gate ≤ 5.000s)`
（Debug harness record；composeSegment 0.524s / claimBatchApply 0.020s / fixture-build
1.655s）——vs 在案 0.490s = +10.8% 机器态漂移**带内即过**（余量 ~9.2×），万张 apply
Delivered 维持。正本 = perf.md §PERF-07 终验带内复核节。

### 2.3 恢复协议实录（checker E1 真链纪律；flake 台账已同步追加行）

终验轮经历三次全套（前两次 App 段崩，第三次干净绿）+ App 独立轮五次（四红一绿）：

1. **崩溃家族**：App bundle 宿主 EXC_BREAKPOINT（SIGTRAP）at `swift_unknownObjectRetain`
   ← `ToneEqualModule.dispatchPack / dispatchLuma` ← PixelPipe.processRec ←
   PipeCache.plane——**ToneEqual encode 路径悬垂 retain = 潜伏缺陷家族**（2 份 .ips
   同栈亲证，证据正本 `profile/appbundle-crash-2026-10-07-0812.ips`）；崩点漂移
   （GUI22 undo 渲染 / DrtPersistence restore 腿 / SidecarV5 writeLeg）= 堆态依赖。
   崩点类隔离全绿（2/0/0、7/0/0、11/0/0）+ App 全量独立轮复绿（630/0/0，210s）。
2. **环境协同因子**：Data 卷 98% 满（4.3GB free）+ Metal shader cache
   `MDB_MAP_FULL` 风暴 + 当日全量重编译风暴；处置 = 盘/缓存卫生（清 Instruments
   ktrace 残留 3.7GB + 测试残留 + 陈旧 DerivedData 容器 1.7GB + Metal cache 重建；
   Data 卷 → 11GB free）+ 缓存回填 → 第 3 试干净轮落地。
3. **产线零 diff 亲证**：9586c1b..HEAD IOP/Core 零命中（唯一 App diff = WorkspaceHostView
   DEBUG probe guard）——崩溃家族为**潜伏旧账非 M2-11 新回归**；**FINDING 登记**
   （error 级，零当场修），归属（验收批 fix 或 V2）= orchestrator 裁决点，随签核面
   呈报。GOAL-STATE Flaky 清算台账已追加两行（家族 + SidecarV5 第 6/7 波）。

## 三、GUI 验收轮一轮四义（T3）

（T3 执行后补齐：四义证据/补测/Manual-Only 登记 + FINDING + O-1/O-2 观察行。）

## 四、M2PERF-01 SC 对账表 + 挂账总汇编 + 签核路径（T4）

（T4 落盘后补齐。）
