---
phase: M7-1（D-6 壳专项——定罪批）
slug: m7-1-shell
status: validated
nyquist_compliant: true
created: 2026-10-16
validated: 2026-10-16
batch_form: conviction（零产线 ΔN=0）
---

# Phase M7-1（D-6 壳专项）— Validation（D-6 终局定性：饿死证据证据级 dissolved，缓解收窄为 upstream-only——双眼定案的定罪批签核）

> 体例对齐 `phases/fix2-defects/FIX2-VALIDATION.md`（正本链上溯
> `phases/v2-maintenance/V2M-VALIDATION.md`）。**本 phase 交付 = D-6 终局
> 定性，非代码修复**——执行批停手（`5323df67`）+ 零共享上下文独立复核
> （`bddaba6b`，`M7-1-HALT-REVIEW.md` 234 行）双眼定案；orchestrator 采纳
> 复核验收意见裁定缓解面。**终态基线 3860/35/0 逐值维持，ΔN = 0**
> （执行批零产线 commit + flag 全套撤回；复核批 doc-only；本签核批
> doc-only）。**核心定案：FIX2 全部饿死证据（C1×3 + C2×4 + E×3 十轮
> transcript）证据级 dissolved**——全部落遮挡/发射静默窗伪象；E 系三连
> 「编辑器面摘段饿死」运行从未进入编辑器面（transcript `phase=library`
> 全程）；今日协议下 C1-EXACT 与 HEAD 逐行为同构（活），编辑器面置前
> reveal **无点击 ≤1s 复燃**。**D-6 缓解裁定 = upstream-only 为主** +
> 遮挡止损 doc 一行（语义勘正「置前即恢复 ≤1s 无需点击」）+ 窗拆
> （SHELL-02）挂条件账；SHELL-01/03 不行使（价值证伪）；SHELL-05 复走
> 行集改挂「功能态常驻」走查批。裁定正本 = `M7-1-01-DECISIONS.md`
> （D-M7-1-01-1..5）+ `M7-1-HALT-REVIEW.md`；证据正本 =
> `gui-acceptance/m7-1/`（t1-scratch-matrix/MATRIX.md + t4-import-retest/
> rounds-summary.txt 等，local-only）+ 复核三实验（/tmp/m71-review/ 即弃，
> 关键数值已内联 HALT-REVIEW §2.2）。

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Batch form** | **定罪批（conviction batch）**——phase 产出 = 探针复验 + 证伪定性 + 缓解裁定；零产线 commit。执行链 = `fc587281`（plan 定稿）→ `a31601d9`（plan 修订）→ `5323df67`（停手批 doc）→ `bddaba6b`（独立复核 doc）→ 本签核批（doc-only） |
| **Full suite（phase 终轮）** | 执行批 T5 已批 HEAD 基线轮：`caffeinate -dis Scripts/test-direct.sh --all` = **`TOTAL\|3860/35/0\|` 2093s exit 0**（IOP 687/5/0〔7728MB〕/ IOPParity 460/3/0〔8108MB 贴线未触 8G 门〕/ Layers 494/5/0 / Library 729/4/0 / Sessions 284/9/0 / Export 379/5/0 / App 827/4/0；正本 = `M7-1-01-SUMMARY.md` §T5 对账）——对账 = FIX2 终态基线 3860/35/0 **逐值精确闭合，ΔN = 0** |
| **ΔN 记账** | **ΔN = 0**：`shell.reducedTree` flag 全套撤回（gate 文件/测试/装配/键——无消费者的死 flag 不入树；「UserDefaults 新键唯一」以**零新键**兑现）；ShellReducedTreeGateTests 随 flag 撤回删除；LEGACY seating 逐字节未触 |
| **红线族机检** | 回滚后 HEAD 原状亲核（执行批 + 本批双验）：tracked modified = 0；`.metal` 零 diff；封存面零触；`runModal` 禁形零命中；LocalizationValue 插值禁形零命中；UserDefaults 新键 = 零；xcstrings 零 diff；Project.swift 零 diff |
| **GUI 证据** | **探针证据族即弃域如实登记**（Checker 条款）：执行批矩阵 = `gui-acceptance/m7-1/t1-scratch-matrix/MATRIX.md`（local-only，per-arm 缺口两处由复核补测闭合——HALT-REVIEW §1.1 row 1 Exp-1 / row 2 影响低注记）；复核三实验 = /tmp/m71-review/（即弃；四 sample + 两截图 + 三 log，关键数值全部内联 HALT-REVIEW）；挂账⑥ 复测 = `t4-import-retest/rounds-summary.txt` |
| **zh 对账** | xcstrings 零 diff；UserDefaults 零新键（批内断言面——本批 doc-only 零触产线） |
| **验收形态偏差申报** | 本 phase 无独立 ACCEPTANCE 文件对：**双眼 = 执行批（停手批自报证伪）+ 零共享上下文独立复核（HALT-REVIEW 亲跑三实验）**，orchestrator 采纳复核验收意见 = 双眼共识裁定；plan 原验收形态（三判据转绿 + 复走行集逐行销账）被定罪批形态改判——三判据判定式以「证伪转绿不可能」如实 FAIL 登记，复走行集改挂功能态常驻走查批（§挂账④），FB 案号槽留待用户提交（§挂账③）。夜间全自动授权在案（先例 D-07-3-T5-1，晨审可推翻） |

