# F0P-02/03 ACCEPTANCE — P2+P3 第一路独立验收（串行制重派，2026-10-20）

> 验收对象：`F0P-02-PLAN.md` + `F0P-03-PLAN.md`（裁决正本 CONTEXT.md 勘误①-⑦）；
> 执行链 P2 `5a651b44`/`0f08198c`/`93b8bc96`/`a3d4a715`/`53f43c4b`/`8cc9e916`/
> `b25c270b`/`b5fd46b2` + P3 `0c70e608`/`89018697`/`e1968e94`/`98a5db6e`。
> 本轮 = 零源码改动独立验收；报告落盘即产物（不 commit）。

## 结论头

**PASS / 0 blocking + 0 major + 3 minor + 7 obs**

全部 plan AC 机检面亲跑/亲核通过；偏差 11 项逐条判**等价终形/合规**，零
blocking；申报数字（`TOTAL|3991/37/0|`、738/4/0 双臂、D-6 0.0%、退役
-2728 行 grep 七门、16 面 12✓+4◑+1✗）与留档逐值吻合。3 minor 均为留痕/
载体精度类，不动判定。独立复跑 + D-6 复测一轮因机器 guard G3（swap 残留）
按 orchestrator 裁决 (b) **移交第二路**（见 §五）。

## 一、guard 过关记录（机器级单重活纪律兑现）

| 时点 | 动作 | 结果 |
|---|---|---|
| 21:1x | 构建前 `Scripts/machine-guard.sh --wait 1800` | **GUARD PASS** (heavy=0 free=65% swap=0M disk=39GB) |
| 21:2x | 四族定向跑前 guard | **GUARD PASS** (heavy=0 free=58% swap=0M disk=37GB) |
| 21:4x | 探针轮前 guard（内嵌于探针脚本 --wait 600） | **GUARD BLOCK ×N（G3 交换 2321→2121MB≥1GB）** |
| 21:50 | chain（guard 1800 → 全套 → guard → 探针）起跑 | guard 持续 BLOCK（G3） |
| 21:5x | **CHAIN-ABORT（orchestrator 裁决 b）** | 自出链清零（chain/guard/宿主 0 残留），swap 自然回落，未手动干预 |

- **obs-1（G3 事件链如实申报）**：验收中途一条打包命令内的 `test-direct.sh`
  旧行被意外执行（stdout 丢弃形态、无留档价值）→ 发现即停（**只杀自出链**
  ：TaskStop + pkill 链内进程，宿主 parentage 确认后清零）→ 被杀宿主
  （IOPParity 3.7GB RSS 态）留下 swap ~2.2GB 残留 → 后续一切重活被 guard
  G3 硬门卡住（降速 ~200MB/14min，等满 1800s 必超时）→ 按「BLOCK 则等 +
  裁决 (b)」CHAIN-ABORT 收口。labelingMode 探针保护键已复原（`defaults
  read` = key absent，clean）。
- 构建 = 本轮首个构建者：`build-for-testing` 一次成功（** TEST BUILD
  SUCCEEDED **，0 errors，SourcePackages 复用零网络），容器
  `~/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`
  @ HEAD `9ca2f326`；**BUILD-HANDOFF.txt 已写**（`.work/gsd/phases/
  f0prime-prod/BUILD-HANDOFF.txt`，容器路径 + HEAD sha + 时间 + 二路消费
  注记），容器确认在位、未删。构建日志 = `all-runs/acc-1-build.log`。

## 二、P2 逐任务判定

