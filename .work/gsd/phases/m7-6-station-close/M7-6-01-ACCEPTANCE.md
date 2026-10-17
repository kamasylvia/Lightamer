# M7-6-01 ACCEPTANCE — 第一路独立验收（2026-10-17）

> 验收对象 = `M7-6-01-PLAN.md`（fixer/checker 后 HEAD `beb8937c`）执行链
> `ad003e88`(T1)→`32b592aa`(T2)→`bac0ff76`(T3)→`4259cfd8`(T4)→`eba261e3`(T5)
> →`83db9107`(T6)。方法 = 按 plan 逐任务验收标准机检（grep/diff 断言亲跑）
> + 测试亲跑（定向 App + 全套 `--all` 独立复跑）+ 红线族 11 项亲跑 +
> zh-audit 双复跑 + 偏差①-⑨ 逐条复核。**零源码改动、零 commit**（本报告
> 落盘即止，orchestrator 收口代 commit）。

## 结论

**PASS / 0 blocking + 0 major + 0 minor + 5 obs**

执行申报全部独立复核成立：六任务验收标准逐条机检 PASS；全套
`TOTAL|3963/35/0|` exit 0 零 MEMFAIL 本机独立复跑精确闭合；红线族 11 项
全 PASS；zh-audit 双 PASS（1709 恰 +1）；偏差申报九面全部「等价终形成立」。

## 逐任务判定表