## 三列证据（定罪核心）

### 列一：探针复验三判据（FIX2 复验门，执行批 + 复核两轮独立重采）

| # | 判据 | 执行批读数（HEAD `fc587281`） | 复核读数（HEAD 等价构建亲跑 Exp-1/2/3） | 判定 |
|---|---|---|---|---|
| 1 | **CPU 硬门**（<10% 门 = 绿） | 空载面 28.5-34.9% 中位带（六形态）+ 编辑器面 C3 96.1% 中位（93.2-99.7%）——门 FAIL | HEAD 空载 30.9% 起自持 ≥110s / C1 复涂 30-36% 自持 45s+ / 编辑器面 78.7-90.3% 基线 spin + 复燃后 78-86% 自持 45s+（收尾 86.5%）——门 FAIL | **三形三面全 FAIL（复现稳定）**——spin 在场非缺陷漂移 |
| 2 | **菜单环六符号 sample 全链** | 全形态环符号同族在场（mm/updateMainMenu/prependValue/mangled-name；CPU 非判读载体） | 稳态符号总量：HEAD 空 mm 204/UpdateStack 696/beginTransaction 1557；C1 mm 202/578；编辑器 mm 274/4334/sizeThatFits 49663 = **满速环** | **环活判定成立**；符号记录格式勘误 = 最大单支 → 总量（§列三 Q1） |
| 3 | **@self 决定性**（无 app 写点） | research 批已钉：21,363+21,360 次 @self-only 重估（42,723/42,731，119 passes/s display-cycle 锁频） | 未重采（判据置换：CPU 轴活/死完全分离——死 0.0% vs 活 26-36%/80-100%，置换侥幸正确但应补记理由；HALT-REVIEW §1.3） | **H1 写点假说证伪维持**（`@self`-only 零属性变更） |

### 列二：六形态矩阵（遮挡门控逐行核，复核 §1.1）

| 行 | 形 | frontmost 证据 | CPU series | 样本存档 | 残留遮态 |
|---|---|---|---|---|---|
| 1 | flag-off = HEAD 座位 | launch.txt（18:49:16 启动 → 18:49:57 frontmost-then-read，41s 沉降） | 10×1s 27.7-31.9% | 复核 Exp-1 补测（mm 总量 204）闭合 row 1 缺口 | 无 |
| 2 | case-B 重组 | MATRIX 在册；per-arm 文件簿记缺口（HALT-REVIEW 注记） | 28.5% 中位 | 无自有文件（5/4/4/103 悬空；与 row 3 同批同族影响低） | 无 |
| 3 | A+B 重组 | t1-idle-flag-on/launch.txt frontmost=true + 可见面截图 | 34.9% 中位 | sample-6s + symbol-counts（pid 49139 对上） | 无 |
| 4 | C1-EXACT | c1-cpu-recheck.txt（pid 50951，19:03:52） | 27.8-43.7% | c1-sample-6s.txt | 无 |
| 5 | C2-EXACT | 同批协议 | 29.05% 中位 | c2-sample-6s.txt | 无 |
| 6 | research 基线 | research §0 配方（当日 16:1x） | 30-34% | m71-editor-sample-head.txt + §0.2 | 无 |

- 首对 flag-on/off 读数（遮态 0.0%）被协议**自己抓出并作废** = 遮挡门控自证有效；保留行无残留遮态窗口。
- **复核第三次独立复现**（Exp-2）：C1-EXACT 复涂（ContentView gate=false 臂 `.inspector` 块移除）+ 增量构建——遮态 0.0%×85s（样本全零符号）→ reveal ≤1s（29.8）→ 30-36% 自持 → hide 15s（全程 0.0%）→ reveal ≤1s（29.3）→ 自持 28.3% 收尾；**与 HEAD 逐行为同构——停手批证伪独立确认**。

