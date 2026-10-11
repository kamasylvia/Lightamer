# M5-2-01 SUMMARY — Mertens 融合 Core 底座批（wave 1 执行批，2026-10-13 收口）

> 执行 subagent worker。plan 正本 = `M5-2-01-PLAN.md`；裁决记录 = 
> `M5-2-CONTEXT.md`（OQ-1..7 全 A，2026-10-11 用户回批）；checker = 
> `M5-2-CHECKER.md`（PASS / 0E+5M，5 minor 同批采纳）；数学/实测带正本 =
> `M5-2-01-DECISIONS.md`（§1-§10）。

## §0 任务表（commit SHA）

| 任务 | 内容 | commit |
|---|---|---|
| T1 | MertensFusion.swift 纯函数族（display 编码/三因子权重/分位映射/deghost 掩码/置换 LUT/fuseStrip/fuse/adaptiveLevels/haloRows/Float64 孪生）+ MertensFusionTests 13 法 + Project.swift/BUNDLE-MAP 登记 | `075114a` |
| T3 | ExifPrecheck.mertensVerdicts 免 EV 预检（零拒绝面 + EV 只组不消费）——commit 序先于 T2（可编译提交纪律，DECISIONS §2） | `fc66033` |
| T2 | MergeKind.hdrMertens + 四 switch 补臂 + runMertensLeg typed stub + MergeParams 双 optional + ProvenanceReplay 镜像/常量 + MertensMergeKindTests 14 法 + MertensProvenanceTests 5 法 | `288467a` |
| T4 | MertensFusionGoldenTests 7 法（G1/G2/G3①②③④ 含负门） | `a141814` |
| T5 | 收口（本批：SUMMARY/DECISIONS/GOAL-STATE/TODO） | 本 commit |

5 commits 未 push（基线 `d9f0957`，全程 L041 tuist generate 恒为批末动作 +
L075 build-for-testing 先于每轮 test-direct）。

## §1 交付面 vs plan AC 总表

| AC | 生效值 | 证据 | 状态 |
|---|---|---|---|
| 1 OQ-1 自实现 | 纯 Swift + MIT 注记；`git grep -i opencv LightamerCore/ App/` 零命中；Project.swift dependencies 块 0 diff（`git diff 1d1f438 -- Project.swift \| grep -c '^[+-].*\.package'` = 0）；零新 `.metal`（`git diff 1d1f438 --name-only \| grep -c '.metal$'` = 0） | T1/T5 | ✅ |
| 2 OQ-3 deghost 四态 | off/low/medium/high 档表三行 golden + `resolved(from:)` nil/未知→medium + 零 App 文件（本批结构自证：diff 只触 Core Stack/ + 测试 + 账面） | T1/T2 | ✅ |
| 3 OQ-5 免 EV | `mertensVerdicts` 零拒绝面全表（同曝光合法/aperture/ISO warning/缺 metadata 0 占位/EV 组成表）+ 严格版 `precheck` 对照负测（同输入 strict 拒 / mertens 收） | T3 | ✅ |
| 4 OQ-6 数学面 | `DrtEotfMath.srgbPiecewise`（类型名勘误 DECISIONS §7）+ `adaptiveLevels` 真值表（六行 + 边界）+ `haloRows = max(32, 2^L)`（32@5 = defaultHaloRows 精确锚）+ clamp [0,1] 域约定（曲线自带） | T1 | ✅ |
| 5 G1 | 双路径双跑逐字节相等 | T4 | ✅ |
| 6 G2 | p99.9 钉门 1e-6（实测 6.95e-7；硬上限 1e-5 在册；DECISIONS §3） | T4 | ✅ |
| 7 G3 | 四靶全绿（③占比 = 0.0 ≤5%；④带内行逐位 + 负门；①worst 8.9e-8 ≤1e-6；②mask ≈1.0 + 置换 worst 1.8e-7） | T4 | ✅ |
| 8 G5 | 三 bundle 定向轮零失败 + 五既有 kind 快照负测 + 旧 sidecar/params 逐字节零漂移 golden JSON | T2/T5 | ✅ |
| 9 进度恒式 | stepTotal(.hdrMertens) = 4N+3；N=3 合成腿 done == total == 15 精确闭合；08-3 观察项挂账（DECISIONS §1/§10） | T2 | ✅ |

零 diff 红线自证（对 M5-1 终点 `1d1f438`）：`LightamerIOP/` +
`LightamerCore/Sources/Sidecar/` + `Pipe/History/` + `Graph/` = **0 行 diff**；
`*.metal` = **0 文件**；Robertson02 腿体（runHDRLeg）逐字节未动（diff 只触
MergeKind/params/stepTotal/defaultTag/dispatch 补臂 + 新 stub 函数）；ExportQueue/
六格式矩阵/sidecar schema 零触。

