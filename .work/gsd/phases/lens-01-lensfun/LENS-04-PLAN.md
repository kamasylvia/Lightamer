---
phase: lens-01-lensfun
plan: "LENS-04"
title: "plan L4 — 系数快照持久化 + process version 裁决 + 测试收口 + perf probe（T1 LensCoefficientSnapshot 快照 + Re-match / T2 process version 裁决〔消费 02/03 全部语义变更〕/ T3 缓存隔离回归 / T4 golden 收口 + RawLab 抽查对账 / T5 100MP perf probe / T6 收口与全批 ΔN 总账）"
wave: 3
depends_on: ["LENS-02"]
autonomous: true
requirements: ["charter = UQ-R4（8bd94370）——渲染确定性收口波（H-L2 根治）+ 全批验收面", "research 正本 = phases/lens-01-lensfun/RESEARCH.md（b2b31909）§Persistence/§Test Strategy/§Plan Split L4 行", "OQ 裁决正本 = 同目录 CONTEXT.md（D-LENS-3 + X3 + hazards H-L1/H-L2 + 红线 15 条）", "基线 3991/37/0 + LENS-01/02 终态（对账式）；本 plan 分账 +12..16", "并行注记 = 与 LENS-03 并行（T1/T3/T4 可先行）；T2 process version 裁决消费 LENS-02/03 全部语义变更 = 03 闭环后串行垫底；C 档停 = 两 plan 各自闭环后一并汇报停", "全套 --all 对账轮归本 plan 收口（orchestrator 批准制 + 8G 门 + MEMFAIL 机检）"]
success_criteria: "SC 全可机检——T1：LensCoefficientSnapshot（15 系数 + profile id + score + dbTag）Params additive + 写入点恰二处（auto-apply 命中/browser 选型——面板 Apply 已于 LENS-02 T4 退役 (review M1)）+ 消费序（snapshot 在先零 DB 依赖；nil = live resolve legacy 恒等）+ Re-match 动作（失效→重匹配→新快照单 commit）+ dbTag strip-on-hash 不折 paramsHash 断言 (review m2) + 零漂移负测；T2：process version 裁决 = 02/03 全部语义变更逐项过 bump 纪律三问（**七项含 LENS-01 匹配硬化对 legacy `.lensfun` 档 (review M3)**；预期默认中性 = 不 bump；任何默认观感漂移 = bump v2 + 新旧 golden 对）——裁决表 + 证据落 DECISIONS；T3：lens on/off 缓存隔离回归（paramsHash 变化 → pipe cache miss，RawLab 教训移植）；T4：golden 收口（projection/scale 归 IOPParity 总账）+ RawLab 无头渲染抽样对账（非 CI 门，抽查形态，evidence 落档）；T5：100MP perf probe（LIGHTAMER_PERF_PROBE + queue fence；lens 全平面单帧耗时 + memo 前后对比；budget 带 = ashift/flip warp 族实测锚定带值，登记绝对 ms + 相对倍率 (review m9)）+ 全套 --all 对账轮（批准制）"
estimated_tests: "+12..16（T1 +5..7 / T2 +2..4〔默认中性 golden 对〕/ T3 +1..2 / T4 +2..3〔抽查对账 fixtures 级〕/ T5 0〔probe 族 skip-gated〕；越带申报理由；skip 增量逐族申报）"
test_bundles: [IOP, IOPParity]
baseline: "3991/37/0 + LENS-01/02 终态（对账式）"
expected_all: "全批终值带 = 3991 + 59..88 = 4050..4079（LENS-01 +13..18〔B1 下修〕/ LENS-02 +18..28 / LENS-03 +16..26 / LENS-04 +12..16；本 plan 收口轮跑全套 --all 对账：exit 0 零 MEMFAIL 七 bundle 8G 门内，skip 增量 = probe 族申报）"
red_lines:
  - "共用红线正本 = CONTEXT §四 plan 红线 front-matter 15 条；本 plan 特别面 = LightamerSidecar 零 diff（快照骑 paramsData，schema 零 bump——CONTEXT 勘误① v11 现行）；RenderProcess 触碰限于 T2 裁决臂（bump 与否的编译面——预期零改）。"
  - "H-L2 硬门：快照落地后渲染与 DB 版本解耦——DB 更新不得改变任何已快照文档渲染（T1 消费序测试钉死）；legacy 档（snapshot nil）live resolve 行为逐字节不变。"
  - "T2 裁决纪律（RenderProcess bump 纪律三问逐项过）：①look-changing = bump + 新旧 golden 对；②非 look 重构 = 禁 bump；③crash 修复 = 原位修。预期默认中性不 bump——发现任何默认观感漂移 = 停手上报 orchestrator 裁决，禁静默 bump 或静默不 bump。"
  - "perf probe 纪律（红线 8）：LIGHTAMER_PERF_PROBE=1 + XCTSkipUnless + queue fence（L014——无 fence 计时 = 假数）；probe 族 = skip 增量申报唯一来源。"
  - "--all 批准制（红线 9）：orchestrator 批准 + caffeinate -dis + 8G 门 + MEMFAIL 机检 + parentage 核验；三轮同值复证（M7-3 三方同值先例）。"