| 任务 | 亲跑/亲核 | 判定 |
|---|---|---|
| **T1** NSMenuParityTests | 亲跑 `--bundle App NSMenuParityTests` = **12/0/0**；seam 亲核 = fresh controller + stub Deps + `install(deps:)` + 每法 save/restore NSApp.mainMenu（armHarness/disarmHarness 对）；paste 二元钉 `testPasteFamilyBinaryEnablerWithoutHoldsControl`（:394，"no holdsControl" 断言 :432——勘误③/⑦ AC 承接形）；AX 迁移集断言（testAXIdentifierMigrationSetPinned）；softproof laState 腿（:306-313）；shortcut × DefaultKeymap pin；标题经 catalog 解析非裸键 | **PASS**（+12 带 +8..12 顶） |
| **T2** ShellGraphMigrationTests | 亲跑 = **4/0/0**；**同实例身份断言在位**（:123 MARK shared-instance identity，review M2 兑现） | **PASS** |
| **T3** MenuBridgeObservationTests | 亲跑 = **4/0/0**；menuNeedsUpdate delegate 面（note-box untracked 属性 = D-F0P-02-1.3 申报形）+ workspace 臂 arm-prime → mainMenuStomps 严格递增回执（re-arm 改形 (a) 兑现，omp M3 推荐案行使）；stale backstop BLOCKED 阻断断言（:258-285） | **PASS** |
| **T4** 窗 smoke + 接线 | 亲跑 = **2/0/0**；`Project.swift` 恰 +4 行显式清单（:875-878，无 glob）；BUNDLE-MAP 恰 +4 数据行（:783-786，另有 +4 注释行 = obs-4）；tuist generate 恒末位 = a3d4a715 commit body 自述（产物面核不可行——xcodeproj 不入 git，obs-5） | **PASS** |
| **T5** 直启宿主等价性 | 本轮只核日志证据（不重做双构建）：`host-equivalence/` roundA（pre-flip `907c373d` worktree+供件+独立 DD）**738/4/0 peakRSS 615MB** = roundB（HEAD 主树）**738/4/0 peakRSS 615MB**——Executed/failed/skip/峰值逐值相等；README 记录供件步（m-omp-6：input/ 314MB + AIModels 194MB）与 SourcePackages 播种法（deviation-3） | **PASS** |
| **T6** 全套三轮同值 | 三轮留档亲核（`all-runs/round{1,2,3}.log`）：**`TOTAL|3991/37/0|` ×3**（2102s/2136s/2107s）；per-bundle executed/skip 向量三轮逐值恒 = IOP 687/5 · IOPParity 460/3 · Layers 494/5 · Library 738/4 · Sessions 284/9 · Export 385/5 · App 943/6（m-omp-8 向量钉）；峰值 IOP r3 7645MB（8G 门内）；3969+22=3991 精确对账、带 3984..3994 内；skip 37 零漂移。**独立复跑一轮移交第二路**（裁决 b，§五） | **PASS（复跑移交）** |
| **T7** 16 面走查 + D-6 定版 | MANIFEST §六亲核：16 面 = 12✓+4◑+1✗（计数口径见 minor-2）；面 2 ImportModeDialog **双重排除证据亲核**——ips `Lightamer-2026-10-20-064532.ips`（procPath = 主容器 B 臂二进制）与 `-065317.ips`（procPath = `/tmp/*/Lightamer.app` A 臂供件二进制）同 `Trace/BPT trap: 5`，A 臂同崩 = pre-existing（M2-9 F-1 家族 mount 腿）；D-6 定版数据亲读（`probe/logs/d6-B-r1..3/cpu.txt` median=**0.0** ×3、`d6-A-r1` median=**97.6**；四哨兵 meta 在档：frontmost=true / 截图 / 主线程泊 / churn 符号族 0）；面 11 = 32 工具（m-omp-1 勘正数）；门① zh/en 双语 dump 双腿在档 | **PASS** |

## 三、P3 逐任务判定

