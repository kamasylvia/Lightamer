# M7-6-01 PLAN CHECKER — 执行前独立复核（只读 + 本报告唯一产出，零源码触碰）

```
phase:        m7-6-station-close
checker:      独立 checker subagent（ZCode；2026-10-13/17）
对象链:       M7-6-01-PLAN.md + M7-6-CONTEXT.md（fixer 后 HEAD cae4e825）
              vs 评审正本 M7-6-01-PLAN-REVIEW.md（e61185b0）8 条 finding 处方
method:       产线源码逐点独立亲验（不信任 fixer 自述、不信任评审数字）——
              AgentControlCoordinator acquire/stop/admit 全函数控制流逐态亲演
              （B1 三态走查：resume 主路径 / Stop-in-final-window / 异 holder
              交错 + alreadyHeldBySelf 不可达论证）；McpServerController
              setWriterCheck grep 恰 3 处 :737/:819/:1081 + startEmbeddedServer
              :1165-1202 全文（无自有 registry、:1176 委托 startHTTPHost）+
              :482/:497 裸臂 + :603-606 arbitrated 臂拼写 + :1046-1065 Bearer
              阀；McpToolRegistry :335/:367/:385-408 装配序（writer→control→
              handler + writeCallCount 只挂 writer 门）；legalEOTFs（DrtRecord
              :448-459）与 DrtOutputColorSpace :53-141 legal 表双侧镜像亲演
              8 对；YiyinPanelView grep LightamerSlider( 实测 8 处逐行读源；
              全 App 177 处 grep 吻合；EditorMTKView :709-811 SDR 幂臂/HDR/
              linear/drtSurfaceSpec 全形；LightamerSlider :18-81 全文（D-H1
              三回调 :30-37 + readout :65-69 + AX :47/:63/:69 + onReset
              :72-74）；McpEndpointInfo 9 字段；McpToolError 19 case 计数；
              requiresControl 13 工具亲演（9 注册点——culling 元数据助手一盖
              五 + editing 4 + match_color 1 + project 2）；LightamerApp
              :1630-1651 plain-await 先例；测试锚点 :194/:253/:473/:1015/
              :270-272/:277 全落；ROADMAP :110 M7-6 行在位；fixer diff 26
              hunks 全部 "+grep 提取行号主张" 逐一对照源码（:1081/:215-217/
              :227-240/:228-231/:248/:722/:786/:1035/:1137/:1165/:1176/
              :1143-1150/:367/:603-606/:482/:497/:734-748/:804-811/:178-268/
              :248-267/:248-259/:1046-1065/:110/ControlToolset:20——全吻合）
verdict:      退回 / 2 residual（均 minor 级、文本一行修；B1/M1/M2 语义修
              本体 + m1-m5 全部落点正确——残留为 fixer/评审自身带入的两处
              可证伪计数/算术，经产线源码与算术重导抓出）
```

**一句话结论**：八条 finding 的修法本体全部正确落位（B1 语义亲演 resume
可达、busy 臂无条件安全；M1 构成=源码构成；m1-m5 全落且超额清扫干净）；
但 fixer/评审带入两处可证伪残留——①M2 翻转文本的「yiyin 3 处 ：160/:182/
:203」为假（实测 8 处，将随 T6 写入 REQUIREMENTS 唯一事实源，M2 同害级）
②ΔN 带 +8..13 未随 B1 的 T1 带 4..6 重导（组件带和实为 +9..14，合法落点
14 会假触「越带申报」门，m2 同害级）。两处均一行修，修后即可放行。

---

## 结论头

**退回 / 2 residual**

| # | severity | 一句话 | 位置 |
|---|---|---|---|
| R1 | minor（害级同类 M2） | 「yiyin 3 处 ：160/:182/:203」为假——`YiyinPanelView.swift` 实测 **8 处** `LightamerSlider(` 调用；假计数将随 T6 写入 REQUIREMENTS | PLAN T3 read_first（:344-346）+ files_modified REQUIREMENTS 行（:52）+ CONTEXT D-M7-6-5 |
| R2 | minor（害级同类 m2） | ΔN 带 **+8..13** 未随 B1 预算重导——组件带和实为 **+9..14**（T1 4..6 + T2 2 + T3 2..4 + T4 1..2）；合法落点 14 假触「越带申报」门、8 为死边 | estimated_tests（:10）/ expected_all（:13）/ 头注基线段（:105-106）/ ΔN 表（:112+:120）/ T5（:480）/ checker 节 9（:650） |