files_modified:
  - LightamerIOP/Sources/Lens/LensfunMatch.swift              # T1：LensCoefficientSnapshot 结构 + 快照 bake/消费序 + Re-match 面
  - LightamerIOP/Sources/Lens/LensModule.swift                # T1：Params.snapshot additive + resolveUniforms 消费序 + T2 裁决臂（如有）
  - App/Sources/Lightamer/UI/Inspector/LensPanelView.swift    # T1：Re-match 按钮 + 快照状态 readout（§1/§4 尾）
  - Resources/Localizable.xcstrings                           # T1：re-match/快照 readout 新键尾块纯插入
  - Tests/LightamerTests/LensSnapshotTests.swift              # T1：新建（IOP——round-trip/消费序/零漂移/dbTag）
  - Tests/LightamerTests/LensCacheIsolationTests.swift        # T3：新建（IOP——on/off 缓存隔离）
  - Tests/LightamerTests/LensDefaultNeutralGoldenTests.swift  # T2：新建（IOPParity——默认中性 golden 对）
  - Tests/LightamerTests/LensPerfProbeTests.swift             # T5：新建（IOPParity——skip-gated probe 族）
  - Project.swift                                             # T6：四个新测试文件入数组
  - .work/gsd/phases/m2-4-0-test-bundles/M2-4-0-BUNDLE-MAP.txt  # T6：四个新测试文件落域登记行 (review m4)
  - .work/gsd/phases/lens-01-lensfun/LENS-04-SUMMARY.md       # T6（含全批 ΔN 总账 + --all 对账表）
  - .work/gsd/phases/lens-01-lensfun/LENS-04-DECISIONS.md     # T6（process version 裁决表 + 对账数值来源 + 偏差）
---

# Plan LENS-04 — plan L4：系数快照 + process version 裁决 + 测试收口 + perf probe

> **裁决正本** = `CONTEXT.md`（D-LENS-3 + X3 + H-L1/H-L2）；规格正本 =
> `RESEARCH.md`（§Persistence / §Test Strategy / §Plan Split L4 行「与
> L2/L3 的语义变更合并裁决 bump」）。
>
> **并行注记**：T1/T3/T4 与 LENS-03 并行可先行（触碰面 = params 持久化
> + 测试，与 03 的 kernel/分发面不相交）；**T2 = 全批语义变更合并裁决，
> 必须在 LENS-03 闭环后执行**（消费 02 的 scale/toggle 与 03 的投影全部
> 默认中性证据）；T5 全套 --all 对账轮 = 全批收口动作（批准制）。
>
> **裁定权归属钉**：T2 裁决形态 CONTEXT 已钉（预期不 bump），但「发现
> 默认观感漂移」= 停手上报 orchestrator（禁静默 bump/禁静默不 bump）；
> 其余无用户裁决分支。
>
> **执行序**：T1 → T3 → T4（并行段）→〔LENS-03 闭环〕→ T2 → T5 → T6。

## ΔN 预算表（逐任务，LENS-04 分账带 +12..16；越带须申报理由）