## §2 测试数字 vs 基线 3477

- 三定向 bundle（`--bundle` 直启轮，caffeinate -dis，L075 重建后跑）：
  **IOP 590/1/0**（基线 563 + 27 = 13+14 逐位）/**IOPParity 451/3/0**（444+7）/
  **Library 631/4/0**（626+5）；skip 计数与 M5-1 终验逐位一致（1/3/4），
  失败零，零 MEMFAIL（IOP 7202MB / IOPParity 6974MB / Library 615MB，8G 门内）。
- 本批净增 **+39 法**（plan 估 +42..52——AC 全覆盖收敛后的自然落点，每 AC
  ≥1 法无缺项；DECISIONS §9）；全局账面 3477 → 3516（待 M5-2 收口轮全套
  `--all` 批准时制亲证，本 plan 不申请）。
- 全套 `--all` 未跑（批准制未申请，plan 纪律节原文）。

## §3 数学证据（正本 = DECISIONS §3-§7）

- G2 孪生 parity：p99.9 = 6.954681426845722e-07 → 钉 1e-6（KD-7 数量级取整
  程序）；max 尾 1.09e-5 print-only。
- G3① 双帧恒等：worst 8.94e-08（带 ≤1e-6，非逐位——per-level 除法舍入，
  plan「预期逐位」实测否，DECISIONS §4）。
- G3③ 占比门：过曝块权重占比 **0.0**（C·S·E 完整权重下 flat 块双因子真零，
  checker O3 两因子并写落实）——比 ≤5% 门更强；KD-7③ 修正（高斯无真零点）
  以 E(1.0)³ = 8.48e-5 专测钉死。
- G3④ halo：带内行 vs 整帧**逐位相等**（levels 5，halo 32 = defaultHaloRows
  锚）+ 负门（halo 16 沾污近边行，门可证伪）；网格对齐前提（strip 起点
  整除 2^(L−1)）= 02 band driver 继承约束（DECISIONS §6）。
- G3② 机制发现：白噪声平移保直方图 + σ1.2 模糊压残差（max 0.101 < 0.12）
  → mask 零命中是**检测器设计**非缺陷；修正靶 = 连贯暗物体平移（mask
  ≈1.0、置换 worst 1.8e-7）；G6 走查样张形态挂账（DECISIONS §5/§10）。

## §4 偏差与发现汇总

1. T3 commit 先于 T2（可编译提交，DECISIONS §2）。
2. `DrtEotfMath` 类型名勘误（plan/checker 写 `DrtEotf.`，宿主实为 DrtEotfMath
   enum——DrtEotf.swift :76；语义/文件位一致）。
3. plan T1「真值表八行」系笔误（KD-2 六行 + 边界两行落测，checker M4）。
4. 基线勘误链 +31→+32（checker M3，plan 文件不回改，本批账面勘误）。
5. Lumen merge.py:146 全格兜底已移植（checker M1）+ gray/std 常数钉死
   （checker M2）。
6. sRGB 结点发丝带 ~1.5e-6（IEC 常数舍入伪影，测度零，专测记录 ≤3e-6）。
7. O1 五 kind 共性 decode N 超步——头注 + commit body 落字，修复批另案。

## §5 bundle 分账（BUNDLE-MAP 增行随各自 commit）

```
IOP   13  MertensFusionTests.swift        (T1 075114a)
IOP   14  MertensMergeKindTests.swift     (T2 288467a)
IOPP   7  MertensFusionGoldenTests.swift  (T4 a141814)
LIB    5  MertensProvenanceTests.swift    (T2 288467a)
```

## §6 移交（M5-2-02 待启）

- 生产腿 = `runMertensLeg` typed stub 原位换体（dispatch 零二次编辑）；
  band-outer + halo 流式须落 band 网格对齐（DECISIONS §6）；deghost in-pass
  置换消费 `substituteLUTs`（内含 merge.py:146 兜底）。
- UI 两入口 + zh 键族 + sRGB-tag 落盘域判别 + perf 探针 + G4（Lumen 结构
  对照非门值）+ G6 走查（样张形态按 DECISIONS §5）。
- 双重验收：`M5-2-01-ACCEPTANCE.md` 由验收波落盘（zcode PASS → 串行 omp，
  严禁并发）；本批不预写。
- GOAL-STATE 续接点已更新（M5-2-01 执行批行）。