### R1 处方

PLAN 三处 + CONTEXT 一处的「3 处（:160 blur / :182 main_rate / :203）」改
「8 处（:160 blur / :182 main_rate / :203 min_margin / :235 corner_radius /
:268 shadow / :380 logo_opacity / :393 line_spacing / :589 font_size——
grep 实测 file 内恰 8）」；REQUIREMENTS 行「yiyin 三处 :160/:182/:203 实测
在册」同步改「yiyin 八处（grep 实测在册）」；CONTEXT D-M7-6-5 勘误句内
「实测 3 处」同步（嵌套括号随批理顺）。方向性结论不变且更强：单组件修复
使 yiyin 面板族受益、三处/八处全落 177 调用点内。fixer 系照抄评审 M2 处方
原文（处方本身即错数）——非 fixer 执行偏差。

### R2 处方

六处带边 +8..13 / 3958..3963 改 **+9..14 / 3959..3964**（estimated_tests /
expected_all / 头注基线段 / ΔN 表行+合计行 / T5 note / checker 节 9）；
预期值 +13 / 3963 不变（6+2+3+2=13 仍在带内）。备选：收紧 T3 带上缘
（2..4 → 2..3）并以 DECISIONS 申报理由维持 +8..13——两形取一，禁静默。
病灶上游：评审第 5 条「B1 处方若增 resume 负腿则 T1 上限 6 → 合计 13 仍在
带内」只核了预期值未重导带边——pre-B1 带（T1 3..5 → 8..13）被冻结带入。

---

## 一、8 条 finding 逐条对账（评审处方 vs fixer 落点）

| # | 处方要点 | fixer 落点 | 判 |
|---|---|---|---|
| B1-1 | 快照+条件复检修法（`stoppedAtEntry` + revoked 臂 `!stoppedAtEntry` 才拒；busy 臂保持无条件） | T1 action 4 重写（:211-225）+ SC（:9）+ files_modified Coordinator 行（:29）+ 红线受限面（:17）+ T1 标题/引言（:166/:168） | ✅ **语义亲演 PASS**（见下节） |
| B1-2 | resume 不断裂负腿 | T1 action 5 ⑤（:240-242）+ files_modified AgentControlCoordinatorTests 行 ③（:39）+ ΔN 5→6（:10/:116/:120） | ✅ |
| B1-3 | SKILL.md §2 诚实面半句 | T4 action 2 ②（:433-437）+ files_modified SKILL.md 行（:33） | ✅ |
| M1 | 生产调用恰 3 点 + grep 构成 5 处（定义+头注+3 调用）+ embedded 单点装配 | SC（:9）/ files_modified McpServerController 行（:27）/ T1 action 1（:193-199）/ T1 read_first（:178）/ T1 验收 grep（:248-250）/ 风险节（:586-589）/ checker ⑦（:623）/ CONTEXT D-M7-6-7 勘误 | ✅ 源码构成吻合：`setWriterCheck` 恰 3 处（:737/:819/:1081 亲验）；startEmbeddedServer :1165 无 registry、:1176 委托 startHTTPHost（全文亲验）；App/Sources `setControlAdmit` pre-fix 恰 2 处（定义 :367 + ControlToolset :20 头注）→ post-fix 5 处构成成立 |
| M2 | 三处传播翻转（yiyin 有滑杆、范围=iop+yiyin 面板族） | T3 read_first（:344-346）/ REQUIREMENTS 行（:52）/ DECISIONS 行（:49）/ CONTEXT D-M7-6-5 勘误 | ⚠️ **方向翻转正确、计数残留 = R1**（实测 8 处非 3 处） |
| m1 | 「9 对」→「8 对」 | SC（:9）/ estimated_tests（:10）/ files_modified 测试行（:40）/ ΔN 表（:117）/ T2 action 3（:297-309）/ T2 验收（:315-316） | ✅ grep「9 对」零残留、8 对 ×9 处；legalEOTFs + DrtOutputColorSpace 双表镜像亲演 8 对（rec709×3 + p3d65×2 + p3d60/p3dci/xyz×gamma26 各 1；rec2020 仅 HDR 两档；gamma18 域外）逐对吻合 |
| m2 | 「恰五」→「恰六（可选腿则七）」 | T1 验收第 1 条（:245-247） | ✅ grep「恰五」零残留；六文件构成与 files_modified 行一致 |
| m3 | 「七字段」→「九字段」 | files_modified SKILL.md 行（:33）/ T4 read_first（:411-412）/ T4 action 2（:429-430） | ✅ grep「七字段」零残留；`McpEndpointInfo` 9 属性亲验（schemaVersion/transport/host/port/pid/startedAt/serverName/serverVersion/auth） |
| m4 | T6 制度注记第三件 | T6 action 1 ⑤（:549-556）+ front-matter SC（:9） | ✅ ROADMAP :110 M7-6 行「UQ-L1 交互走查 ✓」原文在位，降格注记语义成立 |
| m5 | 拖离取消让渡显式申报 | T3 回滚条款（:391-395）+ T5 MANIFEST 观察行（:509）+ files_modified MANIFEST 行（:47） | ✅ |

