# M7-5-CHECKER — M7-5-01 plan 修订批独立反向核

```
phase:      m7-5-turn-taking
reviewee:   M7-5-01-PLAN.md（修订后）+ M7-5-CONTEXT.md（两条勘注）
            ——fixer 批 commit 91e1c20f（docs(m7-5): revise plan per
            review — call-site wiring, three-window wait, nine register
            sites；plan +229/−126 + CONTEXT 两注）
checker:    独立 checker（ZCode；fixer+checker 合批 worker 的 checker 半，
            目标反向——不信 fixer 面，代码面重新 grep 亲核）
method:     Goal-backward（ROADMAP §M7-5 四验收形态 ↔ 任务面逐项映射）+
            三项核心修订自洽（F1 形 B 七点清单完备性 / F2 三窗 OR ×
            D-H1 trio 交互 / F3 九调用点 × 13 工具覆盖矩阵——每项独立
            grep 码面重验）+ 修订批 F1..F12+3info 逐条落位对表 +
            新鲜眼全文残漏扫描（改后全文重读 T1..T7 + front-matter
            YAML 结构机检）
verdict:    PASS — 放行（0 blocking / 0 major / 1 minor〔checker 亲修：
            T1 验收文件数算术滑差 七→八，随本 commit 落〕；
            4 项观察记录在案，均零动作）
```

## 一、结论头

**放行。** 修订批（91e1c20f）把评审 12 findings + 3 info 全部落位，
三项 orchestrator 裁定形（F1 形 B / F2 三窗 OR / F3 九调用点口径）经
checker 独立码面重验全部自洽且完备；OQ 裁决链（D-M7-5-1..10）未被
重开（CONTEXT 仅两条不触裁决的载体/缺席勘注）。新鲜眼捕获 1 处评审
双漏（fixer 与 review 均未抓）的既存算术滑差，已随 checker commit
亲修。修后 plan 可直接放行 T1..T7 执行（夜间全自动授权在案不变）。

## 二、核心修订自洽（三项裁定形逐项独立重验）

### 2.1 F1 形 B 七点清单完备性（独立 grep 重验）

- **生产调用点全清单独立扫描**：`startHTTPHost` / `startHeadlessStdioHost`
  / `startReadOnlyHTTPHost` / `startEmbeddedIfPreferenceEnabled` 在
  `App/Sources` 全域 grep（排除定义行）——`McpServerController.swift`
  之外唯一调用点 = `LightamerApp.swift` :1608（:1262 为注释引用）；
  SettingsPages 面 :1242/:1265 经 `startEmbeddedServer()`（:1102→:1111）
  收敛，不另需接线点。**七点清单闭合无遗漏**：
  `:461`（runHeadless stdio 臂）/:471（http 臂）/:584/:596/:617
  （arbitrated 三臂）/:1120（startEmbeddedServer box 读出）/:1608（GUI
  内嵌臂 coordinator-backed）。
- **五钉保绿路径成立**：McpHostTests 直调点 :230/:270/:291/:333/:358/
  :628/:684 + InMemory 臂 makeRegistry 四参直调（:707-712 段）——形 B
  下 fixture 显式不传 control（缺省 nil）→ :243/:697 两枚 23 计数钉 +
  :719 InMemory≡HTTP 等值断言全部保绿；`McpLauncherTests :200` /
  `McpSearchStateToolsetTests :274` / `McpRegistrySnapshotTests :223`
  骑 makeRegistry/registry 直调面，与宿主签名无关，零波及。红线⑤
  「union 外五钉 23 断言零触」在形 B 下可满足（review F1 指出的
  「形 A 必破钉」矛盾已消解）。
- **缺省 nil 防堵条款（择形申报）**：按 orchestrator 二选一授权，
  fixer 择 **装配点全清单 grep 机检**（主门，T4 验收 ①②③④⑤：
  makeHeadlessControlContext 恰 1 定义 + 恰 3 调用点〔runHeadless 两臂
  + arbitrated 共享点——GUI/Embedded 臂零命中〕+ 七点 `control:` label
  逐点在位 + 三宿主函数体 + startEmbeddedServer 函数体内零命中 +
  McpHostTests fixture 不传 + 五签名 diff 面核），辅以 **get_state
  无头臂 agent 键恒真面**（运行时自证通道，T6）。checker 复核：择形
  理由成立（grep 是静态机检面、可入 T4 验收门；get_state 恒真面是
  运行时通道、防未来回归）——双门互补，防堵条款在 T4 action 2 +
  验收 + DECISIONS 申报项三处落位，future-proofing 句（「未来新生产
  宿主调用点须过 T4 七点清单」）在案。