| 任务 | commit | 判定 | 机检记录（亲跑） |
|---|---|---|---|
| T1 三缺陷 | `ad003e88` | **PASS** | ①`setControlAdmit` App/Sources 恰 5 处（定义 McpToolRegistry :367 + ControlToolset :20 头注 + 三宿主安装点 :754/:841/:1109——embedded 无独立安装点，经 box→startHTTPHost 单点装配，review M1 构成成立）②`admit: (@Sendable …)= nil` 缺省参恰 4 签名（:739/:809/:1066/:1171）+ box 字段恰 1（:1282）+ box 写入（:1186）+ 读出透传（:1201-1216）③`agentControl: { McpControlState.headlessConstant }` 恰 3 处（:488/:508 新 + :617 既有零 diff）④acquire diff = 恰入口快照 1 行 + 循环退出后条件复检 2 行（revoked 臂 `stoppedByUser, !stoppedAtEntry` / busy 臂 `held ∧ holderName != holderName`，两 throw 拼写与 :215-217/:228-231 既有臂**逐字同构**亲证；其余段零触）⑤GUI 装配恰 1 闭包（LightamerApp :1652 `{ [agentControl] name in try await agentControl.admit(toolName: name) }` + plain-await 同款注释）⑥无头臂调用点（:480/:499/:626/:638）零 admit 传递 ⑦commit 恰六文件（3 产线 + 3 测试，review m2）⑧测试腿 5 全绿（McpHostTests +1 真宿主 controlNotHeld〔:278 admit stub + :285 码断言〕/ McpSearchStateToolsetTests +1 / AgentControlCoordinatorTests +3〔:379 final-window revoked / :415 并发 busy / :448 resume 不断裂〕；腿②合并让渡——既有 `testHeadlessAdmitNilWriteToolsAnswerStraightIntoHandler` :427 同语义，本波 +0 法亲证）⑨FIX2③ = `git diff beb8937c..83db9107` 与 `7f6fa522..83db9107` 两域 LibraryProjectController.swift 零输出 |
| T2 UQ-A1 | `32b592aa` | **PASS** | ①Core `DrtOutputColorSpace.swift` 零 diff（0 行）②EditorMTKView diff 仅 SDR 幂臂段（legal 对先 `try? DrtOutputColorSpace.drtOutputColorSpace` → 同实例直返；nil → 既有 calibrated 构造保留为回落臂 + KD-8 注记更新）——HDR/linear 臂、drtSurfaceSpec、PipeCoordinator 零触（diff 面核）③EditorPreviewColorSpaceTests 3 法在库（legal 恒等 8 对〔清单与 Core legal 表一致：rec709×{bt1886,gamma22,srgbPiecewise} + p3d65×{gamma22,srgbPiecewise} + p3d60×gamma26 + p3dci×gamma26 + xyz×gamma26；`preview === export` 同实例 + ICC bytes 逐字节同〕/ srgbPiecewise 真分段行为腿〔CGColor.converted 真 ColorSync 变换，below-knee 线性段判别〕/ 域外回落负腿）——App 轮 917/4/0 全绿亲证 ④App 侧零新缓存面（try? 直调，Core per-pair 缓存承载） |
| T3 UQ-L1 | `bac0ff76` | **PASS** | ①MonochromePanelView / EditorState（previewDenoiseBypass 所在）零 diff（不在全波清单）②`DragGesture(minimumDistance: 3)` 恰一处（LightamerSlider :88；:45 为注释字样）③scrub 路径仅 onDragBegin/onChange/onDragEnd 三回调，零旁路值通道 ④AX identifier 三处 + onReset 双击（:72-74 现址）零触（diff 仅 context 行）⑤xcstrings 恰 +1 键 `slider_scrub_hint` 尾块纯插入（+10/-0 @ :32752 尾块，历史键零触碰）⑥LightamerSliderScrubTests 3 法全绿（travel 映射族含双侧 clamp / Shift ×0.1 族 / begin-end 配对含零 tick 负腿） |
| T4 SKILLS-01 | `4259cfd8` | **PASS** | ①三文件落位（SKILL.md 7898B 七节〔§1..§7 grep 齐全〕+ references/tools.md 14873B〔32 `###` 工具节，五域 9/14/3/3/3〕+ references/errors.md〔19 码行〕）②SkillsReferenceTests 2 法绿（tools.md 活注册表逐字节门 + errors.md 19 码名断言——App 轮亲证）③McpFinalSnapshotTests diff 恰一行（:274 `private func`→`func`，union 内容/断言面零触）④en 单语 `grep -rn "[一-鿿]" skills/` 零命中（exit 1）⑤N2-2 句在 SKILL.md :149 + README :100 链接句 ⑥生成脚手架已移除（committed 测试文件零 `LIGHTAMER_WRITE_TOOLS_REF` 命中）⑦零 taste 亲核（§1 显式指认 launcher `{{PROMPT}}` 载体；无工作流规则段） |
| T5 对账批 | `eba261e3` | **PASS** | 全套对账独立复跑闭合（见下节）；红线族 11 项全 PASS（见下节）；zh-audit 双 PASS；MANIFEST 十一行在库（UQ-L1 六行 + UQ-A1 两行 + major-1 e2e 三行）；SUMMARY/DECISIONS 落盘且与实测一致 |
| T6 站级收口 | `83db9107` | **PASS** | ①M7-VALIDATION.md 六节齐全（§1 站终验 / §2 五 phase 矩阵 / §3 红线族复检 / §4 SC 翻账〔四判定式句 ✓〕/ §5 制度偏离三件〔omp→双 zcode / m7-5 载体 / UQ-L1 SC 降格——review m4 兑现〕/ §6 M7-5 signed + §7 挂账清算 + §8 留痕；front-matter 对齐 M7-1 体例）②REQUIREMENTS 三行 Delivered（SKILLS-01 :452 / UQ-A1 :458 / UQ-L1 :460，commit 指针在行）③ROADMAP :110 M7-6 行 ✅ 闭环（ΔN 终值 + C 档第 3 停标注）④GOAL-STATE :19 续接点翻新（M7 站收口 → next = M8 charter + union 归还注记；diff 纯追加单行）⑤TODO :367 M7-6 条目翻账 ⑥AGENTS.md :567 M7-6 架构增量节。翻账形 = 待办行翻转非历史行改写（diff 面核：ROADMAP/REQUIREMENTS/TODO 的 `-` 行均为 pending 态行，历史 ✅ 行零触碰） |

## 全套终值（本机独立复跑，2026-10-17 20:09–20:39）

```
BUNDLE|IOP|687/5/0|peakRSS=7980MB|418s
BUNDLE|IOPParity|460/3/0|peakRSS=8097MB|760s
BUNDLE|Layers|494/5/0|peakRSS=806MB|176s
BUNDLE|Library|736/4/0|peakRSS=617MB|79s
BUNDLE|Sessions|284/9/0|peakRSS=1620MB|62s
BUNDLE|Export|385/5/0|peakRSS=6420MB|203s
BUNDLE|App|917/4/0|peakRSS=2832MB|388s
TOTAL|3963/35/0|2086s   RUN-EXIT=0   零 MEMFAIL   七 bundle 全 8G 门内
```

- **`TOTAL|3963/35/0|` exit 0 零 MEMFAIL——与执行申报逐值精确一致**；
  对账链 3950 + ΔN 13 = 3963 闭合（预期带 3959..3964 内，点估 +13 精确）。
- 定向轮：`--bundle App` 独立再跑 = `917/4/0|peakRSS=2832MB|394s` exit 0
  （第二遍，与全套轮 App 腿同值）。