| 任务 | 测试增量 | 构成 | 落点 |
|---|---|---|---|
| T1 快照 | **+5..7** | round-trip + 消费序 + 零漂移 + dbTag 不折 hash + Re-match | IOP |
| T2 process 裁决 | **+2..4** | 默认中性 golden 对（lens 默认 off / scale=1 / rectilinear 逐字节） | IOPParity |
| T3 缓存隔离 | **+1..2** | on/off paramsHash → cache miss | IOP |
| T4 golden 收口 + 抽查 | **+2..3** | RawLab 无头抽样对账 fixtures 级（非 CI） | IOPParity |
| T5 perf probe | **0**（skip 族） | probe skip 增量申报（+1..2 skip） | IOPParity |
| T6 收口 | **0** | docs + Project.swift + tuist generate + --all 对账 | — |
| **合计** | **+12..16** | 全批总账 4050..4079（B1 下修后——CONTEXT 勘误③） | 四新测试文件 |

## 已定裁决（生效值，硬约束，不得重开）

1. **快照制**（D-LENS-3）：匹配期系数快照，渲染与 DB 版本解耦；DB 更新
   = 显式 Re-match 才生效。
2. **消费序**：`source == .lensfun && snapshot != nil` → 快照直用；
   snapshot nil → live resolve（legacy 恒等）。
3. **dbTag = 审计字段不折 paramsHash**（X3——strip-on-hash 机制钉死
   (review m2)：stableHash 输入 = snapshot 剥 dbTag 编码）。
4. **T2 预期 = 不 bump**（02/03 全部增量默认中性）；漂移 = 停手上报。
5. **L1 memo 保持**（LENS-01 T4）——快照与 memo 并存（快照命中零 memo
   查询；miss 才走 memo/live 路径）。

## read_first（全局，每任务开工前过一遍）

- `.work/gsd/phases/lens-01-lensfun/CONTEXT.md`（D-LENS-3 + X3 + hazards
  + 红线 15 条 + 勘误①②）
- `.work/gsd/phases/lens-01-lensfun/RESEARCH.md` §Persistence /
  §Test Strategy / §Plan Split L4 行
- `.work/gsd/phases/lens-01-lensfun/{LENS-02,LENS-03}-SUMMARY.md`（T2 裁
  决输入——02/03 语义变更清单）
- `RenderProcess.swift:25-126`（bump 纪律全文 + ledger 形态 + M6-2 语义）
- RawLab 缓存键教训（`reviews/self-lens-correction-20261013-1018.md`）
  + RawLab 无头渲染面（T4 抽查通道——CLI/配方面可无头渲染）
- `.work/LESSONS.md` L014（fence）+ L041 + AGENTS.md 资源监控节（--all
  批准制 + 8G 门）+ M3-3 节（L048 比较空间纪律：decode 回 linear + f32
  产线常数）

---

## T1 — 系数快照持久化（D-LENS-3，X3；H-L2 根治）

> 现状系数在 process 期按当前 DB 实时解析——DB 更新静默改写全部旧档渲
> 染（RESEARCH §Persistence 判定 + 亲核吻合）。

**read_first**：`RESEARCH.md` §Persistence 快照节；CONTEXT §X3 全节；
`LensfunMatch.swift:51-82`（LensKernelParams 15 系数——快照内容源）+
`:405-428`（resolveCommitted——bake 源）；M3-1-01 hash 零漂移先例
（AGENTS.md M3-1 节）；`LensPanelView` §1/§4（Re-match 落点）。

- **action**：
  1. `LensCoefficientSnapshot`（IOP Lens 域，Codable/Hashable/Sendable）
     ：15 系数 Float + profileMaker/profileModel/profileMount: String? +
     profileCrop: Float? + matchScore: Int? + dbTag: String?（SHA 前 16
     hex，LENS-03 T3 dbTag 读出面消费）。
  2. `Params` additive `snapshot: LensCoefficientSnapshot?`（默认 nil，
     encodeIfPresent）；零漂移专测随批。
  3. bake 写入点恰二处 ((review M1)——面板 Apply 已于 LENS-02 T4 退役，
     「三处」为退役前口径)：auto-apply 命中（reloadDefaults 后首匹配
     commit——或 reloadDefaults 内同步匹配 + bake，终形 DECISIONS 二选
     一申报）/ browser 选型（含 detected 确认选型——同一 browser 缝）；
     Re-match 按钮 = 失效快照 → 当前 DB 重匹配 → 新快照单 commit（miss
     = 快照清除 + readout miss 态）。
  4. 消费序改造 `resolveUniforms`：snapshot 非 nil 直用（构造 uniforms
     ——centerX/Y 默认折算沿用）；nil → memo/live resolve（legacy 恒
     等）；`dbTag` 不折 paramsHash 断言——机制 = **strip-on-hash**
     （stableHash 输入 = snapshot 剥 dbTag 编码；同 params 改 dbTag →
     hash 不变，X3 测试钉死；生产路径 dbTag 仅 Re-match〔本身即新
     commit〕变 = 防御性断言 (review m2)）。
  5. 测试：round-trip（bake → params JSON → decode → uniforms 恒等）+
     消费序双臂（snapshot 在先零 DB 依赖——uninstall DB 后渲染不变断
     言；nil → live 路径旧行为恒等）+ 零漂移负测 + Re-match 流转 +
     dbTag strip-on-hash 不折 hash。
