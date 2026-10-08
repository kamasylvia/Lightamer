# M3-1-03 DECISIONS — 小件族合并批 + zh 清算 + phase 收口

> 执行批 2026-10-08（夜间全自动授权在案）。plan = checker 修正版 M3-1-03-PLAN.md；
> 两处「> checker 回注」引注（M6 旁路键控/FULL 桶判定面语义、E2 登记）照办，见 D4/E2。
> 提交链：T1 `7a800a5` → T2 `158a468` → T3 `c5afe0d` → T4 `d4ae750` → T5 本批。

## D1 冲突档「会话态」的作用域 = Export 页视图寿命（KD-1 裁定的落地注记）

KD-1 裁定档位不入 UserDefaults（M2-9 记忆键族六键外零新增）。落地形态：档位活在
`ExportM2PanelModel`（视图 @State）——与该模型既有全部字段（pattern/metadataOn/
quality 四键显面）同层同寿命：**Export 页关闭再开（视图 identity 重建）即回落
Increment**。走查实测复验了该语义（选 Fail → 关页 → 重开 = Increment）。这不是
缺陷：pattern 等字段自 M2-9-04 起就是这个作用域，「会话态」在 M2-9 语境一贯指
「非持久」。若用户要走查后提出跨页开关记忆，属 plan 风险节预告的新挂账（UserDefaults
键登记纪律外零新增，不得顺手加键）。

## D2 run face 装配缝 = `ExportM2PanelModel.makeRunAssembly`（KD-4 角色延伸）

run face 的装配参数束（batch/overrides/drtRecord/variant/pattern/collisionPolicy/
destination/subfolder）从 `runExport` 的内联代码提为模型纯函数 `makeRunAssembly`
（+`RunAssembly` 值类型），视图只留 I/O（flushSidecar/enqueue/write-backs/toast）。
理由：①模型 MARK「The assembly input faces」本就是该角色（makeVariant/makeSizing
同族）；②「run 传值装配」进 plan T1 测试清单——纯缝使其可机检（picker 值逐档断言
达装配束），否则该 AC 只剩编译期保证。行为等价性：装配输入的读取顺序（sync 读 →
Task 内 flush → enqueue）与重构前逐位一致（overrides 仍是 flush 前的活投影快照）。
`ExportState.enqueueExportM2` 形参零改（红线域，`git diff` 机检零命中）；state 层
collisionPolicy 透传消费由既有 `ExportAssemblyTests` 真队列捕获面覆盖，零新引擎测试。

## D3 旁路状态机：先验值记忆 + commit 自愈 + 重建清扫（KD-3 的三道防线）

`EditorState.previewDenoiseBypass: [UUID: Bool]`（实例 UUID → arm 时先验 enabled）：

1. **先验值记忆**：disarm 恢复 arm 时的真值——用户先行 disable 的实例拖完后保持
   disable（否则 disarm 会错误点亮；「edit implies enable」的既有 commit 语义不受
   扰：提交快照带 enabled=false → autoEnable 照旧翻真）。
2. **commit 自愈**：`recordChange` 对被提交实例强制 disarm（真实流程 disarm 先于
   endEditing——D9；此防线兜任何竞态提交路径把「instances ≠ history 真相」的分歧
   钉死：commit 即真相落地，旁路必须让位）。
3. **重建清扫**：`resetHistoryForNewImage`（load）+ `rebuildInstances`（undo/redo/
   jump/version swap/sidecar restore 共用路径）清空旁路表——陈旧 force-false 不得
   活过手势窗口。

upsert 投影强制（`applyLiveInstance` 路径把 tick 快照的 enabled 压回 false）保证拖动
窗口内面板 tick（自带 enabled=true）不复活旁路。双 arm guard（幂等）+ 无 arm disarm
（no-op）钉死。**跳过（enabled=false）而非减趟** = plan KD-3 降档维度裁定的兑现
（decimate 减趟已证不达 16.6ms，perf.md:43-64）；观感复核位 = Manual-Only（D8）。

## D4 FULL 桶判定面语义（checker M6 照办登记）

旁路只落 EditorState live 投影（instances 记录的 enabled 位），**从不进入**
`liveEdited`（coordinator 的 commit 快照集）——因此：①提交快照恒带真实 enabled；
②拖动窗外（旁路表空）FULL 渲染的判定面逐字节不变（AC3 判定式）；③拖动窗内并发的
FULL 重渲短暂缺 denoise = plan 风险节已登记项（根治 = M4 coordinator 串行化余量，
ToneEqual 修复批同款归位），不构成 AC 违反。旁路键控 = 被拖实例 UUID（非 opName）：
测试 `testBypassDisablesOnlyTheDraggedInstanceLiveProjection` 以双 nlmeans 记录
（layer-embedded 形态：异 UUID + multiPriority 1）钉死零连带。

