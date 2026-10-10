---
phase: m4-2
plan: "M4-2-02"
title: "备用批——readEdgeMap 升级口 512→1024 实测裁决（条件触发，非默认执行）——产线调用点 maxLongEdge 1024（签名/缺省 512 零改）+ probe 1024 同参复跑 8 景盒门 ≥6/8 + 预算实测裁决阶梯（≤50ms 维持 / >50ms≤200ms 判据①内门修订申请 / >200ms 停止上报 GPU NMS 逃生口）+ LAYERS 1024 路径回归 + 合成轨门零变负测 + 默认回翻（若 M4-2-01 T6 未执行则由本批承接）+ 收口"
wave: 2
depends_on: ["M4-2-01"]
autonomous: true
requirements: ["IOP-MASK-06（升级口注记——RESEARCH §6 风险1 预设裁决点，OQ-2-A 逃生口姊妹条）"]
estimated_tests: "+1..2"
test_bundles: [Layers, App]
files_modified:
  - App/Sources/Lightamer/State/PipeCoordinator.swift            # 修改：edgeMapField(for:) 的 readEdgeMap 调用点显式传 maxLongEdge: 1024（:2026 一处；FollowEdges.readEdgeMap 签名与缺省 512 零改）
  - App/Sources/Lightamer/State/LayerEditingState.swift          # 修改（条件）：若 M4-2-01 T6 因 T5 FAIL 未执行，本批 T3 承接默认回翻 .streamline
  - App/Sources/Lightamer/UI/Overlay/MaskToolbarView.swift       # 修改（条件）：hint 一行（同 M4-2-01 T6 条件承接）
  - Resources/Localizable.xcstrings                              # 修改（条件）：0-1 键尾块纯插入
  - Tests/LightamerTests/RidgeExtractTests.swift                 # 修改：+1..2 法（readEdgeMap 1024 路径 field 维度/降采样序断言 + 合成纯函数面零变负测）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-02-SUMMARY.md        # 新建（T4）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-02-DECISIONS.md      # 新建（T4）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-02-ACCEPTANCE.md     # 新建（m1 双重验收记录——zcode PASS 后串行 omp）
  - .work/gsd/phases/m4-2-follow-edges/M4-2-02-ACCEPTANCE-OMP.md # 新建（T4）
  - AGENTS.md                                                    # 修改：M2-7 Follow Edges 段升级注记（工作域 512→1024 + 预算门终值，T4）
  - .work/GOAL-STATE.md                                          # 修改：续接点
  - .work/TODO.md                                                # 修改：M4-2 条目
  - .work/LESSONS.md                                             # 如踩坑
---

# Plan M4-2-02 — 备用批：readEdgeMap 升级口 512→1024 实测裁决（条件触发）

> **性质**：**条件触发批，非默认执行**。M4-2-01（主 plan）T5 真图门 FAIL 且败因判别
> 落在「细脊缺响应」分支时，本批才执行；否则本批**整体作废归档**（GOAL-STATE 记
> `expired`，文件保留不删——触发条件与升级行动的在案正本，供未来 phase 复用）。
> 升级口出处 = RESEARCH-NOTES §6 风险1「plan 期实测裁决点，不预设」+ OQ-2-A
> GPU NMS 逃生口的姊妹条（本批仍全 CPU——只放宽读回工作域，不加 kernel）。

## 触发条件（arming，三条同时成立才执行；判定依据 = M4-2-01 T5 probe 诊断行）

1. **主门 FAIL**：M4-2-01 T5 真图 8 景盒功能链 <6/8。
2. **败因 = 细脊缺响应（输入缺响应，非算法失稳）**：probe 诊断行显示 ≥2 个败景的
   scene box 内 NMS 候选零/近零（≤512 场中该脊整条未成形——机理④降采样放大），
   **且**到场脊上的 V2 链指标正常（候选在场处链长/贴脊达标——即失败模式是
   「场里没脊可提取」而非「提取了走不稳」）。
3. **机制轨健康**：M4-2-01 合成 9 景 golden 全绿 + snap 对照轨全绿 + 双跑确定性绿
   （V2 机制本身无缺陷——分辨率是唯一嫌疑变量）。

**不触发/不适用分支（本批零动作，上报 orchestrator）**：
- 败因 = 算法失稳（候选在场但链断/漂移）→ 回 research 修复批，禁升分辨率掩盖。
- 败因 = 其它（seed 布点/景盒定义/解码差异）→ 逐案上报。
- T5 已 PASS → 本批 expired，直接作废。

## 升级行动（已裁形态，执行中不重开）

### KD-1 升参点与预算裁决阶梯

- **改动面收窄到一处**：`PipeCoordinator.edgeMapField(for:)` 内
  `FollowEdges.readEdgeMap(plane, metal: metal)` → `readEdgeMap(plane, maxLongEdge: 1024, metal: metal)`。
  **`readEdgeMap` 签名与缺省 512 零改**（合成测试与既有调用语义零扰动；probe 同步
  同参 1024）。工作域 1024 → 场 ≈1024×681 ≈ 700k px（V1 判据① 域内；field 值数组
  ≈2.8MB，量级无虞）。
