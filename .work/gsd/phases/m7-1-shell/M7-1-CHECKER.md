# M7-1-CHECKER — 修订版 M7-1-01 plan 独立反向核（2026-10-16）

> 评审身份：fixer 后独立 checker 批（同 worker 两阶段，本文件 = checker
> 阶段产物；反向核以修订后 plan 全文 + 评审正本 + 代码面 HEAD 亲核，
> 非 fixer 阶段结论的转述）。
> 输入 = 修订版 `M7-1-01-PLAN.md`（commit `a31601d9` + 本批 checker
> 微修）+ `M7-1-01-PLAN-REVIEW.md` + `M7-1-CONTEXT.md` +
> `M7-1-RESEARCH.md`（§0/§1/§3/§5/§6 抽读）+ `FIX2-01-DECISIONS.md`
> D-FIX2-1 第 5 条 + 代码面（`LightamerApp.swift` / `ContentView.swift`
> / `InspectorView.swift` / `WorkspaceHostView.swift` / 两测试文件
> 构造点 / Commands 块 wrap 区段——逐点实读）。
>
> **结论头：放行**。E-1（修法甲）+ F-1..F-7 + N-2..N-6 修订全部落位、
> 判据链可机检、新旧口径无残留矛盾（grep 机检过）；独立猎残 4 处
> （R-1..R-4，全 minor / 簿记级）已在本 checker 批并入 plan 微修
> （§四），零阻塞残留，可派发执行批。

---

## 一、Goal-backward：修订版达成性

1. **Phase Goal 五刀映射（CONTEXT「Phase Goal」↔ RESEARCH §6.1 推荐序
   ↔ plan 任务序）**：
   - RESEARCH §6.1 六行推荐序：第一刀案 A+B → **T1**；第二刀案 C
     （C3 scratch 门 + 不饿死呈报）→ **T2**；第三刀窗拆 scratch 同批
     采数 → **T2 action 2**；SHELL-03 燃料减频叠加 → **T3**；
     SHELL-04 上游通道 → **T7**（FB 勘误落稿 + 案号回填槽 + 27.1
     监测节律入 GOAL-STATE）；SHELL-05 复走殿后 → **T4**（复测 +
     挂账⑥ N≥3）+ **T6**（三波复走 + 挂账④⑤）。映射闭合，无孤儿刀。
2. **SHELL-01..05 五需求行**：SHELL-01 减树测绘 → T1 落地；SHELL-02
   窗拆评估 → D-M7-1-2 不立项 + T2 action 2 采数挂档；SHELL-03 → T3；
   SHELL-04 → T7；SHELL-05 → T4/T6。无孤儿项。
3. **SC → 任务映射缺口核**：逐条 SC clause 反查产出 action——
   - T1 决定性判据①②/底噪带/列活态/flag-off 带 → action 6 三件读数
     （载体齐全：ps+sample / probed transcript / 页活态组）；走查四件
     → action 7；AX 零回归 → action 4；`--bundle App` → action 4/5；
     legacyBody 零 diff → 头注红线 + T5 机检复跑。无缺口。
   - T2 读数三件 → action 1；分支 A 门 → action 3；分支 B 呈报四项
     （C3 读数 / C1 损失 / C2 损失 / 窗拆读数）→ action 2 + 4（窗拆
     数据流：action 2 采 → action 4 呈报件并列——闭环）。无缺口。
   - T3 机制面 grep + 计数对 → action 1/5；审计三产出 → action 2；
     IA 矩阵族 → 既有测试族 + `--bundle App`；行为三钉 → action 1
     priming 点验 + :429 双面 self-disarm 走查。无缺口。
   - T4 三判据 → action 1-3；flag 双向 → action 4；挂账⑥ → action 5；
     截图三面 → action 6（证据域归档承载）。无缺口。
   - T5/T6/T7 SC 与 action 一一对应（红线族机检清单 = front-matter
     red_lines 逐条；MANIFEST / 三台账同批 / FB 勘误两处 grep）。无缺口。
