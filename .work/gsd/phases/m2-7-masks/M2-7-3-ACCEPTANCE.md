# M2-7-3 ACCEPTANCE — 收口批（Follow Edges 质量走查 + 熔断裁决 + 性能观察 + zh 对账 + 翻账移交）独立验收

> 验收：ZCode 验收 subagent，2026-10-01。对象 = 执行方 6 commits（`853172e` T1a 走查证据 +
> `60582c3` T1b 熔断行 / `315e2a7` T2 perf.md / `78b4f0f` T3 zh 52 键 / `2d333d1` T4 翻账收口；
> plan 正本 = checker 修正版 `7b88bbb`）。方式 = AC 8 条逐条核对 + 五重点定向核查
> （探针源码逐字节比对 + 二进制独立复跑 + 证据图 md5 比对 + grep/git 机检 + 两域独立复跑）。
> **结论头：PASS / 0 error + 3 minor（已修，同批）+ 1 observation。**

## 一、复跑 vs 声明

| 项 | 声明 | 本轮独立实测 | 判定 |
|---|---|---|---|
| Layers 域 | 298/3/0 | **298/3/0**（26s，peakRSS 1039MB，`caffeinate -dis Scripts/test-direct.sh --bundle Layers` 亲跑） | ✅ 逐值一致 |
| zh-audit | --check PASS exit 0（1321/1547） | **PASS exit 0 亲跑**（1321 source / 1547 catalog / zh complete / locale={en,zh}） | ✅ 一致 |
| 全套净轮 | TOTAL\|2525/16/0\|877s EXIT=0 | 采用执行方声明对账（coordinator 批准报备制）+ 事故轮 incident.log 六 bundle 逐值与净轮一致佐证（IOP 467/1、Layers 298/3、Library 430/4、Sessions 279/4、Export 260/1、App 429/0——log 亲读核对）+ Layers 域本轮复跑平值 | ✅ 对账一致 |
| 熔断探针 | probe.log 数字 | **二进制独立复跑**（见 §二①）——判据数字逐值复现 | ✅ 复现亲证 |

## 二、五重点核查结论

### ① 熔断裁决真实性——**独立复现亲证（本验收主证据）**

- **源码链**：committed `probe/`（main/shim/MaskPointExtract）与 /tmp 工作区源**逐字节 diff 一致**；
  shim 仅复制 `MetalContext.makeEncoder`/`maskLikeShape` 机械（亲读 60 行），仓库
  `FollowEdges.swift` 原文编译（walker 零改动）、`MaskEdgeKernels.metal` 原文运行时
  `makeLibrary(source:)`——「真解码（CIRAWFilter 60.2MP DSC00012.ARW，在盘亲核 74.6MB）+
  真 kernel + 真 L014 fence 读回」方法论成立。
- **复现**：committed 二进制复跑一轮——`WARM empty=82/100 avgPts=0.2` 逐字复现；8 景盒 ×
  2 阈值 + 8 auto-seed 共 24 条 SCENE 行链型（n=3/0/1/1/1/1/1/2 模式）与 snap n=2/n=0
  **逐值一致**；DIAG 扫频 4 组 `functionalChains=0/3` 全复现；`FIELD stats` 三值逐位一致
  （max=0.4941 mean=0.01801 p99=0.1808——纯函数确定性实证）。
- **证据图**：复跑再生成的 6 张 PNG（ev_A/B/B2/C + field_vis + plane_dump）与入库版
  **md5 逐字节一致**——入库证据 = 在案源码真实产物，零造假空间。
- **亲看**：ev_B_snap 灯笼上缘 cyan 贴边线 + 白 seed 十字清晰（snap 确定性 2 点亲证）；
  ev_C_degrade 平缓区仅 seed 十字无链（阈值门降级亲证）；ev_A seed 簇与 log n=3/len 4px
  一致；gui_follow_edges_armed.png 工具栏 RAW 键态 `mask_follow_mode_streamline` 高亮
  （翻 `.snap` 前默认态实锤，兼证 T3 前 zh 缺态）。