- **预算裁决阶梯（1024 场）**：
  - edge map GPU pass + 读回：预期 +6ms 级（probe 实测对 V1 基线 6.3ms）。
  - 预提取 O(N)×4：**≤50ms 维持原门**（若 512 实测 ~15ms 则 1024 预期 ~60ms 可能越门）
    → 实测 **>50ms 且 ≤200ms** = V1 判据① 200ms 总门内 → **DECISIONS 记门值修订申请
    （预提取门改 200ms 总门直接对齐），报 orchestrator 追认**——追认前按 200ms 判据①
    作为运行门继续；**>200ms = 停**：GPU NMS 逃生口立项上报（OQ-2-B），本批不自行
    kernel 化、不做第二级升级（如 2048）。
- **阶梯越门即停上报**是本批唯一上报点；其余按本 plan 收口。

### KD-2 回归与负测

- LAYERS +1..2 法：`readEdgeMap` 1024 路径（>1024 源纹理 → 输出场维度 = 1024 长边
  比例缩 + box 最近邻序断言）+ **合成纯函数面零变负测**（同一 EdgeMapField 直构 +
  提取，maxLongEdge 参数不可达纯函数域——门值与 M4-2-01 逐字节同）。
- probe 1024 复跑：8 景盒 × 多 seed，功能链门 ≥6/8 + 双跑确定性 + 诊断行 + 预算行
  （evidence 仓 `m4-2-02/probe/`，主仓零产物——M4-2-01 KD-5 同纪律）。

## Tasks

### T1 升参 + probe 复跑（KD-1/KD-2）

- read_first：M4-2-01-PLAN KD-5（probe 通道纪律）+ `FollowEdges.readEdgeMap` + M4-2-01 T5 probe 诊断行正本（evidence 仓）。
- 调用点传 1024 → probe 1024 同参复跑（门 ≥6/8 + 双跑 + 诊断/预算行）→ LAYERS 回归两法。
- 验收：`--bundle Layers` 全绿；probe 门 ≥6/8 或按 KD-1 阶梯停止上报；预算实测行在册；主仓 `git status` 无 probe 产物。

### T2 预算裁决（KD-1）

- 预提取实测对阶梯：≤50ms → 门不变；>50ms ≤200ms → DECISIONS 门修订申请 + orchestrator 追认记录；>200ms → **停止本批剩余任务**，上报（GPU NMS 立项裁决权在用户/orchestrator）。
- 验收：DECISIONS 裁决行（走哪档 + 数字）；若停止 = SUMMARY 记停止态 + GOAL-STATE 上报待裁。

### T3 默认回翻承接（条件：M4-2-01 T6 未执行）

- `LayerEditingState.swift:193` 回翻 `.streamline` + hint（0-1 键）+ zh-audit——内容与 M4-2-01 T6 逐字同规格（前置门换成本批 T1 门 PASS）。
- 验收：缺省 mode 断言 + `--bundle App` 全绿 + zh-audit 对账。
- （若 M4-2-01 T6 已执行〔即本批在 T5 PASS 后仍被指令执行——非预期路径〕→ 本任务跳过并 DECISIONS 记录。）

### T4 收口

- SUMMARY/DECISIONS/ACCEPTANCE（双重验收：zcode PASS → 串行 omp，严禁并发）+ AGENTS.md M2-7 段升级注记（工作域 1024 + 预算门终值）+ GOAL-STATE/TODO 同批 + 定向轮 Layers/App 全绿 + 全套 `--all`（orchestrator 批准）基线对账。
- 验收：3335 + M4-2-01 增量 + 本批增量逐位对账；红线自证（`MaskEdgeKernels.metal`/`MaskOverlayHost`/`FollowEdges.readEdgeMap` 签名零 diff 截证）。

## 验收标准（AC 总表）

1. **触发纪律**：本批执行必有 M4-2-01 T5 FAIL + 细脊缺响应诊断 + 机制轨健康三证在 DECISIONS 引用（probe 诊断行逐值）；无三证不执行。【T1】
2. **升参收窄**：产线唯一改动 = `PipeCoordinator` 调用点一处；`readEdgeMap` 签名/缺省/函数体零 diff（机检）。【T1】
3. **预算阶梯**：裁决行在册（三档取一）；>200ms 即停上报，无自行扩级。【T2】
4. **真图门**：probe 1024 复跑 ≥6/8 + 双跑确定性（或按阶梯停止态）。【T1】
5. **回归**：LAYERS 1024 路径法 + 纯函数面零变负测绿；合成 9 景门值与 M4-2-01 逐字节同。【T1】
6. **默认回翻**：`.streamline` 缺省（T3 执行时）；`.snap` 架构原样。【T3】
7. **收口**：双重验收两路结论 + 基线对账 + 红线自证。【T4】

## 风险与边界

- **1024 仍 <6/8**：停——上报 orchestrator（phase 重裁：research 复审 / 接受降级 / GPU NMS 立项三选一），本批不三改。
- **预提取越 50ms 门**：判据① 总门（200ms）内的越门 = 门修订申请路径，不是失败；硬顶 200ms。
- **内存**：field 2.8MB / ridge 图线性——量级无虞；Layers/App bundle 贴线风险零增量（新测试小 fixture）。
- **probe 资源**：1024 场 O(N)×4 Swift 串行秒级内完成，短命进程跑完即退。

## 提交约定

- T1 `feat(app): widen edge map working domain to 1024 for fine ridge capture`
- T3 `feat(app): restore streamline as follow edges default mode`
- T4 `docs(m4-2): close edge map upgrade contingency batch`
- 全英文 Conventional Commits；不 push；probe 证据 commit 落 evidence 仓（`m4-2-02: probe evidence`）。