## D5 zh-audit 硬化的验收形态 = 脚本 `--self-test`（执行期二选一，plan 纪律 3）

`ZhAuditExtractorTests` 形态裁定为**脚本自测面**（`zh-audit.py --self-test` golden
fixtures 扩 two continuation 样例：静态键 next-line 形态 + 插值前缀 next-line 形态
），零 XCTest 登记、零 Project.swift churn。理由：提取器是流程工具非产线（plan 风险
节），self-test 与既有四 violation case 同住一处、`uv run python3 Scripts/zh-audit.py
--self-test` 一条命令可验，与 `test-direct-selftest.sh` 同款自证形态。

## D6 硬化立即战果：两枚真缺口入账（T4 范围内的「补 zh 值同批」）

硬化后首轮 `--check` 即抓出 `search_exif_placeholder` / `search_clip_placeholder`
（GlobalSearchDialog TextField 的 next-line continuation 形态，M2-7 起对提取器不可见
= 对账清单盲区）：**catalog 里根本没有这两键**——运行时回退 en defaultValue（en 可见
zh 缺失的真缺口）。两键 en 值逐字转录代码 defaultValue，zh 值同批补齐入 catalog
（plan T4「补 zh 值 = 键块 append/修订同批」授权范围内）。

## D7 路上发现不顺手修：两处 verbatim「Import Folder…」同族（M2-3-4 先例）

F1 sweep 执行中发现同族 verbatim 残余两处：File 菜单项 `LightamerApp.swift:1301`
`Text(verbatim: "Import Folder…")` + 面板标题实参 `:1635`
`LibraryPanels.folder(title: "Import Folder")`。按 M2-3-4 验收批既定先例（「发现
翻译错误不顺手修」）+ plan 钉死的 F1 四处半径，**登记不修**（本文件 + SUMMARY 挂账
节）；归后续 zh 专项 sweep 余量。同轮亦核：legacy 会话空态文案（「选择文件夹以创建
会话」族）为既有 zh 在册键的呈现，非缺口。

## D8 T3 实机走查 = Manual-Only 登记（plan 纪律 4 兜底条款行使）

nlmeans 面板在默认 Alcedo IA **结构不可达**：①M2-1 default-face 禁用集成员
（`LightamerIOPRegistry.defaultFaceDisabledOpNames`，面板注册被 gated）；②M2-3 tab
shell 描述符表（`EditorTabRoute.swift:206-272`）无 nlmeans 席位（legacy 件不进
Alcedo IA——2026-09-27 项目重定义的自然结果）。`LIGHTAMER_FULL_IOP_FACE=1` +
`LIGHTAMER_LEGACY_LIBRARY=1` 双 env QA 通道尝试：legacy 会话宿主（「选择文件夹以创建
会话」空态）与项目 workspace 图片绑定断层，两轮 relaunch 复现未挂上，走查中止按
Manual-Only 登记（补走查配方落 MANIFEST）。补偿性覆盖：状态层六测（身份键控/零
params 零 history/松手恰一 commit + enabled 复原/零 tick 不伪造 commit/重建清扫/
session 路由）+ 面板挂点编译期接线 + D-H1 trio 既有 PanelWiringTests 同构语义。

## D9 面板 disarm 先于 endEditing（顺序裁定）

`NLMeansPanelView.dragEnd()` = 先 `setPreviewDenoiseBypass(off)` 再 `endEditing`：
disarm 同步恢复 instances 真值，其后 commit 的 upsert（经 recordChange，旁路已清）
落真实 enabled——避免「commit 落地时旁路仍在 → upsert 强制压 false → 再 disarm 复原」
的两段翻转窗（其间任何渲染 pass 都可能读到假 false）。arm 侧同理 begin 先、旁路后
（首个 tick 前生效即可，无竞态面）。

## E2 登记闭环（checker 引注照办）

ExportCollisionPickerTests（APP 5）随 T1 commit、NLMeansDragDowngradeTests（APP 6）
随 T3 commit 分别登记 Project.swift 显式清单 + BUNDLE-MAP 增行；`tuist generate` 恒
各自批次最后动作（L041）；行值 = `grep -c "func test"` 三方对表。zh-audit 硬化走
D5 脚本自测形态 = 零登记面（豁免成立注记）。