- **判据逐条**：①冷 6.3ms 中位 ×10（复跑同值）≪ 200ms——非触发；②**触发**——链长
  ≤3 点（功能性需 ≥10 点量级）+ 82/100 空 + 1024/2560 场 × 1.5/0.75 步长扫频 0/3
  （排除降采样假说，失败在 walker 对真实细脊假设本身）+ snap 12px 触达内确定性贴边；
  ③ n/a-by-path 如实记录（P2 seam 只跑 preview 桶；FULL 单发 73.7ms 语境数）。
  **裁决 = 熔断行使成立，无含糊态；验收不推翻。**
- **F1（minor，已修）**：perf.md/SUMMARY/ACCEPTANCE-INPUT/GOAL-STATE/REQUIREMENTS 五处
  账面引数「中位 6.1ms（min 5.7）/ PSO 噪声 74.8ms / FULL 80.3ms」在任何在案 log 中
  **无出处**（committed probe.log = 中位 6.3 / min 6.1 / max 7.3 / FULL 73.7；/tmp 亦仅
  此一轮成功 log + 一轮崩溃 probe0.log）——与 SUMMARY「数字全部来自 probe.log」声明矛盾。
  裁决方向不受影响（两套数同量级且均远内/超阈值同向），已全部对齐在案 log 真值（五文件
  同批勘误，含复跑 6.3/73.5 互证注记）。

### ② 探针替代 GUI 实操的合理性——**成立**

- E3 同根因实锤：synthetic CGEvent 不达窗口 / System Events `click at` 无效 / AX 仅元素级
  ——P2 已登记的同一环境限制（`M2-7-2-DECISIONS.md` §四），非本批新借口。
- 替代通道为**进程内真链**而非引用冒充：解码/kernel/walker/fence 全真（§二①源码链），
  每数字可复跑（验收方已亲跑复现）；GUI 侧真实可达的证据（工具栏武装态 + mask tab RAW
  键态）已截图入库。如实披露于 SUMMARY §走查形态/ACCEPTANCE-INPUT §二/AGENTS.md 方法论节，
  且 plan 风险节明授权「验收 subagent 有权以证据推翻」——程序合规。
- 真不可达面（拖动手感/缩略格渲染等 GUI-only 五点）**未虚报**，挂 Manual-Only（§四）。

### ③ 执行事故（误杀 IOPParity 宿主）处置——**干净、如实**

- 事故轮留证：`all_run_incident.log`（TOTAL|2179/16/0|764s，IOPParity 截断 16/3/0，零
  fail）——本批入库（执行方漏 add，验收补）。
- 净轮独立性：其余六 bundle 两轮逐值一致（log 亲读核对）佐证误杀无连带影响；净轮
  IOPParity 362/3/0（16 + 346 = 362 与总数差精确闭合）。
- **F2（minor，已修）**：SUMMARY 声称「教训入 AGENTS.md M2-7 增量节同批」，但 committed
  AGENTS.md 该节仅熔断/探针/xcstrings 三条、**教训实际未登记**——声明与落盘不符。已在
  AGENTS.md M2-7 节补登记（parentage `ps -o ppid` 核对 + 留证重跑口径）。

### ④ zh 52 键——**独立亲跑 PASS，族账闭合**

- `--check` exit 0 亲跑（1321/1547）；T3 diff 纯插入 884 行、`zh` languageCode 恰 52 处、
  零删除行（机检亲核）；族分账 = P2 DECISIONS §五 52 键清单逐族对上（面板 14 + Range 12 +
  Follow Edges 8 + Default Behavior 5 + 命令/revision 12 + AI sugar 1）。
- 动态族 13 键差额论证成立：scanner 只见静态字面量，labelKey stem/switch 常量/多行
  String(localized:) 不可见——「39 MISSING + 13 动态 = 52 全族照补」与 AGENTS.md 新增
  惯例节自洽，落在 OQ-12 预估 40-70 内。

### ⑤ 两偏差——**均合理且如实登记**

