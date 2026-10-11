# M5-1-03 SUMMARY — TRACK P3：match_color MCP 最小面 + G4 + 五门收口（M5-1 phase 收口批）

> 执行批 2026-10-12（续班 worker：前任 ~10 分钟 API 瞬态亡、零产出，全新开跑；
> 夜间全自动授权在案）。基线 = M5-1-02 修复批后 HEAD `3be69ee`。任务序 T1..T4
> 与 PLAN 一致；**零 Core/IOP diff、零 .metal、零新 SPM、零新网络面**（红线
> 自证见 DECISIONS §12）。

## 0. 提交账

| T | commit | 内容 |
|---|---|---|
| T1 | `e13d750` | feat(mcp): match color tool with per target fan out（工具 + register 一行 + 快照族 19→20 + ToolsetTests 21 法 + xcstrings +1 键 + GUI 装配两行 + Project.swift/BUNDLE-MAP） |
| T2 | `1f4270e` | test(mcp): match color end to end render parity（G4 三法） |
| T3 | `c99e149` | docs(m5-1): five gate ledger with closeout runs（GATE-LEDGER + 收口轮） |
| T4 | `2002779` | docs(m5-1): close track phase with requirements ledger（翻账 + SUMMARY/DECISIONS/GOAL-STATE/TODO） |

## 1. T1 — match_color 工具（KD-1 / OQ-6 生效值）

- **签名**：`match_color(reference, targets?, strength?, solver?, attach?)`——
  五参全落；reference = 库内 id（digits → `LibraryStore.image(id:)` →
  `ImageLinker.resolve` PathKind 0/1/2）或会话 relPath（`resolveMember`，
  load_image 语义同源）；v1 单 reference/调用（裁决字面；多参考 = GUI 面板）。
- **fan-out**：targets 数组 = 逐目标独立求解（共享参考统计，源统计逐图不同——
  解不同是设计语义）；帽 30（get_contact_sheet 先例），超帽 invalidParams 在
  GPU 前置门。缺省 targets = 编辑器当前图（liveImageURL→session relPath 映射）。
- **attach**：true = store 级投影缝落位（`projectColormatch` + SessionBatchApplier
  一次写）+ 返回 `{op, instanceId, params 摘要, solveHash}`；false = 参数组返回
  （键集全部 catalog 内，apply_params 回灌 e2e 钉死）。**事后微调/验收/元数据 =
  既有 apply_params / render_preview / list_iops，零新增面**（机检：`"match_`
  工具名仅 MatchColorToolset 一文件）。
- **确定性披露**：solveHash（共享 solve-cache 键折叠，十进制 L013）随返回——
  同输入同哈希双测钉死（G1 的 agent 面）。
- **render gate**：整调用 `withRenderGate` 串行 + render 档 bounded wait；
  逐目标失败 → errors 数组部分成功形态；硬超时 typed renderTimeout（已完成
  目标落盘真相保留）。
- **快照族 19→20**（checker E3，显式申报面）：四文件计数/表更新 + match_color
  verbatim descriptor 入 frozen 表（all19→all20）+ editing 域快照表加行 +
  白名单负测重形（match_color 移出 not-a-tool 名单）+ descriptionKeys/zh 键。
  明细 = DECISIONS §7。

## 2. T2 — G4 端到端 parity（KD-2 / OQ-8）

- 链路：match_color(attach=true) → apply_params(strength 0.7 微调) →
  render_preview vs 本地同参渲染（同 renderedPlane + JPEG q85）= **byte-identical
  （0 diff）**——SC#3 同型判据原样成立，零容差带（DECISIONS §10）。
- 批量双目标 parity 一条 + 双调用同 solveHash 一条；合成 TIFF fixture（KD-2
  禁真 RAW；测试内生成，确定性解码）。

## 3. T3 — 五门收口（KD-3）

- `M5-1-GATE-LEDGER.md` 五门全表（定义/锚/终值带/落位）——G1/G2/G3/G5 =
  P1/P2 落门 + 收口轮亲验；G4 = 本批落门。
- 收口轮（定向四 bundle，全绿零 MEMFAIL）：Layers **466/4/0**（1153MB）/
  IOPParity **444/3/0**（5836MB）/ App **749/4/0**（2832MB）/ IOP 抽验 **563/1/0**
  （7740MB<8G）。三 bundle 与 M5-1-02 收口值逐位相等（零漂移）。
