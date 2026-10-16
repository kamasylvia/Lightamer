# M7-2-01 SUMMARY — MCP O1 三工具执行摘要（2026-10-16 夜间批）

> 执行序 T1→T2→T3→T4→T5→T6 全部完成；裁决正本 `M7-2-CONTEXT.md`
> （D-M7-2-1..9 零重开）；裁定记录 = 同目录 `M7-2-01-DECISIONS.md`。

## 交付面

- **三工具**：`search_photos`（EXIF 两段 keyset / CLIP top-K 256 / 全文
  bm25 top-K 500，全只读）+ `get_history`（sidecar 只读投影 + versions
  meta + includeParams + F-5 截断语义）+ `get_state`（六字段组一次性
  快照）。全 `readOnlyHint: true`，注册缺省 writer 要求（grep 机检
  `requiresWriter` 零命中 / `readOnlyHint: true` 恰 ×3）。
- **registry**：`McpToolError` 15→16（`modelUnavailable` additive，两
  switch 补臂）；`makeRegistry` 第三参 `searchState:`（缺省 nil = 既有
  20 面零 diff 负测钉死）。
- **宿主缝**：四缝 additive 透传 + EmbeddedState 第五缝（F-4①——off→on
  toggle 不再静默缺席）；GUI 装配（MainActor hop 内组装五面 liveState +
  embeddedWriteCallCount 同源）；无头臂 headlessProjectStore 载体直携
  （semantic/semanticStore/fulltext open 包派生）。
- **只读臂（T4）**：heldByOther 臂 `openReadOnly()` 服务读面（锁免/
  schema 守卫/写断路器原样；失败 nil seam + log 禁 exit）；F-2 甲判据
  通道落地（DEBUG 域 `mcp-endpoint-readonly.json` 独立文件）；两进程
  测试过线亲调工具成功。
- **xcstrings**：三新键尾块纯插入；zh-audit --check + --self-test 双 PASS。

## 验收形态（ROADMAP §M7-2 三条）

1. **parity golden ✓**：EXIF 臂工具 cursor 链走 ≡ GUI 两段走法直调拼接
   （rating ASC + captureDate DESC 两向；NULL-key 行经翻段可达断言 +
   翻段链路断言 + parse/首页直调恒等）；CLIP mock hit 序/score 投影恒等
   （limit 切片含）；全文 ≡ `AIDescriptionService.imageIDs` rank 序恒等。
2. **快照同批 ✓**：域快照新层（3 工具 verbatim + 只读面）+ union 显式改
   20→23 全点位（DECISIONS §1 逐点申报）。
3. **既有 20 工具零回归 ✓**：editing/culling 两层快照文件零 diff；
   `--bundle App` 844/4/0 全绿（含 McpHostTests / McpEditingToolsetTests /
   McpCullingToolsetTests / McpProjectArbitrationTests 序列 A/B 全绿）。

## 测试与全套对账

- 新测试 = **+17**（`McpSearchStateToolsetTests`，BUNDLE-MAP APP 域一行；
  Project.swift 恰一行 + tuist generate 恒末位 L041）。
- **全套 --all 终值（2026-10-16 23:19 实测，exit 0 / 零 MEMFAIL）**：
  - `TOTAL|3877/35/0|`（3860 基线 + ΔN 17；**对账精确闭合**）。
  - 七 bundle 逐行：IOP 687/5/0（7541MB）/ IOPParity 460/3/0（8112MB，
    8G 门内贴线——SPIKE 注记的已知贴线 bundle，无 MEMFAIL）/ Layers
    494/5/0（808MB）/ Library 729/4/0（623MB）/ Sessions 284/9/0
    （1666MB）/ Export 379/5/0（6508MB）/ App 844/4/0（2832MB）。
  - **skip 35 构成声明**：IOP 5 + IOPParity 3 + Layers 5 + Library 4 +
    Sessions 9 + Export 5 + App 4 = 35——全部为既有 perf-probe（
    `LIGHTAMER_PERF_PROBE=1` env 门）与环境门 skip，零静默吸收。
- 定向轮：`--bundle App` = 844/4/0（peak RSS 2832MB，8G 门内；MEMFAIL 零）。

## 挂账（→ 后续 plan / 用户过目）

- **auto 分类器后置**（D-M7-2-2 裁决内挂账）：mode 显式三枚举，auto 不入
  v1。
- **cursor 跨调用稳定性**：与 list_photos 同口径的已知边界（不引入版本戳）。
- **GUI workspace 面字段 null**（DECISIONS §2.8）：per-window
  LibraryPhaseState 自 app 级装配点不可达——真值须新汇集缝（M7 站后续
  裁量）。
- **CLIP 10s 贴线**：万级库实测超时才申报升 20s 档（本波零实测，未预设）。
- **match_color provider projectDirectory 语义**：match_color 自身 provider
  仍传文件 URL（其 golden 行走 absolute kind 未爆）——若后续 M7 计划触
  match_color 库域面，顺路勘正为目录锚（本波零触其文件）。

## 快照串行交接

本波 union 改动权已用讫（20→23）。**M7-3（list_versions 等工具）/
M7-5 接棒时继续显式改本文件（McpFinalSnapshotTests.swift），串行波序，
禁并行派发**（orchestrator 编排保证）。

## 执行批事实

- executor：ZCode subagent（夜间全自动授权，先例 D-07-3-T5-1）。
- commit 链：`9f69775b`（T1）→ `5a89f07f`（T2）→ `028c6230`（T3）→
  `9efbd976`（T4）→ `20997721`（fix 回注）→ `32055308`（T5）→ 本收口批
  （T6 docs）。
- 红线族机检：全 PASS（DECISIONS §1 + T6 收口批对账段——零新 SPM /
  `.metal` 零 diff / 封存面 17 件零 diff / 既有 20 工具面零 diff /
  xcstrings 纯插入 / UserDefaults 零新键 / runModal 零命中 / 插值禁形
  零命中 / F-6 grep 零命中 / Project.swift + BUNDLE-MAP 恰一行）。
- **ACCEPTANCE 不写**（orchestrator 指定——验收批另派）。