4. **达成性判读**：修订版验收判据在证据链上可达——①transcript 零行门
   （C1/C2 scratch 已证 churn 死后 sceneBody 2/25s → 修后 0 行合理）；
   ②环核心符号 ≤1（骨架残环按 D-FIX2-1 第 5 条不含 makeMainMenu 族，
   归零或单帧合理）；③底噪带 ≤40%（正本 ~28%，案 A/B 等效摘除形同域，
   余量充分且带外 FAIL 有真判力）；④T2 编辑器面 <10%（E1/E2/E3 实测
   0.0-0.1%，无底噪矛盾——评审 §三.3 亲证结论维持）；⑤T3 机制面
   grep + 计数对（flag-off 臂环活着，非 0 vs 0）。**修法效果可被判
   「真绿」，成功不会被误记 BLOCKED**——E-1 的裁定路径缺口已消。

## 二、核心修订自洽

1. **E-1 新旧判据全文残留 grep（机检）**：
   - `<5%`/`<10%` 残留命中全部为引用性提及（「替代/撤除 <5%/<10% 数字门」
     三处 + RESEARCH 前身稿 supersede 注记一处）或**编辑器面 <10% 门**
     （T2 域——E 系证据支持，与 E-1 修订的空载面域不冲突）。零残留矛盾。
   - 「CPU 归零」旧表述零残留（T1 头注已改「SwiftUI churn 停；AppKit
     ~11Hz 骨架 ~28% 底噪残留——D-FIX2-1 第 5 条实测」）。
   - **两处裁定相反面消除**：T1 走查注记已升格——action 7 明写「CPU
     底噪裁定单源 = AC 底噪带条款，本走查不再另设 CPU 口径」；AC 底噪带
     条款为唯一裁定（带内 PASS 带注记 / 带外真 FAIL）。
2. **F-1 拓扑 ↔ T3 载体面 ↔ F-2 flag-off 臂互洽**：
   - 拓扑 3→2 内部一致：SC（front-matter）、T3 头注范围钉、action 1、
     AC 机制面 grep、files_modified（ContentView「:228 并 carrier」/
     WorkspaceHostView「:170 并 carrier」/ InspectorView「:429 原位」）
     六处口径同一（grep 机检 = 2 的构成：WorkspaceHostView 1 +
     InspectorView:429 1；ContentView gate=false 分支 0；legacy 不计入）。
   - columnVisibility 槽删除与消费端事实互洽（亲核：该键唯一发布点 =
     legacyBody:287；gate=false 面消费者 focusedColumnVisibility 两处
     `guard let` = 无发布即 no-op——carrier 恒 nil 槽确实会引入行为面
     变量，删除是唯一低风险形）。
   - F-2 flag-off 臂采样面成立性亲核：flag-off 臂 = 现行 seating
     （churn 23-34% 环活）——T1/T2 完成态的 flag-on 面环已死，sample
     「前」读数触底，0 vs 0 无信号（评审 F-2 判定维持）；T3 前后
     flag-off 对照有信号面。flag-on 臂旁证组（环维持饿死非门）补齐
     「减频未复燃环」的机制核。
3. **F-6 降级后挂账④义务的兑现形态**：矩阵「目标 × 可用通道」+
   kd:cmd 有效性探针前置 + AXSelectedCells 直写备选腿 + 判死通道
   Blocked-Channel 登记 + 两代判死正本引证（FIX2-01-SUMMARY §5 D4-01
   两独立通道 + FIX2-01-PLAN-REVIEW N-2 键盘路径判死——亲核引证在案）
   +「至少一条存活通道 × N≥3 兑现对照义务」——AC 在通道判死情形下
   **可达**（原「双通道对照表」固定 2×2 形不可达的缺口已消）；T6 AC、
   SC front-matter、Checker 关注点 #10 三处口径同一。
4. **F-7 同体性 ↔ 红线两分支口径**：头注 scratch 纪律（主树工作区未
   commit 形）/ T2 action 1 / 分支 A 转正 / 分支 B 回退 + AC 机检
   四处一致；「scratch 零产线 commit」在分支 B 的兑现口径（回退后
   diff 面为零）与分支 A 的转正路径（同 diff 晋升 = 产线 commit 属
   行使产物非 scratch 泄漏）分叉清晰，无歧义。