- 全套 `--all` 终验（批准在案）：**3477/21/0 七 bundle 全绿零 MEMFAIL**（详见 GATE-LEDGER §6——
  含首轮 Library 混态产物 SIGSEGV 中止的诚实记录与分割重跑处置；对账链
  3367+38+47+1+24 = 3477 逐位闭合）。

## 4. T4 — 翻账 + 收口（KD-4）

- REQUIREMENTS：TRACK-01..05 勾选 + 门锚注记；TRACK-03 偏差注记（内嵌 LUT →
  `.cube` 派生资产，checker m7）；MCP-09 研究项 C 兑现注记。**翻账留验收**
  ——终态 Delivered 由 VALIDATION 批盖。
- VALIDATION 输入件清单 = GATE-LEDGER + 三 plan ACCEPTANCE（M5-1-01/02/03）+
  走查配方 `.work/gui-acceptance/m5-1/MANIFEST.md`（Manual-Only 行留 M5-4 人工）。
- 双重验收：本 ACCEPTANCE 面待 orchestrator 派 zcode → 串行 omp（config
  dual_acceptance）。

## 5. 机制发现与申报（明细 = DECISIONS）

1. **apply_params 无法 CREATE colormatch**（M5-1-01 seed ABSENT 密封决策）——
   m4 回灌面 = 两段流：attach=true 建实例 → attach=false 组 apply_params 重
   参数化（E-omp1 同族语义，非缺陷；工具 doc 已写明）。
2. GUI 装配两行 install（LightamerApp，files_modified 申报偏离）+ 两枚 host
   seam box（library provider / colormatch service 共享）。
3. attach=false 也提交 `.cube` 资产（解产物完整性）。
4. solver 拼写二态：MCP 入参 kebab / 返回 params 模块 rawValue。
5. 快照族实际改动面 > plan 行号（域表/负测/descriptionKeys——DECISIONS §7）。
6. 测试 24 法 > plan 估 +10..16（typed 面全覆盖所需）。

## 6. M5-1 phase 小结（三 plan 收口）

- **交付**：TRACK 追色族五需求全兑现 + MCP-09 研究项 C——Oklab 统计域（P1）→
  三档求解器（S1 Gaussian OT 主打 / S3 Reinhard / S2 CDF）→ colormatch op +
  65³ `.cube` 派生资产 + 池化 + GUI 面板（P2）→ match_color MCP 编排皮 +
  五门收口（P3）。
- **五门全绿**：G1 bit-identity / G2 双面 parity 门 / G3 合成对恢复 + 目测行 /
  G4 MCP e2e byte-identical / G5 恒等直通。台账 = `M5-1-GATE-LEDGER.md`。
- **批量**：P1 +38 法 / P2 +47 法 + 修复批 +1 / P3 +24 法；全套终值见
  GATE-LEDGER §6。
- **挂账移交**：①GUI 走查 Manual-Only 行 + bake 生产耗时实测（M5-1-02 §3
  遗留，Release 产物怪癖）→ M5-4 VALIDATION 人工执行；②MCP 多参考 v1 缺口
  （agent 侧真实需求出现再立 V2）+ match_color preset 化（OQ-6 备选 A）；③
  M4-1 挂账 #6 孤儿第五度预防照旧（催办维持）。

## 7. M5-2 交接（Mertens 曝光融合，IOP-HDR-06）

- 下波 = M5-2（`REQUIREMENTS` IOP-HDR-06「→ M5-2」）：Mertens 曝光融合——
  **Lumen 借鉴②**（`/Volumes/UNITEK/Documents/Development/lumen-raw` MIT，
  `lumen/merge.py` 参考实现；本地调研正本 = `.work/gsd/research/LUMEN-RAW-NOTES.md`）。
- 本族可复用面：ColorMatchDocument 值面 + throwaway PipeCache 的 headless
  提取形（M5-1-02 E6）；multi-image 合成的 pipeline 级 API 惯例；`.cube`
  之外的派生资产位策略。
- 执行模型照 Phase 约定（omp 执行 + subagent 验收 + dual_acceptance）。
