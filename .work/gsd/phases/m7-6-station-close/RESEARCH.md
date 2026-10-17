# M7-6 RESEARCH — M7 站收官 phase（SKILLS-01 + UQ-A1/UQ-L1 + 三缺陷 + 站级 VALIDATION）

> phase = `m7-6-station-close`；scope 六项定案正本 = `.work/GOAL-STATE.md` 续接点
> 2026-10-17 条 + `phases/m7-5-turn-taking/M7-5-SUMMARY.md` §M7-6 Scope。
> 本文件 = research 起草（只读侦察 + 本文件 doc-only 零源码）；ROADMAP §M7-6 行
> 为 Goal 正本（skill 仓机检 reference ✓ / UQ-A1 解码等值测试 ✓ / UQ-L1 交互
> 走查 ✓ / SC 数字门 = 站终验全套轮判定式兑现）。
> 基线 = `TOTAL|3950/35/0|`（M7-5 三路同值，exit 0 零 MEMFAIL）；本批 ΔN 预估带
> 见 §6。

## 0. Phase 定位与输入清单

| # | 项 | 定案来源 |
|---|---|---|
| ① | SKILLS-01 skills 文档仓（自家 CLI/MCP 的 agent 使用文档，Alcedo parity Block 3） | REQUIREMENTS :452 + survey :303 |
| ② | UQ-A1 预览层 ICC 双曲线失配 / UQ-L1 滑杆双击重置+横扫 scrub 分插 | REQUIREMENTS :458/:460 + UPSTREAM-QUEUE :14/:27 |
| ③ | major-1 setControlAdmit 生产接线（App/Sources 恰 1 定义 + 0 生产调用） | M7-5-SUMMARY §Leftovers 1 |
| ④ | minor-1 裸 stdio/http 臂 agentControl 两行 | M7-5-SUMMARY §Leftovers 2 |
| ⑤ | obs-3 acquire 复检硬化两行 | M7-5-SUMMARY §Leftovers 3 |
| ⑥ | M7 站 VALIDATION 收口（含 M7-5 签核） | M7-5-SUMMARY §Leftovers 6 |

编排红线（承袭）：**union 快照改动权已移交本波**（`McpFinalSnapshotTests.swift`
29→32 基线，五钉 23 不变；串行禁并行——本波若并行派发 = 停手上报）；
FIX2③ controller 零 diff 第四波维持（本批修法落点均不触 McpServerController
的 controller 面——minor-1 触同一文件的头less 装配臂，DECISIONS 申报即可）。

## 1. SKILLS-01：agent 操作 skill 文档仓形态

### 1.1 现状事实

**Alcedo 面实测**（`/Volumes/UNITEK/Documents/Development/AlcedoStudio`）：

- 本地仓 `.agents/skills/` = **16 个开发者工作流 skill**（alcedo-create-plan /
  msvc-cmake / opencl-program-registry / raw-processor-module 等——面向
  Alcedo 自己的编码 agent，非终端用户 agent）。形态 = 每 skill 一目录 +
  `SKILL.md`（front-matter `name` + `description: Use when ...`，正文
  markdown，可选 `references/` + `agents/openai.yaml`）。