- **验收标准（机检）**：
  - 构建绿；默认 params encode == 旧 JSON 逐字节（零漂移专测）。
  - 消费序测试在册（uninstall-DB 后已快照文档渲染逐字节不变 = H-L2 钉
    死门）。
  - grep：bake 写入点恰二处（auto-apply 命中/browser 选型 (review M1)
    ——Apply 旧 action 零残留）；Re-match 恰一入口。
  - 既有 LensMatchHardeningTests/LensfunDBTests 零回归。
- **commit**: `feat(lens04): persist resolved lensfun coefficients in params snapshot`
- **回滚与偏差申报要求**：回滚 = revert 单 commit（回 live resolve 态
  ——H-L2 复活，无新回归）；偏差（bake 时机/Re-match 形态）= DECISIONS
  申报；**禁折 dbTag 进 paramsHash**（X3）；**禁在快照外仍保留第二系数
  持久面**（单源）；**禁动 LightamerSidecar**（快照骑 paramsData）。

## T3 — 缓存隔离回归（RawLab 教训移植）

> RawLab：lens 配置必须进缓存键（file-identity-only 键在 lens on/off 间
> 串值）——我方 paramsHash 折 params 变化，理论天然覆盖，补回归钉死。

**read_first**：RawLab `reviews/self-lens-correction-20261013-1018.md`
（教训正本）；`PipeCacheKey.swift:11,:49,:197-207`（paramsHash 折叠面）
；RESEARCH §Test Strategy 新增⑤。

- **action**：回归测试——同文档 lens on/off（commit 变更 params）→
  paramsHash 变化 → pipe cache miss（无 stale 纹理断言）；lens 滑杆微
  调同理；负例（无关 iop 变化不动 lens 缓存语义照旧）。
- **验收标准（机检）**：构建绿；隔离测试在册且含 on/off 与微调双例；
  `--bundle IOP` 零回归。
- **commit**: `test(lens04): pin lens on-off cache isolation via params hash`
- **回滚与偏差申报要求**：回滚 = revert 单 commit；发现隔离实际缺失 =
  **停手上报**（PipeCacheKey 属折叠面纪律域，禁顺手改键——M6-2 KD-6
  fork-point 契约）。

## T4 — golden 收口 + RawLab 抽查对账（非 CI 门）

**read_first**：RESEARCH §Test Strategy 跨实现对账节；CONTEXT §X8（GPL
对表合法化）；`LensParityTests.swift:14-27`（合成参考既定形态）；RawLab
无头渲染面（CLI/配方面）；M3-3 节 L048 比较空间纪律。

- **action**：
  1. golden 总账核验：projection（L3）/scale（L2）/warp/TCA/渐晕（04-04
     既有）golden 全在册且门值一致（1e-5 warp 级）——缺漏补齐。
  2. RawLab 抽查对账：选 2-3 个 fixtures 级合成/真实例 → RawLab 无头渲
     染同参参考帧 → 抽样比对（容忍带按插值/解码差异宽定，机制注记非门
     ）；evidence（命令 + 数值 + 差异注记）落 `.work/gsd/phases/
     lens-01-lensfun/evidence/rawlab-sampling/`；非 CI 门（跨仓路径不可
     CI 依赖——注释钉死）。**独立性边界注记 (review m8)**：projection/
     scale golden = Alcedo 源转录 CPU 参考 + kernel 同源对表——同笔转
     录的系统性误读会自消，本抽查即唯一真独立对账面；「延后供件」降级
     路径不得用于静默跳过（维持）。
  3. dt 侧维持合成参考（无 lens 腿，既定结论不翻案）。