## 二、B1 语义亲演（对照产线源码逐步走查）

`App/Sources/Lightamer/State/AgentControlCoordinator.swift`（HEAD cae4e825
工作区 = 产线零 diff，fixer commit docs-only）：

- **写点亲验**：`stoppedByUser` 全文件仅两写点——`:259 false`（acquire 成功
  唯一清零点）/ `:294 true`（stop()）。与评审事实链一致。
- **resume 主路径亲演**（Stop 后同 holder re-acquire）：stop() 置
  `held=false ∧ stoppedHolderName=holder ∧ stoppedByUser=true` → agent
  `acquire(holder)` → `:216` 入口 busy 检查 `held==false` 放行 →
  `:221 alreadyHeldBySelf=false` → 等待段入口快照 `stoppedAtEntry=true` →
  `:227 while liveEditActive()` 无未封合编辑输入时循环体零执行 → 条件复检
  revoked 臂 `stoppedByUser ∧ !stoppedAtEntry` = `true ∧ false` = **不触发**
  → busy 臂 `held==false` **不触发** → `:248-256 resumeSameTask=true`
  （stoppedHolderName==holder ∧ taskId/handle 非 nil）taskId 复用 →
  `:259` 清零 → resume 可达。**B1 病灶（永久锁死）被处方真解。**
- **Stop-in-final-window 变体**：最后一轮 poll 时窗内 Stop（循环内 `:228`
  检查已跑过、`stoppedByUser` 翻 true 后循环条件翻转退出）→ 复检点
  `stoppedByUser=true ∧ stoppedAtEntry=false` → throw controlRevokedByUser
  ✅ 不再静默吞；且后续 re-acquire 快照翻 true → 放行，无锁死。
- **busy 臂无条件安全性亲演**：能到复检点时 `held==true ∧ holderName !=
  holderName` 只可能是 `:216` 预计算后等待/挂起期间他 holder 抢到（`:216`
  已拒当时在持异 holder）→ throw busy 恰为想要行为；alreadyHeldBySelf
  路径（held=true）走不到等待段，且 `held=true ∧ stoppedByUser=true` 状态
  不可达（`:257` 置 held=true 的唯一路径 `:259` 同步清零；stop() 置
  stoppedByUser=true 时必置 held=false）——快照/复检无论置于
  `if !alreadyHeldBySelf` 块内外皆安全。✅
- **:214 判读成立**：复检插入点（循环退出后、`:248` success 之前）与源码
  结构精确对位；`:248-259`（清零段）与 `:248-267`（success 全形）两种区间
  引用均与源码吻合，非矛盾。

## 三、fixer 自报 4 项新矛盾核验