- **面向外部 agent 的操作 skill = 独立外部仓**
  [alcedo-skills](https://github.com/zidage/alcedo-skills)（AU15 planned，
  本地仓无 `alcedo-automation` 目录——survey :131/:135/:203 证实）；CLI
  reference 由 `scripts/automation/generate_cli_reference.py` 从 schema 机检
  生成后发布至该外部仓。
- survey gap #27（:273）= agent 操作 skill 文档仓「缺，低成本高价值」；
  survey :303 给出两形态候选：**仓内 `docs/` 或独立 `lightamer-skills` 仓**；
  内容清单 = 会话启动（stdio 配置模板）/工具语义边界/错误码表/
  render_preview 预览语义（编辑态无印框）/UI 单位说明；**不含 taste**
  （taste 留 launcher `{{PROMPT}}` 模板载体）。

**我方 MCP 面**（机检正本已齐备）：

- 32 工具五域（域内清单逐工具钉死 = `Tests/LightamerTests/McpFinalSnapshotTests.swift`
  `all32` :270-272）：**editing 9**（apply_params / copy_adjustments /
  export_image / list_iops / load_image / render_preview / list_luts /
  match_color / paste_adjustments，:49 起）+ **culling 14**（:115 起）+
  **searchstate 3**（get_history / get_state / search_photos，:205 起）+
  **project 3**（list_versions / project_create / project_open，:230 起）+
  **control 3**（control_acquire / control_get / control_release，:253 起）。
- 会话启动面：GUI 臂 = `mcp-endpoint.json` 发现文件（schema v1 七字段 +
  auth none/bearer，`App/Sources/Lightamer/MCP/McpEndpointFile.swift` :61-75；
  loopback 默认零 token、`.lan` 强制 Bearer，`McpServerController.swift`
  :1046-1065）；无头臂 = `--mcp-stdio` / `--mcp-http` 两 flag
  （`runHeadless` :470-509）；launcher = `{{LIGHTAMER_MCP}}` 端点文件 +
  `{{PROMPT}}` 模板（survey :217，14-4 T1/T2 已产）。
- turn-taking 语义：控制命令免 admit、13 个 state-changing 工具过第三道门、
  错误码 19 档（controlNotHeld / controlRevokedByUser / controlBusy ≙
  Alcedo -32003/-32004/-32005 同构）、Stop→同 holder re-acquire = resume、
  无头恒持有（`ControlToolset.swift` :1-60 头注 + `AgentControlCoordinator.swift`
  :178-268）。
- 错误码表/描述 zh 面：`mcp_tool_desc_*` / `mcp_error_*` 族在
  xcstrings（source keys 1708，zh-audit 双 PASS）；`descriptionKeys` 映射表
  = `McpFinalSnapshotTests.swift` :401 起。
- **文档句挂账一件**：N2-2 get_state project 字段不对称（M7-2 挂账，GOAL-STATE
  M7-2 续接点「N2-2 → M7-6 SKILLS-01 文档句」）——已知面如实写进 skill 文档。

### 1.2 方案建议

- **形态 = 仓内 `skills/` 顶层目录，单 skill 多 reference**：
  `skills/lightamer-mcp/SKILL.md`（人写正文）+
  `skills/lightamer-mcp/references/tools.md`（机检生成 32 工具表：name /
  域 / readOnlyHint / schema 摘要 / description 键值）+
  `skills/lightamer-mcp/references/errors.md`（19 错误码表）。
  理由：Alcedo 独立仓的动机是「CLI reference 面向终端用户发布」——我方无
  CLI（挂账，survey 块三「建议默认不做」），分发需求不存在；机检测试同仓
  最简；未来若要独立仓 = 目录平移零重写。
- **SKILL.md 内容骨架**（每节一句话定位，细节进 references）：
  ① Installation & session start（GUI HTTP endpoint 发现 → `curl
  mcp-endpoint.json` → stdio client 配置模板；裸 `--mcp-stdio/--mcp-http`
  臂；launcher 模板）② Turn-taking 语义（先 control_acquire 再写、13 工具
  admit 面、Stop=用户收回 + re-acquire=resume、无头臂恒持有）③ 工具五域
  边界（哪域改像素/哪域只读/which 需要 project）④ 错误码表（19 档 + 三控
  制码语义与恢复动作）⑤ render_preview 语义（编辑态无印框 = M2 页域差异、
  compare:root + region 归一化 0..1）⑥ UI 单位说明（滑杆 range 单位与
  params 数值域映射）⑦ 已知面（N2-2 project 字段不对称句）。
- **机检形态 = 测试即门**：新测试法（新 `SkillsReferenceTests` 文件或
  McpFinalSnapshotTests 扩一法）从 `makeUnionRegistry().descriptors()` 活
  注册表渲染 markdown 与仓内 `references/tools.md` 逐字节比对——注册表
  演进漂移即红，零脚本维护面（对齐 `generate_cli_reference.py` 思路的
  golden-test 化）。
- **语言 = en 单语**：消费者是外部 LLM agent（英文最稳）；Alcedo 同款英文；
  skill 文件不进 xcstrings / 不进 zh-audit 面（DECISIONS 申报豁免即可）。
- **分发 = 随 git 仓**（README 一句链接）；不入 app bundle（v1 无用户可见
  消费面；bundle 内嵌挂账至有需求）。
- **红线**：零 Alcedo 文案搬运（其文档 GPL——禁译禁改全自写）；零 taste 规则。

### 1.3 验收形态

skill 仓机检 reference 生成 ✓（ROADMAP 定式）= 机检测试绿 + 人工抽读
SKILL.md 五节与产线行为一致（turn-taking 语义节可对照
`McpControlToolsetTests` 断言逐句核）。

## 2. UQ-A1：预览层 ICC 双曲线失配

### 2.1 现状事实（缺陷定义与落点）

- **缺陷定义**（UPSTREAM-QUEUE :14，上游 Alcedo `36db9a8`/#391 同病）：
  预览层挂 calibrated-RGB 近似空间（srgbPiecewise 以 2.2 幂近似分段），
  导出文件携 ICC v4——preview/文件双曲线解码失配。
- **预览面**：`App/Sources/Lightamer/UI/EditorMTKView.swift`
  `drtLayerColorSpace(_:)` :732-800——SDR 幂/BT.1886 臂 =
  `CGColorSpace(calibratedRGBWhitePoint:...)` 纯幂 gamma（:749-798）；
  **srgbPiecewise 以 `[2.2, 2.2, 2.2]` 幂近似**（:755-760，M4-1-01 KD-8
  DECISIONS 登记的显示侧偏离）。HDR 臂 = 系统命名 profile（:734-746）、
  linear 臂 = extendedLinearSRGB（:748）。
- **导出面**：`LightamerCore/Sources/Export/DrtOutputColorSpace.swift`
  `drtOutputColorSpace(space:eotf:)` :53-141（public，App 可直调）——SDR
  臂 = L053 自建 ICC v4 字节 → `CGColorSpace(iccProfileData:)`（:248-259）；
  **srgbPiecewise = curv 1024 采样表**（:72-77 rec709 / :89-92 p3d65，非
  para——L053 三坑守住）；per-(space,eotf) 永久缓存（:56）。
- **消费链**（blast radius 单链）：`drtLayerColorSpace` → `drtSurfaceSpec`
  （EditorMTKView.swift :804-811）→ `PipeCoordinator.drtViewportSurface`
  （:646-653）→ EditorMTKView layer colorspace。无第二消费者。
- **域差**：预览 SDR 组合域 ⊃ 导出合法域——导出 linkage table 只收
  rec709×{bt1886,gamma22,srgbPiecewise} / p3d65×{gamma22,st2084,
  srgbPiecewise} / p3d60×gamma26 / p3dci×gamma26 / xyz×gamma26 /
  rec2020×{st2084,hlg}（:59-137），gamma18 及其余组合 typed 拒；预览对全部
  space×SDR-eotf 组合都要能显示。

### 2.2 修复建议

`drtLayerColorSpace` SDR 幂臂改为**两段式**：legal 对先试
`DrtOutputColorSpace.drtOutputColorSpace(space:eotf:)`（Core public，
`try?` → 得导出同款 ICC v4——含 srgbPiecewise 真分段表；同享 per-pair
缓存零 per-frame 开销）；非法对（typed throw）**回落现行 calibrated 构造**
（预览显示义务：域外对仍须上屏；不扩导出 legal 表——那是 export 语义面）。
HDR/linear 臂零改（HDR 两侧同为系统命名 profile 语义一致；linear 仅预览
存在）。

### 2.3 验收形态（可机检）

1. **解码等值测试**（机检，ROADMAP 定式）：每 legal SDR 对，
   preview space 与 export space 同实例（或 ICC data 逐字节同）+ 经
   ColorSync 转换采样 ramp 等值（容差 ≤1 LSB @8bit）——真实咬合点 =
   钉死预览不再对 legal 对回落幂近似。
2. **负腿**：域外对（如 rec709×gamma18）仍产非 nil colorspace（calibrated
   回落在位）。
3. **走查观察项**（Manual-Only）：srgbPiecewise 预览观感微移（2.2 幂 → 真
   分段，低段略深）= 预期行为变化登记，非缺陷。

## 3. UQ-L1：滑杆双击重置 + 值横扫 scrub

### 3.1 现状事实

- **双击重置已在**：`App/Sources/Lightamer/UI/Inspector/LightamerSlider.swift`
  :72-74 整行 `onTapGesture(count: 2)` → `onReset?()`（:36 缺省 nil，:23
  `defaultValue`）；177 个调用点广泛接线 onReset（GradeScalarPanels :49/:65/
  :122/:175/:228/:282/:339、MonochromePanelView :40/:56/:65 等）。
  **缺口 = scrub**：readout Text（:65-69）无任何手势。
- **已知 wrinkle**（lightcraft `cb8b797c` 同款病灶）：整行 onTapGesture 含
  slider track 区——SwiftUI Slider track 点击会跳值，故 track 上双击 =
  第一击跳值（一次 commit）+ reset（第二步 history）。lightcraft 的修法
  （单击 thumb 不动值）基于自绘 egui widget，**不可平移到 SwiftUI Slider**
  （框架内部消费点击）。
- **lightcraft 实现**（正本两 commit）：`cb8b797c` KEY-SLIDER-RESET——
  label/thumb 双击回默认、单击 thumb 不动值、tooltip 提示、禁用滑杆不重置、
  一个 undo step；`ab64e9a5` KEY-SLIDER-SCRUB——press 值域横移 ≥3pt 进入
  scrub（travel 映射 track 宽度、Shift = 1/10 速、<3pt 仍为 click-to-type、
  clamp 到 range/steps、一个 undo step、jittery click 仍 type、拖离取消不
  留残值）。
- **yiyin 面板勘正**：`App/Sources/Lightamer/Yiyin/YiyinPanelView.swift`
  grep Slider 零命中——yiyin 面板无滑杆；UQ 条目「yiyin 面板与我方 iop
  面板通用」实际范围 = **iop 面板族（LightamerSlider 单组件全量覆盖）**。
- **自有 row 变体**：MonochromePanelView 自有 row 结构自带
  `onTapGesture(count: 2)`（:178），不组合 LightamerSlider。

### 3.2 接入点与交互冲突评估

- **接入点 = LightamerSlider 单组件**：readout Text 加
  `DragGesture(minimumDistance: 3)`；scrub 值 = 起点 + Δx/trackWidth×range
  （Shift ×0.1、clamp range）；**映射函数抽纯函数**（travel→value，可独立
  golden 测试）。
- **D-H1 三段语义兼容**（`LightamerSlider.swift` :4-10 头注契约）：scrub
  begin → `onDragBegin()`、per-tick → `onChange`（setLiveParams 0 history）、
  end → `onDragEnd()`（commitContinuousEdit）——scrub 必须**复用同三回调**
  而非旁路，则一次 scrub = 一次连续 commit。
- **denoise 拖动降档旁路**（M3-1-03）：其防线挂在 drag begin/end 投影与
  commit 自愈——scrub 走同回调面自然兼容，零额外接线。
- **冲突点**：①与 `.onTapGesture(count: 2)` 整行——scrub 手势在 readout
  子视图上，双击判定与拖拽判定需 minimumDistance 区分（3pt 阈值同
  lightcraft）；②AX identifier（:47/:63/:69）不动；③Monochrome 自有 row
  不获 scrub（范围决策 OQ-M7-6-5）。

### 3.3 验收形态

ROADMAP 定式「交互走查 ✓」（Manual-Only 走查：双击重置/横扫 scrub/Shift
细调/一个 commit 断言）+ 机检腿（纯函数映射：travel→value/clamp/Shift 系数
+ begin/end 配对计数断言）。tooltip/AX 若加 scrub 提示 → xcstrings 尾块
纯插入（如 `slider_scrub_hint`，zh-audit 对账同批）。

## 4. 三缺陷修法（major-1 / minor-1 / obs-3）

### 4.1 major-1：setControlAdmit 生产接线

**事实链**（亲证）：定义恰 1 = `App/Sources/Lightamer/MCP/McpToolRegistry.swift`
:367-371（actor 字段 `controlAdmit` :335，dispatch 序 writer→control→handler
:385-408）；生产调用 **0**，全仓 3 处调用全在测试 fixture
（`Tests/LightamerTests/McpControlToolsetTests.swift` :194/:253/:473）；四宿
主装配点均只 `setWriterCheck` 无 `setControlAdmit`——startReadOnlyHTTPHost
（`McpServerController.swift` :722-780，:737）、startHeadlessStdioHost
（:786-828，:819）、startHTTPHost（:1035-1113，:1081）、startEmbeddedServer
（:1165-1202）；GUI 装配 = `LightamerApp.swift` :1632-1651 传 controlContext
（acquire/release/state 三 provider）无 admit；admit 闭包从 App 到 registry
无通道（`AgentControlCoordinator.admit(toolName:)` :185-201 在位但无人消费）。

**两案对比**：

- **(a) 宿主透传参 +1 缺省 nil**：四宿主签名 + `startEmbeddedIfPreferenceEnabled`
  （:1137-1157，EmbeddedState box 加一字段承载）+ `startEmbeddedServer`
  直通；每宿主函数体 `setWriterCheck` 之后 `if let admit { await
  registry.setControlAdmit(admit) }`；GUI 装配点喂
  `{ name in try await MainActor.run { try agentControl.admit(toolName: name) } }`
  形闭包。无头臂 nil = 恒放行 = D-M7-5 正确语义，字节零 diff。
- **(b) box 暴露 registry 补接线**：`HttpHostHandle` 已持 registry
  （:1106-1108），但 startEmbeddedServer 不回传 handle（:1166-1194 内部吞
  掉）+ off→on preference toggle 重装配存在时序缝——需要 box 再加 registry
  载体 + 装配后二次接线，状态面更宽。

**推荐 = (a)**：与 `writerCheck` 装配先例完全同构（seam 在 host 函数体内
安装——:819/:1081 两处即先例形态），additive 缺省 nil 零回归，无 toggle
时序缝；(b) 的 handle 不回传 + 竞态两缝都要新面。伴 1 测试腿 = 真宿主
（`startHTTPHost` 带 admit stub 或 embedded 形）**未 acquire 直调
apply_params → controlNotHeld**（现状落 handler internalError——M7-5 第二
路 e2e 实锤），另建议 1 负腿钉无头臂 nil admit 恒放行不变。

### 4.2 minor-1：裸 stdio/http 臂 agentControl 两行

`McpServerController.swift` :482 与 :497 两处
`makeHeadlessSearchState(mode: mode)` 补 `agentControl: { McpControlState.headlessConstant }`
——与 :606（arbitrated 臂）拼写逐字同形（`makeHeadlessSearchState` 签名
:232-236 已有该参，缺省 nil → get_state control.agent = .null 镜像谎报）。
零回归风险（无测试钉裸臂 null 腿；可顺路 +1 断言腿钉裸臂 agent 非 null）。

### 4.3 obs-3：acquire 复检硬化

**事实链**：`App/Sources/Lightamer/State/AgentControlCoordinator.swift`
`acquire` 等待循环 :227-240（while liveEditActive → 内查 stoppedByUser/
deadline → 250ms poll）；循环退出后**无复检**直落 success 路径（:248-267，
:259 `stoppedByUser = false` 静默吞 Stop）。两变体：①Stop-in-final-window
（等待最后一轮 poll 窗口用户 Stop → 循环条件翻转退出不查）②并发异 holder
（入口 :216 预计算后挂起等待期间另一 holder acquire 成功 → 双持有）。

**硬化 = 循环退出后复检两行**：`stoppedByUser` → throw controlRevokedByUser
（同 :229 拼写）；`held ∧ holderName != holderName` → throw controlBusy
（同 :217 拼写）。测试腿 2（`AgentControlCoordinatorTests` 家族）：①
liveEditActive=true → 并发 stop() → flip false → expect revoked；②并发异
holder acquire 成功 → flip false → expect busy。

### 4.4 测试腿预估

三缺陷合计 +3..5 测试法（major-1 两腿 + obs-3 两腿 + minor-1 可选一腿），
产线改动 ≤10 行。

## 5. VALIDATION 收口（M7 站）

### 5.1 现状盘点

| phase | 收口形态 | 正本 |
|---|---|---|
| M7-0 立项 | charter 五正本落账（无 VALIDATION 形态；验收 = 五正本一致 ✓） | ROADMAP :104 |
| M7-1 | `M7-1-VALIDATION.md` status: validated + nyquist true（定罪批形态） | `phases/m7-1-shell/` :4-5 |
| M7-2 | `M7-2-VALIDATION.md` validated（双路 + 三路全套同值 3877） | `phases/m7-2-mcp-o1/` :4-5 |
| M7-3 | `M7-3-VALIDATION.md` validated（3905） | `phases/m7-3-mcp-o2o3/` :4 |
| M7-4 | `M7-4-VALIDATION.md` validated（3925） | `phases/m7-4-mcp-o4/` :4-5 |
| M7-5 | **无独立 VALIDATION.md**（流程偏差在案）——双 ACCEPTANCE + SUMMARY 即收口载体 | `M7-5-SUMMARY.md` §Deviations |

### 5.2 建议形态：单站级文档，不逐 phase 补

**单站级** `phases/m7-6-station-close/M7-VALIDATION.md`（对齐
`M7-1-VALIDATION.md` 体例，front-matter `phase: M7 站`）。理由：m7-5 补写
独立 VALIDATION = 事后追认失真（双 ACCEPTANCE + SUMMARY 已是**更重**的收
口载体）；站级文档显式登记载体偏差为制度事实即可。含 M7-5 签核 = 站级文
档 §M7-5 节给 signed 语义（前置条件 = major-1 修复后重跑 e2e 执法腿——
「执法语义完整后一并过目」，M7-5-SUMMARY §Leftovers 6）。

### 5.3 清单骨架

1. **站终验全套轮**：`caffeinate -dis Scripts/test-direct.sh --all` 判定式
   兑现（预期 `TOTAL|3950+ΔN/35/0|`，ΔN 带 plan 期定——本批预估 +8..13，
   见 §6；零 MEMFAIL 七 bundle 8G 门内）。
2. **五 phase 收口矩阵**：m7-1..m7-4 VALIDATION 指针 + m7-5 双 ACCEPTANCE
   + SUMMARY 指针（载体偏差注明）。
3. **红线族复检**：11 项（M7-5 同表——零新 SPM / .metal 零 diff /
   McpToolRegistry 面〔本批触 setControlAdmit 装配 = M7-5 红线面的
   DECISIONS 显式申报点〕/ controller 面 / 封存面 / xcstrings 尾块 /
   UserDefaults 新键〔UQ-L1 tooltip 键申报〕/ runModal 禁形 / 插值禁形 /
   Project.swift 登记 / tuist generate 末位）。
4. **SC 表翻账**：ROADMAP §Milestone 7 SC 门判定式兑现——skill 机检 ✓ /
   UQ-A1 等值 ✓ / UQ-L1 走查 ✓ / 全套数字门 ✓；REQUIREMENTS 翻账
   （SKILLS-01 / UQ-A1 / UQ-L1 → Delivered 行）。
5. **制度偏离登记**：①omp→双 zcode 验收路由（M7-2 VALIDATION :85 先例在
   案，站级汇总一句）②m7-5 无独立 VALIDATION 载体（承 §5.1）。
6. **挂账清算面**：N2-2 → 本批文档句收口；S-2 让渡 Export 波维持；
   obs-A C12 AX 旗标（OQ-M7-6-10）；FIX2③ 第五波维持注记；union 改动权
   用讫归还（M8 禁并行注记移交下一波）。

## 6. plan 切分建议

**推荐 = 单 plan M7-6-01（六项全入）**。理由：

1. **union 串行纪律 → 并行度结构性为零**：SKILLS-01 机检腿触
   McpFinalSnapshotTests 域（活注册表渲染门）——本波持快照改动权，禁并行
   派发；拆多 plan 无并行收益。
2. **总量小**：三缺陷产线 ≤10 行 + UQ-A1 一函数臂 + UQ-L1 一组件增强 +
   SKILLS-01 纯文档 + VALIDATION 纯文档——编排开销 > 收益。
3. **收官语义天然串行**：VALIDATION 依赖其余五项全落。

任务序建议（单 plan 内）：T1 三缺陷（major-1 → minor-1 → obs-3，同域
MCP/coordinator 文件连做，伴测试腿）→ T2 UQ-A1（Core 消费臂 + 等值测试）→
T3 UQ-L1（LightamerSlider + 纯函数 + 测试 + tooltip 键）→ T4 SKILLS-01
（skills/ 目录 + 机检测试 + README 句 + N2-2 文档句）→ T5 全套对账 + 红线
族 → T6 站级 VALIDATION + 台账翻账（ROADMAP/REQUIREMENTS/TODO/GOAL-STATE/
STATE 同批）。

**ΔN 预估带**：三缺陷测试 +3..5 / UQ-A1 +2 / UQ-L1 +2..4 / SKILLS-01 机检
+1..2 → **+8..13**，3950 → 3958..3963（预期带 plan 期按任务分解细化）。

备选（双 plan：A = 三缺陷+两 UQ 码批 / B = SKILLS-01+VALIDATION）不推荐——
B 依赖 A 收官，且 A 的 union 权同样阻断真并行；如用户坚持分批，按 A→B 串
行执行，编排面无差。

## 7. OQ-M7-6-1..10（每条带推荐，裁决链归 planner 落 CONTEXT，晨审可推翻）

1. **OQ-M7-6-1 skills 仓形态**（仓内 vs 独立仓）：推荐 = **仓内
   `skills/`**。理由 = 我方无 CLI/终端用户分发面（Alcedo 独立仓动机不复存
   在），机检测试同仓最简；独立仓挂账至需求出现。
2. **OQ-M7-6-2 skill 语言**（en 单语 vs zh/en 双语）：推荐 = **en 单语**。
   理由 = 消费者外部 LLM agent、Alcedo 同款英文、双倍维护无收益；
   zh-audit 豁免面 DECISIONS 申报。
3. **OQ-M7-6-3 reference 机检形态**（测试即门 vs 独立生成脚本）：推荐 =
   **测试即门**（活注册表渲染 vs 仓内文件逐字节比对）。理由 = 漂移随全套
   即红、零脚本维护；脚本形态留 v2 若 reference 需独立发布。
4. **OQ-M7-6-4 UQ-A1 域外对处置**（换 ICC 全量 vs legal 对换+域外回落）：
   推荐 = **legal 对换 ICC v4、域外对保留 calibrated 回落**。理由 = 预览
   显示义务（gamma18 等域外对仍须上屏）；扩导出 legal 表 = 改 export 语义
   面，越 UQ-A1 scope。
5. **OQ-M7-6-5 UQ-L1 scrub 范围**（只 LightamerSlider vs 全部自有 row）：
   推荐 = **只落 LightamerSlider**（177 调用点全量受益）；MonochromePanel
   自有 row 登记观察项不顺手改。
6. **OQ-M7-6-6 track 双击 wrinkle**（登记 vs 拦截修复）：推荐 = **登记不
   动**。理由 = SwiftUI Slider track 点击跳值是框架行为，拦截成本高且
   lightcraft 修法（自绘 widget）不可平移；tooltip/文档注记即可。
7. **OQ-M7-6-7 major-1 修法两案**：(a) 宿主透传参 vs (b) box 暴露
   registry：推荐 = **(a)**。理由 = writerCheck 装配同构、无 toggle 时序缝、
   additive 零回归；(b) handle 不回传 + 竞态两缝需新面。
8. **OQ-M7-6-8 站级 VALIDATION 形态**（单站级 vs 逐 phase 补 m7-5）：
   推荐 = **单站级文档，m7-5 不补写**。理由 = 双 ACCEPTANCE + SUMMARY 已是
   更重收口载体，补写 = 事后追认失真；载体偏差显式登记为制度事实。
9. **OQ-M7-6-9 plan 切分**（单 plan vs 双 plan）：推荐 = **单 plan
   M7-6-01**。理由 = union 串行纪律 → 并行度为零 + 六项总量小 + 收官天然
   串行。
10. **OQ-M7-6-10 obs-A C12 AX 旗标处置**（零代码 vs SwiftUI 注记）：
    推荐 = **走查批零代码动作 + 站级 VALIDATION 制度注记一行**（M7-5
    SUMMARY 备选项二的最轻形态——行为门为准、AXEnabled 恒真为框架忠实度
    已知面，不产码）。

## 8. 证据索引（file:line 速查）

- GOAL-STATE 续接点 = `.work/GOAL-STATE.md` :19-21；M7-5-SUMMARY = `phases/m7-5-turn-taking/M7-5-SUMMARY.md`（§Leftovers/§Scope）
- REQUIREMENTS = `.work/gsd/REQUIREMENTS.md` :445-461（TURN Delivered 四行 + SKILLS-01 :452 + UQ 四条 :458-461）
- ROADMAP M7-6 = `.work/gsd/ROADMAP.md` :110
- UPSTREAM-QUEUE = `.work/gsd/research/UPSTREAM-QUEUE.md` :14（A1）/:27（L1）
- survey = `.work/gsd/research/ALCEDO-CLI-AI-SURVEY.md` :131/:203/:273/:303/:312
- registry 面 = `App/Sources/Lightamer/MCP/McpToolRegistry.swift` :304-409（Entry :314 / controlAdmit :335 / setControlAdmit :367 / dispatch :385-408）
- 四宿主 = `App/Sources/Lightamer/MCP/McpServerController.swift` :722/:786/:1035/:1165；裸臂 :482/:497；arbitrated 臂 :603-606；makeHeadlessControlContext :216-221；makeHeadlessSearchState :232-295；union 注释 :832-844
- GUI 装配 = `App/Sources/Lightamer/UI/LightamerApp.swift` :1632-1651
- coordinator = `App/Sources/Lightamer/State/AgentControlCoordinator.swift`（admit :185-201 / acquire :213-268 / 等待循环 :227-240 / stop :288-296）
- UQ-A1 = `App/Sources/Lightamer/UI/EditorMTKView.swift` :732-811（:760 幂近似）+ `LightamerCore/Sources/Export/DrtOutputColorSpace.swift` :53-141（srgbPiecewise :72-77/:89-92；ICC bytes :248-259）+ `App/Sources/Lightamer/State/PipeCoordinator.swift` :646-653
- UQ-L1 = `App/Sources/Lightamer/UI/Inspector/LightamerSlider.swift` :18-81（重置 :72-74 / readout :65-69）；lightcraft 两 commit = `cb8b797c` / `ab64e9a5`
- 快照机检源 = `Tests/LightamerTests/McpFinalSnapshotTests.swift` :49/:115/:205/:230/:253/:270/:401；控制测试 = `Tests/LightamerTests/McpControlToolsetTests.swift` :194/:253/:473
- VALIDATION 体例 = `phases/m7-1-shell/M7-1-VALIDATION.md`（:4-5 front-matter）；omp→双 zcode 先例 = `phases/m7-2-mcp-o1/M7-2-VALIDATION.md` :85
- endpoint schema = `App/Sources/Lightamer/MCP/McpEndpointFile.swift` :61-75