- skip 35 构成：七 bundle skip 数（5+3+5+4+9+5+4）与 M7-5 终态逐值一致 =
  24 基线 + 11 RAW 供件缺失，第三种来源零（零漂移亲证）。
- ΔN 分账亲核：测试方法增量 McpHostTests +1 / McpSearchStateToolsetTests
  +1 / AgentControlCoordinatorTests +3 / EditorPreviewColorSpaceTests +3 /
  LightamerSliderScrubTests +3 / SkillsReferenceTests +2 / McpControlToolsetTests
  +0（腿②让渡）= **+13 精确**，与 SUMMARY 记账表一致。
- 运行监视：全程在岗；IOPParity 8097MB / IOP 7980MB 在 SPIKE 历史带
  6.97-8.14G 内（±3% 方差注记场景未触发——零 MEMFAIL）。

## 红线族 11 项亲跑记录（`beb8937c..83db9107` 全波面）

| # | 项 | 结果 |
|---|---|---|
| 1 | 零新 SPM（Project.swift dependencies 零 diff） | PASS（diff = 恰 +3 测试登记行） |
| 2 | `.metal` 全域零 diff | PASS（0 文件） |
| 3 | McpToolRegistry 面（19 档零触 + writeCallCount 零触 + McpTimeouts 零触） | PASS（McpToolRegistry.swift / McpTimeouts 零 diff；setControlAdmit 装配四点 = DECISIONS §2①/§4 显式申报点，与 plan 一致） |
| 4 | FIX2③ LibraryProjectController 零 diff | PASS（两 diff 域零输出） |
| 5 | 封存面 17 件零 diff | PASS（17 件名 pattern 全波 diff 零命中；EditorMTKView = T2 受限修改面申报面） |
| 6 | xcstrings 尾块纯插入 | PASS（+10/-0 @ 尾块，历史键零触碰） |
| 7 | UserDefaults 零新键 | PASS（diff 无 set/register 新键；仅既有 bool 读 context 行） |
| 8 | runModal 禁形 | PASS（App/Sources 零命中） |
| 9 | 插值禁形 | PASS（`String.LocalizationValue("…\(x)"` 代码形零命中；唯一命中 = LightamerApp :2375 既有注释行，非本波 diff；ExportInspectorView :534 为 `+` 拼接形非插值形且零 diff） |
| 10 | Project.swift 恰三行 + BUNDLE-MAP 恰三行 + tuist generate 恒末位 | PASS（+3/+3 亲数；commit-per-task + 各批测试绿承载 L041） |
| 11 | union 32 + 五钉 23 零触 | PASS（McpFinalSnapshotTests diff 恰一行 private→internal；既有断言 App 轮全绿双证） |

## 偏差①-⑨ 复核（正本 = DECISIONS §2..§9；逐条判「等价终形成立/不成立」）

| # | 偏差 | 判定 | 复核依据 |
|---|---|---|---|
| ① | FIX2③ 正义勘正承接（§2.1） | **成立** | 两 diff 域零输出亲跑；McpServerController hunk 面 = 全 additive/接线形 |
| ② | 七节正本承接（§2.2） | **成立** | SKILL.md §1..§7 grep 齐全，人工抽读与 ControlToolset 语义一致 |
| ③ | plain-await 形承接（§2.3） | **成立** | 闭包形 + 同款注释在 :1652-1658 亲证 |
| ④ | internal 前提 + union 持权一行（§2.4/§4） | **成立** | diff 恰一行；union 内容零触；窗口归还 M8 注记在 VALIDATION §7 |
| ⑤ | schema 全文 + description 列省略（§2.5/§8） | **成立**（晨审可翻面已登记） | 冲突事实亲核为真：`mcp_tool_desc_*` xcstrings 仅 zh 列（亲 grep）——与 en 单语门结构性不可兼得；裁定保 schema verbatim（逐字节门承载）；渲染器回加 description 列即可翻，门不变 |
| ⑥ | obs-3 等价终形（§3：快照落点 / 复检块内 / PollTriggerBox 交错） | **成立** | 快照行前无挂起点（MainActor 同步段亲读）＝入口值；复检落 `if !alreadyHeldBySelf` 块内对 already-held 路径结构性不可触；两 throw 拼写逐字同构；测试 pollInterval 注入 20ms + PollTriggerBox 串行触发，零真 250ms 等（grep 亲证）；「禁无条件拒绝」病灶由 resume 负腿 :448 拦截 |
| ⑦ | T1 腿②合并让渡 + minor-1 腿等价终形（§5） | **成立** | 既有 `testHeadlessAdmitNil…` :427 同语义亲证（本波 +0 法）；plan 判据「直调→非 nil」与修法（调用点接线、签名缺省仍 nil）结构性不一致的分析正确——等价形 = 产线同拼写构造断言 + runHeadless 函数体源级扫描（含且不含双断言）亲读 |
| ⑧ | T2 等值腿收敛同实例+字节同 + srgbPiecewise 行为腿 3 法（§6） | **成立** | 同实例蕴含等值（plan 明示可收敛）；行为腿恰承载 plan 的「真分段非 2.2 幂」判据（CGColor.converted 真变换亲读）；legal 8 对清单与 Core 表一致；KD-8 消解在注记亲证 |
| ⑨ | T3 Shift 换锚 onModifierKeysChanged + trackWidth 整行宽 + 拖离取消让渡（§7） | **成立** | SDK 亲核：arm64e swiftinterface 中 DragGesture.Value 无 modifiers 成员、onModifierKeysChanged 在册——plan 形编译不可达属实；trackWidth = 组件宽近似（框架内部 track 几何不可达）；让渡 = MANIFEST A3 观察行在库（预期行为非缺陷） |