1. **m1 超额出现（修 5 处非评审所列 4 处）**：✅ 成立——grep「9 对」全文件
   零残留；8 对 9 处分布 SC/estimated_tests/files_modified/ΔN 表/T2
   action/T2 验收，全数语义正确。
2. **m3 超额出现（修 3 处非 2 处）**：✅ 成立——grep「七字段」零残留；九
   字段 4 处全对（源码 9 属性亲验）。
3. **「四宿主」保留处**：PLAN 3 处（:4 标题「四宿主透传参案」/ :18 FIX2③
   「四宿主签名批」/ :623 checker ⑦「四宿主签名批〔4 admit: 缺省参〕+ …
   恰 3 点」）+ CONTEXT 2 处（:127 枚举四签名宿主 / :136 勘误引用原文）。
   ✅ **逐处核实均属签名批语境（4 个 `admit:` 缺省参 + box 字段确实四宿主）
   或勘误引文，零安装点构成残留**。fixer 自报计数「4 处」与实际留存 5 处
   不严格对账——bookkeeping 观察（note），非缺陷。
4. **PLAN :214 判读**：✅ 成立（见 §二 末条）。

## 四、行内标记完整性

实测 PLAN 内 `review *` 标记 **44 处**（B1×20 / M1×6 / M2×4 / m1×6 / m2×1
/ m3×2 / m4×2 / m5×3；任务书按 48 计为口径差——CONTEXT 5 处与头注 round-1
引用段的计入与否，note 登记）。**抽核 18+ 处标记-内容一致性全数一致**（:
4 标题 B1 三行 / :9 SC M1+M1grep+m1+B1 / :10 estimated B1 5→6+m1 / :17
红线 B1 / :27-29 files_modified M1+B1 / :33 m3+B1 / :40 m1 / :47 m5 / :52
M2 / :116-120 ΔN 表 B1+m1 / :178 read_first M1 / :197-199 action1 M1 /
:211-225 action4 B1 / :240-242 腿⑤ B1 / :247 验收 m2 / :255 验收 B1 /
:297+:308 T2 m1 / :344-346 T3 M2 / :391-395 m5 / :429-430+:435 T4 m3+B1 /
:480 T5 B1 / :509 m5 / :552-556 T6 m4 / :586-589 风险 M1 / :623+:633
checker M1+B1）。**无标记相邻改动零评审外新方案发明**（CONTEXT 就地勘误
注记 = M2 处方③「原句留痕勘误」的忠实形态，RESEARCH 上游以 CONTEXT 勘误
为准的从属声明合理）。

## 五、数字一致性

- **ΔN 五处同步**：estimated_tests（:10）/ expected_all（:13）/ 头注基线
  段（:105-106）/ ΔN 表（:112+:120）/ T5（:480）「+13 / 3963 / 带 8..13」
  五处互相一致 ✅；3962 / 裸 +12 零残留（:120 的「+12→+13」为来源标注，
  合规）✅。**但带边本身算术错 = R2**（组件带和 9..14 ≠ 声明 8..13；
  pre-B1 算术冻结带入——评审第 5 条原式「下限 3+2+2+1=8 / 上限 5+2+4+2=13」
  在 T1 带 3..5 下成立，B1 后 T1 带 4..6 未回代）。
- **legal SDR 8 对**：grep「9 对」零残留 ✅；8 对清单与 `legalEOTFs` /
  `DrtOutputColorSpace` 双表逐对镜像亲验吻合 ✅（域外负腿选点 rec709×
  gamma18 / p3d65×bt1886 均实测 typed throw 路径 ✅）。
- **9 字段**：grep「七字段」零残留、`McpEndpointInfo` 9 属性亲验 ✅。
- **6 文件**：T1「恰六」与 files_modified 六行（McpServerController /
  LightamerApp / AgentControlCoordinator + McpHostTests /
  McpSearchStateToolsetTests / AgentControlCoordinatorTests）一致，可选腿
  McpControlToolsetTests 单列 ✅。
- **yiyin 计数**：grep 机检 **FAIL = R1**（实测 8 处非 3 处；全 App 177 处
  亲验吻合 ✅——主张成立、支持计数错）。
