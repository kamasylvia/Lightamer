# AR-01 DECISIONS — plan A 执行批裁定记录

> 执行窗：2026-10-17 夜间批（单执行者 ZCode subagent）；HEAD 基线 `c5570b05`
> （fixer 后）；波内 5 个任务 commit + 1 个 T5 定向轮归因 fixup，逐条裁定
> 如下。**执行中无「必须扩面」触发**（sheet 闭包重排 / legacyBody 触碰 /
> scopes 面改动 / 封存面触碰 / KD-3 三级读改形 / D-H1 提交语义改道全零）。

## D-AR1-1 C 路并入条款核对（红线条款，review F-9 义务）

**裁定：C 路合并 MANIFEST 未落盘，静态基线形态维持，条款保持活线。**
检索面：`.work/` 全域（`find .work -iname "*manifest*"`、LANEC/lane-c/automation
键 grep、`.work/audits/` 目录亲列）——C 路 automation（`automation-af8b6363`，
周一 00:00）产物三路合并 MANIFEST **不在库**（`RESEARCH.md` §11 与 CONTEXT
头注登记的落盘时点未发生）。处置：①本批按 plan front-matter 静态基线
`3963/35/0` + ΔN 带 +1..7（终值带 3964..3970）执行对账；②C 路 MANIFEST 落盘
时点的基线重算义务（RESEARCH §11②）**随条款保持**——落盘后 B/C 批开工前
重算并差分申报；③C 路推翻 A/B 清单项的修正义务同上活线。

## D-AR1-2 F-6 byte-frozen 机检命令形（review F-6 偏移适配申报）

**裁定：F-6 判据按内容域零输出兑现，命令形以 offset 适配版执行，语义恒等。**
plan 原文命令 `diff <(git show HEAD:ContentView.swift | sed -n '248,418p')
<(sed -n '248,418p' 工作版)` 的固定行号前提 = gate-false 臂编辑不改变
:248 之前的行数——实际 T2 臂收窄 38 行（`InspectorPageMount` 下沉），新增
struct 落文件尾（不动 :248 之前行序之外的任何段）。适配命令：
`diff <(git show c5570b05:<file> | sed -n '248,418p') <(sed -n '210,380p' <file>)`
= **零输出**；辅以 `git diff -U0` 全 hunk 归属面核（4 hunk 全落 gate-false
臂区 + 文件尾追加，legacyBody 段 :248-418 零 hunk）。T2 commit（`36322b5f`）
与 T5 收口（本文落盘时点）两次亲跑同值。偏差性质 = 机械偏移适配（行号随
臂内行数漂移），冻结语义（段内容逐字节零 diff）严格成立。

## D-AR1-3 T-M1c topBar 窄值输入形（D-M7-AR-2 字面形落地 + RESEARCH 目标句澄清）

**裁定：按 plan SC 字面形（窄值 phase/projectName/isReadOnly/holdsControl +
回调）落地；isReadOnly/holdsControl 的读点留在宿主 body 的 WorkspaceTopBar
构造点。** RESEARCH §2 修法句「isReadOnly/holdsControl 变化只重估 topBar」
的完全叶隔离需给 WorkspaceTopBar 注入 controller/coordinator 引用（叶内
自读）——与 plan SC「窄输入 phase/projectName/isReadOnly/holdsControl + 回
调闭包」的字面参数清单冲突；执行按 SC 字面形（SC = 机检契约正本，其 T1
验收 grep 面不含 isReadOnly/holdsControl 命中面），代价 = 两属性变化仍重估
宿主 body（param 读点）。影响面评估：两属性均为罕见交互事件（只读切换 /
agent 持权），非 D-6 探针测量面（idle CPU）；高频 churn 源（toast/banner/
四 onChange）已全部隔离。若晨审翻「完全叶隔离」→ WorkspaceTopBar 换
controller 引用注入形，机械改（一处 struct 签名 + Mount 点），零行为差。

## D-AR1-4 T2 InspectorPageMount 携带自有 @AppStorage（宽键复用申报）

**裁定：Mount 自持 `@AppStorage("layout.inspectorWidth")`（默认 240 与根同
值），根 body 的同键读保留（legacyBody byte-frozen 所需，属性不可删）。**
效果 = 列宽拖动只重估 Mount，不再重估 ContentView 根（优于改前）。**零新
UserDefaults 键**（同键二次声明，KD-4 红线字面满足）；`clamped()` 为
ContentView private 助手，Mount 内联同式 `CGFloat(min(max(w, 200), 460))`
（数学恒等）。

