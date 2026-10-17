# M7-6-01 DECISIONS — 执行期裁定与偏差申报（2026-10-17）

> 执行正本 = `M7-6-01-PLAN.md`（fixer `cae4e825` + 残修 `06112d02`/`beb8937c`）；
> 裁决正本 = `M7-6-CONTEXT.md`（D-M7-6-1..10 全按 RESEARCH §7 推荐，生效值）。
> 本文件 = executor 执行期偏差与等价终形申报，全部行内/正文标记对应，晨审可翻。

## 1. 执行链与 commit 表

| 任务 | commit | 面 |
|---|---|---|
| T1 三缺陷 | `ad003e88` | major-1 四宿主签名批 + box 第七缝 + GUI 装配 + minor-1 两行 + obs-3 快照+复检三行 + 五测试腿 |
| T2 UQ-A1 | `32b592aa` | drtLayerColorSpace SDR 幂臂两段式 + EditorPreviewColorSpaceTests 3 法 + Project.swift/BUNDLE-MAP 各一行 |
| T3 UQ-L1 | `bac0ff76` | LightamerSlider readout scrub + LightamerSliderScrubSession + 3 法 + xcstrings 恰 +1 键尾块纯插入 |
| T4 SKILLS-01 | `4259cfd8` | skills/lightamer-mcp/ 三文件 + SkillsReferenceTests 2 法 + makeUnionRegistry internal 一行 + README 一句链接 |
| T5 对账批 | （本轮） | 全套对账 + 红线族 + zh-audit 双 PASS + MANIFEST + 本文件 + SUMMARY |
| T6 站级收口 | （T6） | M7-VALIDATION.md + 四台账一 AGENTS 翻账 |

## 2. 转写勘正五条承接（plan 头注逐条）

1. **FIX2③ 正义勘正**——承接：本波红线核 = `LibraryProjectController.swift`
   零 diff（第五波维持，`git diff beb8937c..HEAD --name-only` 亲证不在
   清单）；McpServerController.swift 是本波合法修改面，hunk 清单 =
   ①四宿主签名 `admit:` 缺省参四行 ②三宿主函数体 `setControlAdmit`
   安装三行 ③EmbeddedState box 字段 + `startEmbeddedIfPreferenceEnabled`
   box 写入 + `startEmbeddedServer` 读出透传 ④minor-1 裸臂两处
   `agentControl:` 接线——全部 additive/接线形，control/admit 既有面零漂移
   （McpToolRegistry.swift 零 diff 亲证）。
2. **七节正本**——SKILL.md 七节全落（§1 Installation & session start /
   §2 Turn-taking / §3 Tool domains / §4 Error codes / §5 render_preview /
   §6 UI units / §7 Known surface asymmetries），人工抽读对照
   `McpControlToolsetTests` 断言面与 `ControlToolset.swift` 头注逐句核。
3. **plain-await 形**——GUI admit 闭包 =
   `{ [agentControl] name in try await agentControl.admit(toolName: name) }`
   +「the plain await IS the MainActor hop」同款注释（acquire provider
   :1634-1637 先例形）。
4. **internal 前提**——`makeUnionRegistry` 实测 `private func`（:277），
   本批恰一行 private→internal 提升（union 文件本波唯一 diff，
   `git diff` 亲证；持权行使申报点，见 §4）。
5. **schema 全文从严**——tools.md 渲染 `inputSchemaJSON` verbatim 全文
   （非摘要）。**附加偏差见 §6**（description 列省略——与勘正⑤无冲突，
   schema 全文仍 verbatim；description 是列级省略非摘要化）。

## 3. obs-3 等价终形申报（plan 允许的 DECISIONS 申报路径）

- **快照行落点**：`let stoppedAtEntry = stoppedByUser` 落在
  `alreadyHeldBySelf` 计算之后、`if !alreadyHeldBySelf` 块之前——
  MainActor-isolated 函数体在函数入口到该行之间无挂起点（入口 busy 检查
  与 alreadyHeldBySelf 均为同步计算），快照值 ≡ 函数入口值。
- **复检两行落点**：两复检落在 `if !alreadyHeldBySelf` 块内（循环退出后、
  块闭合前），而非块外——语义等价性证明：alreadyHeldBySelf 路径下
  ①busy 复检恒 false（held ∧ holderName == holderName）②revoked 复检恒
  false（stop() 恒清 held，「stoppedByUser ∧ held」不可达）——块内放置
  使复检对 already-held 路径结构性不可触，plan 的「循环退出后、success
  路径前」字面满足。两 throw 拼写与循环内 revoked 臂（:228-231）/入口
  busy 臂（:215-217）逐字同构。