5. **N-5/N-6 机检性**：判据二两组谓词（环核心组 ≤1 门 / 骨架族注记
   非门）在 SC、T4 action 2、Checker 关注点 #7 三处一致；稳态窗机械
   取段（≥60s + 末尾连续 10s + 全窗同录）在 T1 action 6/AC、T2
   action 1、T4 action 3 四处一致；median 统计量在 T1/T2/T4 + flag-off
   带五处一致。机检谓词无「目测」残留。

## 三、独立猎残（checker 批产出 4 处，全 minor）

- **R-1【簿记】RESEARCH 稿面前身判据未标注取代**：`M7-1-RESEARCH.md`
  §6.1（「空载/图库面 23-34% → 目标 <5%」）与 §6.2 案 A+B 铁条行
  （「CPU <5%」+「⑤AppKit 底噪注记不判 FAIL」）是 E-1 修订前的前身稿
  ——plan read_first 明引 §6.2 铁条，执行批存在读到旧门的面。**修复 =
  修订记录 E-1 bullet 追加 R-1 supersede 注记**（「RESEARCH §6.1/§6.2
  前身稿被本 AC 取代，引 RESEARCH 铁条处一律以 plan AC 为准，research
  稿面不回写」）。
- **R-2【谓词健壮性】T4 flag-off 23-34% 带未计 T3 燃料减频效应**：带
  界在 T1 时点测定；T4 在 T3 后执行，flag-off 臂（carrier 合并落在
  workspace 面代码，双 flag 臂共有）prependValue 削 ~1/3 次数可使带
  下沿小幅下移——按原文「越带 = 判别臂失效停手」会误触停手。**修复 =
  T4 action 4 补判别力主锚**（flag-off 臂环活着：transcript 非零 +
  环核心符号 > 门）+ 带下沿漂移归因注记（越下沿先核 T3 效应，越上沿
  /形态异常才判失效；禁静默放宽带界）。
- **R-3【机检精度】T3 AC grep 计数构成欠精**：原文「gate=false 面
  发布点 = 2」未写明 :228 撤除后 ContentView 分支计 0、legacyBody
  原 2 处冻结不计入——裸 `grep -c focusedSceneValue` 全仓会数出 4。
  **修复 = AC 括注逐点构成**（WorkspaceHostView 1 + InspectorView:429
  1 / ContentView gate=false 0 / legacy 2 不计入）。
- **R-4【修订自检】fixer 首批 files_modified/T3 action 1 残留
  「face 标记」语**：face 标记 / mirror store 是评审 F-1 修法②（真
  3→1 路线）的构件；fixer 择定 3→2 后该构件不行使，残留语会诱导
  执行批加无用参数。**修复 = 两处摘除**（files_modified InspectorView
  行 + T3 action 1 改「无需 face 标记 / mirror store，真 3→1 路线
  不行使」）。

## 四、checker 批微修清单（并入本 commit，plan 内标注 R-1/R-2）

| # | 落点 | 修订 |
|---|---|---|
| R-1 | 修订记录 E-1 bullet | 追加 RESEARCH §6.1/§6.2 前身稿 supersede 注记 |
| R-2 | T4 action 4 | 判别力主锚（环活着）+ 带下沿 T3 效应归因注记 + 禁静默放宽 |
| R-3 | T3 AC 机制面首条 | grep 计数构成逐点括注（1+1 / gate=false 分支 0 / legacy 不计入） |
| R-4 | files_modified InspectorView 行 + T3 action 1 | 摘除 face 标记 / mirror store 残留语，钉「真 3→1 不行使」 |

## 五、放行条件与执行批知悉项

- **放行**：无再修清单。修订版可派发执行批（omp 或 subagent 执行批
  按 AGENTS Phase 执行模型）。
- 执行批知悉（非阻塞）：①N-1 挂账⑥时序自洽（修后证据），无修订义务；
  ②RESEARCH §6.2 他行（案 C / SHELL-02 / SHELL-03 铁条行）与 plan
  对应 AC 如有字面出入，一律以 plan AC 为准（同 R-1 口径）；③M-7
  Scene 探针限制（phase 镜像落 View 层）已写入 T3 action 3；④E-1
  底噪带值（≤40%）若执行批实测显著越带（>40%）按 FAIL 归因路径走，
  禁以「带定宽了」放行——带的裁定语义在条款内自足。