## D-AR1-5 T3 m2② isCustomLook 缓存键终形（F-3 成本对比证据）

**裁定：值键 memo 形（`@ObservationIgnored private var customLookMemo:
(record: DrtRecord, isCustom: Bool)?`），否决 plan 字面「按 recordHash 键
stored 缓存」的 stableHash 形——该形触 F-3 伪优化降级条款。** 成本对比：

| 形 | 单次读成本（hit 路径） | 失效正确性 |
|---|---|---|
| stableHash 键（plan 字面） | ~65 浮点 sorted-keys JSON 序列化 + FNV 字节散（数十 µs 级）≥ 被缓存比较本身 | 键在写点计算——但 KD-3 三级读模型侧无 record setter，history/carrier 腿无写点钩子（F-3 原文坐实）→ 键永不失效 = **伪优化 + 失效洞** |
| 值键 memo（落地方） | 一次 `DrtRecord ==`（12 顶层 + 53 detailed 浮点 + 少量字符串 ≈ 65 场比较，ns-µs 级）vs 原生 `DrtPresets.isCustomLook` = 7 look 快照 × 53 浮点比较（custom record 为全扫最坏 371 场）——hit 路径严格更廉 | record 值本身即键——record 变 = 键 miss = 重算；**无需任何写点钩子**（commit 点零触红线满足），无失效洞 |

两腿回归：`DrtPanelModelTests` +2 法（memo hit 语义恒等 + record 变更
refresh）。

## D-AR1-6 T3 m2③ placementTarget 缓存终形（写点刷新 + 读时活真相校验）

**裁定：layer-leg memo（`@ObservationIgnored (instance, layerID)`）+ 五写
面显式刷新（addPlacement / commitPlacement / tickPlacementRecord /
resetPlacementSide / stepM）+ 每读活真相校验为主判。** 校验读
`coordinator.instanceRecord` + `editorState.adjustmentLayer(id:)` ——与重
扫同源的可观察读，**依赖注册保持**（链变更必触发重校验，无 stale UI——
undo/redo 或外部编辑使 memo 失配即全重扫）；hit 路径 = 一次 id 跳层 + 一
链 first-where + 一 `ModuleInstance ==`（全值比较含 paramsData 字节——id
比较不足以察觉参数替换，F-3 成本证据节登记），严格低于原重扫的 compactMap
分配 + 栈前层遍历。base-chain 腿不 memo（registry 探针已是字典命中，memo
反增开销）。

## D-AR1-7 T3 m9 键数终账（恰 +2..3 带落 +1，显式豁免申报）

**裁定：xcstrings 终账 = 恰 +1 键（`latitude_share_value`，`%@ %lld%%` 格
式），label 作参形——带下界外（带 +2..3），理由链如下，晨审可翻。** plan
带预估 +2..3 = per-share 三键形（below/inside/above 各带 baked label）；
首版按三键落地后 `zh-audit --check` 断言 2 抓出 **3 个孤儿键**
（`latitude_share_below/inside/above` 旧 label 键失引用）——三键形强迫二
选一：删历史键（违「历史键字节与顺序零触碰」）或改 zh-audit.py 内置
allowlist（plan files_modified 外文件）。改用单格式键 + 既有 label 键作
`%@` 参：label 键保持活引用（零孤儿，audit PASS 不触 allowlist）、zh 语序
由单一格式键承载（below/inside/above 三 share 平行结构，语序需求同形——
per-key 语序自由的收益为零）、DRY。终账：**+1 键**，尾块纯插入（deleted
lines = 0 机检），zh-audit --check + --self-test 双 PASS（1710 source keys /
1958 catalog keys / 38 interp 全 variant-PRESENT）。

## D-AR1-8 T4 FilmstripModelTests bundle 归属勘误（RESEARCH §7 errata）

**裁定：FilmstripModelTests 实际属 Library bundle（M2-4-0-BUNDLE-MAP :384
`LIB` 行 + Project.swift :584），非 RESEARCH §7 所记「全在 App bundle」。**
T4 验收面 = `--bundle Library FilmstripModelTests` 8/0/0（6 改写 + 2 新回
归）+ `--bundle Library` 全绿；T5 定向轮 `--bundle App` 不含该件——plan
front-matter `test_bundles: [APP]` 以 Library bundle 补跑覆盖（本批已跑，
终值见 SUMMARY）。勘误性质 = 测试文件归属记载错误，修法面零影响。

## D-AR1-9 T5 定向轮 fail 归因 + manifest token 同步（窗内 fixup）