- **偏差 1（熔断落点 LayerEditingState 非 plan 申报的 MaskToolbarView）**：机检亲核——
  `MaskToolbarView` Picker 无字面默认值，get/set 全绑 `editingState.followEdgesParams.mode`
  （:210-211）；Core `FollowEdgesParams.init` 缺省仍 `.streamline`（FollowEdges.swift:66
  零 diff，FollowEdgesTests 不受扰）。App 侧状态单点翻 `.snap` = 语义等效的「UI 默认翻转」，
  且免触 Core——比 plan 原落点更优。walker/`.streamline` 分支 + 模式选择器保留亲核
  （FollowEdges.swift:108 `case .streamline: return streamline(...)` + Toolbar 双 tag）。
- **偏差 2（走查形态）**：见 §二②，成立。

## 三、AC 总表（8/8 PASS）

| # | AC | 判定 | 验收方式 |
|---|---|---|---|
| 1 | 三景 × 两模式证据 + 判据三项数字 + 裁决明确 | ✅ | evidence 亲看 + 探针复跑复现 + md5 比对（判据数字勘误见 F1） |
| 2 | perf.md 三表 + OQ-11 逐条对照 + 超标处置 | ✅ | perf.md 亲读（缩略项「未测得 + Manual-Only 挂账」如实，无静默超标） |
| 3 | zh-audit exit 0 + 52 键全族 + 旧键零触碰 | ✅ | 亲跑 exit 0 + diff 机检（纯插入/52 zh 块/族账闭合） |
| 4 | REQUIREMENTS M2MASK 措辞与实态一致 | ✅ | M2MASK-01..07 逐行亲读（01..04/06/07 P1/P2 验收批锚注原样；05 P3 注记 = KD-1 预制措辞，验收锚本批补） |
| 5 | ACCEPTANCE-INPUT 四节齐 | ✅ | 亲读（AC 指针/熔断记录/挂账/Manual-Only + 验收方式建议） |
| 6 | GOAL-STATE 终态 + TODO 推进 + 收口 md 同批 | ✅ | T4 单 commit 六文件亲核（GOAL-STATE 追加式历史保持） |
| 7 | 源码 diff = 熔断行 + zh 键，零第三类 | ✅ | **F3（minor，已修）**：SUMMARY/INPUT/GOAL-STATE 引 `git diff 7b88bbb..HEAD` 为全 phase 窗口（63 文件含 P1/P2）——P3 真窗口 = `bf2a4db..HEAD` 亲核 **21 文件**：源码仅 LayerEditingState.swift（6+/2-）+ Localizable.xcstrings（884+，0-），其余全 .work/AGENTS 申报面，零第三类（M2-5-3 F1 同类区间笔误先例） |
| 8 | 全套回归 0 fail（基线 = P2 终数） | ✅ | 净轮声明对账 + incident.log 六 bundle 逐值佐证 + Layers 复跑平值（§一） |

## 四、findings 汇总

- **F1（minor，已修）**：判据①/③ 账面引数（6.1ms/5.7/74.8ms/80.3ms）无在案出处 →
  五文件对齐 committed probe.log 真值（6.3ms 中位 min 6.1 max 7.3；FULL 73.7ms）。
- **F2（minor，已修）**：AGENTS.md 误杀教训「同批登记」声明未落盘 → M2-7 节补登记。
- **F3（minor，已修）**：红线核 diff 区间 `7b88bbb..HEAD` 笔误（全 phase 窗口）→
  改 `bf2a4db..HEAD`（SUMMARY §AC7/§红线核 + INPUT §五 + GOAL-STATE）。
- **O1（observation）**：TODO milestone 行在验收前预写「执行+验收闭环」——状态超前于
  实际（GOAL-STATE 当时仍写「下一步 = 验收 subagent」）；本批 PASS 落地后即为准确，
  作为单一状态源纪律注记记档，不改流程。
- 另：SUMMARY「非空链均为 1 点孤子」措辞与 20 点/18 seed 分布不严格符（均值 1.1，个别
  2-3 点）——已随 F1 同处勘误为「≤3 点（均值 1.1）」；操作性结论「链长 ≤3 点」本就准确。
