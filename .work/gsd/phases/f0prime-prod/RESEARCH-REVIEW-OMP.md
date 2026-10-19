# RESEARCH-REVIEW-OMP — F0'-production 壳交接批 research 独立复审

> **对象**: `.work/gsd/phases/f0prime-prod/RESEARCH.md`（446 行，commit `9a0b9530` 落盘）
> **基座**: `.work/gsd/phases/nsmenu-spike/F0PRIME.md` + spike 分支 `spike/f0prime-shell`
> （`a35ad151`/`c9a91562`/`d8d1380a`）+ patch 归档 `0001..0003`（未入 git，盘上在案）
> **方法**: 纯只读；全部 file:line 引用以 research 基线 `9a0b9530` 的产线源码亲核
> （`git show 9a0b9530:<path>`），spike 引用以 patch 归档 + `c9a91562` 树亲核。
> **基线漂移**: `34364bf8..9a0b9530` 间 App/Tests 零触碰（仅 3 docs commits）——spike 与
> research 同产线基线，引用可比。
> **日期**: 2026-10-19。复审员：omp（制度路由）。

---

## 结论头

**PASS / 0 blocking + 4 major + 10 minor**

四条核心结论（壳交接可行 / 4 真缺口定盘 / 测试面轻 / 3-plan 切分）全部成立，
Scene 穷举经全量 grep 无漏网，untracked 审计方法与 F0PRIME §4.3 机制一致。
4 major 均为"生产化范围/验收锚点"类修正，不动 research 方向；其中 M1 基线勘误
plan 层已自行纠正（CONTEXT 转写勘误①），此处追认。10 minor 多为行号/计数转写
精度 + 2 处走查覆盖补项。**放行 plan 门，无需 research 返工**（findings 由各 plan
AC 直接认领）。

---

## 一、证据抽查（20 点亲核，≥8 要求）

| # | RESEARCH 断言 | 亲核结果 |
|---|---|---|
| 1 | §1.1 入口 fork 序 `LightamerApp.swift:128-158`，四把 fork 不构造 App 状态 | ✅ `9a0b9530` 源 `:129-155`：2 DEBUG fixture + headless + AI worker，全部早退，零 App 构造 |
| 2 | §1.1 `applicationWillTerminate` 参数 `Notification` load-bearing（:190-201） | ✅ `:190-196` 注释 + `:196` 签名；spike 转发 `:2364-2366` 逐字 |
| 3 | §4 App struct @State "全量 43 字段" | ⚠️ **实测 44 个 `@State` 声明**（§4 内部分类 34+6+3+1=44 自洽，唯标题数 43 错）→ m1 |
| 4 | §1.2#3 env 链 23 对象（:525-547）+ dark（:548） | ✅ 实测 `.environment` ×23 + `preferredColorScheme` ×1 |
| 5 | §1.2#2/#8/#9/#10/#11 窗与命令块行号 | ✅ `:507` 主窗 / `:1799-2205` commands / `:2212` preset / `:2224` mcp / `:2236` Settings，逐行命中 |
| 6 | §3-A1 zoom 签名 updateNSView 内读（:131-138），父 body 零 tracked read | ✅ 基线 `EditorMTKView.swift:131-134` 内读；`EditorAreaView` zoom 读仅 `:299` 手势闭包 + `:319/:322` onChange（非跟踪上下文）；ZoomHUD `:542-551` 自 body tracked（= 失效面只在菜单不在 HUD 的原因，与 research 一致） |
| 7 | §1.2#13 focused-value 4 键 + 发布/消费点 | ✅ 全树恰 4 `FocusedValueKey` 定义；发布 `ContentView:249-250/:798`、`WorkspaceHostView:195`、`InspectorView:428`；消费 `:449/:453/:459/:466` 全部命中 |
| 8 | §3.1b App target NSViewRepresentable 仅 2 文件 | ✅ `EditorMTKView.swift` + `LightamerApp.swift`（WindowCapture）；`NSViewControllerRepresentable` 全树 0 命中 |
| 9 | Scene 面穷举完备（无 WindowGroup/SceneStorage/MenuBarExtra/openURL/dismissWindow） | ✅ 全树 grep：`SceneStorage` 0、`MenuBarExtra`/`openURL`/`dismissWindow` 生产引用 0；`WindowGroup` 仅 3 处注释（`LightamerApp:497`、`SessionCoordinator:24`、`EditorMTKView:30`）；次级窗内容（Settings/Preset/Mcp 面）零 scene-env 依赖 |
| 10 | spike patch 行引用（run :2370 / 主窗 :2279 / App 菜单 :2622 / 窗菜单 :2911 / 观察 :3003 / 分发 :3047） | ✅ 逐点命中；`armObservation` 实测 18 读表达式 / 16 去重字段（research"16 字段"口径正确） |
| 11 | §3-B17 export note = onAppear 一次性 true | ✅ patch ContentView 段 `noteExportPanelRequestPresent(true)` 仅 onAppear，无 onChange 双态——时机缺陷坐实 |
| 12 | §3-缺口3 四项 stub | ✅ patch `:2171-2176`：`presetManager/mcpLauncher/showSidebar/showInspector` 均空闭包；export 已走 `openExportPage`（与 §2.4-3 一致） |
| 13 | §2.3 "paste 族 7 项受 holdsControl 合取（spike 已形）" | ❌ **证伪**：bridge paste 两臂（patch `:2741-2749`）无 holdsControl；产线 `:2000-2008` 谓词同样无；spike 仅 undo/redo 两臂有合取 → **M2** |
| 14 | §5.2 测试依赖 2 文件（`batchPasteBlocked` :2639 / 调用 :499-506；manifest :228-235） | ✅ 行号命中；但 census 不全（另有 3 测试相关 static + 文件域 helper + 8 测试文件引用 `LightamerApp`）→ **M3** |
| 15 | §5.4 `test-direct.sh:214` HOST_BIN + `:250-262` DYLD 注入，app main 照常跑 | ✅ 逐行命中；机制描述准确 |
| 16 | §5.1 App bundle "104 文件" / "grep ≈938 法" | ✅ App 域 `func test` 实测恰 **938**；104 = Project.swift 条目数，去重 101（2 文件双列）→ m2 |
| 17 | Bridge 生产化增量 "~300 行"前置：bridge 现状 | ⚠️ bridge 内 `accessibilityIdentifier` **0 命中**（`menu.*` AX 面丢失）；无 Close/performClose 项 → **M4** |
| 18 | §5.5/§7 基线 `3905/35/0`（M7-3） | ❌ **stale**：research 基线已含 audit-repair（`9898a0fb` 为 `9a0b9530` 祖先），真基线 `3969/37/0`；M7-6 收口已是 3963 → **M1** |
| 19 | §1.3 M7-6 plain-await 闭包（:1634-1647）+ admit（:1654-1660） | ✅ 逐段命中，闭包形态判断正确 |
| 20 | §3-D D-C3 `EditorAreaView:274-277` onChange(geo.size) | ✅ 命中；D4/D5 一行补丁判断成立（spike styleMask 4 项无 fullscreen，delegate 无 reopen，verified） |

