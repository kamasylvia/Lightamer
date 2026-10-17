# M7-6-01 PLAN REVIEW — 独立 goal-backward 评审（零共享上下文，只读 + 本报告唯一产出）

```
phase:        m7-6-station-close
reviewee:     M7-6-01-PLAN.md（commit 5449ad57；上游 RESEARCH.md/07927ab2 +
              M7-6-CONTEXT.md；基线声明 58c3a78a + 17b9a6c2 + 07927ab2 经
              git show --stat 亲验全部 docs-only——坐标核验有效）
reviewer:     独立评审 subagent（ZCode；2026-10-13/17）
method:       PLAN/RESEARCH/CONTEXT 三文档通读 + 产线源码逐点亲验（read_first
              抽查 25 处 file:line 全数落点；McpToolRegistry seam 面 /
              McpServerController 四宿主+裸臂+arbitrated+embedded box 全文 /
              AgentControlCoordinator acquire·admit·stop 全函数 + stoppedByUser
              全写点 trace / LightamerApp GUI 装配段 / EditorMTKView
              drtLayerColorSpace 全函数 / DrtOutputColorSpace legal 表全 switch /
              LightamerSlider 全文 / EmbeddedState box / McpFinalSnapshotTests
              all32+makeUnionRegistry+descriptionKeys / legalEOTFs /
              McpEndpointInfo 字段数 / YiyinPanelView grep / Monochrome :178 /
              zh-audit --check 实跑 / test-direct.sh BUNDLES / setControlAdmit
              全仓 grep / .runModal grep / FIX2③ 正本 M7-5-CONTEXT 回查）
verdict:      须修后放行 / 1 blocking + 2 major + 5 minor
              （评审清单格式 PASS / N blocking + N major + N minor；blocking>0
              故 verdict token 按 blocking 定义诚实取「须修后放行」——M7-5-01
              PLAN-REVIEW 同款先例。修法全部落在 plan 文本/SC 数字/测试腿
              清单层面，零产线设计翻案、零源码触碰。）
```

**一句话结论**：六项 scope 覆盖完整、任务序与回滚可操作、五条转写勘正全部
成立、红线族基本正确；但 T1 obs-3 复检行**按 plan 字面实现会打断 TURN-03
resume 主语义**（blocking），另有两处上游事实错误经 planner「逐点亲核」仍
带入 plan（major）。修三处后即可放行执行。

---

## 结论头

**须修后放行 / 1 blocking + 2 major + 5 minor**

| # | severity | 一句话 | 位置 |
|---|---|---|---|
| B1 | **blocking** | obs-3 无条件 `stoppedByUser` 复检行拦截「Stop→re-acquire=resume」主路径——agent 被 Stop 后永久无法重获控制权 | T1 action 4 + SC「恰 +2 复检行」 |
| M1 | **major** | 「四宿主体各一 setControlAdmit / 生产调用恰四点 / grep 恰 5 处 = 定义+四宿主体」构成错误——startEmbeddedServer 无自有 registry，装配点实为 3 个 | front-matter SC(T1) + files_modified McpServerController 行 |
| M2 | **major** | 「YiyinPanelView grep Slider 零命中」为假（实测 3 处 LightamerSlider 调用），假勘注将随 T6 写入 REQUIREMENTS 台账 | T3 read_first + files_modified REQUIREMENTS 行 + 承 RESEARCH §3.1 |
| m1 | minor | 「legal SDR 9 对」实为 8 对（4 处错标；清单本身正确） | front-matter SC(T2)/T2 action/ΔN 表/测试文件行 |
| m2 | minor | T1「git diff --stat 恰五文件」实为 6（3 产线 + 3 测试；可选腿再 +1） | T1 验收标准第 1 条 |
| m3 | minor | 「mcp-endpoint.json schema v1 七字段」实为 9 字段——将随 T4 写进 SKILL.md 成文档假事实 | front-matter SKILL.md 节① + T4 action 2 |
| m4 | minor | UQ-L1 SC 翻账「走查 ✓」降格为「配方就绪 ✓」未在 T6 显式登记为制度注记 | T6 action 1 ④ |
| m5 | minor | lightcraft scrub 语义「拖离取消不留残值」被静默丢弃、未申报让渡 | T3 action（RESEARCH §3.1 清单有、plan 无） |

