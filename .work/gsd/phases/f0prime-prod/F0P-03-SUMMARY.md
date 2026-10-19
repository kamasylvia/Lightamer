# F0P-03 SUMMARY — plan P3 执行摘要（死码退役 + FB 回填 + README 勘正）

> 执行窗：2026-10-20（单 worker 会话，commit-per-task，全英文，未 push）。
> 执行正本 = `F0P-03-PLAN.md`；裁定正本 = `CONTEXT.md`（勘误②⑦落位）；
> 逐任务裁定 = `F0P-03-DECISIONS.md`；抽样复证 =
> `.work/gui-acceptance/f0prime-p1/MANIFEST.md` §九。**执行到 P3 收口为止
> ——全批 C 档停，收口呈用户（FB 终章 + README 勘正同批过目）。**

## 0. 结论头

**P3 全任务闭环：T1 App struct 全族退役 + 测试面重指同 commit 原子
（-2728 行/+60 行，7 文件）+ T2 退役 grep 七门全过 + T3 FB 稿终章回填
呈用户 + T4 README D-6 条目撤除 + toolbar 差异登记 + T5 五点抽样复证
全过 + App bundle 943/6/0（退役零 ΔN，P2 终态维持）。** 产线 commit 5
个；主树 tracked 零残留。

## 1. 逐任务 commit 表

| 任务 | commit | 内容 | 验收判定 |
|---|---|---|---|
| T1 退役+重指（同 commit 原子） | `0c70e608` | App struct 全族（@State 43 字段/scene builder/.commands/@FocusedBinding 面/openWindow/statics/probe armed 旗标）+ entry 死行 + 三键退役 + 四 publish 摘除 + AI 探针迁壳 + 调用点重指 + 2 测试文件重指 | 构建绿 ✓；App 943/6/0 ✓；`git show --stat` 恰七文件 ✓ |
| T2 退役 grep 机检族 | （输出落 DECISIONS §二——纯机检零文件变更为空提交禁令所限，随 T5 docs commit 留痕） | 七门逐条（见下） | 全过 ✓ |
| T3 FB 终章 | `89018697` | APPLE-FB-D6-DRAFT.md 终章回填（append-only；双重排除/churn 功能性发现/壳交接终数据 97.6→0.0/提交核对清单） | 四件在文档 ✓；**呈用户，不代提交** ✓ |
| T4 README 勘正 | `e1968e94` | D-6 条目撤除（定性 = 本 app 侧不再复现，upstream 缺陷不变）+ toolbar 差异行补入 | 两处变更恰面 ✓（`git diff` 面核） |
| T5 复证+收口 | （本 commit） | 五点抽样 + App 定向轮 + SUMMARY/DECISIONS | 全过 ✓ |

全波清单（git log --oneline，新→旧）：本 commit → e1968e94 → 89018697
→ 0c70e608 → b5fd46b2（P2 收口 docs）→ b25c270b …（P2 主体）。

## 2. T2 退役 grep 七门输出（命令级证据）

1. `.commands(` / `WindowGroup` / `Settings {` / `@FocusedBinding` /
   `focusedSceneValue` App target **代码行**零命中：
   - `.commands(` = 0；`WindowGroup` = 仅 2 条 `//` 注释（EditorMTKView:30 /
     SessionCoordinator:24——m-omp-5 豁免形存续）；`Settings {` 边界精确
     grep（`(^|[^a-zA-Z])Settings \{`）= 0（裸 grep 的 YiyinExportSettings
     尾串误命中已排除）；`focusedSceneValue` 代码行 = 0（注释豁免形 2 条
     在案）；`@FocusedBinding` = 恰 1 = **壳 :94 保留面**（omp M2 (a)
     豁免，`@FocusedBinding(\.exportPanelRequest)`）。
2. `LightamerApp.runAIDeterminism` = 0 + 壳内新宿主
   `static func runAIDeterminismProbeIfRequested` 恰 1（Shell :1612）。