**裁定：App 定向轮首轮 919/4/1，唯一 fail =
AgentControlCoordinatorTests.testDisableFaceManifestLandsTheMergeForm——
本批窗内（T1 Δfiles），非既有缺陷。** 机理 = M7-5 face-⑪ 源码 token
manifest 钉的是改前字面（`.disabled(projectController?.isReadOnly ?? false
|| agentControl.holdsControl)`）；T1 把读点收进 WorkspaceTopBar 窄值输入，
行为面不变（disabled 仍合并 isReadOnly ∥ agent-held），字面漂移。处置 =
manifest token 同步到重构后形（`.disabled(isReadOnly || holdsControl)`），
fixup commit `5c072a23`，复测 13/0/0。fixup 属 plan T5 回滚条款「窗内归因
→ 修复后复测」的正当行使。

## D-AR1-10 T5 探针记录节（F-8 钉死形，执行批亲跑）

### 判定：本批零越阈；门值 <10% 在基线树形本身不可达——窗外既有缺陷，停手上报（C 档头项）

**归因矩阵（同协议双构建对测，协议 = 真实 UI 驱动 + 60s settle 过 LUT 预热 +
30s 窗 6 采样中位）：**

| 面 | 基线 `c5570b05` | 本批 `5c072a23` | Δ |
|---|---|---|---|
| 编辑器静置（Open Recent 重开 → ⌘E 进编辑器，12s settle 形） | **193.7%** | **194.4%** | +0.7%（噪声级） |
| 编辑器静置（60s settle 形） | —（12s 形已证等值） | 192.9%（195→90 衰减形） | — |
| 空载无项目面（60s settle） | **31.4%** | **31.9%** | +0.5%（噪声级） |

逐面双构建相等 → **churn 为基线固有，非本批树形改动越阈**。基线 = FIX2 T1
裁定①「接受降级」的持续态（FIX2-VALIDATION：T1 零产线 diff + BLOCKED 分
支行使 + 表型终态 = functional-state-with-churn；FIX2-CONTEXT 既有证据
「三面 34-82% CPU」与本次空载面 ~31% / 编辑器面 ~90% 尾态同域）。plan T5
回滚条款的「逐任务 revert 二分」无需行使（基线已复现，归因在窗外）——按
「窗外 fail = 既有缺陷停手上报」上浮为 C 档停汇报头项：**D-6 探针硬门的
<10% 判据承自 FIX2-01-PLAN 的 SC 原文，但 FIX2 实际结局（裁定①）使该值
从未成为树形的既有属性；门前提在本批开工前已不成立**。修复路径 = FIX2 三
选一①登记的「gate=false 壳减树/窗口内容拆分专项立项」（挂账域，本批零触
——本批的树减面（modifier/Mount/子 View 下沉）方向正确但幅度不足以跨阈）。

### 三铁条核验（本批构建，探针 drive 记录 = /tmp/ar01-d6-probe/drive-*.txt）

- **①spin 消失：NOT-PASS**（~90% 尾态持续，基线同值——同上表，既有态）。
- **②filmstrip 点击换图出图：PASS**——cliclick 真实鼠标点击第二行 →
  acc5 选中环 + current dot + 视口渲染 + 直方图跟随（证据 =
  `/tmp/ar01-d6-probe/state-editor-after-click.png`；functional-with-churn
  表型确认，非 FIX2 前「点击死 + 黑视口」）。
- **③截图证据：在案**（state-editor.png / state-editor-before.png /
  state-noproject.png；local-only /tmp 即弃域，验收批按 MANIFEST 配方重产）。

### 协议勘定过程（F-8 执行记录，供验收批复跑避坑）

1. **`-la_editor_probe` seam 不可用作静置探针**：六行加载完成后
   `NSApp.terminate(nil)`（WorkspaceHostView.swift:1833——仅 `-la_film_probe`
   臂 stay-alive）。首轮 seam 形探针的 199% 读数 = LUT 预热（M7-4，~50s）
   + 导入 + 六行解码的**工作态**，非静置态——该轮 FAIL 判定作废。
2. **`open` 启动的 GUI 实例 stderr 不可捕**（探针 note 走 stderr）——完成
   判据改走截图 + 时序 settle。
3. **LUT 预热窗**：`open` 启动不继承 shell env（LIGHTAMER_SKIP_LUT_PREHEAT
   不生效）→ 静置窗必须 settle ≥60s 过 ~50s 预热。
4. **AI 分析询问对话框**（`library.ai.labelingMode` ask 默认）会挂模态——
   探针轮以 `defaults write` 预置 `never` 抑制（steady-state face），**探针
   后已 `defaults delete` 还原用户默认**。