- **验收标准（机检）**：golden 清单在 SUMMARY 总表；evidence 目录在库
  （命令 + 数值）；比对脚本/fixtures 落 evidence（可复跑）。
- **commit**: `test(lens04): reconcile lens golden ledger with rawlab sampling`
- **回滚与偏差申报要求**：对不上 = 机制注记（插值/解码差异）非放宽门
  ——差异超带 = 停手上报；禁把抽查升格为 CI 门（禁静默）。

## T2 — process version 裁决（02/03 语义变更合并裁决；03 闭环后执行）

> bump 纪律三问（`RenderProcess.swift:25-44`）：①look-changing → bump
> + 新旧 golden 对；②非 look 重构 → 禁 bump；③crash 修复 → 原位修。
> 预期：02（scale 默认 1.0/toggle 默认 on/auto-apply 默认关）+ 03（投影
> 默认 rectilinear/ROI union 边框精度/数据分发）全部默认中性 → **不
> bump**；T1 快照使 legacy 档走 live resolve 旧路径 = 行为不变。

**read_first**：`RenderProcess.swift` 全文（bump 纪律 + ledger + KD-6
fork-point 契约）；LENS-02/03 SUMMARY（语义变更清单 + 各自默认中性证据）
；M6-2 VALIDATION（seam 形态）；CONTEXT D-LENS-3 快照判定第三目。

- **action**：
  1. 交叉收口核验（M5）：核 LENS-03 T1 投影已折入 LENS-02 建的
     auto-crop 边框映射与 resolved-scale readout（并行波交叉点——未折
     入 = 停回 LENS-03 T1 补线，禁带缺口裁决 (review M5/评审 §7)）。
  2. 语义变更逐项过三问裁决表（scale/toggle/auto-apply/投影/ROI/快照/
     **LENS-01 匹配硬化对 legacy `.lensfun` 档**——七项 × 三问 (review
     M3)；第七项 = LENS-01 T3 硬化改变既有 `source == .lensfun` 文档
     live resolve（snapshot nil 恒走 live，无快照保护）：命中→miss =
     校正静默消失、系数变 = 观感变；预期裁决 = 按缺陷修复原位收（硬化
     即正确行为）+ 登记 + 面板 Re-match 提示；若判 look-change 则按
     bump 纪律全套）——每项裁决 + 证据（默认参数恒等 golden 指针）落
     DECISIONS。
  3. 默认中性 golden 对（IOPParity）：lens 默认 off 文档 + scale=1 +
     rectilinear 全链渲染逐字节对照（批前批后同 fixture）；非 RAW 文档
     零行为（红线 12 终验）。
  4. **发现任何默认观感漂移 = 停手上报 orchestrator**（裁决 bump v2 +
     新旧 golden 对 or 修回中性——禁自裁）。
  5. AGENTS.md「process 账本」行复核（不 bump = 零改；bump = 按纪律四步
     全套）。
- **验收标准（机检）**：裁决表七项在 DECISIONS（含匹配硬化 legacy 档项
  (review M3)）；默认中性 golden 对在册且逐字节相等；
  `RenderProcess.swift` 预期零 diff（不 bump 结论的机检面——有 diff =
  裁决翻转，须 orchestrator 记录在案）。
- **commit**: `test(lens04): adjudicate process version neutrality for lens batch`
- **回滚与偏差申报要求**：漂移发现 = 停手上报（禁静默）；bump 翻转 =
  orchestrator 批准记录前置；禁静默不 bump（裁决表缺项 = 流程违规）。

## T5 — 100MP perf probe + 全套 --all 对账轮

**read_first**：RESEARCH §Test Strategy perf 节 + §Geometry Seam tile/
内存节；AGENTS.md M2-5 节（probe 惯例 + fence 红线）+ 资源监控节（8G 门
/parentage/MEMFAIL）；`Scripts/test-direct.sh` 用法（七 bundle）。

