# F0P-03 DECISIONS — plan P3 执行裁定记录

> 正本性质：plan F0P-03（死码退役 + FB 回填 + README 勘正）执行期裁定 +
> 偏差申报。规格正本 = `F0P-03-PLAN.md`；裁决正本 = `CONTEXT.md`。

## D-F0P-03-1 退役域圈定终账（T1 action 1「先圈后删」兑现）

开工前逐段圈定（plan read_first 第 4 条）与实际删除域一致；圈定记录：

- 删除：`LightamerColumnVisibilityKey` 结构 + FocusedValues 扩展的
  columnVisibility 访问器半边（ExportPanelRequestKey 半边保留）；
  struct doc 注释（:254-260）+ `internal struct LightamerApp: App`
  全体（:261-2915，文件尾——omp M1 勘正域）；entry 内死行。
- 保留（零 diff 逐段面核）：`ExportPanelRequestKey` + 扩展 exportPanel
  Request 半边（+ 保留说明注释一条——omp M2 (a) 的「保留说明行」兑现
  ，注记四 publish 面退役后壳侧读 nil → honest-degrade 零行为面）；
  entry enum + DEBUG fork 四把 + `LightamerShellMain.run()` 尾（恰一调
  用点机检 ✓）；AppDelegate 类（勘误④域零 hunk）；WindowCapture；
  McpWriteFaceBox(:42)/PanoFailureCopy(:71)/LightamerEntryPoint(:129)
  文件域件。
- **Focused-value 键族命运（omp M2 (a) 采纳兑现）**：
  `LightamerColumnVisibilityKey`/`MetadataFieldFocusedKey`/
  `WorkspaceModelKey` 三键 + 各自 FocusedValues extension 面 + 四处
  publish（ContentView 根链 ×2 + InspectorPageMount export-page 腿 ×1
  + WorkspaceHostView ×1 + InspectorView ×1）全退役；
  `ExportPanelRequestKey` 定义保留——壳 :94 `@FocusedBinding` 活依赖，
  发布面摘除后恒读 nil → 壳 export 动作 honest-degrade 页路由（壳
  :2062-2071 注释在案的既设退化路径，**零行为面论证**：gate=false 页腿
  = `openExportPage` 同面渲染；gate=true sheet 腿 = focused publisher
  缺席时同缝降级——P1 D-F0P-01-6.2 已验的两面同缝）。**B19/B20 note
  修饰符零 diff**（活链维持）。
- probe armed 旗标对账（research-omp M3）：App struct 侧
  resize/import/sidecar 三旗标随 struct 消亡；壳侧 Face 自有旗标（P1
  迁移形）在位零触；AI determinism 探针原注「P1 已迁壳」不准确之勘正
  = 本轮函数本体真迁壳（此前壳侧只有调用无宿主）。

## D-F0P-03-2 static 转移终形（T1 action 2）

- `batchPasteBlocked`/`readOnlyPasteToast`：**壳已有同名实现**（P1 面搬
  运时已带，ShellFace :1832/:1838）——「或保留同名转发」二选一裁定为
  **纯删 App struct 侧副本 + 测试重指壳类型**（无转发层，单源）。
- `displayPlaneHash`：壳 :1923 自带副本亲核 → App struct 侧安全删除。
- `runAIDeterminismProbeIfRequested`：迁壳 LightamerShellFace（DEBUG 块
  内、resize/sidecar/import 探针同处形态）+ `LightamerShellController
  .init` 调用点同 commit 重指——**壳侧恰两 hunk**（函数体 + 一行重指；
  plan 红线「单 hunk 面核」读法 = 调用点重指恰一 hunk + 迁壳本体为其授
  权伴生 hunk，`git diff` 逐 hunk 面核在案）。函数本体逐字搬运（原
  `static func` internal 语义维持）。

## D-F0P-03-3 重指终形（T1 action 4）

- `AgentControlCoordinatorTests` face ⑤ 行：旧
  `("UI/LightamerApp.swift", "|| agentControl.holdsControl)", …)` → 新
  `("UI/Shell/LightamerShell.swift", "guard !agentControl.holdsControl
  else { return }", …)`——token 对准壳内三处命令闭包守卫（:201/:205/
  :209 = undo/redo/project commands 的活源，face ⑤ 语义等价）；行内注
  记退役重指来源。其余 11 face 行零触。
- `ProjectReadOnlyFaceTests`：6 处 `LightamerApp.batchPasteBlocked/
  readOnlyPasteToast` → `LightamerShellFace.*`（4+2）。

## D-F0P-03-4 T2 七门输出（命令级，收口留痕）

见 SUMMARY §二（逐条 grep 判据 + 豁免形清单）。补充裁定：`Settings {`
门用词边界精确 grep（`(^|[^a-zA-Z])Settings \{`）——裸子串命中
`YiyinExportSettings {` 尾串为类型名非场景声明（机检读法申报，m-omp-5
scoping 同源）。**T2 无独立 commit**：纯机检零文件变更，空提交为全局
禁令所限—— outputs 全文落本文件 + SUMMARY §二，随 T5 docs commit 留
痕（deviation 申报）。

## D-F0P-03-5 T5 复证账

- App bundle 定向轮 **943/6/0**（退役零 ΔN；P2 终态逐值维持；--all 不
  强制 = plan expected_all 条款，未获新批准不跑）。
- 五点抽样全过（MANIFEST §九）：启动+项目/编辑器进出/三窗/五路菜单分
  发/退出链——退役后直启二进制（0c70e608 构建）行为面与退役前逐点同。
- 偏差：无新增（walkthrough 走 P1 配方；window 关闭用 AXCloseButton
  缝——与 P2 同法）。

## 偏差申报（行内 (deviation) 标记累计）

- **(deviation)-1**（T2）：无独立 commit（空提交禁令），机检输出落
  docs commit（上 §四）。
- **(deviation)-2**（T1）：壳侧 diff = 两 hunk 非「单 hunk」字面（迁壳
  本体 + 调用点重指；plan 文本括注「迁壳同 commit」已含本体授权——读
  法申报 + 逐 hunk 面核留痕）。
- **(deviation)-3**（T3）：终章以 `## 终章（append,…）` 形式追加（历
  史章节零触碰纪律；修订节 1-4 不改写，数值以终章为准并显式声明）。