- **T1/T4 分工缝自洽**：T1 = 五签名（makeRegistry + 三宿主 +
  startEmbeddedIfPreferenceEnabled）+ EmbeddedState box control 字段
  （存 :1089 / 读 :1111）就位、透传参暂 nil 保编译绿；T4 = 恒真面 +
  七点接线。函数体只转发（体内零恒真面装配）与 M7-3 searchState/
  project 第四参先例同形——签名批与接线批分离后 union fixture 面在
  T1..T5 期零变化，无中间红灯。

### 2.2 F2 三窗 OR × D-H1 trio 交互（独立枚举重验）

- **窗口清单完备**：PipeCoordinator 全域 `isEditing*` 独立枚举 = 恰三
  private Bool 族——`isEditingContinuous` :167（D-H1 窗：begin :1771→
  置位 :1772 / commit :1815→复位 :1818）、`isEditingDrt` :748（begin
  :737-738 / commit :725-726）、`isEditingFilm` :933（begin :922-923 /
  commit :910-911）。**无第四窗**——OR 覆盖完备。
- **交互面**：计算属性读同类三 private 值零访问面问题；OR 形零新可变
  状态 = 零配对计数风险（评审 F2 指出的「视图拆卸丢 commit → 深度
  永久 >0 → acquire 永久失能」脆弱性结构性消除）；嵌套窗不存在
  （review 亲核全部调用点严格配对在案），OR 语义在重叠场景亦安全。
- **机理申报改写到位**：T2 action 2 引 DrtPanelModel :24-25 头注
  （「Peak slider runs the D-H1 trio」——checker 复读原文吻合）+
  FilmPanelModel :193/:229（beginFilmEdit/commitFilmEdit 调用点亲核
  在位）；原「DRT/Film 无拖动连续态」假机理句已全文清除（grep 零
  残留）。
- **联动面**：T2 验收 grep（liveEditActive 恰一定义）、T6 action 3
  acquire 三态三腿（D-H1/DRT/Film 各注入 stub provider——无 GUI
  依赖）、T7 红线族机检（「PipeCoordinator 恰 additive liveEditActive
  计算属性」）、red_lines 封存面条目、SC T2、Checker 关注点 #7——
  七处消费点全部同批翻转，无 liveEditDepth 残留消费（grep 全仓 app 面
  零命中；仅存的 4 处字面 = 遗留面登记与勘注本身，语义正确）。
- **liveEditDepth 遗留面登记**：T2 action 2 专段（V2/后续 + 触发机理
  + 引入前提「嵌套窗 + 泄漏守护」）+ files_modified DECISIONS 行 +
  CONTEXT D-M7-5-7 载体勘注（裁决不重开声明）——三处落位一致。

### 2.3 F3 九调用点 × 13 工具覆盖矩阵（独立逐一重验）

| # | 文件 | register 调用点 | 工具覆盖 | checker 亲核 |
|---|---|---|---|---|
| 1 | EditingToolset | :142 | load_image | descriptor :143 `loadImageDescriptor` ✓ |
| 2 | EditingToolset | :147 | apply_params | :148 `applyParamsDescriptor` ✓ |
| 3 | EditingToolset | :161 | paste_adjustments | :162 ✓ |
| 4 | EditingToolset | :221 | export_image | :222 ✓（**勘正**：评审 F3 写 :218，实测 :221——plan 已用实测值） |
| 5 | CullingToolset | :326 段 | write five（set_rating/set_flag/set_color_label/append_note/set_keywords） | helper `registerOne` :321 / register :326 / `requiresWriter: true` :338 同参位邻接可加 ✓；:369/:387/:405/:423/:436 五次 registerOne 进入 ✓ |
| 6 | CullingToolset | :516 | apply_preset | :517 descriptor `apply_preset` / :529 requiresWriter ✓ |
| 7 | MatchColorToolset | :164 | match_color | ✓（唯一 register 点） |
| 8 | ProjectToolset | :139 | project_open | :141 name 行 ✓ |
| 9 | ProjectToolset | :202 | project_create | :204 name 行 ✓ |