---

## Blocking

### B1 — obs-3 复检行按 plan 字面实现将打断 resume 主语义（不修不能进执行）

**plan 原文**（T1 action 4）：「acquire 等待循环（:227-240 while）退出后、
success 路径（:248 起 resume 路由）之前恰 +2 复检：
`if stoppedByUser { throw McpToolError.controlRevokedByUser(…` + `if held,
self.holderName != holderName { throw McpToolError.controlBusy(…`」；SC 钉
「acquire 函数体 diff = 恰 +2 复检行」。

**产线事实链**（亲验，`App/Sources/Lightamer/State/AgentControlCoordinator.swift`）：

- `stoppedByUser` 全仓仅两个写点：`false` @ :259（**acquire 成功路径唯一清零
  点**）、`true` @ :294（stop()）。
- Stop 后状态 = `stoppedByUser=true ∧ held=false ∧ stoppedHolderName=holder`。
 TURN-03 resume 流程（Delivered 语义，M7-5-SUMMARY + 本 plan T4 SKILL.md §2
 自己也写「Stop = 用户收回 + 同 holder re-acquire = resume」）：agent 重新
 `acquire(holderName)` → 入口 ：216 busy 检查因 `held=false` 放行 →
 `alreadyHeldBySelf=false`（:221）→ 等待循环 ：227 在无未封合编辑输入时
 **循环体一次都不跑**（`while await liveEditActive()` 首轮即 false）→ 直落
 success 路径 ：248-259 resume 并清零 stoppedByUser。
- **插入 plan 字面的无条件复检行后**：该 resume 路径在进入 success 前被
 `if stoppedByUser` 命中 → throw controlRevokedByUser → stoppedByUser 保持
 true（:259 不可达）→ **agent 被 Stop 一次后永远无法 re-acquire**；且 admit
 门（:186-190）对 stoppedByUser=true 同样全拒 → 13 个 requiresControl 工具
 永久不可用。这不是边角：它就是 TURN-03 的 mainline 场景。
- 变体②复检（`if held, self.holderName != holderName`）**无条件安全**：入口
 :216 已拒异 holder，能到复检点时 held 由 false→true 只能是等待/挂起期间他
 holder 抢到 → throw busy 恰是想要的行为。缺陷只在 revoked 臂。
- 测试腿④两变体本身验不出此回归（两腿都从非 stopped 态出发）——回归将在
 T5 定向轮由 M7-5 既有 resume fixture 抓到，届时按 plan 的「恰 +2」SC 与
 「偏差 = DECISIONS 申报」纪律，executor 无权补第 3 行，必然停手回炉。

**处方**（plan 文本三处修订）：

1. T1 action 4 修法改为「等待段入口快照 + 条件复检」：`while` 前增一行
   `let stoppedAtEntry = stoppedByUser`，复检臂改
   `if stoppedByUser, !stoppedAtEntry { throw …revoked }`（Stop 发生在本次
   acquire 的等待窗内才拒；入口已 stopped = resume 语义，放行清零）；busy 臂
   保持无条件两行。SC 的「恰 +2 复检行」相应改为「恰 +1 快照行 + 2 复检行
   （或等价终形 DECISIONS 申报）」。
2. 测试腿④补一条**resume 不断裂负腿**：acquire → stop() → 同 holder
   re-acquire（liveEditActive 恒 false 注入）→ expect 成功且 taskId 复用
   （resume）——正是能拦住本缺陷的那条腿。
3. T4 SKILL.md §2 turn-taking 语义句补半句诚实面：「等待编辑输入封合期间被
   Stop → re-acquire 得 controlRevokedByUser（非静默吞）」——obs-3 修复后
   这是新的对外语义，agent 文档如实写。