制度偏离两件（omp→双 zcode / m7-5 载体）= T6 VALIDATION §5①② 在库，本批
执行路由 = 双 zcode subagent 制内，无新偏离。登记申报四件（§9）全部兑现
亲证（xcstrings +1 / UserDefaults 零 / union 一行 / 制度偏离归 T6）。

## 残留清单

1. **第二路并行产物两件（非本路残留，归 orchestrator 收口裁决）**：
   `.work/gsd/phases/m7-6-station-close/M7-6-01-ACCEPTANCE-2ND.md`
   （untracked，19:39 落盘）+ `M2-4-0-BUNDLE-MAP.txt` 工作树三计数行更新
   （19:41，McpHostTests 18→19 / McpSearchStateToolsetTests 17→21 /
   AgentControlCoordinatorTests 10→13——与 HEAD 实测 19/21/13 亲核**精确
   一致**，属并行路的账实对账非污染；提交归属由 orchestrator 裁）。
2. **UQ-L1 实机走查**：MANIFEST A1-A6/B1-B2/C1-C3 十一行归验收批/用户
   （SC 措辞降格已登记 VALIDATION §5③）。
3. **挂账清算面**：N2-2 收口 / S-2 维持 / obs-A C12 注记 / FIX2③ 第六波
   待续核 / union 改动权归还 M8——VALIDATION §7 在账，无新增挂账。
4. 会话环境：无残留测试宿主进程（亲查 0）；临时脚本/锁标记已清
   （/tmp 即弃面）；跟踪文件本路零改动（BUNDLE-MAP 三行 = 上述并行路产物）。

## obs 清单（非阻断）

- **obs-1**：验收环境注记——首轮全套经 harness 后台通道在 App 腿中断
  （宿主侧 kill，六 bundle 值已捕获），改 nohup 脱离通道重跑全程闭合；
  终值以重跑轮为准。与 f02 撞车防线（互斥等待 + 锁标记）在案。
- **obs-2**：第二路 BUNDLE-MAP 三计数行更新未提交（见残留清单 1）——
  两个验收路均为零 commit 制，账实对账行的提交归属需 orchestrator 显式
  裁（建议：随本报告批一并 commit，数值已两路独立核一致）。
- **obs-3**：T4 tools.md description 列省略 = 已申报结构冲突裁定（偏差⑤），
  晨审可翻；tools.md 域边界语义由 SKILL.md §3 en 承载，agent 可见面无缺口。
- **obs-4**：IOP/IOPParity 本轮峰值 7980/8097MB——SPIKE 历史带内、8G 门内，
  连续 MEMFAIL 未触发；贴线 bundle 方差注记场景未激活。
- **obs-5**：MANIFEST 在 gitignore 面（.gitignore:79 `.work/gui-acceptance/`）
  ——VALIDATION §8「工作树 untracked 副本（政策 B）」申报与仓库惯例一致，
  磁盘在库即合规。

## 判定依据汇总

- 逐任务 AC：plan 验收标准每条 grep/diff 断言亲跑（记录见判定表）。
- 测试：全套 `--all` 本机独立复跑 `TOTAL|3963/35/0|` exit 0 零 MEMFAIL +
  定向 `--bundle App` 917/4/0 exit 0（两遍同值）。
- zh-audit：`--check` PASS（1709 source keys / 1957 catalog / 38 interp）+
  `--self-test` PASS（V17 golden 八例）。
- 偏差九面：全成立（零「不成立」项）。