- **13 = 4+5+1+1+2** 算术闭合；面外件零误伤：EditingToolset :156
  （copy_adjustments）/:167/:176（list_iops/list_luts）/:1274、
  CullingToolset :242/:470/:631/:706/:794/:820/:1170/:1275（preset
  trio/image trio/bursts/faces/diff_presets 族）、ProjectToolset :292
  （list_versions——checker 亲核 name 行 :294）全部零触。
- **「禁拆五件为独立 register」条款**在 T1 action 5 显式在位（helper
  体零 churn）；13 工具逐名覆盖断言归 T6 registry 层（Entry.requires
  Control 逐名断言）——SC 口径「9 处字面量 + T6 逐名覆盖」双层闭合，
  review F3 的「SC 机检必假失败」与「诱导拆 register」双风险均消解。

## 三、Goal-backward 反向核

- **ROADMAP §M7-5 四验收形态映射**（修后不变，逐项复核在位）：双端
  fixture → T6 action 2（GUI typed 拒 + Stop 失权）+ action 4（无头恒
  持有负测）；GUI 活动卡走查 → T3 + T7 MANIFEST 配方；Stop→resume
  活动连续 → T6 action 6（含 F8 新增 Stop 留列表断言）；无头恒持有
  → T6 action 4。TURN-01..04 四行无孤儿（TURN-01=T1+T2 / TURN-02=T3
  / TURN-03=T3 / TURN-04=T4）。
- **OQ D-M7-5-1..10 兑现面未收窄**：F2 载体形变更不触 D-M7-5-7 裁决
  本体（等待 + 10s + 注入短窗原样——CONTEXT 勘注显式声明「裁决不
  重开」）；F5 缺席申报不触 D-M7-5-4 全表裁决（12 语义面清单不变，
  落点如实 11+1）。其余八项 OQ 的任务面在修订批零触碰（逐项 diff
  对表：SC/红线/action 中 OQ 相关字面无删改）。
- **算术链**：estimated_tests 组成 10..13 + 8..12 = **18..25** =
  ΔN 带 = expected_all 3943..3950 = 头注基线段——四处同值闭合
  （F9 勘正一致）；`--all` 对账式 TOTAL|3925+ΔN/35/0| 保持非死数。

## 四、F1..F12 + 3 info 逐条落位对表

| # | 裁定 | 落位（plan 修订后位置） | checker 验法 |
|---|---|---|---|
| F1 | 形 B | T1 action 6（签名批）/ T4 action 2+验收（七点接线 + 防堵）/ red_lines ②（五钉保绿形 B 注）/ SC T1+T4 / DECISIONS 申报项 | §2.1 独立 grep |
| F2 | 三窗 OR | T2 action 2（属性 + 机理改写 + 遗留面登记）/ T2 验收 grep / T6 action 3 三腿 / red_lines ⑦ / SC T2 / T7 红线族 / CONTEXT D-M7-5-7 勘注 | §2.2 独立枚举 |
| F3 | 9 处字面 | T1 action 5（矩阵 + 禁拆条款）/ SC T1 / files_modified 四 Toolset 行 / Checker 关注点 #2③ | §2.3 逐点亲核 |
| F4 | 无自动红窗 | 头注执行序段 / T2 action 3 / T5 action 4 / T6 引言+action 10（:902 断言新法）/ 风险节第 1 条 / SC T6 / SUMMARY 行 / DECISIONS 行 / Checker 关注点 #3 | get_state control 面断言逐键形码面复核（:910-911/:965-968/:985 逐键取值——无键集/golden 断言）亲验成立 |
| F5 | Undo/Redo 真身 + delete 缺席 | T2 read_first（:1906-:1918）+ action 4 ⑤⑨ + action 5 / files_modified（LightamerApp 行扩、MenuCommandSet/LibraryGridView 两行删）/ SC T2（11 实落点 + 缺席申报）/ 风险节第 2 条 / CONTEXT D-M7-5-4 勘注 / DECISIONS 行 | LightamerApp :1906 `CommandGroup(replacing: .undoRedo)` + :1913/:1918 `.disabled(!canUndo || isReadOnly)` 合并形亲读吻合；全 App 无图库删除路由复核成立 |
| F6 | message switch | T1 action 3 + 验收 grep（每名 3 处）+ diff 逐 hunk（message 连绑×1）/ SC T1 / Checker 关注点 #4 | McpToolRegistry :110-120 逗号连绑列表亲读吻合 |
| F7 | 16 件面外 | T6 action 2（16 件 + diff_presets 显名 + list_* 六件） | diff_presets CullingToolset :633 亲核在码 |
| F8 | Stop 绕 registry.cancel | T3 action 4（handle.cancel 直呼 + 禁入条款）+ 验收 grep / T6 action 6 留列表断言 / Checker 关注点 #6 | registry.cancel :94-98（cancel+finish 移除臂）+ bar :99/:150 既有路由亲核吻合；register :77-80 id 去重 = resume 幂等亲核 |
| F9 | 带 +18..25 | estimated_tests / expected_all / 头注基线段 | 10..13+8..12 = 18..25 = 3943..3950 算术闭合 |
| F10 | 第六缝编号注记 | files_modified DECISIONS 行 + T7 action 6 | EmbeddedState 字段序 editing/culling/searchState/project/control = control 第 5 context 字段亲核（:1174-1185） |
| F11 | beginCommand 措辞 | SC T2 + files_modified AgentControlCoordinator 行（边界驱动闭形句） | 残漏 grep 零命中（仅存「无独立 beginCommand API」否定句，语义正确） |
| F12 | init 依赖枚举 | T2 action 1 + files_modified + Checker 关注点 #7 | — |
| info×3 | — | 随 F10/F11/F12 同批（T7 DECISIONS 行） | — |