## Major

### M1 — setControlAdmit 装配点构成错误：「四宿主」实为「三宿主」

**plan 原文**（front-matter SC T1）：「每宿主函数体 setWriterCheck 调用点
（:737/:819/:1081 + embedded 装配段）之后恰 +1 …（grep 四宿主各一处 +
setControlAdmit 生产调用恰四点——全仓 grep `setControlAdmit` 在 App/Sources
恰 5 处 = 定义 :367 + 四宿主体）」。

**产线事实**（grep 亲验 McpServerController.swift 全文）：

- `setWriterCheck` 全文件**恰 3 处**：:737（read-only）/ :819（stdio）/
  :1081（http）。`startEmbeddedServer`（:1165-1202）**没有** setWriterCheck、
  不持有 registry——它整段委托 `startHTTPHost`（:1176），embedded 的 admit
  经 box 读出透传给 startHTTPHost 后**复用 ：1081 那一个安装点**。
- 因此自然实现 = 生产调用**恰 3 点**（三个宿主函数体各一），不是 plan 钉的
  「恰四点」。「恰 5 处」这个数**碰巧**能达成——但构成与 plan 所写不符：
  实际 = 定义 :367 + `ControlToolset.swift :20` **头注里的一处 setControlAdmit
  字样** + 三宿主调用。按 plan 的构成说明去核，「四宿主各一处」必判假失败；
  executor 若为凑数在 embedded 段经 HttpHostHandle.registry 二次安装，则造
  成 double-install + serve-before-admit 竞态窗（结构性劣化）。
- 病灶上游：RESEARCH §4.1「四宿主装配点均只 `setWriterCheck` 无
  `setControlAdmit`——…startEmbeddedServer（:1165-1202）」将无 registry 的
  embedded 段并入宿主清单；M7-5-SUMMARY Leftovers 1 同句。planner 转写勘正
  五条 + 「file:line 逐点亲核」未覆盖这条**结构性**事实（行号全对、构成错）。

**处方**：SC 改为「setControlAdmit 生产调用恰 **3** 点（三宿主函数体
setWriterCheck 之后）；App/Sources grep `setControlAdmit` 恰 5 处 = 定义
:367 + ControlToolset :20 注释 + 三调用点」；files_modified 行删「+ embedded
装配段」表述，改「embedded 经 box→startHTTPHost 单点装配，无独立安装点」。
签名批（4 个 `admit:` 缺省参 + box 字段 + :1165 读出透传）不变，那部分坐标
全部亲验吻合。

### M2 — 「YiyinPanelView grep Slider 零命中」为假，假勘注将写入台账

**plan 传播三处**：T3 read_first「`YiyinPanelView.swift` grep Slider 零命中
确认（范围勘正）」；files_modified REQUIREMENTS 行「UQ-L1 范围勘注 = iop
面板族〔yiyin 面板无滑杆——RESEARCH §3.1 勘正随批〕」；CONTEXT D-M7-6-5
同句。

**产线事实**：`App/Sources/Lightamer/Yiyin/YiyinPanelView.swift` 实测
**3 处 `LightamerSlider(` 调用**（:160 blur / :182 main_rate / :203）；
引入 commit e495ea8c / a34c079a（08-3/08-2 批）远早于 research。RESEARCH §3.1
的「勘正」建立在一次失败的 grep 上，plan 未复检即采信，还把「确认零命中」
写成 executor 的 read_first 动作（照做必踩坑），并安排 T6 把「yiyin 面板无
滑杆」写进 REQUIREMENTS 台账——**给唯一事实源写入假事实**。

**影响面判定**：修复落点（只触 LightamerSlider）**仍然正确且覆盖更广**——
yiyin 面板三行用 LightamerSlider，本就落在「177 调用点」（实测 grep 全 App
恰 177 处 ✓）之内，scrub 自动受益。错的只是勘注文字与 read_first 动作。