- **action**：
  1. `LensPerfProbeTests`（skip-gated）：100MP float32 平面 lens 全平面
     dispatch 单帧耗时（全开 + 投影 fisheye 重例）+ memo 前后对比（
     LENS-01 T4 收益实证）；queue fence 先行（L014）；budget 带 = 以
     04-04/ashift 实测为锚登记**带值**，执行批登记时同时给**绝对 ms 与
     相对倍率**（禁「同阶」事后解释 (review m9)）。
  2. 全套 `--all` 对账轮：orchestrator 批准 → `Scripts/machine-guard.sh`
     过门 → caffeinate -dis + test-direct.sh --all（七 bundle）→ 8G 门
     + MEMFAIL 机检 → **三轮同值**（M7-3 先例）→ 对账表 = 3991 + 01/02
     /03/04 分账精确和。
  3. skip 增量申报（probe 族 +1..2）；任何 MEMFAIL/超门 = 立即 kill 上
     报（禁放行）。
- **验收标准（机检）**：probe 数值 + 命令 + fence 证据落 DECISIONS；
  --all 三轮 `TOTAL|…/…/0|` 同值 + 分账和对账精确；parentage 一行随记
  录。
- **commit**: `test(lens04): run lens perf probe and full-suite reconciliation`
- **回滚与偏差申报要求**：超 budget 带 = 归因（投影重例豁免面单列）+
  DECISIONS 申报（禁静默超带）；--all 异常 = 恢复协议（M2-11 先例）后
  重跑，禁拿残轮对账。

## T6 — 收口（全批 ΔN 总账 + docs）

- **action**：四新测试文件入数组 + BUNDLE-MAP 四行登记 (review m4)；
  `tuist generate` 恒末位；SUMMARY（全批 ΔN 总账 = 01+02+03+04 分账精
  确和 + --all 对账表 + skip 申报）+ DECISIONS（T2 裁决表七项 + probe
  数据〔绝对 ms + 相对倍率 (review m9)〕+ 偏差汇编）；GUI 走查申报（面
  板五段 + browser + detected 确认 + 接力 crop + Re-match——MANIFEST
  形态归验收批，本 plan 记申报行）；**C 档停汇报**（与 LENS-03 一并）。
- **验收标准（机检）**：SUMMARY/DECISIONS 在库；对账精确；BUNDLE-MAP
  登记行在库 (review m4)；xcstrings/zh-audit 双 PASS 留档。
- **commit**: `docs(lens04): close out lens batch with delta-n ledger and adjudication`
- **回滚与偏差申报要求**：ΔN 越带 = SUMMARY 申报；禁漏 tuist generate。

---

## 风险与回退

- **快照 bake 时机歧义**（auto-apply 同步匹配 vs 后置 commit）——二选一
  DECISIONS 申报（同步 = reloadDefaults 变重；后置 = 首帧 identity 一
  瞬——推荐后置，观感代价一帧内）；禁双路径并存。
- **legacy 档行为漂移**：snapshot nil → live resolve 路径必须与 04-04
  现行为逐字节恒等（memo 只是缓存不改变结果）——消费序双臂测试钉死。
- **T2 裁决翻案风险**：02/03 某增量若实测非中性（如 ROI union 改变边界
  像素）——ROI 属边框协商非像素数学，预期中性；golden 对是裁决证据，发
  现漂移即停（裁决权在 orchestrator）。
- **RawLab 抽查环境**：跨仓路径 + 无头渲染依赖 RawLab 本机可用——不可
  用 = evidence 记录环境缺口，抽查降级为「延后供件」申报（禁静默跳过）。
- **--all 轮内存**：IOPParity 峰值贴线（历史 7786-8107MB）——lens 新增
  golden 如推高 = 分 bundle 轮次拆分（BUNDLE-MAP 纪律）+ 申报。

## Checker 关注点（独立反向核输入）

1. **Goal-backward**：RESEARCH 缺口表全表 ↔ 四 plan 映射完备性（本 plan
   收口 = H-L1/H-L2 终账 + 全批验收）；§Persistence 快照推荐 ↔ T1。
2. **OQ 兑现核**：D-LENS-3（T1 消费序 + dbTag strip-on-hash + Re-match
   ）/ X3 五点逐条 / T2 bump 纪律三问表七项（含匹配硬化 legacy 档
   (review M3)）。
3. **红线核**：LightamerSidecar/RenderProcess（预期）零 diff；probe
   fence 证据；--all 三轮同值 + 分账精确和；skip 申报。
4. **SC 可机检性**：uninstall-DB 恒等断言 = H-L2 机检正门；对账表数字
   可复算。
