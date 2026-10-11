# M5-2-02 SUMMARY — Mertens 生产腿与 UI 收口批（wave 2 执行批，2026-10-14 收口）

> 执行 subagent worker。plan 正本 = `M5-2-02-PLAN.md`；checker 回注 =
> `M5-2-CHECKER.md`（5 minor——M1/M2 01 已落 02 继承，M5 = DECISIONS §1
> 注记处置）；执行裁决 = `M5-2-02-DECISIONS.md`（§1-§5）。

## §0 任务表（commit SHA）

| 任务 | 内容 | commit |
|---|---|---|
| T1 | runMertensLeg 生产腿（KD-3 `runMTBAlignment` 行为保持抽取 + StagedSet 掩码/网格行通道 + landStackProduct additive 臂 + 对齐带 + 置换 in-pass + NaN 消毒 + 分离式 dilate）+ MertensLegTests 13 法 + stub 测试退役改写 | `826fa5b` |
| T2 | writeFloatTIFF additive colorSpace + landStackProduct 传递 + MertensLeg sRGB 落地 + MertensRasterDomainTests 5 法（两域判别钉） | `5afa952` |
| T3 | UI 两菜单项 + Mertens 简形 sheet + mertensMergeHandler 三段接线 + 五 zh 键尾块 + MertensMergeUITests 3 法 | `45bcfe4` |
| T4 | MertensFusionPerfProbeTests（EXPORT env 门）+ perf.md 预算账 + G4 Lumen 结构对照 evidence | `e52bd6f` |
| T5 | G6 MANIFEST + 七 bundle 拼表 + VALIDATION + 账面六件（本批） | 本 commit |

5 commits 未 push（基线 `7d9708f`；全程 L041 generate 批末 + L075
build-for-testing 先于每轮 test-direct）。

## §1 交付面 vs plan AC 总表

| AC | 生效值 | 证据 | 状态 |
|---|---|---|---|
| 1 OQ-2 | sRGB-tagged 32f 落地 → 重导入 `.srgbPiecewise`/`.displayReferred` 两域钉绿 + Robertson02 对照钉（Primé → sceneLinear）+ 落地走 `landStackProduct` 单一路径（additive 零漂移负测） | T2 `MertensRasterDomainTests` 5 法 + 端到端 leg 产物重导入法 | ✅ |
| 2 OQ-4 | 两菜单项并存（Robertson02 项零变化断言）+ `_mertens` 分账产物名 + 零自动择优（结构自证：两 seam 独立、无择优代码路径） | T3 `MertensMergeUITests` 3 法 + `defaultTag` 快照（01 已钉） | ✅ |
| 3 OQ-5 | EV 记录进 provenance（verdicts 消费）+ `exposureRatioVerified` 全 true + 同曝光包端到端可合 | T1 happy path（EV 表 [0,−1,−2] 断言 + 全 true + 落地） | ✅ |
| 4 OQ-6 | band-outer halo 流式（`haloRows(L)` 消费）+ staged 磁盘共享掩码 N×16+1 B/px + 100MP×5 ru_maxrss 6248MB < 8G | T1 驱动 + T4 perf.md（runbook 事故链在册） | ✅ |
| 5 G1 腿级 | 合成腿双跑产物 TIFF 字节逐位相等 | `testDoubleRunProductBitIdentity` | ✅ |
| 6 G4 | Lumen 结构对照报告入 evidence（非门值——相关性 0.990/max 0.105/凸包双高，四节形态全一致） | `evidence/lumen-structural-compare/`（report.md + 脚本 + bench 源；证据域不入 git，L073） | ✅ |
| 7 G5 复验 | 既有五 kind + Robertson02 全路径零 diff；`runHDRLeg` 函数体零 diff（git diff 机检仅注释引用）+ 七 bundle 拼表全绿（§3） | 红线机检清单 + 拼表 | ✅ |
| 8 G6 | MANIFEST 行配方在册（双算法各一张 + 三档对比 + 分账核 + 重导入观感） | `.work/gui-acceptance/m5-2/MANIFEST.md`（Manual-Only，执行移交） | ✅（配方在册；证据待回填） |
| 9 键族 | 五 zh 键尾块纯插入 + zh-audit 绿（1643/1882，+5）+ 零动态键 | T3 diff 纯插入验证 + `zh-audit --check` PASS | ✅ |
| 10 进度恒式 | `done == total == 4N+3`（tier off 同值——精确闭合测试双档跑） | `testProgressConstantDoneEqualsTotalThroughRealLeg` | ✅ |