**处方**：①T3 read_first 句改「实测 3 调用点在册（:160/:182/:203）——
LightamerSlider 单组件修复使 yiyin 面板同样受益」；②T6 REQUIREMENTS 勘注改
「UQ-L1 范围 = LightamerSlider 全部调用点（iop + yiyin 面板族，177 处）」；
③CONTEXT/RESEARCH 原句留痕勘误随 DECISIONS 申报（晨审可见）。

---

## Minor

### m1 — 「legal SDR 9 对」实为 8 对

清单逐项枚举 = rec709×{bt1886,gamma22,srgbPiecewise}(3) + p3d65×{gamma22,
srgbPiecewise}(2) + p3d60×gamma26 + p3dci×gamma26 + xyz×gamma26(3) = **8**。
`DrtRecord.swift :448-459 legalEOTFs` 亲验：SDR 集同为 8（rec2020 仅 HDR 两
档；gamma18 不在任一 legal 集——域外回落负腿选对）。错标出现 4 处（front-
matter SC T2「9 对逐对」/ T2 action 3 / ΔN 表 / EditorPreviewColorSpaceTests
行）。清单本身正确，仅计数标签错。处方：四处「9 对」→「8 对」。

### m2 — T1「git diff --stat 恰五产线/测试文件」实为 6

括号自列：McpServerController + LightamerApp + AgentControlCoordinator（3 产
线）+ 三测试文件扩法（McpHostTests / McpSearchStateToolsetTests /
AgentControlCoordinatorTests）= **6**；可选腿 McpControlToolsetTests 执行则
7。机器判据「恰五」对自然实现必假失败。处方：改「恰六（可选腿执行则恰七，
DECISIONS 申报）」。

### m3 — 「mcp-endpoint.json schema v1 七字段」实为 9 字段

`McpEndpointInfo`（McpEndpointFile.swift :62-72）声明 9 属性：
schemaVersion / transport / host / port / pid / startedAt / serverName /
serverVersion / auth。RESEARCH §1.1 即错、plan 承接并安排写进 SKILL.md §1
（「七字段」），将成 agent 文档假事实（T4 机检不查字段数，必漏）。处方：
SKILL.md 写 9 字段，或不落硬数改按「schema 标记 + 传输五元组 + 服务标识 +
auth 标记」分组描述。

### m4 — UQ-L1 SC 翻账降格未登记

ROADMAP :110 定式「UQ-L1 交互走查 ✓」vs T6 计划写「UQ-L1 走查配方就绪 ✓
〔实机走查归验收批〕」。M7-5 TURN-02「配方就绪归验收批」先例在案，但站级
VALIDATION 以 `status: validated` 签核时，SC 表判定式与 ROADMAP 原文的措辞
差应在 T6 ⑤制度偏离登记节显式加一句（第三件制度注记），否则晨审对账
SC 表 vs ROADMAP 出现未解释降格。处方：T6 action 1 ⑤补一句。

### m5 — lightcraft「拖离取消不留残值」语义静默丢弃

RESEARCH §3.1 交互语义清单明确含「拖离取消不留残值」（ab64e9a5）；plan T3
action 只落 ≥3pt / Shift ×0.1 / clamp / 一个 undo step 四条，未提拖离取消，
也未申报让渡。SwiftUI DragGesture 生命周期（onChanged per-tick 已落 live 值、
onEnded = 释放点）确实无法等价实现 lightcraft 自绘 widget 的取消语义，让渡
合理——但按本仓纪律该让渡要显式申报。处方：T3 回滚与偏差申报要求加一条
「拖离取消语义 = SwiftUI 生命周期不等价，DECISIONS 申报让渡」+ T5 MANIFEST
观察行登记。

---

## 评审清单逐项结论

1. **目标覆盖**：✅ 六项全被 T1-T6 覆盖且验收标准大体可机检；ROADMAP :110
   四判定式 ↔ 任务面映射无孤儿项（skill 机检 = T4 法1 / UQ-A1 等值 = T2 /
   UQ-L1 走查 = T3+T5 MANIFEST / SC 数字门 = T5 对账）。T6 六节 + M7-5
   §signed 节 + 挂账清算面（N2-2/S-2/obs-A C12/FIX2③/union 归还）构成可签
   核收口证据——唯 m4 的 SC 降格登记与 M1/M2 修后才能成立。