- **测试交错终形**（plan 风险节预告的 DECISIONS 申报）：注入 provider 内
  串行 poll 计数器（`PollTriggerBox`）+ 触发轮内联执行交错动作（revoked
  变体 = 轮 3 内 `MainActor.run { coordinator.stop() }` 后返 false；
  busy 变体 = 轮 3 内联跑竞争者 acquire 后返 false，嵌套轮经 armed 旗标
  返 false）——loop 经条件翻转退出、体观察不到翻转 = final-window 形；
  零真等 250ms poll（pollInterval 注入 20ms）。

## 4. union 持权行使申报

`McpFinalSnapshotTests.swift` 恰一行 `private func makeUnionRegistry` →
`func makeUnionRegistry`（internal，同测试 target 可见即够——
SkillsReferenceTests 复用活注册表）。union 内容/断言面零 diff（32 基线 +
五钉 23 维持，App 域既有 union 断言全绿亲证）。**窗口用讫——归还 M8**
（T6 VALIDATION §挂账清算面登记移交注记）。备查：SkillsReferenceTests
另以自身 `domainMembership()` 逐域建 registry 取域成员（不复制域清单）。

## 5. T1 偏差与让渡申报

- **腿②合并让渡**（plan 明示可选路径）：「无头臂端到端 nil 恒放行」与
  既有 `McpControlToolsetTests.testHeadlessAdmitNilWriteToolsAnswer
  StraightIntoHandler`（stub requiresControl 工具无 admit 直通 handler）
  同语义 = 合并让渡，不新增法。T1 实落 **5 腿**（带 4..6 内）：真宿主
  controlNotHeld 1 + minor-1 1 + obs-3 两变体 2 + resume 不断裂负腿 1。
- **minor-1 测试腿等价终形**（deviation）：plan 判据「裸臂直调
  `makeHeadlessSearchState(mode: .stdio)` → provider 非 nil」与修法本身
  结构性不一致——修法 = runHeadless 两个**调用点**接线，签名缺省仍 nil，
  无参直调恒得 nil（除非改签名缺省 = plan 未处方、属第三方案禁自裁）。
  等价终形 = ①产线同拼写构造断言 provider 值 ≡ headlessConstant（stdio
  + http 两臂）②源级接线扫描（runHeadless 函数体切片含
  `agentControl: { McpControlState.headlessConstant }` 且不含裸
  `makeHeadlessSearchState(mode: mode)` 调用——源扫描先例形）。
- **obs-3 resume 负腿**独立落法（review B1）=
  `testAcquireAfterStopStillResumesForSameHolder`：acquire → stop →
  同 holder re-acquire → 成功 + taskId 复用——正是拦住「无条件
  stoppedByUser 拒绝」病灶的那条腿。

## 6. T2 偏差申报

- **legal 8 对清点**（review m1 对账）：rec709×{bt1886,gamma22,
  srgbPiecewise} + p3d65×{gamma22,srgbPiecewise} + p3d60×gamma26 +
  p3dci×gamma26 + xyz×gamma26 = 8，与 Core legal 表亲核一致（gamma18 不在
  任一 legal 集、rec2020 仅 HDR 两档）。**禁扩表红线未触**（域外对
  rec709×gamma18 / p3d65×bt1886 typed 拒保持）。
- **等值测试实现形**（plan 明示可 DECISIONS 申报的收敛）：同实例断言
  （`preview === export`）+ ICC bytes 逐字节同取代 ramp 双解码采样腿——
  同实例蕴含等值。**替代增腿**：srgbPiecewise 对的真分段表行为断言
  （`CGColor.converted` 走真 ColorSync ICC 变换——below-knee 码点落线性段
  ≈ code/12.92，与退役 2.2 幂面 ~4.9× 分离；64 点 ramp 收敛为 4 点判别
  ramp）——该腿恰好承载 plan 的「真分段表形（非 2.2 幂）负断言」判据。
  实现 **3 法**（legal 恒等 1 + 分段行为 1 + 域外回落 1），plan 点估 2、
  带未单列——总账见 SUMMARY（全波恰 +13 落带内）。
- **M4-1-01 KD-8 显示侧偏离消解**：本修复后 legal 对不再可达 2.2 幂近似
  臂（回落臂仅域外对可达）——KD-8 偏离收口申报在案。
- **受限修改面核**：EditorMTKView 仅 SDR 幂臂段 + 头注/KD-8 注记更新；
  HDR 臂 / linear 臂 / drtSurfaceSpec / PipeCoordinator :646-653 零 diff
  亲证。

## 7. T3 偏差申报

- **Shift 通道换锚**（deviation）：plan 形 `value.modifiers.contains(.shift)`
  在本 SDK **编译不可达**——`DragGesture.Value` 无 `modifiers` 成员
  （swiftinterface 亲核：仅 SpatialEventCollection.Event 与
  KeyboardShortcut 携带 modifiers；无 `EnvironmentValues.modifierKeys`）。
  等价终形 = macOS 15+ SwiftUI 原生视图修饰符 `onModifierKeysChanged`
  追踪 → `@State shiftActive`，gesture 闭包读该状态。行为语义不变
  （拖拽中按 Shift 即 1/10 速）。