### 列三：复核三问裁定（HALT-REVIEW §1-§3）

| 问 | 裁定 | 决定性证据 |
|---|---|---|
| **Q1 矩阵方法学** | 六形态读数**有效**（遮挡门控逐行核通过）；符号记录格式勘误 = per-arm 记录最大单支低估活性量级，总量重提（c1 198/537/1228；c2 143/569/1261）与 FIX2 活态同带——「环活」判定成立；plan 判据置换（transcript 零行+符号 ≤1 → CPU+符号）应补记理由（置换结果正确但「≤1」阈值与 FIX2 饿死样本自身读数不兼容） | §1.1 六行核 + §1.2 总量重提 + §1.3 分级（对「描述形 C1/C2 今日不饿死」= 高：三独立复现；对「FIX2 原字节级相同」= 中：不可验证但描述形复涂已足证伪） |
| **Q2 遮挡伪象假说** | **成立并升级为证据级**：D-M7-1-01-1 候选 #1 独占成立（候选 #2 环境漂移 / #3 产线重燃无需动用）——FIX2 全部饿死读数轮（C1×3 + C2×4 + E×3 十轮 transcript）均落静默窗/错面；/tmp/fix2t1 幸存使逐件还原成为可能 | §2.1：C1/C2 transcript 双相结构（发射 2 tick → 静默 0-90s → 复燃 ~60/s，「饿死」读数全落静默相）；**E 系证据链断裂**（e-strip/e-area/e-right 全程 `phase=library`，各 10 menuCmds 探针零 editor——三次「编辑器面摘段饿死」AX 腿未生效从未进编辑器面；对照 e-base 8810 个 `phase=editor` 在案）；**FIX2 自留样本内在矛盾**（c2-long-sample 263/789/1850 恰逢复燃沿 = 满速环，被记作「28% AppKit 残底噪」；idle-sample 0/0/0 = 遮态静默；c1/c2-sample = 复燃上升沿非「残底噪」） |
| **Q3 策略材料** | 行为模型修正 + 三案重裁（§终局行为模型 / §挂账）：窗拆唯一理论杠杆（生产版摘段）依赖 E 系饿死——已无效 → 挂条件账；遮挡止损对 spin 亦有效（Exp-3 hide→0.0% / reveal ≤1s 复燃）→ doc 一行；upstream-only 成默认主路径 | §3①②③ |

## 终局行为模型（D-6 定性终式）

> **D-6 = macOS 27 SwiftUI 菜单/焦点更新自持环（H2 维持：`makeMainMenu ↔
> updateMainMenu ↔ invalidateProperties ↔ updatePreferences` + 焦点 store
> `PropertyList.prependValue` 逐 pass 无去重）——环的树形饿死已无任何在案
> 有效证据**（原五组证据全 dissolved + 今日三独立复现均活）。环的真实行为
> 模型 = **可见性门控开关 × 振幅随面重**：
>
> - **开关**：遮（最小化/完全遮挡/⌘H）→ CPU 归零（0.0%，符号全零）；
>   显 + 激活（置前，**无需任何点击**）→ ≤1s 点火复燃；显期间自持
>   （分钟级在案：FIX2 b2b transcript 401s @59/s + 复核跨相 ≥110s）。
>   ⌘H 全覆盖两形三面；遮挡对编辑器 spin 同样压 0（Exp-3）。
> - **振幅随面**：图库/空载面 ~30%（28-36% 带）；编辑器面 80-100%
>   （78.7-99.7% 带，交互后 98-100%）；legacy 面 0.1%（开菜单态 41.5%
>   点火，FIX2 第一路 #4 维持）。
> - **表型终态 = 功能态-with-churn**（UI 可交互非 hang 非 crash；代价 =
>   永久单核烧 + 电池）。**FIX2 第二路「解遮后 4s 不复燃 + 点击复燃」=
>   观察窗短于点火延迟的测量伪象**（或该轮特异）——「环被点击重置」
>   替代解释不成立（复核 Exp-1/2/3 置前即点火零交互）。
> - **H2 精确定性措辞维持**：「macOS 27 SwiftUI 菜单/焦点更新机制在特定
>   树形〔重树 + `.inspector` 分栏宿主 + 三段内容〕下不收敛」——树形是
>   **点火条件**非**持续条件**（持续面树形手术不可饿死）。