- 范围外滞留（不动）：`.work/gui-acceptance/09-3-tiers-{arw,nef}-A-vs-B.jpg` 两枚 Resilio
  同步噪声 + 仓根 3 枚 ARW/杂项 untracked——非本批产物。

## 五、M2-7 phase 小结（verify-work 输入）

- **三 plan 全 PASS**：M2-7-1 数据/内核（12/12，`M2-7-1-ACCEPTANCE.md` 0e+0m `93ca9e7`）；
  M2-7-2 面板/交互（11/11，`M2-7-2-ACCEPTANCE.md` 0e+1m 已修 `bf2a4db`）；M2-7-3 收口
  （8/8，本报告 0e+3m 已修+1o）。
- **测试 2464 → 2525**（+61 精确：P1 +29 = LAYERS 268→285/APP 398→410；P2 +32 =
  LAYERS 285→298/APP 410→429；P3 零新增=收口红线；skip 16 持平；全套净轮
  TOTAL|2525/16/0|877s EXIT=0，MEMFAIL 零触发峰值 IOP 7850MB < 8G 门）。
- **M2MASK-01..07 全族 Delivered**：01 Radial 双羽化（Alcedo 线性带腿逐式）／02 LinearGradient
  （compression=τ/(2√2) + rotation=atan2 换算钉）／03 Brush（Phase 6 stamping 资产 + revision 面）
  ／04 mask 级属性五件 + 应用序钉／05 Nitro 三件（**Follow Edges = snap 态 Delivered，
  streamline 挂 V2** + Range 面板 + AI subject sugar）／06 蒙版编辑 UI（缩略 GPU 管线 +
  Mask Groups 面板 + 双羽化手柄 + Default Behavior 三分流）／07 contentRevision 乐观并发
  （写点终表五处）。终态注记 + 锚 commit + 验收指针全在 `REQUIREMENTS.md` §M2MASK。
- **熔断裁决（OQ-4-C 行使，可逆）**：UI 默认 `.snap`（`LayerEditingState` 单点，`60582c3`）；
  walker/`.streamline` 分支保留复活零重写；判据②成立经验收探针复现亲证（82/100 空 +
  DIAG 0/3 + 证据图 md5 一致）；V2 修复方向（脊线预提取/亚像素质心/自适应步长）登记
  AGENTS.md M2-7 节。
- **挂账清单**（正本 `M2-7-3-ACCEPTANCE-INPUT.md` §三/§四）：
  1. GUI 交互五点实操证据（E3 延续：缩略格渲染/锁删 toast/Locate 联动/双羽化手柄拖动/
     ask sheet——逻辑面单测已覆盖）；
  2. 缩略 pass 运行时数字（探针不可达 Core framework 闭包 + GUI 无蒙版内容可渲——
     架构面 O(缩略像素)+LRU+零新 queue 已由 P2 AC1/AC9 钉）；
  3. streamline V2（walker 真实脊型失稳，修复方向在案）；
  4. Manual-Only 五项（真机 HDR+100MP 手感/手柄拖动实时性/缩略 GPU 管面目测/三分流实操/
     snap 三参数滑杆手感）；
  5. E3 同根因备忘（GUI pointer 通道环境限制跨 phase 延续——P2 五点 + 本批走查形态同源）。
- **性能观察终账**（`perf.md` 三表）：stamping 0.744ms/千枚基线有效（rasterizer 零 diff）；
  边缘图冷 6.3ms/热 ~0.001ms（prefixHash 折叠语义：mask append 不折叠 → 同层连笔恒命中）；
  FULL 读回 73.7ms 仅语境（seam 不走 FULL）；缩略 pass 运行时数字挂账。
- **phase 交付物**：三 SUMMARY + 三 ACCEPTANCE + DECISIONS 两册 + perf.md + evidence/
  （m2-7-1..3）+ ACCEPTANCE-INPUT 移交清单。**下一步 = C 档门控第 3 停：M2-7 phase
  VALIDATION 签核（verify-work）→ 用户确认后 M2-8。**