| 任务 | 亲跑/亲核 | 判定 |
|---|---|---|
| **T1** 退役 + 重指同 commit 原子 | App struct 退役后文件 **249 行亲读**（ExportPanelRequestKey 保留 + 保留说明注释 :22-28、entry fork 四把逐字 + `LightamerShellMain.run()` 恰一调用点 :160、AppDelegate 勘误④域、WindowCapture、McpWriteFaceBox/PanoFailureCopy 全在位；`_ = { LightamerApp.main() }` 死行已摘）；`git show --stat 0c70e608` = **恰 7 文件**、60 insertions/**2728 deletions**（申报兑现）；hunk 头面核 = 4 hunks 全落声明域/死行/struct 删除域——保留段零 diff；**壳侧恰两 hunk 亲证**（迁壳函数体 @@ -1599,6 +1599,49 + 调用点重指一行 @@ -2211,7 +2254,7），其余壳侧字节零触碰；**statics 迁移清单逐条在壳**：runAIDeterminismProbeIfRequested Shell :1612（恰一处定义）、batchPasteBlocked :1832、readOnlyPasteToast :1838、displayPlaneHash :2023（App struct 侧副本消亡）、probe armed 旗标 ×3 壳侧在位（:1645/:1682/:1903）；**四处 publish 摘除** = ContentView ×2（:265 域）+ InspectorPageMount export 腿（-10 行）+ WorkspaceHostView :178 + InspectorView :410；三键（LightamerColumnVisibilityKey/WorkspaceModelKey/MetadataFieldFocusedKey）+ extension 面零命中；**ExportPanelRequestKey 保留案**（omp M2 (a)）= 壳 :94 `@FocusedBinding` 活依赖 + :2108-2109 honest-degrade 路径（publish 全摘 → 恒读 nil → 页路由，零行为面论证兑现）；**测试重指终形** = AgentControlCoordinatorTests face ⑤ → `("UI/Shell/LightamerShell.swift", "guard !agentControl.holdsControl else { return }")`（holdsControl 活源，语义等价）+ ProjectReadOnlyFaceTests 6 处 → `LightamerShellFace.*`（4+2）；B19/B20 note 保留（WorkspaceHostView :181 / InspectorView :413） | **PASS** |
| **T2** grep 七门 | **七门亲跑全过**：①`.commands(`=0；`WindowGroup` 仅 2 条注释豁免形（EditorMTKView:30/SessionCoordinator:24）；`Settings {` 词边界=0；`@FocusedBinding` 代码行恰 1（壳 :94 豁免面）；`focusedSceneValue` 代码行=0（注释豁免形实测 3 条——minor-1）；②`LightamerApp.runAIDeterminism`=0 + 壳内宿主恰 1（:1612）；③`.runModal(`=0；④LocalizationValue 禁形=0；⑤`F0PrimeShell`=0；⑥xcstrings diff=0（P2+P3 全批）；⑦UserDefaults 应用级键 diff=0。附加：`struct LightamerApp`=0、`LightamerShellMain.run()` 恰 1、`batchPasteBlocked` 定义恰 1（壳侧） | **PASS** |
| **T3** FB 稿终章 | **终章四节亲读**：终 1 壳交接生产化（翻转 commit `752c5294` 存在且恰 3 产线文件亲核 + 三轮同值 + 等价性双轮 + 死码退役）；终 2 D-6 定版表（spike A 96.0/97.1/95.7、生产 B 0.0×3、生产 A 重建 97.6、**−97.6pp**、四哨兵）；终 3 功能性发现注记；终 4 提交核对清单（四勾 + **用户手动提交项未勾 = 不代提交兑现**）；数值与 F0PRIME/P2 DECISIONS 一致；append-only（历史章节零触碰） | **PASS** |
| **T4** README 勘正 | `git show e1968e94` = 恰 1 文件单 hunk（@@ -117,17）；两处变更亲读：toolbar 差异行（in-face 渲染 + NSToolbar 重造后置候选）+ D-6 撤除注记（**"no longer reproduces in this app… upstream framework defect itself is unchanged"**——定性正确，非「框架已修复」）；其它段零触碰 | **PASS** |
| **T5** 复证 + 收口 | App 定向轮 943/6/0（执行方，退役零 ΔN 对账）；五点抽样 MANIFEST §九亲核（启动+项目/编辑器进出/三窗/五路菜单分发/退出链全 ✓）；本轮独立面 = 四族 22 法亲跑（新容器退役后二进制）+ P2 产线零 diff 面核（a3d4a715/8cc9e916/b25c270b 均 tests+docs 域） | **PASS** |

**产线零 diff 复核（P2 勘误②）**：P2 全波 `git show --stat` 逐 commit =
测试文件 + Project.swift + BUNDLE-MAP + docs，产线源文件零触碰 ✓；
manifest face ⑤ 行 / batchPasteBlocked static 在 P2 期间未被触碰（P3
`0c70e608` 原子落位）✓。

## 四、偏差 11 项逐条判定（全部等价终形/合规，零 blocking）

| # | 偏差 | 判定 |
|---|---|---|
| 1 | P2 dev-1 接线拓扑（T1-T3 纯测试文件 + T4 一次收口） | **等价终形**——plan 头「接线收口一次」条款明文授权；累计口径下四文件各恰 +1 行、BUNDLE-MAP 各恰 +1 行亲核 |
| 2 | P2 dev-2 T3 观察 seam 重设计（note-box delegate 面 + arm-prime/stomps 回执） | **等价终形**——生产 Deps 不可达为申报事实（非静默吸收）；plan 红线禁产线加缝下唯一合规路径；「sample 字段子集驱动全流程」条款行使；re-arm 改形 (a) = omp M3 推荐案行使 |
| 3 | P2 dev-3 T5 SourcePackages 播种 | **等价终形**——构建环境型偏差（网络双断），独立容器红线维持未共享；M7-1 代理坑扩展形态 |
| 4 | P2 dev-4 T6 run-1 错容器事故 | **处置合规**——杀自出进程 + parentage 面核 + worktree/容器拆除 + 干净重跑三轮（M2-7-3 先例；LESSONS 候选在案） |
| 5 | P2 dev-5 T7 卷转移/AX 读限（面 12/13 卷转移、面 7/15 AX 读限、face-5 深度后置） | **可接受**——证据卷在案的卷转移非静默缺项；AX 读限 = 测量限制且机检替代面（parity note-box + menuNeedsUpdate 双腿）已绿；挂账显式（F2-2/F2-3） |
| 6 | P2 dev-6 A 臂重建一件两用（走查归因 + D-6 相对门双证） | **等价终形**——双证数据在档（97.6 一致两用），申报在案 |
| 7 | P3 dev-1 T2 无独立 commit | **合规**——纯机检零文件变更，全局空提交禁令优先；输出全文落 DECISIONS/SUMMARY，本轮七门亲跑复现 ✓ |
| 8 | P3 dev-2 壳侧两 hunk 非「单 hunk」字面 | **等价终形**——plan 括注「迁壳同 commit」已含本体授权，「恰一 hunk」读法 = 调用点重指；`git diff` 逐 hunk 亲证 = 恰两 hunk、其余壳侧零字节 |
| 9 | P3 dev-3 FB 终章 append 形式 | **合规**——历史行不改写纪律；「数值以终章为准」显式声明在案 |
| 10 | P3 内联：face ⑤ 重指 token 形变更（文件+token 双改） | **等价终形**——holdsControl 守卫活源（壳 :201/:205/:209 三处命令闭包），source-content guard 机制不变，face ⑤ 语义等价 |
| 11 | P3 内联：static 转移终形 = 纯删 + 重指（非转发层） | **等价终形**——RESEARCH §5.2「或保留同名转发」备选明确在授权内；壳已有同名实现（P1 搬运），单源优于转发层 |

## 五、移交注记（第二路）

1. **全套 `--all` 独立复跑一轮**（申报 `TOTAL|3991/37/0|` + per-bundle
   向量 IOP 687/5 · Parity 460/3 · Layers 494/5 · Library 738/4 ·
   Sessions 284/9 · Export 385/5 · App 943/6）——orchestrator 裁决 (b)
   由第一路移交；**消费本路容器，不重建**：
   `BUILD-HANDOFF.txt` = `.work/gsd/phases/f0prime-prod/BUILD-HANDOFF.txt`，
   容器 `~/Library/Developer/Xcode/DerivedData/Lightamer-dgzsvdwwznxhozhdtijsbcwmglbi`
   （HEAD `9ca2f326`，TEST BUILD SUCCEEDED @ 2026-10-20 21:2x，本轮收口
   时确认在位未删）。**收口前请勿删除该容器。**
2. **D-6 探针复测一轮**（0.0% + 四哨兵，GUI 臂与测试轮错峰）——同裁决
   移交。探针配方 = `probe/run-one-f0p1.sh <label> <二进制>`；fixtures
   `/tmp/nsmenu-spike-fixtures` 已由本路重建（2 ARW link，obs-3——原
   DNG 形态经 watchdog 重启消亡；探针接受任意可导入图片目录，`rendered=yes`
   机检不受影响）；`library.ai.labelingMode` 保护 = 写 never + 事后复原
   （driver 惯例）。T7 在档基线 = d6-B-r1..3 全 0.0 + d6-A-r1 97.6，本轮
   复测为增证轮。
3. swap 残留（~1.9GB 回落中）为第一路 G3 事件尾巴，自然回落即可（orchestrator
   指示：勿手动干预）；二路重活前照常 guard --wait。

## 六、minor / obs 清单

- **minor-1**：F0P-03 SUMMARY §二记「focusedSceneValue 注释豁免形 2 条」，
  实测 **3 条**（漏计 `LightamerApp.swift:11` 文件头 plumbing 注释）——
  门判据（代码行零命中）不受影响，留痕精度。
- **minor-2**：16 面计数口径——「12✓+4◑+1✗」中面 15 以 ✓（全屏+Dock
  reopen 主判）与 ◑（⌘M AX 读限）双列计入两桶；实桶 = 纯✓9 / 混合✓/◑3 /
  纯◑3 / ✗1 = 16。判定本身无矛盾（面 15 功能腿过、读限如实记录），口径
  注记建议后续卷补一行说明。
- **minor-3**：T7 三臂留档之 A 臂二进制 `/tmp/f0p2-dd-A` 经 2026-10-20
  20:48 watchdog 重启消亡（/tmp 清空）；D-6 数据 logs（median 0.0×3 /
  97.6）+ B 臂（主容器）+ C 位记录在库，A 臂可按 `host-equivalence/
  README.md` 配方自 `907c373d` 重建——载体 ephemeral，数据与配方在档。
- **obs-1**：G3 事件链全录（§一）。
- **obs-2**：独立复跑 + D-6 复测移交二路（§五）。
- **obs-3**：探针 fixtures 重建为 2 ARW link（原 DNG 消亡；轮未消费，
  形态对机检无影响）。
- **obs-4**：BUNDLE-MAP +8 行 = 4 数据行 + 4 登记注释行。
- **obs-5**：tuist generate 恒末位（L041）= commit body 自述；xcodeproj
  不入 git，产物时间序面核不可行（以 Project.swift/BUNDLE-MAP 内容面 +
  构建绿承载）。
- **obs-6**：phase 目录存前轮中止验收残留（`probe/logs/acc-r1..r3`、
  `all-runs/acc2-*.log`）未清理；不影响本轮判定，二路读档时注意区分。
- **obs-7**：壳侧行号微漂移（displayPlaneHash 实测 :2023 vs DECISIONS :1923；
  AI 探针调用点 :2257 vs :2254）——记录时点差，语义零差。

## 七、guard 记录摘要

构建前 / 四族定向前两次 **GUARD PASS**；探针与全套轮 **GUARD BLOCK（G3
swap 残留 ≥1GB，连续轮询无回落至门内）→ 按裁决 (b) CHAIN-ABORT**，自出
进程链清零（ps 复核 0 残留），swap 自然回落未干预。全程未并行任何重活；
GUI 臂与测试轮严格串行（探针轮实际未起跑——被 guard 前置拦截）。