## 双眼记录

| 眼 | 载体 | 范围 | 结论 |
|---|---|---|---|
| **眼一：执行批（停手批）** | `M7-1-01-DECISIONS.md` D-M7-1-01-1..5 + `M7-1-01-SUMMARY.md` + `gui-acceptance/m7-1/t1-scratch-matrix/MATRIX.md` | T1 六形态矩阵（frontmost 硬化协议后）+ T2 C3 编辑器面 96.1% + T4 挂账⑥三轮全净 + T5 全套基线 + T7 FB 勘误两处 | T1 前提证伪 → 停手零 commit；归因三候选如实登记未裁决（交复核） |
| **眼二：独立复核（零共享上下文）** | `M7-1-HALT-REVIEW.md` 234 行 | Q1 矩阵逐行核 + Q2 伪象假说亲验（/tmp/fix2t1 逐件还原 + Exp-1/2/3 亲跑三实验）+ Q3 策略裁定 + §4 六条勘误/补强建议 | 三问全裁定；证伪从「重测级」升级「证据级」；停手批处置（零 commit/回退/上报）正确维持 |
| **裁断** | orchestrator 采纳复核验收意见（2026-10-16 夜裁定）：缓解 = upstream-only 为主 + 遮挡止损 doc 一行 + SHELL-02 条件账 + SHELL-01/03 不行使 + SHELL-05 改挂功能态常驻走查批 + 挂账⑥降级待研 | —— | 本 VALIDATION 即裁断落账载体；复核 §4 建议 1-4 并入 LESSONS L082 与 DECISIONS 补记面，建议 5（/tmp/fix2t1 回填）留 orchestrator 裁量〔复核时幸存未回填，窗口仍在〕，建议 6（呈报件 2 AX 桥批注）维持留档 |

## 挂账单一清单（六项，正本 = 本节；STATE/GOAL-STATE/REQUIREMENTS 同批翻账）

| # | 项 | 形态 | 触发/动作 |
|---|---|---|---|
| ① | **SHELL-02 编辑器窗拆** | **挂条件账** | 触发 = **E 系硬化复测复活**（半日级必做前置：同 C1 复涂法逐段摘 filmstrip/viewport/rightPane + probe 项目 + AX 腿 + frontmost + reveal 后 60s 观测 + 样本总量 + **transcript `phase=editor` 机检断言**〔E 系教训〕；判读：任一形 reveal 后 0% 持续 ≥60s = 树形杠杆复活 → 窗拆重评；全部 ≥80% = 窗拆饿死性终证死亡）。若复活：SHELL-02 scratch（编辑器段独立窗）同协议 + 编辑器窗 CPU 硬门 <10% + RESEARCH §3 多窗生命周期走查；量级 L（2-3 plan 波）。若杠杆死亡：窗拆只剩 IA 偏好收益（偏离 Alcedo 单窗对标） |
| ② | **SHELL-01 壳减树 + SHELL-03 燃料减频** | **不行使（价值证伪），parked** | SHELL-01：减树饿死论（C1/C2/E 系）全 dissolved——三独立复现减树形均活（28-36%），无收益面；SHELL-03：价值论证（提高饿死裕度）依赖已证伪 threshold 理论 + FIX2 B1/B2 焦点写点全摘不饿死先例（D-M7-1-01-1 后果节）——纯风险面。两件 parked 零代码（执行批 flag 全套撤回即终态） |
| ③ | **SHELL-04 upstream 通道** | **in-flight（唯一主路径）** | FB 稿补强三点已落 `research/APPLE-FB-D6-DRAFT.md`（遮挡门控确定性复现 / C1/C2 三独立复现树形证伪 / 跨日稳定编辑器 spin 配方 repro.sh 形 78.7-100% 三路在案）；**提交动作 = 用户手动**（Nitro LUT 先例），FB 案号回填槽 = REQUIREMENTS SHELL-04 行 + GOAL-STATE 续接点；macOS 27.1 release notes 监测关键字（`menu`/`updateMainMenu`/`property graph`/`invalidation`）**入巡检**；E 系证据无效一事不入 FB（内部分卷） |
| ④ | **SHELL-05 复走行集** | **改挂「功能态常驻」走查批** | D-6 缓解 = workaround 常态化（遮挡/⌘H）后，行集（波 1 屏面四项 V2M-T1-02/D3-01/D4-01/D5-01 + m6-closeout Blocked-Channel 余行 + FIX2 挂账④点击表型双通道 + 挂账⑤探针缝 exit(0) 兜底）以 **churn 在场判读口径**复走——原「修后复走」（转绿判读）前提消灭，改「功能态常驻 + churn 在场」为判读基线；挂账⑥导入零行间歇复测随该批（见⑤） |
| ⑤ | **FIX2 挂账⑥ 导入零行间歇** | **降级待研** | M7-1 执行批 T4 三轮全净（6/6 行 ×3、DB=6 ×3、0 迟到，churn 完全在场态零再现）+ research 批再现 1 例——间歇与 churn 无稳定相关 = 「churn → grid 迟到」因果假说反向旁证；D-FIX2-4 勘误口径维持（行恒落库 + grid 刷新迟到，禁再循 insert 路径）；维持独立待研登记，非当前活跃缺陷，随④批顺带复测 |
| ⑥ | **T3 燃料减频 + AX 测试桥限制** | **不行使 + 留档** | T3 裁定见②（同 SHELL-03 面）；case A 座移 AX 桥不可测结论（in-process AX 走查只物化 safeAreaInset 内容——D-M7-1-01-2）与证伪独立，留档供座移类改造批复用 |

