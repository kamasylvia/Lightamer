# M7-1-01 DECISIONS — D-6 壳专项执行批（2026-10-16 夜间批）

> 执行批 = M7-1-01 修订版 plan（`a31601d9` + `fc587281`）夜跑。
> **结论头：结构性前提失效——停手上报。零产线 commit，工作树回落 HEAD
> （`fc587281`）。** D-M7-1-1..6 裁决维持；本文登记执行批的实测推翻项。

## D-M7-1-01-1【结构性，停手主因】FIX2 C1/C2 饿死读数在今日 HEAD 复现失败——"threshold form" 理论被本批探针证伪

**裁决**：T1/T2 的交付前提（树形改变 → 环饿死）不成立。全矩阵见
`gui-acceptance/m7-1/t1-scratch-matrix/MATRIX.md`（local-only）。六形态
（HEAD 座位 / case-B 重组 / A+B 重组 / **C1 纯摘** / **C2 纯摘** /
research 基线）+ 编辑器面 C3 重组形，全部环活（28-35% 空载带 / 96%
编辑器面；环符号 makeMainMenu/updateMainMenu/prependValue/mangled-name
同族在场——符号为决定性判读，CPU 非判读载体）。

**协议硬化记录**（本批亲踩 + 修正）：
1. **遮挡门控**：首批 flag-on/flag-off 读数在窗口被遮挡态采得 = 0.0%
   ——FIX2 一路观察 #1（遮挡 0.7% vs 可见窗 34%）精确复现。其后全部
   读数改 `set frontmost` 先行。FIX2 时代的 C1/C2 "CPU 归零" 读数与遮
   态读数同形——归因候选 #1（见下）。
2. **harness PID 陷阱**（RESEARCH §0.4 同域再证）：`-la_editor_probe`
   带参启动时 `pgrep -f "MacOS/Lightamer$"` 锚尾不命中——带参进程须无
   `$` 锚或按 pty 日志头读。

**归因候选（未裁决，交下一批）**：
1. FIX2 时代 C1/C2 饿死读数为遮挡伪象（遮挡门控发现于 FIX2 中段——
   C1/C2 scratch 测量在硬化协议之前；"CPU 归零" 恰是遮挡态签名）；
2. 环境漂移（同 OS build 26A434；显示器/ProMotion/窗态不可回溯）；
3. FIX2 执行批末段产线 commit 在 scratch 测量之后落地重燃环（FIX2
   close 之后树 doc-only 不变——research 已核）。

**后果**：
- T1 决定性判据（transcript 零行 + 环符号 ≤1）全形态不可达 → **零
  commit**；`shell.reducedTree` flag 全套撤回（gate 文件/测试/装配/
  键——无消费者的死 flag 不入树；红线「UserDefaults 新键唯一」以
  「零新键」兑现）；LEGACY seating 逐字节未触。
- T2 C3 门 FAIL（96.1%，环活）→ 分支 B 登记（见 D-M7-1-01-3）。
- T3 燃料减频**不行使**：其价值论证（提高饿死裕度 + 压低残余）依赖
  threshold 理论；理论失效后为纯风险面（focused-value carrier 重排 +
  priming 语义），且 FIX2 B1/B2（全摘焦点写点）当时即不饿死——减频
  不改变环存活。停手待用户裁定。
- 下一步呈报（用户裁定项，经 orchestrator 汇报层）：①按本批协议重跑
  FIX2 C1/C2 scratch（若仍不饿死 → D-6 缓解脱离树形域：窗拆路线重评
  或 upstream-only）；②FB 提交维持（缺陷复现在案，与修法无关）。

## D-M7-1-01-2 case A 座移与测试宿主 AX 桥（执行批面审结论，随停手一并登记）

case A 座移（inset → VStack 行）使 `ToastFaceTests`/`ProjectReadOnlyFaceTests`
AX 走查断言失败。面审结论：**测试宿主内 SwiftUI AX 子树对 in-process
走查只物化 safeAreaInset 内容，普通 VStack 行内容不物化**（包括
topBar 等既有行 id——先在行为，非本批回归；`AXEnhancedUserInterface`/
`AXManualAccessibility` priming 与 NSHostingController/NSHostingView/HStack
包裹挂载形均不能使行座位可见；真机外部走查两臂逐字节相同——外部走查
深度受限，无法判真机行座位 AX 健康）。「座移后断言自愈绿」的 plan 预期
在测试宿主桥限制下不可达；AX 契约禁收条款以**撤回座移**（而非弱化断言）
遵守。此结论随理论证伪一并失去即时必要性，留档供后续批复用。

## D-M7-1-01-3 C3 scratch 裁定 = 分支 B（不饿死；窗拆采数未行使）

C3 形（viewport hero + 双 overlay，工作区 diff 本体判定，F-7）编辑器面
median 96.1%（93.2-99.7%）+ 环活 4/4/39/97（prependValue 39 = 编辑器面
族）→ **不饿死**（门 <10% + transcript 近零：FAIL）。render 链六行全通
（loaded/rendered=yes ×6）——重组形不破坏渲染链。spin 三步铁条未驱动
（分支 A 门未开，无 commit 无铁条义务）。**窗拆 scratch 顺带采数未行使**：
其判读价值依赖 threshold 理论（理论已证伪，采数为重复计价——E-1 乙案
不采先例同款）；窗拆重评随 D-M7-1-01-1 呈报件走。

## D-M7-1-01-4 挂账⑥ N=3 轮复测 = 零间歇再现（churn 在场态）

三轮 `-la_editor_probe /tmp/fix2acc-import`：grid rows 6/6 到达 ×3、
rendered 6/6 ×3、迟到 FAIL 0/3、DB images=6 ×3（机检行 =
`gui-acceptance/m7-1/t4-import-retest/rounds-summary.txt`）。**裁定措辞
（诚实版）**：本批 churn 完全在场（无修法落地），三轮零再现 = 「churn
在场、间歇未现」——对「churn → grid 迟到」因果假说是**反向旁证**（弱化
而非支持）；D-FIX2-4 勘误口径维持（行恒落库 + grid 刷新迟到；禁再循
insert 路径）。挂账⑥ 维持待研登记，独立于 D-6 修法。

## D-M7-1-01-5 FB 勘误两处随批落稿（D-M7-1-3 兑现）

`research/APPLE-FB-D6-DRAFT.md`：①"~60 Hz" → display-cycle-locked
（~60-120 Hz per display refresh；119 passes/s = ProMotion 120Hz 锁频，
rate ≈ 1 pass per display cycle）②CPU 带补 interact-after 98-100% 数据
点（两处：Summary 与 Actual Results）。提交动作 = 用户手动；案号回填槽
登记于 SUMMARY。

## 执行批红线干跑记录

- 零产线 commit；`git status` = 3 个既有 untracked .work 文件（批前在
  案）+ 本批 .work 证据/doc（local-only 域 + gsd 域）。
- UserDefaults 新键 = 零（flag 撤回）；xcstrings 零 diff；.metal 零
  diff；封存面零触；runModal/LocalizationValue 禁形零命中（全回滚后
  逐条机检 = HEAD 原状）。
- 项目文件再生成 ×2（删 gate 文件后 / C3 回退后；tuist generate 恒末
  位遵守）。