**零 diff 红线自证**（对 `7d9708f`）：`HDRMergeMath.swift` /
`ExifPrecheck.swift` / `Sidecar/` / `Pipe/History/` / `Graph/` /
`LightamerIOP/` = **0 行 diff**；`*.metal` = **0 文件**；`Project.swift`
dependencies = 0 diff；`runHDRLeg` 函数体零 diff（git diff 仅注释引用）；
StackMergeService removed-lines 审计 = 仅 stub 体/对齐段 refactor 迁移注释
/landStackProduct 签名行（全部本批任务域内）。

## §2 测试数字 vs 基线

- **七 bundle 定向拼表（分割重跑口径，L075 重建后逐 bundle）**：
  **IOP 608/1/0**（7657MB）/ **IOPParity 451/3/0**（7738MB）/
  **Layers 466/4/0**（1178MB）/ **Library 631/4/0**（617MB）/
  **Sessions 279/4/0**（1625MB）/ **Export 351/2/0**（6443MB）/
  **App 752/4/0**（2832MB）= **TOTAL 3538 / 22 / 0**，零 MEMFAIL。
- 对账链：3477（M5-1 终验）+ 39（M5-2-01）+ 22（本批 13+5+3+1）=
  **3538 逐位闭合**；skip 21+1（probe env 门）= 22。
- 全套单命令 `--all` 未跑（批准制；本批以七定向轮拼表，M5-1 分割重跑
  先例口径——VALIDATION 基线同口径）。

## §3 bundle 分账（BUNDLE-MAP 增行随各自 commit）

```
IOP     13  MertensLegTests.swift           (T1 826fa5b)
IOP      5  MertensRasterDomainTests.swift  (T2 5afa952)
APP      3  MertensMergeUITests.swift       (T3 45bcfe4)
EXPORT   1  MertensFusionPerfProbeTests.swift (T4 e52bd6f)
```

## §4 偏差与发现汇总（正本 = DECISIONS §2-§4）

1. 掩码 = **共享单通道**（merge.py 并集语义逐项核对；KD-1 草图 per-source
   形修正）+ `readMaskBand`（无 shift）——DECISIONS §2.1。
2. LUT 估计 = staged **网格行读回**（等价测试钉整帧面）；分离式 dilate
   （逐位恒等钉死）；NaN→0（E³≈8.5e-5 自然权）；带网格对齐约束兑现
   （驱动级多 band 逐位测试）——DECISIONS §2.2-2.5。
3. plan 外两文件（ContentView 穿线 + 01 stub 测试退役改写）+ landStack
   双加参（version/colorSpace）——DECISIONS §3。
4. 探针三起事故全环境/探针侧（staged 脏页压力 / defer 不跑残留 ENOSPC /
   Release 动态 WebP 链接不对称）——perf.md §事故 + LESSONS L076。
5. 预算终值：融合核 **172.24s**（100MP×5 `-O` 口径）= 预算内零 GPU 化
   触发；staged 写 4.73s；驻留恒 ~2.9GB。

## §5 移交

- **G6 Manual-Only 行** = `.work/gui-acceptance/m5-2/MANIFEST.md`（样张
  形态遵 01 DECISIONS §5：连贯物体靶）——用户/orchestrator 安排执行，
  证据回填 ACCEPTANCE。
- **双重验收**（dual_acceptance）：zcode 独立验收 PASS → 串行 omp 二次
  验收（computer-use 走查 UI 面 + 抽测）→ 结论落
  `M5-2-02-ACCEPTANCE.md`；本批不预写。
- **VALIDATION** = C 档第 3 停（phase 签核面）——`M5-2-VALIDATION.md`
  已成文（本批），结论给用户过目。
- **M5-4 收口交接**：M5-4 = VALIDATION 汇总 + **瘦身手术第二次触发**
  （SPEC 正本：strip 集按 SPEC 重算非空才动手）。M5-2 phase 全量证据链
  （01/02 SUMMARY+DECISIONS + perf.md + G4 evidence + G6 MANIFEST）
  就绪待 M5-4 汇总。