5. **真实 UI 驱动链**（round 3 定稿形）：AX (osascript System Events，权限
   在) 点 文件 > Open Recent Project > 首项（6 图 editor-probe 项目）→ 等
   网格 12s → 点 进入编辑器 → 等 12s（60s settle 形另加预热窗）→ pid
   parentage（GUI parent = launchd [1]，本轮实测 pid=75093/77493/77118/
   78161 四轮全 `parent=1`）→ 30s 窗 6 采样（间隔 6s）中位 → sample 3s 栈
   旁证 + cliclick 铁条② + 截图。
6. **栈旁证**（sample-editor.txt，本批构建）：主线程 AG::Graph update +
   NSView _layoutSubtree + SwiftUICore DisplayList/layout 帧族（与 FIX2
   侦查的 layout-churn 域一致；零 Lightamer 业务帧挂环）。

### 门值修订建议（呈 orchestrator/用户晨审，非本批自裁）

探针门的行使语义修订为二选一：**(a) 相对门** = 本批 vs 基线同协议差分 ≤
噪声带（本次实测 +0.7%/+0.5% → PASS）；**(b) 绝对门** <10% = 与 D-6 专项
立项绑定（专项落地后才有意义，单独对任何树形改动行使都会 FAIL 在基线）。
现 plan 文本的绝对门在既有持续态下为永假式。本批按 (a) 语义判定 PASS、按
(b) 字面如实申报 FAIL 并上报——最终裁定留用户晨审。

## D-AR1-11 其余微偏差清单（逐项零影响申报）

- **T1**：`rebuildLibrarySurface()` 并入既有 `.task` 链首行（plan 允许
  「合并或并列」，取合并——aiEntry.configure 在 rebuild 之后求值，与改前
  onAppear→task 的 configure-after-rebuild 顺序逐位一致）。
- **T1**：`StackCommandModifier` 的 gridModel 依赖 = init 参数（非弱引用）
  ——宿主 @State 类引用，host 每次表面重建 body 求值自然重装；循环持有不
  成立（LibraryGridModel 不回指 modifier）。ImportProgressModifier 同形 +
  adapter lifecycle（原宿主 @State）随观察迁 modifier 自持 @State（modifier
  挂载位寿命 = 原宿主 @State 寿命，语义恒等）。
- **T2**：plan 字面 `ForEach(grid.rows.enumerated(), id: \.element.id)` 不
  可编译（EnumeratedSequence 非 RandomAccessCollection）——落地形
  `ForEach(Array(grid.rows.enumerated()), id: \.element.id)`（Array 包裹，
  身份仍 row.id，机械适配）。
- **T3**：Film 拆分把原 `model?.` 可选链降为子 View 的非可选 `model.`
  直读（子 View 仅在 model 存在时挂载——mount 点 `if let model` 门保证，
  语义恒等）；`placementAnchors` 的 `?? fallback` 撤除（非可选属性，?? 恒
  不触发，原为 nil-model 防御）。`row` 行壳助手在
  SessionControlsView/PlacementSectionView 各持一份私有副本（10 行 shell
  复制 vs 跨 struct 共享 fileprivate 函数——行为冻结批取复制避免调用点
  文字漂移）；Drt 四组各持 `row` 同理。
- **T3**：DrtPanelView 静态名助手（spaceName/eotfName/limitingName/
  presetName）原地保留于 DrtPanelView（四组经 `DrtPanelView.xxx` 调用）
  ——plan 未规定迁出，最小位移。
- **T4**：FilmstripModel 新增 `warmWindow(idToIndex:)` 参数形 + 属性形双
  面（refreshWindow 单次建 map 复用；属性面重建供测试断言）——plan「
  refreshWindow 时 idToIndex 字典重建」的字面兑现 + 断言面便利，`warmWindow
  Range<Int>` 语义零改。
- **T4**：`visibleIDs` 剪枝（`formIntersection(map.keys)`）为 plan「无
  stale id 残留」判据的实现面——删除/重排形下死 id 不得参与窗计算；
  requestedIDs 暖集保持 full-disappear 取消契约零改（预存行为，旧 index
  形同款）。
- **o9**：EditorAdjustmentStackView 会话缓存 = `@State (session, scope)` +
  `onChange(of: activeLayerID)` 写点重装；scope 变更抢跑 onChange tick 的
  窗口内走构造回落（每 scope 变一次分配，非每 body）；pipeCoordinator 环
  境为 app-root 单例（弱引用持有），不设其变更钩子。