- **trackWidth 测量终形**（plan 明示 DECISIONS 申报点）= 整行 HStack 宽
  经 `.onGeometryChange(for:of:action:)` 就地测量（组件宽近似——框架持有
  Slider 内部 track 几何不可达）。
- **拖离取消让渡**（review m5 显式申报面）：lightcraft「拖离取消不留
  残值」不可平移——SwiftUI DragGesture onEnded = 释放点（非离域点）、
  onChanged per-tick 已落 live 值；让渡 = scrub 中拖离不取消、残值留驻。
  MANIFEST A3 观察行登记（预期行为非缺陷）。
- **xcstrings 恰 +1 键**：`slider_scrub_hint` 尾块纯插入亲证（+10/-0，
  JSON valid；历史键字节与顺序零触碰）；zh-audit source keys
  1708→1709 恰 +1 对账。
- 其余零触亲证：MonochromePanelView.swift 零 diff（OQ-M7-6-5）；
  `EditorState.previewDenoiseBypass` 所在文件（EditorState.swift）零 diff；
  AX identifier 三处零改；onReset 双击路径零改；
  `DragGesture(minimumDistance: 3)` 全组件恰一处。

## 8. T4 偏差申报

- **tools.md description 列省略**（deviation，plan 内部两判据冲突的
  裁定）：plan 同时要求 ①tools.md 含 description 列（活注册表渲染）
  ②en 单语机检 `grep -rn "[一-鿿]" skills/` 零命中。亲核事实：活注册表
  的 tool-level description = **zh**（注册点 defaultValue 即 zh 文案，
  xcstrings `mcp_tool_desc_*` 仅 zh 列无 en 列——`McpFinalSnapshotTests
  .testToolDescriptionsCarryZhCatalogKeys` 的头注「en defaultValue」为
  14-2 时代遗留措辞，与现文案语言不符）。两判据不可同时满足；裁定 =
  description 列省略，schema verbatim 全文保留（其字段级 description
  为英文 = 参数语义的 agent 可见面），域边界语义由 SKILL.md §3 英文
  承载。**不发明第三方案**（如 32 条 en 翻译自创 = 无维护单源的漂移面 +
  越内容授权）。晨审若翻（改 en 列入 xcstrings）→ 渲染器加回 description
  列即可，门不变。
- **tools.md 生成通道**（plan 明示 DECISIONS 申报点）：临时脚手架测试
  （env 门 `LIGHTAMER_WRITE_TOOLS_REF=1` 调 internal 渲染函数写盘）跑一次
  产文件，**提交前移除**——提交内无脚手架代码，渲染函数 = 测试文件
  internal static（gate 本体复用）。此后测试即门恒锁。
- **零 taste 自检**：SKILL.md 全部祈使句内容 = 服务端强制协议语义
  （turn-taking 门、错误码恢复动作、schema 域），无主观工作流规则段；
  §1 显式指认 taste 载体 = launcher `{{PROMPT}}` 模板。
- **零 Alcedo 文案自检**：七节 + references 全部自写 en；Alcedo 面
  （本地仓 `.agents/skills/` + alcedo-skills）只对表形态（front-matter
  name/description 形、单 skill 多 reference 结构），无形似句。
- **N2-2 收口**：SKILL.md §7 如实句（headless liveState 携
  `project.heldByOther`，GUI 臂仅 path/readOnly）——M7-2 挂账文档句
  路由兑现（T6 VALIDATION §挂账清算面翻账）。

## 9. 登记申报对账（CONTEXT「登记申报」四件）

1. 制度偏离两件（omp→双 zcode / m7-5 无独立 VALIDATION 载体）→
   T6 VALIDATION §制度偏离登记（本波执行路由 = 双 zcode subagent 制内，
   无新偏离）。
2. xcstrings 恰 +1 键 → 兑现（§7）。
3. UserDefaults 零新键 → 兑现（红线族亲跑零命中）。
4. union 持权行使 = internal 一行 → 兑现（§4）。

## 10. 全套对账终值

- 定向轮：App 域 `917/4/0`（peakRSS 2832MB）——基线 904 + ΔN 13 精确。
- 全套 `--all`：`TOTAL|3963/35/0|` exit 0，零 MEMFAIL，七 bundle 全 8G
  门内（详见 SUMMARY §记账表——IOP 687+0 等六 bundle 与 M7-5 终态逐值
  一致，仅 App +13）。
- ΔN 记账：T1 +5（带 4..6 内）+ T2 +3（点估 +1，带内吸收）+ T3 +3 +
  T4 +2 = **+13**，3950 → **3963**（预期点 +13 精确命中，带 3959..3964
  内）。
- zh-audit：`--check` PASS（source keys 1708→1709 恰 +1 / 1957 catalog
  keys）+ `--self-test` PASS。
- 红线族 11 项全 PASS（SUMMARY §红线族表）。