3. `.runModal(` App/Sources = 0（L057 门复跑）。
4. `String.LocalizationValue("prefix_\(` 禁形 = 0。
5. `F0PrimeShell` = 0。
6. xcstrings diff = 空（全批零 diff 预期兑现）。
7. UserDefaults 应用级键 = 零新增（diff 面核）。

## 3. 退役边界终账（T1 圈定 vs 兑现）

- **删除域**：`internal struct LightamerApp: App` 全体（:261-2915 @
  0c70e608^，含 43 @State + scene builder + .commands 全块 + @FocusedBinding
  ×3 + @FocusedValue + toggleSidebar/toggleInspector + openWindow +
  batchPasteBlocked/readOnlyPasteToast/displayPlaneHash/
  runAIDeterminismProbeIfRequested statics + probe armed 旗标 ×3）+
  struct doc 注释 + `LightamerColumnVisibilityKey` + FocusedValues 扩展
  的 columnVisibility 半边 + entry 内 `_ = { LightamerApp.main() }` 死
  行。文件 2915 → 249 行。
- **保留域零 diff 逐 hunk 面核**：entry enum（fork 四把逐字）/
  AppDelegate 类（勘误④域）/ WindowCapture / McpWriteFaceBox /
  PanoFailureCopy / LightamerEntryPoint——`git diff` 该域零 hunk。
- **壳侧恰两 hunk**（omp M1 显式例外）：① 迁壳函数体（+43 行，
  ShellFace DEBUG 块内）② 调用点重指一行（:2254
  `LightamerShellFace.runAIDeterminismProbeIfRequested()`）——其余壳侧
  字节零触碰。
- **view 侧四处 publish 摘除**：ContentView ×2（根链）+ export page 腿
  ×1 + WorkspaceHostView ×1 + InspectorView ×1；B19/B20 note 修饰符零
  diff；两处本地键定义（WorkspaceModelKey/MetadataFieldFocusedKey + 各
  自 extension）随退役消亡。
- **去向表（research-omp M3 承接）**：batchPasteBlocked/readOnlyPasteToast
  → 壳已有同名实现（Face :1832/:1838），App struct 侧副本随 struct 消亡
  ，测试重指 `LightamerShellFace.*`；displayPlaneHash → 壳 :1923 自带副
  本（App struct 侧安全删除）；runAIDeterminismProbeIfRequested → 迁壳
  Face DEBUG 块（本轮 ②①）；probe armed 旗标 ×3 → 壳侧自有旗标（P1 已
  在位），App struct 侧随 struct 消亡；PanoFailureCopy/McpWriteFaceBox/
  LightamerEntryPoint → 文件域原地保留零 diff。

## 4. 全批 ΔN 终账

P1 +0 / P2 +22 / P3 +0 = **全批 +22** → 三轮 `TOTAL|3991/37/0|`
（3969 基线 + 22；带 3984..3994 内）。P3 App 定向轮 943/6/0 = P2 终态
逐值维持（退役零新增零丢失）。

## 5. 全批收口呈用户（C 档停）

- **FB 稿终章** = `research/APPLE-FB-D6-DRAFT.md` 终章节（提交核对清单
  四件全勾，末项 = 用户手动提交——禁代提交惯例维持）。
- **README** = Known Issues 两处变更（D-6 撤除注记定性 = upstream 缺陷
  不变；toolbar 差异登记行）。
- **挂账移交**：F2-1 ImportModeDialog 既有缺陷（双臂归因，修复候选 =
  M2-8-3 内容面重注入范式——不在退役批范围）；F2-2 session 空态面残留
  呈现；F2-3 yiyin 入口钮定位；P1 移交的 P2 首批归因项（标记应用链断 =
  既有缺陷队列；export 页「加入选中」按钮 action 失效归属未决）仍开放。