---

## 二、Assumptions / 覆盖面 / 可行性评估（对照 F0PRIME）

1. **F0PRIME 结论承接正确**。双门 PASS（菜单权威 / −96pp / SwiftUI 存活）的引用忠实；
   §3.1a 把 §4.3"churn 机器功能性负载"转为空壳审计 premise，机制链（非追踪上下文 →
   churn 顺手 re-eval）与 F0PRIME §4.3 逐句可对，是本 research 最强的一节。
2. **Scene 穷举可信**。除抽查 9 外，另核：`@AppStorage` 仅存 ContentView 布局键族
   （hosting 桥下存活，与 OQ-F0P-8 的 SceneStorage 断言正交）；toolbar 3 组
   （:503/:532/:597）普查命中；sheet/overlay/alert/onChange/task 行号（:1666/:1681/
   :1710/:1750/:1761/:1771/:1782）逐行命中。**ufficient for P1 搬运**。
3. **菜单清单准确**。File 16 / Edit 8 / View 12 / Metadata 15 / Image 2 / Help 1 /
   App 7 的条目与行号经块级扫描核对；shortcut ≈47 复算 ≈46（舍入内）；`visibleCommandIDs`
   纯函数（`MenuCommandSet.swift:78`）KD-6 语义引用正确。缺口在 enabler 语义层（M2）与
   AX/Close 覆盖层（M4），不在条目层。
4. **缺口定盘 4 项全部真实**，修法方向正确：A1 构造参数化（OQ-F0P-7 推荐成立，与
   push-once 同构）/ B17 onChange 化 / C1+三窗 stub / D2 登记不修。审计点位 ~50 的量级可信。
   唯一审计内漏项是二阶的 noteGeometry 写腿稀疏化（m7），不升级预算。
5. **测试面"轻"的结论成立**：harness 已是 NSHosting 形（`SheetEnvironmentInjectionTests:66-80`、
   `ToastFaceTests:38-50` 亲核）、直启宿主机制判断正确、ΔN +15..+25 量级合理。
   但 §5.2 census 漏 3 个测试相关 static（M3），P3 退役半径被低估。