## 五、新鲜眼独立猎残（checker 自有扫描结果）

1. **[minor——checker 亲修，随本 commit]** T1 验收「`git diff --stat`
   恰**七**产线文件」——枚举 ControlToolset 新建 + McpToolRegistry +
   四 Toolset + McpServerController + xcstrings = 1+1+4+1+1 = **8**。
   既存算术滑差（review F1..F12 均未覆盖该数字；fixer 批亦未触）。
   已改「恰八」并注 CHECKER 勘正来源。
2. **[观察，零动作]** files_modified `McpSearchStateToolsetTests` 行
   注释含 `control[\"agent\"]` 转义形——YAML 列表注释面（# 后）转义
   非必需但无害；SC 行（YAML 双引号标量内）转义为必需形（line 9
   quote 配对机检 = 2，标量完好）。front-matter 结构机检：12
   red_lines / 38 files_modified（原 40 − 2 死条目）/ SC 标量引号
   配对——全部通过。
3. **[观察，零动作]** T6 commit message「pin the goldens」语义仍
   成立——union/域快照 verbatim golden 面仍存在，仅 get_state 面
   无既有 golden（F4 勘正范围 = get_state 断言面，非 golden 概念
   全域）。
4. **[观察，零动作]** baseline 注记「HEAD cbad16eb」指**代码基线**
   （其后 review/修订/CHECKER 三笔 docs commit 零产线文件漂移）——
   执行期对账 TOTAL|3925+ΔN/35/0| 以代码面为准，docs-only 链延长
   不影响基线语义；executor 无需动作。

## 六、SC 可机检性抽核（修订后）

- F3 后 T1 验收 grep 判据（每名 3 处 / requiresControl registry 恰 3
  处 / 四 Toolset 恰 9 处 / ControlToolset 零显式）——全部命令级
  可执行，无「目测」面。
- F1 后 T4 验收七项（①..⑦）——grep + diff 面核逐条可执行；七点
  坐标给到行级（:461/:471/:584/:596/:617/:1120/:1608）。
- F4 后 T6 action 10 判据改为「:902 扩 agent NSNull 腿 + 真值腿 +
  既有三键断言零触」——比原「golden 显式改」更可机检（原判据指向
  不存在的 golden，必假失败）。
- F9 后 ΔN 带与组成对账式闭合（§三算术链）。

## 七、放行声明

- **放行 T1..T7 按修后 plan 执行**（夜间全自动授权在案不变；
  `--all` 批准制照旧）。
- **零再修项**：评审 12 findings + 3 info 全部落位；checker 新增
  1 minor 已亲修；4 项观察零动作。
- **执行期注意（非阻塞）**：①T4 七点清单执行时逐点亲核如实申报
  （坐标行级在案，若上游代码漂移以 grep 亲点为准）；②T2 禁编辑
  11 实落点执行时 grep 亲点后如实申报（review 已核 10/12 在位 +
  F5 勘正面）；③liveEditActive provider 闭包在装配点喂
  `pipeCoordinator.liveEditActive`（属性非方法——勿加 `()` 调用
  语义混淆）。

```
checker 签名批：docs(m7-5): CHECKER pass on revised plan（本 commit
含 §五-1 的 T1 验收文件数亲修 + 本 CHECKER.md）
```