2. **坐标与事实抽查**：25 处 read_first file:line 亲验全数落点（含
   :482/:497 裸臂、:227-240 等待循环、:760 幂臂、DrtOutputColorSpace
   :53-141、:277 private、:72-74 onReset 等）——**行号全部吻合**；但两处
   「构成」级事实错误（M1/M2）与三处计数错（m1/m2/m3）说明 plan 的「逐点
   亲核」只核了行号未核基数/结构。
3. **红线正确性**：FIX2③ 勘正①成立（M7-5-CONTEXT :125/:241/:274 +
   ACCEPTANCE :110 「diff 0 行」亲证正义 = LibraryProjectController 零
   diff，plan 表述准确）；封存面 17 件清单可机检；union 串行 + private→
   internal 一行申报自洽（:277 亲验 private 实例方法，internal 后跨测试文
   件经实例调用可达）；`String.LocalizationValue` 插值禁形与 xcstrings 尾块
   纯插入**已写入**红线族（无该写未写）；`.runModal` 零命中实测在位。
4. **测试设计**：T1 腿①真宿主（startHTTPHost(admit:) stub → dispatch 门）
   真证接线非 fixture 自证 ✓；T2 等值腿非恒绿（actual = App 函数、expected
   = Core 封存函数，回归 calibrated 臂即红；同实例→字节同收敛逻辑成立，且
   依赖 T2 的 Core 零 diff SC 兜底——可接受）；T3 session 纯值类型缝 =
   M3-1 YiyinSheetDragSession 同款 AC 可机检范式 ✓；T4 法1 逐字节即门真拦
   tools.md 漂移 ✓。唯一设计缺陷 = B1（腿清单缺 resume 负腿 + 修法本身错）。
5. **ΔN 预算**：+12（带 8..13）算术自洽（5+2+3+2=12；下限 3+2+2+1=8；上限
   5+2+4+2=13）；逐任务构成现实，无重复计；B1 处方若增 resume 负腿则 T1 上
   限 6 → 合计 13 仍在带内。基线 3950/35/0 与 zh-audit 1708 实跑吻合。
6. **任务序与回滚**：T1→T6 依赖序成立（T4 的 internal 一行不与 T1 测试扩法
   冲突——不同文件）；每任务回滚 = revert 单 commit + 偏差申报条款齐备；
   六条 commit 草稿全英文 Conventional（fix/fix/feat/feat/test/docs）✓。
7. **Planner 自报五条勘正**：五条全成立——①FIX2③ 正义 ✓（正本回查）②七节
   从严 ✓③plain-await 形 ✓（:1634-1637 注释亲验在位）④private :277 ✓
   ⑤schema 全文从严 ✓；obs-3 锚微差（:215-217/:228-231）亲验精确。但亲核
   批漏了 M1（结构）与 M2（grep 假阴性）——「行号逐点吻合」≠「事实吻合」。
8. **遗漏**：RESEARCH/CONTEXT 信息无实质丢失（走查观察项、制度偏离、挂账
   清算、晨审推翻点索引全数入 plan）；缺口 = m5（lightcraft 语义让渡未申
   报）与 m4（SC 降格未登记），均已给处方。

## 放行条件

修 B1（obs-3 修法与 SC + resume 负腿 + SKILL.md 语义句）、M1（装配点计数
构成）、M2（yiyin 勘注翻转）三处 plan 文本后即可进执行；m1-m5 可随批顺手
改（均为数字/措辞级）。修法全部落在 plan 文本层面，零产线设计翻案
（OQ-M7-6-1..10 裁决全部维持），零源码触碰。

```
评审证据正本：本文件 §Blocking/§Major/§Minor 各条 file:line 均为 2026-10-17
HEAD 5449ad57 工作区亲验；zh-audit --check PASS(1708) 实跑在案。
```