6. **可行性风险已诚实申报**：§1.2#5 wiring 搬运标"中（体量，机械）"、§5.4 测试宿主等价性
   设验证轮、§8 OQ 全带推荐且推荐多为保守侧（OQ-F0P-5 无回切论证成立：双壳并存确使 churn
   门失守）。OQ-F0P-2（toolbar 差异接受）与 spike 申报一致。
7. **覆盖面缺口**：gate=true legacy 菜单臂（m6）、audio？无。长会话 soak（m10，F0PRIME §5
   保留意见的第三项未入 §6.2 清单）。两者均为 P2 走查行级补项，不动结构。

---

## 三、Findings

### Major

- **M1（§5.5 + §7 P2 行）测试基线 `3905/35/0` 已 stale，真基线 `3969/37/0`**
  `App/Sources` 无关；证据 `git merge-base`：`9898a0fb`（audit-repair 收口，
  全套净轮 `TOTAL|3969/37/0|`）是 research 基线 `9a0b9530` 的祖先；且 M7-6 收口已是
  `3963/35/0`——"M7-3 基线"无论按落盘日（10-19）还是 research 标称日（10-18）都不成立。
  **处方**：P2 验收锚改为 `TOTAL|3969+ΔN/37/0|`（skip 37 = 35 + 探针族 2）；
  plan 层 CONTEXT 转写勘误①已纠正——本复审追认，P2 执行时以 CONTEXT 数为准，
  research 正文无需返工。

- **M2（§2.3）"paste 族 7 项受 holdsControl 合取（spike 已形）"证伪——spike 与产线均无**
  证据：patch 0002 `:2741-2749` paste 两臂 enabler = `hasPayload && !isReadOnly`
  （无 holdsControl）；产线 `LightamerApp.swift:2000-2008` `.disabled` 谓词同样无；
  spike 仅 undo/redo 两臂（`:2736-2749`）有合取。research 把 TODO 写成了 DONE。
  **处方**：P1 生产化清单加一项"paste 两臂（+ partial 对话框臂语义裁决）补 holdsControl
  合取"——注意这是相对现行产线的**行为变更**（现行菜单 paste 在 agent 持锁期可用；
  M7-5 manifest face ⑤ 原本只覆盖 undo/redo + project 命令），P1 需显式裁决并走查，
  不得静默合取。

- **M3（§5.2）测试依赖 census 不全——App struct 另有 3 测试相关 static + 文件域 helper，
  P3 退役半径被低估**
  证据（`9a0b9530` 基线）：`readOnlyPasteToast`（:2645，被 `ProjectReadOnlyFaceTests:508/512`
  调用——research 只列了 `batchPasteBlocked`）、`displayPlaneHash`（:2845，sidecar 恢复
  探针面）、`runAIDeterminismProbeIfRequested`（:2873，07-1 跨进程门）+ 3
  `nonisolated(unsafe)` probe armed 旗标（:2451/:2488/:2725）+ 文件域 `PanoFailureCopy`
 （被 `PanoMergeUITests:163-191` 调用）；Tests 全树引用 `LightamerApp` 共 8 文件
  （4 注释级 + `AIEntryPointsTests` AX marker pin + `AppLaunchTests:61` dark 断言）。
  **处方**：P3 退役计划把"statics/helpers 迁移清单"从 research 的 2 文件展开为：
  4 static + PanoFailureCopy + AppDelegate/WindowCapture/McpWriteFaceBox/LightamerEntryPoint
  去向表；probe 旗标随探针函数迁壳（research §4 行已覆盖，P3 认领即可）。

- **M4（§1/§2）spike→生产 bridge 增量被低估：AX 标识零覆盖 + 无 Close 项 +
  Toggle/动态 label 未核验**
  证据：patch 0002 全文 `accessibilityIdentifier` **0 命中**（产线 `menu.*`/`toolbar.*`
  AX 面在 bridge 下丢失——`AppLaunchTests` AX 腿 + gui-acceptance AX 走查受影响）；
  无 `Close`/`performClose` 项（OQ-F0P-3 的"1:1 对齐"必须读作**含新增 Close 项**，
  当前措辞 ambiguous）；softproof Toggle 的 `laState` 注册与 metadata 动态 label
  （rating/color 显式 switch 键）在 research 中零核验行。
  **处方**：P1 加"bridge AX 标识 1:1（与产线 `menu.*` 拼写同值）+ Close 项按现行 AX 实测
  落位"；P2 `NSMenuParityTests` 加 AX 键断言 + Toggle 态断言；§3.4 "~300 行"估算追加
  AX/Close 行（~30 行级，不升级量级）。