- **其余抽验**：错误码 19 case 亲数吻合（16 非控制 + 3 控制）✅；「13 工具
  admit 面」亲演吻合（9 注册点：culling 元数据助手一盖五 + apply_preset +
  editing load_image/apply_params/paste_adjustments/export_image +
  match_color + project 2）✅；32 工具 all32 :270-272 ✅；union :277
  private ✅；skip 35 = 24+11 与 M7-5 口径一致 ✅。

## 六、可执行性终判

- **T1..T6 闭环**：每任务 read_first → action（编号步进）→ 验收标准（机检
  判据 grep/diff 面核/对账行/bundle 绿）→ commit → 回滚与偏差申报 ✅；依赖
  序 T1→T6 成立；union 串行禁并行 + 持权窗口条款齐备。
- **commit 草稿**：六条全英文 Conventional（fix/fix/feat/feat/test/docs）✅。
- **红线 11 条自洽**：FIX2③ = LibraryProjectController 零 diff + McpServer
  Controller 合法修改面 + DECISIONS 申报逐 hunk（:18）与 T1 验收第 4 条
  （:258-259）互洽 ✅；union 串行 + internal 恰一行申报（:15 / :43 / T4
  action 1）三处互洽 ✅；:277 private 亲验、internal 后同测试 target 可达
  论证成立 ✅；writeCallCount 只挂 writer 门亲验（:385-408 dispatch 序）
  ——setControlAdmit 装配不增计的结构保证成立 ✅。
- **晨审推翻点留痕**：CONTEXT 晨审推翻点索引节 + plan 对 D-M7-6-* 逐条引
  用 ✅；C 档第 3 停条款在 T6 ✅。
- **read_first 锚点抽查**：:482/:497/:603-606/:232-236/:722/:786/:1035/
  :1137/:1165/:1632-1651/:65-69/:72-74/:47/:63/:69/:732/:749-798/:734-748/
  :804-811/:53-141/:56/:248-259/:646-653（PipeCoordinator 实路径
  App/Sources/Lightamer/State/）/:270-272/:277/:401/:194/:253/:473/:1015/
  :1046-1065/ControlToolset :20/ROADMAP :110——**全数落点** ✅。

## 七、回归面（26 hunks）

fixer diff 恰 26 hunks（PLAN 176 行 + CONTEXT 23 行，与任务书口径一致）。
新增行号主张 8 组（:248-267 / :1143-1150 / :1046-1065 / :178-268 / :1176 /
ControlToolset :20 / m1·m3 超额清扫位 / :110）逐一对照源码**全数吻合**；
无评审清单外新事实主张、无新机制/新测试腿发明（resume 负腿与诚实面句均为
评审 B1 处方 2/3 的忠实落位）；「超额清扫」为 grep 机检合法延伸（零残留
亲证）。CONTEXT D-M7-6-5 勘误句的「三处」假计数是唯一的回归面带入
（= R1）。

---

## Notes（不阻断观察）

1. fixer 自报「4 处保留四宿主」与实测留存（PLAN 3 + CONTEXT 2 = 5 处）计数
   不严格对账——逐处核实均属签名批语境/勘误引文，零缺陷。
2. `(review *)` 标记总数 44（任务书按 48 计）——CONTEXT 5 处与头注 round-1
   引用段的统计口径差；抽核全数一致。
3. 「:248-259 清零」与「:248-267 resume 路由段」两种区间引用并存——均与
   源码吻合（清零点 :257-259 落在 success 全形内），非矛盾。
4. R1 修时顺带理顺 CONTEXT D-M7-6-5 勘误句的嵌套括号排版。
5. （正面）fixer 对 m1/m3 的超额清扫经独立 grep 机检零残留属实；评审
   M1/M2 的源码事实链（除 M2 的 3 处计数外）全部亲验成立。

```
复核证据正本：本文件全部 file:line 为 2026-10-17 HEAD cae4e825 工作区亲验
（产线源码零 diff——fixer commit docs-only 经 git show --stat 亲证）；
grep 机检命令与命中数随 §四/§五 各条在案。
```