## 特殊事项

1. **定罪批验收形态改判（orchestrator 裁定采纳）**：plan 验收形态预设修法落地（三判据转绿 + flag 回切判别力 + 复走销账）；执行批首日 T1 即证伪交付前提 → phase 改判为定罪批（定性交付）。原验收形态三判据以「证伪转绿不可能」如实 FAIL 登记不硬造判定（Checker #6 条款：探针证据族即弃域如实登记）。
2. **测量纪律沉淀（LESSONS L082，复核 §4 建议 1-4 收编）**：churn 读数必须 **frontmost + 环符号双验**，遮态读数无效（可见窗语境 CPU ≈ 0.0% 即伪象哨兵——活态带 26-36%/80-100% 与 0.0% 完全分离，读数后即时对带复核）；sample 符号一律记**总量**（跨行求和）禁最大单支，「N hits」必须区分 grep 行数 vs 计数总和；涉编辑器面 AX 腿探针必须 **transcript `phase=editor` 机检断言**后采数；静默相哨兵（2 tick 发射 → 长静默 → 复燃沿 = 遮挡双相签名，勿把复燃沿样本当「残底噪」——FIX2 c2-long 满速环被记作 28% 残底噪即此陷阱）。
3. **呈报件终态（对执行批 SUMMARY 呈报清单销账）**：①【主件】硬化协议重跑 FIX2 C1/C2 scratch → **已由复核代答（三独立复现均活，证据级 dissolved）**；②C1/C2 座移 AX 桥批注 → 留档（挂账⑥）；③FB 提交 → 案号槽维持待用户（挂账③）；④挂账⑥ → 降级待研（挂账⑤）；⑤T3 → 不行使（挂账⑥）。
4. **判据置换补记（复核 §1.3/§4-4）**：plan T1 判据（transcript 零行 + 环符号 ≤1）被 CPU+符号置换——置换结果正确（活/死在 CPU 轴完全分离）但「≤1」阈值与 FIX2 饿死样本自身读数不兼容（若饿死为真其自身样本也过不了 ≤1）；置换当时未论证，本节补记。
5. **workaround 语义勘正落文档**：README Known Issues workaround 行 + FB 稿 occlusion 表述同步勘正——「置前即恢复 ≤1s **无需点击**」（FIX2 第二路「一次点击」表述 = 测量伪象，复核 Exp-1/2/3 零交互置前点火）。

## 留痕

- 执行批证据 = `gui-acceptance/m7-1/`（local-only）：t1-scratch-matrix/（MATRIX.md + per-arm）+ t2-c3-scratch/VERDICT.md + t4-import-retest/rounds-summary.txt + MANIFEST.md。
- 复核留痕 = `/tmp/m71-review/`（即弃域：exp1/2/3 log + 四 sample + 两截图；关键数值全部内联 `M7-1-HALT-REVIEW.md` §2.2）；C1 复涂已 `git checkout --` 回退 + HEAD 二进制重建亲核（复核期间 tracked modified = 0）。
- /tmp/fix2t1 语料（FIX2 时代 B/C/E 系原始件）复核时幸存未回填——回填窗口仍在，留 orchestrator 裁量（复核 §4-5）。
- 本 VALIDATION = doc-only commit；不 push。