### Minor

- **m1（§4）"全量 43 字段"→ 实测 44 个 `@State` 声明**（`LightamerApp.swift:260-428`）；
  且"34 @Observable class-ref"标签不纯：内含 3 actor（`moduleRegistry`/`decoder`/
  `metalContext?`，后者还是 optional）+ 非 Observable 的 `McpWriteFaceBox` +
  optional actor 三件。**处方**：标题数改 44；迁移表把 actor/Box 行单列一行
  （处置不变，仍 controller let——仅标签诚实化）。
- **m2（§5.1）"104 文件" = Project.swift 条目数，去重 101**（`RasterEditFaceTests`/
  `RasterHdrViewportTests` 双列）；"charter 口径 921"已 stale，App 域实测 938
  （与 research 自测一致）。**处方**：P2 ΔN 对账以实跑 Executed 为准（research 已注），
  charter 数不再引用。
- **m3（§6.2-11）"MCP stdio 27 工具"stale**——research 基线 union 已是 **32**
 （M7-4 29 + M7-5 control 3）；已污染 `F0P-02-PLAN.md` 同行。**处方**：走查项改
  "stdio 32 工具冒烟"，F0P-02-PLAN 同行跟改。
- **m4（§9）"`:168` delegate"→ 实测 `AppDelegate` 类声明 `:175`**（:167-168 为注释）。
  **处方**：锚点改 `:175`。
- **m5（§1.1 + §3-D4）`terminateAfterLastWindowClosed=true` 称为"对齐 SwiftUI 默认"
  疑似倒置，且与 D4 reopen 处方互斥**：SwiftUI App 关末窗默认**驻留**（Dock 菜单栏在），
  `true` = 关窗即退（行为变更）；`true` 下 `applicationShouldHandleReopen` 永不可达，
  D4"补一行"成死码。**处方**：P1 二选一并走查——(a) 取 `false` + D4 reopen 生效
  （对齐 SwiftUI 现行）；(b) 取 `true` + D4 删除。research 推荐改 (a)。
- **m6（§1-§2）gate=true legacy 菜单臂未审计**：bridge 有 `visibleCommands`
  gate 接线（patch `:2616-2619`，deps 注入 verified），但 research 未核 session
  三项/saveItem 在 gate=true 下的 enable 面，也未列 legacy overlay 腿（`:1776`）
  在新壳下的存活。**处方**：P2 走查加 `LIGHTAMER_LEGACY_LIBRARY=1` 一行
  （session 菜单 + legacy overlay + Settings Catalogs 节）。
- **m7（§3-A1）修法未覆盖 `noteGeometry`/rememberedSizes 写腿稀疏化**：
  基线 `EditorMTKView.swift:154-158` 在 updateNSView 内写 `viewportState` remembered
  sizes（"App-scene menu seam"）；静默壳下该写仅 tracked 输入变化时跑。**处方**：
  P1 缺口1 验收加"menu actual/fit 落点尺寸 == 手势路径落点"对照断言（或走查行）。
- **m8（§7 P3）机检"`WindowGroup` 零命中"会命中 3 处既有注释**
  （`LightamerApp:497`、`SessionCoordinator:24`、`EditorMTKView:30`）。**处方**：
  P3 机检改注释豁免形（`grep -v '^\s*//'`）或顺手清 3 处注释。
- **m9（§2.4-2/OQ-F0P-1）spike 私有 selector 是字符串形**（patch `:2629`
  `Selector(("showSettingsWindow:"))`），字面量 grep 易漏。**处方**：P1 去桩验收加
  `grep -rn 'showSettingsWindow' App/Sources` 零命中。
- **m10（§6.2）F0PRIME §5 保留意见第三项"长会话行为"未入走查清单**（§6.2 覆盖了
  交互时延/连续手势，无 soak）。**处方**：P2 走查加一 soak 行（静置 30min + 复检
  %cpu/内存无爬升，L082 哨兵复用）。

---

## 四、放行意见

- **放行 plan 门**：4 major 中 M1 已在 plan 层纠正；M2/M3/M4 由 P1/P2/P3 的 AC
  直接认领（上文处方即 AC 行），无需 research 返工轮。
- Plan 层需同步的三处转写：m3（工具数 27→32）、M1（基线数，已做）、m9（去桩 grep）。
- 本复审零源码触碰；唯一写产物 = 本文件。
